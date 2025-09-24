import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/screenshot_database.dart';
import '../services/flutter_logger.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../services/app_selection_service.dart';
import '../models/app_info.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import 'daily_summary_page.dart';

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

  // 应用图标缓存（包名 -> AppInfo）
  final Map<String, AppInfo> _appInfoByPackage = <String, AppInfo>{};

 
  // 自动轮询：每秒检测“暂无总结”并自动刷新，直到清空
  Timer? _autoTimer;
  bool _autoWatching = false;
  int _autoTickCount = 0;

  @override
  void initState() {
    super.initState();
    _initApps();
    _refresh();
  }

  Future<void> _initApps() async {
    try {
      final apps = await AppSelectionService.instance.getAllInstalledApps();
      if (!mounted) return;
      setState(() {
        for (final a in apps) {
          _appInfoByPackage[a.packageName] = a;
        }
      });
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; });
    try {
      final active = await _db.getActiveSegment();
      // 使用带 has_summary 的查询；当开启“仅看无总结”时直接从SQL过滤
      final segments = await _db.listSegmentsEx(limit: 100, onlyNoSummary: _onlyNoSummary);
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
          body: Stack(
            children: [
              PhotoViewGallery.builder(
                itemCount: samples.length,
                pageController: controller,
                backgroundDecoration: const BoxDecoration(),
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
    final bg = Colors.transparent;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
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
                          child: const Text('合并事件', style: TextStyle(fontSize: 12, color: Colors.orange)),
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
                    Builder(
                      builder: (c) {
                        final String rawText = (result['output_text'] as String?) ?? '';
                        final String rawJson = (result['structured_json'] as String?) ?? '';
                        Map<String, dynamic>? sj;
                        try {
                          final d = jsonDecode(rawJson);
                          if (d is Map<String, dynamic>) sj = d;
                        } catch (_) {}
                        String? err;
                        try {
                          final e = sj?['error'];
                          if (e is Map) {
                            final m = (e['message'] ?? e['msg'] ?? '').toString();
                            if (m.trim().isNotEmpty) {
                              err = m;
                            } else {
                              err = e.toString();
                            }
                          } else if (e is String && e.trim().isNotEmpty) {
                            err = e;
                          }
                        } catch (_) {}
                        if (err == null && rawText.trim().startsWith('{')) {
                          try {
                            final d2 = jsonDecode(rawText);
                            if (d2 is Map && d2['error'] != null) {
                              final e2 = d2['error'];
                              if (e2 is Map && (e2['message'] is String)) {
                                err = e2['message'] as String;
                              } else {
                                err = e2.toString();
                              }
                            }
                          } catch (_) {}
                        }
                        if (err == null) {
                          final low = rawText.toLowerCase();
                          if (low.contains('server_error') ||
                              low.contains('request failed') ||
                              low.contains('no candidates returned')) {
                            err = rawText;
                          }
                        }
                        if (err != null) {
                          final cs = Theme.of(c).colorScheme;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: cs.errorContainer,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: cs.error.withOpacity(0.6), width: 1),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, size: 16, color: cs.onErrorContainer),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: SelectableText(
                                        err!,
                                        style: Theme.of(c).textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (rawJson.isNotEmpty)
                                SelectableText(rawJson, style: Theme.of(c).textTheme.bodySmall),
                            ],
                          );
                        } else {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Model：${result['ai_model'] ?? ''}'),
                              const SizedBox(height: 6),
                              MarkdownBody(
                                data: rawText,
                                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(c)).copyWith(
                                  p: Theme.of(c).textTheme.bodyMedium,
                                ),
                                onTapLink: (text, href, title) async {
                                  if (href == null) return;
                                  final uri = Uri.tryParse(href);
                                  if (uri != null) {
                                    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                              if (rawJson.isNotEmpty)
                                SelectableText(rawJson),
                            ],
                          );
                        }
                      },
                    ),
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
        toolbarHeight: 36,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.only(top: 2.0),
          child: const Text('事件状态'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _SegmentTimelineTabView(
          segments: _segments,
          onlyNoSummary: _onlyNoSummary,
          autoWatching: _autoWatching,
          appInfoByPackage: _appInfoByPackage,
          fmtTime: _fmtTime,
          loadSamples: (id) => _db.listSegmentSamples(id),
          loadResult: (id) => _db.getSegmentResult(id),
          onOpenDetail: (seg) => _openDetail(seg),
          openGallery: (samples, index) => _openImageGallery(samples, index),
          activeHeader: _buildActiveCard(),
          onRefreshRequested: _refresh,
        ),
      ),
    );
  }
}

