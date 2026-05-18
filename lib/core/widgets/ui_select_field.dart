import 'package:flutter/material.dart';
import 'package:screen_memo/core/theme/app_theme.dart';

/// 项目统一的下拉选择项。
class UISelectItem<T> {
  const UISelectItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.enabled = true,
  });

  final T value;
  final String label;
  final String? subtitle;
  final bool enabled;
}

/// 项目统一的下拉选择控件。
///
/// 用于替代页面内直接定制的原生下拉控件。
class UISelectField<T> extends StatelessWidget {
  const UISelectField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hintText,
    this.enabled = true,
    this.isExpanded = true,
    this.dense = true,
    this.width,
    this.fillColor,
    this.contentPadding,
    this.menuMaxHeight,
  });

  final T? value;
  final List<UISelectItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hintText;
  final bool enabled;
  final bool isExpanded;
  final bool dense;
  final double? width;
  final Color? fillColor;
  final EdgeInsetsGeometry? contentPadding;
  final double? menuMaxHeight;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final Color resolvedFill =
        fillColor ??
        (isDark ? cs.surfaceContainerLow : theme.scaffoldBackgroundColor);
    final EdgeInsetsGeometry resolvedPadding =
        contentPadding ??
        const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing3,
          vertical: AppTheme.spacing2,
        );

    final Widget field = DropdownButtonFormField<T>(
      initialValue: value,
      isDense: dense,
      isExpanded: isExpanded,
      menuMaxHeight: menuMaxHeight,
      dropdownColor: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 20,
        color: cs.onSurfaceVariant,
      ),
      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
      hint: hintText == null
          ? null
          : Text(
              hintText!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
      items: [
        for (final UISelectItem<T> item in items)
          DropdownMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            child: _UISelectItemContent(
              label: item.label,
              subtitle: item.subtitle,
              enabled: item.enabled,
            ),
          ),
      ],
      selectedItemBuilder: (context) => [
        for (final UISelectItem<T> item in items)
          _UISelectSelectedContent(label: item.label, enabled: item.enabled),
      ],
      onChanged: enabled ? onChanged : null,
      decoration: InputDecoration(
        isDense: dense,
        filled: true,
        fillColor: enabled
            ? resolvedFill
            : cs.surfaceContainerHighest.withValues(alpha: 0.48),
        contentPadding: resolvedPadding,
      ),
    );

    if (width == null) return field;
    return SizedBox(width: width, child: field);
  }
}

class _UISelectItemContent extends StatelessWidget {
  const _UISelectItemContent({
    required this.label,
    required this.enabled,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Color textColor = enabled
        ? cs.onSurface
        : cs.onSurfaceVariant.withValues(alpha: 0.48);
    final String? subtitleText = subtitle?.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
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
    );
  }
}

class _UISelectSelectedContent extends StatelessWidget {
  const _UISelectSelectedContent({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Color color = enabled
        ? cs.onSurface
        : cs.onSurfaceVariant.withValues(alpha: 0.48);

    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(color: color),
    );
  }
}
