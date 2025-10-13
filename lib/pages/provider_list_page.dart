// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:screen_memo/widgets/ui_components.dart';
import 'package:screen_memo/l10n/app_localizations.dart';

import '../services/ai_providers_service.dart';
import '../utils/model_icon_utils.dart';
import '../theme/app_theme.dart';
import 'provider_edit_page.dart';

/// 提供商列表页：
/// - 右上角「新建」
/// - 列表展示：名称、类型、Base URL 简述、模型数量
/// - 操作：编辑、删除、设为默认、启用/禁用
/// - 点击列表项或编辑进入详情
class ProviderListPage extends StatefulWidget {
  const ProviderListPage({super.key});

  @override
  State<ProviderListPage> createState() => _ProviderListPageState();
}

class _ProviderListPageState extends State<ProviderListPage> {
  final _svc = AIProvidersService.instance;

  bool _loading = true;
  List<AIProvider> _list = <AIProvider>[];
  // 查询文本持久化
  String _modelQueryText = '';

  @override
  void initState() {
    super.initState();
    // 预加载图标清单，确保首屏动态图标匹配（含无 -color 后缀）
    ModelIconUtils.preload();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _svc.listProviders();
      setState(() => _list = rows);
    } catch (e) {
      UINotifier.error(context, AppLocalizations.of(context).pleaseTryAgain);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _typeLabel(String t) {
    switch (t) {
      case AIProviderTypes.openai:
        return 'OpenAI';
      case AIProviderTypes.azureOpenAI:
        return 'Azure OpenAI';
      case AIProviderTypes.claude:
        return 'Claude';
      case AIProviderTypes.gemini:
        return 'Gemini';
      case AIProviderTypes.custom:
        return AppLocalizations.of(context).customLabel;
      default:
        return t;
    }
  }

  String _briefUrl(String? url) {
    final s = (url ?? '').trim();
    if (s.isEmpty) return '-';
    return s.length > 48 ? '${s.substring(0, 48)}…' : s;
    }

  Future<void> _onNew() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ProviderEditPage()),
    );
    if (ok == true) await _load();
  }

  Future<void> _onEdit(AIProvider p) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProviderEditPage(providerId: p.id)),
    );
    if (ok == true) await _load();
  }

  Future<void> _onToggleEnable(AIProvider p) async {
    final ok = await _svc.updateProvider(id: p.id!, enabled: !p.enabled);
    if (!ok) {
      UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      return;
    }
    await _load();
  }

  Future<void> _onSetDefault(AIProvider p) async {
    final ok = await _svc.setDefault(p.id!);
    if (!ok) {
      UINotifier.error(context, AppLocalizations.of(context).operationFailed);
      return;
    }
    UINotifier.success(context, AppLocalizations.of(context).saveSuccess);
    await _load();
  }

  Future<void> _onDelete(AIProvider p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).dialogCancel.replaceAll('Cancel','').isEmpty ? AppLocalizations.of(ctx).deleteGroup : AppLocalizations.of(ctx).deleteGroup),
        content: Text(AppLocalizations.of(ctx).confirmDeleteProviderMessage(p.name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(AppLocalizations.of(ctx).dialogCancel)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(AppLocalizations.of(ctx).actionDelete)),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await _svc.deleteProvider(p.id!);
    if (!ok) {
      UINotifier.error(context, AppLocalizations.of(context).deleteFailed);
      return;
    }
    UINotifier.success(context, AppLocalizations.of(context).deletedToast);
    await _load();
  }

  // 厂商 SVG 图标路径（使用公共工具）
  String _vendorIconPath(String type) {
    return ModelIconUtils.getProviderIconPath(type);
  }
 
  // 当前启用模型（兼容旧字段）
  String _activeModelOf(AIProvider p) {
    final act = (p.extra['active_model'] as String?) ?? (p.extra['default_model'] as String?);
    if (act != null && act.trim().isNotEmpty) return act.trim();
    if (p.models.isNotEmpty) return p.models.first;
    return '—';
  }
 
  Future<void> _openModelSheet(AIProvider p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final models = p.models;
        final active = _activeModelOf(p);

        // 控制器与文本持久化，避免键盘折叠时内容丢失
        final TextEditingController queryCtrl = TextEditingController(text: _modelQueryText);
        return StatefulBuilder(
          builder: (c, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollCtrl) {
                final q = queryCtrl.text.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? List<String>.from(models)
                    : models.where((m) => m.toLowerCase().contains(q)).toList();
                // 选中的模型置顶展示
                final idx = filtered.indexWhere((e) => e == active);
                if (idx > 0) {
                  final sel = filtered.removeAt(idx);
                  filtered.insert(0, sel);
                }

                return SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          AppLocalizations.of(context).selectModelWithCounts(filtered.length, models.length),
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
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
                            hintText: AppLocalizations.of(context).searchModelPlaceholder,
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      if (models.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                          child: Text(
                            AppLocalizations.of(context).noModelsDetectedHint,
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.separated(
                            controller: scrollCtrl,
                            itemCount: filtered.length,
                            separatorBuilder: (c, i) => Container(
                              height: 1,
                              color: Theme.of(c).colorScheme.outline.withOpacity(0.6),
                            ),
                            itemBuilder: (c, i) {
                              final m = filtered[i];
                              final selected = m == active;
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppTheme.spacing4,
                                  vertical: AppTheme.spacing1,
                                ),
                                leading: SvgPicture.asset(
                                  ModelIconUtils.getIconPath(m),
                                  width: 22,
                                  height: 22,
                                ),
                                title: Text(
                                  m,
                                  style: Theme.of(ctx).textTheme.bodyMedium,
                                ),
                                trailing: selected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Theme.of(ctx).colorScheme.primary,
                                      size: 22,
                                    )
                                  : null,
                                onTap: () async {
                                  final newExtra = Map<String, dynamic>.from(p.extra);
                                  newExtra['active_model'] = m;
                                  if (newExtra.containsKey('default_model')) {
                                    newExtra.remove('default_model');
                                  }
                                  final ok = await _svc.updateProvider(id: p.id!, extra: newExtra);
                                  if (ok && mounted) {
                                    Navigator.of(ctx).pop();
                                    UINotifier.success(context, AppLocalizations.of(context).modelSwitchedToast(m));
                                    await _load();
                                  } else {
                                    UINotifier.error(context, AppLocalizations.of(context).operationFailed);
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 8),
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
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).providersTitle),
        actions: [
          TextButton.icon(
            onPressed: _onNew,
            icon: Icon(Icons.add),
            label: Text(AppLocalizations.of(context).actionNew),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _load,
              child: _list.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Text(AppLocalizations.of(context).noProvidersYetHint,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ],
                    )
                  : ListView.separated(
                   padding: const EdgeInsets.symmetric(vertical: AppTheme.spacing2),
                   itemCount: _list.length,
                   separatorBuilder: (context, _) => Container(
                     height: 1,
                     color: Theme.of(context).colorScheme.outline.withOpacity(0.6),
                   ),
                   itemBuilder: (context, index) {
                       final p = _list[index];
                       final modelsCount = p.models.length;
                       final activeModel = _activeModelOf(p);

                       return Container(
                         margin: const EdgeInsets.symmetric(
                           horizontal: AppTheme.spacing2,
                           vertical: 2,
                         ),
                         decoration: BoxDecoration(
                           borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                         ),
                         child: Material(
                           color: Colors.transparent,
                           child: InkWell(
                             borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                             onTap: () => _onEdit(p),
                             child: Padding(
                               padding: const EdgeInsets.symmetric(
                                 horizontal: AppTheme.spacing3,
                                 vertical: AppTheme.spacing3,
                               ),
                               child: Row(
                                 children: [
                                   // 提供商图标
                                   Container(
                                     width: 44,
                                     height: 44,
                                     decoration: BoxDecoration(
                                       color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                                       borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                                     ),
                                     padding: const EdgeInsets.all(10),
                                     child: SvgPicture.asset(
                                       _vendorIconPath(p.type),
                                       width: 24,
                                       height: 24,
                                     ),
                                   ),
                                   const SizedBox(width: AppTheme.spacing3),
                                   // 名称和模型信息
                                   Expanded(
                                     child: Column(
                                       crossAxisAlignment: CrossAxisAlignment.start,
                                       children: [
                                         Text(
                                           p.name,
                                           style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                                 fontWeight: FontWeight.w600,
                                                 letterSpacing: 0.15,
                                               ),
                                         ),
                                         const SizedBox(height: 4),
                                         GestureDetector(
                                           onTap: () => _openModelSheet(p),
                          child: Row(
                                             children: [
                                               SvgPicture.asset(
                                                 ModelIconUtils.getIconPath(activeModel),
                                                 width: 14,
                                                 height: 14,
                                               ),
                                               const SizedBox(width: 6),
                                               Flexible(
                                                 child: Text(
                                                   activeModel,
                                                   style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                         color: Theme.of(context).colorScheme.primary,
                                                         fontWeight: FontWeight.w500,
                                                         decoration: TextDecoration.underline,
                                        decorationColor: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                                                       ),
                                                   overflow: TextOverflow.ellipsis,
                                                 ),
                                               ),
                                             ],
                                           ),
                                         ),
                                       ],
                                     ),
                                   ),
                                   // 模型数量标签
                                   Container(
                                     padding: const EdgeInsets.symmetric(
                                       horizontal: 10,
                                       vertical: 6,
                                     ),
                                     decoration: BoxDecoration(
                                       color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.6),
                                       borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                                       border: Border.all(
                                         color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                                         width: 0.5,
                                       ),
                                     ),
                                     child: Row(
                                       mainAxisSize: MainAxisSize.min,
                                       children: [
                                         Icon(
                                           Icons.inventory_2_outlined,
                                           size: 15,
                                           color: Theme.of(context).colorScheme.onSecondaryContainer,
                                         ),
                                         const SizedBox(width: 5),
                                         Text(
                                           modelsCount.toString(),
                                           style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                 color: Theme.of(context).colorScheme.onSecondaryContainer,
                                                 fontWeight: FontWeight.w600,
                                                 fontSize: 13,
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
                       );
                     },
                   ),
            ),
    );
  }
}