// ============= 按日期 Tab 的段落时间轴视图（含分割线/关键动作/Logo/标签/摘要/可展开图片） =============
class _SegmentTimelineTabView extends StatelessWidget {
  final List<Map<String, dynamic>> segments;
  final bool onlyNoSummary;
  final bool autoWatching;
  final Map<String, AppInfo> appInfoByPackage;
  final String Function(int) fmtTime;
  final Future<List<Map<String, dynamic>>> Function(int) loadSamples;
  final Future<Map<String, dynamic>?> Function(int) loadResult;
  final void Function(Map<String, dynamic>) onOpenDetail;
  final Future<void> Function(List<Map<String, dynamic>>, int) openGallery;
  final Widget activeHeader;
  final Future<void> Function() onRefreshRequested;

  const _SegmentTimelineTabView({
    required this.segments,
    required this.onlyNoSummary,
    required this.autoWatching,
    required this.appInfoByPackage,
    required this.fmtTime,
    required this.loadSamples,
    required this.loadResult,
    required this.onOpenDetail,
    required this.openGallery,
    required this.activeHeader,
    required this.onRefreshRequested,
  });

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing1),
        children: [
          activeHeader,
          const SizedBox(height: 8),
          if (onlyNoSummary && autoWatching)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('后台自动检测中…', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Center(child: Text('暂无事件')),
          ),
        ],
      );
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final seg in segments) {
      final k = _dateKey((seg['start_time'] as int?) ?? 0);
      grouped.putIfAbsent(k, () => <Map<String, dynamic>>[]).add(seg);
    }
    final keys = grouped.keys.toList()..sort((a, b) => a.compareTo(b));
    final ordered = keys.reversed.toList();
    final String todayKey = _dateKey(DateTime.now().millisecondsSinceEpoch);

    return DefaultTabController(
      length: ordered.length,
      child: Column(
        children: [
          Builder(
            builder: (context) {
              final Color selectedColor = Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.darkForeground
                  : AppTheme.foreground;
              final Color unselectedColor =
                  Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.mutedForeground;
              return SizedBox(
                height: 32,
                child: Transform.translate(
                  offset: const Offset(0, -2),
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    // 与截图列表一致：左侧少量起始内边距，去除额外垂直内边距
                    padding: const EdgeInsets.only(left: AppTheme.spacing2),
                    // 与截图列表一致：标签水平留白适中
                    labelPadding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
                    labelColor: selectedColor,
                    unselectedLabelColor: unselectedColor,
                    labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    unselectedLabelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                    // 与截图列表一致：去掉底部分割线
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.label,
                    // 减少上下空隙
                    indicatorPadding: EdgeInsets.zero,
                    // 与截图列表一致：细下划线，较小的左右 insets
                    indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(width: 2.0, color: selectedColor),
                      insets: const EdgeInsets.symmetric(horizontal: 4.0),
                    ),
                    tabs: [for (final k in ordered) Tab(text: _buildDayLabel(k, (grouped[k] ?? const []).length))],
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final k in ordered)
                  ListView(
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing1),
                    children: [
                      activeHeader,
                      const SizedBox(height: 8),
                      if (k == todayKey) _buildDailyEntryCard(context, k),
                      ...List.generate((grouped[k] ?? const <Map<String, dynamic>>[]).length, (i) => _SegmentEntryCard(
                            segment: grouped[k]![i],
                            isLast: i == grouped[k]!.length - 1,
                            fmtTime: fmtTime,
                            loadSamples: loadSamples,
                            loadResult: loadResult,
                            appInfoByPackage: appInfoByPackage,
                            onOpenDetail: () => onOpenDetail(grouped[k]![i]),
                            openGallery: openGallery,
                            onRefreshRequested: onRefreshRequested,
                          )),
                      const SizedBox(height: 12),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dateKey(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _buildDayLabel(String key, int count) {
    try {
      final parts = key.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]) ?? 1970;
        final m = int.tryParse(parts[1]) ?? 1;
        final d = int.tryParse(parts[2]) ?? 1;
        final dt = DateTime(y, m, d);
        final now = DateTime.now();
        bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
        if (sameDay(dt, now)) return '今天 $count';
        if (sameDay(dt, now.subtract(const Duration(days: 1)))) return '昨天 $count';
        return '${dt.month}月${dt.day}日 $count';
      }
    } catch (_) {}
    return '$key $count';
  }

  Widget _buildDailyEntryCard(BuildContext context, String dateKey) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_note_outlined),
        title: const Text('今日总结'),
        subtitle: const Text('查看或生成当日总结'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DailySummaryPage(dateKey: dateKey)),
          );
        },
      ),
    );
  }
}

