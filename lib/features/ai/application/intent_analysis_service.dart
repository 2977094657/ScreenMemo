import 'dart:convert';
import 'package:screen_memo/features/ai/application/ai_chat_service.dart';
import 'package:screen_memo/features/ai/application/ai_prompt_time_context.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';

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
    late final AIMessage resp;
    try {
      resp = await _chat.sendMessageOneShot(
        sys + '\n\n' + user,
        context: 'chat',
        timeout: const Duration(seconds: 45),
      );
    } catch (e) {
      // Graceful fallback when AI is not configured / unavailable (e.g. tests).
      try {
        await FlutterLogger.nativeWarn('Intent', 'analyze fallback: $e');
      } catch (_) {}
      return _fallbackResult(now, tzReadable);
    }

    try {
      final raw = resp.content;
      final preview = raw.length <= 1200 ? raw : (raw.substring(0, 1200) + '…');
      await FlutterLogger.nativeInfo(
        'Intent',
        'ai response rawLen=${raw.length} preview=\n' + preview,
      );
    } catch (_) {}

    final Map<String, dynamic> json = _safeExtractJson(resp.content);
    final IntentResult result = _mapToResult(json, now, tzReadable);
    try {
      await FlutterLogger.nativeInfo(
        'Intent',
        'parsed intent=${result.intent} summary=${_clip(result.intentSummary, 80)} range=[${result.startMs}-${result.endMs}] tz=${result.timezone} apps=${result.apps.length}',
      );
    } catch (_) {}
    return result;
  }

  IntentResult _fallbackResult(DateTime now, String tzReadable) {
    return IntentResult(
      intent: 'other',
      intentSummary: '意图解析服务不可用（不预设时间窗）',
      startMs: 0,
      endMs: 0,
      timezone: tzReadable,
      apps: const <String>[],
      keywords: const <String>[],
      sqlFill: <String, dynamic>{},
      skipContext: false,
      contextAction: 'refresh',
      userWantsProceed: false,
    );
  }

  String _buildSystemPrompt(DateTime now, String tzName, String tzReadable) {
    final String localDateTime = buildPromptLocalDateTime(now);
    // 指示严格 JSON 输出与本地时间口语映射
    return [
      'You are an intent parser that outputs STRICT JSON only. No explanations.',
      'Current local datetime: $localDateTime',
      'Timezone: $tzName ($tzReadable).',
      'Return a FIXED schema. start_local/end_local are OPTIONAL: provide them when confidently inferred, otherwise leave them empty and let downstream tools decide the search window.',
      'If the query mentions a calendar date (e.g., "10月10日"/"10月10号"/"2025年10月10日"), resolve to exact start_local and end_local in ISO-8601 with timezone offset (e.g., 2025-10-10T00:00:00+08:00).',
      'If the query mentions parts of day, map them to exact local ranges.',
      'If the query requires a time range but the time period is ambiguous/missing, DO NOT default to the current day. Instead, set an error object and leave start_local/end_local empty.',
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
        'If this query is a follow-up within the previous context window (or a subset like narrowing by app), set "skip_context" = true; you MAY copy those exact ISO datetimes into start_local/end_local when appropriate.',
      );
      lines.add(
        'If this is NOT a follow-up, set skip_context=false. You MAY compute start_local/end_local when confident, but do NOT default to the current day when uncertain.',
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
      '- 对任意 intent，start_local/end_local 都是可选字段：仅在你有把握时填写（ISO-8601，含偏移）。不确定时请留空，不要默认到“当前日期”。',
      '- 当日期/时间存在歧义或信息不足时，可返回 error 并保持 start_local/end_local 为空。',
      '- 若用户使用相对时间表达，也要换算为本地具体日期时间并填入。',
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
