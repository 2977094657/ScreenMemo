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
import '../widgets/ui_dialog.dart';
import '../services/nsfw_preference_service.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final Map<String, Future<Map<String, dynamic>?>> _boxesFutureCache =
      <String, Future<Map<String, dynamic>?>>{};
  final Map<String, AppInfo> _appInfoByPackage = <String, AppInfo>{};

  List<ScreenshotRecord> _results = <ScreenshotRecord>[];
  List<ScreenshotRecord> _filteredResults = <ScreenshotRecord>[]; // 筛选后的结果
  bool _isLoading = false;
  String? _error;
  Timer? _debounce;
  Directory? _baseDir;
  bool _privacyMode = true;

  static const int _firstBatchSize = 6; // 首批快速返回数量
  static const int _pageSize = 24; // 后续分页大小
  int _offset = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  String _lastQuery = '';

  // 筛选相关状态
  String _timeFilter =
      'last30days'; // all, today, yesterday, last7days, last30days, customDays
  int _customDays = 30; // 自定义天数，默认30天
  String _sizeFilter = 'all'; // all, small, medium, large
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  int _totalResultsCount = 0; // 总结果数(未筛选前)
  bool _countingTotal = false;
  int _searchToken = 0;

  // 可见范围索引（用于限制仅可见区域附近才进行OCR标注计算）
  int _visibleStartIndex = 0;
  int _visibleEndIndex = -1;
  final GlobalKey _gridKey = GlobalKey();
  final Map<int, GlobalKey> _itemKeys = <int, GlobalKey>{};
  bool _scrollActive = false;
  Timer? _scrollIdleTimer;

  Rect? _getGridViewportRect() {
    final ctx = _gridKey.currentContext;
    if (ctx == null) return null;
    final render = ctx.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    final topLeft = render.localToGlobal(Offset.zero);
    return topLeft & render.size;
  }

  void _updateVisibleRange() {
    if (_filteredResults.isEmpty || _itemKeys.isEmpty) {
      _visibleStartIndex = 0;
      _visibleEndIndex = -1;
      return;
    }
    final viewport = _getGridViewportRect();
    if (viewport == null) return;
    int? firstIdx;
    int? lastIdx;
    _itemKeys.forEach((index, key) {
      if (index < 0 || index >= _filteredResults.length) return;
      final context = key.currentContext;
      if (context == null) return;
      final render = context.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      final rect = render.localToGlobal(Offset.zero) & render.size;
      final visible = rect.bottom > viewport.top && rect.top < viewport.bottom;
      if (!visible) return;
      if (firstIdx == null || index < firstIdx!) firstIdx = index;
      if (lastIdx == null || index > lastIdx!) lastIdx = index;
    });
    if (firstIdx != null && lastIdx != null) {
      _visibleStartIndex = firstIdx!;
      _visibleEndIndex = lastIdx!;
    }
  }

  bool _shouldLoadBoxesForIndex(int index) {
    if (_lastQuery.isEmpty) return false;
    // 初次构建不可见范围未就绪时，允许首屏附近少量请求
    if (_visibleEndIndex < 0) return index < 12;
    final int start = (_visibleStartIndex - 10) < 0
        ? 0
        : (_visibleStartIndex - 10);
    final int end = _visibleEndIndex + 10;
    return index >= start && index <= end;
  }

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
      final dir = await PathService.getInternalAppDir(null);
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
      final enabled = await AppSelectionService.instance
          .getPrivacyModeEnabled();
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
      try {
        print(
          '[Search] onScroll loadMore pos=' +
              pos.toString() +
              ' max=' +
              max.toString(),
        );
      } catch (_) {}
      _loadMore();
    }
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search(text.trim());
    });
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    final int token = ++_searchToken;
    setState(() {
      _isLoading = true;
      _error = null;
      _results = <ScreenshotRecord>[];
      _filteredResults = <ScreenshotRecord>[];
      _offset = 0;
      _hasMore = false;
      _lastQuery = query;
      _countingTotal = false;
    });

    if (query.isEmpty) {
      if (mounted && token == _searchToken) {
        setState(() {
          _isLoading = false;
          _totalResultsCount = 0;
          _filteredResults = <ScreenshotRecord>[];
        });
      }
      return;
    }

    try {
      final sw = Stopwatch()..start();
      final range = _currentTimeRange();
      final size = _currentSizeRange();
      
      // 第一批：快速返回少量结果
      final firstBatch = await ScreenshotService.instance
          .searchScreenshotsByOcrWithFallback(
            query,
            limit: _firstBatchSize,
            offset: 0,
            startMillis: range?.$1,
            endMillis: range?.$2,
            minSize: size?.$1,
            maxSize: size?.$2,
          );

      if (!mounted || token != _searchToken) return;

      // 立即显示首批结果
      if (firstBatch.isNotEmpty) {
        setState(() {
          _results = firstBatch;
          _totalResultsCount = firstBatch.length;
          _applyFilters();
          _isLoading = false;
          _hasMore = firstBatch.length >= _firstBatchSize;
        });
      }
      
      sw.stop();
      try {
        print('[Search] first batch: ${firstBatch.length} in ${sw.elapsedMilliseconds}ms');
      } catch (_) {}

      // 如果首批不足，说明没有更多数据
      if (firstBatch.length < _firstBatchSize) {
        if (mounted && token == _searchToken) {
          setState(() {
            _isLoading = false;
            _hasMore = false;
          });
        }
        return;
      }

      // 第二批：后台加载更多结果
      final sw2 = Stopwatch()..start();
      final moreBatch = await ScreenshotService.instance
          .searchScreenshotsByOcrWithFallback(
            query,
            limit: _pageSize - _firstBatchSize,
            offset: _firstBatchSize,
            startMillis: range?.$1,
            endMillis: range?.$2,
            minSize: size?.$1,
            maxSize: size?.$2,
          );

      if (!mounted || token != _searchToken) return;

      final allResults = [...firstBatch, ...moreBatch];
      final bool hasMoreData = allResults.length >= _pageSize;
      
      setState(() {
        _results = allResults;
        _totalResultsCount = allResults.length;
        _applyFilters();
        _offset = allResults.length;
        _hasMore = hasMoreData;
        _isLoading = false;
        _countingTotal = hasMoreData;
      });
      
      sw2.stop();
      try {
        print('[Search] total: ${allResults.length} (+${sw2.elapsedMilliseconds}ms)');
      } catch (_) {}

      if (!hasMoreData) {
        return;
      }

      // 后台统计总数
      ScreenshotService.instance
          .countScreenshotsByOcrWithFallback(
            query,
            startMillis: range?.$1,
            endMillis: range?.$2,
            minSize: size?.$1,
            maxSize: size?.$2,
          )
          .then((total) {
            if (!mounted || token != _searchToken) return;
            setState(() {
              _totalResultsCount = total;
              _countingTotal = false;
            });
          })
          .catchError((_) {
            if (!mounted || token != _searchToken) return;
            setState(() {
              _countingTotal = false;
            });
          });
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _error = AppLocalizations.of(context).searchFailedError(e.toString());
        _isLoading = false;
        _countingTotal = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_lastQuery.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final sw = Stopwatch()..start();
      final range = _currentTimeRange();
      final size = _currentSizeRange();
      final more = await ScreenshotService.instance
          .searchScreenshotsByOcrWithFallback(
            _lastQuery,
            limit: _pageSize,
            offset: _offset,
            startMillis: range?.$1,
            endMillis: range?.$2,
            minSize: size?.$1,
            maxSize: size?.$2,
          );
      if (!mounted) return;
      setState(() {
        if (more.isEmpty) {
          _hasMore = false;
        } else {
          _results.addAll(more);
          // 保持总结果数为数据库统计的总数，不用已加载数量覆盖
          _applyFilters();
          _offset += more.length;
          _hasMore = more.length >= _pageSize;
        }
        _loadingMore = false;
      });
      sw.stop();
      try {
        print(
          '[Search] loadMore fetched=' +
              more.length.toString() +
              ' offset=' +
              _offset.toString() +
              ' hasMore=' +
              _hasMore.toString() +
              ' ms=' +
              sw.elapsedMilliseconds.toString(),
        );
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  // 应用筛选条件（数据库层已做时间和大小过滤，此处仅同步结果列表）
  void _applyFilters() {
    // 数据库查询时已传入 startMillis/endMillis 和 minSize/maxSize，
    // 返回的 _results 已经是过滤后的数据，无需再次过滤
    _filteredResults = List.from(_results);
    // 清理超出范围的 itemKeys，避免内存泄漏
    _itemKeys.removeWhere((index, _) => index >= _filteredResults.length);
    // 重置可见范围，等待下一帧计算
    _visibleStartIndex = 0;
    _visibleEndIndex = -1;
  }

  // 将当前筛选转换为数据库参数
  (int, int)? _currentTimeRange() {
    if (_timeFilter == 'all') return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int? s;
    int? e;
    switch (_timeFilter) {
      case 'today':
        s = today.millisecondsSinceEpoch;
        e = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch;
        break;
      case 'yesterday':
        final y = today.subtract(const Duration(days: 1));
        s = y.millisecondsSinceEpoch;
        e = today.millisecondsSinceEpoch - 1;
        break;
      case 'last7days':
        final last7 = today.subtract(const Duration(days: 7));
        s = last7.millisecondsSinceEpoch;
        e = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch;
        break;
      case 'last30days':
        final last30 = today.subtract(const Duration(days: 30));
        s = last30.millisecondsSinceEpoch;
        e = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch;
        break;
      case 'customDays':
        final lastN = today.subtract(Duration(days: _customDays));
        s = lastN.millisecondsSinceEpoch;
        e = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch;
        break;
      case 'custom':
        if (_customStartDate != null && _customEndDate != null) {
          s = DateTime(
            _customStartDate!.year,
            _customStartDate!.month,
            _customStartDate!.day,
          ).millisecondsSinceEpoch;
          e = DateTime(
            _customEndDate!.year,
            _customEndDate!.month,
            _customEndDate!.day,
            23,
            59,
            59,
          ).millisecondsSinceEpoch;
        }
        break;
    }
    if (s == null || e == null) return null;
    return (s, e);
  }

  (int, int)? _currentSizeRange() {
    if (_sizeFilter == 'all') return null;
    switch (_sizeFilter) {
      case 'small':
        return (0, 100 * 1024);
      case 'medium':
        return (100 * 1024, 1024 * 1024);
      case 'large':
        return (1024 * 1024, 1 << 31);
    }
    return null;
  }

  // 重置筛选条件
  void _resetFilters() {
    setState(() {
      _timeFilter = 'last30days';
      _sizeFilter = 'all';
      _customStartDate = null;
      _customEndDate = null;
    });
    // 重新执行搜索以应用重置后的筛选条件
    if (_lastQuery.isNotEmpty) {
      _search(_lastQuery);
    }
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
          });
          // 重新执行搜索以应用新的筛选条件
          if (_lastQuery.isNotEmpty) {
            _search(_lastQuery);
          }
        },
        onReset: _resetFilters,
      ),
    );
  }

  Future<Map<String, dynamic>?> _ensureBoxes(String filePath) async {
    if (_lastQuery.isEmpty) return null;
    final key = '$filePath|$_lastQuery';
    final fut = _boxesFutureCache.putIfAbsent(key, () {
      return ScreenshotService.instance.getOcrMatchBoxes(
        filePath: filePath,
        query: _lastQuery,
      );
    });
    return fut;
  }

  void _openViewer(ScreenshotRecord record, int index) {
    final List<ScreenshotRecord> sameApp = _results
        .where((r) => r.appPackageName == record.appPackageName)
        .toList();
    final int initialIndex = sameApp.indexWhere((r) => r.id == record.id);
    // 从缓存中获取完整的应用信息（包含 icon）
    final appInfo =
        _appInfoByPackage[record.appPackageName] ??
        AppInfo(
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

  // 获取时间范围显示文本
  String _getTimeRangeLabel() {
    final l10n = AppLocalizations.of(context);
    switch (_timeFilter) {
      case 'all':
        return l10n.filterTimeAll;
      case 'today':
        return l10n.filterTimeToday;
      case 'yesterday':
        return l10n.filterTimeYesterday;
      case 'last7days':
        return l10n.filterTimeLast7Days;
      case 'last30days':
        return l10n.filterTimeLast30Days;
      case 'customDays':
        return '${_customDays}${l10n.days}';
      default:
        return l10n.filterTimeLast30Days;
    }
  }

  // 显示时间范围选择底部弹窗
  void _showTimeRangeSheet() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.radiusMd),
                  topRight: Radius.circular(AppTheme.radiusMd),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.spacing4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 顶部指示器
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: AppTheme.spacing3),
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Text(
                        l10n.filterByTime,
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing3),
                      // 时间选项
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildTimeChip(ctx, 'all', l10n.filterTimeAll, setSheetState),
                          _buildTimeChip(ctx, 'today', l10n.filterTimeToday, setSheetState),
                          _buildTimeChip(ctx, 'yesterday', l10n.filterTimeYesterday, setSheetState),
                          _buildTimeChip(ctx, 'last7days', l10n.filterTimeLast7Days, setSheetState),
                          _buildTimeChip(ctx, 'last30days', l10n.filterTimeLast30Days, setSheetState),
                          _buildCustomDaysChip(ctx, l10n, setSheetState),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacing2),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 构建时间选项 Chip
  Widget _buildTimeChip(BuildContext ctx, String value, String label, StateSetter setSheetState) {
    final bool selected = _timeFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _timeFilter = value);
        setSheetState(() {});
        Navigator.pop(ctx);
        if (_lastQuery.isNotEmpty) _search(_lastQuery);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(ctx).colorScheme.primary.withOpacity(0.15)
              : Theme.of(ctx).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: selected
              ? null
              : Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected
                ? Theme.of(ctx).colorScheme.primary
                : Theme.of(ctx).colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // 构建自定义天数 Chip
  Widget _buildCustomDaysChip(BuildContext ctx, AppLocalizations l10n, StateSetter setSheetState) {
    final bool selected = _timeFilter == 'customDays';
    return GestureDetector(
      onTap: () async {
        Navigator.pop(ctx);
        await _showCustomDaysDialog();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(ctx).colorScheme.primary.withOpacity(0.15)
              : Theme.of(ctx).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: selected
              ? null
              : Border.all(color: Colors.grey.withOpacity(0.2), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected ? '${_customDays}${l10n.days}' : l10n.filterTimeCustomDays,
              style: TextStyle(
                fontSize: 12,
                color: selected
                    ? Theme.of(ctx).colorScheme.primary
                    : Theme.of(ctx).colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.edit_outlined,
              size: 12,
              color: selected
                  ? Theme.of(ctx).colorScheme.primary
                  : Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6),
            ),
          ],
        ),
      ),
    );
  }

  // 显示自定义天数输入对话框（使用项目自定义弹窗）
  Future<void> _showCustomDaysDialog() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: _customDays.toString());
    
    final result = await showUIDialog<int>(
      context: context,
      title: l10n.filterTimeCustomDays,
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          hintText: l10n.filterTimeCustomDaysHint,
          suffixText: l10n.days,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
      actions: [
        UIDialogAction<int>(
          text: l10n.dialogCancel,
          style: UIDialogActionStyle.normal,
        ),
        UIDialogAction<int>(
          text: l10n.dialogOk,
          style: UIDialogActionStyle.primary,
          closeOnPress: false,
          onPressed: (ctx) async {
            final val = int.tryParse(controller.text.trim());
            if (val != null && val > 0 && val <= 365) {
              Navigator.of(ctx).pop<int>(val);
            }
          },
        ),
      ],
    );
    
    if (result != null) {
      setState(() {
        _customDays = result;
        _timeFilter = 'customDays';
      });
      if (_lastQuery.isNotEmpty) {
        _search(_lastQuery);
      }
    }
  }

  // 构建时间范围按钮（嵌入搜索框内，简洁无背景）
  Widget _buildTimeRangeDropdown() {
    final color = Theme.of(context).colorScheme.onSurface.withOpacity(0.6);
    return GestureDetector(
      onTap: _showTimeRangeSheet,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _getTimeRangeLabel(),
              style: TextStyle(
                fontSize: 12,
                color: color,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: color,
            ),
          ],
        ),
      ),
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
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.5),
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
                            hintText: AppLocalizations.of(
                              context,
                            ).searchPlaceholder,
                            hintStyle: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
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
                      // 时间范围选择按钮（嵌入搜索框内）
                      _buildTimeRangeDropdown(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedForeground),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noMatchingScreenshots,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.mutedForeground),
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
              bottom: BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).searchResultsCount(
                          _countingTotal
                              ? '...'
                              : _totalResultsCount.toString(),
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_countingTotal) ...[
                      const SizedBox(width: AppTheme.spacing1),
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacing2),
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    // 更新可见范围
                    _updateVisibleRange();
                    // 滚动活跃态：暂停OCR叠加，滚动空闲后再恢复
                    bool shouldSetActive = false;
                    if (n is ScrollUpdateNotification ||
                        n is UserScrollNotification ||
                        n is OverscrollNotification) {
                      if (!_scrollActive) shouldSetActive = true;
                      _scrollIdleTimer?.cancel();
                      _scrollIdleTimer = Timer(
                        const Duration(milliseconds: 120),
                        () {
                          if (!mounted) return;
                          if (_scrollActive) {
                            setState(() {
                              _scrollActive = false;
                            });
                          }
                        },
                      );
                    }
                    if (shouldSetActive) {
                      setState(() {
                        _scrollActive = true;
                      });
                    }
                    // 接近底部时预取下一页
                    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                      _onScroll();
                    }
                    return false;
                  },
                  child: GridView.builder(
                    key: _gridKey,
                    controller: _scrollController,
                    cacheExtent: MediaQuery.of(context).size.height,
                    addAutomaticKeepAlives: false,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.only(
                      left: AppTheme.spacing1,
                      right: AppTheme.spacing1,
                      bottom:
                          MediaQuery.of(context).padding.bottom +
                          AppTheme.spacing6,
                      top: AppTheme.spacing1,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
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

                      // 构建 OCR 标注叠加层（仅可见附近范围才请求与绘制）
                      Widget? ocrOverlay;
                      if (!_scrollActive && _shouldLoadBoxesForIndex(index)) {
                        if (_boxesFutureCache.length > 40) {
                          _boxesFutureCache.remove(
                            _boxesFutureCache.keys.first,
                          );
                        }
                        ocrOverlay = FutureBuilder<Map<String, dynamic>?>(
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
                                final b =
                                    (m['bottom'] as num?)?.toDouble() ?? 0;
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

                      final bool nsfwMasked =
                          _privacyMode &&
                          NsfwPreferenceService.instance.shouldMaskCached(s);
                      final bool isManualNsfw =
                          s.id != null &&
                          NsfwPreferenceService.instance
                              .isManuallyFlaggedCached(
                                screenshotId: s.id!,
                                appPackageName: s.appPackageName,
                              );
                      final bool isNsfwDisplay = isManualNsfw || nsfwMasked;

                      final GlobalKey itemKey = _itemKeys.putIfAbsent(
                        index,
                        () => GlobalKey(),
                      );
                      return KeyedSubtree(
                        key: itemKey,
                        child: RepaintBoundary(
                          child: ScreenshotItemWidget(
                            screenshot: s,
                            baseDir: _baseDir,
                            appInfoMap: _appInfoByPackage,
                            privacyMode: _privacyMode,
                            showNsfwButton: false,
                            isNsfwFlagged: isNsfwDisplay,
                            onTap: () => _openViewer(s, index),
                            showTimelineJumpButton: true,
                            customOverlay: ocrOverlay,
                          ),
                        ),
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
    final double scale =
        (size.width / originalWidth) > (size.height / originalHeight)
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
  final Function(
    String time,
    String size,
    DateTime? startDate,
    DateTime? endDate,
  )
  onApply;
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusMd)),
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
              _buildFilterChip(
                l10n.filterSizeAll,
                'all',
                _sizeFilter,
                (v) => setState(() => _sizeFilter = v),
              ),
              _buildFilterChip(
                l10n.filterSizeSmall,
                'small',
                _sizeFilter,
                (v) => setState(() => _sizeFilter = v),
              ),
              _buildFilterChip(
                l10n.filterSizeMedium,
                'medium',
                _sizeFilter,
                (v) => setState(() => _sizeFilter = v),
              ),
              _buildFilterChip(
                l10n.filterSizeLarge,
                'large',
                _sizeFilter,
                (v) => setState(() => _sizeFilter = v),
              ),
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
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.5),
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

  Widget _buildFilterChip(
    String label,
    String value,
    String currentValue,
    Function(String) onSelected,
  ) {
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      side: isSelected
          ? BorderSide.none
          : BorderSide(color: Colors.grey.withOpacity(0.2), width: 1),
    );
  }
}