class _SegmentEntryCard extends StatefulWidget {
  final Map<String, dynamic> segment;
  final bool isLast;
  final String Function(int) fmtTime;
  final Future<List<Map<String, dynamic>>> Function(int) loadSamples;
  final Future<Map<String, dynamic>?> Function(int) loadResult;
  final Map<String, AppInfo> appInfoByPackage;
  final VoidCallback onOpenDetail;
  final Future<void> Function(List<Map<String, dynamic>>, int) openGallery;
  final Future<void> Function() onRefreshRequested;

  const _SegmentEntryCard({
    required this.segment,
    required this.isLast,
    required this.fmtTime,
    required this.loadSamples,
    required this.loadResult,
    required this.appInfoByPackage,
    required this.onOpenDetail,
    required this.openGallery,
    required this.onRefreshRequested,
  });

  @override
  State<_SegmentEntryCard> createState() => _SegmentEntryCardState();
}

class _SegmentEntryCardState extends State<_SegmentEntryCard> {
  bool _expanded = false;
  // 懒加载样本的本地状态，避免每项滚动时触发异步查询导致跳动
  bool _samplesLoading = false;
  bool _samplesLoaded = false;
  List<Map<String, dynamic>> _samples = const <Map<String, dynamic>>[];
  // 摘要展开/收起状态（防止固定高度无法展开）
  bool _summaryExpanded = false;
  // 重新生成操作状态
  bool _retrying = false;
  // 结果轮询器：点击“重新生成”后，直到拿到结果为止持续旋转提示
  Timer? _resultWatchTimer;

  @override
  Widget build(BuildContext context) {
    final int id = (widget.segment['id'] as int?) ?? 0;
    // 移除 per-item FutureBuilder，使用后端联表元数据；展开时懒加载样本
    final int sampleCount = (widget.segment['sample_count'] as int?) ?? 0;
    final int start = (widget.segment['start_time'] as int?) ?? 0;
    final int end = (widget.segment['end_time'] as int?) ?? 0;
    final String timeLabel = '${widget.fmtTime(start)} - ${widget.fmtTime(end)}';
    final bool merged = (widget.segment['merged_flag'] as int?) == 1;
    final bool hasSummary = ((widget.segment['has_summary'] as int?) ?? 0) == 1;
    final String status = (widget.segment['status'] as String?) ?? '';

    final Map<String, dynamic> resultMeta = {
      'categories': widget.segment['categories'],
      'output_text': widget.segment['output_text'],
    };
    final Map<String, dynamic>? structured = _tryParseJson(widget.segment['structured_json'] as String?);
    final String? keyAction = _extractKeyActionDetail(structured);
    final List<String> categories = _extractCategories(resultMeta, structured);
    final String summary = _extractOverallSummary(resultMeta, structured);

    // 错误检测：从 structured_json.error / output_text(JSON) / 关键字启发式 识别错误
    String? errorText;
    final String outputRaw = (resultMeta['output_text'] as String?)?.toString() ?? '';

    // 1) structured_json.error
    try {
      final err = structured?['error'];
      if (err is Map) {
        final msg = (err['message'] ?? err['msg'] ?? '').toString();
        if (msg.trim().isNotEmpty) {
          errorText = msg;
        } else {
          errorText = err.toString();
        }
      } else if (err is String && err.trim().isNotEmpty) {
        errorText = err;
      }
    } catch (_) {}

    // 2) output_text 若为 JSON 且含 error
    if (errorText == null && outputRaw.isNotEmpty && outputRaw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(outputRaw);
        if (decoded is Map && decoded['error'] != null) {
          final e = decoded['error'];
          if (e is Map && (e['message'] is String)) {
            errorText = (e['message'] as String);
          } else {
            errorText = e.toString();
          }
        }
      } catch (_) {}
    }

