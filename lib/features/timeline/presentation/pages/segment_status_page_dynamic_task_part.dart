part of 'segment_status_page.dart';

// ========== 动态重建任务控制 ==========
enum _DynamicTaskScope { selectedDay, allDays }

class _DynamicTaskConfirmCopy {
  const _DynamicTaskConfirmCopy({
    required this.title,
    required this.message,
    required this.confirmText,
  });

  final String title;
  final String message;
  final String confirmText;
}

extension _SegmentStatusDynamicTaskPart on _SegmentStatusPageState {
  Future<void> _loadDynamicRebuildDayConcurrency() async {
    try {
      final int raw = await UserSettingsService.instance.getInt(
        UserSettingKeys.dynamicRebuildDayConcurrency,
        defaultValue: 1,
      );
      if (!mounted) return;
      final int normalized = math.max(1, math.min(10, raw));
      _segmentStatusSetState(
        () => _selectedDynamicRebuildDayConcurrency = normalized,
      );
      _publishDynamicRebuildUiSnapshot();
    } catch (_) {}
  }

  bool _canEditDynamicRebuildDayConcurrency(
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    return !snapshot.status.isActive &&
        !snapshot.starting &&
        !snapshot.stopping &&
        !snapshot.savingDayConcurrency;
  }

  int _effectiveDynamicRebuildDayConcurrency(
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final int preferred = snapshot.status.isActive
        ? (snapshot.status.dayConcurrency > 0
              ? snapshot.status.dayConcurrency
              : snapshot.selectedDayConcurrency)
        : snapshot.selectedDayConcurrency;
    return math.max(1, math.min(10, preferred));
  }

  Future<void> _setDynamicRebuildDayConcurrency(int value) async {
    final _DynamicRebuildUiSnapshot snapshot =
        _currentDynamicRebuildUiSnapshot();
    if (!_canEditDynamicRebuildDayConcurrency(snapshot)) return;
    final int normalized = math.max(1, math.min(10, value));
    if (normalized == _selectedDynamicRebuildDayConcurrency) return;
    final int previous = _selectedDynamicRebuildDayConcurrency;
    _segmentStatusSetState(() {
      _selectedDynamicRebuildDayConcurrency = normalized;
      _savingDynamicRebuildDayConcurrency = true;
    });
    _publishDynamicRebuildUiSnapshot();
    try {
      await UserSettingsService.instance.setInt(
        UserSettingKeys.dynamicRebuildDayConcurrency,
        normalized,
      );
    } catch (_) {
      if (!mounted) return;
      _segmentStatusSetState(
        () => _selectedDynamicRebuildDayConcurrency = previous,
      );
      UINotifier.error(
        context,
        AppLocalizations.of(context).segmentDynamicConcurrencySaveFailed,
      );
    } finally {
      if (mounted) {
        _segmentStatusSetState(
          () => _savingDynamicRebuildDayConcurrency = false,
        );
        _publishDynamicRebuildUiSnapshot();
      }
    }
  }

  Future<void> _changeDynamicRebuildDayConcurrency(int delta) async {
    await _setDynamicRebuildDayConcurrency(
      _selectedDynamicRebuildDayConcurrency + delta,
    );
  }

  void _publishDynamicRebuildUiSnapshot() {
    _dynamicRebuildUiSnapshotNotifier.value =
        _currentDynamicRebuildUiSnapshot();
    _syncDynamicRebuildIconAnimation();
  }

  void _syncDynamicRebuildIconAnimation() {
    final bool shouldSpin =
        _startingDynamicRebuild ||
        _stoppingDynamicRebuild ||
        _dynamicRebuildTaskStatus.isActive;
    if (shouldSpin) {
      if (!_dynamicRebuildIconController.isAnimating) {
        _dynamicRebuildIconController.repeat();
      }
      return;
    }
    if (_dynamicRebuildIconController.isAnimating) {
      _dynamicRebuildIconController.stop();
    }
    _dynamicRebuildIconController.value = 0;
  }

