import 'package:flutter/material.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/widgets/ui_dialog.dart';
import 'package:screen_memo/models/app_info.dart';
import 'package:screen_memo/models/screenshot_record.dart';
import 'package:screen_memo/features/capture/application/screenshot_service.dart';
import 'package:screen_memo/features/gallery/presentation/widgets/screenshot_item_widget.dart';
import 'package:screen_memo/core/widgets/search_styles.dart';
import 'package:screen_memo/core/widgets/screenshot_style_tab_bar.dart';
import 'package:screen_memo/features/apps/application/app_selection_service.dart';
import 'package:screen_memo/core/logging/flutter_logger.dart';
import 'package:screen_memo/features/favorites/application/favorite_service.dart';
import 'package:screen_memo/data/platform/path_service.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/features/nsfw/application/nsfw_preference_service.dart';

/// 内部：日期Tab信息（一天为单位）
class _DayTabInfo {
  final DateTime day;
  final int startMillis;
  final int endMillis;
  int count;

  _DayTabInfo({
    required this.day,
    required this.startMillis,
    required this.endMillis,
    this.count = 0,
  });

  static bool _isSameYMD(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static bool _isToday(DateTime d) => _isSameYMD(d, DateTime.now());
  static bool _isYesterday(DateTime d) =>
      _isSameYMD(d, DateTime.now().subtract(const Duration(days: 1)));

  String buildLabel() {
    if (_isToday(day)) return '今天 $count';
    if (_isYesterday(day)) return '昨天 $count';
    return '${day.month}月${day.day}日 $count';
  }
}

class ScreenshotGalleryPage extends StatefulWidget {
  const ScreenshotGalleryPage({super.key});

  @override
  State<ScreenshotGalleryPage> createState() => _ScreenshotGalleryPageState();
}

class _ScreenshotGalleryPageState extends State<ScreenshotGalleryPage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  late AppInfo _appInfo;
  late String _packageName;
  List<ScreenshotRecord> _screenshots = [];
  bool _isLoading = false; // 默认不显示加载，直接显示内容
  String? _error;
  Directory? _baseDir;
  final ScrollController _scrollController = ScrollController();
  // 搜索
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<ScreenshotRecord> _searchResults = <ScreenshotRecord>[];
  Timer? _searchDebounce;
  final Map<String, Future<Map<String, dynamic>?>> _boxesFutureCache =
      <String, Future<Map<String, dynamic>?>>{};

  // 多选状态
  bool _selectionMode = false;
  final Set<int> _selectedIds = <int>{};
  final Map<int, GlobalKey> _itemKeys = <int, GlobalKey>{};
  bool _isFullySelected = false; // 标记是否已经全选所有数据
  // 收藏状态缓存
  final Map<int, bool> _favoriteStatus = <int, bool>{};
  // 取消滑动选择
  bool _initialized = false; // 避免返回时重复触发初始化加载
  bool _privacyMode = true; // 默认开启

  // 缓存相关
  static const String _screenshotsCacheKeyPrefix = 'screenshots_cache_';
  static const String _screenshotsCacheTsKeyPrefix = 'screenshots_cache_ts_';
  static const int _screenshotsCacheTtlSeconds = 300; // 仅影响截图列表，不影响首页统计

  // 时间线滚动条交互状态
  bool _timelineActive = false; // 是否正在与时间线交互（长按或拖拽）
  double _timelineFraction = 0.0; // 拖动时的归一化位置 0..1
  final GlobalKey _gridKey = GlobalKey(); // 获取网格可见区域以计算首个可见项
  // 时间线拖动时的逐帧节流标记，避免频繁 jumpTo 造成抖动
  bool _scrubJumpScheduled = false;

  // 分页与懒加载
  static const int _initialPageSize = 8; // 首屏项数（用户一屏可见4个，初始加载8个确保体验）
  static const int _pageSize = 16; // 后续每次追加项数
  bool _isLoadingMore = false; // 是否正在加载更多
  bool _hasMore = true; // 是否还有更多数据
  // 旧：全量列表 _allScreenshots 已弃用（真分页改为仅维护已加载页的列表）
  int _currentDisplayCount = 0; // 当前已显示的数量
  int _pageOffset = 0; // 真分页：已加载偏移量

  // 头部统计（使用全量数据计算，避免分页导致统计不准确）
  int _totalCount = 0;
  int _totalSize = 0;
  DateTime? _latestTime;

  // 日期Tab/过滤
  TabController? _tabController;
  // 完整日期列表与当前可见窗口（默认最近14天，向前增量加载）
  final List<_DayTabInfo> _allDayTabs = <_DayTabInfo>[];
  final List<_DayTabInfo> _dayTabs = <_DayTabInfo>[];
  int _currentTabIndex = 0;
  int? _dateFilterStartMillis;
  int? _dateFilterEndMillis;
  // 简单的每Tab数据缓存，避免切换瞬时显示上一个Tab内容
  final Map<int, List<ScreenshotRecord>> _tabCache =
      <int, List<ScreenshotRecord>>{};
  final Map<int, int> _tabOffset = <int, int>{};
  final Map<int, bool> _tabHasMore = <int, bool>{};
  final Map<int, double> _tabScrollOffset = <int, double>{};
  final Map<int, ScrollController> _tabControllers = <int, ScrollController>{};

  // OCR 标注绘制器（复用全局搜索样式）

  // 日期窗口控制：默认最近14天，每次向前追加14天
  static const int _initialVisibleDayTabs = 14;
  static const int _appendVisibleDayTabs = 14;
  bool _isExpandingDayTabs = false;

  ScrollController _controllerForTab(int index) {
    if (index < 0) index = 0;
    final existing = _tabControllers[index];
    if (existing != null) return existing;
    final initial = _tabScrollOffset[index] ?? 0.0;
    final ctrl = ScrollController(initialScrollOffset: initial);
    ctrl.addListener(() => _onScrollChangedForTab(ctrl, index));
    _tabControllers[index] = ctrl;
    return ctrl;
  }

  void _onScrollChangedForTab(ScrollController ctrl, int index) {
    // 刷新时间线位置（仅当前Tab）
    if (!_timelineActive && mounted && index == _currentTabIndex) {
      setState(() {});
    }
    // 仅当前Tab触发加载更多
    if (index == _currentTabIndex &&
        _hasMore &&
        !_isLoadingMore &&
        ctrl.hasClients) {
      final maxScroll = ctrl.position.maxScrollExtent;
      final currentScroll = ctrl.position.pixels;
      final threshold = maxScroll * 0.8;
      if (currentScroll >= threshold) {
        _loadMoreScreenshots();
      }
    }
    // 记录滚动偏移
    try {
      if (ctrl.hasClients) {
        final double pos = ctrl.position.pixels;
        final double max = ctrl.position.hasPixels
            ? ctrl.position.maxScrollExtent
            : pos;
        final double clamped = pos.clamp(0.0, max);
        _tabScrollOffset[index] = clamped;
      }
    } catch (_) {}
  }

  Future<void> _prefetchFirstPageForTab(int index) async {
    if (!mounted) return;
    if (index < 0 || index >= _dayTabs.length) return;
    if ((_tabCache[index]?.isNotEmpty ?? false)) return;
    final day = _dayTabs[index];
    if (day.count <= 0) return;
    try {
      final batch = await ScreenshotService.instance.getScreenshotsByAppBetween(
        _packageName,
        startMillis: day.startMillis,
        endMillis: day.endMillis,
        limit: _initialPageSize,
        offset: 0,
      );
      // 二次过滤：严格限定同一天，且最多取 _initialPageSize
      final filtered = batch
          .where((r) => _DayTabInfo._isSameYMD(r.captureTime, day.day))
          .take(_initialPageSize)
          .toList();
      if (!mounted) return;
      setState(() {
        _tabCache[index] = List<ScreenshotRecord>.from(filtered);
        _tabOffset[index] = filtered.length;
        _tabHasMore[index] = filtered.length < day.count;
        if (index == _currentTabIndex && _screenshots.isEmpty) {
          _screenshots = List<ScreenshotRecord>.from(filtered);
          _currentDisplayCount = _screenshots.length;
          _pageOffset = _tabOffset[index] ?? _screenshots.length;
          _hasMore = _tabHasMore[index] ?? false;
        }
      });
      // 预加载该批手动标记
      // ignore: unawaited_futures
      _preloadManualFlagsFor(filtered);
    } catch (_) {}
  }

  Future<void> _prefetchAllTabsFirst8() async {
    for (int i = 0; i < _dayTabs.length; i++) {
      // 顺序预取，避免并发压力
      await _prefetchFirstPageForTab(i);
    }
  }

