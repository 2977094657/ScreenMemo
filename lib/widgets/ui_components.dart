import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../theme/app_theme.dart';

/// 统一的底部吐司（Overlay）助手 - Android Toast 风格：底部、深色背景、白字、轻圆角、无阴影
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
    // 统一 Toast 样式（更透明的半透明背景）
    const Color bg = Color(0xCC323232);
    _showTopToast(
      context,
      message: message,
      textColor: Colors.white,
      backgroundColor: bg,
      borderColor: null,
      outlined: false,
      duration: duration ?? const Duration(seconds: 2),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void info(BuildContext context, String message, {Duration? duration, String? actionLabel, VoidCallback? onAction}) {
    const Color bg = Color(0xCC323232);
    _showTopToast(
      context,
      message: message,
      textColor: Colors.white,
      backgroundColor: bg,
      borderColor: null,
      outlined: false,
      duration: duration ?? const Duration(seconds: 2),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void error(BuildContext context, String message, {Duration? duration, String? actionLabel, VoidCallback? onAction}) {
    const Color bg = Color(0xCC323232);
    _showTopToast(
      context,
      message: message,
      textColor: Colors.white,
      backgroundColor: bg,
      borderColor: null,
      outlined: false,
      duration: duration ?? const Duration(seconds: 3),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void warning(BuildContext context, String message, {Duration? duration, String? actionLabel, VoidCallback? onAction}) {
    const Color bg = Color(0xCC323232);
    _showTopToast(
      context,
      message: message,
      textColor: Colors.white,
      backgroundColor: bg,
      borderColor: null,
      outlined: false,
      duration: duration ?? const Duration(seconds: 3),
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// 居中吐司：用于误触提示等场景，扁平无阴影，轻圆角
  static void center(BuildContext context, String message, {Duration? duration}) {
    // 移除已有吐司，避免堆叠
    _removeCurrent();

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (ctx) => _CenterToast(
        message: message,
        displayDuration: duration ?? const Duration(milliseconds: 1500),
        onClosed: _removeCurrent,
      ),
    );

    overlay.insert(entry);
    _currentEntry = entry;
  }

  // ===== 持续进度吐司（手动更新与关闭） =====
  static void showProgress(BuildContext context, {required String message, double? progress}) {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final initial = _ProgressState(message: message, progress: progress);
    if (_progressNotifier == null) {
      _progressNotifier = ValueNotifier<_ProgressState>(initial);
      final entry = OverlayEntry(
        builder: (ctx) => _ProgressToast(
          stateListenable: _progressNotifier!,
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

/// 内部组件：居中吐司（仅渐隐显示，自动消失）
class _CenterToast extends StatefulWidget {
  final String message;
  final Duration displayDuration;
  final VoidCallback onClosed;

  const _CenterToast({
    required this.message,
    required this.displayDuration,
    required this.onClosed,
  });

  @override
  State<_CenterToast> createState() => _CenterToastState();
}

class _CenterToastState extends State<_CenterToast> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
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
                    vertical: AppTheme.spacing2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xCC323232),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
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
  final double? progress; // 0.0 - 1.0，null 表示不确定
  const _ProgressState({required this.message, this.progress});
}

class _ProgressToast extends StatefulWidget {
  final ValueListenable<_ProgressState> stateListenable;
  final VoidCallback onClosed;

  const _ProgressToast({required this.stateListenable, required this.onClosed});

  @override
  State<_ProgressToast> createState() => _ProgressToastState();
}

class _ProgressToastState extends State<_ProgressToast> {
  @override
  Widget build(BuildContext context) {
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
                  color: const Color(0xCC323232),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: ValueListenableBuilder<_ProgressState>(
                  valueListenable: widget.stateListenable,
                  builder: (context, state, _) {
                    final message = state.message;
                    final prog = state.progress;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: AppTheme.spacing2),
                        if (prog != null)
                          UIProgress(value: prog, backgroundColor: Colors.white24, valueColor: Colors.white, height: 6)
                        else
                          const SizedBox(
                            height: 6,
                            child: LinearProgressIndicator(
                              value: null,
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                              minHeight: 6,
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
        child: SafeArea(
          top: safeAreaTop,
          bottom: safeAreaBottom,
          child: child,
        ),
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
        color: cs.onSurfaceVariant.withOpacity(0.4),
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
    final Color outline = cs.outline.withOpacity(0.8);

    // 内边距用于给滑块留出边界
    const double padding = 2.0;
    final double innerWidth = width - padding * 2;
    final double innerHeight = height - padding * 2;
    const double thumbMargin = 3.0;
    final double thumbHeight = innerHeight - thumbMargin * 2;
    final double thumbWidth = (thumbHeight * 0.8).clamp(thumbHeight * 0.7, innerWidth / 2.6);

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