  Future<void> _refreshDynamicAutoRepairEnabled({
    bool showLoading = false,
  }) async {
    if (_loadingDynamicAutoRepair) return;
    final Stopwatch sw = Stopwatch()..start();
    _beginEntryPerfLoad(
      'segment.autoRepair',
      detail: 'showLoading=$showLoading',
    );
    if (showLoading && mounted) {
      _segmentStatusSetState(() => _loadingDynamicAutoRepair = true);
      _publishDynamicRebuildUiSnapshot();
    }
    try {
      final bool enabled = await _db.getDynamicAutoRepairEnabled();
      if (!mounted) return;
      _segmentStatusSetState(() {
        _dynamicAutoRepairEnabled = enabled;
        _loadingDynamicAutoRepair = false;
      });
      _publishDynamicRebuildUiSnapshot();
      _endEntryPerfLoad(
        'segment.autoRepair',
        detail: 'ms=${sw.elapsedMilliseconds} enabled=$enabled',
      );
    } catch (e) {
      _failEntryPerfLoad(
        'segment.autoRepair',
        e,
        detail: 'ms=${sw.elapsedMilliseconds}',
      );
      if (!mounted || !_loadingDynamicAutoRepair) return;
      _segmentStatusSetState(() => _loadingDynamicAutoRepair = false);
      _publishDynamicRebuildUiSnapshot();
    }
  }

  Future<void> _setDynamicAutoRepairEnabled(bool enabled) async {
    if (_loadingDynamicAutoRepair || _togglingDynamicAutoRepair) return;
    final bool previous = _dynamicAutoRepairEnabled;
    _segmentStatusSetState(() {
      _togglingDynamicAutoRepair = true;
      _dynamicAutoRepairEnabled = enabled;
    });
    _publishDynamicRebuildUiSnapshot();
    try {
      final bool persisted = await _db.setDynamicAutoRepairEnabled(enabled);
      if (!mounted) return;
      _segmentStatusSetState(() => _dynamicAutoRepairEnabled = persisted);
      _publishDynamicRebuildUiSnapshot();
      UINotifier.info(
        context,
        persisted
            ? AppLocalizations.of(context).dynamicAutoRepairEnabled
            : AppLocalizations.of(context).dynamicAutoRepairPaused,
      );
    } catch (_) {
      if (!mounted) return;
      _segmentStatusSetState(() => _dynamicAutoRepairEnabled = previous);
      _publishDynamicRebuildUiSnapshot();
      UINotifier.error(
        context,
        AppLocalizations.of(context).dynamicAutoRepairToggleFailed,
      );
    } finally {
      if (mounted) {
        _segmentStatusSetState(() => _togglingDynamicAutoRepair = false);
        _publishDynamicRebuildUiSnapshot();
      }
    }
  }