  /// 当当前日期Tab被删空时，自动移除该Tab并跳转到上一可用日期
  Future<void> _switchAwayIfCurrentDayEmpty() async {
    if (!mounted) return;
    if (_tabController == null || _dayTabs.isEmpty) return;
    if (_currentTabIndex < 0 || _currentTabIndex >= _dayTabs.length) return;
    final int curCount = _dayTabs[_currentTabIndex].count;
    if (curCount > 0) return;

    // 清理当前Tab的缓存/滚动状态
    _tabCache.remove(_currentTabIndex);
    _tabOffset.remove(_currentTabIndex);
    _tabHasMore.remove(_currentTabIndex);
    _tabScrollOffset.remove(_currentTabIndex);

    final int oldIndex = _currentTabIndex;
    _tabController?.removeListener(_onTabControllerChanged);
    _tabController?.dispose();
    _tabController = null;

    setState(() {
      // 移除当前已为空的日期Tab
      if (oldIndex >= 0 && oldIndex < _dayTabs.length) {
        _dayTabs.removeAt(oldIndex);
      }
      // 清空当前展示，等待切换
      _screenshots.clear();
      _currentDisplayCount = 0;
      _hasMore = true;
      _selectionMode = false;
      _isFullySelected = false;
      _selectedIds.clear();
    });

    if (_dayTabs.isNotEmpty) {
      final int newIndex = (oldIndex > 0) ? oldIndex - 1 : 0;
      final TabController ctrl = TabController(
        length: _dayTabs.length,
        vsync: this,
      );
      ctrl.addListener(_onTabControllerChanged);
      setState(() {
        _tabController = ctrl;
        _currentTabIndex = (newIndex >= 0 && newIndex < _dayTabs.length)
            ? newIndex
            : 0;
        _tabController!.index = _currentTabIndex;
        _dateFilterStartMillis = _dayTabs[_currentTabIndex].startMillis;
        _dateFilterEndMillis = _dayTabs[_currentTabIndex].endMillis;
      });
      await _onTabIndexSelected(_currentTabIndex);
    } else {
      // 无任何日期Tab，允许显示空状态
      setState(() {
        _tabController = null;
        _dateFilterStartMillis = null;
        _dateFilterEndMillis = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // 主控制器用于当前Tab，其他Tab使用各自controller
    _loadPrivacyMode();
    // 预加载 NSFW 规则（异步，不阻塞UI）
    // ignore: unawaited_futures
    NsfwPreferenceService.instance.ensureRulesLoaded();
    // 订阅隐私模式变更
    AppSelectionService.instance.onPrivacyModeChanged.listen((enabled) {
      if (!mounted) return;
      setState(() {
        _privacyMode = enabled;
      });
    });
    // 搜索框焦点变化用于切换内嵌统计显示
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(text);
    });
  }

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (!mounted) return;
    setState(() {
      _searchQuery = q;
      _searchResults = <ScreenshotRecord>[];
    });
    if (q.isEmpty) return;
    try {
      final results = await ScreenshotService.instance
          .searchScreenshotsByOcrForApp(_packageName, q, limit: 400, offset: 0);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
      });
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _ensureBoxes(String filePath) async {
    if (_searchQuery.isEmpty) return null;
    final key = '$filePath|$_searchQuery';
    final fut = _boxesFutureCache.putIfAbsent(key, () {
      return ScreenshotService.instance.getOcrMatchBoxes(
        filePath: filePath,
        query: _searchQuery,
      );
    });
    return fut;
  }

  Future<void> _loadPrivacyMode() async {
    try {
      final enabled = await AppSelectionService.instance
          .getPrivacyModeEnabled();
      if (mounted)
        setState(() {
          _privacyMode = enabled;
        });
    } catch (_) {}
  }

  /// 基于数据库返回的“有数据的所有日期”生成 Tabs（倒序），默认仅展示最近14天，
  /// 当用户滑动/切换到最后一个可见日期时，再按批次追加更早日期。
  Future<void> _prepareDayTabs() async {
    if (!mounted) return;
    final List<_DayTabInfo> tabs = <_DayTabInfo>[];
    try {
      final days = await ScreenshotService.instance.listAvailableDaysForApp(
        _packageName,
      );
      for (final m in days) {
        final String ds = (m['date'] as String?) ?? '';
        final int count = (m['count'] as int?) ?? 0;
        if (ds.isEmpty || count <= 0) continue;
        try {
          final parts = ds.split('-');
          if (parts.length != 3) continue;
          final int y = int.parse(parts[0]);
          final int mo = int.parse(parts[1]);
          final int d = int.parse(parts[2]);
          final DateTime day = DateTime(y, mo, d);
          final int start = DateTime(y, mo, d).millisecondsSinceEpoch;
          final int end = DateTime(y, mo, d, 23, 59, 59).millisecondsSinceEpoch;
          tabs.add(
            _DayTabInfo(
              day: day,
              startMillis: start,
              endMillis: end,
              count: count,
            ),
          );
        } catch (_) {}
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _allDayTabs
        ..clear()
        ..addAll(tabs);
      final int visibleCount = _allDayTabs.isEmpty
          ? 0
          : math.min(_initialVisibleDayTabs, _allDayTabs.length);
      _dayTabs
        ..clear()
        ..addAll(_allDayTabs.take(visibleCount));

      _tabController?.removeListener(_onTabControllerChanged);
      _tabController?.dispose();
      if (_dayTabs.isNotEmpty) {
        _currentTabIndex = 0;
        _dateFilterStartMillis = _dayTabs[0].startMillis;
        _dateFilterEndMillis = _dayTabs[0].endMillis;
        _tabController = TabController(length: _dayTabs.length, vsync: this);
        _tabController!.addListener(_onTabControllerChanged);
      } else {
        _currentTabIndex = 0;
        _dateFilterStartMillis = null;
        _dateFilterEndMillis = null;
        _tabController = null;
      }
    });
    if (_dayTabs.isNotEmpty) {
      await _prefetchAllTabsFirst8();
      await _onTabIndexSelected(0);
    }
  }

  void _onTabControllerChanged() {
    if (_tabController == null) return;
    if (_tabController!.indexIsChanging) return; // 避免重复
    final int idx = _tabController!.index;
    // 若当前已处于“最后一个可见日期Tab”，尝试向前扩展更多日期
    if (idx == _dayTabs.length - 1) {
      _expandDayTabsIfNeeded();
    }
    // 优先确保相邻Tab也有首屏缓存，提升滑动预览体验
    // ignore: unawaited_futures
    _prefetchFirstPageForTab(idx - 1);
    // ignore: unawaited_futures
    _prefetchFirstPageForTab(idx + 1);
    _onTabIndexSelected(idx);
  }

  /// 当用户滑动到当前最后一个日期Tab附近时，尝试将可见窗口向前扩展14天
  void _expandDayTabsIfNeeded() {
    if (!mounted) return;
    if (_isExpandingDayTabs) return;
    if (_allDayTabs.isEmpty) return;
    if (_dayTabs.length >= _allDayTabs.length) return; // 已展示全部日期

    _isExpandingDayTabs = true;
    try {
      final int currentVisible = _dayTabs.length;
      final int targetVisible = math.min(
        _allDayTabs.length,
        currentVisible + _appendVisibleDayTabs,
      );
      if (targetVisible <= currentVisible) return;

      final int currentIndex = _tabController?.index ?? _currentTabIndex;

      _tabController?.removeListener(_onTabControllerChanged);
      _tabController?.dispose();

      setState(() {
        _dayTabs
          ..clear()
          ..addAll(_allDayTabs.take(targetVisible));
      });

      _tabController = TabController(
        length: _dayTabs.length,
        vsync: this,
        initialIndex: currentIndex.clamp(0, _dayTabs.length - 1),
      );
      _tabController!.addListener(_onTabControllerChanged);
    } finally {
      _isExpandingDayTabs = false;
    }
  }

