import 'dart:convert';
import 'dart:io';

class _ProjectContext {
  _ProjectContext(this.rootDir);

  final Directory rootDir;

  String get rootPath => rootDir.absolute.path;

  File file(String relativePath) =>
      File('${rootDir.absolute.path}${Platform.pathSeparator}$relativePath');

  Directory dir(String relativePath) =>
      Directory('${rootDir.absolute.path}${Platform.pathSeparator}$relativePath');

  String toRelativePath(String path) {
    final String root = rootDir.absolute.path.replaceAll('\\', '/');
    String p = path.replaceAll('\\', '/');
    if (p.startsWith(root)) {
      p = p.substring(root.length);
      if (p.startsWith('/')) p = p.substring(1);
    }
    return p;
  }
}

class _AuditResult {
  _AuditResult();

  final List<String> hardFailures = [];
  final List<String> softFailures = [];

  bool get hasFailures => hardFailures.isNotEmpty || softFailures.isNotEmpty;
}

class _UiLiteralOccurrence {
  int count = 0;
  final Set<int> exampleLines = <int>{};

  void add(int lineNumber) {
    count += 1;
    if (exampleLines.length < 3) {
      exampleLines.add(lineNumber);
    }
  }
}

Future<int> runI18nAudit(
  List<String> args, {
  IOSink? out,
  IOSink? err,
}) async {
  out ??= stdout;
  err ??= stderr;

  final bool updateBaseline = args.contains('--update-baseline');
  final bool report = args.contains('--report');
  final bool check = args.contains('--check') || !updateBaseline;

  final _ProjectContext? ctx = _findProjectRoot(out: out, err: err);
  if (ctx == null) {
    err.writeln('i18n-audit: failed to locate project root (pubspec.yaml).');
    return 2;
  }

  final _AuditResult result = _AuditResult();

  result.hardFailures.addAll(_checkArbConsistency(ctx));
  result.hardFailures.addAll(_checkIosLocalization(ctx));
  result.hardFailures.addAll(_checkAndroidLocalization(ctx));

  final Map<String, Map<String, _UiLiteralOccurrence>> uiScan =
      _scanUiStringLiterals(ctx);
  final Map<String, Map<String, int>> uiCounts = {
    for (final MapEntry<String, Map<String, _UiLiteralOccurrence>> e
        in uiScan.entries)
      e.key: {
        for (final MapEntry<String, _UiLiteralOccurrence> inner in e.value.entries)
          inner.key: inner.value.count,
      },
  };

  final File baselineFile = ctx.file('tool/i18n_audit_baseline.json');

  if (check) {
    final _Baseline? baseline = _readBaseline(baselineFile);
    if (baseline == null) {
      result.softFailures.add(
        'UI baseline missing: ${ctx.toRelativePath(baselineFile.path)}. Run: dart run tool/i18n_audit.dart --update-baseline',
      );
    } else {
      result.softFailures.addAll(
        _compareAgainstBaseline(
          current: uiScan,
          baseline: baseline.uiStringLiterals,
        ),
      );
    }
  }

  if (updateBaseline) {
    if (result.hardFailures.isNotEmpty) {
      err.writeln('i18n-audit: hard failures present; baseline not updated.');
    } else {
      final _Baseline newBaseline = _Baseline(
        version: 1,
        generatedAt: DateTime.now().toUtc(),
        uiStringLiterals: uiCounts,
      );
      _writeBaseline(baselineFile, newBaseline);
      out.writeln(
        'i18n-audit: baseline updated: ${ctx.toRelativePath(baselineFile.path)}',
      );
    }
  }

  if (report || result.hasFailures) {
    _printReport(
      ctx: ctx,
      result: result,
      uiScan: uiScan,
      baselinePath: ctx.toRelativePath(baselineFile.path),
      out: out,
      err: err,
    );
  }

  return result.hasFailures ? 1 : 0;
}

Future<void> main(List<String> args) async {
  final int code = await runI18nAudit(args);
  if (code != 0) exit(code);
}

