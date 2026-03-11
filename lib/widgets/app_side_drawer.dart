import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:screen_memo/l10n/app_localizations.dart';
import '../services/theme_service.dart';
import '../pages/provider_list_page.dart';
import '../pages/prompt_manager_page.dart';
import '../pages/nocturne_memory_page.dart';
import '../theme/app_theme.dart';
import '../services/ai_settings_service.dart';
import '../utils/model_icon_utils.dart';
import '../widgets/ui_components.dart';
import '../widgets/ui_dialog.dart';
import '../services/flutter_logger.dart';
import '../services/navigation_service.dart';
import '../pages/log_console_page.dart';

/// 侧边栏：简洁清爽，复用设置页面样式
class AppSideDrawer extends StatelessWidget {
  final ThemeService? themeService;

  const AppSideDrawer({super.key, this.themeService});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: AppTheme.spacing2),
            // 动态
            _buildMenuItem(
              context: context,
              icon: Icons.dynamic_feed_outlined,
              title: t.segmentStatusTitle,
              isFirst: true,
              onTap: () {
                Navigator.of(context).pop();
                NavigationService.instance.openSegmentStatus();
              },
            ),
            _buildMenuItem(
              context: context,
              icon: Icons.memory_outlined,
              title: '记忆',
              isFirst: false,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NocturneMemoryPage()),
                );
              },
            ),
            _buildMenuItem(
              context: context,
              icon: Icons.receipt_long_outlined,
              title: '日志面板',
              isFirst: false,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LogConsolePage()),
                );
              },
            ),
            // 提供商
            _buildMenuItem(
              context: context,
              icon: Icons.hub_outlined,
              title: t.providersTitle,
              isFirst: false,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => ProviderListPage()));
              },
            ),
            // 提示词管理
            _buildMenuItem(
              context: context,
              icon: Icons.tips_and_updates_outlined,
              title: t.promptManagerTitle,
              isFirst: false,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => PromptManagerPage()));
              },
            ),
            // —— 对话分割 + 会话列表 ——
            const SizedBox(height: AppTheme.spacing2),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing3,
                vertical: AppTheme.spacing2,
              ),
              child: Text(
                t.conversationsSectionTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            FutureBuilder<List<Object>>(
              future: Future.wait([
                AISettingsService.instance.listAiConversations(),
                AISettingsService.instance.getActiveConversationCid(),
              ]),
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing4,
                      vertical: AppTheme.spacing1,
                    ),
                    child: Text(
                      t.loadingConversations,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  );
                }
                if (!snap.hasData) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing4,
                      vertical: AppTheme.spacing1,
                    ),
                    child: Text(
                      t.noConversations,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  );
                }
                final list = (snap.data![0] as List)
                    .cast<Map<String, dynamic>>();
                final active = (snap.data![1] as String?) ?? '';
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing4,
                      vertical: AppTheme.spacing1,
                    ),
                    child: Text(
                      t.noConversations,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  );
                }

                // 将当前激活会话置顶
                final sortedList = List<Map<String, dynamic>>.from(list);
                sortedList.sort((a, b) {
                  final aCid = (a['cid'] as String?) ?? '';
                  final bCid = (b['cid'] as String?) ?? '';
                  if (aCid == active) return -1;
                  if (bCid == active) return 1;
                  // 其他按更新时间倒序
                  final aTime = (a['updated_at'] as int?) ?? 0;
                  final bTime = (b['updated_at'] as int?) ?? 0;
                  return bTime.compareTo(aTime);
                });

                return Column(
                  children: sortedList.map((c) {
                    final cid = (c['cid'] as String?) ?? '';
                    final rawTitle = (c['title'] as String?) ?? '';
                    final title = rawTitle.trim().isEmpty
                        ? t.untitledConversationLabel
                        : rawTitle;
                    final model = (c['model'] as String?) ?? '';
                    final isActive = active == cid;

                    return _buildConversationItem(
                      context: context,
                      cid: cid,
                      title: title,
                      model: model,
                      isActive: isActive,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 构建菜单项（完全复用设置页面的样式）
  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required bool isFirst,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.6),
            width: 1,
          ),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(
                icon,
                color: theme.colorScheme.onSecondaryContainer,
                size: 18,
              ),
            ),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.mutedForeground,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建会话列表项（支持长按删除，显示模型图标）
  Widget _buildConversationItem({
    required BuildContext context,
    required String cid,
    required String title,
    required String model,
    required bool isActive,
  }) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

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
      child: InkWell(
        onTap: () async {
          try {
            await AISettingsService.instance.setActiveConversationCid(cid);
          } catch (_) {}
          Navigator.of(context).pop();
        },
        onLongPress: () async {
          // 使用自定义对话框
          await showUIDialog<void>(
            context: context,
            title: t.deleteConversationTitle,
            message: t.confirmDeleteConversationMessage(title),
            actions: [
              UIDialogAction(text: t.dialogCancel),
              UIDialogAction(
                text: t.actionDelete,
                style: UIDialogActionStyle.destructive,
                onPressed: (ctx) async {
                  try {
                    final sw = Stopwatch()..start();
                    Navigator.of(ctx).pop();
                    // 触发重建（数据源来自 FutureBuilder，不做本地列表回滚）
                    (context as Element).markNeedsBuild();
                    final ok = await AISettingsService.instance
                        .deleteConversation(cid);
                    sw.stop();
                    try {
                      await FlutterLogger.nativeInfo(
                        'UI',
                        'SideDrawer 删除对话总耗时(毫秒)=' +
                            sw.elapsedMilliseconds.toString(),
                      );
                    } catch (_) {}
                    // 记录“完全清空”耗时：从删除返回到FutureBuilder下一次完成的时间
                    final sw2 = Stopwatch()..start();
                    // 触发一次 rebuild 后，在下一帧读取列表为空的时刻打印
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      sw2.stop();
                      try {
                        await FlutterLogger.nativeInfo(
                          'UI',
                          'SideDrawer 清空后首帧耗时(毫秒)=' +
                              sw2.elapsedMilliseconds.toString(),
                        );
                      } catch (_) {}
                    });
                    if (!ok) {
                      UINotifier.error(context, t.deleteFailed);
                      (context as Element).markNeedsBuild();
                    } else {
                      UINotifier.success(context, t.deletedToast);
                    }
                  } catch (e) {
                    UINotifier.error(
                      ctx,
                      t.deleteFailedWithError(e.toString()),
                    );
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
    );
  }
}
