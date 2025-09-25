import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_chat_service.dart';
import 'ai_settings_service.dart';
import 'screenshot_database.dart';
import 'flutter_logger.dart';

/// 每日总结服务：
/// - 聚合当天已有“事件AI结果”，仅取 structured_json.overall_summary 作为上下文
/// - 使用独立一次性 AI 请求（不写入会话历史）生成当日总结
/// - 结果写入主库 daily_summaries 表
class DailySummaryService {
  DailySummaryService._internal();
  static final DailySummaryService instance = DailySummaryService._internal();

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  final AIChatService _chat = AIChatService.instance;
  final AISettingsService _settings = AISettingsService.instance;

  // 原生交互通道：用于调度/触发系统通知
  static const MethodChannel _channel = MethodChannel('com.fqyw.screen_memo/accessibility');

  // 自动刷新定时器：在前台时按计划预生成当天总结
  Timer? _autoRefreshTimer;

  /// 生成或返回已有的每日总结
  Future<Map<String, dynamic>?> getOrGenerate(String dateKey, {bool force = false}) async {
    // ignore: discarded_futures
    FlutterLogger.nativeInfo('DailySummary', 'getOrGenerate date=$dateKey force=$force');
    if (!force) {
      final existed = await _db.getDailySummary(dateKey);
      if (existed != null) {
        // ignore: discarded_futures
        FlutterLogger.nativeInfo('DailySummary', 'cache hit for $dateKey');
        return existed;
      }
    }
    return await generateForDate(dateKey);
  }

