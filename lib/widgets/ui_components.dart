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
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.primaryForeground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        padding: _getPadding(),
      ),
      child: _buildButtonContent(),
    );
  }
  
  Widget _buildSecondaryButton() {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.secondary,
        foregroundColor: AppTheme.secondaryForeground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        padding: _getPadding(),
      ),
      child: _buildButtonContent(),
    );
  }
  
  Widget _buildOutlineButton() {
    return OutlinedButton(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.foreground,
        side: const BorderSide(color: AppTheme.border, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        padding: _getPadding(),
      ),
      child: _buildButtonContent(),
    );
  }
  
  Widget _buildGhostButton() {
    return TextButton(
      onPressed: loading ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.foreground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        padding: _getPadding(),
      ),
      child: _buildButtonContent(),
    );
  }
  
  Widget _buildDestructiveButton() {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.destructive,
        foregroundColor: AppTheme.destructiveForeground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        padding: _getPadding(),
      ),
      child: _buildButtonContent(),
    );
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

  const UICard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      padding: padding ?? const EdgeInsets.all(AppTheme.spacing6),
      child: child,
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
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.secondary,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: valueColor ?? AppTheme.primary,
            borderRadius: BorderRadius.circular(height / 2),
          ),
        ),
      ),
    );
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
    Color backgroundColor;
    Color textColor;
    
    switch (variant) {
      case UIBadgeVariant.primary:
        backgroundColor = AppTheme.primary;
        textColor = AppTheme.primaryForeground;
        break;
      case UIBadgeVariant.secondary:
        backgroundColor = AppTheme.secondary;
        textColor = AppTheme.secondaryForeground;
        break;
      case UIBadgeVariant.success:
        backgroundColor = AppTheme.success;
        textColor = AppTheme.successForeground;
        break;
      case UIBadgeVariant.destructive:
        backgroundColor = AppTheme.destructive;
        textColor = AppTheme.destructiveForeground;
        break;
      case UIBadgeVariant.outline:
        backgroundColor = Colors.transparent;
        textColor = AppTheme.foreground;
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
    return Container(
      height: height ?? 1,
      width: width,
      color: color ?? AppTheme.border,
    );
  }
}
