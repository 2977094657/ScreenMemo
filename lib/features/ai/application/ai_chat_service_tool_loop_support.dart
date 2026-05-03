part of 'ai_chat_service.dart';

extension AIChatServiceToolLoopSupportExt on AIChatService {
  AIGatewayResult _maybeCoerceToolCallsFromText(
    AIGatewayResult result,
    List<Map<String, dynamic>> tools,
  ) {
    if (result.toolCalls.isNotEmpty) return result;
    final String content = result.content;
    if (content.isEmpty) return result;

    final Set<String> allowedTools = _extractToolNames(tools);
    if (allowedTools.isEmpty) return result;

    final ({List<AIToolCall> calls, String cleaned}) parsed =
        _tryParseTextToolCalls(content, allowedTools);
    if (parsed.calls.isEmpty) return result;

    return AIGatewayResult(
      content: parsed.cleaned,
      modelUsed: result.modelUsed,
      toolCalls: parsed.calls,
      reasoning: result.reasoning,
      reasoningDuration: result.reasoningDuration,
    );
  }

  ({List<AIToolCall> calls, String cleaned}) _tryParseTextToolCalls(
    String content,
    Set<String> allowedTools,
  ) {
    // Some models (or provider adapters) output tool calls in plain text using
    // XML-like wrappers, but they may omit closing tags. We try to salvage
    // those tool calls and keep only the user-visible prose.
    String scan = content;
    String cleanedCandidate = content;
    bool hasWrapper = false;

    final RegExp wrapperOpenRe = RegExp(
      r'<function_calls\b[^>]*>',
      caseSensitive: false,
    );
    final RegExp wrapperCloseRe = RegExp(
      r'</function_calls\s*>',
      caseSensitive: false,
    );
    final RegExpMatch? wrapperOpen = wrapperOpenRe.firstMatch(content);
    if (wrapperOpen != null) {
      hasWrapper = true;
      final int start = wrapperOpen.start;
      int end = content.length;
      final RegExpMatch? wrapperClose = wrapperCloseRe.firstMatch(
        content.substring(wrapperOpen.end),
      );
      if (wrapperClose != null) {
        end = wrapperOpen.end + wrapperClose.end;
      }
      scan = content.substring(start, end);
      cleanedCandidate = (content.substring(0, start) + content.substring(end))
          .trim();
    }

    final RegExp invokeOpenRe = RegExp(
      r'<invoke\b[^>]*>',
      caseSensitive: false,
    );
    final RegExp invokeCloseRe = RegExp(r'</invoke\s*>', caseSensitive: false);
    final List<RegExpMatch> invokeOpens = invokeOpenRe
        .allMatches(scan)
        .toList();
    if (invokeOpens.isEmpty) {
      return (calls: const <AIToolCall>[], cleaned: content);
    }

    final List<({int start, int end, String block})> invokeBlocks =
        <({int start, int end, String block})>[];
    for (int i = 0; i < invokeOpens.length; i++) {
      final RegExpMatch om = invokeOpens[i];
      final int start = om.start;
      final int nextStart = (i + 1 < invokeOpens.length)
          ? invokeOpens[i + 1].start
          : scan.length;

      int end = nextStart;
      final RegExpMatch? close = invokeCloseRe.firstMatch(
        scan.substring(om.end),
      );
      if (close != null) {
        final int closeStartAbs = om.end + close.start;
        final int closeEndAbs = om.end + close.end;
        if (closeStartAbs <= nextStart) {
          end = closeEndAbs;
        }
      }

      if (end <= start) continue;
      final String block = scan.substring(start, end);
      invokeBlocks.add((start: start, end: end, block: block));
    }
    if (invokeBlocks.isEmpty) {
      return (calls: const <AIToolCall>[], cleaned: content);
    }

    final List<AIToolCall> out = <AIToolCall>[];
    for (final b in invokeBlocks) {
      final String block = b.block;
      if (block.trim().isEmpty) continue;

      String name = '';
      final RegExp nameRe = RegExp(
        r'''\bname\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      );
      final RegExpMatch? nameM = nameRe.firstMatch(block);
      if (nameM != null) name = (nameM.group(1) ?? '').trim();
      if (name.isEmpty) {
        final RegExp toolRe = RegExp(
          r'''\btool\s*=\s*["']([^"']+)["']''',
          caseSensitive: false,
        );
        final RegExpMatch? toolM = toolRe.firstMatch(block);
        if (toolM != null) name = (toolM.group(1) ?? '').trim();
      }
      if (name.isEmpty || !allowedTools.contains(name)) continue;

      final Map<String, dynamic> args = <String, dynamic>{};

      // 1) Normal form: <parameter name="x">value</parameter>
      final RegExp paramRe = RegExp(
        r'''<parameter\b[^>]*\bname\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</parameter>''',
        caseSensitive: false,
      );
      for (final pm in paramRe.allMatches(block)) {
        final String key = (pm.group(1) ?? '').trim();
        if (key.isEmpty) continue;
        final String raw = (pm.group(2) ?? '').trim();
        final dynamic value = _parseLooseValue(raw);
        if (!args.containsKey(key)) {
          args[key] = value;
          continue;
        }
        final existing = args[key];
        if (existing is List) {
          existing.add(value);
        } else {
          args[key] = <dynamic>[existing, value];
        }
      }

      // 2) Tolerate missing </parameter>: <parameter name="x">value\n
      if (args.isEmpty) {
        final RegExp paramOpenRe = RegExp(
          r'''<parameter\b[^>]*\bname\s*=\s*["']([^"']+)["'][^>]*>''',
          caseSensitive: false,
        );
        final List<RegExpMatch> opens = paramOpenRe.allMatches(block).toList();
        for (int i = 0; i < opens.length; i++) {
          final RegExpMatch pm = opens[i];
          final String key = (pm.group(1) ?? '').trim();
          if (key.isEmpty) continue;
          if (args.containsKey(key)) continue;

          int valueEnd = block.length;
          if (i + 1 < opens.length) {
            valueEnd = opens[i + 1].start;
          }
          final RegExpMatch? close = RegExp(
            r'</parameter\s*>',
            caseSensitive: false,
          ).firstMatch(block.substring(pm.end, valueEnd));
          if (close != null) {
            valueEnd = pm.end + close.start;
          }
          final String raw = block.substring(pm.end, valueEnd).trim();
          if (raw.isEmpty) continue;
          args[key] = _parseLooseValue(raw);
        }
      }

      // 3) Fallback: some models dump a raw JSON object as "arguments".
      if (args.isEmpty) {
        final int firstBrace = block.indexOf('{');
        final int lastBrace = block.lastIndexOf('}');
        if (firstBrace >= 0 && lastBrace > firstBrace) {
          final String raw = block.substring(firstBrace, lastBrace + 1).trim();
          try {
            final dynamic v = jsonDecode(raw);
            if (v is Map) {
              args.addAll(Map<String, dynamic>.from(v as Map));
            }
          } catch (_) {}
        }
      }

      out.add(
        AIToolCall(
          id: 'toolu_text_${++_textToolCallSeq}',
          name: name,
          argumentsJson: jsonEncode(args),
        ),
      );
    }
    if (out.isEmpty) {
      return (calls: const <AIToolCall>[], cleaned: content);
    }

    String cleaned = content;
    if (hasWrapper) {
      cleaned = cleanedCandidate;
    } else {
      // Remove the detected <invoke ...> blocks from the visible content.
      final List<({int start, int end})> ranges =
          invokeBlocks.map((b) => (start: b.start, end: b.end)).toList()
            ..sort((a, b) => b.start.compareTo(a.start));
      String t = content;
      for (final r in ranges) {
        if (r.start < 0 || r.end > t.length || r.end <= r.start) continue;
        t = t.substring(0, r.start) + t.substring(r.end);
      }
      cleaned = t.trim();
    }

    return (calls: out, cleaned: cleaned);
  }

  dynamic _parseLooseValue(String raw) {
    final String t = raw.trim();
    if (t.isEmpty) return '';
    final int? i = int.tryParse(t);
    if (i != null) return i;
    final double? d = double.tryParse(t);
    if (d != null) return d;
    final String lower = t.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
    if ((t.startsWith('{') && t.endsWith('}')) ||
        (t.startsWith('[') && t.endsWith(']'))) {
      try {
        return jsonDecode(t);
      } catch (_) {}
    }
    return t;
  }

  void _emitProgress(
    void Function(AIStreamEvent event)? emitEvent,
    String message, {
    bool bullet = true,
  }) {
    if (emitEvent == null) return;
    final String prefix = bullet ? '- ' : '';
    final String line = message.endsWith('\n') ? message : '$message\n';
    emitEvent(AIStreamEvent('reasoning', prefix + line));
  }

  void _emitUi(
    void Function(AIStreamEvent event)? emitEvent,
    Map<String, dynamic> payload,
  ) {
    if (emitEvent == null) return;
    try {
      emitEvent(AIStreamEvent('ui', jsonEncode(payload)));
    } catch (_) {}
  }

  ({
    int startMs,
    int endMs,
    bool clampedToGuard,
    bool guardApplied,
    bool clampedToMaxSpan,
  })
  _resolveToolTimeRange({
    required int defaultStartMs,
    required int defaultEndMs,
    int? startMs,
    int? endMs,
    int? guardStartMs,
    int? guardEndMs,
    int maxSpanMs = AIChatService.maxToolTimeSpanMs,
  }) {
    final bool hasGuard =
        (guardStartMs != null &&
        guardEndMs != null &&
        guardStartMs > 0 &&
        guardEndMs >= guardStartMs);
    final bool hasStartArg = (startMs != null && startMs > 0);
    final bool hasEndArg = (endMs != null && endMs > 0);
    int s = (startMs != null && startMs > 0)
        ? startMs
        : (hasGuard ? guardStartMs! : defaultStartMs);
    int e = (endMs != null && endMs > 0)
        ? endMs
        : (hasGuard ? guardEndMs! : defaultEndMs);

    if (s > e) {
      final int tmp = s;
      s = e;
      e = tmp;
    }

    bool clamped = false;
    if (hasGuard) {
      final int gs = guardStartMs!;
      final int ge = guardEndMs!;
      final int beforeS = s;
      final int beforeE = e;
      if (s < gs) s = gs;
      if (e > ge) e = ge;
      if (s > e) {
        s = gs;
        e = ge;
      }
      clamped = (s != beforeS) || (e != beforeE);
    }

    bool clampedToMaxSpan = false;
    if (maxSpanMs > 0) {
      final int span = e - s;
      if (span > maxSpanMs) {
        clampedToMaxSpan = true;
        // Prefer preserving explicit boundary: if only start_ms is given, keep it; otherwise keep end_ms.
        if (hasStartArg && !hasEndArg) {
          e = s + maxSpanMs;
        } else {
          s = e - maxSpanMs;
        }
        if (hasGuard) {
          final int gs = guardStartMs!;
          final int ge = guardEndMs!;
          if (s < gs) s = gs;
          if (e > ge) e = ge;
          if (s > e) {
            s = gs;
            e = ge;
          }
        }
      }
    }
    return (
      startMs: s,
      endMs: e,
      clampedToGuard: clamped,
      guardApplied: hasGuard,
      clampedToMaxSpan: clampedToMaxSpan,
    );
  }
}
