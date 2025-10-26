import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import 'ai_settings_page.dart';
import 'segment_status_page.dart';
import '../services/ai_settings_service.dart';
import '../widgets/ui_components.dart';
import '../services/ai_chat_service.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../widgets/app_side_drawer.dart';
import 'provider_list_page.dart';
import '../utils/model_icon_utils.dart';
import '../services/ai_providers_service.dart';
import '../widgets/ui_dialog.dart';
import '../services/flutter_logger.dart';

class EventHomePage extends StatefulWidget {
  const EventHomePage({super.key});

  @override
  State<EventHomePage> createState() => _EventHomePageState();
}

class _EventHomePageState extends State<EventHomePage> {
  final AISettingsService _settings = AISettingsService.instance;
  String? _model;
  String? _iconAsset;
  bool _loading = true;

  // 基于提供商表的“对话(chat)”上下文（置于 AppBar 顶部）
  AIProvider? _ctxProvider;
  String? _ctxModel;
  bool _ctxLoading = true;
  StreamSubscription<String>? _ctxChangedSub;
  Key _chatViewKey = UniqueKey();

  // 底部选择面板查询文本持久化，避免键盘收起或重建导致清空
  String _providerQueryText = '';
  String _modelQueryText = '';

  // —— 会话列表（侧边栏显示） ——
  List<Map<String, dynamic>> _conversations = <Map<String, dynamic>>[];
  String? _activeConversationCid;
  bool _convLoading = true;

