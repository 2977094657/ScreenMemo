import 'package:flutter/material.dart';
import 'package:screen_memo/core/theme/app_theme.dart';

class SegmentTagChipColors {
  const SegmentTagChipColors({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;
}

int _stableStringHash(String value) {
  int hash = 0x811c9dc5;
  for (final int unit in value.runes) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

SegmentTagChipColors segmentCategoryTagChipColors(
  BuildContext context,
  String text,
) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  final List<Color> palette = AppTheme.dynamicTagPalette;
  final String key = text.trim().toLowerCase();
  final Color foreground =
      palette[_stableStringHash(key.isEmpty ? text : key) % palette.length];
  return SegmentTagChipColors(
    foreground: foreground,
    background: foreground.withValues(alpha: dark ? 0.22 : 0.12),
    border: foreground.withValues(alpha: dark ? 0.54 : 0.34),
  );
}

SegmentTagChipColors segmentMergedTagChipColors(BuildContext context) {
  final bool dark = Theme.of(context).brightness == Brightness.dark;
  final Color foreground = AppTheme.mergedEventAccent;
  return SegmentTagChipColors(
    foreground: foreground,
    background: foreground.withValues(alpha: dark ? 0.24 : 0.18),
    border: foreground.withValues(alpha: dark ? 0.60 : 0.48),
  );
}
