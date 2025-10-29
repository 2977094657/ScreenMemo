import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';
import 'screenshot_database.dart';
import 'flutter_logger.dart';

/// 关键图片附件（供聊天 UI 展示）
class EvidenceImageAttachment {
  final String path;       // 本地文件绝对路径
  final String label;      // 简短描述，如 "09:31:02 AppA"
  const EvidenceImageAttachment({required this.path, required this.label});
}

/// 单个事件（段落）可供 LLM 使用的上下文条目
class ContextEventEntry {
  final int segmentId;
  final String window;     // 如 "[09:30:12–09:44:58]"
  final String summary;    // 从 structured_json.overall_summary 或 output_text（不再截断）
  final String? structuredJson; // 事件的完整 structured_json（若有则优先用于上下文）
  final String? outputText;     // 事件的文本输出（作为 structured_json 缺省的回退）
  final List<String> apps; // 去重后的应用集合（包名/应用名）
  final List<EvidenceImageAttachment> keyImages; // 关键图片与标签
  const ContextEventEntry({
    required this.segmentId,
    required this.window,
    required this.summary,
    required this.structuredJson,
    required this.outputText,
    required this.apps,
    required this.keyImages,
  });
}

/// 聚合后的上下文包
class QueryContextPack {
  final int startMs;
  final int endMs;
  final List<ContextEventEntry> events;
  const QueryContextPack({required this.startMs, required this.endMs, required this.events});
}

/// 上下文查询与拼装服务
class QueryContextService {
  QueryContextService._internal();
  static final QueryContextService instance = QueryContextService._internal();

  final ScreenshotDatabase _db = ScreenshotDatabase.instance;

  // 最近一次构建的上下文缓存（仅内存，跨页面复用，避免紧邻多轮对话重复查询）
  QueryContextPack? _lastPack;
  QueryContextPack? get lastPack => _lastPack;
  void setLastPack(QueryContextPack pack) { _lastPack = pack; }
  void clearLastPack() { _lastPack = null; }

  /// 查询时间窗内的“已有总结”的段落，并选取关键图片，产出上下文包
  Future<QueryContextPack> buildContext({
    required int startMs,
    required int endMs,
    int maxEvents = 0, // 0 表示无限制
    int maxImagesTotal = 0, // 0 表示无限制
  }) async {
    try { await FlutterLogger.nativeInfo('Context', 'buildContext begin range=[$startMs-$endMs] maxEvents=$maxEvents maxImagesTotal=$maxImagesTotal'); } catch (_) {}
    // 同时取“有结果”的事件与“时间窗有重叠且有样本”的事件，合并去重，保证上下文尽可能完整
    final List<Map<String, dynamic>> withResults = await _db.listSegmentsWithResultsBetween(startMillis: startMs, endMillis: endMs);
    final List<Map<String, dynamic>> overlapWithSamples = await _db.listSegmentsOverlapWithSamplesBetween(startMillis: startMs, endMillis: endMs);
    try {
      await FlutterLogger.nativeDebug('Context', 'withResults=${withResults.length} overlapWithSamples=${overlapWithSamples.length}');
    } catch (_) {}
    final Map<int, Map<String, dynamic>> byId = <int, Map<String, dynamic>>{};
    void addOrMerge(Map<String, dynamic> m) {
      final int sid = (m['id'] as int?) ?? 0;
      if (sid <= 0) return;
      final existing = byId[sid];
      if (existing == null) {
        byId[sid] = Map<String, dynamic>.from(m);
      } else {
        // 合并缺失的字段（优先保留已有结果中的字段）
        void fillIfEmpty(String key) {
          final v1 = existing[key];
          final v2 = m[key];
          bool isEmpty(dynamic v) => v == null || (v is String && v.trim().isEmpty);
          if (isEmpty(v1) && !isEmpty(v2)) existing[key] = v2;
        }
        for (final k in <String>['output_text', 'structured_json', 'categories', 'app_packages_display', 'app_packages']) {
          fillIfEmpty(k);
        }
      }
    }
    for (final m in withResults) { addOrMerge(m); }
    for (final m in overlapWithSamples) { addOrMerge(m); }
    List<Map<String, dynamic>> rows = byId.values.toList()
      ..sort((a, b) => ((a['start_time'] as int?) ?? 0).compareTo(((b['start_time'] as int?) ?? 0)));
    final List<ContextEventEntry> events = <ContextEventEntry>[];
    int remainingImages = maxImagesTotal;

    final Iterable<Map<String, dynamic>> segIter = (maxEvents != null && maxEvents > 0)
        ? rows.take(maxEvents)
        : rows;
    for (final seg in segIter) {
      final int sid = (seg['id'] as int?) ?? 0;
      if (sid <= 0) continue;

      final int s = (seg['start_time'] as int?) ?? 0;
      final int e = (seg['end_time'] as int?) ?? 0;
      final String window = _fmtWindow(s, e);

      // 选择摘要（不截断）
      final String summary = _extractSummary(seg, clip: false);

      // 结构化与文本
      final String? sjRaw = (seg['structured_json'] as String?)?.trim();
      final String? otRaw = (seg['output_text'] as String?)?.trim();

      // 应用集合
      final String disp = (seg['app_packages_display'] as String? ?? (seg['app_packages'] as String? ?? '')).trim();
      final List<String> apps = disp.isEmpty
          ? <String>[]
          : disp.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

      // 样本图片：按 position_index 选取头/中/尾关键帧
      final List<Map<String, dynamic>> samples = await _db.listSegmentSamples(sid);
      try { await FlutterLogger.nativeDebug('Context', 'segment#$sid samples=${samples.length}'); } catch (_) {}
      // 选图：如 remainingImages == 0 表示无限制
      final int limit = (maxImagesTotal != null && maxImagesTotal > 0)
          ? (remainingImages > 0 ? remainingImages : maxImagesTotal)
          : 0; // 0 -> 无上限
      final List<EvidenceImageAttachment> images = _pickKeyImages(samples, limit: limit);
      if (maxImagesTotal != null && maxImagesTotal > 0) {
        remainingImages = max(0, remainingImages - images.length);
      }

      events.add(ContextEventEntry(
        segmentId: sid,
        window: window,
        summary: summary,
        structuredJson: (sjRaw != null && sjRaw.toLowerCase() != 'null' && sjRaw.isNotEmpty) ? sjRaw : null,
        outputText: (otRaw != null && otRaw.toLowerCase() != 'null' && otRaw.isNotEmpty) ? otRaw : null,
        apps: apps,
        keyImages: images,
      ));

      if (maxImagesTotal != null && maxImagesTotal > 0 && remainingImages <= 0) break;
    }

    final pack = QueryContextPack(startMs: startMs, endMs: endMs, events: events);
    try { await FlutterLogger.nativeInfo('Context', 'buildContext done events=${events.length} images=${events.fold<int>(0, (a, b) => a + b.keyImages.length)}'); } catch (_) {}
    return pack;
  }

