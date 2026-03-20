import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../theme/app_theme.dart';

enum _UINotificationTone { neutral, success, info, warning, error }

Color _overlayBackgroundForTheme(ThemeData theme) =>
    theme.brightness == Brightness.dark
    ? const Color(0xE8141413)
    : const Color(0xE0191816);

Color _overlayTextForTheme(ThemeData theme) =>
    theme.brightness == Brightness.dark
    ? const Color(0xFFF6F1E8)
    : const Color(0xFFF7F2EA);

Color _overlayTrackForTheme(ThemeData theme) =>
    theme.brightness == Brightness.dark
    ? const Color(0x33FAF9F5)
    : const Color(0x40FAF9F5);

Color _overlayAccentForTone(ThemeData theme, _UINotificationTone tone) {
  switch (tone) {
    case _UINotificationTone.success:
      return AppTheme.success;
    case _UINotificationTone.info:
      return theme.colorScheme.secondary;
    case _UINotificationTone.warning:
      return AppTheme.warning;
    case _UINotificationTone.error:
      return theme.colorScheme.error;
    case _UINotificationTone.neutral:
      return theme.colorScheme.primary;
  }
}

Color _overlayBorderForTone(ThemeData theme, _UINotificationTone tone) {
  final double alpha = tone == _UINotificationTone.neutral ? 0.22 : 0.28;
  return _overlayAccentForTone(theme, tone).withValues(alpha: alpha);
}

Color _overlayActionForTone(ThemeData theme, _UINotificationTone tone) {
  return Color.lerp(
        _overlayTextForTheme(theme),
        _overlayAccentForTone(theme, tone),
        0.48,
      ) ??
      _overlayTextForTheme(theme);
}

/// 统一的底部吐司（Overlay）助手
class UINotifier {
  static OverlayEntry? _currentEntry;
  static OverlayEntry? _progressEntry;
  static ValueNotifier<_ProgressState>? _progressNotifier;

  static void _removeCurrent() {
    try {
      _currentEntry?.remove();
    } catch (_) {}
    _currentEntry = null;
  }

  static void _removeProgress() {
    try {
      _progressEntry?.remove();
    } catch (_) {}
    _progressEntry = null;
    _progressNotifier = null;
  }

