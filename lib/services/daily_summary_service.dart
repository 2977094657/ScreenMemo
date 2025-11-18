import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../constants/user_settings_keys.dart';
import 'ai_chat_service.dart';
import 'ai_settings_service.dart';
import 'ai_providers_service.dart';
import 'screenshot_database.dart';
import 'flutter_logger.dart';
import 'locale_service.dart';
import 'user_settings_service.dart';

String _cleanMorningText(String input) {
  var text = input.trim();
  if (text.isEmpty) return text;
  const prefixes = ['- ', '* ', '• ', '-\t', '*\t', '•\t', '-', '*', '•'];
  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length).trimLeft();
      break;
    }
  }
  text = text.replaceFirst(RegExp(r'^\d+[\.、]\s*'), '');
  text = text.replaceFirst(RegExp(r'^[A-Za-z]\)\s*'), '');
  text = text.replaceFirst(RegExp(r'^[A-Za-z][\.、]\s*'), '');
  text = text.replaceAll(RegExp(r'\s+'), ' ');
  return text.trim();
}

String? _stringOrNull(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value
        .whereType<String>()
        .map(_cleanMorningText)
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
  if (value is String) {
    final cleaned = _cleanMorningText(value);
    return cleaned.isEmpty ? const <String>[] : <String>[cleaned];
  }
  return const <String>[];
}

String _deriveMorningTitle(String input) {
  final cleaned = _cleanMorningText(input);
  if (cleaned.isEmpty) return '';
  final match = RegExp(r'[。！？?!:：\n\r]').firstMatch(cleaned);
  final candidate = match == null ? cleaned : cleaned.substring(0, match.start);
  if (candidate.length > 32) {
    return candidate.substring(0, 32).trimRight() + '…';
  }
  return candidate;
}

enum DailySummaryNotificationSlot {
  morning,
  noon,
  evening,
  night,
  finalReminder,
}

class MorningInsightEntry {
  MorningInsightEntry({
    required String title,
    String? summary,
    List<String>? actions,
    List<String>? tags,
  })  : title = _cleanMorningText(title),
        summary = summary == null ? null : _cleanMorningText(summary),
        actions = (actions ?? const <String>[])
            .map(_cleanMorningText)
            .where((e) => e.isNotEmpty)
            .toList(growable: false),
        tags = (tags ?? const <String>[])
            .map(_cleanMorningText)
            .where((e) => e.isNotEmpty)
            .toList(growable: false);

  final String title;
  final String? summary;
  final List<String> actions;
  final List<String> tags;

  bool get hasSummary => summary != null && summary!.isNotEmpty;
  bool get hasActions => actions.isNotEmpty;
  bool get isMeaningful => title.isNotEmpty || hasSummary || hasActions;

  String get displayTitle {
    if (title.isNotEmpty) return title;
    if (hasSummary) return _deriveMorningTitle(summary!);
    if (hasActions) return _deriveMorningTitle(actions.first);
    return '';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        if (hasSummary) 'summary': summary,
        if (hasActions) 'actions': actions,
        if (tags.isNotEmpty) 'tags': tags,
      };

  factory MorningInsightEntry.fromJson(Map<String, dynamic> json) {
    final String? rawTitle = _stringOrNull(json['title']) ??
        _stringOrNull(json['headline']) ??
        _stringOrNull(json['focus']) ??
        _stringOrNull(json['label']) ??
        _stringOrNull(json['name']);
    final String? rawSummary = _stringOrNull(json['summary']) ??
        _stringOrNull(json['description']) ??
        _stringOrNull(json['insight']) ??
        _stringOrNull(json['note']) ??
        _stringOrNull(json['context']) ??
        _stringOrNull(json['why']);
    final List<String> actions = _stringList(
      json['actions'] ??
          json['steps'] ??
          json['suggestions'] ??
          json['tasks'] ??
          json['followUps'] ??
          json['follow_ups'],
    );
    final List<String> tags = _stringList(json['tags'] ?? json['keywords'] ?? json['labels']);

    String resolvedTitle = rawTitle != null ? _cleanMorningText(rawTitle) : '';
    final String? resolvedSummary = rawSummary == null ? null : _cleanMorningText(rawSummary);

    if (resolvedTitle.isEmpty) {
      if (resolvedSummary != null && resolvedSummary.isNotEmpty) {
        resolvedTitle = _deriveMorningTitle(resolvedSummary);
      } else if (actions.isNotEmpty) {
        resolvedTitle = _deriveMorningTitle(actions.first);
      }
    }

    final String fallbackTitle = resolvedTitle.isNotEmpty
        ? resolvedTitle
        : (resolvedSummary != null && resolvedSummary.isNotEmpty
            ? _deriveMorningTitle(resolvedSummary)
            : (actions.isNotEmpty ? _deriveMorningTitle(actions.first) : ''));

    final String derivedTitle = fallbackTitle.isNotEmpty
        ? fallbackTitle
        : _deriveMorningTitle(resolvedSummary ?? (actions.isNotEmpty ? actions.first : ''));

    final bool meaningful =
        derivedTitle.isNotEmpty || (resolvedSummary != null && resolvedSummary.isNotEmpty) || actions.isNotEmpty;
    if (!meaningful) {
      return MorningInsightEntry(title: '', summary: null);
    }

    return MorningInsightEntry(
      title: derivedTitle.isNotEmpty
          ? derivedTitle
          : (resolvedSummary?.isNotEmpty ?? false)
              ? resolvedSummary!
              : (actions.isNotEmpty ? actions.first : ''),
      summary: resolvedSummary,
      actions: actions,
      tags: tags,
    );
  }

