import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../models/screenshot_record.dart';
import '../services/screenshot_service.dart';
import '../services/app_selection_service.dart';
import '../models/app_info.dart';
import '../services/nsfw_preference_service.dart';
import '../services/app_lifecycle_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../widgets/screenshot_item_widget.dart';
import '../widgets/ui_components.dart';
import '../services/timeline_jump_service.dart';
import '../services/screenshot_database.dart';
import '../services/flutter_logger.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import '../services/replay_export_service.dart';
import '../widgets/screenshot_style_tab_bar.dart';
import '../widgets/timeline_replay_sheet.dart';

/// 全局时间线页面（骨架）
/// 后续将加载按日期的全局截图时间线与应用图标
class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  bool _loading = false;
  bool _refreshing = false;
  // 已加载的日期Tab缓冲（按时间倒序）；支持增量向前追加
  final List<_DayTabInfo> _allDayTabs = <_DayTabInfo>[];
  // 当前 UI 中可见的日期Tab窗口（前缀子集：默认最近14天，向前增量加载）
  final List<_DayTabInfo> _dayTabs = <_DayTabInfo>[];
  TabController? _tabController;
  int _currentTabIndex = 0;
  int? _dateStartMillis;
  int? _dateEndMillis;

  // 数据与分页
  List<ScreenshotRecord> _screenshots = <ScreenshotRecord>[];
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _pageOffset = 0;
  static const int _initialPageSize = 12;
  static const int _pageSize = 24;

  // 应用图标缓存
  final Map<String, AppInfo> _appInfoByPackage = <String, AppInfo>{};
  bool _privacyMode = true; // 默认开启，初始化时从偏好读取

  // 每个Tab的缓存与偏移
  final Map<int, List<ScreenshotRecord>> _tabCache =
      <int, List<ScreenshotRecord>>{};
  final Map<int, int> _tabOffset = <int, int>{};
  final Map<int, bool> _tabHasMore = <int, bool>{};
  final Map<int, AutoScrollController> _tabScrollControllers =
      <int, AutoScrollController>{};
  final Map<int, double> _tabScrollOffset = <int, double>{};
  // 时间线滚动条交互状态（右侧快速滚动）
  bool _timelineActive = false;
  double _timelineFraction = 0.0;
  // 拖动节流：将 jumpTo 合并到每帧一次，减少抖动
  bool _scrubJumpScheduled = false;
  final GlobalKey _gridKey = GlobalKey();
  final Map<int, GlobalKey> _itemKeys = <int, GlobalKey>{};
  StreamSubscription<AppLifecycleEvent>? _lifecycleSub;
  TimelineJumpRequest? _pendingJump;
  VoidCallback? _jumpListener;
  bool _jumpInProgress = false;

  // 日期窗口控制：默认最近14天，每次向前追加14天
  static const int _initialVisibleDayTabs = 14;
  static const int _appendVisibleDayTabs = 14;
  // 查询窗口：首屏与增量加载回溯天数（按时间窗仅扫描涉及的年月表）
  static const int _initialDayTabsLookbackDays = 120;
  static const int _appendDayTabsLookbackDays = 120;
  bool _isExpandingDayTabs = false;
  bool _hasMoreDayTabs = false;

  @override
  void initState() {
    super.initState();
    _init();
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
    // 订阅应用生命周期事件：进入应用/首次进入时自动刷新
    _lifecycleSub = AppLifecycleService.instance.events.listen((event) {
      if (!mounted) return;
      if (_jumpInProgress) return; // 跳转处理中忽略生命周期触发的刷新，避免打断
      if (_loading) return; // 首次初始化进行中，避免重复触发
      if (_refreshing) return; // 刷新进行中，避免并发
      if (event == AppLifecycleEvent.resumed ||
          event == AppLifecycleEvent.firstUiResumed ||
          event == AppLifecycleEvent.timelineShown) {
        // 等价于右上角刷新按钮
        _refresh();
      }
    });
    // 如果“首次进入UI”事件已在本页挂载前发生，补一次刷新
    if (AppLifecycleService.instance.firstUiResumedEmitted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loading && !_refreshing) _refresh();
      });
    }

    // 监听来自 JumpService 的跳转请求
    _jumpListener = () {
      final req = TimelineJumpService.instance.requestNotifier.value;
      if (req == null) return;
      _pendingJump = req;
      try {
        FlutterLogger.nativeInfo(
          'TimelineJump',
          '收到跳转请求，准备处理 路径=' + req.filePath,
        );
      } catch (_) {}
      _handleJumpRequestIfPossible();
    };
    TimelineJumpService.instance.requestNotifier.addListener(_jumpListener!);
    // 初始化时若已有待处理跳转，主动触发一次
    _jumpListener!.call();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    final sw = Stopwatch()..start();
    // 延迟加载应用图标：首屏不阻塞
    // ignore: unawaited_futures
    _loadAppInfos();
    await _loadPrivacyMode();
    await _prepareDayTabs();
    sw.stop();
    try {
      print('[时间线] 初始化完成，耗时 ${sw.elapsedMilliseconds} 毫秒');
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
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

  Future<void> _prepareDayTabs() async {
    final sw = Stopwatch()..start();
    final List<_DayTabInfo> tabs = <_DayTabInfo>[];
    try {
      final swDays = Stopwatch()..start();
      final int? latestMillis = await ScreenshotService.instance
          .getGlobalLatestCaptureTimeMillis();
      final DateTime base = (latestMillis == null || latestMillis <= 0)
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(latestMillis);
      final DateTime endDay = DateTime(base.year, base.month, base.day);
      final int endMillis = DateTime(
        endDay.year,
        endDay.month,
        endDay.day,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;
      final DateTime startDay = endDay.subtract(
        const Duration(days: _initialDayTabsLookbackDays - 1),
      );
      final int startMillis = startDay.millisecondsSinceEpoch;
      final days = await ScreenshotService.instance
          .listAvailableDaysGlobalRange(
            startMillis: startMillis,
            endMillis: endMillis,
          );
      swDays.stop();
      try {
        print(
          '[时间线] 查询可用日期(范围)耗时 ${swDays.elapsedMilliseconds} 毫秒 start=$startMillis end=$endMillis',
        );
      } catch (_) {}
      for (final m in days) {
        final String ds = (m['date'] as String?) ?? '';
        final int count = _readInt(m['count']);
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
      // 已加载日期列表按倒序（越靠前越新）
      _allDayTabs
        ..clear()
        ..addAll(tabs);
      // 只要当前有数据，就允许尝试“加载更多”；当增量查询为空时再关闭
      _hasMoreDayTabs = _allDayTabs.isNotEmpty;

      final int visibleCount = _allDayTabs.isEmpty
          ? 0
          : math.min(_initialVisibleDayTabs, _allDayTabs.length);
      _dayTabs
        ..clear()
        ..addAll(_allDayTabs.take(visibleCount));

      _tabController?.removeListener(_onTabChanged);
      _tabController?.dispose();
      if (_dayTabs.isNotEmpty) {
        _currentTabIndex = 0;
        _tabController = TabController(length: _dayTabs.length, vsync: this);
        _tabController!.addListener(_onTabChanged);
        _dateStartMillis = _dayTabs[0].startMillis;
        _dateEndMillis = _dayTabs[0].endMillis;
      } else {
        _currentTabIndex = 0;
        _tabController = null;
      }
    });
    await _reloadForCurrentTab(reset: true);
    // ignore: unawaited_futures
    _prefetchAdjacentTabs(_currentTabIndex);
    sw.stop();
    try {
      print(
        '[时间线] 准备日期标签完成，耗时 ${sw.elapsedMilliseconds} 毫秒 标签数=${_dayTabs.length}',
      );
    } catch (_) {}
  }

  int _readInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? 0;
  }

  Future<void> _computeDayCountsConcurrently(
    List<_DayTabInfo> tabs, {
    int concurrency = 4,
  }) async {
    if (tabs.isEmpty) return;
    final int maxConcurrent = concurrency <= 0 ? 1 : concurrency;
    int nextIndex = 0;
    Future<void> worker() async {
      for (;;) {
        int myIndex;
        if (nextIndex >= tabs.length) return;
        myIndex = nextIndex;
        nextIndex++;
        final day = tabs[myIndex];
        try {
          final c = await ScreenshotService.instance
              .getGlobalScreenshotCountBetween(
                startMillis: day.startMillis,
                endMillis: day.endMillis,
              );
          day.count = c;
        } catch (_) {
          day.count = 0;
        }
      }
    }

    final List<Future<void>> futures = List<Future<void>>.generate(
      maxConcurrent,
      (_) => worker(),
    );
    await Future.wait(futures);
  }

  void _onTabChanged() {
    if (!mounted || _tabController == null) return;
    // 与截图列表一致：等切换完成（indexIsChanging 为 false 时）再处理
    if (_tabController!.indexIsChanging) return;
    final idx = _tabController!.index;
    setState(() {
      _currentTabIndex = idx;
      _dateStartMillis = _dayTabs[idx].startMillis;
      _dateEndMillis = _dayTabs[idx].endMillis;
    });
    // 若当前已处于“最后一个可见日期Tab”，尝试向前扩展更多日期
    if (idx == _dayTabs.length - 1) {
      _expandDayTabsIfNeeded();
    }
    // 相邻Tab后台预取，提升切换体验
    // ignore: unawaited_futures
    _prefetchAdjacentTabs(idx);
    _reloadForCurrentTab(reset: true);
  }

  /// 当用户滑动到当前最后一个日期Tab附近时，尝试将可见窗口向前扩展14天
  void _expandDayTabsIfNeeded() {
    // ignore: discarded_futures
    _expandDayTabsIfNeededAsync();
  }

  Future<void> _expandDayTabsIfNeededAsync() async {
    if (!mounted) return;
    if (_isExpandingDayTabs) return;
    if (_dayTabs.isEmpty) return;

    _isExpandingDayTabs = true;
    try {
      // 当前已展示到缓冲末尾时，先向前增量拉取一段日期Tab（再展开可见窗口）
      if (_dayTabs.length >= _allDayTabs.length) {
        if (!_hasMoreDayTabs) return;
        final bool appended = await _appendOlderDayTabsToBuffer();
        if (!appended) return;
      }

      final int currentVisible = _dayTabs.length;
      final int targetVisible = math.min(
        _allDayTabs.length,
        currentVisible + _appendVisibleDayTabs,
      );
      if (targetVisible <= currentVisible) return;

      final int currentIndex = _tabController?.index ?? _currentTabIndex;
      _tabController?.removeListener(_onTabChanged);
      _tabController?.dispose();

      if (!mounted) return;
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
      _tabController!.addListener(_onTabChanged);
    } finally {
      _isExpandingDayTabs = false;
    }
  }

  Future<bool> _appendOlderDayTabsToBuffer() async {
    if (!mounted) return false;
    if (_allDayTabs.isEmpty) return false;

    final DateTime oldest = _allDayTabs.last.day;
    final DateTime endDay = DateTime(
      oldest.year,
      oldest.month,
      oldest.day,
    ).subtract(const Duration(days: 1));
    final int endMillis = DateTime(
      endDay.year,
      endDay.month,
      endDay.day,
      23,
      59,
      59,
    ).millisecondsSinceEpoch;

    // 处理“大空档”：若过去120天没有任何截图，但更早还有数据，则逐步扩大回溯窗口
    int lookback = _appendDayTabsLookbackDays;
    for (int attempt = 0; attempt < 4; attempt++) {
      final int daysBack = lookback <= 0 ? 1 : lookback;
      final DateTime startDay = DateTime(
        endDay.year,
        endDay.month,
        endDay.day,
      ).subtract(Duration(days: daysBack - 1));
      final int startMillis = startDay.millisecondsSinceEpoch;

      final List<Map<String, dynamic>> days = await ScreenshotService.instance
          .listAvailableDaysGlobalRange(
            startMillis: startMillis,
            endMillis: endMillis,
          );

      final List<_DayTabInfo> tabs = <_DayTabInfo>[];
      for (final m in days) {
        final String ds = (m['date'] as String?) ?? '';
        final int count = _readInt(m['count']);
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
      if (tabs.isNotEmpty) {
        if (!mounted) return false;
        setState(() {
          _allDayTabs.addAll(tabs);
          _hasMoreDayTabs = true;
        });
        return true;
      }

      if (lookback >= 3650) break; // 约10年
      lookback = math.min(3650, lookback * 3);
    }

    if (mounted) setState(() => _hasMoreDayTabs = false);
    return false;
  }

  Future<void> _reloadForCurrentTab({bool reset = false}) async {
    if (!mounted) return;
    if (_dateStartMillis == null || _dateEndMillis == null) return;
    if (reset) {
      setState(() {
        _screenshots
          ..clear()
          ..addAll(_tabCache[_currentTabIndex] ?? const <ScreenshotRecord>[]);
        _pageOffset = _tabOffset[_currentTabIndex] ?? _screenshots.length;
        _hasMore = _tabHasMore[_currentTabIndex] ?? true;
        _isLoadingMore = false;
      });
    }
    final int limit = _screenshots.isEmpty ? _initialPageSize : _pageSize;
    try {
      final batch = await ScreenshotService.instance
          .getGlobalScreenshotsBetween(
            startMillis: _dateStartMillis!,
            endMillis: _dateEndMillis!,
            limit: limit,
            offset: _pageOffset,
          );
      if (!mounted) return;
      setState(() {
        _screenshots.addAll(batch);
        _pageOffset += batch.length;
        _hasMore = batch.length >= limit;
        // 写回当前Tab缓存
        final list = _tabCache[_currentTabIndex] ?? <ScreenshotRecord>[];
        _tabCache[_currentTabIndex] = List<ScreenshotRecord>.from(list)
          ..addAll(batch);
        _tabOffset[_currentTabIndex] = _pageOffset;
        _tabHasMore[_currentTabIndex] = _hasMore;
      });
      // 预加载 NSFW（手动标记 + AI NSFW），确保遮罩/标记一致
      // ignore: unawaited_futures
      _preloadNsfwFor(batch);
      try {
        if (batch.isNotEmpty) {
          final DateTime first = batch.first.captureTime;
          final DateTime last = batch.last.captureTime;
          print(
            '[时间线] 加载批次 数量=' +
                batch.length.toString() +
                ' 偏移=' +
                (_pageOffset - batch.length).toString() +
                ' 首条=' +
                first.toIso8601String() +
                ' 末条=' +
                last.toIso8601String(),
          );
        } else {
          print('[时间线] 加载批次为空 偏移=' + _pageOffset.toString());
        }
      } catch (_) {}
    } catch (_) {}
    // 加载完成后，如果存在待处理跳转且未处于跳转处理中，则尝试处理
    if (_pendingJump != null && !_jumpInProgress) {
      try {
        FlutterLogger.nativeDebug('TimelineJump', '数据加载完成，检查是否可处理待跳转');
      } catch (_) {}
      _handleJumpRequestIfPossible();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    await _reloadForCurrentTab(reset: false);
    if (mounted) setState(() => _isLoadingMore = false);
  }

  /// 顶部刷新：重载当前日期的时间线数据并更新计数
  Future<void> _refresh() async {
    if (!mounted) return;
    if (_refreshing) return;
    _refreshing = true;
    try {
      if (_dayTabs.isEmpty ||
          _dateStartMillis == null ||
          _dateEndMillis == null) {
        await _prepareDayTabs();
        return;
      }
      final int idx = _currentTabIndex;
      setState(() {
        _screenshots.clear();
        _pageOffset = 0;
        _hasMore = true;
        _isLoadingMore = false;
        _tabCache[idx] = <ScreenshotRecord>[];
        _tabOffset[idx] = 0;
        _tabHasMore[idx] = true;
      });
      await _refreshCurrentTabCount();
      await _reloadForCurrentTab(reset: true);
    } finally {
      _refreshing = false;
    }
  }

  /// 刷新当前Tab的计数标签
  Future<void> _refreshCurrentTabCount() async {
    if (_currentTabIndex < 0 || _currentTabIndex >= _dayTabs.length) return;
    try {
      final c = await ScreenshotService.instance
          .getGlobalScreenshotCountBetween(
            startMillis: _dayTabs[_currentTabIndex].startMillis,
            endMillis: _dayTabs[_currentTabIndex].endMillis,
          );
      if (!mounted) return;
      setState(() {
        _dayTabs[_currentTabIndex].count = c;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ValueListenableBuilder<ReplayExportTask?>(
      valueListenable: ReplayExportService.instance.exportTaskNotifier,
      builder: (context, task, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final l10n = AppLocalizations.of(context);

        final Widget titleWidget;
        if (task == null) {
          titleWidget = Text(l10n.timelineTitle);
        } else {
          final String rangeText = _formatReplayExportRange(
            task.start,
            task.end,
          );
          titleWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacing2),
              Flexible(
                child: Text(
                  l10n.timelineReplayGeneratingRange(rangeText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        }
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 48,
            centerTitle: true,
            automaticallyImplyLeading: false,
            leadingWidth: Platform.isAndroid ? 40 : 0,
            leading: Platform.isAndroid
                ? IconButton(
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: _showReplaySheet,
                    tooltip: l10n.timelineReplay,
                  )
                : null,
            title: Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: titleWidget,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refresh,
                tooltip: l10n.actionRefresh,
              ),
            ],
          ),
          body: _loading
              ? const UILoadingState(compact: true)
              : _dayTabs.isEmpty
              ? UIEmptyState(
                  title: l10n.noScreenshotsTitle,
                  message: l10n.noScreenshotsSubtitle,
                  icon: Icons.photo_library_outlined,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 与截图列表一致的Tab样式与内边距
                    Builder(
                      builder: (context) {
                        if (_dayTabs.isEmpty || _tabController == null) {
                          return const SizedBox(height: 32);
                        }
                        final bool hasMoreTabs =
                            _dayTabs.length < _allDayTabs.length ||
                            _hasMoreDayTabs;
                        return SizedBox(
                          height: 32,
                          child: Transform.translate(
                            offset: const Offset(0, -2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ScreenshotStyleTabBar(
                                    controller: _tabController,
                                    // 与截图列表一致：左侧少量起始内边距，去除额外垂直内边距
                                    padding: const EdgeInsets.only(
                                      left: AppTheme.spacing2,
                                    ),
                                    // 与截图列表一致：标签水平留白适中
                                    labelPadding: const EdgeInsets.symmetric(
                                      horizontal: AppTheme.spacing4,
                                    ),
                                    indicatorInsets: const EdgeInsets.symmetric(
                                      horizontal: 4.0,
                                    ),
                                    tabs: _dayTabs.map((t) {
                                      final l10n = AppLocalizations.of(context);
                                      final text = _DayTabInfo._isToday(t.day)
                                          ? l10n.dayTabToday(t.count)
                                          : (_DayTabInfo._isYesterday(t.day)
                                                ? l10n.dayTabYesterday(t.count)
                                                : l10n.dayTabMonthDayCount(
                                                    t.day.month,
                                                    t.day.day,
                                                    t.count,
                                                  ));
                                      return Tab(text: text);
                                    }).toList(),
                                  ),
                                ),
                                if (hasMoreTabs)
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
                                      icon: const Icon(
                                        Icons.more_horiz,
                                        size: 18,
                                      ),
                                      label: Text(
                                        AppLocalizations.of(context).loadMore,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    // 日期Tab与内容之间增加1px底部外边距
                    const SizedBox(height: 1),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        physics: const ClampingScrollPhysics(),
                        children: _dayTabs
                            .asMap()
                            .entries
                            .map(
                              (entry) => Builder(
                                builder: (_) => _buildGridForIndex(entry.key),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  String _formatReplayExportRange(DateTime start, DateTime end) {
    final Locale locale = Localizations.localeOf(context);
    final bool isZh = locale.languageCode == 'zh';
    final String localeName = locale.toString();

    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final bool isSameDay = sameDay(start, end);
    final bool isFullDay =
        isSameDay &&
        start.hour == 0 &&
        start.minute == 0 &&
        end.hour == 23 &&
        end.minute == 59;

    final DateFormat dayFmt = isZh
        ? DateFormat('M月d日')
        : DateFormat.MMMd(localeName);
    if (isFullDay) return dayFmt.format(start);

    if (isSameDay) {
      final DateFormat timeFmt = isZh
          ? DateFormat('HH:mm')
          : DateFormat.Hm(localeName);
      return '${dayFmt.format(start)} ${timeFmt.format(start)}-${timeFmt.format(end)}';
    }

    return '${dayFmt.format(start)}-${dayFmt.format(end)}';
  }

  Future<void> _showReplaySheet() async {
    if (_dateStartMillis == null || _dateEndMillis == null) return;
    final DateTime dayStart = DateTime.fromMillisecondsSinceEpoch(
      _dateStartMillis!,
    );
    final DateTime dayEnd = DateTime.fromMillisecondsSinceEpoch(
      _dateEndMillis!,
    );
    await TimelineReplaySheet.show(
      context: context,
      initialStart: dayStart,
      initialEnd: dayEnd,
      dayStart: dayStart,
      dayEnd: dayEnd,
    );
  }

  Widget _buildGridForIndex(int tabIndex) {
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
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacing1,
            0,
            AppTheme.spacing1,
            AppTheme.spacing1,
          ),
          child: Container(
            key: isCurrent ? _gridKey : null,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                _tabScrollOffset[tabIndex] = n.metrics.pixels;
                if (isCurrent &&
                    n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                  _loadMore();
                }
                return false;
              },
              child: GridView.builder(
                key: PageStorageKey<String>('timeline_grid_tab_$tabIndex'),
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
                itemBuilder: (context, index) => AutoScrollTag(
                  key: ValueKey(index),
                  controller: _controllerForTab(tabIndex),
                  index: index,
                  highlightColor: Colors.transparent,
                  child: _buildItem(data[index], index),
                ),
              ),
            ),
          ),
        ),
        if (isCurrent && _dayTabs.length > 1) _buildTimelineOverlay(),
      ],
    );
  }

  Future<void> _ensureTabsIncludeDate(DateTime dt) async {
    final int targetStart = DateTime(
      dt.year,
      dt.month,
      dt.day,
    ).millisecondsSinceEpoch;
    final int targetEnd = DateTime(
      dt.year,
      dt.month,
      dt.day,
      23,
      59,
      59,
    ).millisecondsSinceEpoch;
    final bool exists = _dayTabs.any(
      (t) => t.startMillis == targetStart && t.endMillis == targetEnd,
    );
    if (exists) return;

    // 仅查询目标日期的计数，避免扩展至大量天数导致卡顿
    int count = 0;
    try {
      count = await ScreenshotService.instance.getGlobalScreenshotCountBetween(
        startMillis: targetStart,
        endMillis: targetEnd,
      );
    } catch (_) {}
    if (count <= 0) return;

    // 仅在列表末尾追加一个目标日期 Tab，避免破坏现有基于 index 的缓存映射
    final _DayTabInfo newInfo = _DayTabInfo(
      day: DateTime(dt.year, dt.month, dt.day),
      startMillis: targetStart,
      endMillis: targetEnd,
      count: count,
    );

    setState(() {
      _dayTabs.add(newInfo);

      // 重建 TabController，保持当前选中索引不变，避免触发不必要的切换
      final int oldIndex = _currentTabIndex;
      _tabController?.removeListener(_onTabChanged);
      _tabController?.dispose();
      _tabController = TabController(length: _dayTabs.length, vsync: this);
      _tabController!.addListener(_onTabChanged);
      _tabController!.index = (oldIndex >= 0 && oldIndex < _dayTabs.length)
          ? oldIndex
          : 0;

      // 为新 Tab 建立占位缓存，避免访问空映射
      final int newIndex = _dayTabs.length - 1;
      _tabCache[newIndex] = <ScreenshotRecord>[];
      _tabOffset[newIndex] = 0;
      _tabHasMore[newIndex] = true;
    });
  }

  Future<void> _handleJumpRequestIfPossible() async {
    if (_pendingJump == null || _jumpInProgress) return;
    _jumpInProgress = true;
    try {
      final String targetPath = _pendingJump!.filePath;
      try {
        FlutterLogger.nativeInfo('TimelineJump', '开始处理跳转请求 路径=' + targetPath);
      } catch (_) {}
      // 解析目标记录，确定 captureTime
      ScreenshotRecord? rec;
      try {
        rec = await ScreenshotDatabase.instance.getScreenshotByPath(targetPath);
      } catch (_) {}
      if (rec == null) {
        // 数据库未命中，保持请求并稍后重试（冷启动导入尚未完成的可能）
        try {
          FlutterLogger.nativeWarn(
            'TimelineJump',
            '数据库未命中，延迟重试 路径=' + targetPath,
          );
        } catch (_) {}
        // 释放进行中标记，稍后重试
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) _handleJumpRequestIfPossible();
        });
        return; // 交由重试处理
      }

      // 确保日期标签包含目标日期（可能超出默认14天）
      await _ensureTabsIncludeDate(rec.captureTime);

      // 选择日期标签
      final dt = rec.captureTime;
      final int start = DateTime(
        dt.year,
        dt.month,
        dt.day,
      ).millisecondsSinceEpoch;
      final int end = DateTime(
        dt.year,
        dt.month,
        dt.day,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;
      int tabIndex = 0;
      for (int i = 0; i < _dayTabs.length; i++) {
        if (_dayTabs[i].startMillis == start && _dayTabs[i].endMillis == end) {
          tabIndex = i;
          break;
        }
      }
      if (_tabController == null || _dayTabs.isEmpty) return;

      if (tabIndex != _currentTabIndex) {
        _tabController!.index = tabIndex;
        _onTabChanged();
        // 等待一帧，确保 Tab 切换和列表构建
        await Future.delayed(const Duration(milliseconds: 16));
        try {
          FlutterLogger.nativeDebug('TimelineJump', '已切换到目标日期标签，等待网格就绪');
        } catch (_) {}
      }

      // 确保当前标签数据加载
      if (_screenshots.isEmpty) {
        await _reloadForCurrentTab(reset: true);
      }

      // 额外等待网格与滚动控制器就绪（首帧可能尚未有尺寸）
      final bool ready = await _waitForGridReady(
        timeout: const Duration(seconds: 2),
      );
      if (!ready) {
        try {
          FlutterLogger.nativeWarn('TimelineJump', '等待网格就绪超时，将稍后重试');
        } catch (_) {}
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await Future.delayed(const Duration(milliseconds: 200));
          if (mounted) _handleJumpRequestIfPossible();
        });
        return;
      }

      // 在当前列表中查找目标索引（以文件路径比对）
      int idx = _screenshots.indexWhere((e) => e.filePath == targetPath);
      if (idx >= 0) {
        try {
          FlutterLogger.nativeInfo(
            'TimelineJump',
            '找到目标索引 idx=' + idx.toString(),
          );
        } catch (_) {}
        await _scrollToIndexAndHighlight(idx);
        _pendingJump = null; // 完成
        // 消费一次后清空全局跳转请求，避免下次进入仍然触发
        try {
          TimelineJumpService.instance.requestNotifier.value = null;
        } catch (_) {}
        return;
      }

      // 快速路径：通过 DB 计算“当日中比目标更新的数量”，直接定位到近似页，再在页内精确查找
      bool jumped = false;
      try {
        final int startMs = DateTime(
          dt.year,
          dt.month,
          dt.day,
        ).millisecondsSinceEpoch;
        final int endMs = DateTime(
          dt.year,
          dt.month,
          dt.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch;
        final int targetMs = dt.millisecondsSinceEpoch;
        final int newerCount = await ScreenshotService.instance
            .getGlobalScreenshotCountBetween(
              startMillis: targetMs + 1, // 严格更“新”的数量，避免等时冲突
              endMillis: endMs,
            );
        final int dayCount =
            (_dayTabs.isNotEmpty &&
                _currentTabIndex >= 0 &&
                _currentTabIndex < _dayTabs.length)
            ? (_dayTabs[_currentTabIndex].count)
            : 0;
        final int pageStart = (newerCount ~/ _pageSize) * _pageSize;
        final int primaryLimit = _pageSize * 2; // 主动多取一页，提升命中概率
        try {
          FlutterLogger.nativeInfo(
            'TimelineJump',
            '快速定位计算: 更近数量=' +
                newerCount.toString() +
                ', 页起始=' +
                pageStart.toString() +
                ', 限制=' +
                primaryLimit.toString(),
          );
        } catch (_) {}

        // 主尝试：以 pageStart 为起点加载一个较大的切片
        List<ScreenshotRecord> batch = await ScreenshotService.instance
            .getGlobalScreenshotsBetween(
              startMillis: startMs,
              endMillis: endMs,
              limit: primaryLimit,
              offset: pageStart,
            );
        if (mounted) {
          setState(() {
            _screenshots = List<ScreenshotRecord>.from(batch);
            _pageOffset = pageStart + batch.length;
            _hasMore = (dayCount > 0)
                ? (_pageOffset < dayCount)
                : (batch.length >= primaryLimit);
            _tabCache[_currentTabIndex] = List<ScreenshotRecord>.from(batch);
            _tabOffset[_currentTabIndex] = _pageOffset;
            _tabHasMore[_currentTabIndex] = _hasMore;
          });
        }
        idx = _screenshots.indexWhere((e) => e.filePath == targetPath);
        if (idx >= 0) {
          try {
            FlutterLogger.nativeInfo(
              'TimelineJump',
              '快速路径命中，目标位于当前切片 idx=' + idx.toString(),
            );
          } catch (_) {}
          await _scrollToIndexAndHighlight(idx);
          _pendingJump = null;
          try {
            TimelineJumpService.instance.requestNotifier.value = null;
          } catch (_) {}
          jumped = true;
        } else {
          // 备选尝试：向前回退一页扩大窗口
          final int altStart = math.max(0, pageStart - _pageSize);
          final int altLimit = _pageSize * 3; // 再扩大一点窗口
          try {
            FlutterLogger.nativeDebug(
              'TimelineJump',
              '快速路径未命中，尝试回退窗口 备用起点=' +
                  altStart.toString() +
                  ', 限制=' +
                  altLimit.toString(),
            );
          } catch (_) {}
          batch = await ScreenshotService.instance.getGlobalScreenshotsBetween(
            startMillis: startMs,
            endMillis: endMs,
            limit: altLimit,
            offset: altStart,
          );
          if (mounted) {
            setState(() {
              _screenshots = List<ScreenshotRecord>.from(batch);
              _pageOffset = altStart + batch.length;
              _hasMore = (dayCount > 0)
                  ? (_pageOffset < dayCount)
                  : (batch.length >= altLimit);
              _tabCache[_currentTabIndex] = List<ScreenshotRecord>.from(batch);
              _tabOffset[_currentTabIndex] = _pageOffset;
              _tabHasMore[_currentTabIndex] = _hasMore;
            });
          }
          idx = _screenshots.indexWhere((e) => e.filePath == targetPath);
          if (idx >= 0) {
            try {
              FlutterLogger.nativeInfo(
                'TimelineJump',
                '回退窗口命中，目标位于切片 idx=' + idx.toString(),
              );
            } catch (_) {}
            await _scrollToIndexAndHighlight(idx);
            _pendingJump = null;
            try {
              TimelineJumpService.instance.requestNotifier.value = null;
            } catch (_) {}
            jumped = true;
          }
        }
      } catch (_) {}

      if (jumped) return;

      // 回退：未命中时再做按页加载（设上限，避免长时间阻塞）
      int safetyRounds = 6; // 最多再加载6批
      while (_hasMore && safetyRounds-- > 0) {
        try {
          FlutterLogger.nativeDebug('TimelineJump', '未找到目标，尝试分页加载更多');
        } catch (_) {}
        await _loadMore();
        idx = _screenshots.indexWhere((e) => e.filePath == targetPath);
        if (idx >= 0) {
          try {
            FlutterLogger.nativeInfo(
              'TimelineJump',
              '分页后找到目标索引 idx=' + idx.toString(),
            );
          } catch (_) {}
          await _scrollToIndexAndHighlight(idx);
          _pendingJump = null;
          try {
            TimelineJumpService.instance.requestNotifier.value = null;
          } catch (_) {}
          break;
        }
      }
    } finally {
      _jumpInProgress = false;
    }
  }

  Future<void> _scrollToIndexAndHighlight(int index) async {
    final ctrl = _controllerForTab(_currentTabIndex);
    if (!ctrl.hasClients) return;
    try {
      FlutterLogger.nativeInfo(
        'TimelineJump',
        '使用 scroll_to_index 定位 idx=' + index.toString(),
      );
    } catch (_) {}
    try {
      await ctrl.scrollToIndex(index, preferPosition: AutoScrollPosition.begin);
    } catch (_) {}
  }

  /// 等待当前时间线网格与滚动控制器就绪（尺寸可用、hasClients）
  Future<bool> _waitForGridReady({
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final sw = Stopwatch()..start();
    while (mounted && sw.elapsed < timeout) {
      final ctrl = _controllerForTab(_currentTabIndex);
      final bool has = ctrl.hasClients;
      final double gw = (_gridKey.currentContext?.size?.width ?? 0);
      if (has && gw > 0) {
        // 额外等待一帧，确保子元素完成布局
        await Future.delayed(const Duration(milliseconds: 16));
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 16));
    }
    return false;
  }

  AutoScrollController _controllerForTab(int index) {
    if (_tabScrollControllers.containsKey(index))
      return _tabScrollControllers[index]!;
    final c = AutoScrollController(
      initialScrollOffset: _tabScrollOffset[index] ?? 0.0,
    );
    c.addListener(() {
      _tabScrollOffset[index] = c.offset;
    });
    _tabScrollControllers[index] = c;
    return c;
  }

  // 右侧时间线滚动条（与截图列表样式与显示时机保持一致）
  Widget _buildTimelineOverlay() {
    // 与截图列表一致：有数据、已加载完毕且数量>=2时才显示
    if (_screenshots.isEmpty || _screenshots.length < 2) {
      return const SizedBox.shrink();
    }

    const double gestureWidth = 44; // 交互区域
    const double trackWidth = 3; // 轨道宽
    const double thumbHeight = 32; // 拇指高
    const double labelHeight = 28; // 时间标签高

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double viewHeight = constraints.maxHeight;
          final double bottomMargin =
              MediaQuery.of(context).padding.bottom +
              AppTheme.spacing6 +
              AppTheme.spacing1;
          final double trackHeight = (viewHeight - bottomMargin).clamp(
            0,
            viewHeight,
          );

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

          // 计算首个可见项时间
          final int firstVisibleIndex = _getFirstVisibleIndex();
          final String timeLabel =
              (firstVisibleIndex >= 0 &&
                  firstVisibleIndex < _screenshots.length)
              ? _formatTimelineTime(_screenshots[firstVisibleIndex].captureTime)
              : '';

          return Stack(
            children: [
              Positioned(
                right: 0,
                top: 0,
                bottom: bottomMargin,
                width: gestureWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: (details) {
                    if (trackHeight > thumbHeight) {
                      _timelineActive = true;
                      _timelineFraction =
                          (details.localPosition.dy / trackHeight).clamp(
                            0.0,
                            1.0,
                          );
                      setState(() {});
                      _scheduleScrubJump();
                    }
                  },
                  onVerticalDragUpdate: (details) {
                    if (trackHeight > thumbHeight && _timelineActive) {
                      _timelineFraction =
                          (details.localPosition.dy / trackHeight).clamp(
                            0.0,
                            1.0,
                          );
                      setState(() {});
                      _scheduleScrubJump();
                    }
                  },
                  onVerticalDragEnd: (_) {
                    if (mounted)
                      setState(() {
                        _timelineActive = false;
                      });
                  },
                  onLongPressStart: (details) {
                    if (trackHeight > thumbHeight) {
                      _timelineActive = true;
                      _timelineFraction =
                          (details.localPosition.dy / trackHeight).clamp(
                            0.0,
                            1.0,
                          );
                      setState(() {});
                      _scheduleScrubJump();
                    }
                  },
                  onLongPressMoveUpdate: (details) {
                    if (trackHeight > thumbHeight && _timelineActive) {
                      _timelineFraction =
                          (details.localPosition.dy / trackHeight).clamp(
                            0.0,
                            1.0,
                          );
                      setState(() {});
                      _scheduleScrubJump();
                    }
                  },
                  onLongPressEnd: (_) {
                    if (mounted)
                      setState(() {
                        _timelineActive = false;
                      });
                  },
                  child: Stack(
                    children: [
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
                      borderRadius: BorderRadius.circular(6),
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

  // 计算首个可见项索引（用于时间标签）
  int _getFirstVisibleIndex() {
    if (!mounted || _screenshots.isEmpty || _itemKeys.isEmpty) return 0;
    final ctx = _gridKey.currentContext;
    if (ctx == null) return 0;
    final render = ctx.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return 0;
    final viewport = render.localToGlobal(Offset.zero) & render.size;
    int? firstIdx;
    double? minTop;
    _itemKeys.forEach((index, key) {
      if (index >= _screenshots.length) return;
      final kctx = key.currentContext;
      if (kctx == null) return;
      final r = kctx.findRenderObject();
      if (r is! RenderBox || !r.hasSize) return;
      final rect = r.localToGlobal(Offset.zero) & r.size;
      final visible = rect.bottom > viewport.top && rect.top < viewport.bottom;
      if (!visible) return;
      if (minTop == null || rect.top < minTop!) {
        minTop = rect.top;
        firstIdx = index;
      }
    });
    return (firstIdx != null && firstIdx! < _screenshots.length)
        ? firstIdx!
        : 0;
  }

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

  double _currentScrollFraction() {
    final ctrl = _controllerForTab(_currentTabIndex);
    if (!ctrl.hasClients) return 0.0;
    final maxExtent = ctrl.position.maxScrollExtent;
    if (maxExtent <= 0) return 0.0;
    final pixels = ctrl.position.pixels;
    final double f = pixels / maxExtent;
    return f.clamp(0.0, 1.0);
  }

  void _scrollToFraction(double fraction) {
    final ctrl = _controllerForTab(_currentTabIndex);
    if (!ctrl.hasClients || !mounted) return;
    final maxExtent = ctrl.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    final target = fraction.clamp(0.0, 1.0) * maxExtent;
    ctrl.jumpTo(target);
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

  Future<void> _prefetchFirstPageForTab(int index) async {
    if (!mounted) return;
    if (index < 0 || index >= _dayTabs.length) return;
    if ((_tabCache[index]?.isNotEmpty ?? false)) return;
    final day = _dayTabs[index];
    if (day.count <= 0) return;
    try {
      final batch = await ScreenshotService.instance
          .getGlobalScreenshotsBetween(
            startMillis: day.startMillis,
            endMillis: day.endMillis,
            limit: _initialPageSize,
            offset: 0,
          );
      if (!mounted) return;
      setState(() {
        _tabCache[index] = List<ScreenshotRecord>.from(batch);
        _tabOffset[index] = batch.length;
        _tabHasMore[index] = batch.length < day.count;
        if (index == _currentTabIndex && _screenshots.isEmpty) {
          _screenshots = List<ScreenshotRecord>.from(batch);
          _pageOffset = _tabOffset[index] ?? _screenshots.length;
          _hasMore = _tabHasMore[index] ?? false;
        }
      });
      // ignore: unawaited_futures
      _preloadNsfwFor(batch);
    } catch (_) {}
  }

  Future<void> _preloadNsfwFor(List<ScreenshotRecord> data) async {
    if (data.isEmpty) return;
    try {
      // 1) AI NSFW（按 file_path，全局复用）
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

      // 2) 手动标记（按 app 分组）
      final Map<String, List<int>> idsByApp = <String, List<int>>{};
      for (final s in data) {
        final id = s.id;
        final pkg = s.appPackageName.trim();
        if (id == null || pkg.isEmpty) continue;
        idsByApp.putIfAbsent(pkg, () => <int>[]).add(id);
      }
      for (final entry in idsByApp.entries) {
        final ids = entry.value;
        if (ids.isEmpty) continue;
        await NsfwPreferenceService.instance.preloadManualFlags(
          appPackageName: entry.key,
          screenshotIds: ids,
        );
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _prefetchAllTabsFirst8() async {
    // 已弃用：全量串行预取会阻塞首屏
  }

  Future<void> _prefetchAdjacentTabs(int center) async {
    if (!mounted || _dayTabs.isEmpty) return;
    final List<int> candidates = <int>{
      center - 1,
      center + 1,
    }.where((i) => i >= 0 && i < _dayTabs.length).toList();
    for (final i in candidates) {
      try {
        await _prefetchFirstPageForTab(i);
      } catch (_) {}
    }
  }

  Widget _buildItem(ScreenshotRecord screenshot, int index) {
    final GlobalKey itemKey = _itemKeys.putIfAbsent(index, () => GlobalKey());
    final bool isNsfw = NsfwPreferenceService.instance.shouldMaskCached(
      screenshot,
    );
    final bool nsfwMasked = _privacyMode && isNsfw;

    final content = ScreenshotItemWidget(
      screenshot: screenshot,
      appInfoMap: _appInfoByPackage,
      privacyMode: _privacyMode,
      showNsfwButton: false,
      isNsfwFlagged: isNsfw,
      onTap: () {
        if (!nsfwMasked) {
          _viewFromCurrent(index);
        }
      },
      onLinkTap: (url) => _openLink(url),
    );

    return KeyedSubtree(key: itemKey, child: content);
  }

  Future<void> _openLink(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _viewFromCurrent(int index) {
    if (index < 0 || index >= _screenshots.length) return;
    final shot = _screenshots[index];
    final app =
        _appInfoByPackage[shot.appPackageName] ??
        AppInfo(
          packageName: shot.appPackageName,
          appName: shot.appName,
          icon: null,
          version: '',
          isSystemApp: false,
        );
    Navigator.pushNamed(
      context,
      '/screenshot_viewer',
      arguments: {
        'screenshots': _screenshots,
        'initialIndex': index,
        'appName': shot.appName,
        'appInfo': app,
        'multiApp': true,
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    _tabController?.dispose();
    // 逐一释放各Tab滚动控制器
    for (final c in _tabScrollControllers.values) {
      c.dispose();
    }
    // 取消生命周期订阅
    _lifecycleSub?.cancel();
    try {
      if (_jumpListener != null)
        TimelineJumpService.instance.requestNotifier.removeListener(
          _jumpListener!,
        );
    } catch (_) {}
    super.dispose();
  }
}

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
