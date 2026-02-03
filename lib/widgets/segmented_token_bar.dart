import 'package:flutter/material.dart';

class SegmentedTokenBarSegment {
  const SegmentedTokenBarSegment({
    required this.tokens,
    required this.color,
  });

  final int tokens;
  final Color color;
}

/// A "storage usage" style horizontal segmented bar.
///
/// - `totalTokens` is the full capacity (e.g., model context window).
/// - Segments are sized by `tokens / totalTokens`.
class SegmentedTokenBar extends StatelessWidget {
  const SegmentedTokenBar({
    super.key,
    required this.totalTokens,
    required this.segments,
    this.height = 10,
    this.radius = 999,
    this.backgroundColor,
    this.borderColor,
  });

  final int totalTokens;
  final List<SegmentedTokenBarSegment> segments;
  final double height;
  final double radius;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color bg = backgroundColor ?? theme.colorScheme.surfaceContainerHighest;
    final Color bd =
        borderColor ?? theme.colorScheme.outline.withOpacity(0.35);

    final int denom = totalTokens <= 0 ? 1 : totalTokens;
    final List<SegmentedTokenBarSegment> visible = segments
        .where((s) => s.tokens > 0)
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;
        double x = 0;
        final List<Widget> positioned = <Widget>[];
        for (int i = 0; i < visible.length; i++) {
          final SegmentedTokenBarSegment seg = visible[i];
          final double segW = (w * (seg.tokens / denom)).clamp(0.0, w);
          if (segW <= 0) continue;
          positioned.add(
            Positioned(
              left: x,
              top: 0,
              bottom: 0,
              width: segW,
              child: Container(color: seg.color),
            ),
          );
          x += segW;
          if (x >= w) break;
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: bd),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: positioned,
            ),
          ),
        );
      },
    );
  }
}

