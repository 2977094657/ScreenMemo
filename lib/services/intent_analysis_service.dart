import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'ai_chat_service.dart';
import 'ai_settings_service.dart';
import 'flutter_logger.dart';

/// 意图分析结果
class IntentResult {
  final String
  intent; // 例如: time_range_query | app_time_range_query | keyword_lookup
  final String intentSummary; // 面向用户的意图摘要，用于 UI 展示
  final int startMs; // 时间范围起点（毫秒，Epoch）
  final int endMs; // 时间范围终点（毫秒，Epoch）
  final String timezone; // 例如: Asia/Shanghai 或 UTC+08:00
  final List<String> apps; // 可混合应用名/包名，前端后续归一化
  final List<String> keywords; // 可选：关键词（用于无时间时的探测检索）
  final Map<String, dynamic> sqlFill; // 仅关键填充项（不含完整 SQL）
  // 当非首条消息时，AI 判断本次是否可复用上一轮上下文（跳过新的上下文检索）
  final bool skipContext;
  // 上下文加载策略（由意图模型判断）：reuse | refresh | page_prev | page_next
  // - reuse: 复用缓存上下文包（不重新查库）
  // - refresh: 重新构建默认窗口上下文（通常是范围末尾 7 天）
  // - page_prev/page_next: 在多周范围内，建议向前/向后翻一周重新构建上下文窗口
  final String contextAction;
  // 用户是否明确表示“先按现有线索开始找/别再追问/直接查”等（用于跳过澄清，先给候选）
  final bool userWantsProceed;
  // 新增：错误信息（当解析失败或歧义时由 AI 返回）
  final String?
  errorCode; // 如 MISSING_DATE | AMBIGUOUS_DATE | INVALID_DATE | UNSUPPORTED
  final String? errorMessage; // 中文错误原因

  const IntentResult({
    required this.intent,
    required this.intentSummary,
    required this.startMs,
    required this.endMs,
    required this.timezone,
    required this.apps,
    this.keywords = const <String>[],
    required this.sqlFill,
    this.skipContext = false,
    this.contextAction = 'reuse',
    this.userWantsProceed = false,
    this.errorCode,
    this.errorMessage,
  });

  bool get hasValidRange => startMs > 0 && endMs > 0 && endMs >= startMs;
  bool get hasError => (errorCode != null && errorCode!.trim().isNotEmpty);
}

/// 意图分析服务：调用 LLM 严格输出 JSON，仅返回关键 SQL 填充项与意图摘要
class IntentAnalysisService {
  IntentAnalysisService._internal();
  static final IntentAnalysisService instance =
      IntentAnalysisService._internal();

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

    try {
      await FlutterLogger.nativeInfo(
        'Intent',
        'analyze begin userText="${_clip(userText, 200)}" now=${now.toIso8601String()} tz=$tzName($tzReadable)',
      );
    } catch (_) {}
    try {
      final prev = (sys + '\n\n' + user);
      final preview = prev.length <= 1200
          ? prev
          : (prev.substring(0, 1200) + '…');
      await FlutterLogger.nativeDebug(
        'Intent',
        'promptLen=${prev.length} preview=\n' + preview,
      );
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
      await FlutterLogger.nativeInfo(
        'Intent',
        'ai response rawLen=${raw.length} preview=\n' + preview,
      );
    } catch (_) {}

