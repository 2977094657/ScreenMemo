import 'dart:convert';

/// Best-effort extractor for a JSON string field from a raw JSON fragment.
///
/// This intentionally does not require the whole JSON object to be valid. It is
/// used by timeline list rows where the DB only returns a small window around
/// `overall_summary` to avoid Android CursorWindow row-size failures.
String extractJsonStringFieldFromRaw(String? raw, String key) {
  final String s = (raw ?? '').trim();
  if (s.isEmpty || s.toLowerCase() == 'null') return '';

  final _KeyHit? hit = _findKeyHit(s, key);
  if (hit == null) return '';

  int idx = s.indexOf(':', hit.afterKey);
  if (idx < 0) return '';
  idx++;

  while (idx < s.length && _isWhitespace(s.codeUnitAt(idx))) {
    idx++;
  }
  if (idx >= s.length) return '';

  final bool escapedQuoteDelimiter =
      s.codeUnitAt(idx) == 92 /* \ */ &&
      idx + 1 < s.length &&
      s.codeUnitAt(idx + 1) == 34 /* " */;
  final bool normalQuoteDelimiter = s.codeUnitAt(idx) == 34 /* " */;
  if (!escapedQuoteDelimiter && !normalQuoteDelimiter) return '';

  final int valueStart = idx + (escapedQuoteDelimiter ? 2 : 1);
  final int? valueEnd = _findJsonStringValueEnd(
    s,
    valueStart,
    escapedQuoteDelimiter: escapedQuoteDelimiter,
  );
  final String captured = s
      .substring(valueStart, valueEnd ?? s.length)
      .trimRight();
  if (captured.isEmpty) return '';

  return _decodeJsonStringContentBestEffort(captured).trim();
}

String extractOverallSummaryFromRaw(String? raw) {
  return extractJsonStringFieldFromRaw(raw, 'overall_summary');
}

class _KeyHit {
  const _KeyHit({required this.index, required this.afterKey});

  final int index;
  final int afterKey;
}

_KeyHit? _findKeyHit(String s, String key) {
  final String normalNeedle = '"$key"';
  final String escapedNeedle =
      '${String.fromCharCode(92)}"$key${String.fromCharCode(92)}"';

  final int normal = s.indexOf(normalNeedle);
  final int escaped = s.indexOf(escapedNeedle);
  if (normal < 0 && escaped < 0) return null;

  if (normal >= 0 && (escaped < 0 || normal < escaped)) {
    return _KeyHit(index: normal, afterKey: normal + normalNeedle.length);
  }
  return _KeyHit(index: escaped, afterKey: escaped + escapedNeedle.length);
}

int? _findJsonStringValueEnd(
  String s,
  int valueStart, {
  required bool escapedQuoteDelimiter,
}) {
  bool escaped = false;
  for (int i = valueStart; i < s.length; i++) {
    final int cu = s.codeUnitAt(i);
    if (escaped) {
      escaped = false;
      continue;
    }

    if (cu == 92 /* \ */ ) {
      if (escapedQuoteDelimiter &&
          i + 1 < s.length &&
          s.codeUnitAt(i + 1) == 34 /* " */ &&
          _looksLikeStringTerminator(s, i + 2)) {
        return i;
      }
      escaped = true;
      continue;
    }

    if (!escapedQuoteDelimiter &&
        cu == 34 /* " */ &&
        _looksLikeStringTerminator(s, i + 1)) {
      return i;
    }
  }
  return null;
}

bool _looksLikeStringTerminator(String s, int start) {
  int i = start;
  while (i < s.length && _isWhitespace(s.codeUnitAt(i))) {
    i++;
  }
  if (i >= s.length) return true;
  final int cu = s.codeUnitAt(i);
  return cu == 44 /* , */ ||
      cu == 125 /* } */ ||
      cu == 93 /* ] */ ||
      cu == 34 /* " */;
}

bool _isWhitespace(int cu) {
  return cu == 32 || cu == 9 || cu == 10 || cu == 13;
}

String _decodeJsonStringContentBestEffort(String captured) {
  try {
    final dynamic decoded = jsonDecode('"$captured"');
    if (decoded is String) return decoded;
  } catch (_) {
    // Fall through to a tolerant decoder. This covers invalid-but-common model
    // output such as unescaped quotes inside overall_summary.
  }
  return _manualJsonStringUnescape(captured);
}

String _manualJsonStringUnescape(String input) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < input.length; i++) {
    final int cu = input.codeUnitAt(i);
    if (cu != 92 /* \ */ || i + 1 >= input.length) {
      out.writeCharCode(cu);
      continue;
    }

    final int next = input.codeUnitAt(++i);
    switch (next) {
      case 34: // "
        out.write('"');
        break;
      case 92: // \
        out.write(r'\');
        break;
      case 47: // /
        out.write('/');
        break;
      case 98: // b
        out.write('\b');
        break;
      case 102: // f
        out.write('\f');
        break;
      case 110: // n
        out.write('\n');
        break;
      case 114: // r
        out.write('\r');
        break;
      case 116: // t
        out.write('\t');
        break;
      case 117: // u
        if (i + 4 < input.length) {
          final String hex = input.substring(i + 1, i + 5);
          final int? value = int.tryParse(hex, radix: 16);
          if (value != null) {
            out.writeCharCode(value);
            i += 4;
            break;
          }
        }
        out.write(r'\u');
        break;
      default:
        out.writeCharCode(next);
        break;
    }
  }
  return out.toString();
}
