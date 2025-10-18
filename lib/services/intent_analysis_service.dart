import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'ai_chat_service.dart';
import 'ai_settings_service.dart';
import 'flutter_logger.dart';

/// 意图分析结果
class IntentResult {
  final String intent; // 例如: time_range_query | app_time_range_query | keyword_lookup
  final String intentSummary; // 面向用户的意图摘要，用于 UI 展示
  final int startMs; // 时间范围起点（毫秒，Epoch）
  final int endMs;   // 时间范围终点（毫秒，Epoch）
  final String timezone; // 例如: Asia/Shanghai 或 UTC+08:00
  final List<String> apps; // 可混合应用名/包名，前端后续归一化
  final Map<String, dynamic> sqlFill; // 仅关键填充项（不含完整 SQL）
  // 当非首条消息时，AI 判断本次是否可复用上一轮上下文（跳过新的上下文检索）
  final bool skipContext;

  const IntentResult({
    required this.intent,
    required this.intentSummary,
    required this.startMs,
    required this.endMs,
    required this.timezone,
    required this.apps,
    required this.sqlFill,
    this.skipContext = false,
  });

  bool get hasValidRange => startMs > 0 && endMs > 0 && endMs >= startMs;
}

/// 意图分析服务：调用 LLM 严格输出 JSON，仅返回关键 SQL 填充项与意图摘要
class IntentAnalysisService {
  IntentAnalysisService._internal();
  static final IntentAnalysisService instance = IntentAnalysisService._internal();

  final AIChatService _chat = AIChatService.instance;

  /// 分析用户输入，产出 JSON-only 结果
  Future<IntentResult> analyze(
    String userText, {
    IntentPrevHint? previous,
    List<String> previousUserQueries = const <String>[],
  }) async {
    final now = DateTime.now();
    final String tzName = now.timeZoneName;
    final Duration tzOffset = now.timeZoneOffset;
    final int offsetMinutes = tzOffset.inMinutes;
    final String tzSign = offsetMinutes >= 0 ? '+' : '-';
    final int absMin = offsetMinutes.abs();
    final String tzHh = (absMin ~/ 60).toString().padLeft(2, '0');
    final String tzMm = (absMin % 60).toString().padLeft(2, '0');
    final String tzReadable = 'UTC$tzSign$tzHh:$tzMm';

    final String sys = _buildSystemPrompt(now, tzName, tzReadable);
    final String user = _buildUserPrompt(
      userText,
      prev: previous,
      prevUsers: previousUserQueries,
    );

    try { await FlutterLogger.nativeInfo('Intent', 'analyze begin userText="${_clip(userText, 200)}" now=${now.toIso8601String()} tz=$tzName($tzReadable)'); } catch (_) {}
    try {
      final prev = (sys + '\n\n' + user);
      final preview = prev.length <= 1200 ? prev : (prev.substring(0, 1200) + '…');
      await FlutterLogger.nativeDebug('Intent', 'promptLen=${prev.length} preview=\n' + preview);
    } catch (_) {}

    // 使用一次性请求，避免污染会话历史
    final AIMessage resp = await _chat.sendMessageOneShot(
      sys + '\n\n' + user,
      context: 'chat',
      timeout: const Duration(seconds: 45),
    );

    try {
      final raw = resp.content;
      final preview = raw.length <= 1200 ? raw : (raw.substring(0, 1200) + '…');
      await FlutterLogger.nativeInfo('Intent', 'ai response rawLen=${raw.length} preview=\n' + preview);
    } catch (_) {}

    final Map<String, dynamic> json = _safeExtractJson(resp.content);
    final result = _mapToResult(json, now, tzReadable);
    try {
      await FlutterLogger.nativeInfo('Intent', 'parsed intent=${result.intent} summary=${_clip(result.intentSummary, 80)} range=[${result.startMs}-${result.endMs}] tz=${result.timezone} apps=${result.apps.length}');
    } catch (_) {}
    return result;
  }

  String _buildSystemPrompt(DateTime now, String tzName, String tzReadable) {
    // 指示严格 JSON 输出与本地时间口语映射
    return [
      'You are an intent parser that outputs STRICT JSON only. No explanations.',
      'Current local datetime: ${now.toIso8601String()}',
      'Timezone: $tzName ($tzReadable).',
      'When the user asks time-related ranges in Chinese, return only a human-readable time period (time_period).',
      'DO NOT return timestamps or milliseconds; we will convert programmatically.',
      'If the user does not explicitly specify a time period, DEFAULT to time_period = "今天" (local today).',
      'Interpret colloquial periods using local time semantics:',
      '- "今天上午": 08:00–12:00 (local today)',
      '- "今天下午": 12:00–18:00 (local today)',
      '- "今天晚上"/"今晚": 18:00–24:00 (local today)',
      '- "昨天": 00:00–24:00 of yesterday (local)',
      '- "最近一周": now-7d to now (local)',
      '- "最近三天": now-3d to now (local)',
      '- "最近24小时": now-24h to now (local)',
      'Only return minimal fields and the time_period; no extra fields.',
      'Always respond in one JSON object with keys specified below.',
    ].join('\n');
  }

