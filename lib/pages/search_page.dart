import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'package:path/path.dart' as path;

import '../models/app_info.dart';
import '../models/screenshot_record.dart';
import '../services/app_selection_service.dart';
import '../services/path_service.dart';
import '../services/screenshot_service.dart';
import '../theme/app_theme.dart';
import '../widgets/nsfw_guard.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final Map<String, Future<Map<String, dynamic>?>> _boxesFutureCache = <String, Future<Map<String, dynamic>?>>{};
  final Map<String, AppInfo> _appInfoByPackage = <String, AppInfo>{};

  List<ScreenshotRecord> _results = <ScreenshotRecord>[];
  bool _isLoading = false;
  String? _error;
  Timer? _debounce;
  Directory? _baseDir;
  bool _privacyMode = true;

  static const int _pageSize = 120; // 单次获取数量
  int _offset = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _initBaseDir();
    _scrollController.addListener(_onScroll);
    _loadAppInfos();
    _loadPrivacyMode();
    AppSelectionService.instance.onPrivacyModeChanged.listen((enabled) {
      if (!mounted) return;
      setState(() => _privacyMode = enabled);
    });
  }

  Future<void> _initBaseDir() async {
    try {
      final dir = await PathService.getExternalFilesDir(null);
      if (mounted) setState(() => _baseDir = dir);
    } catch (_) {}
  }

  Future<void> _loadAppInfos() async {
    try {
      final apps = await AppSelectionService.instance.getAllInstalledApps();
      if (!mounted) return;
      setState(() {
        _appInfoByPackage
          ..clear()
          ..addEntries(apps.map((a) => MapEntry(a.packageName, a)));
      });
    } catch (_) {}
  }

  Future<void> _loadPrivacyMode() async {
    try {
      final enabled = await AppSelectionService.instance.getPrivacyModeEnabled();
      if (mounted) setState(() => _privacyMode = enabled);
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
      if (mounted) setState(() {}); // 更新清除按钮显隐（虽然已禁用 actions）
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
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final list = await ScreenshotService.instance
          .searchScreenshotsByOcr(query, limit: _pageSize, offset: 0);
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
        _error = AppLocalizations.of(context).searchFailedError(e.toString());
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_lastQuery.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final more = await ScreenshotService.instance
          .searchScreenshotsByOcr(_lastQuery, limit: _pageSize, offset: _offset);
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
      setState(() {
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _ensureBoxes(String filePath) async {
    if (_lastQuery.isEmpty) return null;
    final key = '$filePath|$_lastQuery';
    final fut = _boxesFutureCache.putIfAbsent(key, () {
      return ScreenshotService.instance
          .getOcrMatchBoxes(filePath: filePath, query: _lastQuery);
    });
    return fut;
  }

  void _openViewer(ScreenshotRecord record, int index) {
    final List<ScreenshotRecord> sameApp =
        _results.where((r) => r.appPackageName == record.appPackageName).toList();
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
        automaticallyImplyLeading: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        toolbarHeight: 48,
        title: Row(
          children: [
            Expanded(
              child: Theme(
                data: Theme.of(context).copyWith(
                  highlightColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  inputDecorationTheme: const InputDecorationTheme(
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                  ),
                ),
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.5),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      Icon(
                        Icons.search,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: true,
                          decoration: InputDecoration(
                            isCollapsed: true,
                            hintText: AppLocalizations.of(context).searchPlaceholder,
                            hintStyle: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.5),
                              fontSize: 14,
                            ),
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                          ),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 14,
                          ),
                          textInputAction: TextInputAction.search,
                          onChanged: _onQueryChanged,
                          onSubmitted: (v) => _search(v.trim()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: const [],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(color: AppTheme.destructive),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.text.trim().isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).searchInputHintOcr,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppTheme.mutedForeground),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noMatchingScreenshots,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppTheme.mutedForeground),
        ),
      );
    }

    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        _onScroll();
        return false;
      },
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
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final s = _results[index];
          final File file = _resolveFile(s.filePath);
          final bool nsfwMasked = _privacyMode && NsfwDetector.isNsfwUrl(s.pageUrl);
          return GestureDetector(
            onTap: nsfwMasked ? null : () => _openViewer(s, index),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double tileW = constraints.maxWidth;
                final double tileH = constraints.maxHeight;
                final bool isDark = Theme.of(context).brightness == Brightness.dark;
                final Image baseImage = Image(
                  image: ResizeImage(
                    FileImage(file),
                    width: _targetThumbWidth(context),
                  ),
                  width: tileW,
                  height: tileH,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildErrorTile(AppLocalizations.of(context).imageMissingOrCorrupted),
                );
                final Widget imageWidget = isDark
                    ? ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          Colors.black.withOpacity(0.5),
                          BlendMode.darken,
                        ),
                        child: baseImage,
                      )
                    : baseImage;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      imageWidget,
                      if (_lastQuery.isNotEmpty)
                        FutureBuilder<Map<String, dynamic>?>(
                          future: _ensureBoxes(s.filePath),
                          builder: (context, snapshot) {
                            final data = snapshot.data;
                            if (data == null) return const SizedBox.shrink();
                            final int srcW = (data['width'] as int?) ?? 0;
                            final int srcH = (data['height'] as int?) ?? 0;
                            final List<dynamic> raw =
                                (data['boxes'] as List?) ?? const [];
                            if (srcW <= 0 || srcH <= 0 || raw.isEmpty) {
                              return const SizedBox.shrink();
                            }
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
                      if (!nsfwMasked && s.pageUrl != null && s.pageUrl!.isNotEmpty)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacing2,
                              vertical: AppTheme.spacing1,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.7),
                                  Colors.transparent,
                                ],
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(AppTheme.radiusSm),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.link,
                                  size: 14,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color
                                      : Colors.white,
                                ),
                                const SizedBox(width: AppTheme.spacing1),
                                Expanded(
                                  child: Text(
                                    s.pageUrl!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                                      .brightness ==
                                                  Brightness.dark
                                              ? Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.color
                                              : Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacing2,
                            vertical: AppTheme.spacing1,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.7),
                              ],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(AppTheme.radiusSm),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildAppIcon(s.appPackageName),
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    _formatFileSize(s.fileSize),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Theme.of(context).textTheme.bodySmall?.color
                                          : Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                _formatTime(s.captureTime),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Theme.of(context).textTheme.bodySmall?.color
                                      : Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (nsfwMasked)
                        Positioned.fill(
                          child: NsfwBackdropOverlay(
                            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                            onReveal: () => _openViewer(s, index),
                            showButton: true,
                          ),
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
    final double logicalTileWidth =
        (screenWidth - AppTheme.spacing1 * 3) / 2;
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
      child: Text(
        message,
        style: const TextStyle(color: AppTheme.destructive, fontSize: 12),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
  }

  Widget _buildAppIcon(String packageName) {
    final app = _appInfoByPackage[packageName];
    if (app != null && app.icon != null && app.icon!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          app.icon!,
          width: 18,
          height: 18,
          fit: BoxFit.cover,
        ),
      );
    }
    final parts = packageName.split('.');
    final head = parts.isNotEmpty ? parts.last : packageName;
    final leading = head.isNotEmpty ? head[0].toUpperCase() : '?';
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        leading,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
      ),
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

