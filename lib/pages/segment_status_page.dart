import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/screenshot_database.dart';

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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; });
    try {
      final active = await _db.getActiveSegment();
      final segments = await _db.listSegments(limit: 50);
      setState(() {
        _active = active;
        _segments = segments;
      });
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
                  Text('状态：${seg['status']}'),
                  const SizedBox(height: 8),
                  Text('样本(${samples.length})'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: samples.map((s){
                      final ts = (s['capture_time'] as int?) ?? 0;
                      final name = (s['file_path'] as String?)?.split('/')?.last ?? '';
                      final app = (s['app_name'] as String?) ?? (s['app_package_name'] as String? ?? '');
                      return Chip(label: Text('${_fmtTime(ts)} • $app • $name'));
                    }).toList(),
                  ),
                  const Divider(height: 20),
                  const Text('AI 结果'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('事件状态'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
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
            ..._segments.map((seg) {
              final start = (seg['start_time'] as int?) ?? 0;
              final end = (seg['end_time'] as int?) ?? 0;
              final status = (seg['status'] as String?) ?? '';
              return Card(
                child: ListTile(
                  title: Text('${_fmtTime(start)} - ${_fmtTime(end)}'),
                  subtitle: Text('状态：$status'),
                  trailing: const Icon(Icons.chevron_right),
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