  factory MorningInsightEntry.fromLegacy(String raw) {
    final cleaned = _cleanMorningText(raw);
    final title = _deriveMorningTitle(cleaned);
    return MorningInsightEntry(
      title: title.isNotEmpty ? title : cleaned,
      summary: cleaned.isNotEmpty ? cleaned : null,
    );
  }
}

class MorningInsights {
  final String dateKey;
  final String sourceDateKey;
  final List<MorningInsightEntry> tips;
  final int createdAt;
  final String? rawResponse;

  MorningInsights({
    required this.dateKey,
    required this.sourceDateKey,
    required List<MorningInsightEntry> tips,
    required this.createdAt,
    this.rawResponse,
  }) : tips = List<MorningInsightEntry>.unmodifiable(
            tips.where((element) => element.isMeaningful).toList());

  factory MorningInsights.fromRow(Map<String, dynamic> row) {
    final tipsJson = (row['tips_json'] as String?) ?? '[]';
    List<MorningInsightEntry> tips = const <MorningInsightEntry>[];
    try {
      final decoded = jsonDecode(tipsJson);
      tips = decodeTipsPayload(decoded);
    } catch (_) {}
    return MorningInsights(
      dateKey: (row['date_key'] as String?) ?? '',
      sourceDateKey: (row['source_date_key'] as String?) ?? '',
      tips: tips,
      createdAt: (row['created_at'] as int?) ?? 0,
      rawResponse: row['raw_response'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date_key': dateKey,
      'source_date_key': sourceDateKey,
      'tips': tips.map((e) => e.toJson()).toList(),
      'created_at': createdAt,
      if (rawResponse != null) 'raw_response': rawResponse,
    };
  }

  bool get hasTips => tips.isNotEmpty;

  static List<MorningInsightEntry> decodeTipsPayload(dynamic payload) {
    if (payload == null) return const <MorningInsightEntry>[];

    Iterable<dynamic>? source;
    if (payload is Map<String, dynamic>) {
      final dynamic candidate = payload['items'] ?? payload['tips'] ?? payload['entries'];
      if (candidate is List) {
        source = candidate;
      } else if (candidate is Map) {
        source = _orderedValuesFromMap(candidate);
      }
    } else if (payload is Map) {
      final dynamic candidate = payload['items'] ?? payload['tips'] ?? payload['entries'];
      if (candidate is List) {
        source = candidate;
      } else if (candidate is Map) {
        source = _orderedValuesFromMap(candidate);
      }
    } else if (payload is List) {
      source = payload;
    }
    if (source == null) return const <MorningInsightEntry>[];

    final List<MorningInsightEntry> result = <MorningInsightEntry>[];
    for (final dynamic element in source) {
      final MorningInsightEntry? entry = _entryFromDynamic(element);
      if (entry != null && entry.isMeaningful && !_containsEntry(result, entry)) {
        result.add(entry);
      }
    }
    return result;
  }

  static MorningInsightEntry? _entryFromDynamic(dynamic element) {
    if (element is MorningInsightEntry) return element;
    if (element is Map<String, dynamic>) return MorningInsightEntry.fromJson(element);
    if (element is Map) {
      final converted = element.map<String, dynamic>((key, value) => MapEntry(key.toString(), value));
      return MorningInsightEntry.fromJson(converted);
    }
    if (element is String) {
      final entry = MorningInsightEntry.fromLegacy(element);
      return entry.isMeaningful ? entry : null;
    }
    if (element is List) {
      final actions = element.whereType<String>().map(_cleanMorningText).where((e) => e.isNotEmpty).toList();
      if (actions.isEmpty) return null;
      final title = _deriveMorningTitle(actions.first);
      return MorningInsightEntry(
        title: title.isNotEmpty ? title : actions.first,
        summary: null,
        actions: actions,
      );
    }
    return null;
  }

  static bool _containsEntry(List<MorningInsightEntry> list, MorningInsightEntry candidate) {
    return list.any((item) =>
        item.title == candidate.title &&
        (item.summary ?? '') == (candidate.summary ?? '') &&
        listEquals(item.actions, candidate.actions));
  }

  static Iterable<dynamic> _orderedValuesFromMap(Map<dynamic, dynamic> map) {
    final entries = map.entries.toList();
    entries.sort((a, b) => _compareDynamicKey(a.key, b.key));
    return entries.map((e) => e.value);
  }

  static int _compareDynamicKey(dynamic a, dynamic b) {
    final int? ai = int.tryParse(a?.toString() ?? '');
    final int? bi = int.tryParse(b?.toString() ?? '');
    if (ai != null && bi != null) {
      return ai.compareTo(bi);
    }
    final String as = a?.toString() ?? '';
    final String bs = b?.toString() ?? '';
    return as.compareTo(bs);
  }
}

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

    // 读取“动态(segments)”上下文的提供商与模型，用于日志与写库，保证与动态一致
    String providerTypeUsed = 'openai-compatible';
    String modelUsed = await _settings.getModel();
    try {
      final ctx = await _settings.getAIContextRow('segments');
      final m = (ctx != null ? (ctx['model'] as String?) : null)?.trim();
      if (m != null && m.isNotEmpty) modelUsed = m;
      final pid = (ctx != null ? ctx['provider_id'] : null);
      if (pid is int) {
        try {
          final p = await AIProvidersService.instance.getProvider(pid);
          if (p != null && (p.type.trim().isNotEmpty)) providerTypeUsed = p.type.trim();
        } catch (_) {}
      }
    } catch (_) {}

