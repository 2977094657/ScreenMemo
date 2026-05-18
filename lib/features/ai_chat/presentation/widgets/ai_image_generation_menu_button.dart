import 'package:flutter/material.dart';
import 'package:screen_memo/core/theme/app_theme.dart';
import 'package:screen_memo/core/widgets/model_logo.dart';
import 'package:screen_memo/core/widgets/search_styles.dart';
import 'package:screen_memo/core/widgets/ui_action_menu.dart';
import 'package:screen_memo/core/widgets/ui_components.dart';
import 'package:screen_memo/features/ai/application/ai_providers_service.dart';
import 'package:screen_memo/features/ai/application/ai_settings_service.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

class AIImageGenerationMenuButton extends StatefulWidget {
  const AIImageGenerationMenuButton({super.key});

  @override
  State<AIImageGenerationMenuButton> createState() =>
      _AIImageGenerationMenuButtonState();
}

class _AIImageGenerationMenuButtonState
    extends State<AIImageGenerationMenuButton> {
  final AISettingsService _settings = AISettingsService.instance;
  AIProvider? _provider;
  String? _model;
  String _providerQueryText = '';
  String _modelQueryText = '';

  Future<void> _loadSelection() async {
    try {
      final AIProvidersService svc = AIProvidersService.instance;
      final Map<String, dynamic>? ctxRow = await _settings.getAIContextRow(
        'image_generation',
      );
      AIProvider? selected;
      if (ctxRow != null && ctxRow['provider_id'] is int) {
        selected = await svc.getProvider(ctxRow['provider_id'] as int);
      }
      String model =
          (ctxRow != null &&
              (ctxRow['model'] as String?)?.trim().isNotEmpty == true)
          ? (ctxRow['model'] as String).trim()
          : '';
      if (selected != null &&
          model.isNotEmpty &&
          selected.models.isNotEmpty &&
          !selected.models.contains(model)) {
        model = '';
      }
      if (!mounted) return;
      setState(() {
        _provider = selected;
        _model = model.isEmpty ? null : model;
      });
    } catch (_) {}
  }

  Future<void> _showSettingsSheet() async {
    await _loadSelection();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (c, setModalState) {
            final AppLocalizations l10n = AppLocalizations.of(context);
            final String providerName =
                _provider?.name ?? l10n.aiGeneratedImageNotConfigured;
            final String modelName = (_model ?? '').trim().isEmpty
                ? l10n.aiGeneratedImageNotConfigured
                : _model!.trim();
            return FractionallySizedBox(
              heightFactor: 0.72,
              child: UISheetSurface(
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Center(child: UISheetHandle()),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome_outlined),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l10n.aiGeneratedImageModelTitle,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.aiGeneratedImageModelDesc,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                        ),
                        const SizedBox(height: 18),
                        _buildContextRow(
                          icon: Icons.cloud_queue_outlined,
                          title: l10n.providerLabel,
                          value: providerName,
                          onTap: () async {
                            await _showProviderSheet(
                              currentProvider: _provider,
                              currentModel: _model,
                              onSelected: (provider, model) {
                                setState(() {
                                  _provider = provider;
                                  _model = model;
                                });
                                setModalState(() {});
                              },
                            );
                          },
                        ),
                        const SizedBox(height: AppTheme.spacing2),
                        _buildContextRow(
                          icon: Icons.auto_awesome_motion_outlined,
                          title: l10n.modelLabel,
                          value: modelName,
                          onTap: () async {
                            await _showModelSheet(
                              provider: _provider,
                              activeModel: _model,
                              onSelected: (model) {
                                setState(() => _model = model);
                                setModalState(() {});
                              },
                            );
                          },
                        ),
                        const Spacer(),
                        Text(
                          l10n.aiGeneratedImageModelUnconfiguredHint,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildContextRow({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacing3,
            vertical: AppTheme.spacing3,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showProviderSheet({
    required AIProvider? currentProvider,
    required String? currentModel,
    required void Function(AIProvider provider, String model) onSelected,
  }) async {
    final AIProvidersService svc = AIProvidersService.instance;
    final List<AIProvider> list = await svc.listProviders();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final int currentId = currentProvider?.id ?? -1;
        final TextEditingController queryCtrl = TextEditingController(
          text: _providerQueryText,
        );
        return StatefulBuilder(
          builder: (c, setModalState) {
            final String q = queryCtrl.text.trim().toLowerCase();
            final List<AIProvider> items = q.isEmpty
                ? List<AIProvider>.from(list)
                : list.where((p) {
                    final String name = p.name.toLowerCase();
                    final String type = p.type.toLowerCase();
                    final String base = (p.baseUrl ?? '').toLowerCase();
                    return name.contains(q) ||
                        type.contains(q) ||
                        base.contains(q);
                  }).toList();
            final int selectedIndex = items.indexWhere(
              (p) => p.id == currentId,
            );
            if (selectedIndex > 0) {
              final AIProvider selected = items.removeAt(selectedIndex);
              items.insert(0, selected);
            }
            return FractionallySizedBox(
              heightFactor: 0.88,
              child: UISheetSurface(
                child: Column(
                  children: [
                    const SizedBox(height: AppTheme.spacing3),
                    const UISheetHandle(),
                    const SizedBox(height: AppTheme.spacing3),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: SearchTextField(
                        controller: queryCtrl,
                        hintText: AppLocalizations.of(
                          context,
                        ).searchProviderPlaceholder,
                        autofocus: true,
                        onChanged: (value) {
                          _providerQueryText = value;
                          setModalState(() {});
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (c, i) => Container(
                          height: 1,
                          color: Theme.of(
                            c,
                          ).colorScheme.outline.withValues(alpha: 0.6),
                        ),
                        itemBuilder: (c, i) {
                          final AIProvider provider = items[i];
                          final bool selected = provider.id == currentId;
                          return ListTile(
                            leading: ProviderLogo(
                              providerType: provider.type,
                              providerName: provider.name,
                              baseUrl: provider.baseUrl,
                              size: 20,
                            ),
                            title: Text(
                              provider.name,
                              style: Theme.of(c).textTheme.bodyMedium,
                            ),
                            subtitle: Text(
                              provider.baseUrl ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: selected
                                ? Icon(
                                    Icons.check_circle,
                                    color: Theme.of(c).colorScheme.onSurface,
                                  )
                                : null,
                            onTap: () async {
                              String model = (currentModel ?? '').trim();
                              final List<String> available = provider.models;
                              if (model.isEmpty ||
                                  (available.isNotEmpty &&
                                      !available.contains(model))) {
                                model =
                                    (provider.extra['active_model']
                                                as String? ??
                                            provider.defaultModel)
                                        .toString()
                                        .trim();
                                if (model.isEmpty && available.isNotEmpty) {
                                  model = available.first;
                                }
                              }
                              if (model.isEmpty) {
                                UINotifier.error(
                                  context,
                                  AppLocalizations.of(
                                    context,
                                  ).noModelsForProviderHint,
                                );
                                return;
                              }
                              await _settings.setAIContextSelection(
                                context: 'image_generation',
                                providerId: provider.id!,
                                model: model,
                              );
                              if (!mounted || !ctx.mounted) return;
                              onSelected(provider, model);
                              Navigator.of(ctx).pop();
                              UINotifier.success(
                                context,
                                AppLocalizations.of(
                                  context,
                                ).aiGeneratedImageProviderSaved,
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
      },
    );
  }

  Future<void> _showModelSheet({
    required AIProvider? provider,
    required String? activeModel,
    required ValueChanged<String> onSelected,
  }) async {
    final AIProvider? p = provider;
    if (p == null) {
      UINotifier.info(
        context,
        AppLocalizations.of(context).pleaseSelectProviderFirst,
      );
      return;
    }
    final List<String> models = p.models;
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
        final String active = (activeModel ?? '').trim();
        final TextEditingController queryCtrl = TextEditingController(
          text: _modelQueryText,
        );
        return StatefulBuilder(
          builder: (c, setModalState) {
            final String q = queryCtrl.text.trim().toLowerCase();
            final List<String> items = q.isEmpty
                ? List<String>.from(models)
                : models.where((m) => m.toLowerCase().contains(q)).toList();
            if (active.isNotEmpty && items.contains(active)) {
              items.remove(active);
              items.insert(0, active);
            }
            return FractionallySizedBox(
              heightFactor: 0.88,
              child: UISheetSurface(
                child: Column(
                  children: [
                    const SizedBox(height: AppTheme.spacing3),
                    const UISheetHandle(),
                    const SizedBox(height: AppTheme.spacing3),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: SearchTextField(
                        controller: queryCtrl,
                        hintText: AppLocalizations.of(
                          context,
                        ).searchModelPlaceholder,
                        autofocus: true,
                        onChanged: (value) {
                          _modelQueryText = value;
                          setModalState(() {});
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (c, i) => Container(
                          height: 1,
                          color: Theme.of(
                            c,
                          ).colorScheme.outline.withValues(alpha: 0.6),
                        ),
                        itemBuilder: (c, i) {
                          final String model = items[i];
                          final bool selected = model == active;
                          return ListTile(
                            leading: ModelLogo(modelId: model, size: 20),
                            title: Text(
                              model,
                              style: Theme.of(c).textTheme.bodyMedium,
                            ),
                            trailing: selected
                                ? Icon(
                                    Icons.check_circle,
                                    color: Theme.of(c).colorScheme.onSurface,
                                  )
                                : null,
                            onTap: () async {
                              await _settings.setAIContextSelection(
                                context: 'image_generation',
                                providerId: p.id!,
                                model: model,
                              );
                              if (!mounted || !ctx.mounted) return;
                              onSelected(model);
                              Navigator.of(ctx).pop();
                              UINotifier.success(
                                context,
                                AppLocalizations.of(
                                  context,
                                ).aiGeneratedImageModelSaved,
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
      },
    );
  }

  void _handleSelected(String value) {
    switch (value) {
      case 'image_generation_model':
        _showSettingsSheet();
        break;
      case 'generated_images_history':
        Navigator.of(context).pushNamed('/generated_images_history');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return UIActionMenuButton<String>(
      tooltip: AppLocalizations.of(context).aiGeneratedImagesHistoryTitle,
      buttonIcon: const Icon(Icons.image_outlined),
      onSelected: _handleSelected,
      minWidth: 248,
      items: [
        UIActionMenuItem<String>(
          value: 'image_generation_model',
          label: AppLocalizations.of(context).aiGeneratedImageModelTitle,
        ),
        UIActionMenuItem<String>(
          value: 'generated_images_history',
          label: AppLocalizations.of(context).aiGeneratedImagesHistoryTitle,
        ),
      ],
    );
  }
}
