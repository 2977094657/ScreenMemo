import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../theme/app_theme.dart';
import '../models/screenshot_record.dart';
import '../services/screenshot_service.dart';
import '../services/path_service.dart';
import '../models/app_info.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<ScreenshotRecord> _results = <ScreenshotRecord>[];
  bool _isLoading = false;
  String? _error;
  Timer? _debounce;
  Directory? _baseDir;

  static const int _pageSize = 120; // 单次获取数量
  int _offset = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  String _lastQuery = '';
  final ScrollController _scrollController = ScrollController();
  final Map<String, Future<Map<String, dynamic>?>> _boxesFutureCache = <String, Future<Map<String, dynamic>?>>{};

  @override
  void initState() {
    super.initState();
    _initBaseDir();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initBaseDir() async {
    try {
      final dir = await PathService.getExternalFilesDir(null);
      if (mounted) setState(() { _baseDir = dir; });
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore) return;
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final pos = _scrollController.position.pixels;
    if (pos >= max * 0.85) {
      _loadMore();
    }
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search(text.trim());
    });
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _results = <ScreenshotRecord>[];
      _offset = 0;
      _hasMore = false;
      _lastQuery = query;
    });

    if (query.isEmpty) {
      if (mounted) setState(() { _isLoading = false; });
      return;
    }

    try {
      final list = await ScreenshotService.instance.searchScreenshotsByOcr(query, limit: _pageSize, offset: 0);
      if (!mounted) return;
      setState(() {
        _results = list;
        _offset = list.length;
        _hasMore = list.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '搜索失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_lastQuery.isEmpty) return;
    setState(() { _loadingMore = true; });
    try {
      final more = await ScreenshotService.instance.searchScreenshotsByOcr(_lastQuery, limit: _pageSize, offset: _offset);
      if (!mounted) return;
      setState(() {
        if (more.isEmpty) {
          _hasMore = false;
        } else {
          _results.addAll(more);
          _offset += more.length;
          _hasMore = more.length >= _pageSize;
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loadingMore = false; _hasMore = false; });
    }
  }

  Future<Map<String, dynamic>?> _ensureBoxes(String filePath) async {
    if (_lastQuery.isEmpty) return null;
    final key = '$filePath|$_lastQuery';
    final fut = _boxesFutureCache.putIfAbsent(key, () {
      return ScreenshotService.instance.getOcrMatchBoxes(filePath: filePath, query: _lastQuery);
    });
    return fut;
  }

  void _openViewer(ScreenshotRecord record, int index) {
    // 以“同应用且匹配OCR”的局部集合进入查看器，保证查看器上下文一致
    final List<ScreenshotRecord> sameApp = _results.where((r) => r.appPackageName == record.appPackageName).toList();
    final int initialIndex = sameApp.indexWhere((r) => r.id == record.id);
    final appInfo = AppInfo(
      packageName: record.appPackageName,
      appName: record.appName,
      icon: null,
      version: '',
      isSystemApp: false,
    );
    Navigator.pushNamed(
      context,
      '/screenshot_viewer',
      arguments: {
        'screenshots': sameApp,
        'initialIndex': initialIndex < 0 ? 0 : initialIndex,
        'appName': record.appName,
        'appInfo': appInfo,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入关键词搜索 OCR 文本...',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onChanged: _onQueryChanged,
          onSubmitted: (v) => _search(v.trim()),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: '清除',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _onQueryChanged('');
                setState(() { _results = <ScreenshotRecord>[]; _hasMore = false; _offset = 0; });
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: AppTheme.destructive)),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.text.trim().isEmpty) {
      return Center(
        child: Text(
          '在此输入关键词，按 OCR 文本检索截图',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedForeground),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的截图',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedForeground),
        ),
      );
    }

    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) { _onScroll(); return false; },
      child: GridView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(
          left: AppTheme.spacing1,
          right: AppTheme.spacing1,
          bottom: MediaQuery.of(context).padding.bottom + AppTheme.spacing6,
          top: AppTheme.spacing1,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppTheme.spacing1,
          mainAxisSpacing: AppTheme.spacing1,
          childAspectRatio: 0.45,
        ),
        itemCount: _results.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (_loadingMore && index == _results.length) {
            return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
          }
          final s = _results[index];
          final File file = _resolveFile(s.filePath);
          return GestureDetector(
            onTap: () => _openViewer(s, index),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double tileW = constraints.maxWidth;
                final double tileH = constraints.maxHeight;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image(
                        image: ResizeImage(FileImage(file), width: _targetThumbWidth(context)),
                        width: tileW,
                        height: tileH,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) => _buildErrorTile('图片丢失或损坏'),
                      ),
                      if (_lastQuery.isNotEmpty)
                        FutureBuilder<Map<String, dynamic>?>(
                          future: _ensureBoxes(s.filePath),
                          builder: (context, snapshot) {
                            final data = snapshot.data;
                            if (data == null) return const SizedBox.shrink();
                            final int srcW = (data['width'] as int?) ?? 0;
                            final int srcH = (data['height'] as int?) ?? 0;
                            final List<dynamic> raw = (data['boxes'] as List?) ?? const [];
                            if (srcW <= 0 || srcH <= 0 || raw.isEmpty) return const SizedBox.shrink();
                            final List<Rect> rects = <Rect>[];
                            for (final item in raw) {
                              if (item is Map) {
                                final m = Map<String, dynamic>.from(item);
                                final l = (m['left'] as num?)?.toDouble() ?? 0;
                                final t = (m['top'] as num?)?.toDouble() ?? 0;
                                final r = (m['right'] as num?)?.toDouble() ?? 0;
                                final b = (m['bottom'] as num?)?.toDouble() ?? 0;
                                rects.add(Rect.fromLTRB(l, t, r, b));
                              }
                            }
                            if (rects.isEmpty) return const SizedBox.shrink();
                            return CustomPaint(
                              painter: _OcrBoxesPainter(
                                originalWidth: srcW.toDouble(),
                                originalHeight: srcH.toDouble(),
                                boxes: rects,
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  int _targetThumbWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double logicalTileWidth = (screenWidth - AppTheme.spacing1 * 3) / 2;
    return (logicalTileWidth * MediaQuery.of(context).devicePixelRatio).round();
  }

  File _resolveFile(String filePath) {
    if (path.isAbsolute(filePath)) return File(filePath);
    final base = _baseDir;
    if (base == null) return File(filePath);
    return File(path.join(base.path, filePath));
  }

  Widget _buildErrorTile(String message) {
    return Container(
      color: AppTheme.muted,
      alignment: Alignment.center,
      child: Text(message, style: const TextStyle(color: AppTheme.destructive, fontSize: 12)),
    );
  }
}

class _OcrBoxesPainter extends CustomPainter {
  final double originalWidth;
  final double originalHeight;
  final List<Rect> boxes;

  _OcrBoxesPainter({
    required this.originalWidth,
    required this.originalHeight,
    required this.boxes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (originalWidth <= 0 || originalHeight <= 0) return;
    final double scale = (size.width / originalWidth) > (size.height / originalHeight)
        ? (size.width / originalWidth)
        : (size.height / originalHeight);
    final double drawW = originalWidth * scale;
    final double drawH = originalHeight * scale;
    final double offsetX = (size.width - drawW) / 2.0;
    final double offsetY = (size.height - drawH) / 2.0;

    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.amberAccent.withOpacity(0.95)
      ..strokeWidth = 2.0;
    final Paint fill = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.amberAccent.withOpacity(0.18);

    for (final r in boxes) {
      final Rect mapped = Rect.fromLTRB(
        offsetX + r.left * scale,
        offsetY + r.top * scale,
        offsetX + r.right * scale,
        offsetY + r.bottom * scale,
      ).intersect(Offset.zero & size);
      if (mapped.isEmpty) continue;
      canvas.drawRect(mapped, fill);
      canvas.drawRect(mapped, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _OcrBoxesPainter oldDelegate) {
    return oldDelegate.originalWidth != originalWidth ||
        oldDelegate.originalHeight != originalHeight ||
        oldDelegate.boxes != boxes;
  }
}