_ProjectContext? _findProjectRoot({required IOSink out, required IOSink err}) {
  Directory dir = Directory.current.absolute;
  while (true) {
    final File pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
    if (pubspec.existsSync()) {
      return _ProjectContext(dir);
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) {
      return null;
    }
    dir = parent;
  }
}

String _readTextFile(File file) {
  final List<int> bytes = file.readAsBytesSync();
  return utf8.decode(bytes, allowMalformed: true);
}

Map<String, dynamic> _readJsonFile(File file) {
  final String text = _readTextFile(file);
  final Object? decoded = jsonDecode(text);
  if (decoded is Map<String, dynamic>) return decoded;
  throw FormatException('Expected JSON object in ${file.path}');
}

Map<String, String> _readSimpleYamlMap(File file) {
  final String text = _readTextFile(file);
  final Map<String, String> out = {};
  for (final String rawLine in const LineSplitter().convert(text)) {
    final String line = rawLine.trimRight();
    final String trimmed = line.trimLeft();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('#')) continue;
    final RegExpMatch? m = RegExp(r'^([A-Za-z0-9_-]+)\s*:\s*(.*)$').firstMatch(trimmed);
    if (m == null) continue;
    final String key = m.group(1) ?? '';
    final String value = (m.group(2) ?? '').trim();
    if (value.isEmpty) continue;
    out[key] = value;
  }
  return out;
}

List<String> _checkArbConsistency(_ProjectContext ctx) {
  final List<String> issues = [];

  final File l10nYaml = ctx.file('l10n.yaml');
  if (!l10nYaml.existsSync()) {
    issues.add('Missing l10n.yaml');
    return issues;
  }

  final Map<String, String> l10n = _readSimpleYamlMap(l10nYaml);
  final String arbDir = l10n['arb-dir'] ?? 'lib/l10n';
  final String templateFileName = l10n['template-arb-file'] ?? 'app_en.arb';

  final Directory dir = ctx.dir(arbDir);
  if (!dir.existsSync()) {
    issues.add('ARB dir not found: $arbDir');
    return issues;
  }

  final File template = File('${dir.path}${Platform.pathSeparator}$templateFileName');
  if (!template.existsSync()) {
    issues.add('Template ARB not found: ${ctx.toRelativePath(template.path)}');
    return issues;
  }

  Set<String> loadKeys(File f) {
    final Map<String, dynamic> json = _readJsonFile(f);
    return json.keys.where((k) => !k.startsWith('@')).toSet();
  }

  final Set<String> templateKeys = loadKeys(template);

  final List<File> arbs = dir
      .listSync(followLinks: false)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.arb'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final File arb in arbs) {
    if (arb.path == template.path) continue;
    final Set<String> keys = loadKeys(arb);
    final List<String> missing = (templateKeys.difference(keys).toList()..sort());
    final List<String> extra = (keys.difference(templateKeys).toList()..sort());
    if (missing.isNotEmpty) {
      issues.add(
        'ARB missing keys in ${ctx.toRelativePath(arb.path)}: ${missing.join(', ')}',
      );
    }
    if (extra.isNotEmpty) {
      issues.add(
        'ARB extra keys in ${ctx.toRelativePath(arb.path)} (not in template $templateFileName): ${extra.join(', ')}',
      );
    }
  }

  return issues;
}

