part of 'segment_status_page.dart';

// ========== 动态重建面板 UI ==========
extension _SegmentStatusDynamicSheetPart on _SegmentStatusPageState {
  Widget _buildDynamicRebuildTaskSheetBody(
    BuildContext context,
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = snapshot.status;
    final bool hasTask = _hasVisibleDynamicTask(status);
    final bool showRecentTaskDetails = _shouldShowRecentDynamicTaskDetails(
      status,
    );
    final bool displayAsInitialTask = hasTask && !showRecentTaskDetails;
    final bool showTaskProgress = _shouldShowDynamicTaskProgress(status);
    final bool showWorkerProgress = _shouldShowDynamicWorkerProgress(status);
    final bool actualBackfill = hasTask && status.isBackfillMode;
    final bool actualTargetDayBackfill =
        actualBackfill && status.targetDayKey.trim().isNotEmpty;
    final String sheetTitle = showRecentTaskDetails
        ? '${status.isActive ? '当前后台任务' : '最近任务'}：${_dynamicTaskModeName(backfill: actualBackfill, targetDay: actualTargetDayBackfill)}'
        : '动态任务';
    final String statusBadge = displayAsInitialTask
        ? '未启动'
        : showRecentTaskDetails
        ? '${_dynamicTaskModeShortName(backfill: actualBackfill, targetDay: actualTargetDayBackfill)} · ${_dynamicRebuildTaskLabel(status)}'
        : _dynamicRebuildTaskLabel(status);
    final int dayConcurrency = _effectiveDynamicRebuildDayConcurrency(snapshot);
    final Color statusColor = displayAsInitialTask
        ? cs.outline
        : _dynamicRebuildTaskColor(status);
    final double? progressValue = status.totalSegments > 0
        ? (status.processedSegments / status.totalSegments).clamp(0, 1)
        : (status.isCompleted ? 1 : null);
    final String progressText = status.totalSegments > 0
        ? '${status.processedSegments}/${status.totalSegments} (${status.progressPercent})'
        : (status.isCompleted
              ? (status.isBackfillMode ? '无缺失动态' : '无可重建动态')
              : '0/0 (${status.progressPercent})');
    final String summaryLine =
        '已处理 ${status.processedSegments}/${status.totalSegments} 条动态 · '
        '失败 ${status.failedSegments} 条 · '
        '已完成 ${status.completedDays}/${status.totalDays} 天 · '
        '并发 $dayConcurrency · '
        '待续失败天数 ${status.failedDays}';
    final String currentLine = _dynamicRebuildCurrentLine(status);
    final String modelLine = _dynamicRebuildModelLine(status);
    final String stageHeadline = _dynamicRebuildStageHeadline(status);
    final String serialHint = _dynamicRebuildSerialHint(status);

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
                sheetTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(color: statusColor.withValues(alpha: 0.25)),
              ),
              child: Text(
                statusBadge,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (showTaskProgress) ...[
          const SizedBox(height: AppTheme.spacing4),
          Text(
            progressText,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          UIProgress(
            value: progressValue,
            height: 6,
            valueColor: actualBackfill ? _dynamicBackfillColor(context) : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacing2),
            child: Text(
              summaryLine,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
        if (showRecentTaskDetails && currentLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacing3),
            child: Text(
              currentLine,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        if (showRecentTaskDetails && modelLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacing2),
            child: Text(
              modelLine,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (showRecentTaskDetails && stageHeadline.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: AppTheme.spacing3),
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Text(
              stageHeadline,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (showRecentTaskDetails && serialHint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spacing2),
            child: Text(
              serialHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: AppTheme.spacing3),
        if (showRecentTaskDetails && status.startedAt > 0)
          Text(
            '开始：${_fmtTaskDateTime(status.startedAt)}',
            style: theme.textTheme.bodySmall,
          ),
        if (showRecentTaskDetails && status.updatedAt > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '更新：${_fmtTaskDateTime(status.updatedAt)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (showRecentTaskDetails && status.completedAt > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '结束：${_fmtTaskDateTime(status.completedAt)}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (showRecentTaskDetails && status.lastError != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: AppTheme.spacing3),
            padding: const EdgeInsets.all(AppTheme.spacing3),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Text(
              status.lastError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
          ),
        const SizedBox(height: AppTheme.spacing4),
        _buildDynamicTaskStartControls(context, snapshot),
        const SizedBox(height: AppTheme.spacing3),
        _buildDynamicRebuildDayConcurrencySection(context, snapshot),
        if (showWorkerProgress) ...[
          const SizedBox(height: AppTheme.spacing3),
          _buildDynamicRebuildWorkersSection(context, snapshot),
        ],
        const SizedBox(height: AppTheme.spacing3),
        _buildDynamicAutoRepairSection(context, snapshot),
        if (showRecentTaskDetails && status.recentLogs.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacing4),
          _buildDynamicRebuildStageLogsSection(context, status),
        ],
      ],
    );
  }

  Widget _buildDynamicTaskStartControls(
    BuildContext context,
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final DynamicRebuildTaskStatus status = snapshot.status;
    final OutlinedBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
    );

    if (status.isActive) {
      final String stopLabel = status.isBackfillMode ? '停止补全' : '停止重建';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
                disabledBackgroundColor: cs.surfaceContainerHigh,
                disabledForegroundColor: cs.onSurfaceVariant,
                shape: shape,
              ),
              onPressed: snapshot.stopping ? null : _cancelDynamicRebuild,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(
                snapshot.stopping
                    ? AppLocalizations.of(context).dynamicTaskStopping
                    : stopLabel,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            '当前${_dynamicTaskModeName(backfill: status.isBackfillMode, targetDay: status.targetDayKey.trim().isNotEmpty)}任务运行中，启动按钮已切换为停止按钮。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      );
    }

    Widget startButton({
      required String label,
      required Color backgroundColor,
      required Color foregroundColor,
      required VoidCallback onPressed,
      bool enabled = true,
    }) {
      final bool disabled = snapshot.starting || snapshot.stopping || !enabled;
      final Color effectiveForeground = disabled
          ? cs.onSurfaceVariant
          : foregroundColor;
      return SizedBox(
        height: 42,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            disabledBackgroundColor: cs.surfaceContainerHigh,
            disabledForegroundColor: cs.onSurfaceVariant,
            shape: shape,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing2),
          ),
          onPressed: disabled ? null : onPressed,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              color: effectiveForeground,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    if (status.canContinue) {
      final bool backfill = status.isBackfillMode;
      final String modeName = _dynamicTaskModeShortName(
        backfill: backfill,
        targetDay: status.targetDayKey.trim().isNotEmpty,
      );
      final Color accentColor = backfill
          ? _dynamicBackfillColor(context)
          : cs.error;
      final Color onAccentColor = backfill
          ? _dynamicBackfillOnColor(context)
          : cs.onError;
      final VoidCallback continueAction = backfill
          ? _confirmStartDynamicBackfill
          : _confirmStartDynamicRebuild;
      return Row(
        children: [
          Expanded(
            child: startButton(
              label: '退出$modeName',
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              onPressed: _clearDynamicRebuildTask,
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          Expanded(
            child: startButton(
              label: '继续$modeName',
              backgroundColor: accentColor,
              foregroundColor: onAccentColor,
              onPressed: continueAction,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: startButton(
            label: '重建',
            backgroundColor: cs.error,
            foregroundColor: cs.onError,
            onPressed: _confirmStartDynamicRebuild,
          ),
        ),
        const SizedBox(width: AppTheme.spacing2),
        Expanded(
          child: startButton(
            label: '补全',
            backgroundColor: _dynamicBackfillColor(context),
            foregroundColor: _dynamicBackfillOnColor(context),
            onPressed: _confirmStartDynamicBackfill,
          ),
        ),
      ],
    );
  }

  bool _hasVisibleDynamicTask(DynamicRebuildTaskStatus status) {
    return !status.isIdle && status.taskId.trim().isNotEmpty;
  }

  bool _shouldShowRecentDynamicTaskDetails(DynamicRebuildTaskStatus status) {
    return _hasVisibleDynamicTask(status) &&
        (status.isActive || status.canContinue);
  }

  bool _shouldShowDynamicTaskProgress(DynamicRebuildTaskStatus status) {
    return _shouldShowRecentDynamicTaskDetails(status);
  }

  bool _shouldShowDynamicWorkerProgress(DynamicRebuildTaskStatus status) {
    return _hasVisibleDynamicTask(status) && status.isActive;
  }

  String _dynamicTaskModeName({
    required bool backfill,
    bool targetDay = false,
  }) {
    if (backfill && targetDay) return '当天动态补全';
    if (!backfill && targetDay) return '当天动态重建';
    return backfill ? '动态补全' : '动态重建';
  }

  String _dynamicTaskModeShortName({
    required bool backfill,
    bool targetDay = false,
  }) {
    if (backfill && targetDay) return '当天补全';
    if (!backfill && targetDay) return '当天重建';
    return backfill ? '补全' : '重建';
  }

  Color _dynamicBackfillColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  Color _dynamicBackfillOnColor(BuildContext context) {
    return Theme.of(context).colorScheme.onPrimary;
  }

  Widget _buildDynamicRebuildDayConcurrencySection(
    BuildContext context,
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool editable = _canEditDynamicRebuildDayConcurrency(snapshot);
    final int value = _effectiveDynamicRebuildDayConcurrency(snapshot);

    Widget buildStepButton({
      required IconData icon,
      required VoidCallback? onPressed,
    }) {
      return SizedBox(
        width: 34,
        height: 34,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            side: BorderSide(
              color: cs.outline.withValues(
                alpha: onPressed == null ? 0.18 : 0.34,
              ),
            ),
          ),
          onPressed: onPressed,
          child: Icon(icon, size: 16),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '并发天数',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  editable ? '可设置 1-10 天' : '任务运行中不可修改',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          buildStepButton(
            icon: Icons.remove,
            onPressed: editable && value > 1
                ? () {
                    unawaited(_changeDynamicRebuildDayConcurrency(-1));
                  }
                : null,
          ),
          Container(
            width: 48,
            alignment: Alignment.center,
            child: Text(
              '$value',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          buildStepButton(
            icon: Icons.add,
            onPressed: editable && value < 10
                ? () {
                    unawaited(_changeDynamicRebuildDayConcurrency(1));
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicRebuildWorkersSection(
    BuildContext context,
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final int activeWorkerCount = snapshot.status.workers
        .where((DynamicRebuildWorkerState worker) => !worker.isIdle)
        .length;
    final int slotCount = math.max(1, activeWorkerCount);
    final Map<int, DynamicRebuildWorkerState> workersBySlot =
        <int, DynamicRebuildWorkerState>{
          for (final DynamicRebuildWorkerState worker
              in snapshot.status.workers.where(
                (DynamicRebuildWorkerState worker) => !worker.isIdle,
              ))
            worker.slotId: worker,
        };
    final List<int> visibleSlotIds = workersBySlot.keys.toList()..sort();
    if (visibleSlotIds.isEmpty) visibleSlotIds.add(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '线程进度',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppTheme.spacing1),
        Text(
          '每个线程会串行跑完当天全部动态，完成后再领取下一个未完成日期。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppTheme.spacing3),
        LayoutBuilder(
          builder: (context, constraints) {
            final bool useTwoColumns = constraints.maxWidth >= 680;
            final double cardWidth = useTwoColumns
                ? (constraints.maxWidth - AppTheme.spacing3) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: AppTheme.spacing3,
              runSpacing: AppTheme.spacing3,
              children: [
                for (final int slotId in visibleSlotIds.take(slotCount))
                  SizedBox(
                    width: cardWidth,
                    child: _buildDynamicRebuildWorkerCard(
                      context,
                      slotId,
                      workersBySlot[slotId],
                      backfillMode: snapshot.status.isBackfillMode,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildDynamicRebuildWorkerCard(
    BuildContext context,
    int slotId,
    DynamicRebuildWorkerState? worker, {
    required bool backfillMode,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Color accent = _dynamicRebuildWorkerColor(context, worker);
    final String statusLine = _dynamicRebuildWorkerStatusLine(worker);
    final String stageLabel = worker?.currentStageLabel.trim() ?? '';
    final String stageDetail = worker?.currentStageDetail.trim() ?? '';
    final String rangeLabel = worker?.currentRangeLabel.trim() ?? '';
    final int processed = worker?.processedSegments ?? 0;
    final int total = worker?.totalSegments ?? 0;
    final List<String> allRecentStreamChunks =
        worker?.recentStreamChunks ?? const <String>[];
    final List<String> recentStreamChunks = allRecentStreamChunks.length <= 3
        ? allRecentStreamChunks
        : allRecentStreamChunks.sublist(allRecentStreamChunks.length - 3);
    final double? progressValue = total > 0
        ? (processed / total).clamp(0, 1)
        : null;
    final String progressText = total > 0 ? '$processed/$total' : '0/0';

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '线程 $slotId',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Text(
                  _dynamicRebuildWorkerChipLabel(worker),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            statusLine,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            '当天进度 $progressText',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing1),
          UIProgress(
            value: progressValue,
            height: 5,
            valueColor: backfillMode ? _dynamicBackfillColor(context) : null,
          ),
          if (rangeLabel.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              '时间窗：$rangeLabel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (stageLabel.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing2),
            Text(
              '当前阶段：$stageLabel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (stageDetail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              stageDetail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
          if (recentStreamChunks.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing3),
            Text(
              '最近 3 条流式数据',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.spacing1),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.spacing2),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(color: cs.outline.withValues(alpha: 0.14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (
                    int index = 0;
                    index < recentStreamChunks.length;
                    index++
                  ) ...[
                    if (index > 0) const SizedBox(height: 6),
                    Text(
                      '${index + 1}. ${recentStreamChunks[index]}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicAutoRepairSection(
    BuildContext context,
    _DynamicRebuildUiSnapshot snapshot,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool busy = snapshot.autoRepairLoading || snapshot.autoRepairToggling;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: cs.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '自动补建',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing1),
                Text(
                  snapshot.autoRepairEnabled
                      ? '开启后会在后台自动补齐缺失日期、时间窗和总结。'
                      : '暂停后只停止后台自动补齐，手动重建和补全不受影响。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          if (snapshot.autoRepairLoading && !snapshot.autoRepairToggling)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Opacity(
              opacity: busy ? 0.6 : 1,
              child: Transform.scale(
                scale: 0.92,
                child: Switch(
                  value: snapshot.autoRepairEnabled,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: busy ? null : _setDynamicAutoRepairEnabled,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
