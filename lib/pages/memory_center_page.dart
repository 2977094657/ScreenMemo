import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import '../models/memory_models.dart';
import '../services/ai_providers_service.dart';
import '../services/ai_settings_service.dart';
import '../services/flutter_logger.dart';
import '../services/memory_bridge_service.dart';
import '../services/persona_article_service.dart';
import '../services/ai_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/model_icon_utils.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import 'memory_request_debug_page.dart';

class MemoryCenterPage extends StatefulWidget {
  const MemoryCenterPage({super.key});

  @override
  State<MemoryCenterPage> createState() => _MemoryCenterPageState();
}

class _MemoryCenterPageState extends State<MemoryCenterPage> {
  final MemoryBridgeService _service = MemoryBridgeService.instance;
  final PersonaArticleService _articleService = PersonaArticleService.instance;
  final AISettingsService _settings = AISettingsService.instance;
  final AIProvidersService _providers = AIProvidersService.instance;
  AIProvider? _memoryProvider;
  String? _memoryModel;
  bool _memoryCtxLoading = true;
  StreamSubscription<String>? _ctxChangedSub;

  static const int _pageStep = 10;
  MemorySnapshot? _snapshot;
  MemoryProgressState _progress = const MemoryProgressIdle();
  bool _refreshing = false;
  bool _initializingHistory = false;
  bool _clearing = false;
  bool _pausing = false;
  bool _waitingForInitialProgress = false;
  String? _preparingStageLabel;
  int _eventVisible = _pageStep;
  MemorySnapshot? _bufferedSnapshot;
  final List<MemoryEventSummary> _recentEvents = <MemoryEventSummary>[];
  int _eventTotal = 0;

  StreamSubscription<MemorySnapshot>? _snapshotSub;
  StreamSubscription<MemoryProgressState>? _progressSub;
  StreamSubscription<AIStreamEvent>? _articleSubscription;
  String _article = '';
  bool _articleGenerating = false;
  String? _articleError;
  String _lastPersonaSummary = '';
  final List<String> _articleLogs = <String>[];