  String _buildUserPrompt(String userText, {IntentPrevHint? prev, List<String> prevUsers = const <String>[]}) {
    final List<String> lines = <String>[];
    lines.add('User query: "${userText.replaceAll('"', '\\"')}"');
    if (prevUsers.isNotEmpty) {
      lines.add('Previous user queries (most recent first):');
      final int limit = prevUsers.length;
      for (int i = 0; i < limit; i++) {
        final String q = prevUsers[i].replaceAll('"', '\\"');
        if (q.isEmpty) continue;
        lines.add('- "' + q + '"');
      }
    }
    if (prev != null) {
      String two(int v) => v.toString().padLeft(2, '0');
      if (prev.startMs > 0 && prev.endMs > 0 && prev.endMs >= prev.startMs) {
        final ds = DateTime.fromMillisecondsSinceEpoch(prev.startMs);
        final de = DateTime.fromMillisecondsSinceEpoch(prev.endMs);
        lines.add('Previous context window: ${two(ds.hour)}:${two(ds.minute)}–${two(de.hour)}:${two(de.minute)}');
      }
      if (prev.apps.isNotEmpty) {
        lines.add('Previous apps: ' + prev.apps.join(', '));
      }
      if (prev.summary.trim().isNotEmpty) {
        lines.add('Previous intent summary (CN): ' + prev.summary.trim());
      }
      lines.add('If this query is a follow-up within the previous context window (or a subset like narrowing by app), set "skip_context" to true to reuse previous context. Otherwise set it to false. Consider the previous user queries above to judge continuity.');
    }
    lines.add('If the user does not mention any time period explicitly, assume time_period = "今天" (local today).');
    lines.add('If previous user queries indicate today and a previous context window exists for today, set "skip_context" = true to reuse it.');
    lines.addAll(<String>[
      'Respond with exactly this JSON shape (do NOT add extra fields):',
      '{',
      '  "intent": "time_range_query | app_time_range_query | keyword_lookup | other",',
      '  "intent_summary": "中文一句话摘要，概述用户想查什么",',
      '  "time_period": "中文时间段（如：今天、昨天、今天上午、今天下午、今天晚上、今晚、最近一周、最近三天、最近24小时）",',
      '  "apps": ["可选，应用名或包名"],',
      '  "keywords": ["可选，关键词"],',
      '  "sql_fill": {',
      '    "segments_between": { "start_ms": 0, "end_ms": 0 }',
      '  },',
      '  "skip_context": true | false',
      '}',
      'Rules:',
      '- If time-related, set only time_period; leave milliseconds as 0 in sql_fill.segments_between.',
      '- Use local timezone to resolve colloquial periods.',
      '- intent_summary must be Chinese.',
      '- If previous context provided and this is a follow-up within it, set skip_context=true.',
    ]);
    return lines.join('\n');
  }

  /// 将长字符串截断以便日志预览
  String _clip(String s, int maxLen) {
    if (s.isEmpty) return s;
    return s.length <= maxLen ? s : (s.substring(0, maxLen) + '…');
  }

  Map<String, dynamic> _safeExtractJson(String content) {
    // 去除围栏与前后噪音，找最外层花括号解析
    String s = content.trim();
    if (s.startsWith('```')) {
      final idx = s.indexOf('\n');
      if (idx >= 0) s = s.substring(idx + 1);
      if (s.endsWith('```')) s = s.substring(0, s.length - 3);
    }
    final int l = s.indexOf('{');
    final int r = s.lastIndexOf('}');
    if (l >= 0 && r > l) {
      s = s.substring(l, r + 1);
    }
    try {
      final j = jsonDecode(s);
      if (j is Map<String, dynamic>) return j;
    } catch (_) {}
    return <String, dynamic>{};
  }

