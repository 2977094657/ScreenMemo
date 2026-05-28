part of 'segment_status_page.dart';

// ========== 动态页状态辅助方法 ==========
extension _SegmentStatusStateHelpersPart on _SegmentStatusPageState {
  List<String> _orderedDayKeysFromSegments(
    List<Map<String, dynamic>> segments,
  ) {
    final Set<String> keys = <String>{};
    for (final Map<String, dynamic> seg in segments) {
      final int ms = (seg['start_time'] as int?) ?? 0;
      if (ms <= 0) continue;
      keys.add(_dateKeyFromMillis(ms));
    }
    final List<String> ordered = keys.toList()..sort((a, b) => b.compareTo(a));
    return ordered;
  }

  Map<String, List<Map<String, dynamic>>> _groupSegmentsByDay(
    List<Map<String, dynamic>> segments,
  ) {
    final Map<String, List<Map<String, dynamic>>> grouped =
        <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> seg in segments) {
      final int ms = (seg['start_time'] as int?) ?? 0;
      if (ms <= 0) continue;
      final String key = _dateKeyFromMillis(ms);
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(seg);
    }
    return grouped;
  }

  Map<String, int> _countSegmentsByDay(List<Map<String, dynamic>> segments) {
    final Map<String, int> counts = <String, int>{};
    for (final Map<String, dynamic> seg in segments) {
      final int ms = (seg['start_time'] as int?) ?? 0;
      if (ms <= 0) continue;
      final String key = _dateKeyFromMillis(ms);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  List<Map<String, dynamic>> _flattenSegmentsByDay(
    Map<String, List<Map<String, dynamic>>> segmentsByDay,
    List<String> orderedDayKeys,
  ) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final String key in orderedDayKeys) {
      out.addAll(segmentsByDay[key] ?? const <Map<String, dynamic>>[]);
    }
    return out;
  }

  bool _shouldGateTimelineToCurrentRebuild([DynamicRebuildTaskStatus? status]) {
    final DynamicRebuildTaskStatus effective =
        status ?? _dynamicRebuildTaskStatus;
    if (effective.taskId.isEmpty || effective.isIdle || effective.isCompleted) {
      return false;
    }
    return true;
  }

  String? _dynamicRebuildTimelineCutoffDayKey([
    DynamicRebuildTaskStatus? status,
  ]) {
    final DynamicRebuildTaskStatus effective =
        status ?? _dynamicRebuildTaskStatus;
    if (!_shouldGateTimelineToCurrentRebuild(effective)) return null;
    final String key = effective.timelineCutoffDayKey.trim().isNotEmpty
        ? effective.timelineCutoffDayKey.trim()
        : effective.currentDayKey.trim();
    return key.isEmpty ? '' : key;
  }

  bool _shouldHideTimelineUntilRebuildAdvances([
    DynamicRebuildTaskStatus? status,
  ]) {
    final String? cutoff = _dynamicRebuildTimelineCutoffDayKey(status);
    return cutoff != null && cutoff.isEmpty;
  }

  int? _endMillisForDateKey(String dateKey) {
    final List<String> parts = dateKey.split('-');
    if (parts.length != 3) return null;
    final int? year = int.tryParse(parts[0]);
    final int? month = int.tryParse(parts[1]);
    final int? day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(
          year,
          month,
          day,
        ).add(const Duration(days: 1)).millisecondsSinceEpoch -
        1;
  }

  String _dynamicRebuildTimelineVisibilityFingerprint([
    DynamicRebuildTaskStatus? status,
  ]) {
    final DynamicRebuildTaskStatus effective =
        status ?? _dynamicRebuildTaskStatus;
    final String? cutoff = _dynamicRebuildTimelineCutoffDayKey(effective);
    return '${_shouldGateTimelineToCurrentRebuild(effective)}|${cutoff ?? '(none)'}';
  }

  void _beginEntryPerfLoad(String step, {String? detail}) {
    if (!_trackEntryPerf) return;
    _entryPerfPendingLoads += 1;
    DynamicEntryPerfService.instance.mark('$step.start', detail: detail);
  }

  void _endEntryPerfLoad(String step, {String? detail}) {
    if (!_trackEntryPerf) return;
    if (_entryPerfPendingLoads > 0) {
      _entryPerfPendingLoads -= 1;
    }
    DynamicEntryPerfService.instance.mark('$step.done', detail: detail);
    _completeEntryPerfIfReady();
  }

  void _failEntryPerfLoad(String step, Object error, {String? detail}) {
    if (!_trackEntryPerf) return;
    if (_entryPerfPendingLoads > 0) {
      _entryPerfPendingLoads -= 1;
    }
    final String base = 'error=$error';
    final String resolvedDetail = (detail ?? '').trim();
    DynamicEntryPerfService.instance.mark(
      '$step.error',
      detail: resolvedDetail.isEmpty ? base : '$resolvedDetail | $base',
    );
    _completeEntryPerfIfReady();
  }

  void _completeEntryPerfIfReady() {
    if (!_trackEntryPerf) return;
    if (!_entryPerfShellFrameSeen || _entryPerfPendingLoads > 0) return;
    _trackEntryPerf = false;
    DynamicEntryPerfService.instance.finish(
      'segment.bootstrap.done',
      detail:
          'segments=${_segments.length} selectedDate=${_selectedDateKey ?? ''}',
    );
  }

  Future<void> _loadPrivacyMode() async {
    final Stopwatch sw = Stopwatch()..start();
    _beginEntryPerfLoad('segment.privacyMode');
    try {
      final enabled = await AppSelectionService.instance
          .getPrivacyModeEnabled();
      if (mounted) {
        _segmentStatusSetState(() {
          _privacyMode = enabled;
        });
      }
      _endEntryPerfLoad(
        'segment.privacyMode',
        detail: 'ms=${sw.elapsedMilliseconds} enabled=$enabled',
      );
    } catch (e) {
      _failEntryPerfLoad(
        'segment.privacyMode',
        e,
        detail: 'ms=${sw.elapsedMilliseconds}',
      );
    }
  }

  Future<void> _initApps() async {
    final Stopwatch sw = Stopwatch()..start();
    _beginEntryPerfLoad('segment.apps');
    try {
      final cachedApps = await AppSelectionService.instance
          .getCachedAppInfoByPackage();
      final apps = await AppSelectionService.instance.getAllInstalledApps();
      if (!mounted) return;
      _segmentStatusSetState(() {
        _appInfoByPackage.addAll(cachedApps);
        for (final a in apps) {
          _appInfoByPackage[a.packageName] = a;
        }
      });
      _endEntryPerfLoad(
        'segment.apps',
        detail: 'ms=${sw.elapsedMilliseconds} count=${apps.length}',
      );
    } catch (e) {
      _failEntryPerfLoad(
        'segment.apps',
        e,
        detail: 'ms=${sw.elapsedMilliseconds}',
      );
    }
  }

  Future<void> _refresh({bool triggerSegmentTick = true}) async {
    final Stopwatch sw = Stopwatch()..start();
    final int generation = ++_timelineLoadGeneration;
    _beginEntryPerfLoad(
      'segment.refresh',
      detail:
          'triggerTick=$triggerSegmentTick onlyNoSummary=$_onlyNoSummary selectedDate=${_selectedDateKey ?? ''}',
    );
    try {
      if (mounted) {
        _segmentStatusSetState(() {
          _loading = true;
          _loadingDayKeys = const <String>{};
        });
      }

      // 先触发一次原生端推进/补救：用于“删空某日后重建日期 Tab”等场景
      // ignore: unawaited_futures
      if (triggerSegmentTick && !_dynamicRebuildTaskStatus.isActive) {
        _db.triggerSegmentTick();
      }
      final Stopwatch activeSw = Stopwatch()..start();
      final active = await _db.getActiveSegment();
      DynamicEntryPerfService.instance.mark(
        'segment.refresh.active.done',
        detail:
            'ms=${activeSw.elapsedMilliseconds} hasActive=${active != null}',
      );
      final String? rebuildCutoffDayKey = _dynamicRebuildTimelineCutoffDayKey();
      final bool hideAllUntilCurrentDay =
          _shouldHideTimelineUntilRebuildAdvances();
      final int? rebuildCutoffEndMillis =
          rebuildCutoffDayKey == null || rebuildCutoffDayKey.isEmpty
          ? null
          : _endMillisForDateKey(rebuildCutoffDayKey);
      List<Map<String, dynamic>> segments = const <Map<String, dynamic>>[];
      Map<String, List<Map<String, dynamic>>> segmentsByDay =
          const <String, List<Map<String, dynamic>>>{};
      List<String> loadedDayKeys = const <String>[];
      Map<String, int> dayCountsByKey = const <String, int>{};
      String? selectedDateKey;
      bool hasMoreOlder = false;
      final Stopwatch timelineSw = Stopwatch()..start();

      if (hideAllUntilCurrentDay) {
        selectedDateKey = null;
      } else if (_onlyNoSummary) {
        // “仅看无总结”模式保持原有列表行为，只做字段截断降低 CursorWindow 风险。
        const int fetchLimit = 100;
        segments = await _db.listSegmentsEx(
          limit: fetchLimit,
          onlyNoSummary: true,
          endMillis: rebuildCutoffEndMillis,
          truncateResultColumns: true,
        );
        segmentsByDay = _groupSegmentsByDay(segments);
        loadedDayKeys = _orderedDayKeysFromSegments(segments);
        dayCountsByKey = _countSegmentsByDay(segments);
        selectedDateKey = loadedDayKeys.contains(_selectedDateKey)
            ? _selectedDateKey
            : (loadedDayKeys.isEmpty ? null : loadedDayKeys.first);
      } else {
        final String pinnedDateKey = (_selectedDateKey ?? '').trim();
        final SegmentTimelineDayBatch batch = await _db
            .listSegmentTimelineDayBatch(
              distinctDayCount: _SegmentStatusPageState._initialDayTabs,
              pinnedDateKey: pinnedDateKey.isEmpty ? null : pinnedDateKey,
              maxDateKeyInclusive: rebuildCutoffDayKey,
              requireSamples: true,
            );
        loadedDayKeys = batch.dayKeys;
        dayCountsByKey = batch.dayCountsByKey;
        hasMoreOlder = batch.hasMoreOlder;
        selectedDateKey = loadedDayKeys.contains(pinnedDateKey)
            ? pinnedDateKey
            : (loadedDayKeys.isEmpty ? null : loadedDayKeys.first);
        if (selectedDateKey != null) {
          segments = await _db.listSegmentTimelineDaySegments(
            dateKey: selectedDateKey,
            maxDateKeyInclusive: rebuildCutoffDayKey,
            requireSamples: true,
            truncateResultColumns: true,
          );
          segmentsByDay = <String, List<Map<String, dynamic>>>{
            selectedDateKey: segments,
          };
          dayCountsByKey = <String, int>{
            ...dayCountsByKey,
            selectedDateKey: segments.length,
          };
        }
      }
      DynamicEntryPerfService.instance.mark(
        'segment.refresh.timeline.done',
        detail:
            'ms=${timelineSw.elapsedMilliseconds} segments=${segments.length} dayKeys=${loadedDayKeys.length} loadedDay=${selectedDateKey ?? ''} hasMoreOlder=$hasMoreOlder hideAll=$hideAllUntilCurrentDay',
      );

      if (!mounted) return;
      if (generation != _timelineLoadGeneration) {
        _endEntryPerfLoad(
          'segment.refresh',
          detail: 'ms=${sw.elapsedMilliseconds} stale=true',
        );
        return;
      }
      _segmentStatusSetState(() {
        _active = active;
        _segments = segments;
        _segmentsByDay = segmentsByDay;
        _loadedDayKeys = loadedDayKeys;
        _dayCountsByKey = dayCountsByKey;
        _loadingDayKeys = const <String>{};
        _selectedDateKey = selectedDateKey;
        _maxVisibleDayTabs = loadedDayKeys.isEmpty
            ? _SegmentStatusPageState._initialDayTabs
            : loadedDayKeys.length;
        _noMoreOlderSegments = hideAllUntilCurrentDay || _onlyNoSummary
            ? true
            : !hasMoreOlder;
      });

      // 若处于“仅看无总结”，根据是否还有待补事件启动/停止自动检测
      if (_onlyNoSummary) {
        final hasPending = segments.any(
          (e) => (e['has_summary'] as int? ?? 0) == 0,
        );
        if (hasPending) {
          _maybeStartAutoWatch();
        } else {
          _stopAutoWatch();
        }
      }
      _endEntryPerfLoad(
        'segment.refresh',
        detail:
            'ms=${sw.elapsedMilliseconds} segments=${segments.length} dayKeys=${loadedDayKeys.length} loadedDay=${selectedDateKey ?? ''}',
      );
    } catch (e) {
      _failEntryPerfLoad(
        'segment.refresh',
        e,
        detail: 'ms=${sw.elapsedMilliseconds}',
      );
      // Keep previous state on error.
    } finally {
      if (mounted && generation == _timelineLoadGeneration) {
        _segmentStatusSetState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openSelectedDailySummary() async {
    final String? dateKey = _selectedDateKey;
    if (dateKey == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DailySummaryPage(dateKey: dateKey)),
    );
  }

  bool _segmentStatusCanPop(BuildContext context) {
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (route != null) return route.canPop;
    return Navigator.of(context).canPop();
  }

  double? _segmentStatusLeadingWidth(BuildContext context) {
    final bool canPop = _segmentStatusCanPop(context);
    final bool showDailySummary = _selectedDateKey != null;
    double width = 0;
    if (canPop) width += 52;
    if (showDailySummary) width += 52;
    if (showDailySummary && _dynamicEntryLogIconEnabled) width += 52;
    return width;
  }

  Color _segmentStatusActionIconColor(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return theme.appBarTheme.actionsIconTheme?.color ??
        theme.appBarTheme.iconTheme?.color ??
        IconTheme.of(context).color ??
        theme.colorScheme.onSurfaceVariant;
  }

  String _segmentEntryLogTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${three(t.millisecond)}';
  }

  ({String? tag, String message}) _splitTalkerTag(String? raw) {
    final String message = raw ?? '';
    if (!message.startsWith('[')) {
      return (tag: null, message: message);
    }
    final int end = message.indexOf(']');
    if (end <= 1) {
      return (tag: null, message: message);
    }
    final String tag = message.substring(1, end).trim();
    final String rest = message.substring(end + 1).trimLeft();
    return (tag: tag.isEmpty ? null : tag, message: rest);
  }

  int? _segmentEntrySessionId(TalkerData data) {
    final String message = _splitTalkerTag(data.message).message;
    final Match? match = RegExp(r'session#(\d+)').firstMatch(message);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  bool _isSegmentEntryPerfLog(TalkerData data) {
    final ({String? tag, String message}) parts = _splitTalkerTag(data.message);
    if (parts.tag != DynamicEntryPerfService.logTag) {
      return false;
    }
    return parts.message.contains('source=SegmentStatusPage') ||
        parts.message.contains('segment.');
  }

  List<TalkerData> _latestSegmentEntryPerfLogs() {
    final List<TalkerData> items = FlutterLogger.talker.history
        .where(_isSegmentEntryPerfLog)
        .toList(growable: false);
    if (items.isEmpty) {
      return const <TalkerData>[];
    }
    int? latestSessionId;
    for (final TalkerData item in items.reversed) {
      latestSessionId = _segmentEntrySessionId(item);
      if (latestSessionId != null) {
        break;
      }
    }
    if (latestSessionId == null) {
      return items;
    }
    final List<TalkerData> sessionItems = items
        .where(
          (TalkerData item) => _segmentEntrySessionId(item) == latestSessionId,
        )
        .toList(growable: false);
    return sessionItems.isEmpty ? items : sessionItems;
  }

  String _buildSegmentEntryPerfExportText(List<TalkerData> items) {
    final StringBuffer buffer = StringBuffer();
    for (final TalkerData item in items) {
      final ({String? tag, String message}) parts = _splitTalkerTag(
        item.message,
      );
      final String tagPrefix = parts.tag == null ? '' : '[${parts.tag}] ';
      buffer.writeln(
        '${_segmentEntryLogTime(item.time)} $tagPrefix${parts.message}',
      );
      final Object? error = item.exception ?? item.error;
      if (error != null) {
        buffer.writeln(error.toString());
      }
      if (item.stackTrace != null && item.stackTrace != StackTrace.empty) {
        buffer.writeln(item.stackTrace.toString());
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  Future<void> _openSegmentEntryPerfSheet() async {
    final List<TalkerData> items = _latestSegmentEntryPerfLogs();
    final int? sessionId = items.isEmpty
        ? null
        : _segmentEntrySessionId(items.last);
    final String text = _buildSegmentEntryPerfExportText(items);
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool hasLogs = text.trim().isNotEmpty;

    await AIRequestLogsSheet.show(
      context: context,
      title: '动态进入日志',
      metaText: sessionId == null
          ? '显示当前页可用的动态进入日志'
          : '仅显示最近一次进入会话 session#$sessionId，共 ${items.length} 条',
      hintText: AppLocalizations.of(context).segmentEntryLogHint,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            onPressed: !hasLogs
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (!mounted) return;
                    UINotifier.success(
                      context,
                      AppLocalizations.of(context).segmentEntryLogCopied,
                    );
                  },
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: Text(AppLocalizations.of(context).copyLogAction),
          ),
          const SizedBox(height: AppTheme.spacing3),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
            ),
            child: SelectableText(
              hasLogs ? text : '暂无动态进入日志，请先重新进入动态页再查看。',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentStatusLeading(BuildContext context) {
    final bool canPop = _segmentStatusCanPop(context);
    final bool showDailySummary = _selectedDateKey != null;
    final Color actionColor = _segmentStatusActionIconColor(context);
    if (!canPop && !showDailySummary) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canPop) BackButton(color: actionColor),
        if (showDailySummary)
          IconButton(
            style: IconButton.styleFrom(foregroundColor: actionColor),
            icon: const Icon(Icons.event_note_outlined),
            tooltip: AppLocalizations.of(context).viewOrGenerateForDay,
            onPressed: _openSelectedDailySummary,
          ),
        if (showDailySummary && _dynamicEntryLogIconEnabled)
          IconButton(
            style: IconButton.styleFrom(foregroundColor: actionColor),
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: '动态进入日志',
            onPressed: _openSegmentEntryPerfSheet,
          ),
      ],
    );
  }

  Future<void> _loadSegmentDayIfNeeded(String dateKey) async {
    final String normalized = dateKey.trim();
    if (normalized.isEmpty ||
        _onlyNoSummary ||
        _shouldHideTimelineUntilRebuildAdvances() ||
        _segmentsByDay.containsKey(normalized) ||
        _loadingDayKeys.contains(normalized)) {
      return;
    }
    final int generation = _timelineLoadGeneration;
    _segmentStatusSetState(() {
      _loadingDayKeys = <String>{..._loadingDayKeys, normalized};
    });
    final Stopwatch sw = Stopwatch()..start();
    try {
      final List<Map<String, dynamic>> segments = await _db
          .listSegmentTimelineDaySegments(
            dateKey: normalized,
            maxDateKeyInclusive: _dynamicRebuildTimelineCutoffDayKey(),
            requireSamples: true,
            truncateResultColumns: true,
          );
      DynamicEntryPerfService.instance.mark(
        'segment.dayLoad.done',
        detail:
            'ms=${sw.elapsedMilliseconds} day=$normalized segments=${segments.length}',
      );
      if (!mounted || generation != _timelineLoadGeneration) return;
      final Map<String, List<Map<String, dynamic>>> nextSegmentsByDay =
          <String, List<Map<String, dynamic>>>{
            ..._segmentsByDay,
            normalized: segments,
          };
      final Set<String> nextLoading = <String>{..._loadingDayKeys}
        ..remove(normalized);
      _segmentStatusSetState(() {
        _segmentsByDay = nextSegmentsByDay;
        _segments = _flattenSegmentsByDay(nextSegmentsByDay, _loadedDayKeys);
        _dayCountsByKey = <String, int>{
          ..._dayCountsByKey,
          normalized: segments.length,
        };
        _loadingDayKeys = nextLoading;
      });
    } catch (e) {
      DynamicEntryPerfService.instance.mark(
        'segment.dayLoad.error',
        detail:
            'ms=${sw.elapsedMilliseconds} day=$normalized error=${e.toString()}',
      );
      if (!mounted || generation != _timelineLoadGeneration) return;
      _segmentStatusSetState(() {
        _loadingDayKeys = <String>{..._loadingDayKeys}..remove(normalized);
      });
    }
  }

  Future<List<SegmentTimelineDayInfo>> _loadSegmentTimelineMonthDayCounts(
    int year,
    int month,
  ) async {
    return _db.listSegmentTimelineMonthDayCounts(
      year: year,
      month: month,
      maxDateKeyInclusive: _dynamicRebuildTimelineCutoffDayKey(),
      requireSamples: true,
    );
  }

  Future<List<int>> _loadSegmentTimelineYears() async {
    return _db.listSegmentTimelineYears(
      maxDateKeyInclusive: _dynamicRebuildTimelineCutoffDayKey(),
      requireSamples: true,
    );
  }

  Future<void> _jumpToSegmentTimelineDate(
    String dateKey,
    int knownCount,
  ) async {
    final String normalized = dateKey.trim();
    if (normalized.isEmpty ||
        _onlyNoSummary ||
        _shouldHideTimelineUntilRebuildAdvances()) {
      return;
    }
    final String? cutoff = _dynamicRebuildTimelineCutoffDayKey();
    if (cutoff != null &&
        cutoff.isNotEmpty &&
        normalized.compareTo(cutoff) > 0) {
      if (!mounted) return;
      UINotifier.info(
        context,
        AppLocalizations.of(
          context,
        ).segmentTimelineNotAvailableForDate(normalized),
      );
      return;
    }

    final int generation = ++_timelineLoadGeneration;
    final List<String> nextDayKeys = <String>{
      ..._loadedDayKeys,
      normalized,
    }.toList()..sort((String a, String b) => b.compareTo(a));
    _segmentStatusSetState(() {
      _selectedDateKey = normalized;
      _loadedDayKeys = nextDayKeys;
      _maxVisibleDayTabs = nextDayKeys.length;
      _dayCountsByKey = <String, int>{
        ..._dayCountsByKey,
        if (knownCount > 0) normalized: knownCount,
      };
      _loadingDayKeys = <String>{..._loadingDayKeys, normalized};
    });

    try {
      final List<Map<String, dynamic>> segments = await _db
          .listSegmentTimelineDaySegments(
            dateKey: normalized,
            maxDateKeyInclusive: cutoff,
            requireSamples: true,
            truncateResultColumns: true,
          );
      if (!mounted || generation != _timelineLoadGeneration) return;
      final Map<String, List<Map<String, dynamic>>> nextSegmentsByDay =
          <String, List<Map<String, dynamic>>>{
            ..._segmentsByDay,
            normalized: segments,
          };
      final Set<String> nextLoadingDayKeys = <String>{..._loadingDayKeys}
        ..remove(normalized);
      _segmentStatusSetState(() {
        _selectedDateKey = normalized;
        _segmentsByDay = nextSegmentsByDay;
        _segments = _flattenSegmentsByDay(nextSegmentsByDay, _loadedDayKeys);
        _dayCountsByKey = <String, int>{
          ..._dayCountsByKey,
          normalized: segments.isEmpty ? knownCount : segments.length,
        };
        _loadingDayKeys = nextLoadingDayKeys;
      });
    } catch (_) {
      if (!mounted || generation != _timelineLoadGeneration) return;
      _segmentStatusSetState(() {
        _loadingDayKeys = <String>{..._loadingDayKeys}..remove(normalized);
      });
      UINotifier.error(context, AppLocalizations.of(context).dateJumpFailed);
    }
  }

  void _handleActiveDateChanged(String? dateKey) {
    if (!mounted) return;
    final String normalized = (dateKey ?? '').trim();
    final String? nextDateKey = normalized.isEmpty ? null : normalized;
    if (_selectedDateKey != nextDateKey) {
      _segmentStatusSetState(() {
        _selectedDateKey = nextDateKey;
      });
    }
    if (nextDateKey != null) {
      unawaited(_loadSegmentDayIfNeeded(nextDateKey));
    }
  }

  Future<void> _loadOlderSegmentsFromDbIfNeeded() async {
    if (_onlyNoSummary ||
        _isLoadingMoreDays ||
        _noMoreOlderSegments ||
        _shouldHideTimelineUntilRebuildAdvances()) {
      return;
    }
    final List<String> currentDayKeys = _loadedDayKeys;
    final String beforeDateKey = currentDayKeys.isEmpty
        ? ''
        : currentDayKeys.last;
    if (beforeDateKey.isEmpty) {
      if (!_noMoreOlderSegments) {
        _segmentStatusSetState(() => _noMoreOlderSegments = true);
      }
      return;
    }

    _segmentStatusSetState(() => _isLoadingMoreDays = true);
    try {
      final SegmentTimelineDayBatch batch = await _db
          .listSegmentTimelineDayBatch(
            distinctDayCount: _SegmentStatusPageState._appendDayTabs,
            beforeDateKey: beforeDateKey,
            maxDateKeyInclusive: _dynamicRebuildTimelineCutoffDayKey(),
            requireSamples: true,
          );
      if (batch.days.isEmpty) {
        if (!_noMoreOlderSegments) {
          _segmentStatusSetState(() => _noMoreOlderSegments = true);
        }
        return;
      }

      final List<String> mergedDayKeys = <String>{
        ..._loadedDayKeys,
        ...batch.dayKeys,
      }.toList()..sort((a, b) => b.compareTo(a));
      final Map<String, int> mergedCounts = <String, int>{
        ..._dayCountsByKey,
        ...batch.dayCountsByKey,
      };

      _segmentStatusSetState(() {
        _loadedDayKeys = mergedDayKeys;
        _dayCountsByKey = mergedCounts;
        _maxVisibleDayTabs = mergedDayKeys.length;
        _noMoreOlderSegments = !batch.hasMoreOlder;
      });
    } finally {
      if (mounted) {
        _segmentStatusSetState(() => _isLoadingMoreDays = false);
      }
    }
  }

  Future<void> _handleLastDayTabReached() async {
    if (!mounted) return;
    await _loadOlderSegmentsFromDbIfNeeded();
  }

  String _fmtTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  Widget _buildActiveCard() {
    final a = _active;
    if (a == null) return const SizedBox.shrink();
    final start = (a['start_time'] as int?) ?? 0;
    final end = (a['end_time'] as int?) ?? 0;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    // Banner-style, smaller font, single-line; background matches page (avoid pure white).
    final String text =
        '${l10n.activeSegmentTitle}: ${_fmtTime(start)}-${_fmtTime(end)}';

    final TextStyle style = (theme.textTheme.bodySmall ?? const TextStyle())
        .copyWith(color: cs.onSurface, fontWeight: FontWeight.w600, height: 1);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacing1),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing2,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withOpacity(0.35), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.timelapse, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: AppTheme.spacing2),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStack() {
    return _buildActiveCard();
  }

  _DynamicRebuildUiSnapshot _currentDynamicRebuildUiSnapshot() {
    return _DynamicRebuildUiSnapshot(
      status: _dynamicRebuildTaskStatus,
      starting: _startingDynamicRebuild,
      stopping: _stoppingDynamicRebuild,
      selectedDayConcurrency: _selectedDynamicRebuildDayConcurrency,
      savingDayConcurrency: _savingDynamicRebuildDayConcurrency,
      autoRepairEnabled: _dynamicAutoRepairEnabled,
      autoRepairLoading: _loadingDynamicAutoRepair,
      autoRepairToggling: _togglingDynamicAutoRepair,
      requestLogs: _dynamicRebuildRequestLogsState,
    );
  }
}
