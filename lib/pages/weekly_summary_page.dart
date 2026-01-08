import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/ai_providers_service.dart';
import '../services/ai_settings_service.dart';
import '../services/weekly_summary_service.dart';
import '../services/ai_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/model_icon_utils.dart';
import '../widgets/screenshot_style_tab_bar.dart';
import '../widgets/ui_components.dart';

class WeeklySummaryPage extends StatefulWidget {
  const WeeklySummaryPage({super.key, this.weekStart});

  final String? weekStart;

  @override
  State<WeeklySummaryPage> createState() => _WeeklySummaryPageState();
}

class _WeeklySummaryPageState extends State<WeeklySummaryPage>
    with SingleTickerProviderStateMixin {
  final WeeklySummaryService _service = WeeklySummaryService.instance;

  List<Map<String, dynamic>> _weeks = <Map<String, dynamic>>[];
  Map<String, dynamic>? _current;
  Map<String, dynamic>? _structured;
  String? _selectedWeek;
  bool _listLoading = false;
  bool _detailLoading = false;
  int _detailRequestId = 0;
  StreamSubscription<AIStreamEvent>? _streamSub;
  bool _streaming = false;
  String _streamingText = '';
  String? _streamingWeekStart;
  double _weekSwipeDx = 0.0;

  // —— 基于提供商表的“周总结(weekly)”上下文（与 segments/chat 解耦） ——
  String _weeklyProviderQueryText = '';
  String _weeklyModelQueryText = '';
  AIProvider? _ctxWeeklyProvider;
  String? _ctxWeeklyModel;
  bool _ctxWeeklyLoading = true;

  // 周 Tab（每个 tab = 一周总结）
  TabController? _weekTabController;

  @override
  void initState() {
    super.initState();
    _loadWeeklyContextSelection();
    _loadWeeks(initialSelected: widget.weekStart);
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _weekTabController?.removeListener(_handleWeekTabChanged);
    _weekTabController?.dispose();
    super.dispose();
  }

  void _handleWeekTabChanged() {
    final TabController? c = _weekTabController;
    if (c == null || !mounted) return;
    // 仅在最终落点触发，避免动画过程/重复触发
    if (c.indexIsChanging) return;
    if (_streaming) return;
    final int idx = c.index;
    if (idx < 0 || idx >= _weeks.length) return;
    final String start = ((_weeks[idx]['week_start_date'] as String?) ?? '')
        .trim();
    if (start.isEmpty || start == _selectedWeek) return;
    // ignore: unawaited_futures
    _loadDetail(start);
  }

  int _indexOfWeekStart(String? weekStartKey) {
    final String key = (weekStartKey ?? '').trim();
    if (key.isEmpty) return 0;
    final int idx = _weeks.indexWhere(
      (row) => ((row['week_start_date'] as String?) ?? '').trim() == key,
    );
    return idx >= 0 ? idx : 0;
  }

  void _ensureWeekTabController(int length, {int initialIndex = 0}) {
    if (length <= 0) {
      _weekTabController?.removeListener(_handleWeekTabChanged);
      _weekTabController?.dispose();
      _weekTabController = null;
      return;
    }

    final int desiredIndex = initialIndex.clamp(0, length - 1);
    if (_weekTabController == null || _weekTabController!.length != length) {
      _weekTabController?.removeListener(_handleWeekTabChanged);
      _weekTabController?.dispose();
      _weekTabController = TabController(
        length: length,
        vsync: this,
        initialIndex: desiredIndex,
      );
      _weekTabController!.addListener(_handleWeekTabChanged);
      return;
    }

    if (_weekTabController!.index != desiredIndex) {
      try {
        _weekTabController!.animateTo(desiredIndex);
      } catch (_) {}
    }
  }

  Future<void> _loadWeeklyContextSelection() async {
    try {
      final svc = AIProvidersService.instance;
      final providers = await svc.listProviders();
      if (providers.isEmpty) {
        if (mounted) {
          setState(() {
            _ctxWeeklyProvider = null;
            _ctxWeeklyModel = null;
            _ctxWeeklyLoading = false;
          });
        }
        return;
      }
      final ctxRow = await AISettingsService.instance.getAIContextRow('weekly');
      AIProvider? sel;
      if (ctxRow != null && ctxRow['provider_id'] is int) {
        sel = await svc.getProvider(ctxRow['provider_id'] as int);
      }
      sel ??= await svc.getDefaultProvider();
      sel ??= providers.first;

      String model =
          (ctxRow != null &&
              (ctxRow['model'] as String?)?.trim().isNotEmpty == true)
          ? (ctxRow['model'] as String).trim()
          : ((sel.extra['active_model'] as String?) ?? sel.defaultModel)
                .toString()
                .trim();
      if (model.isEmpty && sel.models.isNotEmpty) model = sel.models.first;

      if (mounted) {
        setState(() {
          _ctxWeeklyProvider = sel;
          _ctxWeeklyModel = model;
          _ctxWeeklyLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ctxWeeklyLoading = false);
    }
  }

  Future<void> _showProviderSheetWeekly() async {
    final svc = AIProvidersService.instance;
    final list = await svc.listProviders();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final currentId = _ctxWeeklyProvider?.id ?? -1;
        // 使用持久化查询文本，避免键盘开合/重建导致输入被清空
        final TextEditingController queryCtrl = TextEditingController(
          text: _weeklyProviderQueryText,
        );
        return StatefulBuilder(
          builder: (c, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) {
                final q = queryCtrl.text.trim().toLowerCase();
                final filtered = list.where((p) {
                  if (q.isEmpty) return true;
                  final name = p.name.toLowerCase();
                  final type = p.type.toLowerCase();
                  final base = (p.baseUrl ?? '').toString().toLowerCase();
                  return name.contains(q) ||
                      type.contains(q) ||
                      base.contains(q);
                }).toList();
                // 将当前选中的提供商置顶，便于观察
                final selIdx = filtered.indexWhere((e) => e.id == currentId);
                if (selIdx > 0) {
                  final sel = filtered.removeAt(selIdx);
                  filtered.insert(0, sel);
                }
                return UISheetSurface(
                  child: Column(
                    children: [
                      const SizedBox(height: AppTheme.spacing3),
                      const UISheetHandle(),
                      const SizedBox(height: AppTheme.spacing3),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        child: TextField(
                          controller: queryCtrl,
                          autofocus: true,
                          onChanged: (_) {
                            _weeklyProviderQueryText = queryCtrl.text;
                            setModalState(() {});
                          },
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: AppLocalizations.of(
                              context,
                            ).searchProviderPlaceholder,
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing2),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          separatorBuilder: (c, i) => Container(
                            height: 1,
                            color: Theme.of(
                              c,
                            ).colorScheme.outline.withOpacity(0.6),
                          ),
                          itemBuilder: (c, i) {
                            final p = filtered[i];
                            final selected = p.id == currentId;
                            return ListTile(
                              leading: SvgPicture.asset(
                                ModelIconUtils.getProviderIconPath(p.type),
                                width: 20,
                                height: 20,
                              ),
                              title: Text(
                                p.name,
                                style: Theme.of(c).textTheme.bodyMedium,
                              ),
                              trailing: selected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Theme.of(c).colorScheme.onSurface,
                                    )
                                  : null,
                              onTap: () async {
                                String model = (_ctxWeeklyModel ?? '').trim();
                                if (model.isEmpty) {
                                  model =
                                      ((p.extra['active_model'] as String?) ??
                                              p.defaultModel)
                                          .toString()
                                          .trim();
                                }
                                if (model.isEmpty && p.models.isNotEmpty) {
                                  model = p.models.first;
                                }
                                await AISettingsService.instance
                                    .setAIContextSelection(
                                      context: 'weekly',
                                      providerId: p.id!,
                                      model: model,
                                    );
                                if (mounted) {
                                  setState(() {
                                    _ctxWeeklyProvider = p;
                                    _ctxWeeklyModel = model;
                                  });
                                  Navigator.of(ctx).pop();
                                  UINotifier.success(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    ).providerSelectedToast(p.name),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showModelSheetWeekly() async {
    final p = _ctxWeeklyProvider;
    if (p == null) {
      UINotifier.info(
        context,
        AppLocalizations.of(context).pleaseSelectProviderFirst,
      );
      return;
    }
    final models = p.models;
    if (models.isEmpty) {
      UINotifier.info(
        context,
        AppLocalizations.of(context).noModelsForProviderHint,
      );
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final active = (_ctxWeeklyModel ?? '').trim();
        // 使用持久化查询文本，避免失焦时文本被清空
        final TextEditingController queryCtrl = TextEditingController(
          text: _weeklyModelQueryText,
        );
        return StatefulBuilder(
          builder: (c, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) {
                final q = queryCtrl.text.trim().toLowerCase();
                final filtered = models.where((m) {
                  if (q.isEmpty) return true;
                  return m.toLowerCase().contains(q);
                }).toList();
                // 将当前选中的模型置顶，便于观察
                final selIdx = filtered.indexWhere((e) => e == active);
                if (selIdx > 0) {
                  final sel = filtered.removeAt(selIdx);
                  filtered.insert(0, sel);
                }
                return UISheetSurface(
                  child: Column(
                    children: [
                      const SizedBox(height: AppTheme.spacing3),
                      const UISheetHandle(),
                      const SizedBox(height: AppTheme.spacing3),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacing4,
                        ),
                        child: TextField(
                          controller: queryCtrl,
                          autofocus: true,
                          onChanged: (_) {
                            _weeklyModelQueryText = queryCtrl.text;
                            setModalState(() {});
                          },
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: AppLocalizations.of(
                              context,
                            ).searchModelPlaceholder,
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing2),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          separatorBuilder: (c, i) => Container(
                            height: 1,
                            color: Theme.of(
                              c,
                            ).colorScheme.outline.withOpacity(0.6),
                          ),
                          itemBuilder: (c, i) {
                            final m = filtered[i];
                            final selected = m == active;
                            return ListTile(
                              leading: SvgPicture.asset(
                                ModelIconUtils.getIconPath(m),
                                width: 20,
                                height: 20,
                              ),
                              title: Text(
                                m,
                                style: Theme.of(c).textTheme.bodyMedium,
                              ),
                              trailing: selected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Theme.of(c).colorScheme.primary,
                                    )
                                  : null,
                              onTap: () async {
                                await AISettingsService.instance
                                    .setAIContextSelection(
                                      context: 'weekly',
                                      providerId: p.id!,
                                      model: m,
                                    );
                                if (mounted) {
                                  setState(() => _ctxWeeklyModel = m);
                                  Navigator.of(ctx).pop();
                                  UINotifier.success(
                                    context,
                                    AppLocalizations.of(
                                      context,
                                    ).modelSwitchedToast(m),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildWeeklyProviderModelBar() {
    final theme = Theme.of(context);
    final String providerName = _ctxWeeklyProvider?.name ?? '—';
    final String modelName = _ctxWeeklyModel ?? '—';
    final TextStyle? linkStyle = theme.textTheme.labelSmall?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.onSurface.withOpacity(0.6),
      color: theme.colorScheme.onSurface,
    );
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
            onTap: _showProviderSheetWeekly,
            behavior: HitTestBehavior.opaque,
            child: Text(
              providerName,
              style: linkStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: GestureDetector(
            onTap: _showModelSheetWeekly,
            behavior: HitTestBehavior.opaque,
            child: Text(
              modelName,
              style: linkStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (_ctxWeeklyLoading) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }

  PreferredSizeWidget? _buildWeekTabsBar(BuildContext context) {
    if (_weeks.isEmpty) return null;
    final int selectedIndex = _indexOfWeekStart(_selectedWeek);
    _ensureWeekTabController(_weeks.length, initialIndex: selectedIndex);
    final TabController? controller = _weekTabController;
    if (controller == null) return null;

    final bool disableTabs = _listLoading || _streaming;
    return PreferredSize(
      preferredSize: const Size.fromHeight(32),
      child: SizedBox(
        height: 32,
        child: Transform.translate(
          offset: const Offset(0, -2),
          child: AbsorbPointer(
            absorbing: disableTabs,
            child: ScreenshotStyleTabBar(
              controller: controller,
              padding: const EdgeInsets.only(left: AppTheme.spacing2),
              labelPadding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
              ),
              indicatorInsets: const EdgeInsets.symmetric(
                horizontal: 4.0,
              ),
              tabs: [
                for (final Map<String, dynamic> row in _weeks)
                  Tab(
                    text: _formatPickerLabel(
                      (row['week_start_date'] as String? ?? '').trim(),
                      (row['week_end_date'] as String? ?? '').trim(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadWeeks({
    String? initialSelected,
    bool loadDetail = true,
  }) async {
    setState(() => _listLoading = true);
    try {
      final weeks = await _service.listWeeklySummaries(onlyCompleted: true);
      if (weeks.isEmpty) {
        if (!mounted) return;
        setState(() {
          _weeks = weeks;
          _current = null;
          _structured = null;
          _selectedWeek = null;
        });
        _ensureWeekTabController(0);
        return;
      }

      String desired = (initialSelected ?? _selectedWeek ?? '').trim();
      if (desired.isEmpty) {
        desired = (weeks.first['week_start_date'] as String? ?? '').trim();
      } else {
        final bool exists = weeks.any(
          (row) =>
              ((row['week_start_date'] as String?) ?? '').trim() == desired,
        );
        if (!exists) {
          desired = (weeks.first['week_start_date'] as String? ?? '').trim();
        }
      }

      if (!mounted) return;
      setState(() {
        _weeks = weeks;
        _selectedWeek = desired.isEmpty ? null : desired;
      });

      _ensureWeekTabController(
        weeks.length,
        initialIndex: _indexOfWeekStart(desired),
      );

      if (desired.isNotEmpty && loadDetail) {
        await _loadDetail(desired);
      }
    } finally {
      if (mounted) setState(() => _listLoading = false);
    }
  }

  Future<void> _loadDetail(
    String weekStart, {
    bool forceReloadList = false,
  }) async {
    if (weekStart.isEmpty) return;
    final int requestId = ++_detailRequestId;
    setState(() {
      _detailLoading = true;
      _selectedWeek = weekStart;
    });
    try {
      final row = await _service.getWeeklySummaryByStart(weekStart);
      Map<String, dynamic>? structured;
      if (row != null) {
        final String? raw = row['structured_json'] as String?;
        if (raw != null && raw.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) {
              structured = decoded;
            }
          } catch (_) {}
        }
      }
      if (!mounted || requestId != _detailRequestId) return;
      if (mounted) {
        setState(() {
          _current = row;
          _structured = structured;
        });
      }
      if (forceReloadList && requestId == _detailRequestId) {
        await _loadWeeks(initialSelected: weekStart, loadDetail: false);
      }
    } finally {
      if (mounted && requestId == _detailRequestId) {
        setState(() => _detailLoading = false);
      }
    }
  }

  bool _canSwipeWeekTabs() {
    if (_weeks.length <= 1) return false;
    if (_listLoading || _streaming) return false;
    final TabController? c = _weekTabController;
    if (c == null || c.length <= 1) return false;
    return true;
  }

  void _onWeekSwipeStart(DragStartDetails details) {
    _weekSwipeDx = 0.0;
  }

  void _onWeekSwipeUpdate(DragUpdateDetails details) {
    _weekSwipeDx += details.delta.dx;
  }

  void _onWeekSwipeEnd(DragEndDetails details) {
    if (!_canSwipeWeekTabs()) return;
    final TabController? controller = _weekTabController;
    if (controller == null) return;

    const double distanceThreshold = 48;
    const double velocityThreshold = 450;

    final double velocity = details.primaryVelocity ?? 0.0;
    final bool byDistance = _weekSwipeDx.abs() >= distanceThreshold;
    final bool byVelocity = velocity.abs() >= velocityThreshold;
    if (!byDistance && !byVelocity) return;

    final bool goNext = byDistance ? (_weekSwipeDx < 0) : (velocity < 0);
    final int targetIndex = goNext ? controller.index + 1 : controller.index - 1;
    if (targetIndex < 0 || targetIndex >= controller.length) return;
    try {
      controller.animateTo(targetIndex);
    } catch (_) {}
  }

  Future<void> _onRegenerate() async {
    final String? weekStart = _selectedWeek;
    if (weekStart == null || weekStart.isEmpty || _streaming) return;
    await _startStreaming(weekStart, force: true, showSuccessSnack: true);
  }

  Future<void> _startStreaming(
    String weekStart, {
    bool force = false,
    bool showSuccessSnack = true,
  }) async {
    await _streamSub?.cancel();
    if (!mounted) return;
    setState(() {
      _streaming = true;
      _streamingText = '';
      _streamingWeekStart = weekStart;
      _detailLoading = false;
    });

    bool hadError = false;
    try {
      final AIStreamingSession? session = await _service
          .streamGenerateForWeekStart(weekStart, force: force);
      if (session == null) {
        if (mounted && _selectedWeek == weekStart) {
          await _loadDetail(weekStart, forceReloadList: true);
        }
        if (showSuccessSnack && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).generateSuccess),
            ),
          );
        }
        return;
      }

      _streamSub = session.stream.listen(
        (AIStreamEvent event) {
          if (!mounted) return;
          if (event.kind == 'content' && event.data.isNotEmpty) {
            setState(() {
              _streamingText += event.data;
            });
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          hadError = true;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).generateFailed),
            ),
          );
        },
      );

      await session.completed;
      if (hadError) return;

      if (mounted && _selectedWeek == weekStart) {
        await _loadDetail(weekStart, forceReloadList: true);
      }
      if (showSuccessSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).generateSuccess)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      if (!hadError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).generateFailed)),
        );
      }
    } finally {
      await _streamSub?.cancel();
      _streamSub = null;
      if (mounted) {
        setState(() {
          _streaming = false;
          _streamingText = '';
          _streamingWeekStart = null;
        });
      }
    }
  }

  Future<void> _onCopy() async {
    final String? text =
        (_structured?['weekly_overview'] as String?) ??
        (_current?['output_text'] as String?);
    if (text == null || text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).copySuccess)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final PreferredSizeWidget? weekTabs = _buildWeekTabsBar(context);

    Widget body;
    if (_listLoading) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_weeks.isEmpty) {
      body = _buildEmptyPlaceholder(context);
    } else {
      body = RefreshIndicator(
        onRefresh: () =>
            _loadWeeks(initialSelected: _selectedWeek, loadDetail: true),
        child: _detailLoading && !_streaming
            ? ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing4,
                  vertical: AppTheme.spacing3,
                ),
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: AppTheme.spacing6),
                  Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              )
            : (_streaming && _streamingWeekStart == _selectedWeek)
            ? _buildStreamingSection(context)
            : _buildWeeklyContent(context),
      );

      if (_canSwipeWeekTabs()) {
        body = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onWeekSwipeStart,
          onHorizontalDragUpdate: _onWeekSwipeUpdate,
          onHorizontalDragEnd: _onWeekSwipeEnd,
          child: body,
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 36,
        centerTitle: true,
        automaticallyImplyLeading: true,
        title: _buildWeeklyProviderModelBar(),
        actions: [
          IconButton(
            tooltip: l10n.actionCopy,
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: (_current == null || _streaming) ? null : _onCopy,
          ),
          IconButton(
            tooltip: _current == null
                ? l10n.actionGenerate
                : l10n.actionRegenerate,
            icon: (_detailLoading || _streaming)
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_outlined),
            onPressed: (_current == null || _detailLoading || _streaming)
                ? null
                : _onRegenerate,
          ),
        ],
        bottom: weekTabs,
      ),
      body: body,
    );
  }

  Widget _buildCardSection({
    required BuildContext context,
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing4),
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTheme.spacing2),
          child,
        ],
      ),
    );
  }

  Widget _buildWeeklyContent(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing4,
        vertical: AppTheme.spacing3,
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _buildOverviewCard(context),
        _buildDailyBreakdownsCard(context),
        _buildActionItemsCard(context),
        const SizedBox(height: AppTheme.spacing3),
      ],
    );
  }

  Widget _buildOverviewCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final String overview =
        (_structured?['weekly_overview'] as String?) ??
        (_current?['output_text'] as String?) ??
        '';
    if (overview.trim().isEmpty) {
      return _buildCardSection(
        context: context,
        title: l10n.weeklySummaryOverviewTitle,
        child: Text(
          l10n.weeklySummaryNoContent,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return _buildCardSection(
      context: context,
      title: l10n.weeklySummaryOverviewTitle,
      child: MarkdownBody(
        data: overview,
        styleSheet: MarkdownStyleSheet.fromTheme(
          theme,
        ).copyWith(p: theme.textTheme.bodyMedium),
      ),
    );
  }

  Widget _buildDailyBreakdownsCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final List<dynamic>? dailyBreakdowns =
        _structured?['daily_breakdowns'] as List<dynamic>?;
    if (dailyBreakdowns == null || dailyBreakdowns.isEmpty) {
      return _buildCardSection(
        context: context,
        title: l10n.weeklySummaryDailyTitle,
        child: Text(
          l10n.weeklySummaryNoContent,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return _buildCardSection(
      context: context,
      title: l10n.weeklySummaryDailyTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: dailyBreakdowns
            .map((item) {
              if (item is! Map) return const SizedBox.shrink();
              final String dateKey = (item['date_key'] as String? ?? '').trim();
              final String headline = (item['headline'] as String? ?? '')
                  .trim();
              final List<dynamic> highlights =
                  item['highlights'] as List<dynamic>? ?? const <dynamic>[];
              final List<String> texts = highlights
                  .whereType<String>()
                  .toList();

              final List<Widget> highlightWidgets = texts.isEmpty
                  ? [
                      Text(
                        l10n.weeklySummaryNoContent,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ]
                  : texts
                        .map(
                          (text) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppTheme.spacing1,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• '),
                                Expanded(child: Text(text)),
                              ],
                            ),
                          ),
                        )
                        .toList();

              return Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spacing3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline.isEmpty ? dateKey : '$dateKey · $headline',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    ...highlightWidgets,
                  ],
                ),
              );
            })
            .whereType<Widget>()
            .toList(),
      ),
    );
  }

  Widget _buildActionItemsCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final List<dynamic>? actionItems =
        _structured?['action_items'] as List<dynamic>?;
    if (actionItems == null || actionItems.isEmpty) {
      return _buildCardSection(
        context: context,
        title: l10n.weeklySummaryActionsTitle,
        child: Text(
          l10n.weeklySummaryNoContent,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return _buildCardSection(
      context: context,
      title: l10n.weeklySummaryActionsTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: actionItems
            .whereType<String>()
            .map(
              (text) => Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.spacing1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildEmptyPlaceholder(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_view_week_outlined,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withOpacity(0.6),
            ),
            const SizedBox(height: AppTheme.spacing3),
            Text(
              l10n.weeklySummaryEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamingSection(BuildContext context) {
    final theme = Theme.of(context);
    final String normalized = _streamingText.trim();
    final bool hasContent = normalized.isNotEmpty;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0;
        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
                vertical: AppTheme.spacing3,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(height: AppTheme.spacing2),
                    Text('正在生成周总结…', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AppTheme.spacing3),
                    if (hasContent)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: MarkdownBody(
                          data: normalized,
                          softLineBreak: true,
                          styleSheet: MarkdownStyleSheet.fromTheme(
                            theme,
                          ).copyWith(p: theme.textTheme.bodyMedium),
                        ),
                      )
                    else
                      Text('模型正在思考，请稍候…', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatRange(String start, String end) {
    if (start.isEmpty && end.isEmpty) return '';
    if (start.isEmpty) return end;
    if (end.isEmpty) return start;
    return '$start ~ $end';
  }

  String _formatPickerLabel(String start, String end) {
    DateTime? startDate = DateTime.tryParse(start);
    DateTime? endDate = DateTime.tryParse(end);
    if (startDate == null) {
      return _formatRange(start, end);
    }
    final DateFormat formatter = DateFormat('MM/dd');
    final String startLabel = formatter.format(startDate);
    if (endDate == null || end.isEmpty) {
      return startLabel;
    }
    final String endLabel = formatter.format(endDate);
    if (startLabel == endLabel) {
      return startLabel;
    }
    return '$startLabel ~ $endLabel';
  }
}
