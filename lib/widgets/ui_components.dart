import 'package:flutter/material.dart';
import 'dart:async';
import '../theme/app_theme.dart';

/// 统一的底部吐司（Overlay）助手 - shadcn风格：扁平、细线框/无线框、小圆角、无阴影
class UINotifier {
  static OverlayEntry? _currentEntry;

  static void _removeCurrent() {
    try {
      _currentEntry?.remove();
    } catch (_) {}
    _currentEntry = null;
  }

  static void _showTopToast(
    BuildContext context, {
    required String message,
    required Color textColor,
    required Color backgroundColor,
    Color? borderColor,
    bool outlined = true,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    // 移除已有吐司，避免堆叠
    _removeCurrent();

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (ctx) => _TopToast(
        message: message,
        textColor: textColor,
        backgroundColor: backgroundColor,
        borderColor: borderColor,
        outlined: outlined,
        displayDuration: duration ?? const Duration(seconds: 3),
        actionLabel: actionLabel,
        onAction: onAction,
        onClosed: () {
          _removeCurrent();
        },
      ),
    );

    overlay.insert(entry);
    _currentEntry = entry;
  }

  static void success(BuildContext context, String message, {Duration? duration, String? actionLabel, VoidCallback? onAction}) {
    final theme = Theme.of(context);
    const Color base = Color(0xFF67C23A); // Element success
    const Color bgLight = Color(0xFFF0F9EB);
    const Color brLight = Color(0xFFE1F3D8);
    final bool isDark = theme.brightness == Brightness.dark;
    _showTopToast(
      context,
      message: message,
      textColor: base,
      backgroundColor: isDark ? theme.colorScheme.surface : bgLight,
      borderColor: isDark ? base.withOpacity(0.6) : brLight,
      outlined: true,
      duration: duration ?? const Duration(seconds: 2),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void info(BuildContext context, String message, {Duration? duration, String? actionLabel, VoidCallback? onAction}) {
    final theme = Theme.of(context);
    const Color base = Color(0xFF909399); // Element info
    const Color bgLight = Color(0xFFF4F4F5);
    const Color brLight = Color(0xFFE9E9EB);
    final bool isDark = theme.brightness == Brightness.dark;
    _showTopToast(
      context,
      message: message,
      textColor: base,
      backgroundColor: isDark ? theme.colorScheme.surface : bgLight,
      borderColor: isDark ? base.withOpacity(0.6) : brLight,
      outlined: true,
      duration: duration ?? const Duration(seconds: 2),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void error(BuildContext context, String message, {Duration? duration, String? actionLabel, VoidCallback? onAction}) {
    final theme = Theme.of(context);
    const Color base = Color(0xFFF56C6C); // Element error
    const Color bgLight = Color(0xFFFEF0F0);
    const Color brLight = Color(0xFFFDE2E2);
    final bool isDark = theme.brightness == Brightness.dark;
    _showTopToast(
      context,
      message: message,
      textColor: base,
      backgroundColor: isDark ? theme.colorScheme.surface : bgLight,
      borderColor: isDark ? base.withOpacity(0.6) : brLight,
      outlined: true,
      duration: duration ?? const Duration(seconds: 4),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void warning(BuildContext context, String message, {Duration? duration, String? actionLabel, VoidCallback? onAction}) {
    final theme = Theme.of(context);
    const Color base = Color(0xFFE6A23C); // Element warning
    const Color bgLight = Color(0xFFFDF6EC);
    const Color brLight = Color(0xFFFAECD8);
    final bool isDark = theme.brightness == Brightness.dark;
    _showTopToast(
      context,
      message: message,
      textColor: base,
      backgroundColor: isDark ? theme.colorScheme.surface : bgLight,
      borderColor: isDark ? base.withOpacity(0.6) : brLight,
      outlined: true,
      duration: duration ?? const Duration(seconds: 3),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

/// 内部组件：带进出场动画与自动消失的顶部吐司
class _TopToast extends StatefulWidget {
  final String message;
  final Color textColor;
  final Color backgroundColor;
  final Color? borderColor;
  final bool outlined;
  final Duration displayDuration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClosed;

  const _TopToast({
    required this.message,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.outlined,
    required this.displayDuration,
    required this.onClosed,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(_fade);
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
    final borderSide = widget.outlined && widget.borderColor != null
        ? Border.all(color: widget.borderColor!, width: 1)
        : null;
    final interactive = widget.actionLabel != null && widget.onAction != null;

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
                        vertical: AppTheme.spacing2,
                      ),
                      decoration: BoxDecoration(
                        color: widget.backgroundColor,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: borderSide,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              widget.message,
                              maxLines: 2,
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                widget.actionLabel!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: widget.textColor,
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

/// shadcn/ui风格的按钮组件
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
    Widget button;
    
    switch (variant) {
      case UIButtonVariant.primary:
        button = _buildPrimaryButton();
        break;
      case UIButtonVariant.secondary:
        button = _buildSecondaryButton();
        break;
      case UIButtonVariant.outline:
        button = _buildOutlineButton();
        break;
      case UIButtonVariant.ghost:
        button = _buildGhostButton();
        break;
      case UIButtonVariant.destructive:
        button = _buildDestructiveButton();
        break;
    }
    
    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    
    return button;
  }
  
  Widget _buildPrimaryButton() {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          padding: _getPadding(),
        ),
        child: _buildButtonContent(),
      );
    });
  }
  
  Widget _buildSecondaryButton() {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.surfaceVariant,
          foregroundColor: cs.onSurfaceVariant,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          padding: _getPadding(),
        ),
        child: _buildButtonContent(),
      );
    });
  }
  
  Widget _buildOutlineButton() {
    return Builder(builder: (context) {
      final theme = Theme.of(context);
      return OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurface,
          side: BorderSide(color: theme.colorScheme.outline, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          padding: _getPadding(),
        ),
        child: _buildButtonContent(),
      );
    });
  }
  
  Widget _buildGhostButton() {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return TextButton(
        onPressed: loading ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: cs.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          padding: _getPadding(),
        ),
        child: _buildButtonContent(),
      );
    });
  }
  
  Widget _buildDestructiveButton() {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.error,
          foregroundColor: cs.onError,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          ),
          padding: _getPadding(),
        ),
        child: _buildButtonContent(),
      );
    });
  }
  
  Widget _buildButtonContent() {
    if (loading) {
      return SizedBox(
        height: _getIconSize(),
        width: _getIconSize(),
        child: const CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryForeground),
        ),
      );
    }
    
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _getIconSize(),
            width: _getIconSize(),
            child: icon,
          ),
          const SizedBox(width: AppTheme.spacing2),
          Text(text, style: TextStyle(fontSize: _getFontSize())),
        ],
      );
    }
    
    return Text(text, style: TextStyle(fontSize: _getFontSize()));
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
}

