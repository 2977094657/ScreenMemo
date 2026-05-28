import 'package:flutter/material.dart';
import 'package:screen_memo/core/theme/app_theme.dart';

/// 项目统一的弹出操作菜单项。
///
/// 文案保持由调用方传入，便于继续使用现有国际化字符串。
class UIActionMenuItem<T> {
  const UIActionMenuItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.enabled = true,
    this.destructive = false,
  });

  final T value;
  final String label;
  final String? subtitle;
  final bool enabled;
  final bool destructive;
}

/// 项目统一的弹出操作菜单。
///
/// 统一处理菜单圆角、颜色、选中态和弹层阴影，避免各页面重复定制。
class UIActionMenuButton<T> extends StatelessWidget {
  const UIActionMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.selectedValue,
    this.tooltip,
    this.buttonIcon,
    this.child,
    this.enabled = true,
    this.padding = const EdgeInsets.all(8),
    this.offset = const Offset(0, 8),
    this.minWidth = 168,
    this.maxWidth = 280,
    this.iconSize,
    this.showSelectedState = true,
  }) : assert(
         buttonIcon == null || child == null,
         'Pass either buttonIcon or child, not both.',
       );

  final List<UIActionMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final T? selectedValue;
  final String? tooltip;
  final Widget? buttonIcon;
  final Widget? child;
  final bool enabled;
  final EdgeInsetsGeometry padding;
  final Offset offset;
  final double minWidth;
  final double maxWidth;
  final double? iconSize;
  final bool showSelectedState;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return PopupMenuButton<T>(
      tooltip: tooltip,
      enabled: enabled && items.any((item) => item.enabled),
      // PopupMenuButton 会用 ThemeData.highlightColor 给 initialValue 匹配项
      // 额外包一层背景；选中态由 _UIActionMenuTile 自己绘制即可。
      onSelected: onSelected,
      padding: padding,
      menuPadding: const EdgeInsets.symmetric(vertical: AppTheme.spacing1),
      offset: offset,
      position: PopupMenuPosition.under,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.34 : 0.14),
      surfaceTintColor: Colors.transparent,
      color: cs.surfaceContainerLow,
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        side: BorderSide(
          color: cs.outline.withValues(alpha: isDark ? 0.55 : 0.42),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      icon: buttonIcon,
      iconSize: iconSize,
      child: child,
      itemBuilder: (context) => [
        for (final UIActionMenuItem<T> item in items)
          PopupMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            height: 44,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacing1,
              vertical: 2,
            ),
            child: _UIActionMenuTile(
              label: item.label,
              subtitle: item.subtitle,
              selected: showSelectedState && selectedValue == item.value,
              enabled: item.enabled,
              destructive: item.destructive,
            ),
          ),
      ],
    );
  }
}

class _UIActionMenuTile extends StatelessWidget {
  const _UIActionMenuTile({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.destructive,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Color baseColor = destructive ? cs.error : cs.onSurface;
    final Color contentColor = enabled
        ? (selected && !destructive ? cs.primary : baseColor)
        : cs.onSurfaceVariant.withValues(alpha: 0.44);
    final Color selectedBackground = destructive
        ? cs.errorContainer.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.34 : 0.50,
          )
        : cs.surfaceContainerHigh.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.72 : 0.82,
          );
    final String? subtitleText = subtitle?.trim();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? selectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: 8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: contentColor,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                if (subtitleText != null && subtitleText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
