import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/memory_entity_models.dart';
import '../services/nocturne_memory_maintenance_service.dart';
import '../services/nocturne_memory_rebuild_service.dart';
import '../services/nocturne_memory_signal_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_dialog.dart';

class NocturneMemoryRebuildTab extends StatefulWidget {
  const NocturneMemoryRebuildTab({super.key});

  @override
  State<NocturneMemoryRebuildTab> createState() =>
      _NocturneMemoryRebuildTabState();
}

class _NocturneMemoryRebuildTabState extends State<NocturneMemoryRebuildTab> {
  final NocturneMemoryRebuildService _controller =
      NocturneMemoryRebuildService.instance;
  final NocturneMemorySignalService _signals =
      NocturneMemorySignalService.instance;
  final NocturneMemoryMaintenanceService _maintenance =
      NocturneMemoryMaintenanceService.instance;
  final ScrollController _panelScroll = ScrollController();
  final ScrollController _logScroll = ScrollController();
  int _lastLogCount = 0;
  NocturneMemorySignalDashboard? _dashboard;
  List<NocturneMemorySignalDiagnosticItem> _candidateItems =
      const <NocturneMemorySignalDiagnosticItem>[];
  List<NocturneMemorySignalDiagnosticItem> _activeItems =
      const <NocturneMemorySignalDiagnosticItem>[];
  List<NocturneMemorySignalDiagnosticItem> _archivedItems =
      const <NocturneMemorySignalDiagnosticItem>[];
  List<MemoryEntityReviewQueueItem> _reviewItems =
      const <MemoryEntityReviewQueueItem>[];
  final Set<int> _reviewBusyIds = <int>{};
  NocturneMemorySignalStatus _selectedSignalStatus =
      NocturneMemorySignalStatus.candidate;
  bool _dashboardLoading = false;
  bool _dashboardReloadQueued = false;