List<String> _checkIosLocalization(_ProjectContext ctx) {
  final List<String> issues = [];

  final File plist = ctx.file('ios/Runner/Info.plist');
  if (!plist.existsSync()) {
    issues.add('Missing iOS Info.plist: ios/Runner/Info.plist');
    return issues;
  }

  final String plistText = _readTextFile(plist);
  final RegExpMatch? m = RegExp(
    r'<key>\s*CFBundleLocalizations\s*</key>\s*<array>([\s\S]*?)</array>',
    multiLine: true,
  ).firstMatch(plistText);
  if (m == null) {
    issues.add('Missing CFBundleLocalizations in ios/Runner/Info.plist');
    return issues;
  }

  final String arrayBody = m.group(1) ?? '';
  final Iterable<RegExpMatch> items =
      RegExp(r'<string>\s*([^<]+?)\s*</string>').allMatches(arrayBody);
  final Set<String> locales = items.map((e) => (e.group(1) ?? '').trim()).toSet();

  const List<String> required = ['en', 'zh-Hans', 'ja', 'ko'];
  for (final String loc in required) {
    if (!locales.contains(loc)) {
      issues.add('iOS missing CFBundleLocalizations entry: $loc');
    }
  }

  final Map<String, String> requiredInfoPlistStrings = {
    'en': 'ios/Runner/en.lproj/InfoPlist.strings',
    'zh-Hans': 'ios/Runner/zh-Hans.lproj/InfoPlist.strings',
    'ja': 'ios/Runner/ja.lproj/InfoPlist.strings',
    'ko': 'ios/Runner/ko.lproj/InfoPlist.strings',
  };

  for (final MapEntry<String, String> e in requiredInfoPlistStrings.entries) {
    final File f = ctx.file(e.value);
    if (!f.existsSync()) {
      issues.add('iOS missing ${e.key} InfoPlist.strings: ${e.value}');
      continue;
    }
    final String text = _readTextFile(f);
    if (!RegExp(r'CFBundleDisplayName"\s*=\s*".*"\s*;').hasMatch(text)) {
      issues.add('iOS missing CFBundleDisplayName in: ${e.value}');
    }
  }

  return issues;
}

Set<String> _readAndroidStringKeys(_ProjectContext ctx, String relativePath) {
  final File file = ctx.file(relativePath);
  if (!file.existsSync()) {
    throw FileSystemException('Missing Android strings file', relativePath);
  }
  final String text = _readTextFile(file);
  final Iterable<RegExpMatch> matches =
      RegExp(r'<string\s+name="([^"]+)"').allMatches(text);
  return matches.map((m) => m.group(1) ?? '').where((s) => s.isNotEmpty).toSet();
}

List<String> _checkAndroidLocalization(_ProjectContext ctx) {
  final List<String> issues = [];

  final File manifest = ctx.file('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    issues.add('Missing AndroidManifest.xml: android/app/src/main/AndroidManifest.xml');
    return issues;
  }

  final String manifestText = _readTextFile(manifest);
  final RegExpMatch? propMatch = RegExp(
    r'android:name="android\.app\.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"[\s\S]*?android:value="([^"]+)"',
    multiLine: true,
  ).firstMatch(manifestText);
  if (propMatch == null) {
    issues.add(
      'AndroidManifest missing PROPERTY_SPECIAL_USE_FGS_SUBTYPE property tag',
    );
  } else {
    final String value = (propMatch.group(1) ?? '').trim();
    if (value != '@string/fgs_special_use_subtype') {
      issues.add(
        'AndroidManifest PROPERTY_SPECIAL_USE_FGS_SUBTYPE must use @string/fgs_special_use_subtype (found: $value)',
      );
    }
  }

  const String keyAccessibility = 'accessibility_service_description';
  const String keyFgsSubtype = 'fgs_special_use_subtype';

  void requireKeys(String path, Set<String> keys, List<String> requiredKeys) {
    for (final String k in requiredKeys) {
      if (!keys.contains(k)) {
        issues.add('Android missing <$k> in $path');
      }
    }
  }

  try {
    final Set<String> base =
        _readAndroidStringKeys(ctx, 'android/app/src/main/res/values/strings.xml');
    requireKeys(
      'android/app/src/main/res/values/strings.xml',
      base,
      const [keyAccessibility, keyFgsSubtype],
    );
  } catch (e) {
    issues.add(e.toString());
  }

  for (final String loc in const ['en', 'ja', 'ko']) {
    final String path = 'android/app/src/main/res/values-$loc/strings.xml';
    try {
      final Set<String> keys = _readAndroidStringKeys(ctx, path);
      requireKeys(path, keys, const [keyAccessibility, keyFgsSubtype]);
    } catch (e) {
      issues.add(e.toString());
    }
  }

  return issues;
}