 @override
 void initState() {
   super.initState();
   _loadChatContextSelection();
   _loadConversations();
    _ctxChangedSub = AISettingsService.instance.onContextChanged.listen((ctx) {
     if (ctx == 'chat' && mounted) {
       _loadChatContextSelection();
       _loadConversations();
     }
      if (ctx == 'chat:deleted' && mounted) {
        // UI 完全清空计时：从收到事件开始到列表空并首次帧绘制
        final sw = Stopwatch()..start();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          sw.stop();
          try { await FlutterLogger.nativeInfo('UI', 'EventHome cleared first-frame ms='+sw.elapsedMilliseconds.toString()); } catch (_) {}
        });
      }
   });
   // 不再需要等待旧的模型加载；直接进入正文视图
   _loading = false;
 }

  @override
  void dispose() {
    _ctxChangedSub?.cancel();
    super.dispose();
  }

  Future<void> _loadModel() async {
    try {
      final m = await _settings.getModel();
      String? icon = _pickIconFor(m);
      if (!mounted) return;
      setState(() {
        _model = m;
        _iconAsset = icon;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  String? _pickIconFor(String? model) {
    if (model == null || model.trim().isEmpty) return null;
    return ModelIconUtils.getIconPath(model);
  }

  // 载入“动态(segments)”的提供商/模型选择（顶部 AppBar 使用）
  Future<void> _loadChatContextSelection() async {
    try {
      final svc = AIProvidersService.instance;
      final providers = await svc.listProviders();
      if (providers.isEmpty) {
        if (mounted) {
          setState(() {
            _ctxProvider = null;
            _ctxModel = null;
            _ctxLoading = false;
          });
        }
        return;
      }
      final ctxRow = await _settings.getAIContextRow('chat');
      AIProvider? sel;
      if (ctxRow != null && ctxRow['provider_id'] is int) {
        sel = await svc.getProvider(ctxRow['provider_id'] as int);
      }
      sel ??= await svc.getDefaultProvider();
      sel ??= providers.first;

      String model = (ctxRow != null && (ctxRow['model'] as String?)?.trim().isNotEmpty == true)
          ? (ctxRow['model'] as String).trim()
          : ((sel.extra['active_model'] as String?) ?? sel.defaultModel).toString().trim();
      if (model.isEmpty || (sel.models.isNotEmpty && !sel.models.contains(model))) {
        final String fb = ((sel.extra['active_model'] as String?) ?? sel.defaultModel).toString().trim();
        model = fb.isNotEmpty ? fb : (sel.models.isNotEmpty ? sel.models.first : model);
      }

      if (mounted) {
        setState(() {
          _ctxProvider = sel;
          _ctxModel = model;
          _ctxLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ctxLoading = false);
    }
  }

 // —— 会话：加载/新建/切换 ——
 Future<void> _loadConversations() async {
   try {
     final list = await _settings.listAiConversations();
     final active = await _settings.getActiveConversationCid();
     if (!mounted) return;
     setState(() {
       _conversations = list;
       _activeConversationCid = active;
       _convLoading = false;
     });
   } catch (_) {
     if (!mounted) return;
     setState(() => _convLoading = false);
   }
 }

 Future<void> _newConversation() async {
   try {
    final cid = await _settings.createConversation(title: '');
     if (!mounted) return;
    UINotifier.success(context, AppLocalizations.of(context).savedCurrentGroupToast);
     setState(() {
       _activeConversationCid = cid;
       _chatViewKey = UniqueKey();
     });
     await _loadConversations();
   } catch (e) {
     if (!mounted) return;
     UINotifier.error(context, 'Create failed: ${e.toString()}');
   }
 }

 Future<void> _switchConversation(String cid) async {
   try {
     await _settings.setActiveConversationCid(cid);
     if (!mounted) return;
     setState(() {
       _activeConversationCid = cid;
       _chatViewKey = UniqueKey();
     });
     UINotifier.success(context, '已切换会话');
     await _loadConversations();
   } catch (e) {
     if (!mounted) return;
     UINotifier.error(context, 'Switch failed: ${e.toString()}');
   }
 }

 Future<void> _showProviderSheetChat() async {
    final svc = AIProvidersService.instance;
    final list = await svc.listProviders();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final currentId = _ctxProvider?.id ?? -1;
        // 将控制器移到 StatefulBuilder 外部，并使用持久化文本初始化
        final TextEditingController queryCtrl = TextEditingController(text: _providerQueryText);
        return StatefulBuilder(
          builder: (c, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
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
                  return name.contains(q) || type.contains(q) || base.contains(q);
                }).toList();
                // 将当前选中的提供商置顶，便于观察
                final selIdx = filtered.indexWhere((e) => e.id == currentId);
                if (selIdx > 0) {
                  final sel = filtered.removeAt(selIdx);
                  filtered.insert(0, sel);
                }
                return SafeArea(
                  child: Column(
                    children: [
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
                            hintText: AppLocalizations.of(context).searchProviderPlaceholder,
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          separatorBuilder: (c, i) => Container(
                            height: 1,
                            color: Theme.of(c).colorScheme.outline.withOpacity(0.6),
                          ),
                          itemBuilder: (c, i) {
                            final p = filtered[i];
                            final selected = p.id == currentId;
                            return ListTile(
                              leading: SvgPicture.asset(
                                ModelIconUtils.getProviderIconPath(p.type),
                                width: 20, height: 20,
                              ),
                              title: Text(p.name, style: Theme.of(c).textTheme.bodyMedium),
                              trailing: selected ? Icon(Icons.check_circle, color: Theme.of(c).colorScheme.primary) : null,
                              onTap: () async {
                                String model = (_ctxModel ?? '').trim();
                                final List<String> available = p.models;
                                if (model.isEmpty || (available.isNotEmpty && !available.contains(model))) {
                                  String fb = (p.extra['active_model'] as String? ?? p.defaultModel).toString().trim();
                                  if (fb.isEmpty && available.isNotEmpty) fb = available.first;
                                  model = fb;
                                }
                                await _settings.setAIContextSelection(context: 'chat', providerId: p.id!, model: model);
                                if (mounted) {
                                  setState(() {
                                    _ctxProvider = p;
                                    _ctxModel = model;
                                  });
                                  Navigator.of(ctx).pop();
                                  UINotifier.success(context, AppLocalizations.of(context).providerSelectedToast(p.name));
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

  Future<void> _showModelSheetChat() async {
    final p = _ctxProvider;
    if (p == null) {
      UINotifier.info(context, AppLocalizations.of(context).pleaseSelectProviderFirst);
      return;
    }
    final models = p.models;
    if (models.isEmpty) {
      UINotifier.info(context, AppLocalizations.of(context).noModelsForProviderHint);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final active = (_ctxModel ?? '').trim();
        // 将控制器移到 StatefulBuilder 外部，并使用持久化文本初始化
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
                final filtered = models.where((mm) {
                  if (q.isEmpty) return true;
                  return mm.toLowerCase().contains(q);
                }).toList();
                // 将当前选中的模型置顶，便于观察
                if (active.isNotEmpty && filtered.contains(active)) {
                  final idx = filtered.indexOf(active);
                  if (idx > 0) {
                    final sel = filtered.removeAt(idx);
                    filtered.insert(0, sel);
                  }
                }
                return SafeArea(
                  child: Column(
                    children: [
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
                              leading: SvgPicture.asset(
                                ModelIconUtils.getIconPath(m),
                                width: 20, height: 20,
                              ),
                              title: Text(m, style: Theme.of(c).textTheme.bodyMedium),
                              trailing: selected ? Icon(Icons.check_circle, color: Theme.of(c).colorScheme.primary) : null,
                              onTap: () async {
                                await _settings.setAIContextSelection(context: 'chat', providerId: p.id!, model: m);
                                if (mounted) {
                                  setState(() => _ctxModel = m);
                                  Navigator.of(ctx).pop();
                                  UINotifier.success(context, AppLocalizations.of(context).modelSwitchedToast(m));
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

  /// AppBar 顶部：仅显示内容并加下划线（provider / model），不显示“提供商”字样
  Widget _buildChatProviderModelAppBarTitle() {
    final theme = Theme.of(context);
    final String providerName = (_ctxProvider?.name ?? '—');
    final String modelName = (_ctxModel ?? '—');
    final TextStyle? link = theme.textTheme.labelSmall?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.onSurface.withOpacity(0.6),
      color: theme.colorScheme.onSurface,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 左侧 SVG 图标（基于模型名的正则匹配方法）
        if (modelName.trim().isNotEmpty && modelName != '—') ...[
          SvgPicture.asset(
            ModelIconUtils.getIconPath(modelName),
            width: 18,
            height: 18,
          ),
          const SizedBox(width: 6),
        ],
        // Provider 名称（下划线，可点击）
        Flexible(
          child: GestureDetector(
            onTap: _showProviderSheetChat,
            behavior: HitTestBehavior.opaque,
            child: Text(
              providerName,
              style: link,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // 模型名称（下划线，可点击）
        Flexible(
          child: GestureDetector(
            onTap: _showModelSheetChat,
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titleText = (_model == null || _model!.trim().isEmpty) ? '—' : _model!;
    final titleWidget = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_iconAsset != null) ...[
          SvgPicture.asset(
            _iconAsset!,
            width: 18,
            height: 18,
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            titleText,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Scaffold(
      drawer: const AppSideDrawer(),
      drawerEnableOpenDragGesture: false,
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: _buildChatProviderModelAppBarTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: '新建会话',
            onPressed: () async {
              await _newConversation();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : LayoutBuilder(
              builder: (context, constraints) {
                final showSidebar = constraints.maxWidth >= 960;
                if (!showSidebar) {
                  return AISettingsPage(embedded: true, key: _chatViewKey);
                }
                final theme = Theme.of(context);
                return Row(
                  children: [
                    // 左侧侧边栏（仅宽屏显示）
                    Container(
                      width: 260,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        border: Border(
                          right: BorderSide(
                            color: theme.colorScheme.outlineVariant,
                            width: 1,
                          ),
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppTheme.spacing4,
                            horizontal: AppTheme.spacing2,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.spacing3,
                                vertical: AppTheme.spacing2,
                              ),
                              child: Text(
                                l10n.aiAssistantTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.spacing3,
                                vertical: AppTheme.spacing2,
                              ),
                              child: Container(
                                height: 1,
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            _buildSidebarTile(
                              context: context,
                              icon: Icons.add_circle_outline,
                              title: l10n.clearConversation,
                              onTap: () async {
                                try {
                                  await AIChatService.instance.clearConversation();
                                  if (mounted) {
                                    UINotifier.success(context, l10n.clearSuccess);
                                    setState(() {
                                      _chatViewKey = UniqueKey();
                                    });
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    UINotifier.error(
                                      context,
                                      l10n.clearFailedWithError(e.toString()),
                                    );
                                  }
                                }
                              },
                            ),
                            // —— 聊天分割（会话列表） ——
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.spacing3,
                                vertical: AppTheme.spacing2,
                              ),
                              child: Text(
                                '对话',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            if (_convLoading)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing1),
                                child: Text('正在加载会话…', style: Theme.of(context).textTheme.bodySmall),
                              )
                            else ...(() {
                              // 将当前激活会话置顶
                              final sortedConvs = List<Map<String, dynamic>>.from(_conversations);
                              sortedConvs.sort((a, b) {
                                final aCid = (a['cid'] as String?) ?? '';
                                final bCid = (b['cid'] as String?) ?? '';
                                if (aCid == (_activeConversationCid ?? '')) return -1;
                                if (bCid == (_activeConversationCid ?? '')) return 1;
                                final aTime = (a['updated_at'] as int?) ?? 0;
                                final bTime = (b['updated_at'] as int?) ?? 0;
                                return bTime.compareTo(aTime);
                              });
                              
                              return sortedConvs.map((c) {
                                final cid = (c['cid'] as String?) ?? '';
                                final title = ((c['title'] as String?) ?? '').trim().isEmpty ? '未命名会话' : (c['title'] as String);
                                final model = (c['model'] as String?) ?? '';
                                final isActive = (_activeConversationCid ?? '') == cid;
                                
                                return _buildConversationTile(
                                  context: context,
                                  cid: cid,
                                  title: title,
                                  model: model,
                                  isActive: isActive,
                                );
                              }).toList();
                            })(),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.spacing4,
                                vertical: AppTheme.spacing2,
                              ),
                              child: Container(
                                height: 1,
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            _buildSidebarTile(
                              context: context,
                              icon: Icons.hub_outlined,
                              title: '提供商',
                              iconWeight: FontWeight.w400,
                              textWeight: FontWeight.w400,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const ProviderListPage()),
                                );
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.spacing4,
                                vertical: AppTheme.spacing2,
                              ),
                              child: Container(
                                height: 1,
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            _buildSidebarTile(
                              context: context,
                              icon: Icons.dynamic_feed_outlined,
                              title: l10n.segmentStatusTitle,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const SegmentStatusPage()),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: AISettingsPage(embedded: true, key: _chatViewKey)),
                  ],
                );
              },
            ),
    );
  }

  /// 构建优化后的侧边栏选项
  Widget _buildSidebarTile({
    required BuildContext context,
    IconData? icon,
    String? svgIcon,
    required String title,
    required VoidCallback onTap,
    FontWeight? iconWeight,
    FontWeight? textWeight,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: 2,
      ),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.4),
            width: 0.5,
          ),
        ),
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
                if (icon != null)
                  Icon(
                    icon,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                else if (svgIcon != null)
                  SvgPicture.asset(
                    svgIcon,
                    width: 20,
                    height: 20,
                    colorFilter: ColorFilter.mode(
                      theme.colorScheme.onSurfaceVariant,
                      BlendMode.srcIn,
                    ),
                  ),
                const SizedBox(width: AppTheme.spacing3),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: textWeight ?? FontWeight.w500,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建会话列表项（支持长按删除，显示模型图标）
  Widget _buildConversationTile({
    required BuildContext context,
    required String cid,
    required String title,
    required String model,
    required bool isActive,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withOpacity(0.15)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.6),
            width: 1,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await _switchConversation(cid);
          },
          onLongPress: () async {
            // 使用自定义对话框
            await showUIDialog<void>(
              context: context,
              title: '删除会话',
              message: '确定要删除会话"$title"吗？',
              actions: [
                UIDialogAction(text: '取消'),
                UIDialogAction(
                  text: '删除',
                  style: UIDialogActionStyle.destructive,
                  onPressed: (ctx) async {
                    try {
                      final sw = Stopwatch()..start();
                      // 乐观更新，避免UI等待数据库事务
                      final prev = List<Map<String, dynamic>>.from(_conversations);
                      setState(() {
                        _conversations.removeWhere((m) => ((m['cid'] as String?) ?? '') == cid);
                        if (_activeConversationCid == cid) {
                          _activeConversationCid = _conversations.isNotEmpty ? (_conversations.first['cid'] as String?) : 'default';
                        }
                      });
                      Navigator.of(ctx).pop();
                      final ok = await _settings.deleteConversation(cid);
                      sw.stop();
                      try { await FlutterLogger.nativeInfo('UI', 'EventHome.deleteConversation total ms='+sw.elapsedMilliseconds.toString()); } catch (_) {}
                      if (!ok) {
                        if (mounted) setState(() { _conversations = prev; });
                        if (mounted) UINotifier.error(context, '删除失败');
                        return;
                      }
                      await _loadConversations();
                      if (mounted) {
                        UINotifier.success(context, '会话已删除');
                      }
                    } catch (e) {
                      if (mounted) {
                        UINotifier.error(context, '删除失败: ${e.toString()}');
                      }
                    }
                  },
                ),
              ],
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing3,
              vertical: AppTheme.spacing3,
            ),
            child: Row(
              children: [
                // 显示模型图标（使用原始SVG颜色）
                SizedBox(
                  width: 36,
                  height: 36,
                  child: model.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: SvgPicture.asset(
                            ModelIconUtils.getIconPath(model),
                            width: 20,
                            height: 20,
                            // 不使用colorFilter，保留原始颜色
                          ),
                        )
                      : Icon(
                          Icons.chat_bubble_outline,
                          color: theme.colorScheme.onSurfaceVariant,
                          size: 18,
                        ),
                ),
                const SizedBox(width: AppTheme.spacing3),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive ? theme.colorScheme.primary : null,
                      letterSpacing: 0.15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive)
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}