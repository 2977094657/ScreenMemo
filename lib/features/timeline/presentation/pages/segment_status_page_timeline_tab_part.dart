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

class _SegmentCalendarDaySelection {
  const _SegmentCalendarDaySelection({
    required this.dateKey,
    required this.count,
  });

  final String dateKey;
  final int count;
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
  final Future<List<int>> Function()? loadAvailableYears;
  final Future<List<SegmentTimelineDayInfo>> Function(int year, int month)?
  loadMonthDayCounts;
  final Future<void> Function(String dateKey, int count)? onDateJumpRequested;

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
    this.loadAvailableYears,
    this.loadMonthDayCounts,
    this.onDateJumpRequested,
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

  DateTime? _dateFromKey(String? dateKey) {
    final String normalized = (dateKey ?? '').trim();
    if (normalized.isEmpty) return null;
    final List<String> parts = normalized.split('-');
    if (parts.length != 3) return null;
    final int? year = int.tryParse(parts[0]);
    final int? month = int.tryParse(parts[1]);
    final int? day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    final DateTime date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  Future<void> _openSegmentCalendarSheet() async {
    final Future<List<SegmentTimelineDayInfo>> Function(int year, int month)?
    loadMonthDayCounts = widget.loadMonthDayCounts;
    final Future<void> Function(String dateKey, int count)?
    onDateJumpRequested = widget.onDateJumpRequested;
    if (loadMonthDayCounts == null || onDateJumpRequested == null) return;
    final DateTime initialDate =
        _dateFromKey(widget.selectedDateKey) ??
        (_orderedKeys.isEmpty ? null : _dateFromKey(_orderedKeys.first)) ??
        DateTime.now();
    final _SegmentCalendarDaySelection? selection =
        await showModalBottomSheet<_SegmentCalendarDaySelection>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (sheetContext) {
            final ColorScheme cs = Theme.of(sheetContext).colorScheme;
            return DraggableScrollableSheet(
              initialChildSize: 0.62,
              minChildSize: 0.42,
              maxChildSize: 0.88,
              expand: false,
              builder: (_, scrollController) {
                return ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppTheme.radiusLg),
                    topRight: Radius.circular(AppTheme.radiusLg),
                  ),
                  child: ColoredBox(
                    color: cs.surface,
                    child: SafeArea(
                      top: false,
                      child: _SegmentCalendarMonthSheet(
                        initialDate: initialDate,
                        selectedDateKey: widget.selectedDateKey,
                        scrollController: scrollController,
                        loadAvailableYears: widget.loadAvailableYears,
                        loadMonthDayCounts: loadMonthDayCounts,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
    if (selection == null || !mounted) return;
    await onDateJumpRequested(selection.dateKey, selection.count);
  }

  bool _shouldShowDateCalendarButton() {
    return widget.loadMonthDayCounts != null &&
        widget.onDateJumpRequested != null &&
        _orderedKeys.isNotEmpty &&
        !widget.onlyNoSummary;
  }

  Widget _buildDateCalendarButton(BuildContext context) {
    if (!_shouldShowDateCalendarButton()) return const SizedBox.shrink();
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: '打开日期日历',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openSegmentCalendarSheet,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Center(
              child: Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
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
                        // 与截图列表一致：左侧少量起始内边距，右侧交给独立按钮处理。
                        padding: const EdgeInsets.only(
                          left: AppTheme.spacing2,
                          right: AppTheme.spacing2,
                        ),
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
                                  if (sameDay(dt, now)) {
                                    return l10n.dayTabToday(c);
                                  }
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
                    if (_shouldShowDateCalendarButton())
                      Padding(
                        padding: const EdgeInsets.only(
                          left: AppTheme.spacing2,
                          right: AppTheme.spacing4,
                        ),
                        child: _buildDateCalendarButton(context),
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

class _SegmentCalendarMonthSheet extends StatefulWidget {
  const _SegmentCalendarMonthSheet({
    required this.initialDate,
    required this.selectedDateKey,
    required this.scrollController,
    required this.loadAvailableYears,
    required this.loadMonthDayCounts,
  });

  final DateTime initialDate;
  final String? selectedDateKey;
  final ScrollController scrollController;
  final Future<List<int>> Function()? loadAvailableYears;
  final Future<List<SegmentTimelineDayInfo>> Function(int year, int month)
  loadMonthDayCounts;

  @override
  State<_SegmentCalendarMonthSheet> createState() =>
      _SegmentCalendarMonthSheetState();
}

class _SegmentCalendarMonthSheetState
    extends State<_SegmentCalendarMonthSheet> {
  late int _year;
  late int _month;
  List<int> _yearOptions = const <int>[];
  Map<String, int> _countsByKey = const <String, int>{};
  bool _loading = false;
  bool _loadingYears = false;
  bool _loadedAvailableYears = false;
  String? _error;
  int _loadTicket = 0;
  int _yearLoadTicket = 0;

  @override
  void initState() {
    super.initState();
    _year = widget.initialDate.year;
    _month = widget.initialDate.month;
    _yearOptions = _normalizeYearOptions(<int>[_year]);
    unawaited(_loadAvailableYears());
    unawaited(_loadMonthCounts());
  }

  List<int> _normalizeYearOptions(Iterable<int> years) {
    final Set<int> values = <int>{
      for (final int year in years)
        if (year > 0) year,
      if (_year > 0) _year,
    };
    final List<int> sorted = values.toList();
    sorted.sort((int a, int b) => b.compareTo(a));
    return sorted;
  }

  List<int> _yearOptionsForCurrentValue() {
    if (_yearOptions.contains(_year)) return _yearOptions;
    return _normalizeYearOptions(<int>[..._yearOptions, _year]);
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  String _dateKeyForDay(int day) =>
      '${_year.toString().padLeft(4, '0')}-'
      '${_two(_month)}-${_two(day)}';

  Future<void> _loadAvailableYears() async {
    final Future<List<int>> Function()? loader = widget.loadAvailableYears;
    if (loader == null) return;
    final int ticket = ++_yearLoadTicket;
    setState(() => _loadingYears = true);
    try {
      final List<int> years = await loader();
      if (!mounted || ticket != _yearLoadTicket) return;
      setState(() {
        _yearOptions = _normalizeYearOptions(years);
        _loadingYears = false;
        _loadedAvailableYears = true;
      });
    } catch (_) {
      if (!mounted || ticket != _yearLoadTicket) return;
      setState(() => _loadingYears = false);
    }
  }

  Future<void> _loadMonthCounts() async {
    final int ticket = ++_loadTicket;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<SegmentTimelineDayInfo> days = await widget.loadMonthDayCounts(
        _year,
        _month,
      );
      if (!mounted || ticket != _loadTicket) return;
      setState(() {
        _countsByKey = <String, int>{
          for (final SegmentTimelineDayInfo info in days)
            info.dayKey: info.count,
        };
        _loading = false;
      });
    } catch (e) {
      if (!mounted || ticket != _loadTicket) return;
      setState(() {
        _countsByKey = const <String, int>{};
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _setYearMonth(int year, int month) {
    final DateTime normalized = DateTime(year, month);
    setState(() {
      _year = normalized.year;
      _month = normalized.month;
      _countsByKey = const <String, int>{};
    });
    unawaited(_loadMonthCounts());
  }

  bool _canChangeMonth(int delta) {
    if (!_loadedAvailableYears) return true;
    final DateTime normalized = DateTime(_year, _month + delta);
    return _yearOptions.contains(normalized.year);
  }

  void _changeMonth(int delta) {
    if (!_canChangeMonth(delta)) return;
    _setYearMonth(_year, _month + delta);
  }

  Widget _buildCalendarPickerButton({
    required String label,
    required int selectedValue,
    required List<UIActionMenuItem<int>> items,
    required ValueChanged<int> onSelected,
    required double minWidth,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return UIActionMenuButton<int>(
      tooltip: label,
      selectedValue: selectedValue,
      items: items,
      onSelected: onSelected,
      padding: EdgeInsets.zero,
      offset: const Offset(0, 6),
      minWidth: minWidth,
      maxWidth: math.max(minWidth, 180),
      child: Container(
        height: 34,
        constraints: BoxConstraints(minWidth: minWidth),
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing2),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacing3),
        Row(
          children: [
            Expanded(
              child: Text(
                '跳转日期',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (_loadingYears && !_loading) ...[
              const SizedBox(width: AppTheme.spacing2),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppTheme.spacing3),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing2,
            vertical: AppTheme.spacing1,
          ),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: '上个月',
                icon: const Icon(Icons.chevron_left),
                onPressed: _canChangeMonth(-1) ? () => _changeMonth(-1) : null,
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: _buildCalendarPickerButton(
                        label: '$_year 年',
                        selectedValue: _year,
                        minWidth: 104,
                        items: <UIActionMenuItem<int>>[
                          for (final int year in _yearOptionsForCurrentValue())
                            UIActionMenuItem<int>(
                              value: year,
                              label: '$year 年',
                            ),
                        ],
                        onSelected: (int value) {
                          if (value == _year) return;
                          _setYearMonth(value, _month);
                        },
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing2),
                    _buildCalendarPickerButton(
                      label: '$_month 月',
                      selectedValue: _month,
                      minWidth: 82,
                      items: <UIActionMenuItem<int>>[
                        for (int month = 1; month <= 12; month += 1)
                          UIActionMenuItem<int>(
                            value: month,
                            label: '$month 月',
                          ),
                      ],
                      onSelected: (int value) {
                        if (value == _month) return;
                        _setYearMonth(_year, value);
                      },
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '下个月',
                icon: const Icon(Icons.chevron_right),
                onPressed: _canChangeMonth(1) ? () => _changeMonth(1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeekHeader(BuildContext context) {
    final TextStyle? style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    const List<String> labels = <String>['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: [
        for (final String label in labels)
          Expanded(
            child: Center(child: Text(label, style: style)),
          ),
      ],
    );
  }

  Widget _buildCalendarGrid(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final int daysInMonth = DateTime(_year, _month + 1, 0).day;
    final int leadingEmptyCells = DateTime(_year, _month, 1).weekday - 1;
    final int rawCellCount = leadingEmptyCells + daysInMonth;
    final int cellCount = ((rawCellCount + 6) ~/ 7) * 7;
    final DateTime today = DateTime.now();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cellCount,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.88,
      ),
      itemBuilder: (context, index) {
        final int day = index - leadingEmptyCells + 1;
        if (day < 1 || day > daysInMonth) {
          return const SizedBox.shrink();
        }
        final String dateKey = _dateKeyForDay(day);
        final int count = _countsByKey[dateKey] ?? 0;
        final bool enabled = count > 0;
        final bool selected = widget.selectedDateKey == dateKey;
        final bool isToday =
            today.year == _year && today.month == _month && today.day == day;
        final Color accent = selected ? cs.primary : cs.onSurface;
        final Color background = selected
            ? cs.primaryContainer.withValues(alpha: 0.72)
            : enabled
            ? cs.surfaceContainerHighest.withValues(alpha: 0.36)
            : cs.surfaceContainerHighest.withValues(alpha: 0.16);
        final Color borderColor = selected
            ? cs.primary.withValues(alpha: 0.65)
            : isToday
            ? cs.tertiary.withValues(alpha: 0.5)
            : cs.outline.withValues(alpha: 0.12);
        return Material(
          key: ValueKey<String>('segment-calendar-day-$dateKey'),
          color: background,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled
                ? () {
                    Navigator.of(context).pop(
                      _SegmentCalendarDaySelection(
                        dateKey: dateKey,
                        count: count,
                      ),
                    );
                  }
                : null,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: borderColor),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$day',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: enabled
                          ? accent
                          : cs.onSurfaceVariant.withValues(alpha: 0.58),
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count 条',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: enabled
                          ? cs.onSurfaceVariant
                          : cs.onSurfaceVariant.withValues(alpha: 0.45),
                      fontWeight: enabled ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacing4,
        AppTheme.spacing3,
        AppTheme.spacing4,
        AppTheme.spacing4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: AppTheme.spacing3),
          Text(
            '只加载当前月份的动态数量，选择有动态的日期后会跳转到那一天。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (_error != null && _error!.trim().isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.spacing3),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onErrorContainer,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppTheme.spacing4),
          _buildWeekHeader(context),
          const SizedBox(height: AppTheme.spacing2),
          _buildCalendarGrid(context),
        ],
      ),
    );
  }
}