  Future<void> _onTabIndexSelected(int index) async {
    if (index < 0 || index >= _dayTabs.length) return;
    if (_currentTabIndex == index && _screenshots.isNotEmpty) return;
    // 切换前保存旧Tab的滚动偏移
    try {
      if (_scrollController.hasClients) {
        _tabScrollOffset[_currentTabIndex] = _scrollController.position.pixels;
      }
    } catch (_) {}
    setState(() {
      _currentTabIndex = index;
      _dateFilterStartMillis = _dayTabs[index].startMillis;
      _dateFilterEndMillis = _dayTabs[index].endMillis;
      // 切换时先从缓存展示，避免闪现上一页内容
      final cached = _tabCache[index];
      if (cached != null) {
        _screenshots = List<ScreenshotRecord>.from(cached);
        _currentDisplayCount = _screenshots.length;
        _hasMore = _tabHasMore[index] ?? false;
        _pageOffset = _tabOffset[index] ?? _screenshots.length;
      } else {
        _screenshots.clear();
        _currentDisplayCount = 0;
        _hasMore = true;
      }
      _selectedIds.clear();
      _isFullySelected = false;
    });
    // 预加载当前可见集的手动 NSFW 标记
    // ignore: unawaited_futures
    _preloadManualFlagsFor(_screenshots);
    await _refreshCurrentTabCount();
    // 若缺少首屏缓存，补一次加载；否则按需继续加载更多
    if ((_tabCache[index]?.isEmpty ?? true)) {
      await _loadScreenshots();
    } else if (_hasMore) {
      // 不阻塞UI，后台加载下一页
      // ignore: unawaited_futures
      _loadMoreScreenshots();
    }
    // 恢复新Tab的滚动偏移（若存在）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final ctrl = _controllerForTab(index);
        if (ctrl.hasClients) {
          final double restoreRaw = _tabScrollOffset[index] ?? 0.0;
          final double max = ctrl.position.maxScrollExtent;
          final double restore = restoreRaw.clamp(0.0, max);
          if (restore > 0) {
            ctrl.jumpTo(restore);
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _refreshCurrentTabCount() async {
    if (_currentTabIndex < 0 || _currentTabIndex >= _dayTabs.length) return;
    try {
      final c = await ScreenshotService.instance.getScreenshotCountByAppBetween(
        _packageName,
        startMillis: _dayTabs[_currentTabIndex].startMillis,
        endMillis: _dayTabs[_currentTabIndex].endMillis,
      );
      if (!mounted) return;
      setState(() {
        _dayTabs[_currentTabIndex].count = c;
      });
    } catch (_) {}
  }

  void _onScrollChanged() {
    // 非交互状态下，同步刷新以更新时间线拇指位置
    if (!_timelineActive && mounted) {
      setState(() {});
    }

    // 检查是否需要加载更多
    // 主控制器不再统一承载滚动监听（每Tab独立监听）
  }

  /// 加载更多截图到显示列表
  Future<void> _loadMoreScreenshots() async {
    if (_isLoadingMore || !_hasMore) return;
    if (!mounted) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final int limit = _currentDisplayCount == 0
          ? _initialPageSize
          : _pageSize;
      List<ScreenshotRecord> batch = <ScreenshotRecord>[];
      if (_dateFilterStartMillis != null && _dateFilterEndMillis != null) {
        batch = await ScreenshotService.instance.getScreenshotsByAppBetween(
          _packageName,
          startMillis: _dateFilterStartMillis!,
          endMillis: _dateFilterEndMillis!,
          limit: limit,
          offset: _pageOffset,
        );
        // 二次过滤，避免跨日混入
        final day = _dayTabs[_currentTabIndex].day;
        batch = batch
            .where((r) => _DayTabInfo._isSameYMD(r.captureTime, day))
            .toList();
      } else {
        batch = await ScreenshotService.instance.getScreenshotsByApp(
          _packageName,
          limit: limit,
          offset: _pageOffset,
        );
      }

      if (!mounted) return;
      setState(() {
        if (batch.isEmpty) {
          _hasMore = false;
        } else {
          // 追加并去重（按 id 去重）
          final existingIds = _screenshots
              .where((e) => e.id != null)
              .map((e) => e.id!)
              .toSet();
          for (final r in batch) {
            final id = r.id;
            if (id != null && existingIds.contains(id)) continue;
            _screenshots.add(r);
          }
          _pageOffset += batch.length;
          _currentDisplayCount = _screenshots.length;
          // 依据当前筛选（天）或全量决定是否还有更多
          int expectedTotal = _totalCount;
          if (_dateFilterStartMillis != null &&
              _dateFilterEndMillis != null &&
              _currentTabIndex >= 0 &&
              _currentTabIndex < _dayTabs.length) {
            expectedTotal = _dayTabs[_currentTabIndex].count;
          }
          _hasMore = _currentDisplayCount < expectedTotal;

          // 如果是全选状态，将新加载的项也加入选择
          if (_isFullySelected) {
            final newIds = _screenshots
                .where((s) => s.id != null && !_selectedIds.contains(s.id))
                .map((s) => s.id!)
                .toSet();
            _selectedIds.addAll(newIds);
          }

          // 缓存当前Tab内容，避免切换时回显旧页
          _tabCache[_currentTabIndex] = List<ScreenshotRecord>.from(
            _screenshots,
          );
          _tabOffset[_currentTabIndex] = _pageOffset;
          _tabHasMore[_currentTabIndex] = _hasMore;
          // 清理不在显示范围内的键
          _itemKeys.removeWhere((index, _) => index >= _screenshots.length);
        }
        _isLoadingMore = false;
      });
      // 预加载本批手动 NSFW 标记
      // ignore: unawaited_futures
      _preloadManualFlagsFor(batch);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
        _error = AppLocalizations.of(
          context,
        ).loadMoreFailedWithError(e.toString());
      });
    }
  }

  /// 构建标题栏右侧统计文本：X张 · Y.YYMB/GB/TB · 时间（本地化）
  String _buildHeaderStatsText() {
    final l10n = AppLocalizations.of(context);
    String timeStr = l10n.none;
    if (_latestTime != null) {
      timeStr = _formatDateTimeForStats(_latestTime!);
    }
    return '${l10n.imagesCountLabel(_totalCount)} · ${_formatTotalSizeMBGBTB(_totalSize)} · $timeStr';
  }