  @override
  void initState() {
    super.initState();
    _ctxChangedSub = _settings.onContextChanged.listen((String contextName) {
      if (contextName == 'memory' && mounted) {
        _loadMemoryContextSelection();
      }
    });
    unawaited(ModelIconUtils.preload());
    unawaited(_loadMemoryContextSelection());
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _logInfo('启动初始化开始');
    await _service.ensureInitialized();
    if (!mounted) return;
    final MemoryProgressState cachedProgress = _service.latestProgress;
    final bool progressRunning = cachedProgress is MemoryProgressRunning;
    final bool waitingFlag = progressRunning
        ? _service.waitingForInitialProgress
        : false;
    final String? stageLabel = progressRunning
        ? _service.pendingStageLabel
        : null;
    final PersonaArticleCache? cachedArticle = await _articleService
        .loadCachedArticle();
    setState(() {
      _snapshot =
          _service.latestSnapshot ??
          MemorySnapshot(
            recentEvents: <MemoryEventSummary>[],
            personaSummary: '',
          );
      _eventTotal = _snapshot!.recentEventTotalCount;
      if (_snapshot!.recentEvents.isNotEmpty) {
        _replaceLeadingEvents(_recentEvents, _snapshot!.recentEvents);
      }
      _eventVisible = _normalizeVisible(
        _eventVisible,
        math.min(_recentEvents.length, _eventTotal),
      );
      _progress = cachedProgress;
      _initializingHistory = progressRunning;
      _waitingForInitialProgress = waitingFlag;
      _preparingStageLabel = stageLabel;
      if (cachedArticle != null &&
          cachedArticle.article.trim().isNotEmpty &&
          _article.trim().isEmpty) {
        _article = cachedArticle.article;
      }
    });
    _lastPersonaSummary = _snapshot?.personaSummary.trim() ?? '';
    _snapshotSub = _service.snapshotStream.listen((MemorySnapshot snapshot) {
      if (!mounted) return;
      if (_progress is MemoryProgressRunning) {
        _bufferedSnapshot = snapshot;
        _handlePersonaSummaryChange(snapshot.personaSummary);
        return;
      }
      _applySnapshot(snapshot);
    });
    _progressSub = _service.progressStream.listen((
      MemoryProgressState progress,
    ) {
      _logInfo('progressStream 状态更新 ${_describeProgress(progress)}');
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _initializingHistory = progress is MemoryProgressRunning;
        if (progress is MemoryProgressRunning) {
          _waitingForInitialProgress = _service.waitingForInitialProgress;
          _preparingStageLabel = _service.pendingStageLabel;
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
      if (progress is MemoryProgressCompleted) {
        _appendArticleLog('解析完成，触发画像文章再生成');
        _scheduleArticleRegeneration(force: true);
      }
    });
    unawaited(_runInitialSync());
    await _refresh(initial: true);
  }

  Future<void> _loadMemoryContextSelection() async {
    if (!mounted) return;
    setState(() => _memoryCtxLoading = true);
    try {
      final List<AIProvider> providers = await _providers.listProviders();
      if (!mounted) return;
      if (providers.isEmpty) {
        setState(() {
          _memoryProvider = null;
          _memoryModel = null;
          _memoryCtxLoading = false;
        });
        await _service.setExtractionContext(provider: null, model: null);
        return;
      }

      final Map<String, dynamic>? ctxRow = await _settings.getAIContextRow(
        'memory',
      );
      AIProvider? provider;
      String model = '';
      bool needPersist = false;
      if (ctxRow != null && ctxRow['provider_id'] is int) {
        final int ctxProviderId = ctxRow['provider_id'] as int;
        for (final AIProvider candidate in providers) {
          if ((candidate.id ?? -1) == ctxProviderId) {
            provider = candidate;
            break;
          }
        }
        if (provider == null) {
          provider = providers.firstWhere(
            (p) => p.isDefault,
            orElse: () => providers.first,
          );
          needPersist = true;
        }
        final String? storedModel = ctxRow['model'] as String?;
        if (storedModel != null && storedModel.trim().isNotEmpty) {
          model = storedModel.trim();
        }
      } else {
        provider = providers.firstWhere(
          (p) => p.isDefault,
          orElse: () => providers.first,
        );
        needPersist = true;
      }

      provider ??= providers.first;
      if (model.isEmpty) {
        model =
            ((provider.extra['active_model'] as String?) ??
                    provider.defaultModel)
                .toString()
                .trim();
      }
      final List<String> available = provider.models;
      if (model.isEmpty && available.isNotEmpty) {
        model = available.first;
        needPersist = true;
      }
      if (available.isNotEmpty &&
          model.isNotEmpty &&
          !available.contains(model)) {
        final String fallback =
            ((provider.extra['active_model'] as String?) ??
                    provider.defaultModel)
                .toString()
                .trim();
        if (fallback.isNotEmpty && available.contains(fallback)) {
          model = fallback;
        } else if (available.isNotEmpty) {
          model = available.first;
        }
        needPersist = true;
      }

      if (!mounted) return;
      setState(() {
        _memoryProvider = provider;
        _memoryModel = model;
        _memoryCtxLoading = false;
      });
      await _service.setExtractionContext(provider: provider, model: model);
      if (needPersist && provider.id != null && model.trim().isNotEmpty) {
        await _settings.setAIContextSelection(
          context: 'memory',
          providerId: provider.id!,
          model: model.trim(),
        );
      }
    } catch (e) {
      _logInfo('加载上下文选择失败：$e');
      if (!mounted) return;
      setState(() => _memoryCtxLoading = false);
      await _service.setExtractionContext(
        provider: _memoryProvider,
        model: _memoryModel,
      );
    }
  }

  Widget _buildMemoryAppBarTitle(BuildContext context) {
    if (_memoryCtxLoading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final ThemeData theme = Theme.of(context);
    final TextStyle? link = theme.textTheme.labelSmall?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.onSurface.withOpacity(0.6),
      color: theme.colorScheme.onSurface,
    );
    final String providerName = (_memoryProvider?.name ?? '').trim().isNotEmpty
        ? _memoryProvider!.name
        : '—';
    final String modelName = (_memoryModel ?? '').trim().isNotEmpty
        ? _memoryModel!.trim()
        : '—';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (modelName.trim().isNotEmpty && modelName != '—') ...[
          SvgPicture.asset(
            ModelIconUtils.getIconPath(modelName),
            width: 18,
            height: 18,
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: GestureDetector(
            onTap: _showMemoryProviderSheet,
            behavior: HitTestBehavior.opaque,
            child: Text(
              providerName,
              style: link,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: GestureDetector(
            onTap: _showMemoryModelSheet,
            behavior: HitTestBehavior.opaque,
            child: Text(
              modelName,
              style: link,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showMemoryProviderSheet() async {
    final AppLocalizations t = AppLocalizations.of(context);
    List<AIProvider> providers;
    try {
      providers = await _providers.listProviders();
    } catch (e) {
      _logInfo('打开提供商选择面板：获取列表失败：$e');
      providers = const <AIProvider>[];
    }
    if (!mounted) return;
    if (providers.isEmpty) {
      UINotifier.info(context, t.providerNotFound);
      return;
    }
    final int activeId = _memoryProvider?.id ?? -1;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        final double maxHeight = MediaQuery.of(context).size.height * 0.7;
        return UISheetSurface(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              children: [
                const SizedBox(height: AppTheme.spacing3),
                const UISheetHandle(),
                const SizedBox(height: AppTheme.spacing3),
                Expanded(
                  child: ListView.separated(
                    itemCount: providers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext itemContext, int index) {
                      final AIProvider provider = providers[index];
                      final bool selected =
                          (provider.id ?? -1) == activeId && activeId != -1;
                      return ListTile(
                        leading: SvgPicture.asset(
                          ModelIconUtils.getProviderIconPath(provider.type),
                          width: 20,
                          height: 20,
                        ),
                        title: Text(provider.name),
                        subtitle:
                            (provider.baseUrl != null &&
                                provider.baseUrl!.trim().isNotEmpty)
                            ? Text(
                                provider.baseUrl!.trim(),
                                style: Theme.of(
                                  itemContext,
                                ).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: selected
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(
                                  itemContext,
                                ).colorScheme.primary,
                              )
                            : null,
                        onTap: provider.id == null
                            ? null
                            : () async {
                                String nextModel = (_memoryModel ?? '').trim();
                                final List<String> available = provider.models;
                                if (nextModel.isEmpty ||
                                    (available.isNotEmpty &&
                                        !available.contains(nextModel))) {
                                  String fallback =
                                      ((provider.extra['active_model']
                                                  as String?) ??
                                              provider.defaultModel)
                                          .toString()
                                          .trim();
                                  if (fallback.isEmpty &&
                                      available.isNotEmpty) {
                                    fallback = available.first;
                                  }
                                  nextModel = fallback;
                                }
                                await _settings.setAIContextSelection(
                                  context: 'memory',
                                  providerId: provider.id!,
                                  model: nextModel.trim(),
                                );
                                if (!mounted) return;
                                setState(() {
                                  _memoryProvider = provider;
                                  _memoryModel = nextModel;
                                });
                                await _service.setExtractionContext(
                                  provider: provider,
                                  model: nextModel,
                                );
                                Navigator.of(sheetContext).pop();
                                UINotifier.success(
                                  context,
                                  t.providerSelectedToast(provider.name),
                                );
                              },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showMemoryModelSheet() async {
    final AppLocalizations t = AppLocalizations.of(context);
    final AIProvider? provider = _memoryProvider;
    if (provider == null || provider.id == null) {
      UINotifier.info(context, t.pleaseSelectProviderFirst);
      return;
    }
    final List<String> models = provider.models;
    if (models.isEmpty) {
      UINotifier.info(context, t.noModelsForProviderHint);
      return;
    }
    final String active = (_memoryModel ?? '').trim();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        final double maxHeight = MediaQuery.of(context).size.height * 0.7;
        return UISheetSurface(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              children: [
                const SizedBox(height: AppTheme.spacing3),
                const UISheetHandle(),
                const SizedBox(height: AppTheme.spacing3),
                Expanded(
                  child: ListView.separated(
                    itemCount: models.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext itemContext, int index) {
                      final String model = models[index];
                      final bool selected = model == active;
                      return ListTile(
                        leading: SvgPicture.asset(
                          ModelIconUtils.getIconPath(model),
                          width: 20,
                          height: 20,
                        ),
                        title: Text(model),
                        trailing: selected
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(
                                  itemContext,
                                ).colorScheme.primary,
                              )
                            : null,
                        onTap: () async {
                          await _settings.setAIContextSelection(
                            context: 'memory',
                            providerId: provider.id!,
                            model: model,
                          );
                          if (!mounted) return;
                          setState(() => _memoryModel = model);
                          await _service.setExtractionContext(
                            provider: provider,
                            model: model,
                          );
                          Navigator.of(sheetContext).pop();
                          UINotifier.success(
                            context,
                            t.modelSwitchedToast(model),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _ctxChangedSub?.cancel();
    _snapshotSub?.cancel();
    _progressSub?.cancel();
    _articleSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool initial = false}) async {
    if (!mounted) return;
    setState(() => _refreshing = true);
    try {
      _logInfo('获取快照开始 初始=$initial');
      final MemorySnapshot? snap = await _service.fetchSnapshot();
      if (!mounted) return;
      if (!initial && snap != null) {
        UINotifier.info(
          context,
          AppLocalizations.of(context).memorySnapshotUpdated,
        );
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(
          context,
        ).memoryConfirmFailedToast(e.message ?? 'error'),
      );
    } catch (e) {
      if (!mounted) return;
      UINotifier.error(
        context,
        AppLocalizations.of(context).memoryConfirmFailedToast(e.toString()),
      );
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _runInitialSync() async {
    try {
      final int segmentSynced = await _service.syncSegmentsToMemory();
      _logInfo('初始同步：动态导入=$segmentSynced');
      final int chatSynced = await _service.syncAllConversationsToMemory();
      _logInfo('初始同步：聊天导入=$chatSynced');
      if (!mounted) return;
      await _refresh(initial: false);
    } catch (e) {
      _logInfo('初始同步失败：$e');
    }
  }

  Future<void> _regenerateArticle({bool force = false}) async {
    _appendArticleLog('收到画像文章生成请求 强制=$force 生成中=$_articleGenerating');
    if (_articleGenerating && !force) {
      _appendArticleLog('已有生成任务在执行，跳过此次触发');
      return;
    }
    await _articleSubscription?.cancel();
    setState(() {
      _article = '';
      _articleError = null;
      _articleGenerating = true;
      _articleLogs.clear();
    });
    _appendArticleLog('开始生成画像文章');
    try {
      final Stream<AIStreamEvent> stream = PersonaArticleService.instance
          .streamArticle();
      _appendArticleLog('已连接 AI 服务，开始接收内容');
      _articleSubscription = stream.listen(
        (AIStreamEvent event) {
          if (!mounted) return;
          if (event.kind == 'content' && event.data.isNotEmpty) {
            setState(() {
              _article += event.data;
            });
          }
        },
        onError: (Object error) {
          if (!mounted) return;
          _appendArticleLog('画像文章生成失败：$error');
          setState(() {
            _articleGenerating = false;
            _articleError = error.toString();
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _articleGenerating = false;
          });
          final String finalArticle = _article.trim();
          if (finalArticle.isNotEmpty) {
            unawaited(
              _articleService.persistArticle(
                style: PersonaArticleStyle.narrative,
                article: finalArticle,
                localeOverride: Localizations.maybeLocaleOf(context),
              ),
            );
          }
          _appendArticleLog('画像文章生成完成');
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _articleGenerating = false;
        _articleError = e.toString();
      });
      _appendArticleLog('画像文章生成发生异常：$e');
    }
  }

  void _scheduleArticleRegeneration({bool force = false}) {
    _appendArticleLog('调度画像文章生成，强制=$force');
    unawaited(_regenerateArticle(force: force));
  }

  Future<void> _startHistoricalProcessing({
    required bool forceReprocess,
  }) async {
    if (_initializingHistory) {
      _logInfo('跳过历史处理（忙碌中）强制=$forceReprocess');
      return;
    }
    _logInfo('发起历史处理请求 强制=$forceReprocess');
    final AppLocalizations t = AppLocalizations.of(context);
    final MemoryProgressRunning primedProgress = MemoryProgressRunning(
      processedCount: 0,
      totalCount: 0,
      progress: 0,
      currentEventId: null,
      currentEventExternalId: null,
      currentEventType: null,
    );
    setState(() {
      _initializingHistory = true;
      _waitingForInitialProgress = true;
      _preparingStageLabel = t.memoryProgressStageSyncSegments;
      _progress = primedProgress;
    });
    _service.primeProgressState(
      primedProgress,
      waitingForInitialProgress: true,
      stageLabel: t.memoryProgressStageSyncSegments,
    );
    try {
      final int segmentSynced = await _service.syncSegmentsToMemory();
      _logInfo('历史处理：动态同步导入=$segmentSynced');
      if (mounted) {
        setState(() => _preparingStageLabel = t.memoryProgressStageSyncChats);
        _service.updatePreparationStage(_preparingStageLabel);
      }
      final int chatSynced = await _service.syncAllConversationsToMemory();
      _logInfo('历史处理：聊天同步导入=$chatSynced');
      if (mounted) {
        setState(() => _preparingStageLabel = t.memoryProgressStageDispatch);
        _service.updatePreparationStage(_preparingStageLabel);
      }
      await _service.startHistoricalProcessing(forceReprocess: forceReprocess);
      if (!mounted) return;
      _logInfo('历史处理已派发 强制=$forceReprocess');
      UINotifier.success(context, t.memoryStartProcessingToast);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _waitingForInitialProgress = false;
        _preparingStageLabel = null;
        _progress = const MemoryProgressIdle();
      });
      _service.primeProgressState(
        const MemoryProgressIdle(),
        waitingForInitialProgress: false,
      );
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
      _service.primeProgressState(
        const MemoryProgressIdle(),
        waitingForInitialProgress: false,
      );
      UINotifier.error(context, t.memoryConfirmFailedToast(e.toString()));
    } finally {
      if (mounted) {
        setState(() {
          _initializingHistory = _progress is MemoryProgressRunning;
        });
        _logInfo('历史处理完成 强制=$forceReprocess');
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
          recentEvents: <MemoryEventSummary>[],
          personaSummary: '',
        );
    final String persona = snapshot.personaSummary.trim();
    final bool canCopyPersona = persona.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: _buildMemoryAppBarTitle(context),
        actions: [
          if (canCopyPersona)
            IconButton(
              tooltip: t.copyPersonaTooltip,
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: persona));
                if (!context.mounted) return;
                UINotifier.success(context, t.copySuccess);
              },
            ),
          IconButton(
            tooltip: '请求调试',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MemoryRequestDebugPage(),
                ),
              );
            },
            icon: const Icon(Icons.bug_report_outlined),
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary,
                      ),
                    ),
                  )
                : const Icon(Icons.delete_outline),
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
              ),
              child: _buildPersonaSection(context, snapshot),
            ),
            const SizedBox(height: AppTheme.spacing4),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
              ),
              child: _buildArticleSection(context),
            ),
            const SizedBox(height: AppTheme.spacing12),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        bottom: false,
        child: Container(
          width: double.infinity,
          color: theme.colorScheme.surface,
          child: _buildProgressCard(context),
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
        _progress = const MemoryProgressIdle();
      });
      _service.primeProgressState(
        const MemoryProgressIdle(),
        waitingForInitialProgress: false,
      );
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
    final bool confirmed =
        await showUIDialog<bool>(
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
          recentEvents: const <MemoryEventSummary>[],
          lastUpdatedAt: DateTime.now(),
          personaSummary: '',
        );
        _recentEvents.clear();
        _eventTotal = 0;
        _eventVisible = _pageStep;
        _article = '';
        _articleLogs.clear();
      });
      _service.primeProgressState(
        const MemoryProgressIdle(),
        waitingForInitialProgress: false,
      );
      try {
        await _articleService.clearCachedArticle();
      } catch (e, st) {
        _logInfo('清理人设文章缓存失败：$e $st');
      }
      if (!mounted) return;
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

  Widget _buildPersonaSection(BuildContext context, MemorySnapshot snapshot) {
    final AppLocalizations t = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String persona = snapshot.personaSummary.trim();
    if (persona.isEmpty) {
      return Text(
        t.memoryPersonaEmptyPlaceholder,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return _buildArticleMarkdown(theme, persona);
  }

  Widget _buildArticleSection(BuildContext context) {
    final AppLocalizations t = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final String article = _article.trim();
    final bool hasArticle = article.isNotEmpty;

    Widget content;
    if (_articleGenerating && !hasArticle) {
      content = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (hasArticle) {
      content = _buildArticleMarkdown(theme, article);
    } else if (_articleError != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.memoryArticleEmptyPlaceholder,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          Text(
            _articleError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      );
    } else {
      content = Text(
        t.memoryArticleEmptyPlaceholder,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [content],
    );
  }

  Widget _buildArticleMarkdown(ThemeData theme, String markdown) {
    final double baseSize = theme.textTheme.bodyMedium?.fontSize ?? 15;
    final TextStyle paragraph =
        (theme.textTheme.bodyLarge ??
                theme.textTheme.bodyMedium ??
                const TextStyle())
            .copyWith(fontSize: baseSize + 1, height: 1.65);
    final TextStyle heading =
        (theme.textTheme.titleMedium ?? theme.textTheme.bodyLarge ?? paragraph)
            .copyWith(
              fontSize: baseSize + 4,
              height: 1.35,
              fontWeight: FontWeight.w700,
            );

    final MarkdownStyleSheet sheet = MarkdownStyleSheet.fromTheme(theme)
        .copyWith(
          p: paragraph,
          h2: heading,
          h3: heading.copyWith(fontSize: heading.fontSize! - 1),
          h4: heading.copyWith(fontSize: heading.fontSize! - 2),
          blockSpacing: AppTheme.spacing2.toDouble(),
          listIndent: AppTheme.spacing3.toDouble(),
        );

    return MarkdownBody(data: markdown, styleSheet: sheet, shrinkWrap: true);
  }

  Widget _buildArticleLogPanel(ThemeData theme, AppLocalizations t) {
    final TextStyle entryStyle =
        theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.2,
        ) ??
        const TextStyle(fontSize: 12);
    final List<String> logs = _articleLogs.reversed.toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.55),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.articleLogTitle,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          for (final String log in logs)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacing1),
              child: Text(log, style: entryStyle),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressDetailRow({
    required BuildContext context,
    required TextStyle bodyStyle,
    required MemoryProgressRunning progress,
    required String percentText,
    required AppLocalizations t,
  }) {
    return Text(
      t.memoryProgressRunningDetail(
        progress.processedCount,
        progress.totalCount,
        percentText,
      ),
      style: bodyStyle,
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
      final double sTarget = brightness == Brightness.dark
          ? sMinDark
          : sMinLight;
      final double lTarget = brightness == Brightness.dark
          ? lMinDark
          : lMinLight;
      final double s = h.saturation < sTarget ? sTarget : h.saturation;
      final double l = h.lightness < lTarget ? lTarget : h.lightness;
      return h.withSaturation(s).withLightness(l).toColor();
    }

    final Color c1 = tune(const Color(0xFF1F6FEB));
    final Color c2 = tune(const Color(0xFF3B82F6));
    final Color c3 = tune(const Color(0xFF60A5FA));
    final Color c4 = tune(const Color(0xFF7C83FF));
    final Color cY = tune(
      const Color(0xFFF59E0B),
      lMinLight: 0.86,
      lMinDark: 0.76,
    );
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
    final BorderRadius cardRadius = BorderRadius.zero;
    final BorderRadius buttonRadius = BorderRadius.circular(AppTheme.radiusLg);
    final EdgeInsets cardPadding = const EdgeInsets.symmetric(
      horizontal: AppTheme.spacing3,
      vertical: AppTheme.spacing2,
    );
    final TextStyle headerStyle =
        theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600) ??
        theme.textTheme.bodyMedium!;
    final TextStyle bodyStyle =
        theme.textTheme.bodySmall ?? theme.textTheme.bodyMedium!;
    final ButtonStyle filledPill = FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: buttonRadius),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing1,
      ),
    );
    final ButtonStyle outlinedPill = OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: buttonRadius),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing3,
        vertical: AppTheme.spacing1,
      ),
    );
    final BorderSide outline = BorderSide(
      color: theme.colorScheme.outlineVariant.withOpacity(0.45),
      width: 1,
    );
    final List<BoxShadow> cardShadows = const <BoxShadow>[];

    if (progress is MemoryProgressRunning) {
      final bool waiting = _waitingForInitialProgress;
      final String? stageLabel = _preparingStageLabel;
      final double percent = (progress.safeProgress * 100).clamp(0, 100);
      final String percentText = percent >= 10
          ? percent.toStringAsFixed(0)
          : percent.toStringAsFixed(1);
      return Card(
        margin: EdgeInsets.zero,
        color: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
        child: Container(
          padding: cardPadding,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: cardRadius,
            border: Border.fromBorderSide(outline),
            boxShadow: cardShadows,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.memoryProgressRunning, style: headerStyle),
              const SizedBox(height: AppTheme.spacing1),
              LinearProgressIndicator(
                value: waiting ? null : progress.safeProgress,
                minHeight: 4,
              ),
              const SizedBox(height: AppTheme.spacing1),
              if (waiting && stageLabel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spacing2),
                  child: Text(
                    t.memoryProgressPreparing(stageLabel),
                    style: bodyStyle.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else ...[
                _buildProgressDetailRow(
                  context: context,
                  bodyStyle: bodyStyle,
                  progress: progress,
                  percentText: percentText,
                  t: t,
                ),
                const SizedBox(height: AppTheme.spacing1),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _pausing ? null : _pauseProcessing,
                    style: filledPill,
                    icon: _pausing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.pause_circle_outline, size: 18),
                    label: Text(
                      _pausing ? t.articleGenerating : t.memoryPauseActionLabel,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (progress is MemoryProgressCompleted) {
      final int seconds = progress.duration.inSeconds;
      return Card(
        margin: EdgeInsets.zero,
        color: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
        child: Container(
          padding: cardPadding,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: cardRadius,
            border: Border.fromBorderSide(outline),
            boxShadow: cardShadows,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.memoryProgressCompleted(progress.totalCount, seconds),
                style: bodyStyle,
              ),
              const SizedBox(height: AppTheme.spacing2),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _initializingHistory
                      ? null
                      : () => _startHistoricalProcessing(forceReprocess: false),
                  style: filledPill,
                  icon: _initializingHistory
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(t.memoryStartProcessingActionShort),
                ),
              ),
              const SizedBox(height: AppTheme.spacing1),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _initializingHistory
                      ? null
                      : () => _startHistoricalProcessing(forceReprocess: true),
                  style: outlinedPill,
                  icon: const Icon(Icons.restart_alt_outlined, size: 18),
                  label: Text(t.memoryReprocessAction),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (progress is MemoryProgressFailed) {
      final String headerText = t.memoryProgressFailed(progress.errorMessage);
      final String? subtitle =
          progress.failedEventExternalId?.isNotEmpty == true
          ? t.memoryProgressFailedEvent(progress.failedEventExternalId!)
          : null;
      final String? raw = progress.rawResponse?.trim();

      return Card(
        margin: EdgeInsets.zero,
        color: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: cardRadius),
        child: Container(
          padding: cardPadding,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: cardRadius,
            border: Border.fromBorderSide(outline),
            boxShadow: cardShadows,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headerText,
                style: headerStyle.copyWith(color: theme.colorScheme.error),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppTheme.spacing1),
                Text(
                  subtitle,
                  style: bodyStyle.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (raw != null && raw.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacing2),
                Text(
                  t.memoryMalformedResponseRawLabel,
                  style: bodyStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing1),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTheme.spacing2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: cardRadius,
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                    ),
                  ),
                  child: SelectableText(
                    raw,
                    style: bodyStyle.copyWith(
                      fontFamily: 'monospace',
                      height: 1.25,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppTheme.spacing2),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _initializingHistory
                      ? null
                      : () => _startHistoricalProcessing(forceReprocess: false),
                  style: filledPill,
                  icon: _initializingHistory
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(t.memoryStartProcessingActionShort),
                ),
              ),
              const SizedBox(height: AppTheme.spacing1),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _initializingHistory
                      ? null
                      : () => _startHistoricalProcessing(forceReprocess: true),
                  style: outlinedPill,
                  icon: const Icon(Icons.restart_alt_outlined, size: 18),
                  label: Text(t.memoryReprocessAction),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: cardRadius),
      child: Container(
        padding: cardPadding,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: cardRadius,
          border: Border.fromBorderSide(outline),
          boxShadow: cardShadows,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _memoryProgressIdleHint(t),
              style: bodyStyle.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTheme.spacing2),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _initializingHistory
                    ? null
                    : () => _startHistoricalProcessing(forceReprocess: false),
                style: filledPill,
                icon: _initializingHistory
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(t.memoryStartProcessingActionShort),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _memoryProgressIdleHint(AppLocalizations t) {
    final String code = t.localeName.toLowerCase();
    if (code.startsWith('zh')) {
      return '点击下方按钮即可解析历史动态事件，完善你的个人档案';
    }
    if (code.startsWith('ja')) {
      return '下のボタンで過去の行動イベントを再解析し、あなた自身のプロフィールを整えましょう';
    }
    if (code.startsWith('ko')) {
      return '아래 버튼을 눌러 과거 활동 이벤트를 다시 분석해 개인 프로필을 보완해 보세요';
    }
    return 'Tap below to reprocess past activity events and complete your personal archive';
  }

  Widget _buildInfoChip({
    required BuildContext context,
    required IconData icon,
    required String label,
  }) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surfaceVariant.withOpacity(0.4),
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
      return '运行中 已处理=${progress.processedCount}/${progress.totalCount} 进度=${progress.safeProgress.toStringAsFixed(3)} 当前事件ID=${progress.currentEventId}';
    }
    if (progress is MemoryProgressCompleted) {
      return '已完成 总数=${progress.totalCount} 耗时=${progress.duration.inMilliseconds}毫秒';
    }
    if (progress is MemoryProgressFailed) {
      return '失败 已处理=${progress.processedCount}/${progress.totalCount} 错误=${progress.errorMessage}';
    }
    return '空闲';
  }

  void _applySnapshot(MemorySnapshot snapshot) {
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _eventTotal = snapshot.recentEventTotalCount;

      if (snapshot.recentEvents.isNotEmpty || _recentEvents.isEmpty) {
        _replaceLeadingEvents(_recentEvents, snapshot.recentEvents);
      }

      _eventVisible = _normalizeVisible(
        _eventVisible,
        math.min(_recentEvents.length, _eventTotal),
      );
    });
    _handlePersonaSummaryChange(snapshot.personaSummary);
  }

  void _replaceLeadingEvents(
    List<MemoryEventSummary> target,
    List<MemoryEventSummary> incoming,
  ) {
    if (incoming.isEmpty) return;
    final Set<int> incomingIds = incoming.map((e) => e.id).toSet();
    target.removeWhere((event) => incomingIds.contains(event.id));
    target.insertAll(0, incoming);
  }

  void _appendEvents(
    List<MemoryEventSummary> target,
    List<MemoryEventSummary> incoming,
  ) {
    if (incoming.isEmpty) return;
    final Set<int> existingIds = target.map((e) => e.id).toSet();
    for (final MemoryEventSummary event in incoming) {
      if (existingIds.add(event.id)) {
        target.add(event);
      }
    }
  }

  void _handlePersonaSummaryChange(String summary) {
    final String trimmed = summary.trim();
    if (trimmed.isEmpty) return;
    if (trimmed == _lastPersonaSummary) return;
    _appendArticleLog('画像摘要更新，准备重新生成文章');
    _lastPersonaSummary = trimmed;
    _scheduleArticleRegeneration(force: true);
  }

  void _appendArticleLog(String message) {
    FlutterLogger.nativeInfo('MemoryCenter', message);
    if (!mounted) return;
    setState(() {
      if (_articleLogs.length >= 30) {
        _articleLogs.removeAt(0);
      }
      final String timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
      _articleLogs.add('[$timestamp] $message');
    });
  }

  void _logInfo(String message) {
    try {
      FlutterLogger.nativeInfo('MemoryCenterPage', message);
    } catch (_) {}
  }
}