  Future<void> _openDynamicRebuildTaskSheet() async {
    try {
      await Future.wait<void>([
        _refreshDynamicRebuildTaskStatus(refreshSegmentsOnChange: false),
        _refreshDynamicAutoRepairEnabled(showLoading: true),
      ]);
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ValueListenableBuilder<_DynamicRebuildUiSnapshot>(
          valueListenable: _dynamicRebuildUiSnapshotNotifier,
          builder: (sheetCtx, snapshot, _) {
            final cs = Theme.of(sheetCtx).colorScheme;
            return DraggableScrollableSheet(
              initialChildSize: 0.62,
              minChildSize: 0.32,
              maxChildSize: 0.90,
              expand: false,
              builder: (_, scrollCtrl) {
                return ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppTheme.radiusLg),
                    topRight: Radius.circular(AppTheme.radiusLg),
                  ),
                  child: ColoredBox(
                    color: cs.surface,
                    child: SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.spacing4,
                          AppTheme.spacing3,
                          AppTheme.spacing4,
                          AppTheme.spacing4,
                        ),
                        child: _buildDynamicRebuildTaskSheetBody(
                          sheetCtx,
                          snapshot,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  int _dynamicRebuildCurrentOrdinal(DynamicRebuildTaskStatus status) {
    if (status.totalSegments <= 0) return 0;
    if (status.isCompleted) return status.totalSegments;
    final int next = status.processedSegments + 1;
    return math.min(status.totalSegments, math.max(1, next));
  }

  String _dynamicRebuildCurrentLine(DynamicRebuildTaskStatus status) {
    final List<String> activeDays =
        status.workers
            .where(
              (DynamicRebuildWorkerState worker) =>
                  worker.isRunning || worker.isRetrying,
            )
            .map((DynamicRebuildWorkerState worker) => worker.dayKey.trim())
            .where((String dayKey) => dayKey.isNotEmpty)
            .toSet()
            .toList()
          ..sort((String a, String b) => b.compareTo(a));
    if (activeDays.isNotEmpty) {
      return '当前活跃日期：${activeDays.join(' / ')}';
    }
    final String scope = [
      if (status.currentDayKey.isNotEmpty) status.currentDayKey,
      if (status.currentRangeLabel.isNotEmpty) status.currentRangeLabel,
    ].join(' · ');
    if (scope.isNotEmpty) {
      final String prefix = status.isActive
          ? (status.isBackfillMode ? '当前正在补全' : '当前正在重建')
          : '当前停留在';
      return '$prefix：$scope';
    }
    if (status.timelineCutoffDayKey.trim().isNotEmpty) {
      return '时间线当前可见到：${status.timelineCutoffDayKey.trim()}';
    }
    if (status.totalSegments <= 0) return '';
    final int currentOrdinal = _dynamicRebuildCurrentOrdinal(status);
    if (currentOrdinal <= 0) return '';
    return '当前进度停留在第 $currentOrdinal/${status.totalSegments} 条动态';
  }

  String _dynamicRebuildStageHeadline(DynamicRebuildTaskStatus status) {
    final String label = status.currentStageLabel.trim();
    final String detail = status.currentStageDetail.trim();
    if (label.isEmpty && detail.isEmpty) return '';
    if (label.isEmpty) return '当前环节：$detail';
    if (detail.isEmpty) return '当前环节：$label';
    return '当前环节：$label\n$detail';
  }

  String _dynamicRebuildModelLine(DynamicRebuildTaskStatus status) {
    final String model = status.aiModel.trim();
    if (model.isEmpty) return '';
    return '当前模型：$model';
  }

  String _dynamicRebuildWorkerStatusLine(DynamicRebuildWorkerState? worker) {
    if (worker == null) return '等待分配';
    if (worker.isRetrying) {
      final int retryLimit = worker.retryLimit > 0 ? worker.retryLimit : 3;
      final int retryCount = worker.retryCount > 0 ? worker.retryCount : 1;
      return '重试 $retryCount/$retryLimit';
    }
    if (worker.dayKey.trim().isNotEmpty) return worker.dayKey.trim();
    if (worker.isFailedWaiting) return '等待手动继续';
    if (worker.isCompleted) return '当天完成';
    return '等待分配';
  }

  String _dynamicRebuildWorkerChipLabel(DynamicRebuildWorkerState? worker) {
    if (worker == null || worker.isIdle) return '空闲';
    if (worker.isRetrying) return '重试中';
    if (worker.isRunning) return '运行中';
    if (worker.isCompleted) return '已完成';
    if (worker.isFailedWaiting) return '待继续';
    return worker.status;
  }

  Color _dynamicRebuildWorkerColor(
    BuildContext context,
    DynamicRebuildWorkerState? worker,
  ) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (worker == null || worker.isIdle) return cs.outline;
    if (worker.isRunning) return cs.tertiary;
    if (worker.isRetrying) return cs.secondary;
    if (worker.isCompleted) return cs.primary;
    if (worker.isFailedWaiting) return cs.error;
    return cs.onSurfaceVariant;
  }

  Widget _buildDynamicRebuildStageLogsSection(
    BuildContext context,
    DynamicRebuildTaskStatus status,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<String> logs = status.recentLogs;
    if (logs.isEmpty) return const SizedBox.shrink();
    final int start = math.max(0, logs.length - 12);
    final List<String> visible = logs.sublist(start);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '阶段日志',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          for (final String line in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _dynamicRebuildSerialHint(DynamicRebuildTaskStatus status) {
    if (status.isPreparing || status.isPending || status.isRunning) {
      return status.isBackfillMode
          ? '按天并发补全中：线程会先串行补完当天缺失动态，再领取下一个未完成日期。'
          : '按天并发重建中：线程会先串行跑完当天全部动态，再领取下一个未完成日期。';
    }
    if (status.canContinue || status.isCompletedWithFailures) {
      return status.isBackfillMode
          ? '继续补全只会续跑未完成或失败待续的日期，不会清空已有动态。'
          : '继续重建只会续跑未完成或失败待续的日期，不会重新清空已完成结果。';
    }
    return '';
  }

  String _dynamicRebuildTaskLabel(DynamicRebuildTaskStatus status) {
    if (status.isIdle) return '未启动';
    if (status.isPreparing) return '准备中';
    if (status.isPending || status.isRunning) return '运行中';
    if (status.isCompleted) return '已完成';
    if (status.isCompletedWithFailures) return '部分完成';
    if (status.isFailed) return '失败';
    if (status.isCancelled) return '已停止';
    return status.status;
  }

  Color _dynamicRebuildTaskColor(DynamicRebuildTaskStatus status) {
    final cs = Theme.of(context).colorScheme;
    if (status.isBackfillMode &&
        (status.isCompleted ||
            status.isPreparing ||
            status.isPending ||
            status.isRunning)) {
      return const Color(0xFF005B43);
    }
    if (status.isCompleted) return cs.primary;
    if (status.isCompletedWithFailures) return cs.secondary;
    if (status.isPreparing || status.isPending || status.isRunning) {
      return cs.tertiary;
    }
    if (status.isFailed) return cs.error;
    if (status.isCancelled) return cs.onSurfaceVariant;
    return cs.onSurfaceVariant;
  }

  String _fmtTaskDateTime(int millis) {
    if (millis <= 0) return '(null)';
    return DateTime.fromMillisecondsSinceEpoch(millis).toString();
  }

  void _maybeStartAutoWatch() {
    if (!_onlyNoSummary || _autoWatching) return;
    _autoWatching = true;
    // 先触发一次原生扫描，确保后续能尽快进入工作状态
    () async {
      try {
        await _db.triggerSegmentTick();
      } catch (_) {}
    }();
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 1), (_) => _autoPoll());
  }

  void _stopAutoWatch() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _autoWatching = false;
  }

  Future<void> _autoPoll() async {
    if (!_onlyNoSummary || !mounted) {
      _stopAutoWatch();
      return;
    }
    if (_loading) return;
    try {
      // 每次只做轻量查询；原生端 1s 心跳已持续推进/补救
      final String? rebuildCutoffDayKey = _dynamicRebuildTimelineCutoffDayKey();
      final List<Map<String, dynamic>> segments =
          _shouldHideTimelineUntilRebuildAdvances()
          ? const <Map<String, dynamic>>[]
          : await _db.listSegmentsEx(
              limit: 50,
              onlyNoSummary: true,
              endMillis:
                  rebuildCutoffDayKey == null || rebuildCutoffDayKey.isEmpty
                  ? null
                  : _endMillisForDateKey(rebuildCutoffDayKey),
              truncateResultColumns: true,
            );
      if (!mounted) return;
      final List<String> loadedDayKeys = _orderedDayKeysFromSegments(segments);
      _segmentStatusSetState(() {
        _segments = segments;
        _segmentsByDay = _groupSegmentsByDay(segments);
        _loadedDayKeys = loadedDayKeys;
        _dayCountsByKey = _countSegmentsByDay(segments);
        _loadingDayKeys = const <String>{};
        _maxVisibleDayTabs = loadedDayKeys.isEmpty
            ? _SegmentStatusPageState._initialDayTabs
            : loadedDayKeys.length;
        _noMoreOlderSegments = true;
      });
      // 若已无“暂无总结”，停止自动检测
      final hasPending = segments.any(
        (e) => (e['has_summary'] as int? ?? 0) == 0,
      );
      if (!hasPending) _stopAutoWatch();
    } catch (_) {}
  }

  void _startDynamicRebuildTaskPolling() {
    _dynamicRebuildTaskPollTimer?.cancel();
    _dynamicRebuildTaskPollTimer = Timer.periodic(const Duration(seconds: 2), (
      _,
    ) {
      // ignore: discarded_futures
      _refreshDynamicRebuildTaskStatus();
    });
  }

  Future<void> _refreshDynamicRebuildTaskStatus({
    bool refreshSegmentsOnChange = true,
  }) async {
    if (_pollingDynamicRebuildTask) return;
    final Stopwatch sw = Stopwatch()..start();
    _beginEntryPerfLoad(
      'segment.rebuildStatus',
      detail: 'refreshSegmentsOnChange=$refreshSegmentsOnChange',
    );
    _pollingDynamicRebuildTask = true;
    try {
      final previous = _dynamicRebuildTaskStatus;
      final status = await _visibleDynamicRebuildTaskStatus(
        await _db.getDynamicRebuildTaskStatus(),
      );
      if (!mounted) return;
      _segmentStatusSetState(() {
        _dynamicRebuildTaskStatus = status;
      });
      _publishDynamicRebuildUiSnapshot();
      if (refreshSegmentsOnChange) {
        await _handleDynamicRebuildTaskStatusChange(previous, status);
      }
      _endEntryPerfLoad(
        'segment.rebuildStatus',
        detail:
            'ms=${sw.elapsedMilliseconds} status=${status.status} active=${status.isActive}',
      );
    } catch (e) {
      _failEntryPerfLoad(
        'segment.rebuildStatus',
        e,
        detail: 'ms=${sw.elapsedMilliseconds}',
      );
    } finally {
      _pollingDynamicRebuildTask = false;
    }
  }

  Future<DynamicRebuildTaskStatus> _visibleDynamicRebuildTaskStatus(
    DynamicRebuildTaskStatus status,
  ) async {
    if (!status.isCompleted || status.canContinue) return status;
    try {
      return await _db.clearDynamicRebuildTask();
    } catch (_) {
      return status;
    }
  }

  Future<void> _handleDynamicRebuildTaskStatusChange(
    DynamicRebuildTaskStatus previous,
    DynamicRebuildTaskStatus current,
  ) async {
    if (_loading) {
      DynamicEntryPerfService.instance.mark(
        'segment.rebuildStatus.refreshSkipped',
        detail:
            'loading=true prev=${previous.status} current=${current.status}',
      );
      return;
    }
    final bool justStarted = !previous.isActive && current.isActive;
    final bool progressAdvanced =
        current.isActive &&
        current.processedSegments > previous.processedSegments;
    final bool becameTerminal = previous.isActive && !current.isActive;
    final bool terminalChanged =
        previous.status != current.status &&
        (current.isCompleted ||
            current.isCompletedWithFailures ||
            current.isFailed ||
            current.isCancelled);
    final bool timelineVisibilityChanged =
        _dynamicRebuildTimelineVisibilityFingerprint(previous) !=
        _dynamicRebuildTimelineVisibilityFingerprint(current);
    if (justStarted) {
      await _refresh(triggerSegmentTick: false);
      return;
    }
    if (progressAdvanced) {
      await _refreshSegmentsForDynamicRebuildProgress();
      return;
    }
    if (timelineVisibilityChanged || becameTerminal || terminalChanged) {
      await _refresh(triggerSegmentTick: false);
    }
  }

  Future<void> _refreshSegmentsForDynamicRebuildProgress() async {
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastDynamicRebuildListRefreshAt < 1500) return;
    _lastDynamicRebuildListRefreshAt = now;
    await _refresh(triggerSegmentTick: false);
  }

  Future<void> _confirmStartDynamicRebuild() async {
    if (_dynamicRebuildTaskStatus.isActive || _startingDynamicRebuild) return;
    final bool continueExisting =
        _dynamicRebuildTaskStatus.canContinue &&
        _dynamicRebuildTaskStatus.isRebuildMode;
    if (!continueExisting) {
      final _DynamicTaskScope? scope = await _pickDynamicTaskScope(
        backfill: false,
      );
      if (scope == null || !mounted) return;
      await _startDynamicRebuild(
        targetDayKey: scope == _DynamicTaskScope.selectedDay
            ? (_selectedDateKey ?? '').trim()
            : null,
      );
      return;
    }
    final bool ok = await UIDialogs.showConfirm(
      context,
      title: '继续重建动态',
      message: '会从上次未完成或失败的日期继续重建，不会重新清空已完成结果。适合任务中断后继续处理。确定继续吗？',
      confirmText: '继续重建',
      cancelText: '取消',
    );
    if (!ok || !mounted) return;
    await _continueDynamicRebuild();
  }

  _DynamicTaskConfirmCopy _dynamicTaskConfirmCopy({
    required bool backfill,
    required _DynamicTaskScope scope,
    required String dateKey,
  }) {
    if (!backfill) {
      switch (scope) {
        case _DynamicTaskScope.selectedDay:
          return _DynamicTaskConfirmCopy(
            title: '重建当天动态',
            message: '只清空并重建 $dateKey 的动态、当日总结和相关图片元数据，其他日期动态不会被删除。确定开始吗？',
            confirmText: '重建当天',
          );
        case _DynamicTaskScope.allDays:
          return const _DynamicTaskConfirmCopy(
            title: '重建动态',
            message:
                '重建会先清空当前动态、每日/每周总结与相关图片元数据，再从最老截图开始完整生成。适合需要彻底重跑全部动态的情况。确定继续吗？',
            confirmText: '立即重建',
          );
      }
    }
    switch (scope) {
      case _DynamicTaskScope.selectedDay:
        return _DynamicTaskConfirmCopy(
          title: '补全当天动态',
          message:
              '只补全 $dateKey 缺失动态和缺失总结，不会清空或覆盖已有动态。每条补全结果生成后，仍会检查是否能与上一条动态合并。确定开始吗？',
          confirmText: '补全当天',
        );
      case _DynamicTaskScope.allDays:
        return const _DynamicTaskConfirmCopy(
          title: '补全动态',
          message:
              '补全会按截图时间扫描每一天，已被现有动态结果覆盖的窗口会跳过，只把缺失日期、缺失时间窗或缺失总结加入后台队列，不会清空当前动态。每条补全结果生成后，仍会检查是否能与上一条动态合并，但不会重新扫描遗漏窗口。确定继续吗？',
          confirmText: '开始补全',
        );
    }
  }

  Widget _buildDynamicBackfillScopeCard(
    BuildContext context, {
    required _DynamicTaskScope scope,
    required _DynamicTaskScope selectedScope,
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<_DynamicTaskScope> onSelected,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool selected = scope == selectedScope;
    final Color accent = _dynamicBackfillColor(context);
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => onSelected(scope) : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 54),
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing2,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: selected
                      ? accent.withValues(alpha: 0.55)
                      : cs.outline.withValues(alpha: 0.18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: selected ? accent : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: selected ? accent : cs.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<_DynamicTaskScope?> _pickDynamicTaskScope({
    required bool backfill,
  }) async {
    final String dateKey = (_selectedDateKey ?? '').trim();
    final bool canUseSelectedDay = dateKey.isNotEmpty;
    _DynamicTaskScope selectedScope = canUseSelectedDay
        ? _DynamicTaskScope.selectedDay
        : _DynamicTaskScope.allDays;

    return showGeneralDialog<_DynamicTaskScope>(
      context: context,
      barrierDismissible: true,
      barrierLabel: backfill ? 'Backfill Scope' : 'Rebuild Scope',
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.50),
      transitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (dialogContext, _, __) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final ThemeData theme = Theme.of(dialogContext);
            final ColorScheme cs = theme.colorScheme;
            final bool isDark = theme.brightness == Brightness.dark;
            final Color surface =
                theme.dialogTheme.backgroundColor ?? cs.surface;
            final Color divider = cs.outlineVariant.withValues(
              alpha: isDark ? 0.95 : 1.0,
            );
            final _DynamicTaskConfirmCopy copy = _dynamicTaskConfirmCopy(
              backfill: backfill,
              scope: selectedScope,
              dateKey: dateKey,
            );
            return PopScope(
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing6,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 420,
                        minWidth: 300,
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: Container(
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusLg,
                            ),
                            border: Border.all(color: divider),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppTheme.spacing6,
                                  AppTheme.spacing6,
                                  AppTheme.spacing6,
                                  AppTheme.spacing2,
                                ),
                                child: Text(
                                  copy.title,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppTheme.spacing6,
                                  AppTheme.spacing2,
                                  AppTheme.spacing6,
                                  AppTheme.spacing5,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      copy.message,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                            height: 1.45,
                                          ),
                                    ),
                                    const SizedBox(height: AppTheme.spacing4),
                                    Row(
                                      children: [
                                        _buildDynamicBackfillScopeCard(
                                          dialogContext,
                                          scope: _DynamicTaskScope.selectedDay,
                                          selectedScope: selectedScope,
                                          title: backfill ? '补全当天' : '重建当天',
                                          subtitle: canUseSelectedDay
                                              ? dateKey
                                              : '当前没有选中日期',
                                          enabled: canUseSelectedDay,
                                          onSelected: (scope) {
                                            setDialogState(
                                              () => selectedScope = scope,
                                            );
                                          },
                                        ),
                                        const SizedBox(
                                          width: AppTheme.spacing2,
                                        ),
                                        _buildDynamicBackfillScopeCard(
                                          dialogContext,
                                          scope: _DynamicTaskScope.allDays,
                                          selectedScope: selectedScope,
                                          title: backfill ? '补全全部' : '重建全部',
                                          subtitle: backfill
                                              ? '扫描所有日期'
                                              : '清空后完整生成',
                                          enabled: true,
                                          onSelected: (scope) {
                                            setDialogState(
                                              () => selectedScope = scope,
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: divider, width: 1),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 48,
                                        child: TextButton(
                                          onPressed: () {
                                            Navigator.of(
                                              dialogContext,
                                            ).pop(null);
                                          },
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                cs.onSurfaceVariant,
                                            shape: const RoundedRectangleBorder(
                                              borderRadius: BorderRadius.zero,
                                            ),
                                          ),
                                          child: Text(
                                            AppLocalizations.of(
                                              dialogContext,
                                            ).dialogCancel,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 48,
                                      color: divider,
                                    ),
                                    Expanded(
                                      child: SizedBox(
                                        height: 48,
                                        child: TextButton(
                                          onPressed: () {
                                            Navigator.of(
                                              dialogContext,
                                            ).pop(selectedScope);
                                          },
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                _dynamicBackfillColor(context),
                                            shape: const RoundedRectangleBorder(
                                              borderRadius: BorderRadius.zero,
                                            ),
                                            textStyle: theme
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          child: Text(copy.confirmText),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<_DynamicTaskScope?> _pickDynamicBackfillScope() {
    return _pickDynamicTaskScope(backfill: true);
  }

  Future<void> _confirmStartDynamicBackfill() async {
    if (_dynamicRebuildTaskStatus.isActive || _startingDynamicRebuild) return;
    final bool continueExisting =
        _dynamicRebuildTaskStatus.canContinue &&
        _dynamicRebuildTaskStatus.isBackfillMode;
    if (!continueExisting) {
      final _DynamicTaskScope? scope = await _pickDynamicBackfillScope();
      if (scope == null || !mounted) return;
      await _startDynamicRebuild(
        taskMode: 'backfill',
        targetDayKey: scope == _DynamicTaskScope.selectedDay
            ? (_selectedDateKey ?? '').trim()
            : null,
      );
      return;
    }
    final bool ok = await UIDialogs.showConfirm(
      context,
      title: '继续补全动态',
      message:
          '会继续处理未完成或失败待续的日期，只补齐缺失日期、缺失时间窗或缺失总结，不会清空当前动态。每条补全结果生成后，仍会检查是否能与上一条动态合并，但不会重新扫描遗漏窗口。确定继续吗？',
      confirmText: '继续补全',
      cancelText: '取消',
    );
    if (!ok || !mounted) return;
    await _continueDynamicRebuild();
  }

  Future<void> _startDynamicRebuild({
    bool resumeExisting = false,
    String taskMode = 'rebuild',
    String? targetDayKey,
  }) async {
    if (_startingDynamicRebuild) return;
    _segmentStatusSetState(() => _startingDynamicRebuild = true);
    _publishDynamicRebuildUiSnapshot();
    try {
      final previous = _dynamicRebuildTaskStatus;
      final status = await _db.startDynamicRebuildTask(
        resumeExisting: resumeExisting,
        dayConcurrency: _selectedDynamicRebuildDayConcurrency,
        taskMode: resumeExisting
            ? _dynamicRebuildTaskStatus.taskMode
            : taskMode,
        targetDayKey: resumeExisting ? null : targetDayKey,
      );
      if (!mounted) return;
      final DynamicRebuildTaskStatus visibleStatus =
          await _visibleDynamicRebuildTaskStatus(status);
      if (!mounted) return;
      _segmentStatusSetState(() {
        _dynamicRebuildTaskStatus = visibleStatus;
        if (status.dayConcurrency > 0) {
          _selectedDynamicRebuildDayConcurrency = math.max(
            1,
            math.min(10, status.dayConcurrency),
          );
        }
      });
      _publishDynamicRebuildUiSnapshot();
      if (status.isCompleted && status.totalSegments == 0) {
        UINotifier.info(
          context,
          status.targetDayKey.trim().isNotEmpty
              ? (status.isBackfillMode ? '当天没有需要补全的动态' : '当天没有可重建的动态')
              : status.isBackfillMode
              ? '未发现需要补全的动态'
              : AppLocalizations.of(context).dynamicRebuildNoSegments,
        );
        await _refresh(triggerSegmentTick: false);
      } else if (status.isActive && resumeExisting) {
        final String model = status.aiModel.trim();
        UINotifier.info(
          context,
          model.isNotEmpty
              ? AppLocalizations.of(
                  context,
                ).dynamicRebuildSwitchedModelContinue(model)
              : AppLocalizations.of(context).dynamicRebuildTaskResumed,
        );
        await _refresh(triggerSegmentTick: false);
      } else if (status.isActive && !previous.isActive) {
        UINotifier.info(
          context,
          status.targetDayKey.trim().isNotEmpty
              ? (status.isBackfillMode
                    ? '已开始后台补全当天动态，可在通知栏查看进度'
                    : '已开始后台重建当天动态，可在通知栏查看进度')
              : status.isBackfillMode
              ? '已开始后台补全，可在通知栏查看进度'
              : AppLocalizations.of(context).dynamicRebuildStartedInBackground,
        );
        await _refresh(triggerSegmentTick: false);
      } else if (status.isActive) {
        UINotifier.info(
          context,
          status.isBackfillMode
              ? '动态补全任务已恢复'
              : AppLocalizations.of(context).dynamicRebuildTaskResumed,
        );
      }
    } catch (e) {
      if (mounted) {
        await UIDialogs.showInfo(
          context,
          title: taskMode == 'backfill' ? '动态补全失败' : '动态重建失败',
          message: e.toString(),
        );
      }
    } finally {
      if (mounted) {
        _segmentStatusSetState(() => _startingDynamicRebuild = false);
        _publishDynamicRebuildUiSnapshot();
      }
    }
  }

  Future<void> _continueDynamicRebuild() async {
    await _startDynamicRebuild(resumeExisting: true);
  }

  Future<void> _clearDynamicRebuildTask() async {
    if (_dynamicRebuildTaskStatus.isActive || _stoppingDynamicRebuild) return;
    _segmentStatusSetState(() => _stoppingDynamicRebuild = true);
    _publishDynamicRebuildUiSnapshot();
    try {
      final status = await _db.clearDynamicRebuildTask();
      if (!mounted) return;
      _segmentStatusSetState(() => _dynamicRebuildTaskStatus = status);
      _publishDynamicRebuildUiSnapshot();
      UINotifier.info(
        context,
        AppLocalizations.of(context).dynamicTaskExitSuccess,
      );
      await _refresh(triggerSegmentTick: false);
    } catch (_) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).dynamicTaskExitFailed,
        );
      }
    } finally {
      if (mounted) {
        _segmentStatusSetState(() => _stoppingDynamicRebuild = false);
        _publishDynamicRebuildUiSnapshot();
      }
    }
  }

  Future<void> _cancelDynamicRebuild() async {
    if (_stoppingDynamicRebuild) return;
    _segmentStatusSetState(() => _stoppingDynamicRebuild = true);
    _publishDynamicRebuildUiSnapshot();
    try {
      final status = await _db.cancelDynamicRebuildTask();
      if (!mounted) return;
      _segmentStatusSetState(() => _dynamicRebuildTaskStatus = status);
      _publishDynamicRebuildUiSnapshot();
      UINotifier.info(
        context,
        AppLocalizations.of(context).dynamicRebuildStopped,
      );
      await _refresh(triggerSegmentTick: false);
    } catch (_) {
      if (mounted) {
        UINotifier.error(
          context,
          AppLocalizations.of(context).dynamicRebuildStopFailed,
        );
      }
    } finally {
      if (mounted) {
        _segmentStatusSetState(() => _stoppingDynamicRebuild = false);
        _publishDynamicRebuildUiSnapshot();
      }
    }
  }
}
