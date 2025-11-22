import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import 'ai_chat_service.dart';
import 'ai_settings_service.dart';
import 'ai_providers_service.dart';
import 'flutter_logger.dart';
import 'locale_service.dart';
import 'screenshot_database.dart';

/// 周总结服务：按用户首次使用日起每7天生成一次周总结
/// - 上下文来源：最近7天的 `segments` 结果 + 每日总结（若存在）
/// - 输出：写入主库 weekly_summaries 表
class WeeklySummaryService {
  WeeklySummaryService._internal();
  static final WeeklySummaryService instance = WeeklySummaryService._internal();

  static const Duration _weekLength = Duration(days: 7);
  static const Duration _generationTimeOffset = Duration(hours: 8);
  static const int _maxSegmentsPerDay = 40;
  static const int _maxSegmentLength = 500;
  static const int _maxDailySummaryLength = 1200;

  static const String _prefsFirstDateKey = 'weekly_summary_first_date';
  static const String _prefsCompletedWeeksKey = 'weekly_summary_completed_weeks';
  static const String _prefsLastGeneratedAtKey = 'weekly_summary_last_generated_at';

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  final AIChatService _chat = AIChatService.instance;
  final AISettingsService _settings = AISettingsService.instance;

  Timer? _scheduleTimer;
  bool _processing = false;

  Future<_WeeklySummaryGenerationContext> _prepareWeeklySummaryContext({
    required String weekStartKey,
    required String weekEndKey,
    required WeeklyContext context,
  }) async {
    final String prompt = await _buildWeeklyPrompt(
      weekStartKey,
      weekEndKey,
      context,
    );

    String providerType = 'segments';
    late final String modelUsed;
    final Map<String, dynamic>? ctxRow;
    try {
      ctxRow = await _settings.getAIContextRow('segments');
    } catch (e) {
      throw StateError('Segments AI context lookup failed: $e');
    }

    if (ctxRow == null) {
      throw StateError('Segments AI context not configured');
    }

    final String? ctxModel = (ctxRow['model'] as String?)?.trim();
    if (ctxModel == null || ctxModel.isEmpty) {
      throw StateError('Segments AI context model missing');
    }
    modelUsed = ctxModel;

    final int? providerId = ctxRow['provider_id'] as int?;
    if (providerId == null) {
      throw StateError('Segments AI context provider missing');
    }

    try {
      final provider = await AIProvidersService.instance.getProvider(providerId);
      if (provider == null) {
        throw StateError('Segments AI provider unavailable');
      }
      final String type = provider.type.trim();
      if (type.isNotEmpty) {
        providerType = type;
      }
    } catch (e) {
      throw StateError('Segments AI provider fetch failed: $e');
    }

    try {
      await FlutterLogger.nativeInfo(
        'WeeklySummary',
        'prepare week $weekStartKey-$weekEndKey provider=$providerType model=$modelUsed contextEntries=${context.totalEntries}',
      );
    } catch (_) {}

    return _WeeklySummaryGenerationContext(
      weekStartKey: weekStartKey,
      weekEndKey: weekEndKey,
      prompt: prompt,
      providerType: providerType,
      model: modelUsed,
    );
  }