String _stripLineCommentOutsideStrings(String line) {
  int i = 0;
  while (i < line.length) {
    final String ch = line[i];
    if (ch == "'" || ch == '"') {
      i = _skipDartStringLiteral(line, i);
      continue;
    }
    if (ch == '/' && i + 1 < line.length && line[i + 1] == '/') {
      return line.substring(0, i);
    }
    i += 1;
  }
  return line;
}

String _stripStringsAndLineComment(String line) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < line.length) {
    final String ch = line[i];
    if (ch == "'" || ch == '"') {
      final int next = _skipDartStringLiteral(line, i);
      out.write(' ');
      i = next;
      continue;
    }
    if (ch == '/' && i + 1 < line.length && line[i + 1] == '/') {
      break;
    }
    out.write(ch);
    i += 1;
  }
  return out.toString();
}

List<String> _extractStringLiteralsFromLine(String line) {
  final List<String> out = [];
  int i = 0;
  while (i < line.length) {
    final String ch = line[i];
    if (ch == "'" || ch == '"') {
      final String quote = ch;
      final bool triple =
          i + 2 < line.length && line[i + 1] == quote && line[i + 2] == quote;
      final bool isRaw = _isRawStringQuote(line, i);
      final int? end = _findDartStringEnd(
        line,
        startQuoteIndex: i,
        quote: quote,
        triple: triple,
        raw: isRaw,
      );
      if (end == null) return out;

      if (triple) {
        out.add(line.substring(i + 3, end));
        i = end + 3;
      } else {
        out.add(line.substring(i + 1, end));
        i = end + 1;
      }
      continue;
    }

    if (ch == '/' && i + 1 < line.length && line[i + 1] == '/') {
      return out;
    }

    i += 1;
  }
  return out;
}

