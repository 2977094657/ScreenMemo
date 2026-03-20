import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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

class UIDialogs {
  static Future<void> showInfo(
    BuildContext context, {
    required String title,
    required String message,
    String okText = '知道了',
  }) async {
    await showUIDialog<void>(
      context: context,
      title: title,
      message: message,
      actions: <UIDialogAction<void>>[
        UIDialogAction<void>(
          text: okText,
          style: UIDialogActionStyle.primary,
          result: null,
        ),
      ],
    );
  }

  static Future<bool> showConfirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = '确定',
    String cancelText = '取消',
    bool destructive = false,
  }) async {
    final bool? ok = await showUIDialog<bool>(
      context: context,
      title: title,
      message: message,
      barrierDismissible: true,
      actions: <UIDialogAction<bool>>[
        UIDialogAction<bool>(
          text: cancelText,
          style: UIDialogActionStyle.normal,
          result: false,
        ),
        UIDialogAction<bool>(
          text: confirmText,
          style: destructive
              ? UIDialogActionStyle.destructive
              : UIDialogActionStyle.primary,
          result: true,
        ),
      ],
    );
    return ok == true;
  }
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
  final cs = theme.colorScheme;
  final bool isDark = theme.brightness == Brightness.dark;
  final Color surface = theme.dialogTheme.backgroundColor ?? cs.surface;
  final Color borderColor = cs.outlineVariant.withValues(
    alpha: isDark ? 0.95 : 1.0,
  );

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dialog',
    barrierColor: cs.scrim.withValues(alpha: isDark ? 0.62 : 0.48),
    pageBuilder: (ctx, _, __) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360, minWidth: 280),
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
                              color: cs.onSurface,
                            ),
                            child: Center(child: titleWidget ?? Text(title!)),
                          ),
                        ),
                      if (message != null || content != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.spacing6,
                            AppTheme.spacing2,
                            AppTheme.spacing6,
                            AppTheme.spacing5,
                          ),
                          child: DefaultTextStyle(
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.45,
                            ),
                            child: message != null
                                ? Text(message, textAlign: TextAlign.center)
                                : content!,
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
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 170),
  );
}

Widget _buildActionsSection<T>(
  BuildContext context,
  List<UIDialogAction<T>> actions,
) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final divider = cs.outlineVariant.withValues(alpha: 0.9);

  Color resolveColor(UIDialogActionStyle style) {
    switch (style) {
      case UIDialogActionStyle.destructive:
        return cs.error;
      case UIDialogActionStyle.primary:
        return cs.primary;
      case UIDialogActionStyle.normal:
        return cs.onSurfaceVariant;
    }
  }

  FontWeight resolveWeight(UIDialogActionStyle style) {
    switch (style) {
      case UIDialogActionStyle.normal:
        return FontWeight.w500;
      case UIDialogActionStyle.primary:
      case UIDialogActionStyle.destructive:
        return FontWeight.w600;
    }
  }

  Future<void> handleTap(UIDialogAction<T> action) async {
    final navigator = Navigator.of(context);
    if (action.onPressed != null) {
      await action.onPressed!(context);
    }
    if (action.closeOnPress && navigator.canPop()) {
      navigator.pop<T>(action.result);
    }
  }

  if (actions.isEmpty) {
    return const SizedBox.shrink();
  }

  ButtonStyle actionStyle(UIDialogAction<T> action) {
    final foreground = resolveColor(action.style);
    return TextButton.styleFrom(
      foregroundColor: foreground,
      overlayColor: foreground.withValues(alpha: 0.08),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
      textStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: resolveWeight(action.style),
      ),
    );
  }

  if (actions.length <= 2) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: divider, width: 1)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < actions.length; i++) ...[
            if (i > 0) Container(width: 1, height: 48, color: divider),
            Expanded(
              child: SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: () => handleTap(actions[i]),
                  style: actionStyle(actions[i]),
                  child: Text(actions[i].text),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (int i = 0; i < actions.length; i++) ...[
        Container(height: 1, color: divider),
        SizedBox(
          height: 48,
          child: TextButton(
            onPressed: () => handleTap(actions[i]),
            style: actionStyle(actions[i]),
            child: Text(actions[i].text),
          ),
        ),
      ],
    ],
  );
}
