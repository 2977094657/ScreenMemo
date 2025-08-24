import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// iOS风格布局 + shadcn 扁平视觉的通用弹窗
/// - 无阴影
/// - 小圆角(6-8px)
/// - 细边框或无边框
/// - 动作按钮水平排列（<=2个），超过则纵向排列
class UIDialogAction<T> {
  final String text;
  final UIDialogActionStyle style;
  final T? result;
  final Future<void> Function(BuildContext context)? onPressed;
  final bool closeOnPress;

  const UIDialogAction({
    required this.text,
    this.style = UIDialogActionStyle.normal,
    this.result,
    this.onPressed,
    this.closeOnPress = true,
  });
}

enum UIDialogActionStyle { normal, primary, destructive }

Future<T?> showUIDialog<T>({
  required BuildContext context,
  String? title,
  Widget? titleWidget,
  String? message,
  Widget? content,
  List<UIDialogAction<T>> actions = const [],
  bool barrierDismissible = true,
}) {
  final theme = Theme.of(context);
  final surface = theme.colorScheme.surface;
  final onSurface = theme.colorScheme.onSurface;
  final borderColor = theme.colorScheme.outline;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dialog',
    barrierColor: Colors.black.withOpacity(0.5),
    pageBuilder: (ctx, _, __) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 300,
                minWidth: 240,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(color: borderColor, width: 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    if (title != null || titleWidget != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.spacing6,
                          AppTheme.spacing6,
                          AppTheme.spacing6,
                          AppTheme.spacing2,
                        ),
                        child: DefaultTextStyle(
                          style: theme.textTheme.titleLarge!.copyWith(
                            fontWeight: FontWeight.w600,
                            color: onSurface,
                          ),
                          child: Center(
                            child: titleWidget ?? Text(title!),
                          ),
                        ),
                      ),
                    if (message != null || content != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.spacing6,
                          AppTheme.spacing2,
                          AppTheme.spacing6,
                          AppTheme.spacing4,
                        ),
                        child: DefaultTextStyle(
                          style: theme.textTheme.bodyMedium!.copyWith(color: onSurface),
                          child: message != null ? Text(message, textAlign: TextAlign.center) : content!,
                        ),
                      ),
                    _buildActionsSection(context, actions),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 160),
  );
}

Widget _buildActionsSection<T>(BuildContext context, List<UIDialogAction<T>> actions) {
  final theme = Theme.of(context);
  final divider = theme.colorScheme.outline.withOpacity(0.6);
  final onSurface = theme.colorScheme.onSurface;

  Color _resolveColor(UIDialogActionStyle style) {
    switch (style) {
      case UIDialogActionStyle.destructive:
        return AppTheme.destructive;
      case UIDialogActionStyle.primary:
        return theme.colorScheme.primary;
      case UIDialogActionStyle.normal:
      default:
        return onSurface;
    }
  }

  Future<void> _handleTap(UIDialogAction<T> action) async {
    if (action.onPressed != null) {
      await action.onPressed!(context);
    }
    if (action.closeOnPress) {
      // 只有在未自行关闭时才尝试关闭
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop<T>(action.result);
      }
    }
  }

  if (actions.isEmpty) {
    return const SizedBox.shrink();
  }

  if (actions.length <= 2) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: divider, width: 1)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < actions.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 44,
                color: divider,
              ),
            Expanded(
              child: SizedBox(
                height: 44,
                child: TextButton(
                  onPressed: () => _handleTap(actions[i]),
                  style: TextButton.styleFrom(
                    foregroundColor: _resolveColor(actions[i].style),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
                  ),
                  child: Text(
                    actions[i].text,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 超过2个时纵向排列
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (int i = 0; i < actions.length; i++) ...[
        if (i == 0)
          Container(
            height: 1,
            color: divider,
          )
        else
          Container(
            height: 1,
            margin: const EdgeInsets.only(left: 0),
            color: divider,
          ),
        SizedBox(
          height: 44,
          child: TextButton(
            onPressed: () => _handleTap(actions[i]),
            style: TextButton.styleFrom(
              foregroundColor: _resolveColor(actions[i].style),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
            ),
            child: Text(
              actions[i].text,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    ],
  );
}