    // 打印请求准备信息（与原生侧风格一致：预览 + 完整分块）
    try { await FlutterLogger.nativeInfo('DailySummary', 'AI prepare: context=segments provider='+providerTypeUsed+' model='+modelUsed+' promptLen='+prompt.length.toString()); } catch (_) {}
    try {
      final prev = prompt.length <= 1200 ? prompt : (prompt.substring(0, 1200) + '…');
      await FlutterLogger.nativeDebug('DailySummary', 'prompt preview: '+prev);
    } catch (_) {}
    try {
      await FlutterLogger.nativeInfo('DailySummary', 'prompt full BEGIN >>>');
      final s = prompt;
      const int chunk = 1800;
      for (int i = 0; i < s.length; i += chunk) {
        final end = (i + chunk < s.length) ? (i + chunk) : s.length;
        await FlutterLogger.nativeInfo('DailySummary', s.substring(i, end));
      }
      await FlutterLogger.nativeInfo('DailySummary', 'prompt full END <<<');
    } catch (_) {}

    // 使用“动态(segments)”上下文对应的提供商/模型进行一次性请求，确保与动态 AppBar 选择一致
    AIMessage resp;
    try {
      resp = await _chat.sendMessageOneShot(prompt, context: 'segments', timeout: null);
    } catch (e, st) {
      // ignore: discarded_futures
      await FlutterLogger.nativeError('DailySummary', 'AI request failed: '+e.toString());
      // ignore: discarded_futures
      await FlutterLogger.nativeDebug('DailySummary', 'AI exception stack: '+st.toString());
      rethrow;
    }
    final raw = _stripFences(resp.content.trim());
    // ignore: discarded_futures
    FlutterLogger.nativeInfo('DailySummary', 'AI raw length=${raw.length}');
    try {
      final prev = raw.length <= 1200 ? raw : (raw.substring(0, 1200) + '…');
      await FlutterLogger.nativeDebug('DailySummary', 'AI response preview: '+prev);
    } catch (_) {}
    try {
      await FlutterLogger.nativeInfo('DailySummary', 'AI response full BEGIN >>>');
      final s = raw;
      const int chunk = 1800;
      for (int i = 0; i < s.length; i += chunk) {
        final end = (i + chunk < s.length) ? (i + chunk) : s.length;
        await FlutterLogger.nativeInfo('DailySummary', s.substring(i, end));
      }
      await FlutterLogger.nativeInfo('DailySummary', 'AI response full END <<<');
    } catch (_) {}

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
      FlutterLogger.nativeWarn('DailySummary', 'non-JSON AI response, try repair then fallback; error=$e');
      // 先尝试修复 overall_summary / notification_brief 中的未转义引号，然后再次解析
      try {
        final repaired = _repairJsonUnescapedQuotes(raw, keys: const ['overall_summary', 'notification_brief']);
        final j2 = jsonDecode(repaired);
        if (j2 is Map<String, dynamic>) {
          sj = j2;
          final v2 = j2['overall_summary'];
          if (v2 is String && v2.trim().isNotEmpty) {
            outputText = v2.trim();
          }
        }
      } catch (_) {
        // 修复仍失败：使用“宽松截取”避免被内部引号截断
        try {
          final ov2 = _extractLooseField(raw, 'overall_summary', nextKeyHint: '"timeline"');
          final nb2 = _extractLooseField(raw, 'notification_brief');
          if (ov2 != null && ov2.trim().isNotEmpty) {
            final ov3 = _unescapeJsonStringCandidate(ov2.trim());
            final nb3 = nb2 == null ? null : _unescapeJsonStringCandidate(nb2.trim());
            outputText = ov3;
            final m = <String, dynamic>{'overall_summary': outputText};
            if (nb3 != null && nb3.trim().isNotEmpty) m['notification_brief'] = nb3.trim();
            sj = m;
          } else {
            // 最后尝试原先的简易正则提取
            final ov = _extractJsonStringValue(raw, 'overall_summary');
            final nb = _extractJsonStringValue(raw, 'notification_brief');
            if (ov != null && ov.trim().isNotEmpty) {
              outputText = ov.trim();
              final m = <String, dynamic>{'overall_summary': outputText};
              if (nb != null && nb.trim().isNotEmpty) m['notification_brief'] = nb.trim();
              sj = m;
            }
          }
        } catch (_) {}
      }
      // 仍失败则保持 outputText=raw
    }

    // 写入记录时复用上方解析到的 provider 与 model
    await _db.upsertDailySummary(
      dateKey: dateKey,
      aiProvider: providerTypeUsed,
      aiModel: modelUsed,
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
    FlutterLogger.nativeInfo('DailySummary', 'upsert ok model='+modelUsed+' outLen='+outputText.length.toString());
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

  Future<MorningInsights?> loadMorningInsights(String dateKey) async {
    final row = await _db.getMorningInsights(dateKey);
    if (row == null) return null;
    final insights = MorningInsights.fromRow(row);
    if (insights.tips.isEmpty) return null;
    return insights;
  }

  Future<void> clearMorningInsights(String dateKey) async {
    await _db.deleteMorningInsights(dateKey);
  }

  Future<MorningInsights?> fetchOrGenerateMorningInsights(String dateKey, {bool force = false}) async {
    if (!force) {
      final existed = await loadMorningInsights(dateKey);
      if (existed != null) {
        if (existed.tips.length >= 10) {
          return existed;
        }
        final regenerated = await generateMorningInsights(dateKey);
        return regenerated ?? existed;
      }
    }
    return await generateMorningInsights(dateKey);
  }

  Future<MorningInsights?> generateMorningInsights(String dateKey) async {
    final sourceDateKey = previousDateKey(dateKey);
    final range = _dayRangeMillis(sourceDateKey);
    if (range == null) return null;

    final segments = await _db.listSegmentsWithResultsBetween(
      startMillis: range[0],
      endMillis: range[1],
    );

    final prompt = await _buildMorningPrompt(dateKey, sourceDateKey, segments);
    try { await FlutterLogger.nativeInfo('MorningInsights', 'generate start target=$dateKey source=$sourceDateKey segments=${segments.length}'); } catch (_) {}
    final resp = await _chat.sendMessageOneShot(prompt, context: 'segments', timeout: null);
    final stripped = _stripFences(resp.content.trim());
    try { await FlutterLogger.nativeDebug('MorningInsights', 'AI response preview: '+(stripped.length > 800 ? stripped.substring(0, 800)+'…' : stripped)); } catch (_) {}

    final tips = _parseMorningTips(stripped);
    if (tips.isEmpty) {
      try { await FlutterLogger.nativeWarn('MorningInsights', 'parsed tips empty'); } catch (_) {}
      return null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final rawJson = jsonEncode({
      'items': tips.map((e) => e.toJson()).toList(),
    });
    await _db.upsertMorningInsights(
      dateKey: dateKey,
      sourceDateKey: sourceDateKey,
      tipsJson: rawJson,
      rawResponse: stripped,
    );
    try { await FlutterLogger.nativeInfo('MorningInsights', 'saved tips=${tips.length}'); } catch (_) {}
    return MorningInsights(
      dateKey: dateKey,
      sourceDateKey: sourceDateKey,
      tips: tips,
      createdAt: now,
      rawResponse: stripped,
    );
  }

  Future<String> _buildDailyPrompt(String dateKey, List<Map<String, dynamic>> segments) async {
    final custom = await _settings.getPromptDaily();

    // 计算当前应用语言并获取“语言策略”系统文案（要求忽略上下文语言，按应用语言输出）
    final String langCode = (LocaleService.instance.locale?.languageCode ??
            WidgetsBinding.instance.platformDispatcher.locale.languageCode)
        .toLowerCase();
    final bool isZh = langCode.startsWith('zh');
    final locale = isZh ? const Locale('zh') : const Locale('en');
    final String languagePolicy = lookupAppLocalizations(locale).aiSystemPromptLanguagePolicy;

    final String defaultTemplate = isZh ? _defaultDailyPromptZh : _defaultDailyPromptEn;
    String header;
    final String? trimmedAddon = custom?.trim();
    if (trimmedAddon != null && trimmedAddon.isNotEmpty) {
      final String beginMarker = isZh ? '【重要附加说明（开始）】' : '***IMPORTANT EXTRA INSTRUCTIONS (BEGIN)***';
      final String endMarker = isZh ? '【重要附加说明（结束）】' : '***IMPORTANT EXTRA INSTRUCTIONS (END)***';
      final String upperBlock = '$beginMarker\n$trimmedAddon';
      final String lowerBlock = '$endMarker\n$trimmedAddon';
      header = '$languagePolicy\n\n$upperBlock\n\n$defaultTemplate\n\n$lowerBlock';
    } else {
      header = '$languagePolicy\n\n$defaultTemplate';
    }

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

  String _notificationTitleForSlot(String dateKey, DailySummaryNotificationSlot slot) {
    final String langCode = (LocaleService.instance.locale?.languageCode ??
            WidgetsBinding.instance.platformDispatcher.locale.languageCode)
        .toLowerCase();
    final bool isZh = langCode.startsWith('zh');
    final locale = isZh ? const Locale('zh') : const Locale('en');
    final l10n = lookupAppLocalizations(locale);
    switch (slot) {
      case DailySummaryNotificationSlot.morning:
        return l10n.dailySummarySlotMorningTitle(dateKey);
      case DailySummaryNotificationSlot.noon:
        return l10n.dailySummarySlotNoonTitle(dateKey);
      case DailySummaryNotificationSlot.evening:
        return l10n.dailySummarySlotEveningTitle(dateKey);
      case DailySummaryNotificationSlot.night:
        return l10n.dailySummarySlotNightTitle(dateKey);
      case DailySummaryNotificationSlot.finalReminder:
        return l10n.dailySummaryTitle(dateKey);
    }
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

  // 从原始文本中近似抽取 JSON 字符串字段（仅用于容错），支持简单转义还原
  String? _extractJsonStringValue(String raw, String key) {
    try {
      final pattern = RegExp('"'+RegExp.escape(key)+'"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"', dotAll: true);
      final m = pattern.firstMatch(raw);
      if (m == null) return null;
      final captured = m.group(1) ?? '';
      // 使用 JSON 解析一次来还原转义字符
      try {
        final wrapped = '{"x":"$captured"}';
        final obj = jsonDecode(wrapped);
        final val = (obj is Map && obj['x'] is String) ? (obj['x'] as String) : captured;
        return val.trim();
      } catch (_) {
        return captured.trim();
      }
    } catch (_) {
      return null;
    }
  }

  // 修复指定键的值中未转义的双引号（只在解析失败时使用）
  String _repairJsonUnescapedQuotes(String s, {required List<String> keys}) {
    String out = s;
    for (final key in keys) {
      out = _repairOneField(out, key, nextKeyHint: key == 'overall_summary' ? '"timeline"' : null);
    }
    return out;
  }

  String _repairOneField(String s, String key, {String? nextKeyHint}) {
    try {
      final keyIdx = s.indexOf('"$key"');
      if (keyIdx < 0) return s;
      final colon = s.indexOf(':', keyIdx);
      if (colon < 0) return s;
      final firstQuote = s.indexOf('"', colon);
      if (firstQuote < 0) return s;
      int endQuote;
      if (nextKeyHint != null) {
        final nextIdx = s.indexOf(nextKeyHint, firstQuote + 1);
        if (nextIdx < 0) return s;
        endQuote = s.lastIndexOf('"', nextIdx - 1);
      } else {
        final brace = s.indexOf('}', firstQuote + 1);
        if (brace < 0) return s;
        endQuote = s.lastIndexOf('"', brace);
      }
      if (endQuote <= firstQuote) return s;
      final value = s.substring(firstQuote + 1, endQuote);
      // 仅替换未转义的引号
      final escaped = value.replaceAllMapped(RegExp(r'(?<!\\)"'), (m) => '\\"');
      return s.substring(0, firstQuote + 1) + escaped + s.substring(endQuote);
    } catch (_) {
      return s;
    }
  }

  // 宽松截取：跨越未转义引号，按“下一字段”或“对象结束”来界定结束位置
  String? _extractLooseField(String s, String key, {String? nextKeyHint}) {
    try {
      final keyIdx = s.indexOf('"$key"');
      if (keyIdx < 0) return null;
      final colon = s.indexOf(':', keyIdx);
      if (colon < 0) return null;
      final firstQuote = s.indexOf('"', colon);
      if (firstQuote < 0) return null;
      int endQuote;
      if (nextKeyHint != null) {
        final nextIdx = s.indexOf(nextKeyHint, firstQuote + 1);
        if (nextIdx < 0) return null;
        endQuote = s.lastIndexOf('"', nextIdx - 1);
      } else {
        final brace = s.indexOf('}', firstQuote + 1);
        if (brace < 0) return null;
        endQuote = s.lastIndexOf('"', brace);
      }
      if (endQuote <= firstQuote) return null;
      final value = s.substring(firstQuote + 1, endQuote);
      return value.trim();
    } catch (_) {
      return null;
    }
  }

  // 尝试将形如 "\n" 等 JSON 转义序列反转为真实字符
  String _unescapeJsonStringCandidate(String s) {
    try {
      final wrapped = '{"x":"' + s.replaceAll('\\', '\\\\').replaceAll('"', '\\"') + '"}';
      final obj = jsonDecode(wrapped);
      if (obj is Map && obj['x'] is String) {
        return (obj['x'] as String);
      }
    } catch (_) {}
    return s;
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
      final title = _notificationTitleForSlot(
        dateKey,
        DailySummaryNotificationSlot.finalReminder,
      );
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
      // 同步安排固定时段（08:00/12:00/17:00/22:00）
      try {
        final ok = await _channel.invokeMethod('scheduleDailySummaryNotification', {
          // 复用原生接收器：为固定时段单独调用由原生端恢复时统一设定
          // 这里仅确保通道可用；具体固定时段在原生 Boot 恢复与 restore 时安排
          'hour': hour,
          'minute': minute,
          'enabled': enabled,
        });
        // ignore: discarded_futures
        FlutterLogger.nativeDebug('DailySummary', 'schedule fixed slots via native restore side-effect ok=$ok');
      } catch (_) {}
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
      final bool enabled = await UserSettingsService.instance.getBool(
        UserSettingKeys.dailyNotifyEnabled,
        defaultValue: true,
        legacyPrefKeys: const <String>['daily_notify_enabled'],
      );
      final int hour = await UserSettingsService.instance.getInt(
        UserSettingKeys.dailyNotifyHour,
        defaultValue: 22,
        legacyPrefKeys: const <String>['daily_notify_hour'],
      );
      final int minute = await UserSettingsService.instance.getInt(
        UserSettingKeys.dailyNotifyMinute,
        defaultValue: 0,
        legacyPrefKeys: const <String>['daily_notify_minute'],
      );

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

  String previousDateKey(String dateKey) {
    final range = _dayRangeMillis(dateKey);
    if (range == null) return dateKey;
    final start = DateTime.fromMillisecondsSinceEpoch(range[0]);
    final prev = start.subtract(const Duration(days: 1));
    return _dateKey(prev);
  }

  Future<String> _buildMorningPrompt(String displayDateKey, String sourceDateKey, List<Map<String, dynamic>> segments) async {
    final String? custom = await _settings.getPromptMorning();
    final String langCode = (LocaleService.instance.locale?.languageCode ??
            WidgetsBinding.instance.platformDispatcher.locale.languageCode)
        .toLowerCase();
    final bool isZh = langCode.startsWith('zh');
    final bool isJa = langCode.startsWith('ja');
    final bool isKo = langCode.startsWith('ko');
    final Locale locale = isZh
        ? const Locale('zh')
        : (isJa ? const Locale('ja') : (isKo ? const Locale('ko') : const Locale('en')));
    final String languagePolicy = lookupAppLocalizations(locale).aiSystemPromptLanguagePolicy;
    final String defaultTemplate = isZh
        ? _defaultMorningPromptZh
        : (isJa ? _defaultMorningPromptJa : (isKo ? _defaultMorningPromptKo : _defaultMorningPromptEn));
    final String beginMarker = isZh
        ? '【重要附加说明（开始）】'
        : (isJa ? '【重要な追加指示（開始）】' : (isKo ? '***중요 추가 지침 (시작)***' : '***IMPORTANT EXTRA INSTRUCTIONS (BEGIN)***'));
    final String endMarker = isZh
        ? '【重要附加说明（结束）】'
        : (isJa ? '【重要な追加指示（終了）】' : (isKo ? '***중요 추가 지침 (종료)***' : '***IMPORTANT EXTRA INSTRUCTIONS (END)***'));
    final String? trimmedAddon = custom == null ? null : custom.trim().isEmpty ? null : custom.trim();
    final buffer = StringBuffer()
      ..writeln(languagePolicy)
      ..writeln();
    if (trimmedAddon != null) {
      buffer
        ..writeln(beginMarker)
        ..writeln(trimmedAddon)
        ..writeln()
        ..writeln(defaultTemplate)
        ..writeln()
        ..writeln(endMarker)
        ..writeln(trimmedAddon);
    } else {
      buffer.writeln(defaultTemplate);
    }

    final String labelTarget = isZh
        ? '目标日期'
        : (isJa ? '対象日' : (isKo ? '목표 날짜' : 'Target Date'));
    final String labelSource = isZh
        ? '昨日日期'
        : (isJa ? '前日' : (isKo ? '전날' : 'Source Date'));
    final String labelContext = isZh
        ? '上下文（昨日 overall_summary，仅用于理解背景，禁止逐句复述）'
        : (isJa
            ? 'コンテキスト（前日の overall_summary。理解のためのみで逐語引用禁止）'
            : (isKo ? '컨텍스트(전날 overall_summary, 참고용, 그대로 반복 금지)' : 'Context (yesterday overall_summary, context only; do not restate verbatim)'));
    final String noContext = isZh
        ? '(昨日无可用上下文，请据此给出泛化建议)'
        : (isJa
            ? '(前日の情報がほぼありません。一般的な継続方針を提案してください)'
            : (isKo
                ? '(전날 참고 정보가 거의 없습니다. 실용적인 일반 제안을 제공하세요)'
                : '(Very little context available; please provide generalized yet actionable suggestions)'));

    buffer
      ..writeln()
      ..writeln('$labelTarget: $displayDateKey')
      ..writeln('$labelSource: $sourceDateKey')
      ..writeln('$labelContext:');

    bool hasContext = false;
    for (final seg in segments) {
      final summary = _extractOverallSummary(seg);
      if (summary.isEmpty) continue;
      final start = _fmtHms((seg['start_time'] as int?) ?? 0);
      final end = _fmtHms((seg['end_time'] as int?) ?? 0);
      buffer.writeln('- [$start-$end] $summary');
      hasContext = true;
    }
    if (!hasContext) {
      buffer.writeln(noContext);
    }
    return buffer.toString();
  }

  List<MorningInsightEntry> _parseMorningTips(String raw) {
    List<MorningInsightEntry> tryParse(String text) {
      try {
        final decoded = jsonDecode(text);
        final entries = MorningInsights.decodeTipsPayload(decoded);
        if (entries.isNotEmpty) return entries;
      } catch (_) {}
      return const <MorningInsightEntry>[];
    }

    final primary = tryParse(raw);
    if (primary.isNotEmpty) return primary;

    try {
      final repaired = _repairJsonUnescapedQuotes(raw, keys: const ['items', 'tips']);
      final second = tryParse(repaired);
      if (second.isNotEmpty) return second;
    } catch (_) {}

    try {
      final idxStart = raw.indexOf('[');
      final idxEnd = raw.lastIndexOf(']');
      if (idxStart >= 0 && idxEnd > idxStart) {
        final arrayText = raw.substring(idxStart, idxEnd + 1);
        final decoded = jsonDecode(arrayText);
        final entries = MorningInsights.decodeTipsPayload(decoded);
        if (entries.isNotEmpty) return entries;
        if (decoded is List) {
          final legacy = decoded
              .whereType<String>()
              .map(MorningInsightEntry.fromLegacy)
              .where((entry) => entry.isMeaningful)
              .toList(growable: false);
          if (legacy.isNotEmpty) return legacy;
        }
      }
    } catch (_) {}

    final cleaned = _cleanMorningText(raw);
    if (cleaned.isNotEmpty) {
      final entry = MorningInsightEntry.fromLegacy(cleaned);
      return entry.isMeaningful ? <MorningInsightEntry>[entry] : const <MorningInsightEntry>[];
    }
    return const <MorningInsightEntry>[];
  }

  /// 默认每日总结提示词（中文，JSON输出，含 overall_summary、timeline、notification_brief）
  static const String _defaultDailyPromptZh = '''
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

  /// Default daily-summary prompt in English (JSON output with overall_summary, timeline, notification_brief).
  static const String _defaultDailyPromptEn = '''
  You are a strict English daily-summary assistant. Based on the provided "overall_summary" for multiple time ranges of the day (context only), you MUST generate a complete daily JSON summary. Do not terminate early or omit any fields/sections.

  Output requirements (satisfy all):
  - Output a single JSON object that can be parsed by standard JSON. Do NOT include explanations, prefixes/suffixes, or any text outside JSON (no Markdown outside JSON).
  - Fields are fixed and all required: overall_summary, timeline, notification_brief. Do not omit, leave empty, or return null.
  - overall_summary must be pure Markdown text (NO triple backtick code fences ```). It MUST include:
    1) First paragraph: a single untitled paragraph summarizing the day’s theme, rhythm, and takeaways;
    2) Then exactly these three second-level sections (Markdown headings) in the fixed order:
       "## Key Actions"
       "## Main Activities"
       "## Key Content"
       Each section must contain at least 3 bullet points using "- ". If context is insufficient, still keep the section and provide at least 1 meaningful placeholder bullet (e.g., "No notable key actions"), never delete sections.
  - timeline must be an array in ascending time order with 5–12 key entries. Each item:
    { "time": "HH:mm:ss-HH:mm:ss", "summary": "One-sentence action (may use brief Markdown emphasis)" }
    If context is minimal, at least 1 item is required; it MUST NOT be empty.
  - notification_brief must be 1–3 short sentences of plain English (no Markdown/headings/lists/code fences), concise and covering the day’s highlights.
  - Do NOT output images or links; do NOT return any keys other than the 3 above; do NOT use null; trim leading/trailing spaces for all strings.

  Strictly output the following JSON shape (fixed keys, all present):
  {
    "overall_summary": "(Markdown) First paragraph is an untitled summary; then include sections “## Key Actions”, “## Main Activities”, “## Key Content”, each with bullet points starting with “- ”",
    "timeline": [
      { "time": "HH:mm:ss-HH:mm:ss", "summary": "..." }
    ],
    "notification_brief": "1–3 sentences in plain English without Markdown"
  }
  ''';

  static const String _defaultMorningPromptZh = '''
  你是一位中文晨间复盘助手。基于“昨日多个时间段的 overall_summary（仅作为背景）”，请为今天早上生成结构化、富有人文关怀的行动建议。
  
  输出规范（必须全部满足）：
  1. 结构要求
     - 仅输出一个 JSON 对象，键固定为 items；不要添加任何额外文字或注释。
     - items 数组长度须为 50 条，且保持顺序完整。
     - 每条元素必须包含以下字段：
       {
         "title": "6-16 字中文短语，不含标点与编号，语气轻柔",
         "summary": "20-60 字中文描述，语调温暖而具象，可带隐喻或自我肯定",
         "actions": ["12-36 字中文行动提示，1-3 条，纯文本，无序号/表情/Markdown"]
       }
  2. 文风与语气
     - items 数组内每条建议仍需同时满足以下条件：
       • 语气温暖、治愈、富有人文关怀；以陈述式鼓励与松弛提醒为主，避免任务驱动的命令口吻。
       • 每条 summary 或 actions 中的句子须为 18-60 字完整中文句子，可适度穿插比喻、轻挑战或自我肯定。除非特别必要，全篇最多包含一条问句。
       • 避免模板化措辞，严禁使用“昨天…今天…”、“昨日…今日…”等套话；同一条目内各句的开头需有变化，不能全部使用相同词语。
       • 至少有一条建议突出节奏/情绪/环境的准备，其余条目结合昨日的关键线索、人物或场景，从新的角度展望今日行动，可提醒风险、捕捉机会或调节心态。
     - 严禁使用 Markdown、列表符号、编号、表情或代码围栏；输出均为纯文本。
  3. 兜底策略
     - 当上下文极少时，仍需输出 50 条高质量、具启发性的泛化建议，依旧遵循上述结构与文风限定。
  
  示例：{"items":[{"title":"晨光热身","summary":"用更松弛的拉伸开启身体，让昨夜的紧绷慢慢散去，心绪也慢慢沉静。","actions":["轻柔伸展 10 分钟，关注呼吸节奏","整理桌面，为今天的思路留出余白"]}]}
  ''';

  static const String _defaultMorningPromptEn = '''
  You are a morning reflection assistant. Using the "yesterday overall_summary" excerpts (context only), craft structured, human-centered inspirations for the upcoming day.
  
  Output rules (all mandatory):
  1. Structure
     - Return exactly one JSON object whose only key is items; do not add explanations or extra text.
     - The items array must contain 50 entries, preserving order.
     - Each entry must follow this structure:
       {
         "title": "Gentle 5–14 word headline, no punctuation or numbering",
         "summary": "Warm 1–2 sentence description (roughly 18–60 words) blending empathy, imagery, or soft challenge",
         "actions": ["Single-sentence action prompts, 12–36 words each, 1–3 items, plain text (no bullets/emoji/markdown)"]
       }
  2. Tone & phrasing
     - Keep the voice warm, restorative, and human; favour declarative encouragement and grounded calm over task-driven commands.
     - Each sentence in summary or actions should be a complete, fluent sentence about 18–60 words (or an equivalent natural English length). Use metaphors, gentle challenges, or self-affirmations sparingly; the entire output may contain at most one question.
     - Avoid templated phrasing such as "Yesterday… today…" and do not begin every sentence with the same words. Ensure at least one entry centres on cadence/mood/environment readiness, while the others extend yesterday’s cues, people, or scenes into today’s opportunities, watchpoints, or mindset adjustments.
     - Plain text only: no Markdown, list markers, numbering, emojis, or code fences.
  3. Fallback
     - If context is sparse, still produce 50 meaningful entries that respect the same structure and tone requirements.
  
  Example: {"items":[{"title":"Unhurried focus","summary":"Invite a looser morning by airing the room, softening your shoulders, and letting yesterday’s pace dissolve.","actions":["Block a 15-minute buffer before deep work to breathe in quiet","Tidy the desk to leave generous room for the day’s ideas"]}]}
  ''';

  static const String _defaultMorningPromptJa = '''
  あなたは朝の振り返りアシスタントです。「前日の overall_summary（あくまで文脈）」を用いて、今日に向けた人間味のある提案を構造化して届けてください。
  
  出力要件（すべて順守してください）：
  1. 構造
     - JSON オブジェクトを 1 つだけ返し、キーは items 固定。説明文や余計な文字は付けないこと。
     - items 配列は 50 件とし、順番を崩さないこと。
     - 各要素は次の構造に従うこと：
       {
         "title": "やわらかなニュアンスの日本語見出し（5～12文字、句読点・番号なし）",
         "summary": "18～60文字程度の穏やかな文章で情景や心情を描写する（1～2文）",
         "actions": ["12～36文字の行動ヒントを1～3件、1文で完結、箇条書き記号・絵文字・Markdown禁止"]
       }
  2. 文体と表現
     - 全体の語り口はあたたかく癒しを意識し、人への配慮を込めてください。命令的・タスク駆動の口調は避けます。
     - summary や actions の各文は 18～60 文字程度の完全文とし、比喩・小さなチャレンジ・自分への肯定を適度に織り交ぜても構いません。全体で疑問文は最大 1 文までにしてください。
     - 「昨日…今日…」「前日…本日…」といった定型句を使わず、同じ言葉で始まる文を連続させないこと。少なくとも 1 件はリズム／感情／環境づくりに触れ、他の項目は前日の手がかりや登場人物をヒントに今日の視点・機会・注意点へと広げてください。
     - すべて純テキストで出力し、Markdown・箇条書き記号・番号・絵文字・コードフェンスは禁止します。
  3. コンテキストが乏しい場合
     - 情報がほとんどない場合でも、上記構造と文体を守った質の高い提案を 50 件生成してください。
  
  例：{"items":[{"title":"朝の余白","summary":"カーテン越しの光を吸い込みながら深呼吸し、固まった肩をそっとほぐしていきましょう。","actions":["10分間のストレッチで呼吸と体をととのえる","机の上を整えて今日のアイデアに余白を残す"]}]}
  ''';

  static const String _defaultMorningPromptKo = '''
  당신은 아침 리뷰 도우미입니다. 제공된 "전날 overall_summary"(맥락 전용)를 참고해 오늘을 위한 구조화된 제안을 따뜻한 어조로 전달하세요.
  
  출력 규칙(모두 준수하세요):
  1. 구조
     - JSON 객체 한 개만 반환하고, 키는 items 로 고정합니다. 추가 설명이나 다른 텍스트는 금지합니다.
     - items 배열에는 50개의 항목이 있어야 하며, 순서를 유지해야 합니다.
     - 각 항목은 아래 구조를 따라야 합니다.
       {
         "title": "5~12자 이내의 한국어 짧은 제목, 번호/구두점 없음, 부드러운 톤",
         "summary": "18~60자 분량의 따뜻한 서술형 문장(1~2문장)으로 장면과 감정을 담아낼 것",
         "actions": ["12~36자 행동 힌트 1~3개, 한 문장으로, 불릿·이모지·마크다운 금지"]
       }
  2. 문체와 표현
     - 전체 어조는 따뜻하고 치유적인 사람 중심이어야 하며, 과도한 명령형이나 업무 지향적 표현을 피하세요.
     - summary 와 actions 의 각 문장은 18~60자 분량의 완전한 문장이어야 하며, 비유·가벼운 도전·자기 확언을 적절히 섞어도 좋습니다. 전체 출력에서 물음표 문장은 최대 1개까지만 허용됩니다.
     - "어제… 오늘…" "전날… 금일…" 등 정형화된 문장을 사용하지 말고, 같은 단어로 시작하는 문장을 연속해서 쓰지 마세요. 최소 1개의 항목은 리듬·감정·환경 정비에 초점을 맞추고, 나머지는 전날의 단서·인물·장면을 오늘의 기회나 주의점·마음가짐으로 확장하세요.
     - 모든 출력은 순수 텍스트로 작성하며, Markdown·불릿 기호·번호·이모지·코드 블록을 사용하지 마세요.
  3. 맥락이 부족한 경우
     - 정보가 매우 적더라도 위 구조와 문체를 지키며 최소 50개의 의미 있는 제안을 생성해야 합니다.
  
  예시: {"items":[{"title":"여유로운 숨","summary":"창문을 열어 잔잔한 공기를 들이마시고 굳어 있던 어깨를 천천히 내려놓으며 오늘을 느슨하게 시작해 보세요.","actions":["10분간 스트레칭으로 호흡과 몸의 리듬을 맞추세요","책상 위를 정돈해 오늘의 아이디어가 놓일 공간을 남겨 두세요"]}]}
  ''';
}