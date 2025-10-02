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
import '../widgets/screenshot_item_widget.dart';

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
  List<ScreenshotRecord> _filteredResults = <ScreenshotRecord>[]; // 筛选后的结果
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

  // 筛选相关状态
  String _timeFilter = 'all'; // all, today, yesterday, last7days, last30days, custom
  String _sizeFilter = 'all'; // all, small, medium, large
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  int _totalResultsCount = 0; // 总结果数(未筛选前)

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
        _totalResultsCount = list.length;
        _applyFilters();
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
          _totalResultsCount = _results.length;
          _applyFilters();
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

  // 应用筛选条件
  void _applyFilters() {
    List<ScreenshotRecord> filtered = List.from(_results);

    // 时间筛选
    if (_timeFilter != 'all') {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      switch (_timeFilter) {
        case 'today':
          filtered = filtered.where((r) =>
            r.captureTime.isAfter(today)
          ).toList();
          break;
        case 'yesterday':
          final yesterday = today.subtract(const Duration(days: 1));
          filtered = filtered.where((r) =>
            r.captureTime.isAfter(yesterday) && r.captureTime.isBefore(today)
          ).toList();
          break;
        case 'last7days':
          final last7 = today.subtract(const Duration(days: 7));
          filtered = filtered.where((r) =>
            r.captureTime.isAfter(last7)
          ).toList();
          break;
        case 'last30days':
          final last30 = today.subtract(const Duration(days: 30));
          filtered = filtered.where((r) =>
            r.captureTime.isAfter(last30)
          ).toList();
          break;
        case 'custom':
          if (_customStartDate != null && _customEndDate != null) {
            filtered = filtered.where((r) =>
              r.captureTime.isAfter(_customStartDate!) &&
              r.captureTime.isBefore(_customEndDate!.add(const Duration(days: 1)))
            ).toList();
          }
          break;
      }
    }

    // 大小筛选
    if (_sizeFilter != 'all') {
      switch (_sizeFilter) {
        case 'small':
          filtered = filtered.where((r) => r.fileSize < 100 * 1024).toList();
          break;
        case 'medium':
          filtered = filtered.where((r) =>
            r.fileSize >= 100 * 1024 && r.fileSize <= 1024 * 1024
          ).toList();
          break;
        case 'large':
          filtered = filtered.where((r) => r.fileSize > 1024 * 1024).toList();
          break;
      }
    }

    _filteredResults = filtered;
  }

  // 重置筛选条件
  void _resetFilters() {
    setState(() {
      _timeFilter = 'all';
      _sizeFilter = 'all';
      _customStartDate = null;
      _customEndDate = null;
      _applyFilters();
    });
  }

  // 显示筛选对话框
  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FilterSheet(
        timeFilter: _timeFilter,
        sizeFilter: _sizeFilter,
        customStartDate: _customStartDate,
        customEndDate: _customEndDate,
        onApply: (time, size, startDate, endDate) {
          setState(() {
            _timeFilter = time;
            _sizeFilter = size;
            _customStartDate = startDate;
            _customEndDate = endDate;
            _applyFilters();
          });
        },
        onReset: _resetFilters,
      ),
    );
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
    // 从缓存中获取完整的应用信息（包含 icon）
    final appInfo = _appInfoByPackage[record.appPackageName] ?? AppInfo(
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

    return Column(
      children: [
        // 结果统计和筛选栏
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: AppTheme.spacing2,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.withOpacity(0.2),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).searchResultsCount(_filteredResults.length.toString()),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.mutedForeground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              InkWell(
                onTap: _showFilterDialog,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing2,
                    vertical: AppTheme.spacing1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: (_timeFilter != 'all' || _sizeFilter != 'all')
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.withOpacity(0.3),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.filter_list,
                        size: 16,
                        color: (_timeFilter != 'all' || _sizeFilter != 'all')
                            ? Theme.of(context).colorScheme.primary
                            : AppTheme.mutedForeground,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context).searchFiltersTitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: (_timeFilter != 'all' || _sizeFilter != 'all')
                              ? Theme.of(context).colorScheme.primary
                              : AppTheme.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 图片网格
        Expanded(
          child: _filteredResults.isEmpty
              ? Center(
                  child: Text(
                    AppLocalizations.of(context).noResultsForFilters,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.mutedForeground),
                  ),
                )
              : NotificationListener<ScrollEndNotification>(
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
        itemCount: _filteredResults.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (_loadingMore && index == _filteredResults.length) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final s = _filteredResults[index];
          
          // 构建 OCR 标注叠加层
          Widget? ocrOverlay;
          if (_lastQuery.isNotEmpty) {
            ocrOverlay = FutureBuilder<Map<String, dynamic>?>(
              future: _ensureBoxes(s.filePath),
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data == null) return const SizedBox.shrink();
                final int srcW = (data['width'] as int?) ?? 0;
                final int srcH = (data['height'] as int?) ?? 0;
                final List<dynamic> raw = (data['boxes'] as List?) ?? const [];
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
                return Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: CustomPaint(
                      painter: _OcrBoxesPainter(
                        originalWidth: srcW.toDouble(),
                        originalHeight: srcH.toDouble(),
                        boxes: rects,
                      ),
                    ),
                  ),
                );
              },
            );
          }
          
          return ScreenshotItemWidget(
            screenshot: s,
            baseDir: _baseDir,
            appInfoMap: _appInfoByPackage,
            privacyMode: _privacyMode,
            onTap: () => _openViewer(s, index),
            customOverlay: ocrOverlay,
          );
        },
      ),
        ),
        ),
      ],
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



