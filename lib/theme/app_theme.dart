import 'package:flutter/material.dart';

/// 应用主题配置，参考shadcn/ui设计风格
class AppTheme {
  // 颜色配置
  static const Color primary = Color(0xFF3B82F6);
  static const Color primaryForeground = Color(0xFFFAFAFA);
  static const Color secondary = Color(0xFFF4F4F5);
  static const Color secondaryForeground = Color(0xFF09090B);
  static const Color muted = Color(0xFFF4F4F5);
  static const Color mutedForeground = Color(0xFF71717A);
  static const Color accent = Color(0xFFF4F4F5);
  static const Color accentForeground = Color(0xFF09090B);
  static const Color destructive = Color(0xFFEF4444);
  static const Color destructiveForeground = Color(0xFFFAFAFA);
  static const Color border = Color(0xFFE4E4E7);
  static const Color input = Color(0xFFE4E4E7);
  static const Color ring = Color(0xFF3B82F6);
  static const Color background = Color(0xFFFFFFFF);
  static const Color foreground = Color(0xFF09090B);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardForeground = Color(0xFF09090B);
  static const Color popover = Color(0xFFFFFFFF);
  static const Color popoverForeground = Color(0xFF09090B);

  // 成功色
  static const Color success = Color(0xFF22C55E);
  static const Color successForeground = Color(0xFFFFFFFF);

  // 警告色
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningForeground = Color(0xFFFFFFFF);

  // 信息色
  static const Color info = Color(0xFF3B82F6);
  static const Color infoForeground = Color(0xFFFFFFFF);

  // 边框半径
  static const double radiusXs = 2.0;
  static const double radiusSm = 4.0;
  static const double radiusMd = 6.0;
  static const double radiusLg = 8.0;
  static const double radiusXl = 12.0;

  // 间距
  static const double spacing1 = 4.0;
  static const double spacing2 = 8.0;
  static const double spacing3 = 12.0;
  static const double spacing4 = 16.0;
  static const double spacing5 = 20.0;
  static const double spacing6 = 24.0;
  static const double spacing8 = 32.0;
  static const double spacing10 = 40.0;

  // ===== 工具函数：在深色模式下为过暗或低饱和度的种子色选择更可见的强调色 =====
  static Color _effectiveSeedForDark(Color seed) {
    try {
      final double lum = seed.computeLuminance();
      final hsl = HSLColor.fromColor(seed);
      final bool tooDark = lum < 0.08; // 近黑
      final bool lowSaturation = hsl.saturation < 0.10; // 近灰
      if (tooDark || lowSaturation) {
        // 使用在深色背景上可读性良好的强调色
        return darkSelectedAccent; // #60A5FA
      }
      return seed;
    } catch (_) {
      return darkSelectedAccent;
    }
  }

  static const double spacing12 = 48.0;
  static const double spacing16 = 64.0;
  static const double spacing20 = 80.0;

  // 字体大小
  static const double fontSizeXs = 12.0;
  static const double fontSizeSm = 14.0;
  static const double fontSizeBase = 16.0;
  static const double fontSizeLg = 18.0;
  static const double fontSizeXl = 20.0;
  static const double fontSize2xl = 24.0;
  static const double fontSize3xl = 30.0;
  static const double fontSize4xl = 36.0;

  // 阴影（shadcn/ui风格不使用阴影，但保留定义以备需要）
  static const List<BoxShadow> shadowNone = [];

  // 黑夜模式颜色配置（自定义要求）
  // 背景: #232427（稍深但非纯黑），文本/图标: #A9B7C6
  static const Color darkPrimary = Color(0xFFA9B7C6);
  static const Color darkPrimaryForeground = Color(0xFF3C3F41);
  static const Color darkSecondary = Color(0xFF4A4D4F);
  static const Color darkSecondaryForeground = Color(0xFFA9B7C6);
  static const Color darkMuted = Color(0xFF4A4D4F);
  static const Color darkMutedForeground = Color(0xFFA9B7C6);
  static const Color darkAccent = Color(0xFF4A4D4F);
  static const Color darkAccentForeground = Color(0xFFA9B7C6);
  static const Color darkDestructive = Color(0xFFB55454);
  static const Color darkDestructiveForeground = Color(0xFFA9B7C6);
  static const Color darkBorder = Color(0xFF56595B);
  static const Color darkInput = Color(0xFF4A4D4F);
  static const Color darkRing = Color(0xFFA9B7C6);
  static const Color darkBackground = Color(0xFF232427);
  static const Color darkForeground = Color(0xFFA9B7C6);
  static const Color darkCard = Color(0xFF2A2D30);
  static const Color darkCardForeground = Color(0xFFA9B7C6);
  static const Color darkPopover = Color(0xFF2A2D30);
  static const Color darkPopoverForeground = Color(0xFFA9B7C6);