  static void _showToastWithOverlay(
    OverlayState overlay, {
    required _UINotificationTone tone,
    required String message,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(overlay.context);
    _removeCurrent();

    final entry = OverlayEntry(
      builder: (ctx) => _TopToast(
        message: message,
        textColor: _overlayTextForTheme(theme),
        backgroundColor: _overlayBackgroundForTheme(theme),
        borderColor: _overlayBorderForTone(theme, tone),
        actionColor: _overlayActionForTone(theme, tone),
        displayDuration: duration ?? const Duration(seconds: 3),
        actionLabel: actionLabel,
        onAction: onAction,
        onClosed: _removeCurrent,
      ),
    );

    overlay.insert(entry);
    _currentEntry = entry;
  }

  static void _showToast(
    BuildContext context, {
    required _UINotificationTone tone,
    required String message,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = Overlay.of(context);
    _showToastWithOverlay(
      overlay,
      tone: tone,
      message: message,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void success(
    BuildContext context,
    String message, {
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showToast(
      context,
      tone: _UINotificationTone.success,
      message: message,
      duration: duration ?? const Duration(seconds: 2),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void successOnOverlay(
    OverlayState overlay,
    String message, {
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showToastWithOverlay(
      overlay,
      tone: _UINotificationTone.success,
      message: message,
      duration: duration ?? const Duration(seconds: 2),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void info(
    BuildContext context,
    String message, {
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showToast(
      context,
      tone: _UINotificationTone.info,
      message: message,
      duration: duration ?? const Duration(seconds: 2),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void infoOnOverlay(
    OverlayState overlay,
    String message, {
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showToastWithOverlay(
      overlay,
      tone: _UINotificationTone.info,
      message: message,
      duration: duration ?? const Duration(seconds: 2),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showToast(
      context,
      tone: _UINotificationTone.error,
      message: message,
      duration: duration ?? const Duration(seconds: 3),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void errorOnOverlay(
    OverlayState overlay,
    String message, {
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showToastWithOverlay(
      overlay,
      tone: _UINotificationTone.error,
      message: message,
      duration: duration ?? const Duration(seconds: 3),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void warning(
    BuildContext context,
    String message, {
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showToast(
      context,
      tone: _UINotificationTone.warning,
      message: message,
      duration: duration ?? const Duration(seconds: 3),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void warningOnOverlay(
    OverlayState overlay,
    String message, {
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showToastWithOverlay(
      overlay,
      tone: _UINotificationTone.warning,
      message: message,
      duration: duration ?? const Duration(seconds: 3),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void center(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    _removeCurrent();

    final overlay = Overlay.of(context);
    final theme = Theme.of(context);

    final entry = OverlayEntry(
      builder: (ctx) => _CenterToast(
        message: message,
        textColor: _overlayTextForTheme(theme),
        backgroundColor: _overlayBackgroundForTheme(theme),
        borderColor: _overlayBorderForTone(theme, _UINotificationTone.neutral),
        displayDuration: duration ?? const Duration(milliseconds: 1500),
        onClosed: _removeCurrent,
      ),
    );

    overlay.insert(entry);
    _currentEntry = entry;
  }

  static void showProgress(
    BuildContext context, {
    required String message,
    double? progress,
  }) {
    final overlay = Overlay.of(context);
    showProgressOnOverlay(overlay, message: message, progress: progress);
  }

  static void showProgressOnOverlay(
    OverlayState overlay, {
    required String message,
    double? progress,
  }) {
    final initial = _ProgressState(message: message, progress: progress);
    if (_progressNotifier == null) {
      _progressNotifier = ValueNotifier<_ProgressState>(initial);
      final theme = Theme.of(overlay.context);
      final entry = OverlayEntry(
        builder: (ctx) => _ProgressToast(
          stateListenable: _progressNotifier!,
          backgroundColor: _overlayBackgroundForTheme(theme),
          textColor: _overlayTextForTheme(theme),
          borderColor: _overlayBorderForTone(
            theme,
            _UINotificationTone.neutral,
          ),
          trackColor: _overlayTrackForTheme(theme),
          progressColor: _overlayAccentForTone(
            theme,
            _UINotificationTone.neutral,
          ),
          onClosed: _removeProgress,
        ),
      );
      overlay.insert(entry);
      _progressEntry = entry;
    } else {
      _progressNotifier!.value = initial;
    }
  }

  static void updateProgress({String? message, double? progress}) {
    final notifier = _progressNotifier;
    if (notifier == null) return;
    final current = notifier.value;
    notifier.value = _ProgressState(
      message: message ?? current.message,
      progress: progress ?? current.progress,
    );
  }

  static void hideProgress() {
    _removeProgress();
  }
}

/// 内部组件：带进出场动画与自动消失的顶部吐司
class _TopToast extends StatefulWidget {
  final String message;
  final Color textColor;
  final Color backgroundColor;
  final Color? borderColor;
  final Color? actionColor;
  final Duration displayDuration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClosed;

  const _TopToast({
    required this.message,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.actionColor,
    required this.displayDuration,
    required this.onClosed,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(_fade);
    _controller.forward();
    _timer = Timer(widget.displayDuration, _startDismiss);
  }

  void _startDismiss() async {
    try {
      await _controller.reverse();
    } catch (_) {}
    if (mounted) widget.onClosed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool interactive =
        widget.actionLabel != null && widget.onAction != null;

    return SafeArea(
      top: false,
      bottom: true,
      child: IgnorePointer(
        ignoring: !interactive,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
            child: SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _fade,
                child: Material(
                  type: MaterialType.transparency,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing4,
                        vertical: AppTheme.spacing3,
                      ),
                      decoration: BoxDecoration(
                        color: widget.backgroundColor,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: widget.borderColor == null
                            ? null
                            : Border.all(color: widget.borderColor!, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              widget.message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: widget.textColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (interactive) ...[
                            const SizedBox(width: AppTheme.spacing2),
                            TextButton(
                              onPressed: () {
                                widget.onAction?.call();
                                _startDismiss();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor:
                                    widget.actionColor ?? widget.textColor,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                widget.actionLabel!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: widget.actionColor ?? widget.textColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 内部组件：居中吐司（仅渐隐显示，自动消失）
class _CenterToast extends StatefulWidget {
  final String message;
  final Color textColor;
  final Color backgroundColor;
  final Color? borderColor;
  final Duration displayDuration;
  final VoidCallback onClosed;

  const _CenterToast({
    required this.message,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.displayDuration,
    required this.onClosed,
  });

  @override
  State<_CenterToast> createState() => _CenterToastState();
}

class _CenterToastState extends State<_CenterToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
    _timer = Timer(widget.displayDuration, _startDismiss);
  }

  void _startDismiss() async {
    try {
      await _controller.reverse();
    } catch (_) {}
    if (mounted) widget.onClosed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: IgnorePointer(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing4,
                    vertical: AppTheme.spacing3,
                  ),
                  decoration: BoxDecoration(
                    color: widget.backgroundColor,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: widget.borderColor == null
                        ? null
                        : Border.all(color: widget.borderColor!, width: 1),
                  ),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: widget.textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressState {
  final String message;
  final double? progress;
  const _ProgressState({required this.message, this.progress});
}

class _ProgressToast extends StatelessWidget {
  final ValueListenable<_ProgressState> stateListenable;
  final Color backgroundColor;
  final Color textColor;
  final Color? borderColor;
  final Color trackColor;
  final Color progressColor;
  final VoidCallback onClosed;

  const _ProgressToast({
    required this.stateListenable,
    required this.backgroundColor,
    required this.textColor,
    required this.borderColor,
    required this.trackColor,
    required this.progressColor,
    required this.onClosed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      bottom: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
          child: Material(
            type: MaterialType.transparency,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing4,
                  vertical: AppTheme.spacing3,
                ),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: borderColor == null
                      ? null
                      : Border.all(color: borderColor!, width: 1),
                ),
                child: ValueListenableBuilder<_ProgressState>(
                  valueListenable: stateListenable,
                  builder: (context, state, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacing2),
                        UIProgress(
                          value: state.progress,
                          backgroundColor: trackColor,
                          valueColor: progressColor,
                          height: 6,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSm,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// shadcn/ui风格的按钮组件
class _UIButtonPalette {
  final Color backgroundColor;
  final Color foregroundColor;
  final Color disabledBackgroundColor;
  final Color disabledForegroundColor;
  final Color overlayColor;
  final BorderSide? borderSide;

  const _UIButtonPalette({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.disabledBackgroundColor,
    required this.disabledForegroundColor,
    required this.overlayColor,
    this.borderSide,
  });
}

class UIButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final UIButtonVariant variant;
  final UIButtonSize size;
  final Widget? icon;
  final bool loading;
  final bool fullWidth;

  const UIButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = UIButtonVariant.primary,
    this.size = UIButtonSize.medium,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _resolvePalette(context);
    final style = _buildStyle(palette);
    final child = _buildButtonContent(
      context,
      foregroundColor: palette.foregroundColor,
    );

    Widget button;
    switch (variant) {
      case UIButtonVariant.outline:
        button = OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: style,
          child: child,
        );
        break;
      case UIButtonVariant.ghost:
        button = TextButton(
          onPressed: loading ? null : onPressed,
          style: style,
          child: child,
        );
        break;
      case UIButtonVariant.secondary:
      case UIButtonVariant.primary:
      case UIButtonVariant.destructive:
        button = ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: style,
          child: child,
        );
        break;
    }

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }

    return button;
  }

  _UIButtonPalette _resolvePalette(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    switch (variant) {
      case UIButtonVariant.primary:
        return _UIButtonPalette(
          backgroundColor: isDark ? cs.primary : cs.onSurface,
          foregroundColor: isDark ? cs.onPrimary : cs.surfaceContainerLowest,
          disabledBackgroundColor: cs.surfaceContainerHigh,
          disabledForegroundColor: cs.onSurfaceVariant,
          overlayColor: (isDark ? cs.onPrimary : cs.surfaceContainerLowest)
              .withValues(alpha: 0.08),
        );
      case UIButtonVariant.secondary:
        return _UIButtonPalette(
          backgroundColor: isDark
              ? cs.surfaceContainerHigh
              : cs.surfaceContainer,
          foregroundColor: cs.onSurface,
          disabledBackgroundColor: cs.surfaceContainerLow,
          disabledForegroundColor: cs.onSurfaceVariant,
          overlayColor: cs.onSurface.withValues(alpha: 0.05),
          borderSide: BorderSide(
            color: cs.outline.withValues(alpha: 0.78),
            width: 1,
          ),
        );
      case UIButtonVariant.outline:
        return _UIButtonPalette(
          backgroundColor: Colors.transparent,
          foregroundColor: cs.onSurface,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: cs.onSurfaceVariant,
          overlayColor: cs.onSurface.withValues(alpha: 0.05),
          borderSide: BorderSide(color: cs.outline, width: 1),
        );
      case UIButtonVariant.ghost:
        return _UIButtonPalette(
          backgroundColor: Colors.transparent,
          foregroundColor: cs.onSurface,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: cs.onSurfaceVariant,
          overlayColor: cs.onSurface.withValues(alpha: 0.05),
        );
      case UIButtonVariant.destructive:
        return _UIButtonPalette(
          backgroundColor: cs.error,
          foregroundColor: cs.onError,
          disabledBackgroundColor: cs.surfaceContainerHigh,
          disabledForegroundColor: cs.onSurfaceVariant,
          overlayColor: cs.onError.withValues(alpha: 0.08),
        );
    }
  }

  ButtonStyle _buildStyle(_UIButtonPalette palette) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return palette.disabledBackgroundColor;
        }
        return palette.backgroundColor;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return palette.disabledForegroundColor;
        }
        return palette.foregroundColor;
      }),
      overlayColor: WidgetStatePropertyAll(palette.overlayColor),
      side: palette.borderSide == null
          ? null
          : WidgetStatePropertyAll(palette.borderSide),
      elevation: const WidgetStatePropertyAll(0),
      shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      minimumSize: WidgetStatePropertyAll(Size(0, _getMinHeight())),
      padding: WidgetStatePropertyAll(_getPadding()),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
      ),
      textStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: _getFontSize(), fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildButtonContent(
    BuildContext context, {
    required Color foregroundColor,
  }) {
    if (loading) {
      return SizedBox(
        height: _getIconSize(),
        width: _getIconSize(),
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
        ),
      );
    }

    final textWidget = Text(
      text,
      style: TextStyle(fontSize: _getFontSize(), fontWeight: FontWeight.w600),
    );

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme.merge(
            data: IconThemeData(size: _getIconSize(), color: foregroundColor),
            child: SizedBox(
              height: _getIconSize(),
              width: _getIconSize(),
              child: Center(child: icon),
            ),
          ),
          const SizedBox(width: AppTheme.spacing2),
          textWidget,
        ],
      );
    }

    return textWidget;
  }

  EdgeInsets _getPadding() {
    switch (size) {
      case UIButtonSize.small:
        return const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing3,
          vertical: AppTheme.spacing1,
        );
      case UIButtonSize.medium:
        return const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing4,
          vertical: AppTheme.spacing2,
        );
      case UIButtonSize.large:
        return const EdgeInsets.symmetric(
          horizontal: AppTheme.spacing6,
          vertical: AppTheme.spacing3,
        );
    }
  }

  double _getFontSize() {
    switch (size) {
      case UIButtonSize.small:
        return AppTheme.fontSizeXs;
      case UIButtonSize.medium:
        return AppTheme.fontSizeSm;
      case UIButtonSize.large:
        return AppTheme.fontSizeBase;
    }
  }

  double _getIconSize() {
    switch (size) {
      case UIButtonSize.small:
        return 14.0;
      case UIButtonSize.medium:
        return 16.0;
      case UIButtonSize.large:
        return 18.0;
    }
  }

  double _getMinHeight() {
    switch (size) {
      case UIButtonSize.small:
        return 32.0;
      case UIButtonSize.medium:
        return 40.0;
      case UIButtonSize.large:
        return 48.0;
    }
  }
}

enum UIButtonVariant { primary, secondary, outline, ghost, destructive }

enum UIButtonSize { small, medium, large }

/// shadcn/ui风格的卡片组件
class UICard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final bool showBorder;

  const UICard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final cardColor = theme.cardTheme.color ?? theme.colorScheme.surface;
        final borderColor = theme.colorScheme.outline;
        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: showBorder
                ? Border.all(color: borderColor, width: 1)
                : null,
          ),
          padding: padding ?? const EdgeInsets.all(AppTheme.spacing6),
          child: child,
        );
      },
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: card,
      );
    }

    return card;
  }
}

/// shadcn/ui风格的进度条组件
class UIProgress extends StatelessWidget {
  final double? value;
  final Color? backgroundColor;
  final Color? valueColor;
  final double height;
  final BorderRadiusGeometry? borderRadius;

  const UIProgress({
    super.key,
    required this.value,
    this.backgroundColor,
    this.valueColor,
    this.height = 8.0,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final BorderRadiusGeometry effectiveRadius =
        borderRadius ?? BorderRadius.circular(height / 2);
    return ClipRRect(
      borderRadius: effectiveRadius,
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          value: value?.clamp(0.0, 1.0).toDouble(),
          minHeight: height,
          backgroundColor: backgroundColor ?? cs.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(valueColor ?? cs.primary),
        ),
      ),
    );
  }
}

class UILoadingState extends StatelessWidget {
  final String? label;
  final EdgeInsetsGeometry padding;
  final bool compact;

  const UILoadingState({
    super.key,
    this.label,
    this.padding = const EdgeInsets.all(AppTheme.spacing6),
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final double iconBoxSize = compact ? 44 : 52;
    final double indicatorSize = compact ? 18 : 22;

    return _UIStateLayout(
      padding: padding,
      icon: Container(
        width: iconBoxSize,
        height: iconBoxSize,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: cs.outline.withValues(alpha: 0.75),
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: SizedBox(
          width: indicatorSize,
          height: indicatorSize,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
          ),
        ),
      ),
      title: label,
    );
  }
}

class UIEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const UIEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.all(AppTheme.spacing6),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _UIStateLayout(
      padding: padding,
      icon: _buildStateIcon(
        context,
        icon: icon,
        iconColor: cs.onSurfaceVariant,
        backgroundColor: cs.surfaceContainerHigh,
      ),
      title: title,
      message: message,
      action: actionLabel != null && onAction != null
          ? UIButton(
              text: actionLabel!,
              onPressed: onAction,
              variant: UIButtonVariant.outline,
              size: UIButtonSize.small,
            )
          : null,
    );
  }
}

class UIErrorState extends StatelessWidget {
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;
  final EdgeInsetsGeometry padding;

  const UIErrorState({
    super.key,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.error_outline,
    this.padding = const EdgeInsets.all(AppTheme.spacing6),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _UIStateLayout(
      padding: padding,
      icon: _buildStateIcon(
        context,
        icon: icon,
        iconColor: cs.onErrorContainer,
        backgroundColor: cs.errorContainer,
      ),
      title: title,
      message: message,
      action: actionLabel != null && onAction != null
          ? UIButton(
              text: actionLabel!,
              onPressed: onAction,
              variant: UIButtonVariant.secondary,
              size: UIButtonSize.small,
            )
          : null,
    );
  }
}

class _UIStateLayout extends StatelessWidget {
  final Widget icon;
  final String? title;
  final String? message;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  const _UIStateLayout({
    required this.icon,
    this.title,
    this.message,
    this.action,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: padding,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              if (title != null) ...[
                const SizedBox(height: AppTheme.spacing4),
                Text(
                  title!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (message != null) ...[
                const SizedBox(height: AppTheme.spacing2),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: AppTheme.spacing4),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildStateIcon(
  BuildContext context, {
  required IconData icon,
  required Color iconColor,
  required Color backgroundColor,
}) {
  final cs = Theme.of(context).colorScheme;

  return Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      border: Border.all(color: cs.outline.withValues(alpha: 0.7), width: 1),
    ),
    alignment: Alignment.center,
    child: Icon(icon, size: 24, color: iconColor),
  );
}

/// shadcn/ui风格的徽章组件
class UIBadge extends StatelessWidget {
  final String text;
  final UIBadgeVariant variant;

  const UIBadge({
    super.key,
    required this.text,
    this.variant = UIBadgeVariant.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    late final Color backgroundColor;
    late final Color textColor;
    BorderSide? borderSide;

    switch (variant) {
      case UIBadgeVariant.primary:
        backgroundColor = cs.primaryContainer;
        textColor = cs.onPrimaryContainer;
        break;
      case UIBadgeVariant.secondary:
        backgroundColor = cs.surfaceContainerHigh;
        textColor = cs.onSurfaceVariant;
        borderSide = BorderSide(
          color: cs.outline.withValues(alpha: 0.72),
          width: 1,
        );
        break;
      case UIBadgeVariant.success:
        backgroundColor = cs.tertiaryContainer;
        textColor = cs.onTertiaryContainer;
        break;
      case UIBadgeVariant.destructive:
        backgroundColor = cs.errorContainer;
        textColor = cs.onErrorContainer;
        break;
      case UIBadgeVariant.outline:
        backgroundColor = Colors.transparent;
        textColor = cs.onSurfaceVariant;
        borderSide = BorderSide(color: cs.outline, width: 1);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: borderSide == null
            ? null
            : Border.all(color: borderSide.color, width: borderSide.width),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTheme.fontSizeXs,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

enum UIBadgeVariant { primary, secondary, success, destructive, outline }

/// shadcn/ui风格的分隔符组件
class UISeparator extends StatelessWidget {
  final double? height;
  final double? width;
  final Color? color;

  const UISeparator({super.key, this.height, this.width, this.color});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final outline = Theme.of(context).colorScheme.outline;
        return Container(
          height: height ?? 1,
          width: width,
          color: color ?? outline,
        );
      },
    );
  }
}

/// 语言选择弹窗同款：圆角 + surface 背景 + 顶部拖动指示条
class UISheetSurface extends StatelessWidget {
  const UISheetSurface({
    super.key,
    required this.child,
    this.safeAreaTop = false,
    this.safeAreaBottom = true,
  });

  final Widget child;
  final bool safeAreaTop;
  final bool safeAreaBottom;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(AppTheme.radiusLg),
        topRight: Radius.circular(AppTheme.radiusLg),
      ),
      child: ColoredBox(
        color: cs.surface,
        child: SafeArea(top: safeAreaTop, bottom: safeAreaBottom, child: child),
      ),
    );
  }
}

class UISheetHandle extends StatelessWidget {
  const UISheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// 矩形开关组件：小圆角轨道 + 矩形滑块（用于替代默认圆形拇指）
class UIRectSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;
  final Duration duration;

  const UIRectSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.width = 56,
    this.height = 36,
    this.duration = const Duration(milliseconds: 160),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color trackColor = value ? cs.primary : cs.surface;
    final Color thumbColor = value ? cs.onPrimary : cs.onSurface;
    final Color outline = cs.outline.withValues(alpha: 0.8);

    // 内边距用于给滑块留出边界
    const double padding = 2.0;
    final double innerWidth = width - padding * 2;
    final double innerHeight = height - padding * 2;
    const double thumbMargin = 3.0;
    final double thumbHeight = innerHeight - thumbMargin * 2;
    final double thumbWidth = (thumbHeight * 0.8).clamp(
      thumbHeight * 0.7,
      innerWidth / 2.6,
    );

    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
        padding: const EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: outline, width: 1),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: duration,
              curve: Curves.easeOutCubic,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: thumbWidth,
                height: thumbHeight,
                decoration: BoxDecoration(
                  color: thumbColor,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