bool _isIdentChar(String ch) {
  if (ch.isEmpty) return false;
  final int c = ch.codeUnitAt(0);
  return (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      c == 0x5F; // _
}

bool _isIdentStartChar(String ch) {
  if (ch.isEmpty) return false;
  final int c = ch.codeUnitAt(0);
  return (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      c == 0x5F; // _
}

bool _isRawStringQuote(String line, int quoteIndex) {
  return quoteIndex > 0 &&
      line[quoteIndex - 1] == 'r' &&
      (quoteIndex < 2 || !_isIdentChar(line[quoteIndex - 2]));
}

int _skipDartStringLiteral(String line, int startQuoteIndex) {
  final String quote = line[startQuoteIndex];
  final bool triple = startQuoteIndex + 2 < line.length &&
      line[startQuoteIndex + 1] == quote &&
      line[startQuoteIndex + 2] == quote;
  final bool raw = _isRawStringQuote(line, startQuoteIndex);

  final int? end = _findDartStringEnd(
    line,
    startQuoteIndex: startQuoteIndex,
    quote: quote,
    triple: triple,
    raw: raw,
  );
  if (end == null) return line.length;
  return triple ? end + 3 : end + 1;
}

int? _findDartStringEnd(
  String line, {
  required int startQuoteIndex,
  required String quote,
  required bool triple,
  required bool raw,
}) {
  int i = startQuoteIndex + (triple ? 3 : 1);
  while (i < line.length) {
    if (!raw) {
      final String ch = line[i];

      if (!triple && ch == '\\') {
        i += 2;
        continue;
      }

      if (ch == r'$') {
        if (i + 1 < line.length && line[i + 1] == '{') {
          i = _skipDartInterpolationExpression(line, i + 2);
          continue;
        }
        if (i + 1 < line.length && _isIdentStartChar(line[i + 1])) {
          i += 2;
          while (i < line.length && _isIdentChar(line[i])) {
            i += 1;
          }
          continue;
        }
      }
    }

    if (triple) {
      if (i + 2 < line.length &&
          line[i] == quote &&
          line[i + 1] == quote &&
          line[i + 2] == quote) {
        return i;
      }
      i += 1;
      continue;
    }

    if (line[i] == quote) return i;
    i += 1;
  }
  return null;
}

int _skipDartInterpolationExpression(String line, int start) {
  int depth = 1;
  int i = start;
  while (i < line.length) {
    final String ch = line[i];

    if (ch == "'" || ch == '"') {
      i = _skipDartStringLiteral(line, i);
      continue;
    }

    if (ch == '/' && i + 1 < line.length) {
      final String next = line[i + 1];
      if (next == '/') {
        return line.length;
      }
      if (next == '*') {
        final int end = line.indexOf('*/', i + 2);
        if (end == -1) return line.length;
        i = end + 2;
        continue;
      }
    }

    if (ch == '{') {
      depth += 1;
      i += 1;
      continue;
    }
    if (ch == '}') {
      depth -= 1;
      i += 1;
      if (depth == 0) return i;
      continue;
    }
    i += 1;
  }
  return line.length;
}

bool _needsTranslation(String literal) {
  final String trimmed = literal.trim();
  if (trimmed.isEmpty) return false;
  return RegExp(r'[A-Za-z]').hasMatch(trimmed) ||
      RegExp(r'[\u4E00-\u9FFF]').hasMatch(trimmed) ||
      RegExp(r'[\u3040-\u30FF]').hasMatch(trimmed) ||
      RegExp(r'[\uAC00-\uD7AF]').hasMatch(trimmed);
}

Map<String, Map<String, _UiLiteralOccurrence>> _scanUiStringLiterals(
  _ProjectContext ctx,
) {
  final List<RegExp> uiMarkerPatterns = [
    RegExp(r'\bText(?:\s*\.\s*rich)?\s*\('),
    RegExp(r'\bTooltip\s*\('),
    RegExp(r'\bSnackBar\s*\('),
    RegExp(r'\bAlertDialog\s*\('),
    RegExp(r'\bshowDialog\s*(?:<[^>]*>)?\s*\('),
    RegExp(r'\bhintText\s*:'),
    RegExp(r'\blabelText\s*:'),
    RegExp(r'\bhelperText\s*:'),
    RegExp(r'\berrorText\s*:'),
    RegExp(r'\bTab\s*\(\s*text\s*:'),
    RegExp(r'\bUINotifier\.'),
    RegExp(r'\bSemantics\s*\('),
  ];

  final Directory libDir = ctx.dir('lib');
  if (!libDir.existsSync()) return {};

  final Map<String, Map<String, _UiLiteralOccurrence>> findings = {};

  for (final FileSystemEntity ent
      in libDir.listSync(recursive: true, followLinks: false)) {
    if (ent is! File) continue;
    if (!ent.path.toLowerCase().endsWith('.dart')) continue;

    final String rel = ctx.toRelativePath(ent.path);
    if (rel.replaceAll('\\', '/').startsWith('lib/l10n/')) continue;
    if (rel.toLowerCase().endsWith('.g.dart')) continue;

    final String text = _readTextFile(ent);
    if (text.contains('// i18n-ignore-file')) continue;

    final List<String> lines = const LineSplitter().convert(text);
    for (int i = 0; i < lines.length; i++) {
      final int lineNumber = i + 1;
      final String line = lines[i];

      if (line.contains('// i18n-ignore')) continue;

      final String markerHaystack = _stripStringsAndLineComment(line);
      if (!uiMarkerPatterns.any(markerHaystack.contains)) continue;

      final List<String> literals = _extractStringLiteralsFromLine(
        _stripLineCommentOutsideStrings(line),
      );
      for (final String lit in literals) {
        if (!_needsTranslation(lit)) continue;
        final Map<String, _UiLiteralOccurrence> perFile =
            findings.putIfAbsent(rel, () => <String, _UiLiteralOccurrence>{});
        final _UiLiteralOccurrence occ =
            perFile.putIfAbsent(lit, () => _UiLiteralOccurrence());
        occ.add(lineNumber);
      }
    }
  }

  return findings;
}

List<String> _compareAgainstBaseline({
  required Map<String, Map<String, _UiLiteralOccurrence>> current,
  required Map<String, Map<String, int>> baseline,
}) {
  final List<String> issues = [];

  for (final MapEntry<String, Map<String, _UiLiteralOccurrence>> fileEntry
      in current.entries) {
    final String path = fileEntry.key;
    final Map<String, int> baseLits = baseline[path] ?? const {};
    for (final MapEntry<String, _UiLiteralOccurrence> litEntry
        in fileEntry.value.entries) {
      final String literal = litEntry.key;
      final _UiLiteralOccurrence occ = litEntry.value;
      final int? baseCount = baseLits[literal];
      if (baseCount == null) {
        issues.add(
          'New UI hardcoded string literal in $path: "${_escapeForDisplay(literal)}" (count=${occ.count}, lines=${occ.exampleLines.toList()..sort()})',
        );
        continue;
      }
      if (occ.count > baseCount) {
        issues.add(
          'Increased UI hardcoded string literal in $path: "${_escapeForDisplay(literal)}" (baseline=$baseCount, now=${occ.count}, lines=${occ.exampleLines.toList()..sort()})',
        );
      }
    }
  }

  return issues;
}

String _escapeForDisplay(String s) {
  return s.replaceAll('\\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n');
}

class _Baseline {
  _Baseline({
    required this.version,
    required this.generatedAt,
    required this.uiStringLiterals,
  });

  final int version;
  final DateTime generatedAt;
  final Map<String, Map<String, int>> uiStringLiterals;

  Map<String, dynamic> toJson() => {
        'version': version,
        'generatedAt': generatedAt.toIso8601String(),
        'uiStringLiterals': uiStringLiterals,
      };

  static _Baseline fromJson(Map<String, dynamic> json) {
    final int version = (json['version'] as num?)?.toInt() ?? 1;
    final String generatedAtRaw = (json['generatedAt'] as String?) ?? '';
    final DateTime generatedAt =
        DateTime.tryParse(generatedAtRaw)?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final Map<String, dynamic> uiRaw =
        (json['uiStringLiterals'] as Map<String, dynamic>?) ?? const {};
    final Map<String, Map<String, int>> ui = {};
    for (final MapEntry<String, dynamic> e in uiRaw.entries) {
      final Object? v = e.value;
      if (v is! Map) continue;
      final Map<String, int> litMap = {};
      for (final MapEntry<Object?, Object?> inner in v.entries) {
        final String? lit = inner.key is String ? inner.key as String : null;
        final int? count = inner.value is num ? (inner.value as num).toInt() : null;
        if (lit == null || count == null) continue;
        litMap[lit] = count;
      }
      ui[e.key] = litMap;
    }
    return _Baseline(version: version, generatedAt: generatedAt, uiStringLiterals: ui);
  }
}

_Baseline? _readBaseline(File file) {
  if (!file.existsSync()) return null;
  try {
    final Map<String, dynamic> json = _readJsonFile(file);
    return _Baseline.fromJson(json);
  } catch (_) {
    return null;
  }
}

void _writeBaseline(File file, _Baseline baseline) {
  final String jsonText = const JsonEncoder.withIndent('  ').convert(baseline.toJson());
  file.writeAsStringSync('$jsonText\n', encoding: utf8);
}

void _printReport({
  required _ProjectContext ctx,
  required _AuditResult result,
  required Map<String, Map<String, _UiLiteralOccurrence>> uiScan,
  required String baselinePath,
  required IOSink out,
  required IOSink err,
}) {
  out.writeln('## i18n audit report');
  out.writeln();

  out.writeln('- Project root: ${ctx.rootPath}');
  out.writeln('- Baseline: $baselinePath');
  out.writeln('- UI literal files: ${uiScan.length}');
  final int uiLiteralTotal = uiScan.values
      .map((m) => m.values.fold<int>(0, (a, b) => a + b.count))
      .fold<int>(0, (a, b) => a + b);
  out.writeln('- UI literal occurrences: $uiLiteralTotal');
  out.writeln();

  if (result.hardFailures.isNotEmpty) {
    err.writeln('### Hard failures');
    for (final String s in result.hardFailures) {
      err.writeln('- $s');
    }
    err.writeln();
  }

  if (result.softFailures.isNotEmpty) {
    err.writeln('### Baseline failures');
    for (final String s in result.softFailures) {
      err.writeln('- $s');
    }
    err.writeln();
  }
}
