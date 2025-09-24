import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ai_chat_service.dart';
import 'ai_settings_service.dart';
import 'screenshot_database.dart';

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

  /// 生成或返回已有的每日总结
  Future<Map<String, dynamic>?> getOrGenerate(String dateKey, {bool force = false}) async {
    if (!force) {
      final existed = await _db.getDailySummary(dateKey);
      if (existed != null) return existed;
    }
    return await generateForDate(dateKey);
  }

  /// 生成某日总结（强制重算）
  Future<Map<String, dynamic>?> generateForDate(String dateKey) async {
    final range = _dayRangeMillis(dateKey);
    if (range == null) return null;

    final segments = await _db.listSegmentsWithResultsBetween(
      startMillis: range[0],
      endMillis: range[1],
    );
    // 仅取 structured_json.overall_summary 作为上下文
    final prompt = await _buildDailyPrompt(dateKey, segments);

    final resp = await _chat.sendMessageOneShot(prompt);
    final raw = _stripFences(resp.content.trim());

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
    } catch (_) {
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

  /// 默认每日总结提示词（JSON输出，仅 overall_summary 与 timeline）
  static const String _defaultDailyPrompt = '''
你是一位高质量的中文日总结助手。基于我提供的“当天多个时间段的 overall_summary（仅用于上下文）”，请生成清晰的“当日总结”并提供简洁的时间线（不需要逐段逐句复述原文）。
要求：
- 仅输出一个 JSON 对象，不要附加解释，也不要输出 JSON 之外的 Markdown；
- 重点：先输出 overall_summary（Markdown 文本，禁止使用代码块围栏```）：
  - 第一段为无标题的整段总结，概括当天的主题、节奏与收获；
  - 随后可使用若干小节（使用 Markdown 小标题）组织信息，如“## 关键操作”“## 主要活动”“## 重点内容”等；
  - 内容应避免流水账，尽可能提炼与归纳，保留关键信息，条理清晰；
- 然后输出 timeline[]（事件时间线），按时间升序列出 5-12 条“关键片段”，每条结构：
  { "time": "HH:mm:ss-HH:mm:ss", "summary": "一句话行为（可用简短 Markdown 强调）" }
- 禁止输出图片与引用图片地址；
- 如果上下文非常少，也要保持格式完整，timeline 可减少条目但不要为空。

仅输出以下字段（不要省略字段名）：
{
  "overall_summary": "(Markdown) 顶部为无标题总结段落，随后使用小标题与要点组织每天的关键信息",
  "timeline": [
    { "time": "HH:mm:ss-HH:mm:ss", "summary": "..." }
  ]
}
''';
}