  Future<void> _persistWeeklySummary({
    required _WeeklySummaryGenerationContext ctx,
    required String raw,
  }) async {
    Map<String, dynamic>? structured;
    String outputText = raw;
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        structured = decoded;
        final dynamic overview = decoded['weekly_overview'];
        if (overview is String && overview.trim().isNotEmpty) {
          outputText = overview.trim();
        }
      }
    } catch (_) {
      // 保留原始文本作为输出
    }

    await _db.upsertWeeklySummary(
      weekStartDate: ctx.weekStartKey,
      weekEndDate: ctx.weekEndKey,
      aiProvider: ctx.providerType,
      aiModel: ctx.model,
      outputText: outputText,
      structuredJson: structured == null ? null : jsonEncode(structured),
    );
  }

  /// 刷新调度：
  /// - 若存在过期的周总结则立即生成
  /// - 否则安排下一次定时器
  Future<void> refreshSchedule({bool forceProcess = false}) async {
    _scheduleTimer?.cancel();
    await _processPendingSummaries(force: forceProcess);
  }

  /// 根据周起始日生成（或获取已缓存的）周总结
  Future<Map<String, dynamic>?> generateForWeekStart(String weekStartDate, {bool force = false}) async {
    final DateTime? weekStart = _parseDateKey(weekStartDate);
    if (weekStart == null) return null;
    return await _generateForWeek(weekStart, force: force);
  }

  /// 返回指定周起始日的总结（若存在）
  Future<Map<String, dynamic>?> getWeeklySummaryByStart(String weekStartDate) async {
    return await _db.getWeeklySummary(weekStartDate);
  }

  /// 列出已生成的周总结（按周起始日倒序）
  Future<List<Map<String, dynamic>>> listWeeklySummaries({int? limit, int? offset, bool onlyCompleted = false}) async {
    final List<Map<String, dynamic>> rows = await _db.listWeeklySummaries(limit: limit, offset: offset);
    if (!onlyCompleted) return rows;

    final String todayKey = _dateKey(DateTime.now());
    return rows.where((row) {
      final String? end = (row['week_end_date'] as String?)?.trim();
      if (end == null || end.isEmpty) return false;
      return end.compareTo(todayKey) <= 0;
    }).toList();
  }

  Future<void> _processPendingSummaries({bool force = false}) async {
    if (_processing) return;
    _processing = true;
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      while (true) {
        final _ScheduleState? state = await _computeNextSchedule(prefs);
        if (state == null) {
          _scheduleTimer = null;
          return;
        }
        final DateTime now = DateTime.now();
        final bool shouldGenerate = force || !state.due.isAfter(now);
        if (shouldGenerate) {
          try {
            await _generateForWeek(state.weekStart);
            await prefs.setInt(_prefsCompletedWeeksKey, state.completedWeeks + 1);
            await prefs.setInt(_prefsLastGeneratedAtKey, DateTime.now().millisecondsSinceEpoch);
            force = true;
          } catch (e, stackTrace) {
            try {
              await FlutterLogger.nativeWarn('WeeklySummary', 'generate failed: $e');
              await FlutterLogger.nativeDebug('WeeklySummary', stackTrace.toString());
            } catch (_) {}
            break; // 避免死循环，待下次重新调度
          }
          continue; // 检查是否仍有未完成的周
        }

        final Duration delay = state.due.difference(now);
        _scheduleTimer = Timer(delay, () {
          refreshSchedule(forceProcess: true);
        });
        break;
      }
    } finally {
      _processing = false;
    }
  }

  Future<_ScheduleState?> _computeNextSchedule(SharedPreferences prefs) async {
    final String? firstDateKey = await _ensureFirstDate(prefs);
    if (firstDateKey == null || firstDateKey.isEmpty) return null;

    final DateTime? firstDate = _parseDateKey(firstDateKey);
    if (firstDate == null) return null;

    int completedWeeks = prefs.getInt(_prefsCompletedWeeksKey) ?? 0;
    if (completedWeeks < 0) completedWeeks = 0;

    // 计算下一周的起始日
    final DateTime weekStart = firstDate.add(Duration(days: completedWeeks * 7));
    final DateTime weekEnd = weekStart.add(const Duration(days: 6));
    final DateTime due = weekStart.add(_weekLength).add(_generationTimeOffset);

    return _ScheduleState(
      firstDateKey: firstDateKey,
      completedWeeks: completedWeeks,
      weekStart: weekStart,
      weekEnd: weekEnd,
      due: due,
    );
  }

  Future<String?> _ensureFirstDate(SharedPreferences prefs) async {
    String? stored = prefs.getString(_prefsFirstDateKey);
    final String? earliest = await _findEarliestAvailableDateKey();
    if (earliest == null) return stored;

    if (stored == null) {
      await prefs.setString(_prefsFirstDateKey, earliest);
      await prefs.setInt(_prefsCompletedWeeksKey, 0);
      return earliest;
    }

    if (_compareDateKey(earliest, stored) < 0) {
      await prefs.setString(_prefsFirstDateKey, earliest);
      await prefs.setInt(_prefsCompletedWeeksKey, 0);
      return earliest;
    }

    return stored;
  }

  Future<String?> _findEarliestAvailableDateKey() async {
    final List<Map<String, dynamic>> days = await _db.listAvailableDaysGlobal();
    if (days.isEmpty) return null;
    final Map<String, dynamic>? last = days.last;
    final String? key = last?['date'] as String?;
    return key;
  }

  Future<Map<String, dynamic>?> _generateForWeek(DateTime weekStart, {bool force = false}) async {
    final String weekStartKey = _dateKey(weekStart);
    final String weekEndKey = _dateKey(weekStart.add(const Duration(days: 6)));

    if (!force) {
      final Map<String, dynamic>? existed = await _db.getWeeklySummary(weekStartKey);
      if (existed != null) return existed;
    }

    final WeeklyContext context = await _buildWeeklyContext(weekStart);
    if (context.totalEntries == 0) {
      final Map<String, dynamic> fallback = {
        'weekly_overview': '暂无足够的数据生成周总结。',
        'daily_breakdowns': const <Map<String, dynamic>>[],
        'action_items': const <String>[],
        'notification_brief': '本周暂无记录。',
      };
      await _db.upsertWeeklySummary(
        weekStartDate: weekStartKey,
        weekEndDate: weekEndKey,
        aiProvider: 'local',
        aiModel: 'fallback',
        outputText: fallback['weekly_overview'] as String,
        structuredJson: jsonEncode(fallback),
      );
      return await _db.getWeeklySummary(weekStartKey);
    }

    final _WeeklySummaryGenerationContext ctx =
        await _prepareWeeklySummaryContext(
      weekStartKey: weekStartKey,
      weekEndKey: weekEndKey,
      context: context,
    );

    final AIMessage response = await _chat.sendMessageOneShot(
      ctx.prompt,
      context: 'segments',
      timeout: null,
    );

    final String raw = _stripFences(response.content.trim());
    await _persistWeeklySummary(ctx: ctx, raw: raw);
    return await _db.getWeeklySummary(weekStartKey);
  }

  Future<AIStreamingSession?> streamGenerateForWeekStart(
    String weekStartDate, {
    bool force = false,
  }) async {
    final DateTime? weekStart = _parseDateKey(weekStartDate);
    if (weekStart == null) {
      return null;
    }

    if (!force) {
      final Map<String, dynamic>? existed =
          await _db.getWeeklySummary(weekStartDate);
      if (existed != null) {
        return null;
      }
    }

    final WeeklyContext context = await _buildWeeklyContext(weekStart);
    if (context.totalEntries == 0) {
      final String weekEndKey =
          _dateKey(weekStart.add(const Duration(days: 6)));
      final Map<String, dynamic> fallback = {
        'weekly_overview': '暂无足够的数据生成周总结。',
        'daily_breakdowns': const <Map<String, dynamic>>[],
        'action_items': const <String>[],
        'notification_brief': '本周暂无记录。',
      };
      await _db.upsertWeeklySummary(
        weekStartDate: weekStartDate,
        weekEndDate: weekEndKey,
        aiProvider: 'local',
        aiModel: 'fallback',
        outputText: fallback['weekly_overview'] as String,
        structuredJson: jsonEncode(fallback),
      );
      return null;
    }

    final String weekEndKey =
        _dateKey(weekStart.add(const Duration(days: 6)));
    final _WeeklySummaryGenerationContext ctx =
        await _prepareWeeklySummaryContext(
      weekStartKey: weekStartDate,
      weekEndKey: weekEndKey,
      context: context,
    );

    final AIStreamingSession baseSession =
        await _chat.sendMessageStreamedV2WithDisplayOverride(
      'weekly_summary_$weekStartDate',
      ctx.prompt,
      includeHistory: false,
      persistHistory: false,
      context: 'segments',
    );

    final StreamController<AIStreamEvent> controller =
        StreamController<AIStreamEvent>();
    late final StreamSubscription<AIStreamEvent> subscription;
    controller.onCancel = () async {
      await subscription.cancel();
    };
    subscription = baseSession.stream.listen(
      controller.add,
      onError: (Object error, StackTrace stackTrace) {
        controller.addError(error, stackTrace);
        controller.close();
      },
      onDone: () {
        controller.close();
      },
      cancelOnError: false,
    );

    final Future<AIMessage> completed = baseSession.completed.then(
      (AIMessage message) async {
        final String raw = _stripFences(message.content.trim());
        await _persistWeeklySummary(ctx: ctx, raw: raw);
        return message;
      },
    );

    return AIStreamingSession(
      stream: controller.stream,
      completed: completed,
    );
  }

  Future<WeeklyContext> _buildWeeklyContext(DateTime weekStart) async {
    final DateTime weekEnd = weekStart.add(const Duration(days: 6));
    final DateTime rangeEnd = DateTime(weekEnd.year, weekEnd.month, weekEnd.day, 23, 59, 59, 999);
    final List<Map<String, dynamic>> segments = await _db.listSegmentsWithResultsBetween(
      startMillis: weekStart.millisecondsSinceEpoch,
      endMillis: rangeEnd.millisecondsSinceEpoch,
    );

    final Map<String, List<_SegmentSnippet>> grouped = <String, List<_SegmentSnippet>>{};
    for (final Map<String, dynamic> seg in segments) {
      final String? summary = _extractSegmentSummary(seg);
      if (summary == null || summary.isEmpty) continue;
      final int start = (seg['start_time'] as int?) ?? 0;
      final int end = (seg['end_time'] as int?) ?? 0;
      final DateTime dt = DateTime.fromMillisecondsSinceEpoch(start == 0 ? end : start);
      if (dt.isAfter(rangeEnd)) continue;
      final String dateKey = _dateKey(DateTime(dt.year, dt.month, dt.day));
      final List<_SegmentSnippet> list = grouped.putIfAbsent(dateKey, () => <_SegmentSnippet>[]);
      if (list.length >= _maxSegmentsPerDay) continue;
      final String range = _formatRange(start, end);
      list.add(_SegmentSnippet(timeRange: range, summary: summary));
    }

    final List<_WeeklyDayContext> days = <_WeeklyDayContext>[];
    int totalEntries = 0;
    for (int i = 0; i < 7; i++) {
      final DateTime day = weekStart.add(Duration(days: i));
      final String key = _dateKey(day);
      final Map<String, dynamic>? daily = await _db.getDailySummary(key);
      final String? dailyText = _extractDailyOverall(daily);
      final List<_SegmentSnippet> snippets = grouped[key] ?? <_SegmentSnippet>[];
      totalEntries += (snippets.length + (dailyText == null || dailyText.isEmpty ? 0 : 1));
      days.add(
        _WeeklyDayContext(
          dateKey: key,
          dailySummary: dailyText,
          segments: snippets,
        ),
      );
    }

    return WeeklyContext(days: days, totalEntries: totalEntries);
  }

  Future<String> _buildWeeklyPrompt(
    String weekStartKey,
    String weekEndKey,
    WeeklyContext context,
  ) async {
    final Locale? currentLocale = LocaleService.instance.locale;
    final Locale deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final String lang = (currentLocale ?? deviceLocale).languageCode.toLowerCase();
    final bool isZh = lang.startsWith('zh');
    final bool isJa = lang.startsWith('ja');
    final bool isKo = lang.startsWith('ko');
    final Locale promptLocale = isZh
        ? const Locale('zh')
        : (isJa
            ? const Locale('ja')
            : (isKo ? const Locale('ko') : const Locale('en')));
    final String languagePolicy = lookupAppLocalizations(promptLocale).aiSystemPromptLanguagePolicy;
    final String defaultTemplate = isZh
        ? _defaultWeeklyPromptZh
        : (isJa
            ? _defaultWeeklyPromptJa
            : (isKo ? _defaultWeeklyPromptKo : _defaultWeeklyPromptEn));

    final String? customAddon = await _settings.getPromptWeekly();
    final String? trimmedAddon = customAddon?.trim();
    final bool useZhMarkers = isZh;
    final String beginMarker = useZhMarkers ? '【重要附加说明（开始）】' : '***IMPORTANT EXTRA INSTRUCTIONS (BEGIN)***';
    final String endMarker = useZhMarkers ? '【重要附加说明（结束）】' : '***IMPORTANT EXTRA INSTRUCTIONS (END)***';
    final String header = (trimmedAddon != null && trimmedAddon.isNotEmpty)
        ? '$languagePolicy\n\n$beginMarker\n$trimmedAddon\n\n$defaultTemplate\n\n$endMarker\n$trimmedAddon'
        : '$languagePolicy\n\n$defaultTemplate';

    final StringBuffer sb = StringBuffer()
      ..writeln(header)
      ..writeln()
      ..writeln('周起始: $weekStartKey')
      ..writeln('周结束: $weekEndKey')
      ..writeln('上下文（按日期归类，包含每日总结与详细动态）:')
      ..writeln();

    for (final _WeeklyDayContext day in context.days) {
      sb.writeln('### ${day.dateKey}');
      if (day.dailySummary != null && day.dailySummary!.trim().isNotEmpty) {
        final String trimmed = day.dailySummary!.trim();
        sb.writeln('每日概览:');
        sb.writeln(_truncate(trimmed, _maxDailySummaryLength));
      } else {
        sb.writeln('每日概览: (缺失)');
      }
      if (day.segments.isEmpty) {
        sb.writeln('- [无记录] 本日未捕获到可用动态');
      } else {
        for (final _SegmentSnippet snip in day.segments) {
          sb.writeln('- [${snip.timeRange}] ${_truncate(snip.summary, _maxSegmentLength)}');
        }
      }
      sb.writeln();
    }

    return sb.toString();
  }

  static String _truncate(String input, int maxLength) {
    if (input.length <= maxLength) return input;
    return input.substring(0, maxLength).trimRight() + '…';
  }

  String? _extractSegmentSummary(Map<String, dynamic> seg) {
    final String rawJson = (seg['structured_json'] as String?) ?? '';
    if (rawJson.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(rawJson);
        if (decoded is Map && decoded['overall_summary'] is String) {
          final String text = (decoded['overall_summary'] as String).trim();
          if (text.isNotEmpty) return text;
        }
      } catch (_) {}
    }
    final String? output = (seg['output_text'] as String?)?.trim();
    if (output != null && output.isNotEmpty && output.toLowerCase() != 'null') return output;
    return null;
  }

  String? _extractDailyOverall(Map<String, dynamic>? daily) {
    if (daily == null) return null;
    final String raw = (daily['structured_json'] as String?) ?? '';
    if (raw.isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map && decoded['overall_summary'] is String) {
          final String text = (decoded['overall_summary'] as String).trim();
          if (text.isNotEmpty) return text;
        }
      } catch (_) {}
    }
    final String? output = (daily['output_text'] as String?)?.trim();
    if (output != null && output.isNotEmpty && output.toLowerCase() != 'null') return output;
    return null;
  }

  String _formatRange(int startMillis, int endMillis) {
    if (startMillis <= 0 && endMillis <= 0) return '--:-- - --:--';
    final DateTime start = DateTime.fromMillisecondsSinceEpoch(startMillis > 0 ? startMillis : endMillis);
    final DateTime end = DateTime.fromMillisecondsSinceEpoch(endMillis > 0 ? endMillis : startMillis);
    return '${_two(start.hour)}:${_two(start.minute)}-${_two(end.hour)}:${_two(end.minute)}';
  }

  String _dateKey(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${_two(dt.month)}-${_two(dt.day)}';
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  int _compareDateKey(String a, String b) {
    return a.compareTo(b);
  }

  DateTime? _parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    try {
      final int y = int.parse(parts[0]);
      final int m = int.parse(parts[1]);
      final int d = int.parse(parts[2]);
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  String _stripFences(String text) {
    final String trimmed = text.trim();
    if (!trimmed.startsWith('```')) return trimmed;
    final int firstLineBreak = trimmed.indexOf('\n');
    final String rest = firstLineBreak >= 0 ? trimmed.substring(firstLineBreak + 1) : trimmed;
    final int endIndex = rest.lastIndexOf('```');
    if (endIndex >= 0) {
      return rest.substring(0, endIndex).trim();
    }
    return rest.trim();
  }

  static const String _defaultWeeklyPromptZh = '''
你是一位严格的中文周总结助手。根据我提供的「按日期划分的每日摘要与动态列表」，生成结构化的 JSON 周总结。

输出要求：
- 仅输出一个可被标准 JSON 解析的对象，不要附加解释或额外文本。
- 必须包含以下字段且不可为 null：weekly_overview、daily_breakdowns、action_items、notification_brief。
- weekly_overview：使用 Markdown，需满足：
  1) 开头段落不少于 3 句，综合描述本周主题、节奏与关键产出，并引用至少一个具体日期或时间段。
  2) 依次包含“## 本周亮点”“## 关键推进”“## 风险与待改进”三个小节，每节至少 3 条要点；每条要点采用 `- **[日期/来源]** 内容` 形式，内容需说明发生背景、影响及量化细节（若上下文支持）。
  3) 对于跨越多日的趋势、重复出现的风险或延误事项，请在对应要点中显式指出关联日期或次数。
  4) 若信息不足以支撑 3 条要点，可写明“暂无更多记录，但需关注...”，但不得输出空数组。
- daily_breakdowns：数组，按日期升序列出 7 条对象，每条包含：
  { "date_key": "YYYY-MM-DD", "headline": "一句话标题", "highlights": ["简要要点", ...] }
  每个 highlights 至少 3 条，优先引用时间范围或应用来源，并说明结论或下一步；如当日无有效内容，使用“暂无新的可见记录”。
- action_items：长度 4-6 的数组，每条以动词开头，包含可执行步骤、预期结果，并在括号中标注依据的日期或事件。
- notification_brief：1-2 句纯文本（不含 Markdown），提炼最紧急的提醒并标注相关日期或触发事件。
- 禁止输出图片、代码块或额外字段；所有字符串需去除首尾空白，保证 JSON 语法严格正确。
''';

  static const String _defaultWeeklyPromptEn = '''
You are a disciplined weekly review assistant. Based on the grouped daily summaries and activity snippets I provide, produce a structured JSON weekly report.

Output requirements:
- Return a single JSON object that can be parsed by standard JSON libraries; do not add explanations or extra text.
- Required non-null fields: weekly_overview, daily_breakdowns, action_items, notification_brief.
- weekly_overview: Markdown content with the following structure:
  1) Opening paragraph of at least three sentences summarizing the week's theme, cadence, and key outcomes, referencing at least one explicit date or time range.
  2) Sections in order with "##" headings: "## Weekly Highlights", "## Key Progress", "## Risks & Improvements". Each section must contain at least three bullet points using the format `- **[Date/Source]** insight`, describing context, impact, and quantitative detail when available.
  3) Call out cross-day trends, recurring blockers, or delayed items by explicitly citing related dates or counts.
  4) If evidence is insufficient for three bullet points, include a synthesized observation explaining the gap (for example, `- **[N/A]** No additional records, monitor ...`) rather than leaving the list short.
- daily_breakdowns: array of exactly seven objects sorted by date ASC. Each object:
  { "date_key": "YYYY-MM-DD", "headline": "One-sentence headline", "highlights": ["Concise point", ...] }
  Provide at least three concise bullet points per day, preferring entries that reference time ranges/apps and end with an insight or next step; if a day has no material, include "No new records available".
- action_items: array of 4–6 actionable recommendations for the coming week. Start each item with a verb, include the concrete next step and expected outcome, and cite the supporting date/event in parentheses.
- notification_brief: 1–2 plain sentences (no Markdown) capturing the most urgent takeaway and referencing the relevant date/event.
- Do not output images, code fences, or extra fields; trim all strings and ensure valid JSON.
''';

  static const String _defaultWeeklyPromptJa = '''
あなたは厳密な週次レビューアシスタントです。提供された日ごとの概要と活動記録をもとに、構造化された JSON 形式の週次レポートを作成してください。

出力要件：
- 標準的な JSON として解析可能なオブジェクトを 1 つだけ返し、説明や余分な文字列を追加しないこと。
- 必須フィールド（null 禁止）：weekly_overview、daily_breakdowns、action_items、notification_brief。
- weekly_overview：Markdown 形式。以下を満たすこと：
  1) 見出しなしの冒頭段落は 3 文以上とし、週全体のテーマ・ペース・主要成果をまとめ、少なくとも 1 件の具体的な日付または時間帯を言及する。
  2) 「## 今週のハイライト」「## 主要な前進」「## リスクと改善点」の順にセクションを配置し、各セクションに 3 件以上の箇条書きを含める。各項目は `- **[日付/情報源]** 内容` の形式で、背景・影響・可能なら数値まで記述する。
  3) 複数日にまたがるトレンドや繰り返し発生した課題は、関連する日付や回数を明示する。
  4) 情報が不足して 3 件を満たせない場合でも、理由を説明する補足（例：「- **[N/A]** 追加記録なし。継続監視が必要」）を入れ、空配列にはしないこと。
- daily_breakdowns：日付昇順の 7 件の配列。各要素：
  { "date_key": "YYYY-MM-DD", "headline": "1文サマリー", "highlights": ["短いポイント", ...] }
  各日の highlights は最低 3 件とし、時間帯やアプリ由来を優先して記し、最後に所感または次のアクションを示す。内容がない場合は「新しい記録はありません」を入れる。
- action_items：翌週に向けた実行可能な提案を 4〜6 件列挙。すべて動詞で始め、具体的なステップと期待成果、根拠となる日付・イベントを括弧で示す。
- notification_brief：Markdown を含まない 1〜2 文で、週の最重要メッセージをまとめ、関連する日付・イベントを明記する。
- 追加フィールドやコードブロックは禁止し、すべての文字列の前後空白を除去し、正しい JSON を維持すること。
''';

  static const String _defaultWeeklyPromptKo = '''
당신은 주간 리뷰 어시스턴트입니다. 제공된 날짜별 요약과 활동 목록을 기반으로 구조화된 JSON 형식의 주간 보고서를 생성하세요.

출력 규칙:
- 표준 JSON으로 파싱 가능한 객체를 딱 한 개만 반환하고, 설명이나 추가 텍스트를 붙이지 마세요.
- 필수 필드(빈 값/ null 금지): weekly_overview, daily_breakdowns, action_items, notification_brief.
- weekly_overview: Markdown 형식으로 다음 요구 사항을 충족합니다.
  1) 제목 없는 첫 단락을 3문장 이상 작성하여 한 주의 흐름, 속도, 주요 성과를 요약하고 최소 한 개 이상의 구체적인 날짜 또는 시간대를 언급합니다.
  2) "## 주간 하이라이트", "## 핵심 진전", "## 리스크와 개선" 순서로 섹션을 배치하고, 각 섹션에 최소 3개의 불릿을 작성합니다. 각 불릿은 `- **[날짜/출처]** 내용` 형식을 사용하며, 배경·영향·가능한 경우 수치 정보를 포함합니다.
  3) 여러 날에 걸친 추세나 반복된 이슈는 관련 날짜나 발생 횟수를 명확히 표기하세요.
  4) 근거가 부족해 3개를 채우지 못할 경우에도 공백으로 두지 말고 “- **[N/A]** 추가 기록 없음. 모니터링 필요”와 같이 이유를 설명하세요.
- daily_breakdowns: 날짜 오름차순의 7개 객체 배열. 각 객체는
  { "date_key": "YYYY-MM-DD", "headline": "한 문장 요약", "highlights": ["간결한 포인트", ...] }
  형태이며, highlights는 최소 3개를 작성합니다. 시간대나 앱 출처를 우선적으로 언급하고, 마지막에 인사이트 또는 다음 행동을 명시하세요. 내용이 없으면 "새로운 기록 없음"을 넣으세요.
- action_items: 다음 주를 위한 실행 가능한 제안 4~6개. 모든 항목을 동사로 시작하고, 구체적 단계와 기대 결과, 근거가 된 날짜/이벤트를 괄호로 표시하세요.
- notification_brief: Markdown 없는 1~2개의 문장으로 가장 긴급한 메시지를 요약하고 관련 날짜/사건을 언급하세요.
- 추가 필드, 이미지, 코드 블록은 금지하며 모든 문자열의 앞뒤 공백을 제거하고 JSON 문법을 지키세요.
''';
}

class _WeeklySummaryGenerationContext {
  const _WeeklySummaryGenerationContext({
    required this.weekStartKey,
    required this.weekEndKey,
    required this.prompt,
    required this.providerType,
    required this.model,
  });

  final String weekStartKey;
  final String weekEndKey;
  final String prompt;
  final String providerType;
  final String model;
}

class _ScheduleState {
  _ScheduleState({
    required this.firstDateKey,
    required this.completedWeeks,
    required this.weekStart,
    required this.weekEnd,
    required this.due,
  });

  final String firstDateKey;
  final int completedWeeks;
  final DateTime weekStart;
  final DateTime weekEnd;
  final DateTime due;
}

class WeeklyContext {
  WeeklyContext({required this.days, required this.totalEntries});

  final List<_WeeklyDayContext> days;
  final int totalEntries;
}

class _WeeklyDayContext {
  _WeeklyDayContext({required this.dateKey, required this.dailySummary, required this.segments});

  final String dateKey;
  final String? dailySummary;
  final List<_SegmentSnippet> segments;
}

class _SegmentSnippet {
  _SegmentSnippet({required this.timeRange, required this.summary});

  final String timeRange;
  final String summary;
}