enum UIButtonVariant {
  primary,
  secondary,
  outline,
  ghost,
  destructive,
}

enum UIButtonSize {
  small,
  medium,
  large,
}

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
    Widget card = Builder(builder: (context) {
      final theme = Theme.of(context);
      final cardColor = theme.cardTheme.color ?? theme.colorScheme.surface;
      final borderColor = theme.colorScheme.outline;
      return Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: showBorder ? Border.all(color: borderColor, width: 1) : null,
        ),
        padding: padding ?? const EdgeInsets.all(AppTheme.spacing6),
        child: child,
      );
    });
    
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
  final double value;
  final Color? backgroundColor;
  final Color? valueColor;
  final double height;

  const UIProgress({
    super.key,
    required this.value,
    this.backgroundColor,
    this.valueColor,
    this.height = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: backgroundColor ?? cs.surfaceVariant,
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: valueColor ?? cs.primary,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        ),
      );
    });
  }
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
    Color backgroundColor;
    Color textColor;
    
    switch (variant) {
      case UIBadgeVariant.primary:
        backgroundColor = cs.primary;
        textColor = cs.onPrimary;
        break;
      case UIBadgeVariant.secondary:
        backgroundColor = cs.secondaryContainer;
        textColor = cs.onSecondaryContainer;
        break;
      case UIBadgeVariant.success:
        backgroundColor = AppTheme.success;
        textColor = AppTheme.successForeground;
        break;
      case UIBadgeVariant.destructive:
        backgroundColor = cs.error;
        textColor = cs.onError;
        break;
      case UIBadgeVariant.outline:
        backgroundColor = Colors.transparent;
        textColor = cs.onSurface;
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing2,
        vertical: AppTheme.spacing1,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: variant == UIBadgeVariant.outline
            ? Border.all(color: AppTheme.border, width: 1)
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTheme.fontSizeXs,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}

enum UIBadgeVariant {
  primary,
  secondary,
  success,
  destructive,
  outline,
}

/// shadcn/ui风格的分隔符组件
class UISeparator extends StatelessWidget {
  final double? height;
  final double? width;
  final Color? color;

  const UISeparator({
    super.key,
    this.height,
    this.width,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (context) {
      final outline = Theme.of(context).colorScheme.outline;
      return Container(
        height: height ?? 1,
        width: width,
        color: color ?? outline,
      );
    });
  }
}