  // 暗色模式下用于“选中高亮”的强调色（与灰系区分更明显）
  // 选用 Blue 400：#60A5FA，在深背景上具有良好可读性与克制的纯度
  static const Color darkSelectedAccent = Color(0xFF60A5FA);

  /// 获取主题数据
  static ThemeData get lightTheme {
    const ColorScheme cs = ColorScheme.light(
      primary: primary,
      onPrimary: primaryForeground,
      secondary: secondary,
      onSecondary: secondaryForeground,
      surface: background,
      onSurface: foreground,
      error: destructive,
      onError: destructiveForeground,
      outline: border,
      surfaceVariant: muted, // 使用 muted 作为 surfaceVariant
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        iconTheme: IconThemeData(color: foreground),
        elevation: 0,
      ),
      dividerColor: cs.outline,
      progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.primary),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cs.surfaceVariant,
        selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        selectedIconTheme: IconThemeData(color: cs.primary, size: 20),
        unselectedIconTheme: IconThemeData(
          color: cs.onSurfaceVariant,
          size: 18,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        // 统一底部菜单拖动条颜色，与首页语言底部菜单一致
        dragHandleColor: cs.onSurfaceVariant.withOpacity(0.4),
        elevation: 0,
        modalElevation: 0,
        backgroundColor: cs.surface,
        modalBackgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
        clipBehavior: Clip.hardEdge,
      ),
      scaffoldBackgroundColor: background,
      cardTheme: const CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: primaryForeground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          elevation: 0,
          side: const BorderSide(color: border, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: ring, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: destructive, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: destructive, width: 2),
        ),
        filled: true,
        fillColor: background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacing3,
          vertical: spacing2,
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: fontSize4xl,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
        displayMedium: TextStyle(
          fontSize: fontSize3xl,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
        displaySmall: TextStyle(
          fontSize: fontSize2xl,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
        headlineLarge: TextStyle(
          fontSize: fontSize2xl,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        headlineMedium: TextStyle(
          fontSize: fontSizeXl,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        headlineSmall: TextStyle(
          fontSize: fontSizeLg,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        titleLarge: TextStyle(
          fontSize: fontSizeBase,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        titleMedium: TextStyle(
          fontSize: fontSizeSm,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        titleSmall: TextStyle(
          fontSize: fontSizeXs,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        bodyLarge: TextStyle(fontSize: fontSizeBase, color: foreground),
        bodyMedium: TextStyle(fontSize: fontSizeSm, color: foreground),
        bodySmall: TextStyle(fontSize: fontSizeXs, color: mutedForeground),
        labelLarge: TextStyle(
          fontSize: fontSizeSm,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        labelMedium: TextStyle(
          fontSize: fontSizeXs,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        labelSmall: TextStyle(
          fontSize: 10.0,
          fontWeight: FontWeight.w500,
          color: mutedForeground,
        ),
      ),
    );
  }

  /// 获取黑夜模式主题数据
  static ThemeData get darkTheme {
    const ColorScheme cs = ColorScheme.dark(
      primary: darkPrimary,
      onPrimary: darkPrimaryForeground,
      secondary: darkSecondary,
      onSecondary: darkSecondaryForeground,
      surface: darkCard,
      onSurface: darkForeground,
      error: darkDestructive,
      onError: darkDestructiveForeground,
      outline: darkBorder,
      surfaceVariant: darkInput,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: darkForeground,
        iconTheme: IconThemeData(color: darkForeground),
        elevation: 0,
      ),
      dividerColor: cs.outline,
      progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.primary),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cs.surfaceVariant,
        selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        selectedIconTheme: IconThemeData(color: cs.primary, size: 20),
        unselectedIconTheme: IconThemeData(
          color: cs.onSurfaceVariant,
          size: 18,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        // 统一底部菜单拖动条颜色，与首页语言底部菜单一致
        dragHandleColor: cs.onSurfaceVariant.withOpacity(0.4),
        elevation: 0,
        modalElevation: 0,
        backgroundColor: cs.surface,
        modalBackgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
        clipBehavior: Clip.hardEdge,
      ),
      scaffoldBackgroundColor: darkBackground,
      iconTheme: const IconThemeData(color: darkForeground),
      cardTheme: const CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
          side: BorderSide(color: darkBorder, width: 1),
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: fontSize4xl,
          fontWeight: FontWeight.bold,
          color: darkForeground,
        ),
        displayMedium: TextStyle(
          fontSize: fontSize3xl,
          fontWeight: FontWeight.bold,
          color: darkForeground,
        ),
        displaySmall: TextStyle(
          fontSize: fontSize2xl,
          fontWeight: FontWeight.bold,
          color: darkForeground,
        ),
        headlineLarge: TextStyle(
          fontSize: fontSize2xl,
          fontWeight: FontWeight.w600,
          color: darkForeground,
        ),
        headlineMedium: TextStyle(
          fontSize: fontSizeXl,
          fontWeight: FontWeight.w600,
          color: darkForeground,
        ),
        headlineSmall: TextStyle(
          fontSize: fontSizeLg,
          fontWeight: FontWeight.w600,
          color: darkForeground,
        ),
        titleLarge: TextStyle(
          fontSize: fontSizeBase,
          fontWeight: FontWeight.w600,
          color: darkForeground,
        ),
        titleMedium: TextStyle(
          fontSize: fontSizeSm,
          fontWeight: FontWeight.w500,
          color: darkForeground,
        ),
        titleSmall: TextStyle(
          fontSize: fontSizeXs,
          fontWeight: FontWeight.w500,
          color: darkForeground,
        ),
        bodyLarge: TextStyle(fontSize: fontSizeBase, color: darkForeground),
        bodyMedium: TextStyle(fontSize: fontSizeSm, color: darkForeground),
        bodySmall: TextStyle(fontSize: fontSizeXs, color: darkMutedForeground),
        labelLarge: TextStyle(
          fontSize: fontSizeSm,
          fontWeight: FontWeight.w500,
          color: darkForeground,
        ),
        labelMedium: TextStyle(
          fontSize: fontSizeXs,
          fontWeight: FontWeight.w500,
          color: darkForeground,
        ),
        labelSmall: TextStyle(
          fontSize: 10.0,
          fontWeight: FontWeight.w500,
          color: darkMutedForeground,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: darkPrimaryForeground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkForeground,
          elevation: 0,
          side: const BorderSide(color: darkBorder, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkForeground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkBorder, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkRing, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkDestructive, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkDestructive, width: 2),
        ),
        filled: true,
        fillColor: darkCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacing3,
          vertical: spacing2,
        ),
      ),
    );
  }

  /// 基于 seed color 构建浅色主题（仅影响 ColorScheme 与关键控件的强调色）
  static ThemeData lightThemeFor(Color seed) {
    final ColorScheme cs =
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ).copyWith(
          primary: seed,
          // 与现有设计保持一致的表面与分隔语义
          surface: background,
          onSurface: foreground,
          outline: border,
          surfaceVariant: muted,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return cs.onPrimary;
          return cs.surfaceVariant; // 关闭态使用浅灰拇指，避免出现黑色视觉
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected))
            return cs.primary.withOpacity(0.85);
          return cs.surface;
        }),
        trackOutlineColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected))
            return cs.primary.withOpacity(0.6);
          return cs.outline; // 关闭态显示外边界以增强可见性
        }),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        iconTheme: IconThemeData(color: foreground),
        elevation: 0,
      ),
      dividerColor: cs.outline,
      progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.primary),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cs.surfaceVariant,
        selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        selectedIconTheme: IconThemeData(color: cs.primary, size: 20),
        unselectedIconTheme: IconThemeData(
          color: cs.onSurfaceVariant,
          size: 18,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        dragHandleColor: cs.onSurfaceVariant.withOpacity(0.4),
        elevation: 0,
        modalElevation: 0,
        backgroundColor: cs.surface,
        modalBackgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
        clipBehavior: Clip.hardEdge,
      ),
      scaffoldBackgroundColor: background,
      cardTheme: const CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          elevation: 0,
          side: BorderSide(color: cs.outline, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.onSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: cs.outline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: cs.outline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: destructive, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: destructive, width: 2),
        ),
        filled: true,
        fillColor: background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacing3,
          vertical: spacing2,
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: fontSize4xl,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
        displayMedium: TextStyle(
          fontSize: fontSize3xl,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
        displaySmall: TextStyle(
          fontSize: fontSize2xl,
          fontWeight: FontWeight.bold,
          color: foreground,
        ),
        headlineLarge: TextStyle(
          fontSize: fontSize2xl,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        headlineMedium: TextStyle(
          fontSize: fontSizeXl,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        headlineSmall: TextStyle(
          fontSize: fontSizeLg,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        titleLarge: TextStyle(
          fontSize: fontSizeBase,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
        titleMedium: TextStyle(
          fontSize: fontSizeSm,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        titleSmall: TextStyle(
          fontSize: fontSizeXs,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        bodyLarge: TextStyle(fontSize: fontSizeBase, color: foreground),
        bodyMedium: TextStyle(fontSize: fontSizeSm, color: foreground),
        bodySmall: TextStyle(fontSize: fontSizeXs, color: mutedForeground),
        labelLarge: TextStyle(
          fontSize: fontSizeSm,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        labelMedium: TextStyle(
          fontSize: fontSizeXs,
          fontWeight: FontWeight.w500,
          color: foreground,
        ),
        labelSmall: TextStyle(
          fontSize: 10.0,
          fontWeight: FontWeight.w500,
          color: mutedForeground,
        ),
      ),
    );
  }

  /// 基于 seed color 构建暗色主题（仅影响 ColorScheme 与关键控件的强调色）
  static ThemeData darkThemeFor(Color seed) {
    final Color darkSeed = _effectiveSeedForDark(seed);
    final ColorScheme cs =
        ColorScheme.fromSeed(
          seedColor: darkSeed,
          brightness: Brightness.dark,
        ).copyWith(
          primary: darkSeed,
          surface: darkCard,
          onSurface: darkForeground,
          outline: darkBorder,
          surfaceVariant: darkInput,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return cs.onPrimary;
          return cs.onSurfaceVariant; // 深色模式下关闭态保持与界面一致的中性颜色
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected))
            return cs.primary.withOpacity(0.85);
          return cs.surface;
        }),
        trackOutlineColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected))
            return cs.primary.withOpacity(0.6);
          return cs.outline;
        }),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: darkForeground,
        iconTheme: IconThemeData(color: darkForeground),
        elevation: 0,
      ),
      dividerColor: cs.outline,
      progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.primary),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cs.surfaceVariant,
        selectedItemColor: cs.primary,
        unselectedItemColor: cs.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        selectedIconTheme: IconThemeData(color: cs.primary, size: 20),
        unselectedIconTheme: IconThemeData(
          color: cs.onSurfaceVariant,
          size: 18,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        dragHandleColor: cs.onSurfaceVariant.withOpacity(0.4),
        elevation: 0,
        modalElevation: 0,
        backgroundColor: cs.surface,
        modalBackgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
        clipBehavior: Clip.hardEdge,
      ),
      scaffoldBackgroundColor: darkBackground,
      iconTheme: const IconThemeData(color: darkForeground),
      cardTheme: const CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
          side: BorderSide(color: darkBorder, width: 1),
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: fontSize4xl,
          fontWeight: FontWeight.bold,
          color: darkForeground,
        ),
        displayMedium: TextStyle(
          fontSize: fontSize3xl,
          fontWeight: FontWeight.bold,
          color: darkForeground,
        ),
        displaySmall: TextStyle(
          fontSize: fontSize2xl,
          fontWeight: FontWeight.bold,
          color: darkForeground,
        ),
        headlineLarge: TextStyle(
          fontSize: fontSize2xl,
          fontWeight: FontWeight.w600,
          color: darkForeground,
        ),
        headlineMedium: TextStyle(
          fontSize: fontSizeXl,
          fontWeight: FontWeight.w600,
          color: darkForeground,
        ),
        headlineSmall: TextStyle(
          fontSize: fontSizeLg,
          fontWeight: FontWeight.w600,
          color: darkForeground,
        ),
        titleLarge: TextStyle(
          fontSize: fontSizeBase,
          fontWeight: FontWeight.w600,
          color: darkForeground,
        ),
        titleMedium: TextStyle(
          fontSize: fontSizeSm,
          fontWeight: FontWeight.w500,
          color: darkForeground,
        ),
        titleSmall: TextStyle(
          fontSize: fontSizeXs,
          fontWeight: FontWeight.w500,
          color: darkForeground,
        ),
        bodyLarge: TextStyle(fontSize: fontSizeBase, color: darkForeground),
        bodyMedium: TextStyle(fontSize: fontSizeSm, color: darkForeground),
        bodySmall: TextStyle(fontSize: fontSizeXs, color: darkMutedForeground),
        labelLarge: TextStyle(
          fontSize: fontSizeSm,
          fontWeight: FontWeight.w500,
          color: darkForeground,
        ),
        labelMedium: TextStyle(
          fontSize: fontSizeXs,
          fontWeight: FontWeight.w500,
          color: darkForeground,
        ),
        labelSmall: TextStyle(
          fontSize: 10.0,
          fontWeight: FontWeight.w500,
          color: darkMutedForeground,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          elevation: 0,
          side: BorderSide(color: cs.outline, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.onSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: cs.outline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: cs.outline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkDestructive, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkDestructive, width: 2),
        ),
        filled: true,
        fillColor: darkCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacing3,
          vertical: spacing2,
        ),
      ),
    );
  }
}
