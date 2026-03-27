import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import '../services/ai_providers_service.dart';
import '../services/ai_settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/model_icon_utils.dart';
import '../widgets/screenshot_style_tab_bar.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import 'nocturne_memory_rebuild_tab.dart';
import 'nocturne_memory_view_tab.dart';

/// Nocturne-style Memory (URI graph) page.
///
/// - Tab: 查看记忆
/// - Tab: 一键重建（纯图片语料：来自“动态”里的截图样本）
/// - AppBar: 像“动态”那样选择提供商与模型（独立上下文：memory）
class NocturneMemoryPage extends StatefulWidget {
  const NocturneMemoryPage({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<NocturneMemoryPage> createState() => _NocturneMemoryPageState();
}

class _NocturneMemoryPageState extends State<NocturneMemoryPage>
    with SingleTickerProviderStateMixin {
  // —— 基于提供商表的“memory”上下文（与对话/动态隔离） ——
  AIProvider? _ctxProvider;
  String? _ctxModel;

  // 底部弹窗查询输入持久化
  String _providerQueryText = '';
  String _modelQueryText = '';

  StreamSubscription<String>? _ctxChangedSub;
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _loadMemoryContextSelection();
    _ctxChangedSub = AISettingsService.instance.onContextChanged.listen((ctx) {
      if (ctx == 'memory' && mounted) _loadMemoryContextSelection();
    });
  }

  @override
  void dispose() {
    _ctxChangedSub?.cancel();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadMemoryContextSelection() async {
    try {
      final svc = AIProvidersService.instance;
      final providers = await svc.listProviders();
      if (providers.isEmpty) {
        if (mounted) {
          setState(() {
            _ctxProvider = null;
            _ctxModel = null;
          });
        }
        return;
      }

      final ctxRow = await AISettingsService.instance.getAIContextRow('memory');
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
      if (model.isNotEmpty &&
          sel.models.isNotEmpty &&
          !sel.models.contains(model)) {
        final String fb =
            ((sel.extra['active_model'] as String?) ?? sel.defaultModel)
                .toString()
                .trim();
        model = fb.isNotEmpty ? fb : sel.models.first;
      }

      if (mounted) {
        setState(() {
          _ctxProvider = sel;
          _ctxModel = model;
        });
      }
    } catch (_) {}
  }

  Future<void> _showProviderSheetMemory() async {
    final svc = AIProvidersService.instance;
    final list = await svc.listProviders();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final currentId = _ctxProvider?.id ?? -1;
        final TextEditingController queryCtrl = TextEditingController(
          text: _providerQueryText,
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: TextField(
                          controller: queryCtrl,
                          autofocus: true,
                          onChanged: (_) {
                            _providerQueryText = queryCtrl.text;
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
                      Expanded(
                        child: ListView.separated(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          separatorBuilder: (c, i) => Container(
                            height: 1,
                            color: Theme.of(
                              c,
                            ).colorScheme.outline.withValues(alpha: 0.6),
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
                              title: Text(p.name),
                              trailing: selected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Theme.of(c).colorScheme.onSurface,
                                    )
                                  : null,
                              onTap: () async {
                                final NavigatorState navigator = Navigator.of(
                                  ctx,
                                );
                                String model = (_ctxModel ?? '').trim();
                                final List<String> available = p.models;
                                if (model.isEmpty ||
                                    (available.isNotEmpty &&
                                        !available.contains(model))) {
                                  String fb =
                                      (p.extra['active_model'] as String? ??
                                              p.defaultModel)
                                          .toString()
                                          .trim();
                                  if (fb.isEmpty && available.isNotEmpty) {
                                    fb = available.first;
                                  }
                                  model = fb;
                                }
                                await AISettingsService.instance
                                    .setAIContextSelection(
                                      context: 'memory',
                                      providerId: p.id!,
                                      model: model,
                                    );
                                if (mounted) {
                                  setState(() {
                                    _ctxProvider = p;
                                    _ctxModel = model;
                                  });
                                  navigator.pop();
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

  Future<void> _showModelSheetMemory() async {
    final p = _ctxProvider;
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
        final active = (_ctxModel ?? '').trim();
        final TextEditingController queryCtrl = TextEditingController(
          text: _modelQueryText,
        );
        return StatefulBuilder(
          builder: (c, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) {
                final q = queryCtrl.text.trim().toLowerCase();
                final filtered = models.where((mm) {
                  if (q.isEmpty) return true;
                  return mm.toLowerCase().contains(q);
                }).toList();
                if (active.isNotEmpty && filtered.contains(active)) {
                  final idx = filtered.indexOf(active);
                  if (idx > 0) {
                    final sel = filtered.removeAt(idx);
                    filtered.insert(0, sel);
                  }
                }
                return UISheetSurface(
                  child: Column(
                    children: [
                      const SizedBox(height: AppTheme.spacing3),
                      const UISheetHandle(),
                      const SizedBox(height: AppTheme.spacing3),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: TextField(
                          controller: queryCtrl,
                          autofocus: true,
                          onChanged: (_) {
                            _modelQueryText = queryCtrl.text;
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
                      Expanded(
                        child: ListView.separated(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          separatorBuilder: (c, i) => Container(
                            height: 1,
                            color: Theme.of(
                              c,
                            ).colorScheme.outline.withValues(alpha: 0.6),
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
                              title: Text(m),
                              trailing: selected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Theme.of(c).colorScheme.primary,
                                    )
                                  : null,
                              onTap: () async {
                                final NavigatorState navigator = Navigator.of(
                                  ctx,
                                );
                                await AISettingsService.instance
                                    .setAIContextSelection(
                                      context: 'memory',
                                      providerId: p.id!,
                                      model: m,
                                    );
                                if (mounted) {
                                  setState(() => _ctxModel = m);
                                  navigator.pop();
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

  Widget _buildProviderModelTitle() {
    final theme = Theme.of(context);
    final String providerName = _ctxProvider?.name ?? '—';
    final String modelName = _ctxModel ?? '—';
    final TextStyle? linkStyle = theme.textTheme.labelSmall?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
            onTap: _showProviderSheetMemory,
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
            onTap: _showModelSheetMemory,
            behavior: HitTestBehavior.opaque,
            child: Text(
              modelName,
              style: linkStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 36,
        centerTitle: true,
        title: _buildProviderModelTitle(),
        actions: [
          IconButton(
            tooltip: '说明',
            onPressed: () {
              UIDialogs.showInfo(
                context,
                title: 'Nocturne 记忆',
                message:
                    '这里是 Nocturne 风格的“URI 图记忆”。\n\n'
                    '重建时仅使用“动态”里的截图图片作为语料（每次最多 10 张）。\n'
                    '重建任务现在会在页面外继续运行，并在通知栏显示进度。\n'
                    '当解析响应失败会立刻暂停，并在页面下方显示原始响应，允许你选择继续。',
              );
            },
            icon: const Icon(Icons.info_outline, size: 20),
          ),
        ],
        bottom: ScreenshotStyleTabBar(
          controller: _tab,
          isScrollable: false,
          height: 34,
          tabs: const [
            Tab(text: '查看记忆'),
            Tab(text: '一键重建'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [NocturneMemoryViewTab(), NocturneMemoryRebuildTab()],
      ),
    );
  }
}
