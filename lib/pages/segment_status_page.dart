import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../services/screenshot_database.dart';
import '../services/flutter_logger.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// 段落事件状态页
/// - 显示进行中的事件（collecting）
/// - 列出最近事件及其样本与AI结果摘要
class SegmentStatusPage extends StatefulWidget {
  const SegmentStatusPage({super.key});

  @override
  State<SegmentStatusPage> createState() => _SegmentStatusPageState();
}

class _SegmentStatusPageState extends State<SegmentStatusPage> {
  final ScreenshotDatabase _db = ScreenshotDatabase.instance;
  Map<String, dynamic>? _active;
  List<Map<String, dynamic>> _segments = <Map<String, dynamic>>[];
  bool _loading = false;
  bool _onlyNoSummary = false; // 仅看暂无AI总结
 
  // 自动轮询：每秒检测“暂无总结”并自动刷新，直到清空
  Timer? _autoTimer;
  bool _autoWatching = false;
  int _autoTickCount = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; });
    try {
      final active = await _db.getActiveSegment();
      // 使用带 has_summary 的查询；当开启“仅看无总结”时直接从SQL过滤
      final segments = await _db.listSegmentsEx(limit: 50, onlyNoSummary: _onlyNoSummary);
      setState(() {
        _active = active;
        _segments = segments;
      });
      // 若处于“仅看无总结”，根据是否还有待补事件启动/停止自动检测
      if (_onlyNoSummary) {
        final hasPending = segments.any((e) => (e['has_summary'] as int? ?? 0) == 0);
        if (hasPending) {
          _maybeStartAutoWatch();
        } else {
          _stopAutoWatch();
        }
      }
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  String _fmtTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}:${dt.second.toString().padLeft(2,'0')}';
  }

  Widget _buildActiveCard() {
    final a = _active;
    if (a == null) return const SizedBox.shrink();
    final start = (a['start_time'] as int?) ?? 0;
    final end = (a['end_time'] as int?) ?? 0;
    final dur = (a['duration_sec'] as int?) ?? 0;
    final interval = (a['sample_interval_sec'] as int?) ?? 0;
    return Card(
      color: Colors.blue.withOpacity(0.08),
      child: ListTile(
        title: const Text('进行中的时间段'),
        subtitle: Text('${_fmtTime(start)} - ${_fmtTime(end)}  ·  ${dur}s  ·  每${interval}s采样'),
        trailing: const Icon(Icons.timelapse),
      ),
    );
  }

  Future<void> _openImageGallery(List<Map<String, dynamic>> samples, int initialIndex) async {
    if (!mounted) return;
    final PageController controller = PageController(initialPage: initialIndex);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              PhotoViewGallery.builder(
                itemCount: samples.length,
                pageController: controller,
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                builder: (ctx, index) {
                  final path = (samples[index]['file_path'] as String?) ?? '';
                  return PhotoViewGalleryPageOptions(
                    imageProvider: FileImage(File(path)),
                    initialScale: PhotoViewComputedScale.contained,
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 4.0,
                    errorBuilder: (c, e, s) => const Center(
                      child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                    ),
                  );
                },
              ),
              Positioned(
                top: MediaQuery.of(dialogCtx).padding.top + 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(dialogCtx).maybePop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSamplesGrid(List<Map<String, dynamic>> samples) {
    final bg = Theme.of(context).dividerColor.withOpacity(0.08);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 9 / 16,
      ),
      itemCount: samples.length,
      itemBuilder: (ctx, i) {
        final s = samples[i];
        final path = (s['file_path'] as String?) ?? '';
        return GestureDetector(
          onTap: () => _openImageGallery(samples, i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              color: bg,
              child: path.isEmpty
                  ? const Center(child: Icon(Icons.image_not_supported_outlined))
                  : Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image_outlined)),
                    ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDetail(Map<String, dynamic> seg) async {
    final id = (seg['id'] as int?) ?? 0;
    final samples = await _db.listSegmentSamples(id);
    final result = await _db.getSegmentResult(id);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          builder: (_, ctrl) {
            return Container(
              padding: const EdgeInsets.all(12),
              child: ListView(
                controller: ctrl,
                children: [
                  Text('时间段：${_fmtTime((seg['start_time'] as int?) ?? 0)} - ${_fmtTime((seg['end_time'] as int?) ?? 0)}'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('状态：${seg['status']}'),
                      const SizedBox(width: 8),
                      if ((seg['merged_flag'] as int?) == 1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('已合并', style: TextStyle(fontSize: 12, color: Colors.orange)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('样本(${samples.length})'),
                  const SizedBox(height: 6),
                  _buildSamplesGrid(samples),
                  const Divider(height: 20),
                  Row(
                    children: [
                      const Text('AI 结果'),
                      const Spacer(),
                      if (result != null)
                        IconButton(
                          tooltip: '复制结果',
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                          onPressed: () async {
                            final text = ((result['structured_json'] as String?) ?? (result['output_text'] as String?) ?? '').toString();
                            if (text.isEmpty) return;
                            await Clipboard.setData(ClipboardData(text: text));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (result == null) const Text('暂无'),
                  if (result != null) ...[
                    Text('Model：${result['ai_model'] ?? ''}'),
                    const SizedBox(height: 6),
                    Text((result['output_text'] as String?) ?? ''),
                    const SizedBox(height: 10),
                    if ((result['structured_json'] as String?) != null)
                      SelectableText((result['structured_json'] as String?) ?? ''),
                  ],
                ],
              ),
            );
          },
        );
      }
    );
  }

  void _maybeStartAutoWatch() {
    if (!_onlyNoSummary || _autoWatching) return;
    _autoWatching = true;
    _autoTickCount = 0;
    // 先触发一次原生扫描，确保后续能尽快进入工作状态
    () async {
      try { await _db.triggerSegmentTick(); } catch (_) {}
    }();
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 1), (_) => _autoPoll());
  }
 
  void _stopAutoWatch() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _autoWatching = false;
  }
 
  Future<void> _autoPoll() async {
    if (!_onlyNoSummary || !mounted) { _stopAutoWatch(); return; }
    if (_loading) return;
    _autoTickCount++;
    try {
      // 每次只做轻量查询；原生端 1s 心跳已持续推进/补救
      final segments = await _db.listSegmentsEx(limit: 50, onlyNoSummary: true);
      if (!mounted) return;
      setState(() { _segments = segments; });
      // 若已无“暂无总结”，停止自动检测
      final hasPending = segments.any((e) => (e['has_summary'] as int? ?? 0) == 0);
      if (!hasPending) _stopAutoWatch();
    } catch (_) {}
  }
 
  @override
  void dispose() {
    _stopAutoWatch();
    super.dispose();
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('事件状态'),
        actions: [
          // 仅看暂无AI总结
          Row(children: [
            const Text('仅看无总结', style: TextStyle(fontSize: 12)),
            Switch(
              value: _onlyNoSummary,
              onChanged: (v) async {
                setState(() { _onlyNoSummary = v; });
                // 切换时刷新数据源，避免在UI端二次过滤导致不生效
                try { await FlutterLogger.nativeInfo('UI', 'toggle onlyNoSummary='+v.toString()); } catch (_) {}
                await _refresh();
                if (v) {
                  _maybeStartAutoWatch();
                } else {
                  _stopAutoWatch();
                }
              },
            ),
          ]),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              // 允许点击，但内部自行忽略正在加载中的重复触发
              if (_loading) {
                try { await FlutterLogger.nativeInfo('UI', 'refresh pressed but loading=true - ignored'); } catch (_) {}
                return;
              }
              try { await FlutterLogger.nativeInfo('UI', 'refresh pressed; onlyNoSummary='+_onlyNoSummary.toString()); } catch (_) {}
              // 若开启“仅看无总结”，直接对当前列表中的无总结项进行精准重试
              if (_onlyNoSummary && _segments.isNotEmpty) {
                try {
                  final ids = _segments
                      .where((e) => (e['has_summary'] as int?) == 0)
                      .map((e) => (e['id'] as int?) ?? 0)
                      .where((id) => id > 0)
                      .toList();
                  if (ids.isNotEmpty) {
                    final n = await _db.retrySegments(ids);
                    try { await FlutterLogger.nativeInfo('UI', 'retrySegments triggered count='+n.toString()); } catch (_) {}
                  }
                } catch (e) {
                  try { await FlutterLogger.nativeWarn('UI', 'retrySegments error: '+e.toString()); } catch (_) {}
                }
              }
              // 触发一次原生补救扫描，再刷新列表
              try {
                final ok = await _db.triggerSegmentTick();
                try { await FlutterLogger.nativeInfo('UI', 'triggerSegmentTick result='+ok.toString()); } catch (_) {}
              } catch (e) {
                try { await FlutterLogger.nativeWarn('UI', 'triggerSegmentTick error: '+e.toString()); } catch (_) {}
              }
              await _refresh();
            },
          )
          ,
          IconButton(
            icon: const Icon(Icons.delete_forever_outlined),
            tooltip: '清除全部事件',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('确认清除'),
                  content: const Text('将删除所有事件与AI结果（不删除截图）。确定继续？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
                    TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确定')),
                  ],
                ),
              );
              if (confirmed != true) return;
              // 直接通过数据库执行清空
              try {
                final db = await ScreenshotDatabase.instance.database;
                await db.delete('segment_results');
                await db.delete('segment_samples');
                await db.delete('segments');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清除全部事件')));
                  _refresh();
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('清除失败: $e')));
              }
            },
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _buildActiveCard(),
            const SizedBox(height: 8),
            if (_onlyNoSummary && _autoWatching)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('后台自动检测中…', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
              ),
            ..._segments.map((seg) {
              final start = (seg['start_time'] as int?) ?? 0;
              final end = (seg['end_time'] as int?) ?? 0;
              final status = (seg['status'] as String?) ?? '';
              final hasFlag = seg.containsKey('has_summary') ? (seg['has_summary'] as int?) : null;
              final merged = (seg['merged_flag'] as int?) == 1;
              return Card(
                child: ListTile(
                  title: Text('${_fmtTime(start)} - ${_fmtTime(end)}'),
                  subtitle: hasFlag != null
                      ? Text(hasFlag == 1 ? '状态：$status · 已有总结' : '状态：$status · 暂无总结')
                      : FutureBuilder<Map<String, dynamic>?>(
                          future: _db.getSegmentResult((seg['id'] as int?) ?? 0),
                          builder: (ctx, snap) {
                            final r = snap.data;
                            final text = (r?['output_text'] as String?)?.trim();
                            final json = (r?['structured_json'] as String?)?.trim();
                            final hasContent = (text != null && text.isNotEmpty && text.toLowerCase() != 'null') ||
                                              (json != null && json.isNotEmpty && json.toLowerCase() != 'null');
                            final subtitle = hasContent ? '状态：$status · 已有总结' : '状态：$status · 暂无总结';
                            return Text(subtitle);
                          },
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (merged)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('已合并', style: TextStyle(fontSize: 11, color: Colors.orange)),
                        ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => _openDetail(seg),
                ),
              );
            }),
            if (_segments.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: Text('暂无事件')),
              ),
          ],
        ),
      ),
    );
  }
}