  // ----- helpers -----
  String _fmtWindow(int startMs, int endMs) {
    String two(int v) => v.toString().padLeft(2, '0');
    if (startMs <= 0 || endMs <= 0) return '[--:--:--–--:--:--]';
    final ds = DateTime.fromMillisecondsSinceEpoch(startMs);
    final de = DateTime.fromMillisecondsSinceEpoch(endMs);
    String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
    final bool sameDay = (ds.year == de.year && ds.month == de.month && ds.day == de.day);
    if (sameDay) {
      return '[${ymd(ds)} ${two(ds.hour)}:${two(ds.minute)}:${two(ds.second)}–${two(de.hour)}:${two(de.minute)}:${two(de.second)}]';
    }
    return '[${ymd(ds)} ${two(ds.hour)}:${two(ds.minute)}:${two(ds.second)}–${ymd(de)} ${two(de.hour)}:${two(de.minute)}:${two(de.second)}]';
  }

  String _extractSummary(Map<String, dynamic> seg, {bool clip = false}) {
    final rawJson = (seg['structured_json'] as String?) ?? '';
    if (rawJson.isNotEmpty) {
      try {
        final j = jsonDecode(rawJson);
        if (j is Map && j['overall_summary'] is String) {
          final s = (j['overall_summary'] as String).trim();
          if (s.isNotEmpty) return clip ? _clip(s, 800) : s;
        }
      } catch (_) {}
    }
    final txt = (seg['output_text'] as String?)?.trim() ?? '';
    if (txt.isNotEmpty && txt.toLowerCase() != 'null') return clip ? _clip(txt, 800) : txt;
    return '';
  }

  String _clip(String s, int maxLen) => s.length > maxLen ? (s.substring(0, maxLen) + '…') : s;

  List<EvidenceImageAttachment> _pickKeyImages(List<Map<String, dynamic>> samples, {int limit = 0}) {
    if (samples.isEmpty) return const <EvidenceImageAttachment>[];
    final List<Map<String, dynamic>> sorted = List<Map<String, dynamic>>.from(samples)
      ..sort((a, b) => ((a['position_index'] as int?) ?? 0).compareTo((b['position_index'] as int?) ?? 0));

    final picks = <EvidenceImageAttachment>[];

    // 无限制：返回全部有效样本（按顺序）
    if (limit <= 0) {
      for (final m in sorted) {
        final path = (m['file_path'] as String?) ?? '';
        if (path.isEmpty || !File(path).existsSync()) continue;
        final int ts = (m['capture_time'] as int?) ?? 0;
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        final label = DateFormat('HH:mm:ss').format(dt) + ' ' + ((m['app_name'] as String?) ?? '').trim();
        picks.add(EvidenceImageAttachment(path: path, label: label.trim()));
      }
      return picks;
    }

    // 有上限：均匀抽样（覆盖头到尾）
    final int n = sorted.length;
    if (limit >= n) {
      for (final m in sorted) {
        final path = (m['file_path'] as String?) ?? '';
        if (path.isEmpty || !File(path).existsSync()) continue;
        final int ts = (m['capture_time'] as int?) ?? 0;
        final dt = DateTime.fromMillisecondsSinceEpoch(ts);
        final label = DateFormat('HH:mm:ss').format(dt) + ' ' + ((m['app_name'] as String?) ?? '').trim();
        picks.add(EvidenceImageAttachment(path: path, label: label.trim()));
      }
      return picks;
    }

    final double step = (n - 1) / (limit - 1);
    final Set<int> used = <int>{};
    for (int k = 0; k < limit; k++) {
      int idx = (k * step).round();
      if (idx < 0) idx = 0;
      if (idx >= n) idx = n - 1;
      if (!used.add(idx)) continue;
      final m = sorted[idx];
      final path = (m['file_path'] as String?) ?? '';
      if (path.isEmpty || !File(path).existsSync()) continue;
      final int ts = (m['capture_time'] as int?) ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts);
      final label = DateFormat('HH:mm:ss').format(dt) + ' ' + ((m['app_name'] as String?) ?? '').trim();
      picks.add(EvidenceImageAttachment(path: path, label: label.trim()));
    }
    return picks;
  }
}