    // 3) 关键字启发式
    if (errorText == null) {
      final low = outputRaw.toLowerCase();
      if (low.contains('server_error') ||
          low.contains('request failed') ||
          low.contains('no candidates returned')) {
        errorText = outputRaw;
      }
    }

    Widget _buildErrorBanner(String text) {
      final cs = Theme.of(context).colorScheme;
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.error.withOpacity(0.6), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: cs.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      );
    }

        // 包名：优先使用后端汇总的 app_packages_display，其次 app_packages（保证首屏就能显示 Logo）
        List<String> packages = <String>[];
        final String? appPkgsDisplay = widget.segment['app_packages_display'] as String?;
        final String? appPkgsRaw = widget.segment['app_packages'] as String?;
        final String? pkgSrc = (appPkgsDisplay != null && appPkgsDisplay.trim().isNotEmpty)
            ? appPkgsDisplay
            : appPkgsRaw;
        if (pkgSrc != null && pkgSrc.trim().isNotEmpty) {
          packages = pkgSrc.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty).toList();
        }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing3, vertical: AppTheme.spacing1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _timeSeparator(context, label: timeLabel, keyActionDetail: keyAction),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: packages.map((pkg) => _buildAppIcon(context, pkg)).toList(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.start,
                  children: [
                    if (merged)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing2, vertical: 2),
                        constraints: const BoxConstraints(minHeight: 20),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          border: Border.all(color: AppTheme.warning.withOpacity(0.45), width: 1),
                        ),
                        child: const Text(
                          '合并事件',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.warning,
                            height: 1.0,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ...categories.map((c) => _buildChip(context, c)).toList(),
                  ],
                ),
              ),
            ],
          ),
          if (errorText != null) ...[
            const SizedBox(height: 6),
            _buildErrorBanner(errorText!),
          ] else if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            // 根据是否超出行数动态决定是否显示“展开/收起”
            LayoutBuilder(
              builder: (context, constraints) {
                final TextStyle? textStyle = Theme.of(context).textTheme.bodyMedium;
                // 仅在收起状态下检测是否溢出
                bool overflow = false;
                if (!_summaryExpanded && textStyle != null) {
                  final tp = TextPainter(
                    text: TextSpan(text: summary, style: textStyle),
                    maxLines: 7,
                    ellipsis: '…',
                    textDirection: Directionality.of(context),
                  )..layout(maxWidth: constraints.maxWidth);
                  overflow = tp.didExceedMaxLines;
                }

                // 预估 7 行高度用于折叠时裁切
                final double lineHeight = (textStyle?.height ?? 1.2) * (textStyle?.fontSize ?? 14.0);
                final double collapsedHeight = lineHeight * 7.0 + 2.0;

                final md = MarkdownBody(
                  data: summary,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: textStyle,
                  ),
                  onTapLink: (text, href, title) async {
                    if (href == null) return;
                    final uri = Uri.tryParse(href);
                    if (uri != null) {
                      try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
                    }
                  },
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _summaryExpanded
                        ? md
                        : ConstrainedBox(constraints: BoxConstraints(maxHeight: collapsedHeight), child: ClipRect(child: md)),
                    if (overflow || _summaryExpanded)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => setState(() => _summaryExpanded = !_summaryExpanded),
                          child: Text(_summaryExpanded ? '收起内容' : '展开更多'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: sampleCount <= 0 ? null : () async {
                  setState(() => _expanded = !_expanded);
                  if (_expanded && !_samplesLoaded && !_samplesLoading) {
                    setState(() => _samplesLoading = true);
                    try {
                      final loaded = await widget.loadSamples(id);
                      setState(() {
                        _samples = loaded;
                        _samplesLoaded = true;
                      });
                    } catch (_) {} finally {
                      if (mounted) setState(() => _samplesLoading = false);
                    }
                  }
                },
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(_expanded ? '收起图片 ($sampleCount)' : '查看图片 ($sampleCount)'),
              ),
              const Spacer(),
              IconButton(
                tooltip: '重新生成',
                onPressed: _retrying ? null : () async {
                  await _retry();
                },
                icon: _retrying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_outlined, size: 18),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '复制',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  final buffer = StringBuffer()
                    ..writeln('时间段：$timeLabel')
                    ..writeln('状态：$status');
                  if (merged) buffer.writeln('标记：合并事件');
                  if (categories.isNotEmpty) buffer.writeln('类别：${categories.join(', ')}');
                  if (errorText != null && errorText!.trim().isNotEmpty) {
                    buffer.writeln('错误：$errorText');
                  } else if (summary.trim().isNotEmpty) {
                    buffer.writeln('摘要：$summary');
                  }
                  await Clipboard.setData(ClipboardData(text: buffer.toString()));
                  if (!mounted) return;
                  UINotifier.success(context, '已复制到剪贴板');
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '删除事件',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  await _confirmAndDelete();
                },
              ),
            ],
          ),
          if (_expanded)
            (_samplesLoading
                ? const SizedBox(
                    height: 60,
                    child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                : (_samples.isNotEmpty ? _buildThumbGrid(context, _samples) : const SizedBox.shrink())),
          if (!widget.isLast) ...[
            const SizedBox(height: AppTheme.spacing3),
            _buildSeparator(context),
            const SizedBox(height: AppTheme.spacing3),
          ],
        ],
      ),
    );
  }

            // 时间居中 + 下一行展示关键动作（不使用分割线）
            Widget _timeSeparator(BuildContext context, {required String label, String? keyActionDetail}) {
              final Color actionColor = AppTheme.warning; // 使用更醒目的警告色
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 22,
                    child: Center(
                      child: Text(
                        label,
                        style: DefaultTextStyle.of(context).style,
                      ),
                    ),
                  ),
                  if (keyActionDetail != null && keyActionDetail.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Center(
                        child: Text(
                          keyActionDetail,
                          style: DefaultTextStyle.of(context).style.copyWith(color: actionColor),
                        ),
                      ),
                    ),
                ],
              );
            }

  Widget _buildSeparator(BuildContext context) {
    final Color base = DefaultTextStyle.of(context).style.color
        ?? Theme.of(context).textTheme.bodyMedium?.color
        ?? Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      height: 1,
      color: base.withOpacity(0.2),
    );
  }

  Widget _buildAppIcon(BuildContext context, String package) {
    final app = widget.appInfoByPackage[package];
    if (app != null && app.icon != null && app.icon!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(app.icon!, width: 20, height: 20, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(Icons.apps, size: 14),
    );
  }

  Widget _buildChip(BuildContext context, String text) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color fg = dark ? AppTheme.darkSelectedAccent : AppTheme.info;
    // 关键：不设置 alignment，不用 ConstrainedBox 包裹宽度；仅设置最小高度，宽度随文本自适应
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing2, vertical: 2),
      constraints: const BoxConstraints(minHeight: 20),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: fg.withOpacity(0.35), width: 1),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: fg,
          height: 1.0,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildThumbGrid(BuildContext context, List<Map<String, dynamic>> samples) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: samples.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
        childAspectRatio: 9 / 16,
      ),
      itemBuilder: (ctx, i) {
        final s = samples[i];
        final path = (s['file_path'] as String?) ?? '';
        return GestureDetector(
          onTap: () => widget.openGallery(samples, i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: path.isEmpty
                ? Container(
                  color: Colors.transparent,
                  child: const Center(child: Icon(Icons.image_not_supported_outlined)),
                )
              : Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Container(
                    color: Colors.transparent,
                    child: const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
          ),
        );
      },
    );
  }

  Future<void> _retry() async {
    final int id = (widget.segment['id'] as int?) ?? 0;
    if (id <= 0 || _retrying) return;
    setState(() => _retrying = true);
    try {
      // 手动重试不受时间/已有结果限制：强制重跑
      final n = await ScreenshotDatabase.instance.retrySegments([id], force: true);
      if (!mounted) return;
      final ok = n > 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Regeneration queued' : 'Already queued or failed')),
      );
      // 开启轮询直到拿到结果为止；若原本就有结果，可能立即返回
      if (ok) _startResultWatch(id);
      // 如果没成功入队，停止旋转
      if (!ok) setState(() => _retrying = false);
    } catch (_) {
      if (mounted) {
        setState(() => _retrying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Retry failed')),
        );
      }
    }
  }

  Future<void> _confirmAndDelete() async {
    final int id = (widget.segment['id'] as int?) ?? 0;
    if (id <= 0) return;
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: const Text('删除确认'),
              content: const Text('确定删除该事件？此操作不会删除任何图片文件。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('删除'),
                ),
              ],
            );
          },
        ) ?? false;
    if (!confirmed) return;
    try {
      final ok = await ScreenshotDatabase.instance.deleteSegmentOnly(id);
      if (!mounted) return;
      if (ok) {
        UINotifier.success(context, '事件已删除');
        await widget.onRefreshRequested();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delete failed')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delete failed')));
    }
  }

  void _startResultWatch(int id) {
    _resultWatchTimer?.cancel();
    // 轮询间隔 2s；若拿到结果则停止旋转
    _resultWatchTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
      try {
        final res = await widget.loadResult(id);
        if (!mounted) return;
        if (res != null) {
          setState(() => _retrying = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Regenerated')));
          t.cancel();
        }
      } catch (_) {
        // 读取失败不影响轮询，继续尝试
      }
    });
  }

  Map<String, dynamic>? _tryParseJson(String? s) {
    if (s == null) return null;
    try {
      final obj = jsonDecode(s);
      if (obj is Map<String, dynamic>) return obj;
    } catch (_) {}
    return null;
  }

  String? _extractKeyActionDetail(Map<String, dynamic>? sj) {
    if (sj == null) return null;
    final ka = sj['key_actions'];
    if (ka is List && ka.isNotEmpty) {
      final first = ka.first;
      if (first is Map && first['detail'] is String) return (first['detail'] as String);
      if (first is String) return first;
    } else if (ka is Map && ka['detail'] is String) {
      return ka['detail'] as String;
    } else if (ka is String) {
      return ka;
    }
    return null;
  }

  List<String> _extractCategories(Map<String, dynamic>? result, Map<String, dynamic>? sj) {
    final List<String> out = <String>[];
    // 1) result.categories 可能是 JSON 或逗号分隔
    final raw = result?['categories'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final obj = jsonDecode(raw);
        if (obj is List) {
          out.addAll(obj.map((e) => e.toString()));
        } else {
          out.addAll(raw.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty));
        }
      } catch (_) {
        out.addAll(raw.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty));
      }
    }
    // 2) structured_json.categories
    final sc = sj?['categories'];
    if (sc is List) {
      out.addAll(sc.map((e) => e.toString()));
    } else if (sc is String && sc.trim().isNotEmpty) {
      out.addAll(sc.split(RegExp(r'[,\s]+')).where((e) => e.trim().isNotEmpty));
    }
    // 去重
    final set = <String>{};
    final res = <String>[];
    for (final c in out) {
      final v = c.trim();
      if (v.isEmpty) continue;
      if (set.add(v)) res.add(v);
    }
    return res;
  }

  String _extractOverallSummary(Map<String, dynamic>? result, Map<String, dynamic>? sj) {
    final v = sj?['overall_summary'];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    final out = (result?['output_text'] as String?)?.trim() ?? '';
    return out.toLowerCase() == 'null' ? '' : out;
  }

  List<String> _uniquePackages(List<Map<String, dynamic>> samples) {
    final set = <String>{};
    for (final s in samples) {
      final p = (s['app_package_name'] as String?) ?? '';
      if (p.isNotEmpty) set.add(p);
    }
    return set.toList();
  }
}