  /// 生成某日总结（强制重算）
  Future<Map<String, dynamic>?> generateForDate(String dateKey) async {
    // ignore: discarded_futures
    FlutterLogger.nativeInfo('DailySummary', 'generateForDate begin date=$dateKey');
    final range = _dayRangeMillis(dateKey);
    if (range == null) {
      // ignore: discarded_futures
      FlutterLogger.nativeWarn('DailySummary', 'generateForDate bad dateKey=$dateKey');
      return null;
    }

    final segments = await _db.listSegmentsWithResultsBetween(
      startMillis: range[0],
      endMillis: range[1],
    );
    // ignore: discarded_futures
    FlutterLogger.nativeInfo('DailySummary', 'context segments=${segments.length}');

    // 仅取 structured_json.overall_summary 作为上下文
    final prompt = await _buildDailyPrompt(dateKey, segments);
    // ignore: discarded_futures
    FlutterLogger.nativeDebug('DailySummary', 'prompt length=${prompt.length}');

    final resp = await _chat.sendMessageOneShot(prompt);
    final raw = _stripFences(resp.content.trim());
    // ignore: discarded_futures
    FlutterLogger.nativeInfo('DailySummary', 'AI raw length=${raw.length}');

    Map<String, dynamic>? sj;
    String outputText = raw;
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) {
        sj = j;
        final v = j['overall_summary'];
        if (v is String && v.trim().isNotEmpty) {
          outputText = v.trim();
        }
      }
    } catch (e) {
      // ignore: discarded_futures
      FlutterLogger.nativeWarn('DailySummary', 'non-JSON AI response, use raw; error=$e');
      // 非 JSON 回复：直接存入 output_text
    }

    final model = await _settings.getModel();
    await _db.upsertDailySummary(
      dateKey: dateKey,
      aiProvider: 'openai-compatible',
      aiModel: model,
      outputText: outputText,
      structuredJson: sj == null ? null : jsonEncode(sj),
    );
    // 生成后将“通知简报”写入原生缓存，供闹钟触达时使用一致内容（避免英文兜底）
    try {
      String briefText = '';
      // 优先 structured_json.notification_brief
      final nb = sj?['notification_brief'];
      if (nb is String && nb.trim().isNotEmpty) {
        briefText = nb.trim();
      } else {
        // 回退 overall_summary/输出文本首句
        String sum = '';
        final ov = sj?['overall_summary'];
        if (ov is String && ov.trim().isNotEmpty) {
          sum = ov.trim();
        } else {
          sum = outputText.trim();
        }
        final idx = sum.indexOf(RegExp(r'[。.!?！？]'));
        briefText = idx > 0 ? sum.substring(0, idx + 1) : (sum.length > 120 ? (sum.substring(0, 120) + '…') : sum);
      }
      if (briefText.isNotEmpty) {
        await _channel.invokeMethod('setDailyBrief', {
          'dateKey': dateKey,
          'brief': briefText,
        });
        // ignore: discarded_futures
        FlutterLogger.nativeInfo('DailySummary', 'setDailyBrief cached len=${briefText.length}');
      }
    } catch (e) {
      // ignore: discarded_futures
      FlutterLogger.nativeWarn('DailySummary', 'setDailyBrief failed: $e');
    }
    // ignore: discarded_futures
    FlutterLogger.nativeInfo('DailySummary', 'upsert ok model=$model outLen=${outputText.length}');
    return await _db.getDailySummary(dateKey);
  }

  /// 获取某日的段落（带结果），供页面渲染时间线兜底
  Future<List<Map<String, dynamic>>> getSegmentsForDay(String dateKey) async {
    final range = _dayRangeMillis(dateKey);
    if (range == null) return <Map<String, dynamic>>[];
    return await _db.listSegmentsWithResultsBetween(
      startMillis: range[0],
      endMillis: range[1],
    );
  }

  Future<String> _buildDailyPrompt(String dateKey, List<Map<String, dynamic>> segments) async {
    final custom = await _settings.getPromptDaily();
    final header = custom ?? _defaultDailyPrompt;

    final sb = StringBuffer();
    sb.writeln(header);
    sb.writeln();
    sb.writeln('日期: $dateKey');
    sb.writeln('上下文（仅用于总结的 overall_summary，禁止逐句复述原文）：');

    int count = 0;
    for (final seg in segments) {
      final start = _fmtHms((seg['start_time'] as int?) ?? 0);
      final end = _fmtHms((seg['end_time'] as int?) ?? 0);
      final ov = _extractOverallSummary(seg);
      if (ov.isEmpty) continue;
      // 控制单条上下文长度，避免过长
      final clipped = ov.length > 800 ? (ov.substring(0, 800) + '…') : ov;
      sb.writeln('- [$start-$end] $clipped');
      count++;
      if (count >= 200) break; // 保险上限
    }

    return sb.toString();
  }

  String _extractOverallSummary(Map<String, dynamic> seg) {
    // 仅允许 structured_json.overall_summary，严格不回退其他字段
    final rawJson = (seg['structured_json'] as String?) ?? '';
    if (rawJson.isEmpty) return '';
    try {
      final j = jsonDecode(rawJson);
      if (j is Map && j['overall_summary'] is String) {
        final s = (j['overall_summary'] as String).trim();
        if (s.isNotEmpty) return s;
      }
    } catch (_) {}
    return '';
  }

  List<int>? _dayRangeMillis(String dateKey) {
    try {
      final parts = dateKey.split('-');
      if (parts.length != 3) return null;
      final y = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final d = int.parse(parts[2]);
      final start = DateTime(y, m, d, 0, 0, 0);
      final end = DateTime(y, m, d, 23, 59, 59);
      return [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    } catch (_) {
      return null;
    }
  }

  String _fmtHms(int ms) {
    if (ms <= 0) return '--:--:--';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
    }

  String _stripFences(String s) {
    // 去除可能的三引号代码块
    final trimmed = s.trim();
    if (trimmed.startsWith('```')) {
      // ```json\n...\n``` 或 ```\n...\n```
      final idx = trimmed.indexOf('\n');
      final rest = idx >= 0 ? trimmed.substring(idx + 1) : trimmed;
      final end = rest.lastIndexOf('```');
      if (end >= 0) return rest.substring(0, end).trim();
      return rest.trim();
    }
    return trimmed;
  }

  /// 获取今日通知用的简短文本（优先 structured_json.notification_brief，回退为摘要首句）
  Future<String> getNotificationBrief(String dateKey) async {
    // ignore: discarded_futures
    FlutterLogger.nativeDebug('DailySummary', 'getNotificationBrief date=$dateKey');
    final daily = await _db.getDailySummary(dateKey);
    if (daily == null) {
      // ignore: discarded_futures
      FlutterLogger.nativeWarn('DailySummary', 'getNotificationBrief: no daily row for $dateKey');
      return '';
    }
    Map<String, dynamic>? sj;
    final raw = (daily['structured_json'] as String?) ?? '';
    if (raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is Map<String, dynamic>) sj = j;
      } catch (_) {}
    }
    String firstSentence(String s) {
      if (s.isEmpty) return s;
      final idx = s.indexOf(RegExp(r'[。.!?！？]'));
      if (idx > 0) return s.substring(0, idx + 1);
      return s.length > 120 ? (s.substring(0, 120) + '…') : s;
    }
    // 1) notification_brief
    final brief = sj?['notification_brief'];
    if (brief is String && brief.trim().isNotEmpty) {
      final out = brief.trim();
      // ignore: discarded_futures
      FlutterLogger.nativeInfo('DailySummary', 'brief from structured_json len=${out.length}');
      return out;
    }
    // 2) 回退 overall_summary 的首句
    String sum = '';
    final ov = sj?['overall_summary'];
    if (ov is String && ov.trim().isNotEmpty) {
      sum = ov.trim();
    } else {
      final rawOut = (daily['output_text'] as String?)?.trim() ?? '';
      if (rawOut.toLowerCase() != 'null') sum = rawOut;
    }
    final result = firstSentence(sum);
    // ignore: discarded_futures
    FlutterLogger.nativeInfo('DailySummary', 'brief from fallback len=${result.length}');
    return result;
  }

  /// 立即触发一次“今日总结”通知（若无当日结果则尽量使用已有摘要）
  Future<bool> triggerNotificationNow(String dateKey) async {
    try {
      // ignore: discarded_futures
      FlutterLogger.nativeInfo('DailySummary', 'triggerNotificationNow date=$dateKey');
      final brief = (await getNotificationBrief(dateKey)).trim();
      if (brief.isEmpty) {
        // ignore: discarded_futures
        FlutterLogger.nativeWarn('DailySummary', 'triggerNotificationNow: empty brief for $dateKey');
        return false;
      }
      // 将简报写入原生侧缓存，便于闹钟触达时使用中文内容
      try {
        await _channel.invokeMethod('setDailyBrief', {
          'dateKey': dateKey,
          'brief': brief,
        });
      } catch (_) {}
      final title = '今日总结 $dateKey';
      // 首选大文本通知（heads-up 条件满足时可弹横幅）
      final ok2 = await _channel.invokeMethod('showNotification', {
        'title': title,
        'message': brief,
      });
      // ignore: discarded_futures
      FlutterLogger.nativeInfo('DailySummary', 'showNotification result=$ok2');
      if (ok2 == true) return true;
      // 回退为简单通知
      final ok = await _channel.invokeMethod('showSimpleNotification', {
        'title': title,
        'message': brief,
      });
      // ignore: discarded_futures
      FlutterLogger.nativeInfo('DailySummary', 'showSimpleNotification result=$ok');
      return ok == true;
    } catch (e) {
      // ignore: discarded_futures
      FlutterLogger.nativeError('DailySummary', 'triggerNotification error: $e');
      return false;
    }
  }

  /// 调度每日提醒（交由原生层实现，hour/minute 为 24 小时制；enabled=false 取消）
  Future<bool> scheduleDailyNotification({
    required int hour,
    required int minute,
    required bool enabled,
  }) async {
    try {
      // ignore: discarded_futures
      FlutterLogger.nativeInfo('DailySummary', 'scheduleDailyNotification enabled=$enabled time=$hour:$minute');
      final res = await _channel.invokeMethod('scheduleDailySummaryNotification', {
        'hour': hour,
        'minute': minute,
        'enabled': enabled,
      });
      // ignore: discarded_futures
      FlutterLogger.nativeInfo('DailySummary', 'scheduleDailyNotification result=$res');
      return res == true;
    } catch (e) {
      // ignore: discarded_futures
      FlutterLogger.nativeError('DailySummary', 'scheduleDailyNotification error: $e');
      return false;
    }
  }

  /// 刷新“自动预生成”调度：
  /// - 每天 08:00、12:00、17:00 自动更新一次
  /// - 若开启每日提醒，则在提醒时间的前 1 分钟再自动更新一次（确保内容新鲜）
  /// 说明：该调度依赖应用在前台运行；若应用未运行，则由原生闹钟按既定时间展示兜底通知。
  Future<void> refreshAutoRefreshSchedule() async {
    try {
      _autoRefreshTimer?.cancel();
      final prefs = await SharedPreferences.getInstance();
      final bool enabled = prefs.getBool('daily_notify_enabled') ?? true;
      final int hour = (prefs.getInt('daily_notify_hour') ?? 22).clamp(0, 23);
      final int minute = (prefs.getInt('daily_notify_minute') ?? 0).clamp(0, 59);

      final DateTime now = DateTime.now();

      // 固定时间点候选（08:00、12:00、17:00）
      final List<DateTime> candidates = <DateTime>[];
      for (final pair in const <List<int>>[
        <int>[8, 0],
        <int>[12, 0],
        <int>[17, 0],
      ]) {
        DateTime t = DateTime(now.year, now.month, now.day, pair[0], pair[1]);
        if (!t.isAfter(now)) {
          t = t.add(const Duration(days: 1));
        }
        candidates.add(t);
      }

      // 提醒前 1 分钟（若启用）
      if (enabled) {
        DateTime pre = DateTime(now.year, now.month, now.day, hour, minute)
            .subtract(const Duration(minutes: 1));
        if (!pre.isAfter(now)) {
          final DateTime tm = now.add(const Duration(days: 1));
          pre = DateTime(tm.year, tm.month, tm.day, hour, minute)
              .subtract(const Duration(minutes: 1));
        }
        candidates.add(pre);
      }

      // 选择最近一次
      candidates.sort((a, b) => a.compareTo(b));
      if (candidates.isEmpty) return;
      final DateTime nextAt = candidates.first;
      final Duration delay = nextAt.difference(now);

      // 日志
      // ignore: discarded_futures
      FlutterLogger.nativeInfo('DailySummary', 'auto-refresh scheduled at ${nextAt.toIso8601String()} (in ${delay.inSeconds}s)');

      _autoRefreshTimer = Timer(delay, () async {
        try {
          final String key = _dateKey(nextAt);
          await generateForDate(key); // 内部已写入通知用 brief
        } catch (e) {
          // ignore: discarded_futures
          FlutterLogger.nativeWarn('DailySummary', 'auto-refresh generate failed: $e');
        } finally {
          // 继续调度下一次
          // ignore: discarded_futures
          refreshAutoRefreshSchedule();
        }
      });
    } catch (e) {
      // ignore: discarded_futures
      FlutterLogger.nativeWarn('DailySummary', 'refreshAutoRefreshSchedule failed: $e');
    }
  }

  String _dateKey(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year.toString().padLeft(4, '0')}-${two(dt.month)}-${two(dt.day)}';
  }

  /// 默认每日总结提示词（JSON输出，含 overall_summary、timeline、notification_brief）
  static const String _defaultDailyPrompt = '''
  你是一位严格的中文日总结助手。基于我提供的“当天多个时间段的 overall_summary（仅用于上下文）”，必须生成“完整的当日总结 JSON”，不得提前结束或缺失任何字段或章节。

  输出要求（务必逐条满足）：
  - 仅输出一个 JSON 对象，且可被标准 JSON 解析；不要附加解释/前后缀；不要输出 JSON 之外的 Markdown 或任何其他文本。
  - 字段固定且全部必填：overall_summary、timeline、notification_brief。不得省略、置空或返回 null。
  - overall_summary 为纯 Markdown 文本（禁止使用代码块围栏```），必须包含以下结构：
    1) 第一段：无标题的整段总结，概括当天主题、节奏与收获；
    2) 依次包含这三个二级小节（标题用 Markdown 形式，且顺序固定）：
       "## 关键操作"
       "## 主要活动"
       "## 重点内容"
       每个小节至少 3 条要点（使用 “- ” 无序列表）。如信息不足，也必须保留小节，并给出不低于 1 条的“占位但有意义”的要点（如“无明显关键操作”），禁止删除小节。
  - timeline 为数组，按时间升序列出 5–12 条关键片段；每条结构：
    { "time": "HH:mm:ss-HH:mm:ss", "summary": "一句话行为（可用简短 Markdown 强调）" }
    如果上下文极少，最少也要 1 条，禁止为空。
  - notification_brief 为纯中文短句 1–3 句，不含 Markdown/列表/标题/代码围栏，覆盖当天重点且尽量精炼。
  - 禁止输出图片或图片链接；禁止返回除上述 3 个字段外的任何键；禁止使用 null；所有字符串需去除首尾空白。

  严格输出以下 JSON 结构（键名固定，且全部存在）：
  {
    "overall_summary": "(Markdown) 第一段为无标题整段总结；随后必须依次包含“## 关键操作”“## 主要活动”“## 重点内容”，每节为若干以“- ”开头的列表项",
    "timeline": [
      { "time": "HH:mm:ss-HH:mm:ss", "summary": "..." }
    ],
    "notification_brief": "1-3 句中文纯文本，不含 Markdown"
  }
  ''';
}