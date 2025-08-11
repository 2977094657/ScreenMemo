import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
