import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SelectionCheckbox extends StatelessWidget {
  const SelectionCheckbox({
    super.key,
    required this.selected,
    this.size = 22,
    this.iconSize = 14,
  });

  final bool selected;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      alignment: Alignment.center,
      child: selected
          ? Icon(Icons.check, size: iconSize, color: Colors.white)
          : null,
    );
  }
}