  @override
  void initState() {
    super.initState();
    _lastLogCount = _controller.logs.length;
    _controller.addListener(_handleControllerChanged);
    _maintenance.addListener(_handleMaintenanceChanged);
    unawaited(_controller.ensureInitialized(autoResume: true));
    unawaited(_maintenance.ensureInitialized(autoResume: true));
    unawaited(_reloadDashboard());
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _maintenance.removeListener(_handleMaintenanceChanged);
    _panelScroll.dispose();
    _logScroll.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    final int nextLogCount = _controller.logs.length;
    final bool shouldScroll = nextLogCount != _lastLogCount;
    _lastLogCount = nextLogCount;
    if (!mounted) return;
    setState(() {});
    unawaited(_reloadDashboard());
    if (!shouldScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScroll.hasClients) return;
      try {
        _logScroll.animateTo(
          _logScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } catch (_) {}
    });
  }

  void _handleMaintenanceChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_reloadDashboard());
  }

  Future<void> _reloadDashboard() async {
    if (_dashboardLoading) {
      _dashboardReloadQueued = true;
      return;
    }
    _dashboardLoading = true;
    try {
      final List<Object> loaded = await Future.wait<Object>(<Future<Object>>[
        _signals.loadDashboard(limitPerStatus: 6),
        _signals.loadItemsByStatus(NocturneMemorySignalStatus.candidate),
        _signals.loadItemsByStatus(NocturneMemorySignalStatus.active),
        _signals.loadItemsByStatus(NocturneMemorySignalStatus.archived),
        _signals.loadReviewQueueItems(),
      ]);
      final NocturneMemorySignalDashboard dashboard =
          loaded[0] as NocturneMemorySignalDashboard;
      final List<NocturneMemorySignalDiagnosticItem> candidates =
          loaded[1] as List<NocturneMemorySignalDiagnosticItem>;
      final List<NocturneMemorySignalDiagnosticItem> active =
          loaded[2] as List<NocturneMemorySignalDiagnosticItem>;
      final List<NocturneMemorySignalDiagnosticItem> archived =
          loaded[3] as List<NocturneMemorySignalDiagnosticItem>;
      final List<MemoryEntityReviewQueueItem> reviewItems =
          loaded[4] as List<MemoryEntityReviewQueueItem>;
      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
        _candidateItems = candidates;
        _activeItems = active;
        _archivedItems = archived;
        _reviewItems = reviewItems;
      });
    } catch (_) {
    } finally {
      _dashboardLoading = false;
      if (_dashboardReloadQueued) {
        _dashboardReloadQueued = false;
        unawaited(_reloadDashboard());
      }
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _approveReviewItem(
    MemoryEntityReviewQueueItem item, {
    String? targetEntityId,
    bool forceCreateNew = false,
  }) async {
    if (_reviewBusyIds.contains(item.id)) return;
    setState(() => _reviewBusyIds.add(item.id));
    try {
      final MemoryEntityApplyResult result = await _signals
          .approveReviewQueueItem(
            reviewId: item.id,
            targetEntityId: targetEntityId,
            forceCreateNew: forceCreateNew,
          );
      final MemoryEntityRecord? record = result.record;
      _toast(
        record == null
            ? '复核已批准'
            : '复核已批准：${record.preferredName} -> ${record.displayUri}',
      );
      await _reloadDashboard();
    } catch (e) {
      _toast('批准复核失败：$e');
    } finally {
      if (mounted) {
        setState(() => _reviewBusyIds.remove(item.id));
      }
    }
  }

  Future<void> _dismissReviewItem(MemoryEntityReviewQueueItem item) async {
    if (_reviewBusyIds.contains(item.id)) return;
    final bool ok = await UIDialogs.showConfirm(
      context,
      title: '忽略待复核项',
      message:
          '这会把该候选从 review 队列移除，不会写入实体层。\n\n'
          '候选：${item.preferredName}\n'
          '原因：${item.reviewReason}\n\n'
          '继续忽略？',
      confirmText: '确认忽略',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _reviewBusyIds.add(item.id));
    try {
      await _signals.dismissReviewQueueItem(item.id);
      _toast('已忽略待复核项');
      await _reloadDashboard();
    } catch (e) {
      _toast('忽略待复核项失败：$e');
    } finally {
      if (mounted) {
        setState(() => _reviewBusyIds.remove(item.id));
      }
    }
  }

  bool _requiresMaintenanceConfirmation(
    NocturneMemoryMaintenanceSuggestion suggestion,
  ) {
    switch (suggestion.action) {
      case NocturneMemoryMaintenanceAction.archiveMemory:
      case NocturneMemoryMaintenanceAction.deleteMemory:
        return true;
      case NocturneMemoryMaintenanceAction.rewriteMemory:
      case NocturneMemoryMaintenanceAction.addAlias:
      case NocturneMemoryMaintenanceAction.moveMemory:
      case NocturneMemoryMaintenanceAction.dropCandidate:
        return false;
    }
  }

  Future<bool> _confirmMaintenanceApply(
    List<NocturneMemoryMaintenanceSuggestion> suggestions,
  ) async {
    final List<NocturneMemoryMaintenanceSuggestion> aggressive = suggestions
        .where(_requiresMaintenanceConfirmation)
        .toList();
    if (aggressive.isEmpty) return true;

    if (aggressive.length == 1) {
      final NocturneMemoryMaintenanceSuggestion suggestion = aggressive.first;
      final bool deleting =
          suggestion.action == NocturneMemoryMaintenanceAction.deleteMemory;
      final String title = deleting ? '确认删除节点' : '确认强制封存';
      final String message =
          '这条整理建议会直接影响现有记忆，需要单独确认。\n\n'
          'target_uri: ${suggestion.targetUri}\n'
          '原因: ${suggestion.reason}\n'
          '证据: ${suggestion.evidence}\n\n'
          '继续应用？';
      return UIDialogs.showConfirm(
        context,
        title: title,
        message: message,
        confirmText: deleting ? '确认删除' : '确认封存',
        destructive: true,
      );
    }

    final List<String> preview = aggressive
        .take(6)
        .map(
          (suggestion) => '${suggestion.action.label}: ${suggestion.targetUri}',
        )
        .toList();
    final int hiddenCount = aggressive.length - preview.length;
    final String message =
        '本次批量应用包含 ${aggressive.length} 条激进整理动作，需要先确认。\n\n'
        '${preview.join('\n')}'
        '${hiddenCount > 0 ? '\n…其余 $hiddenCount 条未展开' : ''}\n\n'
        '继续应用整批建议？';
    return UIDialogs.showConfirm(
      context,
      title: '确认应用激进建议',
      message: message,
      confirmText: '继续全部应用',
      destructive: true,
    );
  }

  Future<void> _start() async {
    if (_controller.running) return;
    final bool ok = await UIDialogs.showConfirm(
      context,
      title: '一键重建记忆',
      message: '将清空当前 Nocturne 记忆库，并仅用“动态”里的截图图片重新构建。\n\n继续？',
      confirmText: '开始重建',
    );
    if (!ok) return;
    await _controller.startFresh();
    if (!mounted) return;
    if (_controller.running) {
      _toast('已开始后台重建，可在通知栏查看进度');
    }
  }

  Widget _buildStatsRow(BuildContext context) {
    final int total = _controller.totalSegments;
    final int cur = _controller.cursor.clamp(0, total);
    final String pos = total <= 0 ? '-' : '$cur/$total';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '进度：$pos  已处理=${_controller.processed}  跳过(无图)=${_controller.skippedNoImages}  跳过(文件缺失)=${_controller.skippedMissingFiles}  失败=${_controller.failed}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_controller.lastSegmentId != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '当前段落：#${_controller.lastSegmentId}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (_controller.segmentSampleCursorSegmentId != null &&
            _controller.segmentSampleTotal > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '段内图片：${_controller.segmentSampleCursor}/${_controller.segmentSampleTotal}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _controller.running
                ? '任务已切到页面外继续执行；退出此页不会暂停，可在通知栏查看进度。'
                : '重建任务已改为应用级任务：退出此页后不会因页面销毁而中断。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  static String _formatTimestamp(int ms) {
    if (ms <= 0) return '—';
    final DateTime dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  Widget _buildSignalItem(
    BuildContext context,
    NocturneMemorySignalDiagnosticItem item,
  ) {
    String statusText() {
      switch (item.status) {
        case NocturneMemorySignalStatus.active:
          return '正式记忆';
        case NocturneMemorySignalStatus.archived:
          return '已封存';
        case NocturneMemorySignalStatus.candidate:
          return '候选';
      }
    }

    String readinessText() {
      if (item.needsReview) {
        return '已拦截，等待人工复核';
      }
      if (item.status == NocturneMemorySignalStatus.active) {
        return 'score=${item.decayedScore.toStringAsFixed(2)}，跨天=${item.distinctDayCount}';
      }
      if (item.status == NocturneMemorySignalStatus.archived) {
        return '最近出现：${_formatTimestamp(item.lastSeenAt)}';
      }
      final List<String> parts = <String>[];
      if (item.rootMaterializationBlocked) {
        parts.add('根节点不可直接物化');
      }
      if (item.missingActivationScore > 0) {
        parts.add('还差分数 ${item.missingActivationScore.toStringAsFixed(2)}');
      }
      if (item.missingDistinctDays > 0) {
        parts.add('还差跨天 ${item.missingDistinctDays}');
      }
      if (item.evidenceSatisfied && item.missingActivationScore <= 0) {
        parts.add('满足阈值，等待物化');
      }
      return parts.isEmpty
          ? 'score=${item.decayedScore.toStringAsFixed(2)}，跨天=${item.distinctDayCount}'
          : parts.join('，');
    }

    final String preview = item.latestContent
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '（无内容）');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.14),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.uri.replaceFirst('core://', ''),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${statusText()} | ${readinessText()}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if ((item.reviewReason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'review: ${item.reviewReason!.trim()}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildSignalDashboardPanel(BuildContext context) {
    final NocturneMemorySignalDashboard? dashboard = _dashboard;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextStyle? labelStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final List<Widget> qualityChips = <Widget>[];
    final List<Widget> rootChips = <Widget>[];
    if (dashboard != null) {
      final MemoryEntityQualityMetrics metrics = dashboard.qualityMetrics;
      List<String> qualityPairs() => <String>[
        '新建 ${metrics.createdNewCount}',
        '合并 ${metrics.matchedExistingCount}',
        '待复核 ${metrics.reviewQueuedCount}',
        '重复拦截 ${metrics.duplicateBlockCount}',
        '歧义拦截 ${metrics.ambiguousBlockCount}',
        '证据不足 ${metrics.lowEvidenceBlockCount}',
        '空批率 ${(metrics.emptyBatchRate * 100).toStringAsFixed(1)}%',
        '重复簇 ${metrics.duplicateClusterCount}',
        '图层漂移 ${metrics.materializationDrift}',
        '人工批准 ${metrics.manualReviewApprovedCount}',
        '图层节点 ${metrics.materializedNodeCount}',
        '实体数 ${metrics.materializedEntityCount}',
      ];
      for (final String text in qualityPairs()) {
        qualityChips.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.26),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: cs.outline.withValues(alpha: 0.14),
                width: 1,
              ),
            ),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );
      }
      for (final NocturneMemorySignalRootSummary root in dashboard.roots) {
        if (root.candidateCount <= 0 &&
            root.activeCount <= 0 &&
            root.archivedCount <= 0) {
          continue;
        }
        final String shortRoot = root.rootUri.replaceFirst(
          'core://my_user/',
          '',
        );
        rootChips.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.26),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$shortRoot  C${root.candidateCount} A${root.activeCount} R${root.archivedCount}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );
      }
    }

    List<NocturneMemorySignalDiagnosticItem> itemsForSelectedStatus() {
      switch (_selectedSignalStatus) {
        case NocturneMemorySignalStatus.active:
          return _activeItems;
        case NocturneMemorySignalStatus.archived:
          return _archivedItems;
        case NocturneMemorySignalStatus.candidate:
          return _candidateItems;
      }
    }

    String statusLabel(NocturneMemorySignalStatus status) {
      switch (status) {
        case NocturneMemorySignalStatus.active:
          return '正式';
        case NocturneMemorySignalStatus.archived:
          return '封存';
        case NocturneMemorySignalStatus.candidate:
          return '候选';
      }
    }

    int statusCount(NocturneMemorySignalStatus status) {
      switch (status) {
        case NocturneMemorySignalStatus.active:
          return dashboard?.activeCount ?? _activeItems.length;
        case NocturneMemorySignalStatus.archived:
          return dashboard?.archivedCount ?? _archivedItems.length;
        case NocturneMemorySignalStatus.candidate:
          return dashboard?.candidateCount ?? _candidateItems.length;
      }
    }

    final List<NocturneMemorySignalDiagnosticItem> visibleItems =
        itemsForSelectedStatus();
    final List<NocturneMemorySignalStatus> statuses =
        NocturneMemorySignalStatus.values;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '记忆信号面板',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (_dashboardLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dashboard == null
                ? '正在读取候选/正式/封存状态…'
                : '总数=${dashboard.totalCount}  候选=${dashboard.candidateCount}  正式=${dashboard.activeCount}  封存=${dashboard.archivedCount}  Review=${dashboard.reviewQueueCount}',
            style: labelStyle,
          ),
          if (qualityChips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '质量指标',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: qualityChips),
          ],
          if (rootChips.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: rootChips),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: statuses.map((status) {
              final bool selected = status == _selectedSignalStatus;
              return ChoiceChip(
                label: Text('${statusLabel(status)} ${statusCount(status)}'),
                selected: selected,
                onSelected: (_) {
                  if (_selectedSignalStatus == status) return;
                  setState(() {
                    _selectedSignalStatus = status;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            '${statusLabel(_selectedSignalStatus)}列表（全量，虚拟渲染）',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 360,
            child: visibleItems.isEmpty
                ? Center(child: Text('无', style: labelStyle))
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView.builder(
                      itemCount: visibleItems.length,
                      itemBuilder: (BuildContext context, int index) {
                        return _buildSignalItem(context, visibleItems[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewQueuePanel(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TextStyle? labelStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review 队列',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _reviewItems.isEmpty
                ? '当前没有待复核项'
                : '待复核 ${_reviewItems.length} 条，以下展示最近进入队列的记录',
            style: labelStyle,
          ),
          if (_reviewItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.builder(
                  itemCount: _reviewItems.length,
                  itemBuilder: (BuildContext context, int index) {
                    final MemoryEntityReviewQueueItem item =
                        _reviewItems[index];
                    final bool busy = _reviewBusyIds.contains(item.id);
                    final String apps = item.appNames.isEmpty
                        ? 'unknown'
                        : item.appNames.join(', ');
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(
                          color: cs.outline.withValues(alpha: 0.14),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.preferredName}  [${item.reviewStage}]',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'segment=${item.segmentId} batch=${item.batchIndex} app=$apps',
                            style: labelStyle,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.reviewReason,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: cs.error),
                          ),
                          if ((item.evidenceSummary ?? '')
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              item.evidenceSummary!.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: labelStyle,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonal(
                                onPressed: busy
                                    ? null
                                    : () => _approveReviewItem(
                                        item,
                                        targetEntityId: item.suggestedEntityId,
                                      ),
                                child: Text(
                                  item.suggestedEntityId != null &&
                                          item.suggestedEntityId!
                                              .trim()
                                              .isNotEmpty
                                      ? '按建议合并'
                                      : '批准当前方案',
                                ),
                              ),
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => _approveReviewItem(
                                        item,
                                        forceCreateNew: true,
                                      ),
                                child: const Text('强制新建'),
                              ),
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => _dismissReviewItem(item),
                                child: const Text('忽略'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaintenancePanel(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String lastRun = _formatTimestamp(_maintenance.lastRunAtMs);
    final String lastApply = _formatTimestamp(_maintenance.lastApplyAtMs);
    final String summary = _maintenance.lastSummary.trim();
    final String raw = _maintenance.lastRaw.trim();
    final String error = _maintenance.lastError.trim();
    final List<NocturneMemoryMaintenanceSuggestion> suggestions =
        _maintenance.suggestions;
    final String generateStatus = _maintenance.running
        ? '生成中'
        : _maintenance.lastStatus == 'failed'
        ? '失败'
        : _maintenance.lastStatus == 'completed'
        ? '已完成'
        : '未运行';
    final String applyStatus = _maintenance.applying
        ? '应用中'
        : _maintenance.lastApplyStatus == 'failed'
        ? '失败'
        : _maintenance.lastApplyStatus == 'completed'
        ? '已完成'
        : '未运行';
    final String applyResult = _maintenance.lastApplyResult.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: cs.outline.withValues(alpha: 0.18), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '定期整理',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton(
                onPressed: (_maintenance.running || _maintenance.applying)
                    ? null
                    : () async {
                        await _maintenance.runNow(force: true);
                        if (!mounted) return;
                        await _reloadDashboard();
                      },
                child: const Text('生成建议'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed:
                    (_maintenance.running ||
                        _maintenance.applying ||
                        suggestions.isEmpty)
                    ? null
                    : () async {
                        final bool ok = await _confirmMaintenanceApply(
                          suggestions,
                        );
                        if (!ok) return;
                        await _maintenance.applySuggestions();
                        if (!mounted) return;
                        await _reloadDashboard();
                      },
                child: const Text('全部应用'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '生成：$generateStatus  最近：$lastRun  自动间隔：12 小时',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            '应用：$applyStatus  最近：$lastApply',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            '这里只针对“整理建议”要求手动确认；普通截图提取仍会按现有规则自动进入候选/正式记忆。',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          const SizedBox(height: 8),
          SelectableText(
            summary.isEmpty ? '暂无整理摘要。' : summary,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Text(
            '建议列表',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (suggestions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '当前没有可应用的整理建议。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            ...suggestions.map(
              (suggestion) => _buildMaintenanceSuggestionItem(
                context,
                suggestion,
                enabled: !_maintenance.running && !_maintenance.applying,
              ),
            ),
          if (applyResult.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '应用结果',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            SelectableText(
              applyResult,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (raw.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'AI 原始输出',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            SelectableText(raw, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _buildMaintenanceSuggestionItem(
    BuildContext context,
    NocturneMemoryMaintenanceSuggestion suggestion, {
    required bool enabled,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: cs.outline.withValues(alpha: 0.14), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            suggestion.action.label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          SelectableText(
            'target_uri: ${suggestion.targetUri}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if ((suggestion.newUri ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            SelectableText(
              'new_uri: ${suggestion.newUri}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if ((suggestion.content ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              suggestion.content!,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '原因：${suggestion.reason}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            '证据：${suggestion.evidence}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: !enabled
                    ? null
                    : () async {
                        final bool ok = await _confirmMaintenanceApply(
                          <NocturneMemoryMaintenanceSuggestion>[suggestion],
                        );
                        if (!ok) return;
                        await _maintenance.applyPendingSuggestion(suggestion);
                        if (!mounted) return;
                        await _reloadDashboard();
                      },
                child: const Text('应用这条'),
              ),
              OutlinedButton(
                onPressed: !enabled
                    ? null
                    : () async {
                        await _maintenance.dismissSuggestion(suggestion);
                        if (!mounted) return;
                        await _reloadDashboard();
                      },
                child: const Text('不应用'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPausePanel(BuildContext context) {
    if (!_controller.paused) return const SizedBox.shrink();
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String reason = (_controller.pauseReason ?? '').trim();
    final String header = reason == 'parse_failed'
        ? '自动修复失败，已暂停'
        : reason == 'apply_failed'
        ? '写入失败，已暂停'
        : reason == 'stopped'
        ? '已停止'
        : '已暂停';
    final String detail = (_controller.lastError ?? '').trim();
    final String raw = (_controller.lastRawResponse ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: cs.error.withValues(alpha: 0.25), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onErrorContainer,
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onErrorContainer),
            ),
          ],
          if (raw.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '原始响应：',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onErrorContainer.withValues(alpha: 0.95),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(
                  color: cs.outline.withValues(alpha: 0.18),
                  width: 1,
                ),
              ),
              child: SelectableText(
                raw,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(
                onPressed: _controller.continueAfterPause,
                child: const Text('继续'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: (detail.isEmpty && raw.isEmpty)
                    ? null
                    : () async {
                        try {
                          final StringBuffer sb = StringBuffer();
                          if (_controller.lastSegmentId != null) {
                            sb.writeln(
                              'segment: #${_controller.lastSegmentId}',
                            );
                          }
                          if (reason.isNotEmpty) sb.writeln('reason: $reason');
                          if (detail.isNotEmpty) sb.writeln(detail);
                          if (raw.isNotEmpty) {
                            sb.writeln();
                            sb.writeln('raw:');
                            sb.writeln(raw);
                          }
                          await Clipboard.setData(
                            ClipboardData(text: sb.toString().trimRight()),
                          );
                          if (mounted) _toast('已复制');
                        } catch (_) {
                          if (mounted) _toast('复制失败');
                        }
                      },
                icon: const Icon(Icons.content_copy, size: 18),
                label: const Text('复制错误'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () async {
                  await UIDialogs.showInfo(
                    context,
                    title: '提示',
                    message:
                        '“继续”会跳过当前失败批次（本批最多10张图），继续处理本段剩余图片；若该段落已无剩余则进入下一段。\n\n若属于段落级异常，则会直接跳过该段落。',
                  );
                },
                child: const Text('说明'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(BuildContext context) {
    final List<String> logs = _controller.logs;
    if (logs.isEmpty) {
      return Center(
        child: Text(
          '日志会显示在这里',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _logScroll,
      itemCount: logs.length,
      itemBuilder: (ctx, i) {
        final s = logs[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(s, style: Theme.of(context).textTheme.bodySmall),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewportHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 800;
        final double logHeight = viewportHeight >= 900
            ? 280
            : viewportHeight >= 760
            ? 240
            : 200;

        return Padding(
          padding: const EdgeInsets.all(AppTheme.spacing3),
          child: Column(
            children: [
              Expanded(
                child: Scrollbar(
                  controller: _panelScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _panelScroll,
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _controller.running ? null : _start,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('一键重建'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _controller.running
                                  ? _controller.requestStop
                                  : null,
                              icon: const Icon(Icons.stop, size: 18),
                              label: const Text('停止'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSm,
                            ),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withValues(alpha: 0.18),
                              width: 1,
                            ),
                          ),
                          child: _buildStatsRow(context),
                        ),
                        const SizedBox(height: 10),
                        _buildSignalDashboardPanel(context),
                        const SizedBox(height: 10),
                        _buildReviewQueuePanel(context),
                        const SizedBox(height: 10),
                        _buildMaintenancePanel(context),
                        const SizedBox(height: 10),
                        _buildPausePanel(context),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: logHeight,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.0),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.18),
                      width: 1,
                    ),
                  ),
                  child: _buildLogList(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
