import 'dart:async';
import 'dart:math' as math;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import '../models/memory_models.dart';
import '../services/flutter_logger.dart';
import '../services/memory_bridge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../widgets/tag_hierarchy_tree.dart';
import '../widgets/ui_dialog.dart';
import 'tag_detail_page.dart';

class MemoryCenterPage extends StatefulWidget {
  const MemoryCenterPage({super.key});

  @override
  State<MemoryCenterPage> createState() => _MemoryCenterPageState();
}

class _MemoryCenterPageState extends State<MemoryCenterPage> {
  final MemoryBridgeService _service = MemoryBridgeService.instance;
  final Set<int> _confirmingTagIds = <int>{};
  final Set<int> _deletingTagIds = <int>{};

  static const int _pageStep = 10;
  static const int _prefetchStep = 20;
  MemorySnapshot? _snapshot;
  MemoryProgressState _progress = const MemoryProgressIdle();
  bool _refreshing = false;
  bool _initializingHistory = false;
  bool _clearing = false;
  bool _pausing = false;
  bool _waitingForInitialProgress = false;
  String? _preparingStageLabel;
  int _pendingVisible = _pageStep;
  int _confirmedVisible = _pageStep;
  int _eventVisible = _pageStep;
  MemorySnapshot? _bufferedSnapshot;
  final List<MemoryTag> _pendingTags = <MemoryTag>[];
  final List<MemoryTag> _confirmedTags = <MemoryTag>[];
  final List<MemoryEventSummary> _recentEvents = <MemoryEventSummary>[];
  final Map<int, MemoryTag> _tagIndex = <int, MemoryTag>{};
  int _pendingTotal = 0;
  int _confirmedTotal = 0;
  int _eventTotal = 0;
  bool _loadingPendingMore = false;
  bool _loadingConfirmedMore = false;

