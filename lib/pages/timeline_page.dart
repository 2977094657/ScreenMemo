import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/screenshot_record.dart';
import '../services/screenshot_service.dart';
import '../services/app_selection_service.dart';
import '../models/app_info.dart';
import '../widgets/nsfw_guard.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final Map<int, List<ScreenshotRecord>> _tabCache = <int, List<ScreenshotRecord>>{};
  final Map<int, int> _tabOffset = <int, int>{};
  final Map<int, bool> _tabHasMore = <int, bool>{};
  final Map<int, ScrollController> _tabScrollControllers = <int, ScrollController>{};
  final Map<int, double> _tabScrollOffset = <int, double>{};
  // 时间线滚动条交互状态（右侧快速滚动）
  bool _timelineActive = false;
  double _timelineFraction = 0.0;
  final GlobalKey _gridKey = GlobalKey();
  final Map<int, GlobalKey> _itemKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _init();
    // 订阅隐私模式变更
    AppSelectionService.instance.onPrivacyModeChanged.listen((enabled) {
      if (!mounted) return;
      setState(() { _privacyMode = enabled; });
    });
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    await _loadAppInfos();
    await _loadPrivacyMode();
    await _prepareDayTabs();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPrivacyMode() async {
    try {
      final enabled = await AppSelectionService.instance.getPrivacyModeEnabled();
      if (mounted) setState(() { _privacyMode = enabled; });
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

  Future<void> _prepareDayTabs({int days = 14}) async {
    final DateTime today = DateTime.now();
    final DateTime base = DateTime(today.year, today.month, today.day);
    final List<_DayTabInfo> tabs = <_DayTabInfo>[];

    for (int i = 0; i < days; i++) {
      final DateTime d = base.subtract(Duration(days: i));
      final int start = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
      final int end = DateTime(d.year, d.month, d.day, 23, 59, 59).millisecondsSinceEpoch;
      tabs.add(_DayTabInfo(day: d, startMillis: start, endMillis: end));
    }

    for (int i = 0; i < tabs.length; i++) {
      try {
        final c = await ScreenshotService.instance.getGlobalScreenshotCountBetween(
          startMillis: tabs[i].startMillis,
          endMillis: tabs[i].endMillis,
        );
        tabs[i].count = c;
        if (mounted) setState(() {});
      } catch (_) {}
    }

    if (!mounted) return;
    final available = tabs.where((t) => t.count > 0).toList();
    setState(() {
      _dayTabs
        ..clear()
        ..addAll(available);
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
    // 预取所有Tab的首屏缓存，再显示当前Tab
    await _prefetchAllTabsFirst8();
    await _reloadForCurrentTab(reset: true);
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
    _reloadForCurrentTab(reset: true);
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
      final batch = await ScreenshotService.instance.getGlobalScreenshotsBetween(
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
        _tabCache[_currentTabIndex] = List<ScreenshotRecord>.from(list)..addAll(batch);
        _tabOffset[_currentTabIndex] = _pageOffset;
        _tabHasMore[_currentTabIndex] = _hasMore;
      });
    } catch (_) {}
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    await _reloadForCurrentTab(reset: false);
    if (mounted) setState(() => _isLoadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 40,
        title: const Text('时间线'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _dayTabs.isEmpty
              ? const Center(child: Text('No screenshots'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 与截图列表一致的Tab样式与内边距
                    Padding(
                      padding: const EdgeInsets.only(left: 0, right: AppTheme.spacing1),
                      child: _dayTabs.isEmpty || _tabController == null
                          ? const SizedBox(height: 32)
                          : SizedBox(
                              height: 32,
                              child: TabBar(
                                controller: _tabController,
                                isScrollable: true,
                                tabAlignment: TabAlignment.start,
                                padding: const EdgeInsets.only(left: AppTheme.spacing2),
                                // 增加时间线日期Tab的左右间距（仅时间线页）
                                labelPadding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
                                labelColor: (Theme.of(context).brightness == Brightness.dark
                                    ? AppTheme.darkForeground
                                    : AppTheme.foreground),
                                unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color ?? AppTheme.mutedForeground,
                                labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                unselectedLabelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                                dividerColor: Colors.transparent,
                                indicatorSize: TabBarIndicatorSize.label,
                                indicator: UnderlineTabIndicator(
                                  borderSide: BorderSide(
                                    width: 2.0,
                                    color: (Theme.of(context).brightness == Brightness.dark
                                        ? AppTheme.darkForeground
                                        : AppTheme.foreground),
                                  ),
                                  insets: const EdgeInsets.symmetric(horizontal: 4.0),
                                ),
                                tabs: _dayTabs.map((t) => Tab(text: t.buildLabel())).toList(),
                              ),
                            ),
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
                            .map((entry) => _buildGridForIndex(entry.key))
                            .toList(),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildGridForIndex(int tabIndex) {
    final bool isCurrent = tabIndex == _currentTabIndex;
    final List<ScreenshotRecord> data = isCurrent
        ? _screenshots
        : List<ScreenshotRecord>.from(_tabCache[tabIndex] ?? const <ScreenshotRecord>[]);
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
          padding: const EdgeInsets.fromLTRB(AppTheme.spacing1, 0, AppTheme.spacing1, AppTheme.spacing1),
          child: Container(
            key: isCurrent ? _gridKey : null,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                _tabScrollOffset[tabIndex] = n.metrics.pixels;
                if (isCurrent && n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
                  _loadMore();
                }
                return false;
              },
              child: GridView.builder(
                key: PageStorageKey<String>('timeline_grid_tab_$tabIndex'),
                controller: _controllerForTab(tabIndex),
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
                itemBuilder: (context, index) => _buildItem(data[index], index),
              ),
            ),
          ),
        ),
        if (isCurrent) _buildTimelineOverlay(),
      ],
    );
  }

  ScrollController _controllerForTab(int index) {
    if (_tabScrollControllers.containsKey(index)) return _tabScrollControllers[index]!;
    final c = ScrollController(initialScrollOffset: _tabScrollOffset[index] ?? 0.0);
    c.addListener(() {
      _tabScrollOffset[index] = c.offset;
    });
    _tabScrollControllers[index] = c;
    return c;
  }

  // 右侧时间线滚动条（与截图列表样式与显示时机保持一致）
  Widget _buildTimelineOverlay() {
    // 与截图列表一致：有数据、已加载完毕且数量>=2时才显示
    if (_screenshots.isEmpty || _hasMore || _screenshots.length < 2) {
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
              MediaQuery.of(context).padding.bottom + AppTheme.spacing6 + AppTheme.spacing1;
          final double trackHeight = (viewHeight - bottomMargin).clamp(0, viewHeight);

          final ctrl = _controllerForTab(_currentTabIndex);
          if (trackHeight <= 0 || !ctrl.hasClients) {
            return const SizedBox.shrink();
          }

          final double currentFraction = _timelineActive
              ? _timelineFraction
              : _currentScrollFraction();
          final double clampedFraction = currentFraction.clamp(0.0, 1.0);
          final double thumbTop = clampedFraction * (trackHeight - thumbHeight).clamp(0, trackHeight);

          // 计算首个可见项时间
          final int firstVisibleIndex = _getFirstVisibleIndex();
          final String timeLabel = (firstVisibleIndex >= 0 && firstVisibleIndex < _screenshots.length)
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
                      _timelineFraction = (details.localPosition.dy / trackHeight).clamp(0.0, 1.0);
                      setState(() {});
                      _scrollToFraction(_timelineFraction);
                    }
                  },
                  onVerticalDragUpdate: (details) {
                    if (trackHeight > thumbHeight && _timelineActive) {
                      _timelineFraction = (details.localPosition.dy / trackHeight).clamp(0.0, 1.0);
                      setState(() {});
                      _scrollToFraction(_timelineFraction);
                    }
                  },
                  onVerticalDragEnd: (_) {
                    if (mounted) setState(() { _timelineActive = false; });
                  },
                  onLongPressStart: (details) {
                    if (trackHeight > thumbHeight) {
                      _timelineActive = true;
                      _timelineFraction = (details.localPosition.dy / trackHeight).clamp(0.0, 1.0);
                      setState(() {});
                      _scrollToFraction(_timelineFraction);
                    }
                  },
                  onLongPressMoveUpdate: (details) {
                    if (trackHeight > thumbHeight && _timelineActive) {
                      _timelineFraction = (details.localPosition.dy / trackHeight).clamp(0.0, 1.0);
                      setState(() {});
                      _scrollToFraction(_timelineFraction);
                    }
                  },
                  onLongPressEnd: (_) {
                    if (mounted) setState(() { _timelineActive = false; });
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
                  top: (clampedFraction * (trackHeight - labelHeight)).clamp(0, trackHeight - labelHeight),
                  child: Container(
                    height: labelHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Theme.of(context).dividerColor, width: 1),
                    ),
                    child: Text(
                      timeLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
    return (firstIdx != null && firstIdx! < _screenshots.length) ? firstIdx! : 0;
  }

  String _formatTimelineTime(DateTime dateTime) {
    final now = DateTime.now();
    final bool sameDay = now.year == dateTime.year && now.month == dateTime.month && now.day == dateTime.day;
    final bool sameYear = now.year == dateTime.year;
    String hh = dateTime.hour.toString().padLeft(2, '0');
    String mm = dateTime.minute.toString().padLeft(2, '0');
    if (sameDay) {
      return '$hh:$mm';
    } else if (sameYear) {
      return '${dateTime.month}月${dateTime.day}日 $hh:$mm';
    } else {
      return '${dateTime.year}年${dateTime.month}月${dateTime.day}日 $hh:$mm';
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

  Future<void> _prefetchFirstPageForTab(int index) async {
    if (!mounted) return;
    if (index < 0 || index >= _dayTabs.length) return;
    if ((_tabCache[index]?.isNotEmpty ?? false)) return;
    final day = _dayTabs[index];
    if (day.count <= 0) return;
    try {
      final batch = await ScreenshotService.instance.getGlobalScreenshotsBetween(
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
    } catch (_) {}
  }

  Future<void> _prefetchAllTabsFirst8() async {
    for (int i = 0; i < _dayTabs.length; i++) {
      await _prefetchFirstPageForTab(i);
    }
  }

  Widget _buildItem(ScreenshotRecord screenshot, int index) {
    final GlobalKey itemKey = _itemKeys.putIfAbsent(index, () => GlobalKey());
    final file = File(screenshot.filePath);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final baseImage = Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildErrorItem('图片丢失或损坏'),
    );
    final Widget image = ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: isDark
          ? ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.5),
                BlendMode.darken,
              ),
              child: baseImage,
            )
          : baseImage,
    );
    final bool nsfwMasked = _privacyMode && NsfwDetector.isNsfwUrl(screenshot.pageUrl);
    final content = GestureDetector(
      onTap: () {
        if (!nsfwMasked) {
          _viewFromCurrent(index);
        }
      },
      child: Stack(
      children: [
        image,
        // NSFW 遮罩（隐私模式）：与截图列表一致
        if (nsfwMasked)
          Positioned.fill(
            child: NsfwBackdropOverlay(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              onReveal: () => _viewFromCurrent(index),
              showButton: true,
            ),
          ),
        // 顶部链接信息遮罩：NSFW 时隐藏，避免露出网址
        // 链接条不受隐私开关影响，仅在非 NSFW 时展示
        if (!nsfwMasked && screenshot.pageUrl != null && screenshot.pageUrl!.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openLink(screenshot.pageUrl!),
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
                      Colors.black.withValues(alpha: 0.7),
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
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).textTheme.bodySmall?.color
                          : Colors.white,
                    ),
                    const SizedBox(width: AppTheme.spacing1),
                    Expanded(
                      child: Text(
                        screenshot.pageUrl!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Theme.of(context).textTheme.bodySmall?.color
                                  : Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
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
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppTheme.radiusSm),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildAppIcon(screenshot.appPackageName),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      _formatFileSize(screenshot.fileSize),
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
                  _formatTime(screenshot.captureTime),
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
      ],
    ));
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
    final app = _appInfoByPackage[shot.appPackageName] ??
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
    // 占位符（小圆形）
    final parts = packageName.split('.');
    final head = parts.isNotEmpty ? parts.last : packageName;
    final leading = head.isNotEmpty ? head[0].toUpperCase() : '?';
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
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

  Widget _buildErrorItem(String message) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      alignment: Alignment.center,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall,
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
