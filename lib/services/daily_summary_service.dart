import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// 默认每日总结提示词（JSON输出，含 overall_summary、timeline、notification_brief）
  static const String _defaultDailyPrompt = '''
 你是一位高质量的中文日总结助手。基于我提供的“当天多个时间段的 overall_summary（仅用于上下文）”，请生成清晰的“当日总结”，并提供简洁的时间线及一段用于通知的超短摘要（notification_brief）。
 要求：
 - 仅输出一个 JSON 对象，不要附加解释，也不要输出 JSON 之外的 Markdown；
 - 重点：先输出 overall_summary（Markdown 文本，禁止使用代码块围栏```）：
   - 第一段为无标题的整段总结，概括当天的主题、节奏与收获；
   - 随后可使用若干小节（使用 Markdown 小标题）组织信息，如“## 关键操作”“## 主要活动”“## 重点内容”等；
   - 内容应避免流水账，尽可能提炼与归纳，保留关键信息，条理清晰；
 - 然后输出 timeline[]（事件时间线），按时间升序列出 5-12 条“关键片段”，每条结构：
   { "time": "HH:mm:ss-HH:mm:ss", "summary": "一句话行为（可用简短 Markdown 强调）" }
 - 额外输出 notification_brief（用于通知的简短纯文本，1-3 句中文，避免 Markdown/列表/标题，覆盖当天重点，尽量精炼）；
 - 禁止输出图片与引用图片地址；
 - 如果上下文非常少，也要保持格式完整，timeline 可减少条目但不要为空。
 
 仅输出以下字段（不要省略字段名）：
 {
   "overall_summary": "(Markdown) 顶部为无标题总结段落，随后使用小标题与要点组织每天的关键信息",
   "timeline": [
     { "time": "HH:mm:ss-HH:mm:ss", "summary": "..." }
   ],
   "notification_brief": "纯文本 1-3 句，不含 Markdown，概述当天关键活动"
 }
 ''';
}