  StreamSubscription<MemorySnapshot>? _snapshotSub;
  StreamSubscription<MemoryProgressState>? _progressSub;
  StreamSubscription<MemoryTagUpdate>? _tagUpdateSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _logInfo('bootstrap start');
    await _service.ensureInitialized();
    if (!mounted) return;
    setState(() {
      _snapshot = _service.latestSnapshot ??
          MemorySnapshot(
            pendingTags: <MemoryTag>[],
            confirmedTags: <MemoryTag>[],
            recentEvents: <MemoryEventSummary>[],
            personaSummary: '',
          );
      _pendingTotal = _snapshot!.pendingTotalCount;
      _confirmedTotal = _snapshot!.confirmedTotalCount;
      _eventTotal = _snapshot!.recentEventTotalCount;
      if (_snapshot!.pendingTags.isNotEmpty) {
        _replaceLeadingTags(_pendingTags, _snapshot!.pendingTags);
      }
      if (_snapshot!.confirmedTags.isNotEmpty) {
        _replaceLeadingTags(_confirmedTags, _snapshot!.confirmedTags);
      }
      if (_snapshot!.recentEvents.isNotEmpty) {
        _replaceLeadingEvents(_recentEvents, _snapshot!.recentEvents);
      }
      _pendingVisible =
          _normalizeVisible(_pendingVisible, math.min(_pendingTags.length, _pendingTotal));
      _confirmedVisible =
          _normalizeVisible(_confirmedVisible, math.min(_confirmedTags.length, _confirmedTotal));
      _eventVisible =
          _normalizeVisible(_eventVisible, math.min(_recentEvents.length, _eventTotal));
      _progress = _service.latestProgress;
    });
    _snapshotSub = _service.snapshotStream.listen((MemorySnapshot snapshot) {
      if (!mounted) return;
      if (_progress is MemoryProgressRunning) {
        _bufferedSnapshot = snapshot;
        return;
      }
      _applySnapshot(snapshot);
    });
    _progressSub = _service.progressStream.listen((MemoryProgressState progress) {
      _logInfo('progressStream update ${_describeProgress(progress)}');
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _initializingHistory = progress is MemoryProgressRunning;
        if (progress is MemoryProgressRunning) {
          _waitingForInitialProgress = false;
          _preparingStageLabel = null;
        } else {
          _waitingForInitialProgress = false;
          _preparingStageLabel = null;
        }
      });
      if (progress is! MemoryProgressRunning && _bufferedSnapshot != null) {
        final MemorySnapshot snapshot = _bufferedSnapshot!;
        _bufferedSnapshot = null;
        _applySnapshot(snapshot);
      }
    });
    _tagUpdateSub = _service.tagUpdateStream.listen((MemoryTagUpdate update) {
      _logInfo(
        'tagUpdateStream tagId=${update.tag.id} isNew=${update.isNewTag} statusChanged=${update.statusChanged}',
      );
      if (!mounted) return;
      if (update.isNewTag) {
        UINotifier.info(context, AppLocalizations.of(context).memorySnapshotUpdated);
      }
    });
    unawaited(_runInitialSync());
    await _refresh(initial: true);
  }

  @override
  void dispose() {
    _snapshotSub?.cancel();
    _progressSub?.cancel();
    _tagUpdateSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool initial = false}) async {
    if (!mounted) return;
    setState(() => _refreshing = true);
    try {
      _logInfo('fetchSnapshot start initial=$initial');
      final MemorySnapshot? snap = await _service.fetchSnapshot();
      if (!mounted) return;
      if (!initial && snap != null) {
        UINotifier.info(context, AppLocalizations.of(context).memorySnapshotUpdated);
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      UINotifier.error(context, AppLocalizations.of(context).memoryConfirmFailedToast(e.message ?? 'error'));
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, AppLocalizations.of(context).memoryConfirmFailedToast(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _runInitialSync() async {
    try {
      final int segmentSynced = await _service.syncSegmentsToMemory();
      _logInfo('initial sync segment ingested=$segmentSynced');
      final int chatSynced = await _service.syncAllConversationsToMemory();
      _logInfo('initial sync chat ingested=$chatSynced');
      if (!mounted) return;
      await _refresh(initial: false);
    } catch (e) {
      _logInfo('initial sync failed: $e');
    }
  }

  Future<void> _confirmTag(MemoryTag tag) async {
    if (_confirmingTagIds.contains(tag.id)) {
      _logInfo('confirmTag ignored (already running) tagId=${tag.id}');
      return;
    }
    _logInfo('confirmTag start tagId=${tag.id}');
    setState(() => _confirmingTagIds.add(tag.id));
    try {
      final MemoryTag? updated = await _service.confirmTag(tag.id);
      if (!mounted) return;
      _logInfo('confirmTag success tagId=${tag.id} status=${(updated ?? tag).status}');
      UINotifier.success(
        context,
        AppLocalizations.of(context).memoryConfirmSuccessToast((updated ?? tag).label),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).memoryConfirmFailedToast(e.message ?? 'error'),
      );
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).memoryConfirmFailedToast(e.toString()),
      );
    } finally {
      if (mounted) {
        setState(() => _confirmingTagIds.remove(tag.id));
      }
    }
  }

  Future<void> _confirmDeleteTag(MemoryTag tag) async {
    if (_deletingTagIds.contains(tag.id)) {
      return;
    }
    final AppLocalizations t = AppLocalizations.of(context);
    final bool? confirmed = await showUIDialog<bool>(
      context: context,
      title: t.memoryDeleteTagConfirmTitle,
      message: t.memoryDeleteTagConfirmMessage(tag.label),
      actions: [
        UIDialogAction(text: t.dialogCancel),
        UIDialogAction(
          text: t.actionDelete,
          style: UIDialogActionStyle.destructive,
          result: true,
        ),
      ],
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _deletingTagIds.add(tag.id));
    try {
      final bool removed = await _service.deleteTag(tag.id);
      if (!mounted) return;
      if (removed) {
        setState(() {
          _handleTagRemoved(tag.id);
        });
        UINotifier.success(context, t.memoryDeleteTagSuccess);
        unawaited(_refresh(initial: true));
      } else {
        UINotifier.error(context, t.memoryDeleteTagFailed('not_removed'));
      }
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, t.memoryDeleteTagFailed(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _deletingTagIds.remove(tag.id));
      } else {
        _deletingTagIds.remove(tag.id);
      }
    }
  }

  Future<void> _startHistoricalProcessing({required bool forceReprocess}) async {
    if (_initializingHistory) {
      _logInfo('startHistoricalProcessing skipped (busy) force=$forceReprocess');
      return;
    }
    _logInfo('startHistoricalProcessing request force=$forceReprocess');
    final AppLocalizations t = AppLocalizations.of(context);
    setState(() {
      _initializingHistory = true;
      _waitingForInitialProgress = true;
      _preparingStageLabel = t.memoryProgressStageSyncSegments;
      _progress = MemoryProgressRunning(
        processedCount: 0,
        totalCount: 0,
        progress: 0,
        currentEventId: null,
        currentEventExternalId: null,
        currentEventType: null,
        newlyDiscoveredTags: const <String>[],
      );
    });
    try {
      final int segmentSynced = await _service.syncSegmentsToMemory();
      _logInfo('startHistoricalProcessing segment sync ingested=$segmentSynced');
      if (mounted) {
        setState(() => _preparingStageLabel = t.memoryProgressStageSyncChats);
      }
      final int chatSynced = await _service.syncAllConversationsToMemory();
      _logInfo('startHistoricalProcessing chat sync ingested=$chatSynced');
      if (mounted) {
        setState(() => _preparingStageLabel = t.memoryProgressStageDispatch);
      }
      await _service.startHistoricalProcessing(forceReprocess: forceReprocess);
      if (!mounted) return;
      _logInfo('startHistoricalProcessing dispatched force=$forceReprocess');
      UINotifier.success(
        context,
        t.memoryStartProcessingToast,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _waitingForInitialProgress = false;
        _preparingStageLabel = null;
        _progress = const MemoryProgressIdle();
      });
      UINotifier.error(
        context,
        t.memoryConfirmFailedToast(e.message ?? 'error'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _waitingForInitialProgress = false;
        _preparingStageLabel = null;
        _progress = const MemoryProgressIdle();
      });
      UINotifier.error(
        context,
        t.memoryConfirmFailedToast(e.toString()),
      );
    } finally {
      if (mounted) {
        setState(() {
          _initializingHistory = _progress is MemoryProgressRunning;
        });
        _logInfo('startHistoricalProcessing finished force=$forceReprocess');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final MemorySnapshot snapshot =
        _snapshot ??
        MemorySnapshot(
          pendingTags: <MemoryTag>[],
          confirmedTags: <MemoryTag>[],
          recentEvents: <MemoryEventSummary>[],
          personaSummary: '',
        );
    final Map<int, MemoryTag> tagLookup = Map<int, MemoryTag>.from(_tagIndex);
    final bool pendingHasMore = _pendingVisible < _pendingTotal;
    final bool confirmedHasMore = _confirmedVisible < _confirmedTotal;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.memoryCenterTitle),
        actions: [
          IconButton(
            tooltip: t.copyPersonaTooltip,
            onPressed: () => _copyPersonaSummary(t),
            icon: const Icon(Icons.copy_outlined),
          ),
          IconButton(
            tooltip: t.memoryPauseTooltip,
            onPressed: (!_initializingHistory && _progress is! MemoryProgressRunning) || _pausing
                ? null
                : _pauseProcessing,
            icon: _pausing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                    ),
                  )
                : const Icon(Icons.pause_circle_outline),
          ),
          IconButton(
            tooltip: t.memoryClearAllTooltip,
            onPressed: (_refreshing || _clearing) ? null : _confirmClearMemory,
            icon: _clearing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                    ),
                  )
                : const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(),
        child: ListView(
          padding: EdgeInsets.zero,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: AppTheme.spacing4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
              child: _buildHeroSection(context, snapshot),
            ),
            const SizedBox(height: AppTheme.spacing4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
              child: _buildProgressCard(context),
            ),
            const SizedBox(height: AppTheme.spacing4),
            _buildTagSection(
              context: context,
              title: t.memoryPendingSectionTitle,
              emptyText: t.memoryNoPending,
              tags: _pendingTags,
              showConfirmAction: true,
              totalCount: _pendingTotal,
              visibleCount: _pendingVisible,
              onTap: _openTagDetail,
              onLoadMore: pendingHasMore ? _loadMorePending : null,
              isLoadingMore: _loadingPendingMore,
            ),
            const SizedBox(height: AppTheme.spacing4),
            _buildTagSection(
              context: context,
              title: t.memoryConfirmedSectionTitle,
              emptyText: t.memoryNoConfirmed,
              tags: _confirmedTags,
              showConfirmAction: false,
              totalCount: _confirmedTotal,
              visibleCount: _confirmedVisible,
              onTap: _openTagDetail,
              onLoadMore: confirmedHasMore ? _loadMoreConfirmed : null,
              isLoadingMore: _loadingConfirmedMore,
            ),
            const SizedBox(height: AppTheme.spacing4),
            const SizedBox(height: AppTheme.spacing8),
          ],
        ),
      ),
    );
  }

  Future<void> _pauseProcessing() async {
    if (_pausing) return;
    final AppLocalizations t = AppLocalizations.of(context);
    setState(() => _pausing = true);
    try {
      await _service.cancelInitialization();
      await _service.fetchSnapshot();
      if (!mounted) return;
      setState(() {
        _initializingHistory = false;
        _waitingForInitialProgress = false;
        _preparingStageLabel = null;
      });
      UINotifier.info(context, t.memoryPauseSuccess);
    } on PlatformException catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        t.memoryPauseFailed(e.message ?? 'PlatformException'),
      );
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, t.memoryPauseFailed(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _pausing = false);
      }
    }
  }

  Future<void> _confirmClearMemory() async {
    final AppLocalizations t = AppLocalizations.of(context);
    final bool confirmed = await showUIDialog<bool>(
          context: context,
          title: t.memoryClearAllConfirmTitle,
          message: t.memoryClearAllConfirmMessage,
          actions: [
            UIDialogAction(text: t.dialogCancel),
            UIDialogAction(
              text: t.actionClear,
              style: UIDialogActionStyle.destructive,
              onPressed: (dialogCtx) async {
                Navigator.of(dialogCtx).pop(true);
              },
            ),
          ],
        ) ??
        false;
    if (!confirmed) return;
    await _clearMemoryData();
  }

  Future<void> _clearMemoryData() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    final AppLocalizations t = AppLocalizations.of(context);
    try {
      await _service.clearMemoryData();
      await _service.fetchSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = MemorySnapshot(
          pendingTags: const <MemoryTag>[],
          confirmedTags: const <MemoryTag>[],
          recentEvents: const <MemoryEventSummary>[],
          lastUpdatedAt: DateTime.now(),
          personaSummary: '',
        );
        _pendingTags.clear();
        _confirmedTags.clear();
        _recentEvents.clear();
        _tagIndex.clear();
        _pendingTotal = 0;
        _confirmedTotal = 0;
        _eventTotal = 0;
        _pendingVisible = _pageStep;
        _confirmedVisible = _pageStep;
        _eventVisible = _pageStep;
      });
      UINotifier.success(context, t.clearSuccess);
    } on PlatformException catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        t.clearFailedWithError(e.message ?? 'PlatformException'),
      );
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(context, t.clearFailedWithError(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
      }
    }
  }

  Widget _buildHeroSection(BuildContext context, MemorySnapshot snapshot) {
    final AppLocalizations t = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String rawSummary = snapshot.personaSummary;
    final bool hasSummary = rawSummary.trim().isNotEmpty;
    final String displaySummary = _composePersonaSummaryText(rawSummary, t);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.6)),
      ),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasSummary)
            MarkdownBody(
              data: displaySummary,
              shrinkWrap: true,
              selectable: false,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.4,
                ),
                h3: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
                listBullet: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            )
          else
            Text(
              displaySummary.replaceAll('**', ''),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  String _composePersonaSummaryText(String rawSummary, AppLocalizations t) {
    final String trimmed = rawSummary.trim();
    if (trimmed.isEmpty) {
      return '**画像概览**\n\n${t.memoryPersonaEmptyPlaceholder}';
    }
    return trimmed;
  }

  Widget _buildGradientTagPill(BuildContext context, String tag, double maxWidth) {
    final ThemeData theme = Theme.of(context);
    final Brightness brightness = theme.brightness;
    final List<Color> colors = _geminiGradientColors(brightness);
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: AppTheme.spacing1,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (Rect bounds) => LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[colors[2], colors[6], colors[8]],
              stops: const <double>[0.0, 0.55, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: const Icon(
              Icons.auto_awesome,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppTheme.spacing1),
          Flexible(
            child: Text(
              tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _geminiGradientColors(Brightness brightness) {
    Color tune(
      Color c, {
      double sMinLight = 0.98,
      double sMinDark = 0.96,
      double lMinLight = 0.80,
      double lMinDark = 0.72,
    }) {
      final HSLColor h = HSLColor.fromColor(c);
      final double sTarget = brightness == Brightness.dark ? sMinDark : sMinLight;
      final double lTarget = brightness == Brightness.dark ? lMinDark : lMinLight;
      final double s = h.saturation < sTarget ? sTarget : h.saturation;
      final double l = h.lightness < lTarget ? lTarget : h.lightness;
      return h.withSaturation(s).withLightness(l).toColor();
    }

    final Color c1 = tune(const Color(0xFF1F6FEB));
    final Color c2 = tune(const Color(0xFF3B82F6));
    final Color c3 = tune(const Color(0xFF60A5FA));
    final Color c4 = tune(const Color(0xFF7C83FF));
    final Color cY = tune(const Color(0xFFF59E0B), lMinLight: 0.86, lMinDark: 0.76);
    return <Color>[
      c1,
      Color.lerp(c1, c2, 0.5)!,
      c2,
      Color.lerp(c2, c3, 0.5)!,
      c3,
      Color.lerp(c3, c4, 0.5)!,
      c4,
      Color.lerp(c4, cY, 0.45)!,
      cY,
    ];
  }

  Future<void> _copyPersonaSummary(AppLocalizations t) async {
    final String displaySummary = _composePersonaSummaryText(_snapshot?.personaSummary ?? '', t);
    try {
      await Clipboard.setData(ClipboardData(text: displaySummary));
      if (!mounted) return;
      UINotifier.success(context, t.copySuccess);
    } catch (_) {
      if (!mounted) return;
      UINotifier.error(context, t.copyFailed);
    }
  }

  Widget _buildStatCard({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required Color accent,
  }) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: AppTheme.spacing2),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    final AppLocalizations t = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final MemoryProgressState progress = _progress;

    if (progress is MemoryProgressRunning) {
      final bool waiting = _waitingForInitialProgress;
      final String? stageLabel = _preparingStageLabel;
      final double percent = (progress.safeProgress * 100).clamp(0, 100);
      final String percentText = percent >= 10 ? percent.toStringAsFixed(0) : percent.toStringAsFixed(1);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.memoryProgressRunning,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppTheme.spacing3),
              LinearProgressIndicator(
                value: waiting ? null : progress.safeProgress,
                minHeight: 6,
              ),
              const SizedBox(height: AppTheme.spacing3),
              if (waiting && stageLabel != null)
                Text(
                  t.memoryProgressPreparing(stageLabel),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
              Text(
                t.memoryProgressRunningDetail(
                  progress.processedCount,
                  progress.totalCount,
                  percentText,
                ),
                style: theme.textTheme.bodyMedium,
              ),
              if (progress.newlyDiscoveredTags.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacing2),
                Text(
                  t.memoryProgressNewTagsDetail(progress.newlyDiscoveredTags.length),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: AppTheme.spacing2),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double maxWidth = math.min(constraints.maxWidth, 520);
                    return Wrap(
                      spacing: AppTheme.spacing2,
                      runSpacing: AppTheme.spacing2,
                      children: progress.newlyDiscoveredTags
                          .map((String tag) => _buildGradientTagPill(context, tag, maxWidth))
                          .toList(),
                    );
                  },
                ),
                ],
              ],
            ],
          ),
        ),
      );
    }

    if (progress is MemoryProgressCompleted) {
      final int seconds = progress.duration.inSeconds;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppTheme.spacing2,
                runSpacing: AppTheme.spacing2,
                children: [
                  FilledButton.icon(
                    onPressed: _initializingHistory
                        ? null
                        : () => _startHistoricalProcessing(forceReprocess: false),
                    icon: _initializingHistory
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.colorScheme.onPrimary,
                              ),
                            ),
                          )
                        : const Icon(Icons.play_arrow_rounded, size: 18),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                    ),
                    label: Text(t.memoryStartProcessingActionShort),
                  ),
                  OutlinedButton.icon(
                    onPressed: _initializingHistory
                        ? null
                        : () => _startHistoricalProcessing(forceReprocess: true),
                    icon: const Icon(Icons.restart_alt_outlined, size: 18),
                    label: Text(t.memoryReprocessAction),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacing3),
              Text(
                t.memoryProgressCompleted(progress.totalCount, seconds),
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    if (progress is MemoryProgressFailed) {
      final String headerText = t.memoryProgressFailed(progress.errorMessage);
      final String? subtitle = progress.failedEventExternalId?.isNotEmpty == true
          ? t.memoryProgressFailedEvent(progress.failedEventExternalId!)
          : null;
      final String? raw = progress.rawResponse?.trim();

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Wrap(
                    spacing: AppTheme.spacing2,
                    runSpacing: AppTheme.spacing2,
                    children: [
                      FilledButton.icon(
                        onPressed: _initializingHistory
                            ? null
                            : () => _startHistoricalProcessing(forceReprocess: false),
                        icon: _initializingHistory
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    theme.colorScheme.onPrimary,
                                  ),
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded, size: 18),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          ),
                        ),
                        label: Text(t.memoryStartProcessingActionShort),
                      ),
                      OutlinedButton.icon(
                        onPressed: _initializingHistory
                            ? null
                            : () => _startHistoricalProcessing(forceReprocess: true),
                        icon: const Icon(Icons.restart_alt_outlined, size: 18),
                        label: Text(t.memoryReprocessAction),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacing3),
              Text(
                headerText,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppTheme.spacing2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (raw != null && raw.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacing3),
                Text(
                  t.memoryMalformedResponseRawLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing1),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTheme.spacing3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                    ),
                  ),
                  child: SelectableText(
                    raw,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                t.memoryProgressIdle,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: AppTheme.spacing3),
            FilledButton.icon(
              onPressed: _initializingHistory
                  ? null
                  : () => _startHistoricalProcessing(forceReprocess: false),
              icon: _initializingHistory
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.onPrimary,
                        ),
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
              ),
              label: Text(t.memoryStartProcessingActionShort),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagSection({
    required BuildContext context,
    required String title,
    required String emptyText,
    required List<MemoryTag> tags,
    required bool showConfirmAction,
    required int visibleCount,
    required int totalCount,
    required ValueChanged<MemoryTag> onTap,
    VoidCallback? onLoadMore,
    bool isLoadingMore = false,
  }) {
    final ThemeData theme = Theme.of(context);
    final int safeVisible = math.min(visibleCount, math.min(tags.length, totalCount));
    final List<MemoryTag> displayTags = tags.take(safeVisible).toList();
    final bool canLoadMore = onLoadMore != null && safeVisible < totalCount;
    final Color statusColor =
        showConfirmAction ? theme.colorScheme.errorContainer : theme.colorScheme.secondaryContainer;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: AppTheme.spacing2),
              Expanded(
                child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                totalCount.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacing3),
          if (totalCount == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.spacing4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              child: Text(
                emptyText,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else if (displayTags.isNotEmpty)
                TagHierarchyTree(
                  tags: displayTags,
                  showConfirmAction: showConfirmAction,
                  onTapTag: onTap,
                  onConfirmTag: _confirmTag,
                  onDeleteTag: _confirmDeleteTag,
                  deletingTagIds: _deletingTagIds,
                  confirmingTagIds: _confirmingTagIds,
            ),
          if (displayTags.isEmpty && totalCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing2),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  ),
                ),
              ),
            ),
          if (canLoadMore) ...[
            const SizedBox(height: AppTheme.spacing2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: isLoadingMore ? null : onLoadMore,
                child: isLoadingMore
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacing2),
                          Text(AppLocalizations.of(context).memoryLoadMore),
                        ],
                      )
                    : Text(AppLocalizations.of(context).memoryLoadMore),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      labelStyle: Theme.of(context).textTheme.bodySmall,
    );
  }

  int _normalizeVisible(int current, int total) {
    if (total == 0) return 0;
    final int minimum = math.min(_pageStep, total);
    if (current <= 0) return minimum;
    if (current < minimum) return minimum;
    return math.min(current, total);
  }

  int _increaseVisible(int current, int total) {
    if (total == 0) return 0;
    if (current <= 0) return math.min(_pageStep, total);
    return math.min(total, current + _pageStep);
  }

  String _describeProgress(MemoryProgressState progress) {
    if (progress is MemoryProgressRunning) {
      return 'running processed=${progress.processedCount}/${progress.totalCount} progress=${progress.safeProgress.toStringAsFixed(3)} currentEventId=${progress.currentEventId}';
    }
    if (progress is MemoryProgressCompleted) {
      return 'completed total=${progress.totalCount} duration=${progress.duration.inMilliseconds}ms';
    }
    if (progress is MemoryProgressFailed) {
      return 'failed processed=${progress.processedCount}/${progress.totalCount} error=${progress.errorMessage}';
    }
    return 'idle';
  }

  Future<void> _loadMorePending() async {
    if (_loadingPendingMore || _pendingVisible >= _pendingTotal) return;
    final int target = math.min(_pendingVisible + _pageStep, _pendingTotal);
    if (target <= _pendingVisible) return;
    if (_pendingTags.length >= target) {
      setState(() => _pendingVisible = target);
      return;
    }
    setState(() => _loadingPendingMore = true);
    try {
      final int offset = _pendingTags.length;
      final int limit = math.max(_pageStep, target - _pendingTags.length + _prefetchStep);
      final List<MemoryTag> fetched = await _service.loadTags(
        status: MemoryTagStatus.pending,
        offset: offset,
        limit: limit,
      );
      if (!mounted) return;
      setState(() {
        _appendTags(_pendingTags, fetched);
        _pendingVisible = math.min(target, _pendingTags.length);
        _loadingPendingMore = false;
      });
    } catch (e) {
      _logInfo('loadMorePending failed: $e');
      if (mounted) {
        setState(() => _loadingPendingMore = false);
      } else {
        _loadingPendingMore = false;
      }
    }
  }

  Future<void> _loadMoreConfirmed() async {
    if (_loadingConfirmedMore || _confirmedVisible >= _confirmedTotal) return;
    final int target = math.min(_confirmedVisible + _pageStep, _confirmedTotal);
    if (target <= _confirmedVisible) return;
    if (_confirmedTags.length >= target) {
      setState(() => _confirmedVisible = target);
      return;
    }
    setState(() => _loadingConfirmedMore = true);
    try {
      final int offset = _confirmedTags.length;
      final int limit = math.max(_pageStep, target - _confirmedTags.length + _prefetchStep);
      final List<MemoryTag> fetched = await _service.loadTags(
        status: MemoryTagStatus.confirmed,
        offset: offset,
        limit: limit,
      );
      if (!mounted) return;
      setState(() {
        _appendTags(_confirmedTags, fetched);
        _confirmedVisible = math.min(target, _confirmedTags.length);
        _loadingConfirmedMore = false;
      });
    } catch (e) {
      _logInfo('loadMoreConfirmed failed: $e');
      if (mounted) {
        setState(() => _loadingConfirmedMore = false);
      } else {
        _loadingConfirmedMore = false;
      }
    }
  }

  void _applySnapshot(MemorySnapshot snapshot) {
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _pendingTotal = snapshot.pendingTotalCount;
      _confirmedTotal = snapshot.confirmedTotalCount;
      _eventTotal = snapshot.recentEventTotalCount;

      if (snapshot.pendingTags.isNotEmpty || _pendingTags.isEmpty) {
        _replaceLeadingTags(_pendingTags, snapshot.pendingTags);
      }
      if (snapshot.confirmedTags.isNotEmpty || _confirmedTags.isEmpty) {
        _replaceLeadingTags(_confirmedTags, snapshot.confirmedTags);
      }
      if (snapshot.recentEvents.isNotEmpty || _recentEvents.isEmpty) {
        _replaceLeadingEvents(_recentEvents, snapshot.recentEvents);
      }

      _pendingVisible = _normalizeVisible(
        _pendingVisible,
        math.min(_pendingTags.length, _pendingTotal),
      );
      _confirmedVisible = _normalizeVisible(
        _confirmedVisible,
        math.min(_confirmedTags.length, _confirmedTotal),
      );
      _eventVisible = _normalizeVisible(
        _eventVisible,
        math.min(_recentEvents.length, _eventTotal),
      );
    });
  }

  void _replaceLeadingTags(List<MemoryTag> target, List<MemoryTag> incoming) {
    if (incoming.isEmpty) return;
    final Set<int> incomingIds = incoming.map((e) => e.id).toSet();
    target.removeWhere((tag) => incomingIds.contains(tag.id));
    target.insertAll(0, incoming);
    for (final MemoryTag tag in incoming) {
      _tagIndex[tag.id] = tag;
    }
  }

  void _appendTags(List<MemoryTag> target, List<MemoryTag> incoming) {
    if (incoming.isEmpty) return;
    final Set<int> existingIds = target.map((e) => e.id).toSet();
    for (final MemoryTag tag in incoming) {
      if (existingIds.add(tag.id)) {
        target.add(tag);
        _tagIndex[tag.id] = tag;
      } else {
        _tagIndex[tag.id] = tag;
      }
    }
  }

  void _replaceLeadingEvents(List<MemoryEventSummary> target, List<MemoryEventSummary> incoming) {
    if (incoming.isEmpty) return;
    final Set<int> incomingIds = incoming.map((e) => e.id).toSet();
    target.removeWhere((event) => incomingIds.contains(event.id));
    target.insertAll(0, incoming);
  }

  void _appendEvents(List<MemoryEventSummary> target, List<MemoryEventSummary> incoming) {
    if (incoming.isEmpty) return;
    final Set<int> existingIds = target.map((e) => e.id).toSet();
    for (final MemoryEventSummary event in incoming) {
      if (existingIds.add(event.id)) {
        target.add(event);
      }
    }
  }

  void _handleTagRemoved(int tagId) {
    _tagIndex.remove(tagId);
    final bool removedPending = _removeTagFromCollection(_pendingTags, tagId);
    final bool removedConfirmed = _removeTagFromCollection(_confirmedTags, tagId);
    if (!removedPending && !removedConfirmed) {
      return;
    }
    if (removedPending) {
      _pendingTotal = math.max(0, _pendingTotal - 1);
      _pendingVisible = _normalizeVisible(
        _pendingVisible,
        math.min(_pendingTags.length, _pendingTotal),
      );
    }
    if (removedConfirmed) {
      _confirmedTotal = math.max(0, _confirmedTotal - 1);
      _confirmedVisible = _normalizeVisible(
        _confirmedVisible,
        math.min(_confirmedTags.length, _confirmedTotal),
      );
    }
  }

  bool _removeTagFromCollection(List<MemoryTag> target, int tagId) {
    final int index = target.indexWhere((tag) => tag.id == tagId);
    if (index == -1) {
      return false;
    }
    target.removeAt(index);
    return true;
  }

  void _openTagDetail(MemoryTag tag) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TagDetailPage(
          tagId: tag.id,
          initialTag: tag,
        ),
      ),
    );
  }

  void _logInfo(String message) {
    try {
      FlutterLogger.nativeInfo('MemoryCenterPage', message);
    } catch (_) {}
  }
}

