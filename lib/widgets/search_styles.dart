import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SearchStyles {
  static const double fieldHeight = 36.0;
  static const BorderRadius fieldBorderRadius = BorderRadius.all(
    Radius.circular(AppTheme.radiusLg),
  );
  static const Color highlightBase = Color(0xFFFFD740);
  static const double highlightStrokeWidth = 1.0;

  static ThemeData inputTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
      ),
    );
  }

  static Color fieldFillColor(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? theme.colorScheme.surface
        : theme.scaffoldBackgroundColor;
  }

  static Color fieldBorderColor(BuildContext context) {
    return Colors.grey.withValues(alpha: 0.5);
  }

  static Color placeholderColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
  }

  static TextStyle hintTextStyle(BuildContext context) {
    return TextStyle(color: placeholderColor(context), fontSize: 14);
  }

  static TextStyle inputTextStyle(BuildContext context) {
    return TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 14,
    );
  }

  static BoxDecoration fieldDecoration(BuildContext context) {
    return BoxDecoration(
      color: fieldFillColor(context),
      borderRadius: fieldBorderRadius,
      border: Border.all(color: fieldBorderColor(context), width: 1.0),
    );
  }

  static InputDecoration inputDecoration({
    required BuildContext context,
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    BoxConstraints? prefixIconConstraints,
    BoxConstraints? suffixIconConstraints,
    EdgeInsetsGeometry? contentPadding = const EdgeInsets.symmetric(
      horizontal: 8,
      vertical: 8,
    ),
    bool isCollapsed = false,
    bool isDense = true,
  }) {
    return InputDecoration(
      isDense: isDense,
      isCollapsed: isCollapsed,
      hintText: hintText,
      hintStyle: hintTextStyle(context),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      filled: false,
      contentPadding: isCollapsed ? null : contentPadding,
      prefixIcon: prefixIcon,
      prefixIconConstraints: prefixIconConstraints,
      suffixIcon: suffixIcon,
      suffixIconConstraints: suffixIconConstraints,
    );
  }

  static Color highlightFillColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return highlightBase.withValues(alpha: isDark ? 0.24 : 0.18);
  }

  static Color highlightStrokeColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return highlightBase.withValues(alpha: isDark ? 0.9 : 0.82);
  }

  static BoxDecoration highlightTextDecoration(BuildContext context) {
    return BoxDecoration(
      color: highlightFillColor(context),
      borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusXs)),
      border: Border.all(
        color: highlightStrokeColor(context),
        width: highlightStrokeWidth,
      ),
    );
  }
}

class SearchTextField extends StatelessWidget {
  const SearchTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.search,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixIconConstraints,
    this.suffixIconConstraints,
    this.contentPadding,
    this.height = SearchStyles.fieldHeight,
  });

  final TextEditingController controller;
  final String hintText;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final BoxConstraints? prefixIconConstraints;
  final BoxConstraints? suffixIconConstraints;
  final EdgeInsetsGeometry? contentPadding;
  final double height;

  @override
  Widget build(BuildContext context) {
    final Widget effectivePrefixIcon =
        prefixIcon ??
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 6),
          child: Icon(
            Icons.search,
            size: 18,
            color: SearchStyles.placeholderColor(context),
          ),
        );
    return Theme(
      data: SearchStyles.inputTheme(context),
      child: Container(
        height: height,
        decoration: SearchStyles.fieldDecoration(context),
        alignment: Alignment.center,
        child: ClipRRect(
          borderRadius: SearchStyles.fieldBorderRadius,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            textInputAction: textInputAction,
            style: SearchStyles.inputTextStyle(context),
            decoration: SearchStyles.inputDecoration(
              context: context,
              hintText: hintText,
              prefixIcon: effectivePrefixIcon,
              prefixIconConstraints:
                  prefixIconConstraints ??
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              suffixIcon: suffixIcon,
              suffixIconConstraints: suffixIconConstraints,
              contentPadding:
                  contentPadding ??
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ),
      ),
    );
  }
}

class SearchMatchBoxesOverlay extends StatelessWidget {
  const SearchMatchBoxesOverlay({super.key, required this.boxesFuture});

  final Future<Map<String, dynamic>?> boxesFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: boxesFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        final int srcW = (data['width'] as int?) ?? 0;
        final int srcH = (data['height'] as int?) ?? 0;
        final List<dynamic> raw = (data['boxes'] as List?) ?? const <dynamic>[];
        if (srcW <= 0 || srcH <= 0 || raw.isEmpty) {
          return const SizedBox.shrink();
        }
        final rects = _parseRects(raw);
        if (rects.isEmpty) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: CustomPaint(
              painter: SearchMatchBoxesPainter(
                originalWidth: srcW.toDouble(),
                originalHeight: srcH.toDouble(),
                boxes: rects,
                strokeColor: SearchStyles.highlightStrokeColor(context),
                fillColor: SearchStyles.highlightFillColor(context),
                strokeWidth: SearchStyles.highlightStrokeWidth,
              ),
            ),
          ),
        );
      },
    );
  }

  static List<Rect> _parseRects(List<dynamic> raw) {
    final List<Rect> rects = <Rect>[];
    for (final item in raw) {
      if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        final l = (m['left'] as num?)?.toDouble() ?? 0;
        final t = (m['top'] as num?)?.toDouble() ?? 0;
        final r = (m['right'] as num?)?.toDouble() ?? 0;
        final b = (m['bottom'] as num?)?.toDouble() ?? 0;
        rects.add(Rect.fromLTRB(l, t, r, b));
      }
    }
    return rects;
  }
}

class SearchMatchBoxesPainter extends CustomPainter {
  final double originalWidth;
  final double originalHeight;
  final List<Rect> boxes;
  final Color strokeColor;
  final Color fillColor;
  final double strokeWidth;

  SearchMatchBoxesPainter({
    required this.originalWidth,
    required this.originalHeight,
    required this.boxes,
    required this.strokeColor,
    required this.fillColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (originalWidth <= 0 || originalHeight <= 0) return;
    final double scale =
        (size.width / originalWidth) > (size.height / originalHeight)
        ? (size.width / originalWidth)
        : (size.height / originalHeight);
    final double drawW = originalWidth * scale;
    final double drawH = originalHeight * scale;
    final double offsetX = (size.width - drawW) / 2.0;
    final double offsetY = (size.height - drawH) / 2.0;

    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = strokeColor
      ..strokeWidth = strokeWidth;
    final Paint fill = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;

    for (final r in boxes) {
      final Rect mapped = Rect.fromLTRB(
        offsetX + r.left * scale,
        offsetY + r.top * scale,
        offsetX + r.right * scale,
        offsetY + r.bottom * scale,
      ).intersect(Offset.zero & size);
      if (mapped.isEmpty) continue;
      canvas.drawRect(mapped, fill);
      canvas.drawRect(mapped, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant SearchMatchBoxesPainter oldDelegate) {
    return oldDelegate.originalWidth != originalWidth ||
        oldDelegate.originalHeight != originalHeight ||
        oldDelegate.boxes != boxes ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