    final Map<String, dynamic> json = _safeExtractJson(resp.content);
    IntentResult result = _mapToResult(json, now, tzReadable);
    final IntentResult fixed = _maybeFixRelativeRange(userText, result, now);
    if (fixed.startMs != result.startMs || fixed.endMs != result.endMs) {
      try {
        await FlutterLogger.nativeWarn(
          'Intent',
          'range corrected by heuristic: [${result.startMs}-${result.endMs}] -> [${fixed.startMs}-${fixed.endMs}] user="${_clip(userText, 80)}"',
        );
      } catch (_) {}
      result = fixed;
    }
    try {
      await FlutterLogger.nativeInfo(
        'Intent',
        'parsed intent=${result.intent} summary=${_clip(result.intentSummary, 80)} range=[${result.startMs}-${result.endMs}] tz=${result.timezone} apps=${result.apps.length}',
      );
    } catch (_) {}
    return result;
  }

  String _buildSystemPrompt(DateTime now, String tzName, String tzReadable) {
    // 指示严格 JSON 输出与本地时间口语映射
    return [
      'You are an intent parser that outputs STRICT JSON only. No explanations.',
      'Current local datetime: ${now.toIso8601String()}',
      'Timezone: $tzName ($tzReadable).',
      'Return a FIXED schema. For retrieval intents you MUST output explicit local datetimes; for intent="other" (non-retrieval), leave start_local/end_local empty.',
      'If the query mentions a calendar date (e.g., "10月10日"/"10月10号"/"2025年10月10日"), resolve to exact start_local and end_local in ISO-8601 with timezone offset (e.g., 2025-10-10T00:00:00+08:00).',
      'If the query mentions parts of day (上午/下午/晚上/今晚), map them to exact ranges using local time semantics: 上午=08:00–12:00, 下午=12:00–18:00, 晚上/今晚=18:00–24:00.',
      'If the query requires a time range but the time period is ambiguous/missing, DO NOT default to today. Instead, set an error object and leave start_local/end_local empty.',
      'Always respond in one JSON object with keys specified below.',
    ].join('\n');
  }

  String _buildUserPrompt(
    String userText, {
    IntentPrevHint? prev,
    List<String> prevUsers = const <String>[],
  }) {
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
        final Duration off = DateTime.now().timeZoneOffset;
        final String sign = off.inMinutes >= 0 ? '+' : '-';
        final int absMin = off.inMinutes.abs();
        final String oh = (absMin ~/ 60).toString().padLeft(2, '0');
        final String om = (absMin % 60).toString().padLeft(2, '0');
        String ymdhms(DateTime d) =>
            '${d.year}-${two(d.month)}-${two(d.day)}T${two(d.hour)}:${two(d.minute)}:${two(d.second)}$sign$oh:$om';
        final String prevStartIso = ymdhms(ds);
        final String prevEndIso = ymdhms(de);
        lines.add(
          'Previous context window ISO(local): ' +
              prevStartIso +
              ' – ' +
              prevEndIso,
        );
      }
      if (prev.apps.isNotEmpty) {
        lines.add('Previous apps: ' + prev.apps.join(', '));
      }
      if (prev.summary.trim().isNotEmpty) {
        lines.add('Previous intent summary (CN): ' + prev.summary.trim());
      }
      lines.add(
        'If this query is a follow-up within the previous context window (or a subset like narrowing by app), set "skip_context" = true, and you MUST copy the exact ISO datetimes from "Previous context window ISO(local)" into start_local and end_local.',
      );
      lines.add(
        'If this is NOT a follow-up, set skip_context=false and compute a new start_local/end_local explicitly (do NOT default to today).',
      );
    }
    lines.addAll(<String>[
      'Note: The app can only preload a 7-day context window at a time (default: the LAST 7 days within the requested range). If the user wants to keep searching across weeks, you can set context_action=page_prev/page_next to page the context window.',
      'Respond with exactly this JSON shape (do NOT add extra fields):',
      '{',
      '  "intent": "time_range_query | app_time_range_query | keyword_lookup | other",',
      '  "intent_summary": "中文一句话摘要，概述用户想查什么",',
      '  "start_local": "YYYY-MM-DDTHH:mm:ss±HH:MM（本地时间，带偏移；若 intent=other 可为空字符串）",',
      '  "end_local":   "YYYY-MM-DDTHH:mm:ss±HH:MM（本地时间，带偏移；若 intent=other 可为空字符串）",',
      '  "timezone":    "如 UTC+08:00",',
      '  "apps": ["可选，应用名或包名"],',
      '  "keywords": ["可选，关键词"],',
      '  "skip_context": true | false,',
      '  "context_action": "reuse | refresh | page_prev | page_next",',
      '  "user_wants_proceed": true | false,',
      '  "error": { "code": "MISSING_DATE | AMBIGUOUS_DATE | INVALID_DATE | UNSUPPORTED", "message": "中文错误原因" }',
      '}',
      'Rules:',
      '- 若 intent=other（非检索/非回顾屏幕记录，如：通用对话/闲聊/功能咨询/设置问题），start_local/end_local 必须留空，且不要返回 MISSING_DATE。',
      '- 仅当 intent 需要时间范围（time_range_query/app_time_range_query/keyword_lookup）时，才必须返回 start_local 与 end_local（ISO-8601，含偏移）；禁止默认到“今天”。',
      '- 若 intent 需要时间范围，但用户未给出可解析的日期/时间或存在歧义，请仅返回 error，并保持 start_local/end_local 为空。',
      '- 若用户说“今天/昨天/今晚”等相对时间，也要换算为本地具体日期时间并填入。',
      '- intent_summary 必须为中文。',
      '- 若为上一轮时间窗内的续问，合理设置 skip_context=true。',
      '- context_action 用于指导“上下文包”的复用/刷新/翻页（由你判断；不要依赖固定关键词）。',
      '- 若用户明确表示希望“先按现有线索开始找/别再追问/直接先找找看”，请将 user_wants_proceed=true（即使时间缺失/歧义也要填这个字段）。',
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
    DateTime startOfDay(DateTime d) =>
        DateTime(d.year, d.month, d.day, 0, 0, 0, 0, 0);
    DateTime endOfDay(DateTime d) =>
        DateTime(d.year, d.month, d.day, 23, 59, 59, 999, 0);

    final String low = p.toLowerCase();

    // 显式中文日期（如：10月10日/10月10号/2025年10月10日，支持 上午/下午/晚上）
    final List<int> explicit = _parseExplicitChineseDate(p, now);
    if (explicit.isNotEmpty &&
        explicit[0] > 0 &&
        explicit[1] > 0 &&
        explicit[1] >= explicit[0]) {
      return explicit;
    }

    // 明确列出的口语映射
    if (low.contains('今天上午')) {
      start = DateTime(now.year, now.month, now.day, 8, 0, 0, 0, 0);
      end = DateTime(
        now.year,
        now.month,
        now.day,
        12,
        0,
        0,
        0,
        0,
      ).subtract(const Duration(milliseconds: 1));
      return <int>[start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    }
    if (low.contains('今天下午')) {
      start = DateTime(now.year, now.month, now.day, 12, 0, 0, 0, 0);
      end = DateTime(
        now.year,
        now.month,
        now.day,
        18,
        0,
        0,
        0,
        0,
      ).subtract(const Duration(milliseconds: 1));
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
    if (low.contains('最近一月') ||
        low.contains('最近一个月') ||
        low.contains('近一月') ||
        low.contains('近一个月') ||
        low.contains('最近30天') ||
        low.contains('近30天')) {
      start = now.subtract(const Duration(days: 30));
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

  IntentResult _maybeFixRelativeRange(
    String userText,
    IntentResult result,
    DateTime now,
  ) {
    if (result.hasError || !result.hasValidRange) return result;
    // Only apply to relative-time phrases; do not touch explicit dates.
    final String t = userText.trim().toLowerCase();
    if (t.isEmpty) return result;
    if (RegExp(r'[12]\d{3}\s*年|\d{1,2}\s*月\s*\d{1,2}').hasMatch(t)) {
      return result;
    }

    String? period;
    if (t.contains('最近一月') ||
        t.contains('最近一个月') ||
        t.contains('近一月') ||
        t.contains('近一个月') ||
        t.contains('最近30天') ||
        t.contains('近30天')) {
      period = '最近一个月';
    } else if (t.contains('最近一周') || t.contains('最近7天')) {
      period = '最近一周';
    } else if (t.contains('最近三天') || t.contains('最近3天')) {
      period = '最近三天';
    } else if (t.contains('最近24小时') || t.contains('最近二十四小时')) {
      period = '最近24小时';
    } else if (t.contains('昨天')) {
      period = '昨天';
    } else if (t.contains('今天') || t == '今日') {
      period = '今天';
    }
    if (period == null) return result;

    final List<int> expected = _computeRangeFromTimePeriod(period, now);
    if (expected.length < 2 || expected[0] <= 0 || expected[1] <= 0)
      return result;

    final int expStart = expected[0];
    final int expEnd = expected[1];
    final int gotStart = result.startMs;
    final int gotEnd = result.endMs;

    // If model output is clearly out-of-bounds (e.g. "last month" but returned ~1 year),
    // clamp to a sane window.
    final int gotSpan = (gotEnd > 0 && gotStart > 0)
        ? (gotEnd - gotStart).abs()
        : 0;
    final int maxSpan = (period == '最近一个月')
        ? const Duration(days: 45).inMilliseconds
        : const Duration(days: 14).inMilliseconds;
    final bool spanTooLarge = gotSpan > maxSpan;

    final int nowMs = now.millisecondsSinceEpoch;
    final bool endFarFromNow =
        gotEnd > 0 &&
        (gotEnd - nowMs).abs() > const Duration(days: 3).inMilliseconds;

    if (!spanTooLarge && !endFarFromNow) return result;

    return IntentResult(
      intent: result.intent,
      intentSummary: result.intentSummary,
      startMs: expStart,
      endMs: expEnd,
      timezone: result.timezone,
      apps: result.apps,
      keywords: result.keywords,
      sqlFill: result.sqlFill,
      skipContext: result.skipContext,
      contextAction: result.contextAction,
      userWantsProceed: result.userWantsProceed,
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
    );
  }

  /// 解析显式中文日期：
  /// - 10月10日 / 10月10号
  /// - 2025年10月10日
  /// 可选带时段：上午/下午/晚上（与“今天上午/下午/晚上”的时间划分一致）
  List<int> _parseExplicitChineseDate(String text, DateTime now) {
    // 注意：这里使用原始字符串(r'...')，不要对正则中的反斜杠做二次转义
    // 正确写法示例：\d -> 在原始字符串中写成 \d，而不是 \\\\d
    final RegExp reYmd = RegExp(
      r'(?:([12]\d{3})年)?\s*(\d{1,2})\s*月\s*(\d{1,2})\s*(?:[日号])?',
    );
    final Match? m = reYmd.firstMatch(text);
    if (m == null) {
      return const <int>[0, 0];
    }

    int year = now.year;
    try {
      final String? y = m.group(1);
      if (y != null && y.isNotEmpty) year = int.parse(y);
    } catch (_) {}

    int month;
    int day;
    try {
      month = int.parse(m.group(2)!);
      day = int.parse(m.group(3)!);
    } catch (_) {
      return const <int>[0, 0];
    }

    DateTime startOfDay(DateTime d) =>
        DateTime(d.year, d.month, d.day, 0, 0, 0, 0, 0);
    DateTime endOfDay(DateTime d) =>
        DateTime(d.year, d.month, d.day, 23, 59, 59, 999, 0);

    late final DateTime base;
    try {
      base = DateTime(year, month, day, 0, 0, 0, 0, 0);
      if (base.year != year || base.month != month || base.day != day) {
        return const <int>[0, 0];
      }
    } catch (_) {
      return const <int>[0, 0];
    }

    final bool isMorning = text.contains('上午') || text.contains('早上');
    final bool isAfternoon = text.contains('下午');
    final bool isEvening =
        text.contains('晚上') ||
        text.contains('晚间') ||
        text.contains('夜里') ||
        text.contains('夜间') ||
        text.contains('夜晚') ||
        text.contains('傍晚');

    DateTime start;
    DateTime end;
    if (isMorning) {
      start = DateTime(base.year, base.month, base.day, 8, 0, 0, 0, 0);
      end = DateTime(
        base.year,
        base.month,
        base.day,
        12,
        0,
        0,
        0,
        0,
      ).subtract(const Duration(milliseconds: 1));
    } else if (isAfternoon) {
      start = DateTime(base.year, base.month, base.day, 12, 0, 0, 0, 0);
      end = DateTime(
        base.year,
        base.month,
        base.day,
        18,
        0,
        0,
        0,
        0,
      ).subtract(const Duration(milliseconds: 1));
    } else if (isEvening) {
      start = DateTime(base.year, base.month, base.day, 18, 0, 0, 0, 0);
      end = endOfDay(base);
    } else {
      start = startOfDay(base);
      end = endOfDay(base);
    }

    return <int>[start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
  }

  IntentResult _mapToResult(
    Map<String, dynamic> j,
    DateTime now,
    String tzReadable,
  ) {
    int startMs = 0;
    int endMs = 0;
    String intent = (j['intent'] as String?)?.trim() ?? 'time_range_query';
    String intentSummary =
        (j['intent_summary'] as String?)?.trim() ?? '用户查询近期活动';
    final Map<String, dynamic> sql = (j['sql_fill'] is Map)
        ? Map<String, dynamic>.from(j['sql_fill'])
        : <String, dynamic>{};
    List<String> apps = <String>[];
    List<String> keywords = <String>[];
    bool skipContext = false;
    String contextAction = 'reuse';
    bool userWantsProceed = false;
    String? errorCode;
    String? errorMessage;

    // 新协议：必须提供 start_local / end_local（ISO-8601，本地时区带偏移）
    String? sLocalRaw;
    String? eLocalRaw;
    try {
      sLocalRaw = (j['start_local'] as String?)?.trim();
      eLocalRaw = (j['end_local'] as String?)?.trim();
      if (sLocalRaw != null &&
          sLocalRaw!.isNotEmpty &&
          eLocalRaw != null &&
          eLocalRaw!.isNotEmpty) {
        try {
          final DateTime s = DateTime.parse(sLocalRaw!);
          final DateTime e = DateTime.parse(eLocalRaw!);
          startMs = s.millisecondsSinceEpoch;
          endMs = e.millisecondsSinceEpoch;
        } catch (e) {
          errorCode = 'INVALID_DATE';
          errorMessage = '无法解析模型返回的日期时间：start_local/end_local 格式错误';
        }
      }
    } catch (_) {}

    // 读取 error 对象（若模型认为输入缺失/歧义）
    try {
      final Map<String, dynamic>? err = (j['error'] is Map)
          ? Map<String, dynamic>.from(j['error'])
          : null;
      final String? ec = (err?['code'] as String?)?.trim();
      final String? em = (err?['message'] as String?)?.trim();
      if (ec != null && ec.isNotEmpty) errorCode = ec;
      if (em != null && em.isNotEmpty) errorMessage = em;
    } catch (_) {}

    try {
      final dynamic a = j['apps'];
      if (a is List) {
        apps = a
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {}

    try {
      final dynamic k = j['keywords'];
      if (k is List) {
        keywords = k
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
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

    try {
      final dynamic ca =
          j['context_action'] ?? j['contextAction'] ?? j['context'];
      if (ca is String) {
        final String s = ca.trim().toLowerCase();
        if (s == 'reuse' || s == 'cache' || s == 'cached') {
          contextAction = 'reuse';
        } else if (s == 'refresh' || s == 'reload' || s == 'new') {
          contextAction = 'refresh';
        } else if (s == 'page_prev' ||
            s == 'prev' ||
            s == 'previous' ||
            s == 'pageprevious') {
          contextAction = 'page_prev';
        } else if (s == 'page_next' || s == 'next' || s == 'pagenext') {
          contextAction = 'page_next';
        }
      }
    } catch (_) {}

    if (!skipContext && contextAction == 'reuse') {
      contextAction = 'refresh';
    }

    try {
      final dynamic p =
          j['user_wants_proceed'] ?? j['wants_proceed'] ?? j['proceed'];
      if (p is bool) userWantsProceed = p;
      if (p is String) {
        final String s = p.trim().toLowerCase();
        if (s == 'true' || s == 'yes' || s == '1') userWantsProceed = true;
        if (s == 'false' || s == 'no' || s == '0') userWantsProceed = false;
      }
    } catch (_) {}

    // 禁止回退：若无效则保持无效，由上层终止流程并提示错误

    // 始终填充 SQL 段与日期键（若有效）
    if (startMs > 0 && endMs > 0 && endMs >= startMs) {
      sql['segments_between'] = {'start_ms': startMs, 'end_ms': endMs};
      try {
        final String? sd = (sLocalRaw != null && sLocalRaw!.contains('T'))
            ? sLocalRaw!.split('T').first
            : null;
        final String? ed = (eLocalRaw != null && eLocalRaw!.contains('T'))
            ? eLocalRaw!.split('T').first
            : null;
        if (sd != null || ed != null) {
          sql['context_date'] = {
            if (sd != null) 'start_date': sd,
            if (ed != null) 'end_date': ed,
          };
        }
        if (sLocalRaw != null) sql['start_local'] = sLocalRaw;
        if (eLocalRaw != null) sql['end_local'] = eLocalRaw;
        final String? tzFromModel = (j['timezone'] as String?)?.trim();
        if (tzFromModel != null && tzFromModel.isNotEmpty)
          sql['timezone'] = tzFromModel;
      } catch (_) {}
    }

    return IntentResult(
      intent: intent,
      intentSummary: intentSummary,
      startMs: startMs,
      endMs: endMs,
      timezone: (j['timezone'] as String?)?.trim().isNotEmpty == true
          ? (j['timezone'] as String).trim()
          : tzReadable,
      apps: apps,
      keywords: keywords,
      sqlFill: sql,
      skipContext: skipContext,
      contextAction: contextAction,
      userWantsProceed: userWantsProceed,
      errorCode: errorCode,
      errorMessage: errorMessage,
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