  /// 将中文时间段文本转换为 [startMs, endMs]（endMs 为包含端点，毫秒）
  List<int> _computeRangeFromTimePeriod(String? period, DateTime now) {
    if (period == null) return const <int>[0, 0];
    final String p = period.trim();
    if (p.isEmpty) return const <int>[0, 0];

    DateTime start;
    DateTime end;

    // 基于本地时间的“今天/昨天”等计算
    DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 0, 0, 0, 0, 0);
    DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999, 0);

    final String low = p.toLowerCase();

    // 明确列出的口语映射
    if (low.contains('今天上午')) {
      start = DateTime(now.year, now.month, now.day, 8, 0, 0, 0, 0);
      end = DateTime(now.year, now.month, now.day, 12, 0, 0, 0, 0).subtract(const Duration(milliseconds: 1));
      return <int>[start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    }
    if (low.contains('今天下午')) {
      start = DateTime(now.year, now.month, now.day, 12, 0, 0, 0, 0);
      end = DateTime(now.year, now.month, now.day, 18, 0, 0, 0, 0).subtract(const Duration(milliseconds: 1));
      return <int>[start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    }
    if (low.contains('今天晚上') || low == '今晚') {
      start = DateTime(now.year, now.month, now.day, 18, 0, 0, 0, 0);
      end = endOfDay(now);
      return <int>[start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    }
    if (low.contains('昨天')) {
      final DateTime y = now.subtract(const Duration(days: 1));
      start = startOfDay(y);
      end = endOfDay(y);
      return <int>[start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    }
    if (low.contains('最近一周') || low.contains('最近7天')) {
      start = now.subtract(const Duration(days: 7));
      end = now;
      return <int>[start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    }
    if (low.contains('最近三天') || low.contains('最近3天')) {
      start = now.subtract(const Duration(days: 3));
      end = now;
      return <int>[start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    }
    if (low.contains('最近24小时') || low.contains('最近二十四小时')) {
      start = now.subtract(const Duration(hours: 24));
      end = now;
      return <int>[start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    }
    if (low.contains('今天') || low == '今日') {
      start = startOfDay(now);
      end = endOfDay(now);
      return <int>[start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    }

    return const <int>[0, 0];
  }

  IntentResult _mapToResult(Map<String, dynamic> j, DateTime now, String tzReadable) {
    int startMs = 0;
    int endMs = 0;
    String intent = (j['intent'] as String?)?.trim() ?? 'time_range_query';
    String intentSummary = (j['intent_summary'] as String?)?.trim() ?? '用户查询近期活动';
    final Map<String, dynamic> sql = (j['sql_fill'] is Map) ? Map<String, dynamic>.from(j['sql_fill']) : <String, dynamic>{};
    List<String> apps = <String>[];
    bool skipContext = false;

    // 优先使用 time_period 文本进行转换
    try {
      final String? periodText = (j['time_period'] as String?)?.trim();
      final List<int> r = _computeRangeFromTimePeriod(periodText, now);
      startMs = (r.isNotEmpty) ? r[0] : 0;
      endMs = (r.length >= 2) ? r[1] : 0;
    } catch (_) {}

    // 兼容旧协议：若无 time_period 或转换失败，则尝试直接读取数值 time_range
    if (startMs <= 0 || endMs <= 0 || endMs < startMs) {
      try {
        final Map<String, dynamic>? tr = (j['time_range'] is Map) ? Map<String, dynamic>.from(j['time_range']) : null;
        startMs = (tr?['start_ms'] is num) ? (tr!['start_ms'] as num).toInt() : 0;
        endMs   = (tr?['end_ms'] is num) ? (tr!['end_ms'] as num).toInt()   : 0;
      } catch (_) {}
    }

    try {
      final dynamic a = j['apps'];
      if (a is List) {
        apps = a.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}

    try {
      final dynamic sc = j['skip_context'];
      if (sc is bool) skipContext = sc;
      if (sc is String) {
        final s = sc.trim().toLowerCase();
        if (s == 'true' || s == 'yes' || s == '1') skipContext = true;
        if (s == 'false' || s == 'no' || s == '0') skipContext = false;
      }
    } catch (_) {}

    // 兜底：若解析失败，默认使用“今天”的完整时间窗（本地时区）
    if (startMs <= 0 || endMs <= 0 || endMs < startMs) {
      final DateTime s = DateTime(now.year, now.month, now.day, 0, 0, 0, 0, 0);
      final DateTime e = DateTime(now.year, now.month, now.day, 23, 59, 59, 999, 0);
      startMs = s.millisecondsSinceEpoch;
      endMs = e.millisecondsSinceEpoch;
    }

    // 始终填充 SQL 段，使用程序端计算的毫秒范围
    sql['segments_between'] = {'start_ms': startMs, 'end_ms': endMs};

    return IntentResult(
      intent: intent,
      intentSummary: intentSummary,
      startMs: startMs,
      endMs: endMs,
      timezone: tzReadable,
      apps: apps,
      sqlFill: sql,
      skipContext: skipContext,
    );
  }
}

/// 传递给意图分析器的“上一轮上下文”提示
class IntentPrevHint {
  final int startMs;
  final int endMs;
  final List<String> apps;
  final String summary; // 中文概要，来自上一轮 intentSummary
  const IntentPrevHint({
    required this.startMs,
    required this.endMs,
    this.apps = const <String>[],
    this.summary = '',
  });
}