// 筛选面板Widget - 优化UI版本
class _FilterSheet extends StatefulWidget {
  final String timeFilter;
  final String sizeFilter;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final Function(String time, String size, DateTime? startDate, DateTime? endDate) onApply;
  final VoidCallback onReset;

  const _FilterSheet({
    required this.timeFilter,
    required this.sizeFilter,
    this.customStartDate,
    this.customEndDate,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String _timeFilter;
  late String _sizeFilter;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void initState() {
    super.initState();
    _timeFilter = widget.timeFilter;
    _sizeFilter = widget.sizeFilter;
    _customStartDate = widget.customStartDate;
    _customEndDate = widget.customEndDate;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    return Container(
      padding: EdgeInsets.only(
        left: AppTheme.spacing3,
        right: AppTheme.spacing3,
        top: AppTheme.spacing3,
        bottom: MediaQuery.of(context).padding.bottom + AppTheme.spacing3,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.searchFiltersTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // 时间筛选
          Text(
            l10n.filterByTime,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _buildFilterChip(l10n.filterTimeAll, 'all', _timeFilter, (v) => setState(() => _timeFilter = v)),
              _buildFilterChip(l10n.filterTimeToday, 'today', _timeFilter, (v) => setState(() => _timeFilter = v)),
              _buildFilterChip(l10n.filterTimeYesterday, 'yesterday', _timeFilter, (v) => setState(() => _timeFilter = v)),
              _buildFilterChip(l10n.filterTimeLast7Days, 'last7days', _timeFilter, (v) => setState(() => _timeFilter = v)),
              _buildFilterChip(l10n.filterTimeLast30Days, 'last30days', _timeFilter, (v) => setState(() => _timeFilter = v)),
            ],
          ),
          const SizedBox(height: 16),
          
          // 大小筛选
          Text(
            l10n.filterBySize,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _buildFilterChip(l10n.filterSizeAll, 'all', _sizeFilter, (v) => setState(() => _sizeFilter = v)),
              _buildFilterChip(l10n.filterSizeSmall, 'small', _sizeFilter, (v) => setState(() => _sizeFilter = v)),
              _buildFilterChip(l10n.filterSizeMedium, 'medium', _sizeFilter, (v) => setState(() => _sizeFilter = v)),
              _buildFilterChip(l10n.filterSizeLarge, 'large', _sizeFilter, (v) => setState(() => _sizeFilter = v)),
            ],
          ),
          const SizedBox(height: 20),
          
          // 按钮栏
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    widget.onReset();
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    l10n.resetFilters,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    widget.onApply(
                      _timeFilter,
                      _sizeFilter,
                      _customStartDate,
                      _customEndDate,
                    );
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    l10n.applyFilters,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, String currentValue, Function(String) onSelected) {
    final isSelected = currentValue == value;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) => onSelected(value),
      backgroundColor: Theme.of(context).colorScheme.surface,
      selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
      checkmarkColor: Theme.of(context).colorScheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      side: isSelected
          ? BorderSide.none
          : BorderSide(
              color: Colors.grey.withOpacity(0.2),
              width: 1,
            ),
    );
  }
}