  /// 格式化时间（用于统计显示）
  String _formatDateTimeForStats(DateTime dateTime) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return l10n.justNow;
    } else if (diff.inHours < 1) {
      return l10n.minutesAgo(diff.inMinutes);
    } else if (diff.inDays < 1) {
      return l10n.hoursAgo(diff.inHours);
    } else if (diff.inDays < 7) {
      return l10n.daysAgo(diff.inDays);
    } else {
      final bool sameYear = now.year == dateTime.year;
      final String hh = dateTime.hour.toString().padLeft(2, '0');
      final String mm = dateTime.minute.toString().padLeft(2, '0');
      if (sameYear) {
        return l10n.monthDayTime(dateTime.month, dateTime.day, hh, mm);
      } else {
        return l10n.yearMonthDayTime(
          dateTime.year,
          dateTime.month,
          dateTime.day,
          hh,
          mm,
        );
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _appInfo = args['appInfo'] as AppInfo;
      _packageName = args['packageName'] as String;
      _loadInitialData();
      // 准备日期Tabs（异步）
      // ignore: unawaited_futures
      _prepareDayTabs();
    } else {
      setState(() {
        _error = AppLocalizations.of(context).invalidArguments;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadInitialData() async {
    try {
      // 使用PathService获取正确的外部文件目录
      final dir = await PathService.getInternalAppDir(null);

      if (dir == null) {
        throw Exception("无法获取应用目录");
      }

      print('路径服务返回的目录: ${dir.path}');

      setState(() {
        _baseDir = dir;
      });
      await _loadScreenshots();
    } catch (e) {
      setState(() {
        _error = AppLocalizations.of(context).initFailedWithError(e.toString());
      });
    }
  }

  Future<void> _loadScreenshots() async {
    try {
      print('=== 开始加载截图 ===');
      print('应用包名: $_packageName');
      print('基础目录: ${_baseDir?.path}');
      print('当前截图数量: ${_screenshots.length}');

      // 先设置加载状态，防止显示空状态
      if (_screenshots.isEmpty) {
        setState(() {
          _isLoading = true;
        });
      }

      // 先获取统计，确定总量和最近时间、总大小
      try {
        final stats = await ScreenshotService.instance
            .getScreenshotStatsCachedFirst();
        final appStatsMap = stats['appStatistics'];
        if (appStatsMap is Map) {
          final dynamic raw = appStatsMap[_packageName];
          if (raw is Map) {
            _totalCount = (raw['totalCount'] as int?) ?? 0;
            final lc = raw['lastCaptureTime'];
            if (lc is DateTime) {
              _latestTime = lc;
            } else if (lc is int) {
              _latestTime = DateTime.fromMillisecondsSinceEpoch(lc);
            }
            _totalSize = (raw['totalSize'] as int?) ?? 0;
          }
        }
        if (_totalCount <= 0) {
          _totalCount = await ScreenshotService.instance
              .getScreenshotCountByApp(_packageName);
        }
      } catch (_) {
        // 统计失败不阻塞首屏，后续展示用默认值
      }

      // 重置分页并加载第一页
      setState(() {
        _screenshots.clear();
        _currentDisplayCount = 0;
        _pageOffset = 0;
        _hasMore = _totalCount > 0;
      });

      await _loadMoreScreenshots();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      // 预加载本页的手动 NSFW 标记缓存
      // ignore: unawaited_futures
      _preloadManualFlagsFor(_screenshots);
    } catch (e) {
      print('加载截图失败: $e');
      setState(() {
        _error = '加载截图失败: $e';
        _isLoading = false;
      });
    }
  }

  // 旧的全量处理逻辑移除，统计在 _loadScreenshots 首次加载时已设置

  // 旧的“全量加载”函数已移除，改为真分页按需加载

  /// 从缓存加载截图数据
  Future<List<ScreenshotRecord>?> _loadScreenshotsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_screenshotsCacheKeyPrefix$_packageName';
      final tsKey = '$_screenshotsCacheTsKeyPrefix$_packageName';

      final cachedJson = prefs.getString(cacheKey);
      final ts = prefs.getInt(tsKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (cachedJson != null &&
          ts > 0 &&
          (now - ts) <= _screenshotsCacheTtlSeconds * 1000) {
        final List<dynamic> decoded = jsonDecode(cachedJson);
        return decoded.map((item) => ScreenshotRecord.fromMap(item)).toList();
      }
      return null;
    } catch (e) {
      print('从缓存加载截图失败: $e');
      return null;
    }
  }

  /// 保存截图数据到缓存
  Future<void> _saveScreenshotsToCache(
    List<ScreenshotRecord> screenshots,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_screenshotsCacheKeyPrefix$_packageName';
      final tsKey = '$_screenshotsCacheTsKeyPrefix$_packageName';

      final jsonList = screenshots.map((s) => s.toMap()).toList();
      await prefs.setString(cacheKey, jsonEncode(jsonList));
      await prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('保存截图到缓存失败: $e');
    }
  }

  /// 后台刷新截图缓存
  Future<void> _refreshScreenshotsCache() async {
    try {
      // 分页场景：仅缓存当前已加载的前若干项，避免过大
      await _saveScreenshotsToCache(_screenshots);
    } catch (e) {
      print('后台刷新截图缓存失败: $e');
    }
  }

  /// 使截图缓存失效
  Future<void> _invalidateScreenshotsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_screenshotsCacheKeyPrefix$_packageName';
      final tsKey = '$_screenshotsCacheTsKeyPrefix$_packageName';

      await prefs.remove(cacheKey);
      await prefs.remove(tsKey);
      print('已使截图缓存失效: $cacheKey');
    } catch (e) {
      print('使截图缓存失效失败: $e');
    }
  }

  void _viewScreenshot(ScreenshotRecord screenshot, int index) {
    // 选择正确的数据集与索引（搜索模式使用搜索结果集）
    final List<ScreenshotRecord> data = _searchQuery.isNotEmpty
        ? _searchResults
        : _screenshots;
    int initialIndex = index;
    if (initialIndex < 0 ||
        initialIndex >= data.length ||
        (data[initialIndex].id != screenshot.id)) {
      final byId = data.indexWhere((s) => s.id == screenshot.id);
      if (byId >= 0) {
        initialIndex = byId;
      } else {
        final byPath = data.indexWhere(
          (s) => s.filePath == screenshot.filePath,
        );
        if (byPath >= 0) {
          initialIndex = byPath;
        } else {
          initialIndex = 0;
        }
      }
    }
    // 查看时使用全量数据，确保可以滑动查看所有图片
    Navigator.pushNamed(
      context,
      '/screenshot_viewer',
      arguments: {
        // 真分页：仅传当前已加载的截图集合
        'screenshots': data,
        'initialIndex': initialIndex,
        'appName': _appInfo.appName,
        'appInfo': _appInfo, // 传递完整的appInfo对象，包含图标
      },
    );
  }

  Future<void> _openAppScreenshotSettings() async {
    final Object? result = await Navigator.of(context).pushNamed(
      '/app_screenshot_settings',
      arguments: {'appInfo': _appInfo, 'packageName': _packageName},
    );
    if (!mounted || result is! int || result <= 0) return;
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _searchResults.clear();
      _selectionMode = false;
      _selectedIds.clear();
      _isFullySelected = false;
      _screenshots.clear();
      _tabCache.clear();
      _tabOffset.clear();
      _tabHasMore.clear();
      _tabScrollOffset.clear();
      _itemKeys.clear();
    });
    await _invalidateScreenshotsCache();
    await _prepareDayTabs();
    await _loadScreenshots();
    if (!mounted) return;
    UINotifier.success(
      context,
      AppLocalizations.of(context).deletedCountToast(result),
    );
  }

  Future<void> _deleteScreenshot(ScreenshotRecord screenshot) async {
    final confirmed = await showUIDialog<bool>(
      context: context,
      title: AppLocalizations.of(context).confirmDeleteTitle,
      message: AppLocalizations.of(context).confirmDeleteMessage,
      actions: [
        UIDialogAction<bool>(
          text: AppLocalizations.of(context).dialogCancel,
          result: false,
        ),
        UIDialogAction<bool>(
          text: AppLocalizations.of(context).actionDelete,
          style: UIDialogActionStyle.destructive,
          result: true,
        ),
      ],
      barrierDismissible: false,
    );

    if (confirmed == true && screenshot.id != null) {
      // 记录UI层删除请求日志（文件与原生）
      // ignore: unawaited_futures
      FlutterLogger.info(
        'UI.删除单图-发起 id=${screenshot.id} 包=${_appInfo.packageName} 路径=${screenshot.filePath}',
      );
      // ignore: unawaited_futures
      FlutterLogger.nativeInfo(
        'UI',
        '删除截图 id=${screenshot.id} 包名=${_appInfo.packageName}',
      );
      try {
        final success = await ScreenshotService.instance.deleteScreenshot(
          screenshot.id!,
          _appInfo.packageName,
        );
        if (success) {
          // ignore: unawaited_futures
          FlutterLogger.info(
            'UI.删除单图-成功 id=${screenshot.id} 包=${_appInfo.packageName}',
          );
          // ignore: unawaited_futures
          FlutterLogger.nativeInfo('UI', '删除截图成功 id=${screenshot.id}');
          setState(() {
            _screenshots.removeWhere((s) => s.id == screenshot.id);
            _currentDisplayCount = _screenshots.length;
            if (_totalCount > 0) _totalCount -= 1;
            // 同步更新当前日期Tab计数
            if (_dayTabs.isNotEmpty &&
                _currentTabIndex >= 0 &&
                _currentTabIndex < _dayTabs.length) {
              final cur = _dayTabs[_currentTabIndex].count;
              _dayTabs[_currentTabIndex].count = (cur - 1).clamp(0, 1 << 31);
            }
          });
          // 删除后失效首页统计缓存
          await ScreenshotService.instance.invalidateStatsCache();
          // 删除后失效截图列表缓存
          await _invalidateScreenshotsCache();

          if (mounted) {
            UINotifier.success(
              context,
              AppLocalizations.of(context).screenshotDeletedToast,
            );
          }
        } else {
          // ignore: unawaited_futures
          FlutterLogger.warn(
            'UI.删除单图-失败 id=${screenshot.id} 包=${_appInfo.packageName}',
          );
          // ignore: unawaited_futures
          FlutterLogger.nativeWarn('UI', '删除截图失败 id=${screenshot.id}');
          if (mounted) {
            UINotifier.error(
              context,
              AppLocalizations.of(context).deleteFailed,
            );
          }
        }
      } catch (e) {
        // ignore: unawaited_futures
        FlutterLogger.error('UI.删除单图-异常: $e');
        // ignore: unawaited_futures
        FlutterLogger.nativeError('UI', '删除截图异常：$e');
        if (mounted) {
          UINotifier.error(
            context,
            AppLocalizations.of(context).deleteFailedWithError(e.toString()),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            // 左侧独立logo移除：搜索框已内嵌应用图标
            Expanded(
              child: _selectionMode
                  ? Text(
                      AppLocalizations.of(
                        context,
                      ).selectedItemsCount(_selectedIds.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Container(
                      height: SearchStyles.fieldHeight,
                      decoration: SearchStyles.fieldDecoration(context),
                      alignment: Alignment.center,
                      child: ClipRRect(
                        borderRadius: SearchStyles.fieldBorderRadius,
                        child: TextField(
                          focusNode: _searchFocusNode,
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          onSubmitted: _performSearch,
                          textInputAction: TextInputAction.search,
                          style: SearchStyles.inputTextStyle(context),
                          decoration: SearchStyles.inputDecoration(
                            context: context,
                            hintText: AppLocalizations.of(
                              context,
                            ).searchPlaceholder,
                            prefixIcon: (_appInfo.icon != null)
                                ? Padding(
                                    padding: const EdgeInsets.only(
                                      left: 8,
                                      right: 6,
                                    ),
                                    child: Image.memory(
                                      _appInfo.icon!,
                                      width: 18,
                                      height: 18,
                                      fit: BoxFit.contain,
                                    ),
                                  )
                                : const Padding(
                                    padding: EdgeInsets.only(left: 8, right: 6),
                                    child: Icon(Icons.android, size: 18),
                                  ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 0,
                              minHeight: 0,
                            ),
                            // 去掉右侧搜索图标，仅在有文本时显示清除
                            suffixIcon:
                                (_searchQuery.isNotEmpty ||
                                    _searchController.text.isNotEmpty)
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    tooltip: AppLocalizations.of(
                                      context,
                                    ).actionClear,
                                    onPressed: () {
                                      _searchController.clear();
                                      _performSearch('');
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          if (!_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: _openAppScreenshotSettings,
              tooltip: AppLocalizations.of(context).screenshotSectionTitle,
            ),
          ] else ...[
            TextButton(
              onPressed: () {
                setState(() {
                  _selectionMode = false;
                  _selectedIds.clear();
                  _isFullySelected = false; // 重置全选状态
                });
              },
              child: Text(AppLocalizations.of(context).dialogCancel),
            ),
            TextButton(
              onPressed: () async {
                if (_isFullySelected) {
                  setState(() {
                    _selectedIds.clear();
                    _isFullySelected = false;
                  });
                  return;
                }
                // 依据当前筛选（天Tab）决定全选范围
                List<int> allIds = <int>[];
                try {
                  if (_dateFilterStartMillis != null &&
                      _dateFilterEndMillis != null &&
                      _currentTabIndex >= 0 &&
                      _currentTabIndex < _dayTabs.length) {
                    final day = _dayTabs[_currentTabIndex];
                    allIds = await ScreenshotService.instance
                        .getScreenshotIdsByAppBetween(
                          _packageName,
                          startMillis: day.startMillis,
                          endMillis: day.endMillis,
                        );
                  } else {
                    allIds = await ScreenshotService.instance
                        .getAllScreenshotIdsForApp(_packageName);
                  }
                } catch (_) {}
                if (!mounted) return;
                setState(() {
                  _selectedIds
                    ..clear()
                    ..addAll(allIds);
                  _isFullySelected = true;
                  _selectionMode = true;
                });
              },
              child: Text(_getSelectAllButtonText()),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: AppLocalizations.of(context).deleteSelectedTooltip,
              onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // 搜索模式：优先显示搜索结果
    if (_searchQuery.isNotEmpty) {
      return _buildSearchResultGrid();
    }
    // 优先显示错误状态
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppTheme.destructive,
            ),
            const SizedBox(height: AppTheme.spacing4),
            Text(
              _error!,
              style: const TextStyle(color: AppTheme.destructive),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacing4),
            UIButton(
              text: AppLocalizations.of(context).actionRetry,
              onPressed: _loadInitialData,
              variant: UIButtonVariant.outline,
            ),
          ],
        ),
      );
    }

    // 如果有数据就直接显示网格+Tab栏，即使数据正在加载
    if (_screenshots.isNotEmpty || _isLoading) {
      return _buildTabsAndGrid();
    }

    // 只有在确实没有数据且不在加载时才显示空状态
    if (_screenshots.isEmpty && !_isLoading) {
      // 延迟显示空状态，给缓存加载一点时间
      return FutureBuilder(
        future: Future.delayed(const Duration(milliseconds: 300)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              _screenshots.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    size: 64,
                    color: AppTheme.mutedForeground,
                  ),
                  const SizedBox(height: AppTheme.spacing4),
                  Text(
                    AppLocalizations.of(context).noScreenshotsTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing2),
                  Text(
                    AppLocalizations.of(context).noScreenshotsSubtitle,
                    style: const TextStyle(color: AppTheme.mutedForeground),
                  ),
                ],
              ),
            );
          }
          // 加载中时显示空白，避免闪烁
          return const SizedBox.shrink();
        },
      );
    }

    return _buildTabsAndGrid();
  }

  Widget _buildSearchResultGrid() {
    final data = _searchResults;
    if (data.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context).noMatchingResults),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacing1),
      child: RefreshIndicator(
        onRefresh: _loadScreenshots,
        child: GridView.builder(
          key: PageStorageKey<String>(
            'screenshot_gallery_search_${_packageName}',
          ),
          // 仅缓存当前视窗上下各一屏，超出即回收
          cacheExtent: MediaQuery.of(context).size.height,
          addAutomaticKeepAlives: false,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + AppTheme.spacing6,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: AppTheme.spacing1,
            mainAxisSpacing: AppTheme.spacing1,
            childAspectRatio: 0.45,
          ),
          itemCount: data.length,
          itemBuilder: (context, index) {
            final s = data[index];
            return Stack(
              children: [
                _buildScreenshotItem(s, index),
                SearchMatchBoxesOverlay(boxesFuture: _ensureBoxes(s.filePath)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 构建顶部日期Tab栏 + 下方网格
  Widget _buildTabsAndGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 与 AppBar 内容左对齐：TabBar 自身通过 padding 控制左内边距
        Padding(
          padding: const EdgeInsets.only(left: 0, right: AppTheme.spacing1),
          child: _dayTabs.isEmpty || _tabController == null
              ? const SizedBox(height: 32)
              : SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Expanded(
                        child: ScreenshotStyleTabBar(
                          controller: _tabController,
                          padding: const EdgeInsets.only(
                            left: AppTheme.spacing4,
                          ),
                          labelPadding: const EdgeInsets.only(
                            right: AppTheme.spacing6,
                          ),
                          tabs: _dayTabs
                              .map(
                                (t) => Tab(
                                  text: (() {
                                    final l = AppLocalizations.of(context);
                                    if (_DayTabInfo._isToday(t.day)) {
                                      return l.dayTabToday(t.count);
                                    }
                                    if (_DayTabInfo._isYesterday(t.day)) {
                                      return l.dayTabYesterday(t.count);
                                    }
                                    return l.dayTabMonthDayCount(
                                      t.day.month,
                                      t.day.day,
                                      t.count,
                                    );
                                  })(),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      if (_dayTabs.length < _allDayTabs.length)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: AppTheme.spacing2,
                          ),
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.spacing2,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _expandDayTabsIfNeeded,
                            icon: const Icon(Icons.more_horiz, size: 18),
                            label: Text(AppLocalizations.of(context).loadMore),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        // 日期Tab与内容之间增加1px底部外边距
        const SizedBox(height: 1),
        Expanded(
          child: _tabController == null
              ? _buildGalleryGrid()
              : TabBarView(
                  controller: _tabController,
                  physics: const ClampingScrollPhysics(),
                  children: _dayTabs.isEmpty
                      ? [_buildGalleryGridForIndex(0)]
                      : _dayTabs
                            .asMap()
                            .entries
                            .map(
                              (entry) => _buildGalleryGridForIndex(entry.key),
                            )
                            .toList(),
                ),
        ),
      ],
    );
  }

  /// 渲染指定索引Tab的网格：当前页使用主数据，非当前页使用缓存数据与独立控制器
  Widget _buildGalleryGridForIndex(int tabIndex) {
    final bool isCurrent = tabIndex == _currentTabIndex;
    final List<ScreenshotRecord> data = isCurrent
        ? _screenshots
        : List<ScreenshotRecord>.from(
            _tabCache[tabIndex] ?? const <ScreenshotRecord>[],
          );
    if (!isCurrent && data.isEmpty) {
      // 若缓存尚未就绪，展示轻量占位
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppTheme.spacing1),
          child: Container(
            key: isCurrent ? _gridKey : null,
            child: RefreshIndicator(
              onRefresh: _loadScreenshots,
              child: GridView.builder(
                key: PageStorageKey<String>(
                  'screenshot_gallery_grid_${_packageName}_tab_$tabIndex',
                ),
                controller: _controllerForTab(tabIndex),
                // 仅缓存当前视窗上下各一屏，超出即回收
                cacheExtent: MediaQuery.of(context).size.height,
                addAutomaticKeepAlives: false,
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.only(
                  bottom:
                      MediaQuery.of(context).padding.bottom + AppTheme.spacing6,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppTheme.spacing1,
                  mainAxisSpacing: AppTheme.spacing1,
                  childAspectRatio: 0.45,
                ),
                itemCount: data.length,
                itemBuilder: (context, index) {
                  final s = data[index];
                  return isCurrent
                      ? _buildScreenshotItem(s, index)
                      : _buildPreviewItem(s);
                },
              ),
            ),
          ),
        ),
        if (isCurrent && _dayTabs.length > 1) _buildTimelineOverlay(),
      ],
    );
  }

  /// 预览项：非交互，仅用于滑动时提前可见
  Widget _buildPreviewItem(ScreenshotRecord screenshot) {
    if (_baseDir == null) {
      return _buildErrorItem(AppLocalizations.of(context).appDirUninitialized);
    }

    return ScreenshotItemWidget(
      screenshot: screenshot,
      baseDir: _baseDir,
      appInfoMap: {_packageName: _appInfo},
      privacyMode: _privacyMode,
      // 预览项不可交互
      onTap: null,
    );
  }

  Widget _buildGalleryGrid() => _buildGalleryGridForIndex(_currentTabIndex);

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    _tabController?.removeListener(_onTabControllerChanged);
    _tabController?.dispose();
    super.dispose();
  }

  Widget _buildScreenshotItem(ScreenshotRecord screenshot, int index) {
    if (_baseDir == null) {
      return _buildErrorItem(AppLocalizations.of(context).appDirUninitialized);
    }

    final isSelected =
        _selectionMode &&
        screenshot.id != null &&
        _selectedIds.contains(screenshot.id);
    final GlobalKey itemKey = _itemKeys.putIfAbsent(index, () => GlobalKey());
    final bool isNsfw = NsfwPreferenceService.instance.shouldMaskCached(
      screenshot,
    );
    final bool nsfwMasked = _privacyMode && isNsfw;
    // 手动标记状态（仅 DB）
    final bool isManualNsfw =
        screenshot.id != null &&
        NsfwPreferenceService.instance.isManuallyFlaggedCached(
          screenshotId: screenshot.id!,
          appPackageName: screenshot.appPackageName,
        );
    // UI 显示状态：全局统一展示（不依赖隐私模式开关）
    final bool isNsfwDisplay = isNsfw;

    final itemContent = ScreenshotItemWidget(
      screenshot: screenshot,
      baseDir: _baseDir,
      appInfoMap: {_packageName: _appInfo},
      privacyMode: _privacyMode,
      onTap: () {
        if (_selectionMode) {
          _toggleSelect(index);
        } else {
          if (nsfwMasked) {
            _confirmRevealAndOpen(screenshot, index);
          } else {
            _viewScreenshot(screenshot, index);
          }
        }
      },
      onLongPress: () {
        if (!_selectionMode) {
          setState(() => _selectionMode = true);
          _loadFavoriteStatus();
        }
        _toggleSelect(index);
      },
      onLinkTap: (url) => _showLinkDialogFromGrid(url),
      showCheckbox: _selectionMode,
      isSelected: isSelected,
      showFavoriteButton: _selectionMode && screenshot.id != null,
      isFavorited: _favoriteStatus[screenshot.id] ?? false,
      onFavoriteToggle: () => _toggleFavorite(screenshot),
      showNsfwButton: _selectionMode && screenshot.id != null,
      isNsfwFlagged: isNsfwDisplay,
      onNsfwToggle: () async {
        if (screenshot.id == null) return;
        // 若当前因域名规则/自动识别被遮罩，但未手动标记，则提示在设置中管理域名规则
        if (!isManualNsfw && isNsfw) {
          if (!mounted) return;
          UINotifier.info(
            context,
            AppLocalizations.of(context).nsfwBlockedByRulesHint,
          );
          return;
        }
        final newFlag = !isManualNsfw;
        final ok = await NsfwPreferenceService.instance.setManualFlag(
          screenshotId: screenshot.id!,
          appPackageName: screenshot.appPackageName,
          flag: newFlag,
        );
        if (!mounted) return;
        if (ok) {
          setState(() {});
          final l10n = AppLocalizations.of(context);
          UINotifier.success(
            context,
            newFlag ? l10n.manualMarkSuccess : l10n.manualUnmarkSuccess,
          );
        } else {
          UINotifier.error(
            context,
            AppLocalizations.of(context).manualMarkFailed,
          );
        }
      },
    );

    return KeyedSubtree(key: itemKey, child: itemContent);
  }

  Future<void> _confirmRevealAndOpen(
    ScreenshotRecord screenshot,
    int index,
  ) async {
    final confirmed = await showUIDialog<bool>(
      context: context,
      title: AppLocalizations.of(context).nsfwWarningTitle,
      message: AppLocalizations.of(context).nsfwWarningSubtitle,
      actions: [
        UIDialogAction<bool>(
          text: AppLocalizations.of(context).dialogCancel,
          result: false,
        ),
        UIDialogAction<bool>(
          text: AppLocalizations.of(context).actionContinue,
          style: UIDialogActionStyle.primary,
          result: true,
        ),
      ],
      barrierDismissible: true,
    );
    if (confirmed == true) {
      _viewScreenshot(screenshot, index);
    }
  }

  Future<void> _showLinkDialogFromGrid(String url) async {
    await showUIDialog<void>(
      context: context,
      title: AppLocalizations.of(context).linkTitle,
      content: SelectableText(url, textAlign: TextAlign.center),
      barrierDismissible: true,
      actions: [
        UIDialogAction<void>(
          text: AppLocalizations.of(context).actionCopy,
          style: UIDialogActionStyle.primary,
          closeOnPress: true,
          onPressed: (ctx) async {
            try {
              await Clipboard.setData(ClipboardData(text: url));
              // ignore: unawaited_futures
              FlutterLogger.info('UI.网格-复制链接 成功');
              // ignore: unawaited_futures
              FlutterLogger.nativeInfo('UI', '网格复制链接成功');
              if (mounted) {
                UINotifier.success(
                  context,
                  AppLocalizations.of(context).copySuccess,
                );
              }
            } catch (e) {
              // ignore: unawaited_futures
              FlutterLogger.error('UI.网格-复制链接 失败: ' + e.toString());
              // ignore: unawaited_futures
              FlutterLogger.nativeError('UI', '网格复制链接失败：' + e.toString());
              if (mounted) {
                UINotifier.error(
                  context,
                  AppLocalizations.of(context).copyFailed,
                );
              }
            }
          },
        ),
        UIDialogAction<void>(
          text: AppLocalizations.of(context).actionOpen,
          style: UIDialogActionStyle.normal,
          closeOnPress: true,
          onPressed: (ctx) async {
            try {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            } catch (_) {}
          },
        ),
        UIDialogAction<void>(
          text: AppLocalizations.of(context).dialogCancel,
          style: UIDialogActionStyle.normal,
          closeOnPress: true,
        ),
      ],
    );
  }

  // 构建右侧时间线滚动条与时间提示
  Widget _buildTimelineOverlay() {
    if (_screenshots.isEmpty || _screenshots.length < 2) {
      return const SizedBox.shrink();
    }

    const double gestureWidth = 44; // 右侧可交互区域宽度
    const double trackWidth = 3; // 可见轨道宽度
    const double thumbHeight = 32; // 拇指高度
    const double labelHeight = 28; // 时间标签高度（用于定位）

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double viewHeight = constraints.maxHeight;
          // 与网格保持一致的底部边距：外层 Padding + GridView 的 bottom padding
          final double bottomMargin =
              MediaQuery.of(context).padding.bottom +
              AppTheme.spacing6 +
              AppTheme.spacing1;
          final double trackHeight = (viewHeight - bottomMargin).clamp(
            0,
            viewHeight,
          );

          // 增加安全检查，避免异常计算（使用当前Tab的controller）
          final ctrl = _controllerForTab(_currentTabIndex);
          if (trackHeight <= 0 || !ctrl.hasClients) {
            return const SizedBox.shrink();
          }

          final double currentFraction = _timelineActive
              ? _timelineFraction
              : _currentScrollFraction();
          final double clampedFraction = currentFraction.clamp(0.0, 1.0);
          final double thumbTop =
              clampedFraction *
              (trackHeight - thumbHeight).clamp(0, trackHeight);

          final int firstVisibleIndex = _timelineActive
              ? _approxIndexFromFraction()
              : _getFirstVisibleIndex();
          final String timeLabel =
              (firstVisibleIndex >= 0 &&
                  firstVisibleIndex < _screenshots.length)
              ? _formatTimelineTime(_screenshots[firstVisibleIndex].captureTime)
              : '';

          return Stack(
            children: [
              // 交互区域 - 只占右侧44像素，避免影响主要内容区域
              Positioned(
                right: 0,
                top: 0,
                bottom: bottomMargin,
                width: gestureWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  // 防止手势冲突，增加边界检查
                  onVerticalDragStart: (details) {
                    if (trackHeight > thumbHeight) {
                      _activateTimelineWithLocalY(
                        details.localPosition.dy,
                        trackHeight,
                      );
                    }
                  },
                  onVerticalDragUpdate: (details) {
                    if (trackHeight > thumbHeight && _timelineActive) {
                      _activateTimelineWithLocalY(
                        details.localPosition.dy,
                        trackHeight,
                      );
                    }
                  },
                  onVerticalDragEnd: (_) {
                    if (mounted) {
                      setState(() {
                        _timelineActive = false;
                      });
                    }
                    _maybeLoadAfterScrub();
                  },
                  onLongPressStart: (details) {
                    if (trackHeight > thumbHeight) {
                      _activateTimelineWithLocalY(
                        details.localPosition.dy,
                        trackHeight,
                      );
                    }
                  },
                  onLongPressMoveUpdate: (details) {
                    if (trackHeight > thumbHeight && _timelineActive) {
                      _activateTimelineWithLocalY(
                        details.localPosition.dy,
                        trackHeight,
                      );
                    }
                  },
                  onLongPressEnd: (_) {
                    if (mounted) {
                      setState(() {
                        _timelineActive = false;
                      });
                    }
                    _maybeLoadAfterScrub();
                  },
                  child: Stack(
                    children: [
                      // 轨道
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: trackWidth,
                          margin: EdgeInsets.zero,
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // 拇指（与轨道右对齐）
                      Positioned(
                        right: 0,
                        top: thumbTop,
                        child: Container(
                          width: trackWidth,
                          height: thumbHeight,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade600,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_timelineActive)
                Positioned(
                  right: gestureWidth + 8,
                  top: (clampedFraction * (trackHeight - labelHeight)).clamp(
                    0,
                    trackHeight - labelHeight,
                  ),
                  child: Container(
                    height: labelHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6), // 小圆角，无阴影
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      timeLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // 激活时间线并根据手指位置滚动
  void _activateTimelineWithLocalY(double localY, double viewHeight) {
    // 增加安全检查
    final ctrl = _controllerForTab(_currentTabIndex);
    if (viewHeight <= 0 || !ctrl.hasClients || !mounted) return;

    final double raw = localY / viewHeight;
    final double fraction = raw.clamp(0.0, 1.0);

    setState(() {
      _timelineActive = true;
      _timelineFraction = fraction;
    });
    _scheduleScrubJump();
  }

  // 当前滚动位置归一化 [0,1]
  double _currentScrollFraction() {
    final ctrl = _controllerForTab(_currentTabIndex);
    if (!ctrl.hasClients) return 0.0;
    final maxExtent = ctrl.position.maxScrollExtent;
    if (maxExtent <= 0) return 0.0;
    final pixels = ctrl.position.pixels;
    final double f = pixels / maxExtent;
    return f.clamp(0.0, 1.0);
  }

  // 滚动到对应归一化位置
  void _scrollToFraction(double fraction) {
    final ctrl = _controllerForTab(_currentTabIndex);
    if (!ctrl.hasClients || !mounted) return;
    final maxExtent = ctrl.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    final target = fraction.clamp(0.0, 1.0) * maxExtent;
    ctrl.jumpTo(target);
  }

  // 拖动时用 fraction 近似当前索引，避免在大量 GlobalKey 上做布局查询
  int _approxIndexFromFraction() {
    if (_screenshots.isEmpty) return 0;
    final double f = _timelineFraction.clamp(0.0, 1.0);
    final int last = _screenshots.length - 1;
    final int idx = (f * last).round();
    return idx.clamp(0, last);
  }

  // 将 jumpTo 合并到每帧一次，降低拖动过程中的重排与抖动
  void _scheduleScrubJump() {
    if (_scrubJumpScheduled) return;
    _scrubJumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrubJumpScheduled = false;
      if (!mounted) return;
      final ctrl = _controllerForTab(_currentTabIndex);
      if (!ctrl.hasClients) return;
      final maxExtent = ctrl.position.maxScrollExtent;
      if (maxExtent <= 0) return;
      final double f = _timelineFraction.clamp(0.0, 1.0);
      final double target = f * maxExtent;
      if ((ctrl.position.pixels - target).abs() > 0.5) {
        ctrl.jumpTo(target);
      }
    });
  }

  // 拖动结束后按需加载一批，避免在拖动过程中频繁 setState 卡顿
  void _maybeLoadAfterScrub() {
    if (!mounted) return;
    if (_hasMore && !_isLoadingMore && _timelineFraction >= 0.98) {
      // ignore: unawaited_futures
      _loadMoreScreenshots();
    }
  }

  Rect? _getGridViewportRect() {
    if (!mounted) return null;
    final ctx = _gridKey.currentContext;
    if (ctx == null) return null;
    final render = ctx.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return null;
    final topLeft = render.localToGlobal(Offset.zero);
    return topLeft & render.size;
  }

  // 计算当前视口内第一张可见截图的索引
  int _getFirstVisibleIndex() {
    if (!mounted || _screenshots.isEmpty || _itemKeys.isEmpty) return 0;

    final viewport = _getGridViewportRect();
    if (viewport == null) return 0;

    int? firstIdx;
    double? minTop;

    _itemKeys.forEach((index, key) {
      // 增加边界检查
      if (index >= _screenshots.length) return;

      final context = key.currentContext;
      if (context == null) return;

      final render = context.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;

      try {
        final rect = render.localToGlobal(Offset.zero) & render.size;
        final bool visible =
            rect.bottom > viewport.top && rect.top < viewport.bottom;
        if (!visible) return;

        if (minTop == null || rect.top < minTop!) {
          minTop = rect.top;
          firstIdx = index;
        }
      } catch (e) {
        // 忽略布局异常，继续处理其他项
        return;
      }
    });

    return (firstIdx != null && firstIdx! < _screenshots.length)
        ? firstIdx!
        : 0;
  }

  // 时间线标签格式化（当天/本年/跨年）
  String _formatTimelineTime(DateTime dateTime) {
    final now = DateTime.now();
    final t = AppLocalizations.of(context);
    final bool sameDay =
        now.year == dateTime.year &&
        now.month == dateTime.month &&
        now.day == dateTime.day;
    final bool sameYear = now.year == dateTime.year;
    final String hh = dateTime.hour.toString().padLeft(2, '0');
    final String mm = dateTime.minute.toString().padLeft(2, '0');
    if (sameDay) {
      return '$hh:$mm';
    } else if (sameYear) {
      return t.monthDayTime(dateTime.month, dateTime.day, hh, mm);
    } else {
      return t.yearMonthDayTime(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        hh,
        mm,
      );
    }
  }

  /// 获取全选按钮文本
  String _getSelectAllButtonText() {
    return _isFullySelected
        ? AppLocalizations.of(context).clearAll
        : AppLocalizations.of(context).selectAll;
  }

  void _toggleSelect(int index) {
    if (index < 0 || index >= _screenshots.length) return;
    final id = _screenshots[index].id;
    if (id == null) return;
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
        // 如果取消选择了某项，就不再是全选状态
        _isFullySelected = false;
      } else {
        _selectedIds.add(id);
        // 基于当前筛选范围（当日或全量）判断是否达到“全选”
        int expectedTotal = _totalCount;
        if (_dateFilterStartMillis != null &&
            _dateFilterEndMillis != null &&
            _currentTabIndex >= 0 &&
            _currentTabIndex < _dayTabs.length) {
          expectedTotal = _dayTabs[_currentTabIndex].count;
        }
        _isFullySelected =
            expectedTotal > 0 && _selectedIds.length >= expectedTotal;
      }
    });
  }

  void _hitSelectAtPosition(Offset globalPosition) {
    // 命中检测：遍历可见项，若指针在其区域内则选中
    _itemKeys.forEach((index, key) {
      final context = key.currentContext;
      if (context == null) return;
      final render = context.findRenderObject();
      if (render is! RenderBox) return;
      final topLeft = render.localToGlobal(Offset.zero);
      final rect = topLeft & render.size;
      if (rect.contains(globalPosition)) {
        _toggleSelect(index);
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    // 检查是否选择了全部（基于当前筛选范围：当日或全量）
    int expectedTotal = _totalCount;
    if (_dateFilterStartMillis != null &&
        _dateFilterEndMillis != null &&
        _currentTabIndex >= 0 &&
        _currentTabIndex < _dayTabs.length) {
      expectedTotal = _dayTabs[_currentTabIndex].count;
    }
    final isSelectAll =
        _selectedIds.length >= expectedTotal && expectedTotal > 0;
    final int totalCount = expectedTotal;

    final String title = isSelectAll
        ? AppLocalizations.of(context).confirmDeleteAllTitle
        : AppLocalizations.of(context).confirmDeleteTitle;
    final String message = isSelectAll
        ? AppLocalizations.of(context).deleteAllMessage(expectedTotal)
        : AppLocalizations.of(
            context,
          ).deleteSelectedMessage(_selectedIds.length);

    final confirmed = await showUIDialog<bool>(
      context: context,
      title: title,
      message: message,
      actions: const [
        UIDialogAction<bool>(text: '取消', result: false),
        UIDialogAction<bool>(
          text: '删除',
          style: UIDialogActionStyle.destructive,
          result: true,
        ),
      ],
      barrierDismissible: false,
    );

    if (confirmed != true) return;

    // 记录UI层批量删除请求日志
    // ignore: unawaited_futures
    FlutterLogger.info(
      'UI.批量删除-发起 包=$_packageName 选择=${_selectedIds.length} 是否全删=$isSelectAll',
    );
    // ignore: unawaited_futures
    FlutterLogger.nativeInfo(
      'UI',
      '批量删除开始 数量=${_selectedIds.length} 是否全删=$isSelectAll',
    );

    final bool inDayScope =
        _dateFilterStartMillis != null &&
        _dateFilterEndMillis != null &&
        _currentTabIndex >= 0 &&
        _currentTabIndex < _dayTabs.length;

    if (isSelectAll && !inDayScope) {
      // 全删除模式：使用高效的文件夹删除
      final success = await ScreenshotService.instance
          .deleteAllScreenshotsForApp(_packageName);

      if (success) {
        // ignore: unawaited_futures
        FlutterLogger.info('UI.全删-成功 包=$_packageName 总数=$totalCount');
        // ignore: unawaited_futures
        FlutterLogger.nativeInfo('UI', '全删成功 总数=$totalCount');
        // 清空本地数据
        setState(() {
          _screenshots.clear();
          _selectedIds.clear();
          _selectionMode = false;
          _isFullySelected = false; // 重置全选状态
          _totalCount = 0;
          _totalSize = 0;
          _latestTime = null;
          _currentDisplayCount = 0;
          _hasMore = false;
        });
        // 重新构建日期 Tabs（去除14天限制）
        await _prepareDayTabs();

        // 失效缓存
        await ScreenshotService.instance.invalidateStatsCache();
        await _invalidateScreenshotsCache();

        if (mounted) {
          UINotifier.success(
            context,
            AppLocalizations.of(context).deletedCountToast(totalCount),
          );
        }
      } else {
        // ignore: unawaited_futures
        FlutterLogger.warn('UI.全删-失败 包=$_packageName');
        // ignore: unawaited_futures
        FlutterLogger.nativeWarn('UI', '全删失败');
        if (mounted) {
          UINotifier.error(
            context,
            AppLocalizations.of(context).deleteFailedRetry,
          );
        }
      }
    } else {
      // 部分删除模式：根据保留比例触发“仅保留”快速删除
      final totalCount = _totalCount;
      final keepCount = totalCount - _selectedIds.length;
      final keepRatio = totalCount == 0 ? 1.0 : (keepCount / totalCount);

      // 阈值可后续做成设置项，这里先固定为10%
      const double thresholdKeepRatio = 0.1;

      bool usedFastKeepOnly = false;
      if (keepCount >= 0 && keepRatio <= thresholdKeepRatio) {
        // 选择删除大多数，仅保留极少数 -> 使用快速“仅保留”策略
        // 真分页模式无法可靠计算全量 keepIds，这里禁用快速“仅保留”路径
        final List<int> keepIds = const <int>[];

        // ignore: unawaited_futures
        FlutterLogger.info(
          'UI.fastDeleteKeepOnly start package=$_packageName keep=${keepIds.length} delete=${_selectedIds.length}',
        );
        // ignore: unawaited_futures
        FlutterLogger.nativeInfo('UI', '仅保留快速删除开始 保留=${keepIds.length}');
        usedFastKeepOnly = await ScreenshotService.instance.fastDeleteKeepOnly(
          packageName: _packageName,
          keepIds: keepIds,
          thresholdKeepRatio: thresholdKeepRatio,
        );
      }

      if (!usedFastKeepOnly) {
        // 使用批量删除API，显示进度
        final ids = List<int>.from(_selectedIds);
        // ignore: unawaited_futures
        FlutterLogger.info(
          'UI.批量删除-开始 包=${_appInfo.packageName} 数量=${ids.length}',
        );
        // ignore: unawaited_futures
        FlutterLogger.nativeInfo('UI', '批量删除开始 数量=${ids.length}');
        if (mounted) {
          UINotifier.showProgress(
            context,
            message: AppLocalizations.of(context).galleryDeleting,
            progress: null,
          );
        }

        // 为表现更流畅，这里分批提交给批量删除（数据库侧已分片），我们主要更新UI进度
        final successCount = await ScreenshotService.instance
            .deleteScreenshotsBatch(_appInfo.packageName, ids);
        if (mounted) {
          UINotifier.updateProgress(
            message: AppLocalizations.of(context).galleryCleaningCache,
            progress: 0.9,
          );
        }

        // 计算更准确的删除数量与日期Tab新计数（避免出现“删除0张”的提示）
        int deletedShown = successCount;
        int? newDayCount;
        if (_dayTabs.isNotEmpty &&
            _currentTabIndex >= 0 &&
            _currentTabIndex < _dayTabs.length &&
            _dateFilterStartMillis != null &&
            _dateFilterEndMillis != null) {
          final prev = _dayTabs[_currentTabIndex].count;
          try {
            final refreshed = await ScreenshotService.instance
                .getScreenshotCountByAppBetween(
                  _packageName,
                  startMillis: _dayTabs[_currentTabIndex].startMillis,
                  endMillis: _dayTabs[_currentTabIndex].endMillis,
                );
            newDayCount = refreshed;
            final delta = prev - refreshed;
            if (delta > 0) {
              deletedShown = delta;
            }
          } catch (_) {}
        }

        // 本地移除（从全量数据和显示数据中删除），并同步缓存与统计
        setState(() {
          _screenshots.removeWhere(
            (s) => s.id != null && _selectedIds.contains(s.id),
          );
          final int minus = (newDayCount != null)
              ? ((_dayTabs[_currentTabIndex].count - newDayCount!).clamp(
                  0,
                  1 << 31,
                ))
              : _selectedIds.length;
          _totalCount = (_totalCount - minus).clamp(0, 1 << 31);
          _currentDisplayCount = _screenshots.length;
          _hasMore = _currentDisplayCount < _totalCount;
          _selectedIds.clear();
          _selectionMode = false;
          _isFullySelected = false; // 重置全选状态
          if (newDayCount != null) {
            _dayTabs[_currentTabIndex].count = newDayCount!;
          }
          // 同步当前Tab缓存，避免切换后才刷新
          _tabCache[_currentTabIndex] = List<ScreenshotRecord>.from(
            _screenshots,
          );
          _tabOffset[_currentTabIndex] = _currentDisplayCount;
          _tabHasMore[_currentTabIndex] = _hasMore;
        });

        // 若当前日期Tab已被删空，自动切换到上一可用日期
        await _switchAwayIfCurrentDayEmpty();

        // 缓存已在批量删除后统一刷新，这里只需失效本页面的截图缓存
        await _invalidateScreenshotsCache();
        if (mounted) {
          UINotifier.hideProgress();
        }
        if (mounted) {
          // ignore: unawaited_futures
          FlutterLogger.info('UI.批量删除-成功 删除数=' + deletedShown.toString());
          // ignore: unawaited_futures
          FlutterLogger.nativeInfo(
            'UI',
            '批量删除成功 删除数=' + deletedShown.toString(),
          );
          UINotifier.success(
            context,
            AppLocalizations.of(context).deletedCountToast(deletedShown),
          );
        }
      } else {
        // 使用了“仅保留”快速删除：直接重载数据
        await ScreenshotService.instance.invalidateStatsCache();
        await _invalidateScreenshotsCache();

        // 重新加载当前应用截图（真分页）
        await _loadScreenshots();
        setState(() {
          _selectedIds.clear();
          _selectionMode = false;
          _isFullySelected = false;
        });

        if (mounted) {
          // ignore: unawaited_futures
          FlutterLogger.info(
            'UI.仅保留-完成 保留=$keepCount 删除=${totalCount - keepCount}',
          );
          // ignore: unawaited_futures
          FlutterLogger.nativeInfo('UI', '仅保留快速删除完成');
          UINotifier.success(
            context,
            AppLocalizations.of(
              context,
            ).keptAndDeletedSummary(keepCount, totalCount - keepCount),
          );
        }
      }
    }
  }

  Widget _buildErrorItem(String message) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.muted,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppTheme.destructive,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(color: AppTheme.destructive, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// 将字节格式化为最小MB，然后GB/TB
  String _formatTotalSizeMBGBTB(int bytes) {
    const double kb = 1024;
    const double mb = kb * 1024;
    const double gb = mb * 1024;
    const double tb = gb * 1024;

    if (bytes >= tb) {
      return (bytes / tb).toStringAsFixed(2) + 'TB';
    } else if (bytes >= gb) {
      return (bytes / gb).toStringAsFixed(2) + 'GB';
    } else {
      // 最小单位MB（包含 <1MB 的情况）
      return (bytes / mb).toStringAsFixed(2) + 'MB';
    }
  }

  /// 加载当前截图列表的收藏状态
  Future<void> _loadFavoriteStatus() async {
    if (_screenshots.isEmpty) return;

    try {
      final ids = _screenshots
          .where((s) => s.id != null)
          .map((s) => s.id!)
          .toList();

      if (ids.isEmpty) return;

      final statusMap = await FavoriteService.instance.checkFavorites(
        screenshotIds: ids,
        appPackageName: _packageName,
      );

      if (!mounted) return;
      setState(() {
        _favoriteStatus.clear();
        _favoriteStatus.addAll(statusMap);
      });
    } catch (e) {
      print('加载收藏状态失败: $e');
    }
  }

  /// 切换收藏状态
  Future<void> _toggleFavorite(ScreenshotRecord screenshot) async {
    if (screenshot.id == null) return;

    try {
      final currentStatus = _favoriteStatus[screenshot.id] ?? false;
      final success = await FavoriteService.instance.toggleFavorite(
        screenshotId: screenshot.id!,
        appPackageName: screenshot.appPackageName,
      );

      if (success) {
        setState(() {
          _favoriteStatus[screenshot.id!] = !currentStatus;
        });

        if (mounted) {
          UINotifier.success(
            context,
            currentStatus
                ? AppLocalizations.of(context).favoriteRemoved
                : AppLocalizations.of(context).favoriteAdded,
          );
        }
      } else if (mounted) {
        UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      }
    } catch (e) {
      print('切换收藏状态失败: $e');
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).operationFailedWithError(e.toString()),
        );
      }
    }
  }

  // （测试截图生成功能已移除）

  Future<void> _preloadManualFlagsFor(List<ScreenshotRecord> data) async {
    try {
      final ids = data.where((s) => s.id != null).map((s) => s.id!).toList();
      // 1) 手动标记（按 app）
      if (ids.isNotEmpty) {
        await NsfwPreferenceService.instance.preloadManualFlags(
          appPackageName: _packageName,
          screenshotIds: ids,
        );
      }

      // 2) AI NSFW（按 file_path，全局复用）
      final paths = data
          .map((s) => s.filePath.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      if (paths.isNotEmpty) {
        await NsfwPreferenceService.instance.preloadAiNsfwFlags(
          filePaths: paths,
        );
        await NsfwPreferenceService.instance.preloadSegmentNsfwFlags(
          filePaths: paths,
        );
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }
}
