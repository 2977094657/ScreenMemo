part of 'segment_status_page.dart';

// ========== 日期 Tab 与时间线 ==========
/// 将毫秒时间戳转换为日期 key（YYYY-MM-DD）
String _dateKeyFromMillis(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final String y = dt.year.toString().padLeft(4, '0');
  final String m = dt.month.toString().padLeft(2, '0');
  final String d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

// ============= 按日期 Tab 的段落时间轴视图（含分割线/关键动作/Logo/标签/摘要/可展开图片） =============
class _SegmentTimelineTabView extends StatefulWidget {
  final List<Map<String, dynamic>> segments;
  final List<String> dayKeys;
  final Map<String, int> dayCountsByKey;
  final Map<String, List<Map<String, dynamic>>> segmentsByDay;
  final Set<String> loadingDayKeys;
  final bool onlyNoSummary;
  final bool autoWatching;
  final Map<String, AppInfo> appInfoByPackage;
  final String Function(int) fmtTime;
  final Future<List<Map<String, dynamic>>> Function(int) loadSamples;
  final Future<Map<String, dynamic>?> Function(int) loadResult;
  final void Function(Map<String, dynamic>) onOpenDetail;
  final Future<void> Function(List<Map<String, dynamic>>, int) openGallery;
  final Widget activeHeader;
  final bool hasActiveHeader;
  final Future<void> Function() onRefreshRequested;
  final bool privacyMode;
  final bool dynamicRebuildActive;
  final int maxVisibleDayTabs;
  final String? selectedDateKey;
  final bool isTimelineLoading;
  final bool isLoadingMoreDays;
  final bool noMoreOlderSegments;
  final Future<void> Function()? onLastDayTabReached;
  final ValueChanged<String?>? onActiveDateChanged;

  const _SegmentTimelineTabView({
    required this.segments,
    required this.dayKeys,
    required this.dayCountsByKey,
    required this.segmentsByDay,
    required this.loadingDayKeys,
    required this.onlyNoSummary,
    required this.autoWatching,
    required this.appInfoByPackage,
    required this.fmtTime,
    required this.loadSamples,
    required this.loadResult,
    required this.onOpenDetail,
    required this.openGallery,
    required this.activeHeader,
    required this.hasActiveHeader,
    required this.onRefreshRequested,
    required this.privacyMode,
    required this.dynamicRebuildActive,
    required this.maxVisibleDayTabs,
    this.selectedDateKey,
    required this.isTimelineLoading,
    required this.isLoadingMoreDays,
    required this.noMoreOlderSegments,
    this.onLastDayTabReached,
    this.onActiveDateChanged,
  });

  @override
  State<_SegmentTimelineTabView> createState() =>
      _SegmentTimelineTabViewState();
}

class _SegmentTimelineTabViewState extends State<_SegmentTimelineTabView>
    with SingleTickerProviderStateMixin {
  static const int _autoLoadThreshold = 3;

  TabController? _tabController;
  List<String> _orderedKeys = const <String>[];
  String? _lastReportedDateKey;
  String? _lastAutoLoadTriggerKey;
  bool _autoLoadCheckQueued = false;

  void _handleTabSelectionChanged() {
    if (!mounted) return;
    _reportActiveDateKey();
    _queueAutoLoadCheck();
  }

  int _desiredTabIndex(List<String> ordered, int fallbackIndex) {
    if (ordered.isEmpty) return 0;
    final String selectedDateKey = (widget.selectedDateKey ?? '').trim();
    if (selectedDateKey.isNotEmpty) {
      final int selectedIndex = ordered.indexOf(selectedDateKey);
      if (selectedIndex >= 0) return selectedIndex;
      return 0;
    }
    return fallbackIndex.clamp(0, ordered.length - 1);
  }

  void _queueAutoLoadCheck() {
    if (_autoLoadCheckQueued) return;
    _autoLoadCheckQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoLoadCheckQueued = false;
      if (!mounted) return;
      _maybeAutoLoadOlderDays();
    });
  }

  void _maybeAutoLoadOlderDays() {
    if (widget.onlyNoSummary ||
        widget.onLastDayTabReached == null ||
        widget.isLoadingMoreDays ||
        widget.noMoreOlderSegments) {
      return;
    }
    final TabController? controller = _tabController;
    if (controller == null || _orderedKeys.isEmpty) return;
    final int remainingTabs = _orderedKeys.length - 1 - controller.index;
    if (remainingTabs >= _autoLoadThreshold) return;
    final String triggerKey = _orderedKeys.last;
    if (_lastAutoLoadTriggerKey == triggerKey) return;
    _lastAutoLoadTriggerKey = triggerKey;
    unawaited(widget.onLastDayTabReached!.call());
  }

  void _reportActiveDateKey() {
    final TabController? controller = _tabController;
    String? nextDateKey;
    if (controller != null &&
        _orderedKeys.isNotEmpty &&
        controller.index >= 0 &&
        controller.index < _orderedKeys.length) {
      nextDateKey = _orderedKeys[controller.index];
    }
    if (_lastReportedDateKey == nextDateKey) return;
    _lastReportedDateKey = nextDateKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onActiveDateChanged?.call(nextDateKey);
    });
  }

  Widget _buildDaySegmentList(
    String dateKey,
    List<Map<String, dynamic>> daySegments,
    bool isLoaded,
    bool isLoading,
  ) {
    if (daySegments.isEmpty && (!isLoaded || isLoading)) {
      return ListView(
        key: PageStorageKey<String>('segment-day-loading-$dateKey'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing4,
          vertical: AppTheme.spacing1,
        ),
        children: const [
          SizedBox(height: 180),
          Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          SizedBox(height: 12),
        ],
      );
    }

    return ListView.builder(
      key: PageStorageKey<String>('segment-day-$dateKey'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing1,
      ),
      itemCount: daySegments.length + 1,
      itemBuilder: (context, index) {
        if (index >= daySegments.length) {
          return const SizedBox(height: 12);
        }
        final Map<String, dynamic> segment = daySegments[index];
        return _SegmentEntryCard(
          key: ValueKey<int>((segment['id'] as int?) ?? index),
          segment: segment,
          isLast: index == daySegments.length - 1,
          fmtTime: widget.fmtTime,
          loadSamples: widget.loadSamples,
          loadResult: widget.loadResult,
          appInfoByPackage: widget.appInfoByPackage,
          onOpenDetail: () => widget.onOpenDetail(segment),
          openGallery: widget.openGallery,
          onRefreshRequested: widget.onRefreshRequested,
          privacyMode: widget.privacyMode,
          dynamicRebuildActive: widget.dynamicRebuildActive,
        );
      },
    );
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabSelectionChanged);
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> segments = widget.segments;
    final bool useLazyDayTabs =
        !widget.onlyNoSummary && widget.dayKeys.isNotEmpty;

    if (segments.isEmpty && !useLazyDayTabs) {
      _orderedKeys = const <String>[];
      _reportActiveDateKey();
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing4,
              vertical: AppTheme.spacing1,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  if (widget.hasActiveHeader) widget.activeHeader,
                  if (widget.hasActiveHeader &&
                      widget.onlyNoSummary &&
                      widget.autoWatching)
                    const SizedBox(height: 8),
                  if (widget.onlyNoSummary && widget.autoWatching)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        AppLocalizations.of(context).autoWatchingHint,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: widget.isTimelineLoading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing6,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_note_outlined,
                            size: 64,
                            color: AppTheme.mutedForeground.withOpacity(0.5),
                          ),
                          const SizedBox(height: AppTheme.spacing4),
                          Text(
                            AppLocalizations.of(context).noEvents,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.mutedForeground,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppTheme.spacing2),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: Text(
                              AppLocalizations.of(context).noEventsSubtitle,
                              style: const TextStyle(
                                color: AppTheme.mutedForeground,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      );
    }

    final Map<String, List<Map<String, dynamic>>> grouped = useLazyDayTabs
        ? widget.segmentsByDay
        : <String, List<Map<String, dynamic>>>{};
    if (!useLazyDayTabs) {
      for (final seg in segments) {
        final k = _dateKeyFromMillis((seg['start_time'] as int?) ?? 0);
        grouped.putIfAbsent(k, () => <Map<String, dynamic>>[]).add(seg);
      }
    }
    final List<String> orderedAll = useLazyDayTabs
        ? widget.dayKeys
        : (grouped.keys.toList()..sort((a, b) => b.compareTo(a)));

    // 仅展示当前已加载批次中的日期；默认模式下 maxVisibleDayTabs 会与已加载日期数保持一致。
    final int desiredTabs = widget.maxVisibleDayTabs <= 0
        ? 1
        : widget.maxVisibleDayTabs;
    final int visibleCount = math.min(desiredTabs, orderedAll.length);
    final List<String> ordered = orderedAll.take(visibleCount).toList();
    final List<String> previousOrderedKeys = _orderedKeys;
    final TabController? oldController = _tabController;
    final int oldIndex = oldController?.index ?? 0;
    final String? currentDateKey =
        oldController != null &&
            previousOrderedKeys.isNotEmpty &&
            oldIndex >= 0 &&
            oldIndex < previousOrderedKeys.length
        ? previousOrderedKeys[oldIndex]
        : null;
    _orderedKeys = ordered;

    int fallbackIndex = 0;
    if (ordered.isNotEmpty) {
      if (currentDateKey != null) {
        final int currentKeyIndex = ordered.indexOf(currentDateKey);
        fallbackIndex = currentKeyIndex >= 0
            ? currentKeyIndex
            : oldIndex.clamp(0, ordered.length - 1);
      } else {
        fallbackIndex = oldIndex.clamp(0, ordered.length - 1);
      }
    }
    final int desiredIndex = _desiredTabIndex(ordered, fallbackIndex);
    final bool shouldRecreateController =
        _tabController == null ||
        _tabController!.length != ordered.length ||
        _tabController!.index != desiredIndex;
    if (shouldRecreateController) {
      _tabController?.removeListener(_handleTabSelectionChanged);
      _tabController?.dispose();
      _tabController = TabController(
        length: ordered.length,
        vsync: this,
        initialIndex: desiredIndex,
      );
      _tabController!.addListener(_handleTabSelectionChanged);
    }
    _reportActiveDateKey();
    _queueAutoLoadCheck();

    return Column(
      children: [
        if (widget.hasActiveHeader) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacing4,
              AppTheme.spacing1,
              AppTheme.spacing4,
              0,
            ),
            child: widget.activeHeader,
          ),
          const SizedBox(height: 8),
        ],
        Builder(
          builder: (context) {
            final bool showLoadMoreButton =
                !widget.onlyNoSummary &&
                widget.onLastDayTabReached != null &&
                !widget.noMoreOlderSegments;
            final bool isLoadingMore = widget.isLoadingMoreDays;
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
                        padding: const EdgeInsets.only(left: AppTheme.spacing2),
                        // 与截图列表一致：标签水平留白适中
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        indicatorInsets: const EdgeInsets.symmetric(
                          horizontal: 4.0,
                        ),
                        tabs: [
                          for (final k in ordered)
                            Tab(
                              text: (() {
                                final parts = k.split('-');
                                if (parts.length == 3) {
                                  final y = int.tryParse(parts[0]) ?? 1970;
                                  final m = int.tryParse(parts[1]) ?? 1;
                                  final d = int.tryParse(parts[2]) ?? 1;
                                  final dt = DateTime(y, m, d);
                                  final now = DateTime.now();
                                  bool sameDay(DateTime a, DateTime b) =>
                                      a.year == b.year &&
                                      a.month == b.month &&
                                      a.day == b.day;
                                  final int c =
                                      widget.dayCountsByKey[k] ??
                                      (grouped[k] ??
                                              const <Map<String, dynamic>>[])
                                          .length;
                                  final l10n = AppLocalizations.of(context);
                                  if (sameDay(dt, now))
                                    return l10n.dayTabToday(c);
                                  if (sameDay(
                                    dt,
                                    now.subtract(const Duration(days: 1)),
                                  )) {
                                    return l10n.dayTabYesterday(c);
                                  }
                                  return l10n.dayTabMonthDayCount(
                                    dt.month,
                                    dt.day,
                                    c,
                                  );
                                }
                                return '$k ${widget.dayCountsByKey[k] ?? (grouped[k] ?? const <Map<String, dynamic>>[]).length}';
                              })(),
                            ),
                        ],
                      ),
                    ),
                    if (showLoadMoreButton)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: isLoadingMore
                            ? const Padding(
                                padding: EdgeInsets.only(
                                  left: AppTheme.spacing2,
                                  right: AppTheme.spacing1,
                                ),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final k in ordered)
                _buildDaySegmentList(
                  k,
                  grouped[k] ?? const <Map<String, dynamic>>[],
                  !useLazyDayTabs || widget.segmentsByDay.containsKey(k),
                  widget.loadingDayKeys.contains(k),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
