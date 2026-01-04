import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ScreenshotStyleTabBar extends StatelessWidget implements PreferredSizeWidget {
  const ScreenshotStyleTabBar({
    super.key,
    required this.tabs,
    this.controller,
    this.height = 32,
    this.isScrollable = true,
    this.padding,
    this.labelPadding,
    this.indicatorInsets,
    this.tabAlignment,
    this.indicatorSize,
    this.indicatorPadding,
  });

  final List<Widget> tabs;
  final TabController? controller;
  final double height;
  final bool isScrollable;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? labelPadding;
  final EdgeInsetsGeometry? indicatorInsets;
  final TabAlignment? tabAlignment;
  final TabBarIndicatorSize? indicatorSize;
  final EdgeInsetsGeometry? indicatorPadding;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color selectedColor = theme.brightness == Brightness.dark
        ? AppTheme.darkForeground
        : AppTheme.foreground;
    final Color unselectedColor =
        theme.textTheme.bodySmall?.color ?? AppTheme.mutedForeground;

    final TabAlignment effectiveTabAlignment =
        tabAlignment ?? (isScrollable ? TabAlignment.start : TabAlignment.fill);
    final EdgeInsetsGeometry effectivePadding =
        padding ??
        (isScrollable
            ? const EdgeInsets.only(left: AppTheme.spacing4)
            : const EdgeInsets.symmetric(horizontal: AppTheme.spacing4));
    final EdgeInsetsGeometry effectiveLabelPadding =
        labelPadding ??
        (isScrollable
            ? const EdgeInsets.only(right: AppTheme.spacing6)
            : EdgeInsets.zero);
    final EdgeInsetsGeometry effectiveIndicatorInsets =
        indicatorInsets ??
        const EdgeInsets.symmetric(horizontal: AppTheme.spacing2);
    final TabBarIndicatorSize effectiveIndicatorSize =
        indicatorSize ??
        (isScrollable ? TabBarIndicatorSize.label : TabBarIndicatorSize.tab);
    final EdgeInsetsGeometry effectiveIndicatorPadding =
        indicatorPadding ?? EdgeInsets.zero;

    return SizedBox(
      height: height,
      child: TabBar(
        controller: controller,
        tabs: tabs,
        isScrollable: isScrollable,
        tabAlignment: effectiveTabAlignment,
        padding: effectivePadding,
        labelPadding: effectiveLabelPadding,
        labelColor: selectedColor,
        unselectedLabelColor: unselectedColor,
        labelStyle:
            theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
        dividerColor: Colors.transparent,
        indicatorSize: effectiveIndicatorSize,
        indicatorPadding: effectiveIndicatorPadding,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(width: 2.0, color: selectedColor),
          insets: effectiveIndicatorInsets,
        ),
      ),
    );
  }
}
