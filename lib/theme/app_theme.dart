import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFFD97757);
  static const Color primaryForeground = Color(0xFF141413);
  static const Color secondary = Color(0xFF6A9BCC);
  static const Color secondaryForeground = Color(0xFFFAF9F5);
  static const Color muted = Color(0xFFE8E6DC);
  static const Color mutedForeground = Color(0xFF828179);
  static const Color accent = Color(0xFFD97757);
  static const Color accentForeground = Color(0xFF141413);
  static const Color destructive = Color(0xFFB8644F);
  static const Color destructiveForeground = Color(0xFFFAF9F5);
  static const Color border = Color(0xFFD8D4C9);
  static const Color input = Color(0xFFF0EFEA);
  static const Color ring = Color(0xFFD97757);
  static const Color background = Color(0xFFFAF9F5);
  static const Color pageBackgroundLight = background;
  static const Color foreground = Color(0xFF141413);
  static const Color card = Color(0xFFE8E6DC);
  static const Color cardForeground = Color(0xFF141413);
  static const Color popover = Color(0xFFF0EFEA);
  static const Color popoverForeground = Color(0xFF141413);

  static const Color success = Color(0xFF788C5D);
  static const Color successForeground = Color(0xFFFAF9F5);
  static const Color warning = Color(0xFF9B7656);
  static const Color warningForeground = Color(0xFFFAF9F5);
  static const Color info = Color(0xFF6A9BCC);
  static const Color infoForeground = Color(0xFFFAF9F5);

  static const double radiusXs = 2.0;
  static const double radiusSm = 4.0;
  static const double radiusMd = 6.0;
  static const double radiusLg = 8.0;
  static const double radiusXl = 12.0;

  static const double spacing1 = 4.0;
  static const double spacing2 = 8.0;
  static const double spacing3 = 12.0;
  static const double spacing4 = 16.0;
  static const double spacing5 = 20.0;
  static const double spacing6 = 24.0;
  static const double spacing8 = 32.0;
  static const double spacing10 = 40.0;
  static const double spacing12 = 48.0;
  static const double spacing16 = 64.0;
  static const double spacing20 = 80.0;

  static const double fontSizeXs = 12.0;
  static const double fontSizeSm = 14.0;
  static const double fontSizeBase = 16.0;
  static const double fontSizeLg = 18.0;
  static const double fontSizeXl = 20.0;
  static const double fontSize2xl = 24.0;
  static const double fontSize3xl = 30.0;
  static const double fontSize4xl = 36.0;

  static const List<BoxShadow> shadowNone = [];

  static const Color darkPrimary = Color(0xFFD97757);
  static const Color darkPrimaryForeground = Color(0xFF141413);
  static const Color darkSecondary = Color(0xFF86ADD3);
  static const Color darkSecondaryForeground = Color(0xFF141413);
  static const Color darkMuted = Color(0xFF2A2926);
  static const Color darkMutedForeground = Color(0xFFD8D1C4);
  static const Color darkAccent = Color(0xFFD97757);
  static const Color darkAccentForeground = Color(0xFF141413);
  static const Color darkDestructive = Color(0xFFB66C5A);
  static const Color darkDestructiveForeground = Color(0xFFFAF9F5);
  static const Color darkBorder = Color(0xFF3D3D3A);
  static const Color darkInput = Color(0xFF1F1E1B);
  static const Color darkRing = Color(0xFFD97757);
  static const Color darkBackground = Color(0xFF141413);
  static const Color darkForeground = Color(0xFFFAF9F5);
  static const Color darkCard = Color(0xFF2A2926);
  static const Color darkCardForeground = Color(0xFFFAF9F5);
  static const Color darkPopover = Color(0xFF1F1E1B);
  static const Color darkPopoverForeground = Color(0xFFFAF9F5);
  static const Color darkSelectedAccent = Color(0xFF86ADD3);

  static const Color _lightSubtle = Color(0xFFF0EFEA);
  static const Color _lightCard = Color(0xFFE8E6DC);
  static const Color _lightPrimaryContainer = Color(0xFFF2E0D7);
  static const Color _lightSecondaryContainer = Color(0xFFDCE7F1);
  static const Color _lightTertiaryContainer = Color(0xFFE2E8D9);
  static const Color _lightErrorContainer = Color(0xFFF1DED8);
  static const Color _lightOutlineVariant = Color(0xFFE3DED2);
  static const Color _lightSurfaceHigh = Color(0xFFE3DFD4);
  static const Color _lightSurfaceHighest = Color(0xFFDFDBCF);
  static const Color _lightInversePrimary = Color(0xFFE6A48A);

  static const Color _darkSubtle = Color(0xFF1F1E1B);
  static const Color _darkCard = Color(0xFF2A2926);
  static const Color _darkPrimaryContainer = Color(0xFF5D372D);
  static const Color _darkSecondaryContainer = Color(0xFF243747);
  static const Color _darkTertiaryContainer = Color(0xFF323D28);
  static const Color _darkErrorContainer = Color(0xFF4A2D27);
  static const Color _darkOutlineVariant = Color(0xFF4A4844);
  static const Color _darkSurfaceHigh = Color(0xFF2F2E2B);
  static const Color _darkSurfaceHighest = Color(0xFF353431);

  static const ColorScheme _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: primary,
    onPrimary: primaryForeground,
    primaryContainer: _lightPrimaryContainer,
    onPrimaryContainer: foreground,
    secondary: secondary,
    onSecondary: secondaryForeground,
    secondaryContainer: _lightSecondaryContainer,
    onSecondaryContainer: foreground,
    tertiary: success,
    onTertiary: successForeground,
    tertiaryContainer: _lightTertiaryContainer,
    onTertiaryContainer: foreground,
    error: destructive,
    onError: destructiveForeground,
    errorContainer: _lightErrorContainer,
    onErrorContainer: foreground,
    surface: _lightSubtle,
    onSurface: foreground,
    surfaceDim: _lightSubtle,
    surfaceBright: Color(0xFFFCFBF7),
    surfaceContainerLowest: background,
    surfaceContainerLow: _lightSubtle,
    surfaceContainer: _lightCard,
    surfaceContainerHigh: _lightSurfaceHigh,
    surfaceContainerHighest: _lightSurfaceHighest,
    onSurfaceVariant: mutedForeground,
    outline: border,
    outlineVariant: _lightOutlineVariant,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: darkBackground,
    onInverseSurface: darkForeground,
    inversePrimary: _lightInversePrimary,
    surfaceTint: Colors.transparent,
  );

  static const ColorScheme _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: darkPrimary,
    onPrimary: darkPrimaryForeground,
    primaryContainer: _darkPrimaryContainer,
    onPrimaryContainer: darkForeground,
    secondary: darkSecondary,
    onSecondary: darkSecondaryForeground,
    secondaryContainer: _darkSecondaryContainer,
    onSecondaryContainer: darkForeground,
    tertiary: Color(0xFF8EA076),
    onTertiary: foreground,
    tertiaryContainer: _darkTertiaryContainer,
    onTertiaryContainer: darkForeground,
    error: darkDestructive,
    onError: darkDestructiveForeground,
    errorContainer: _darkErrorContainer,
    onErrorContainer: darkForeground,
    surface: _darkSubtle,
    onSurface: darkForeground,
    surfaceDim: darkBackground,
    surfaceBright: _darkCard,
    surfaceContainerLowest: Color(0xFF0E0E0D),
    surfaceContainerLow: _darkSubtle,
    surfaceContainer: _darkCard,
    surfaceContainerHigh: _darkSurfaceHigh,
    surfaceContainerHighest: _darkSurfaceHighest,
    onSurfaceVariant: darkMutedForeground,
    outline: darkBorder,
    outlineVariant: _darkOutlineVariant,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: background,
    onInverseSurface: foreground,
    inversePrimary: primary,
    surfaceTint: Colors.transparent,
  );

  static ThemeData get lightTheme => _buildThemeData(
    colorScheme: _lightColorScheme,
    scaffoldBackgroundColor: background,
    appBarBackgroundColor: background,
    cardColor: card,
    inputFillColor: _lightSubtle,
    primaryButtonBackgroundColor: foreground,
    primaryButtonForegroundColor: background,
    secondaryButtonBackgroundColor: _lightCard,
    secondaryButtonForegroundColor: foreground,
  );

  static ThemeData get darkTheme => _buildThemeData(
    colorScheme: _darkColorScheme,
    scaffoldBackgroundColor: darkBackground,
    appBarBackgroundColor: darkBackground,
    cardColor: darkCard,
    inputFillColor: _darkSubtle,
    primaryButtonBackgroundColor: darkPrimary,
    primaryButtonForegroundColor: darkPrimaryForeground,
    secondaryButtonBackgroundColor: _darkCard,
    secondaryButtonForegroundColor: darkForeground,
  );

  static ThemeData _buildThemeData({
    required ColorScheme colorScheme,
    required Color scaffoldBackgroundColor,
    required Color appBarBackgroundColor,
    required Color cardColor,
    required Color inputFillColor,
    required Color primaryButtonBackgroundColor,
    required Color primaryButtonForegroundColor,
    required Color secondaryButtonBackgroundColor,
    required Color secondaryButtonForegroundColor,
  }) {
    final bool isDark = colorScheme.brightness == Brightness.dark;

    final TextTheme textTheme = TextTheme(
      displayLarge: TextStyle(
        fontSize: fontSize4xl,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      displayMedium: TextStyle(
        fontSize: fontSize3xl,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      displaySmall: TextStyle(
        fontSize: fontSize2xl,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      headlineLarge: TextStyle(
        fontSize: fontSize2xl,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: fontSizeXl,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: fontSizeLg,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: fontSizeBase,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: fontSizeSm,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: fontSizeXs,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: fontSizeBase,
        color: colorScheme.onSurface,
      ),
      bodyMedium: TextStyle(fontSize: fontSizeSm, color: colorScheme.onSurface),
      bodySmall: TextStyle(
        fontSize: fontSizeXs,
        color: colorScheme.onSurfaceVariant,
      ),
      labelLarge: TextStyle(
        fontSize: fontSizeSm,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurface,
      ),
      labelMedium: TextStyle(
        fontSize: fontSizeXs,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurface,
      ),
      labelSmall: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    final RoundedRectangleBorder mediumShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMd),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      dividerColor: colorScheme.outline,
      iconTheme: IconThemeData(color: colorScheme.onSurface),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBackgroundColor,
        foregroundColor: colorScheme.onSurface,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 48,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        selectedIconTheme: IconThemeData(color: colorScheme.primary, size: 20),
        unselectedIconTheme: IconThemeData(
          color: colorScheme.onSurfaceVariant,
          size: 18,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        modalBackgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
        clipBehavior: Clip.hardEdge,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
          side: BorderSide(color: colorScheme.outline, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: colorScheme.outline, width: 1),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? const Color(0xE01F1E1B)
            : const Color(0xE0141413),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: background,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        selectedColor: colorScheme.primaryContainer,
        secondarySelectedColor: colorScheme.primaryContainer,
        disabledColor: colorScheme.surfaceContainerLow,
        labelStyle: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
        secondaryLabelStyle: textTheme.bodySmall?.copyWith(
          color: colorScheme.onPrimaryContainer,
        ),
        padding: const EdgeInsets.symmetric(horizontal: spacing2, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: colorScheme.outline, width: 1),
        ),
        side: BorderSide(color: colorScheme.outline, width: 1),
        showCheckmark: false,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withValues(alpha: 0.78);
          }
          return colorScheme.surfaceContainerHigh;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withValues(alpha: 0.45);
          }
          return colorScheme.outline;
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryButtonBackgroundColor,
          foregroundColor: primaryButtonForegroundColor,
          surfaceTintColor: Colors.transparent,
          shape: mediumShape,
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryButtonBackgroundColor,
          foregroundColor: primaryButtonForegroundColor,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shape: mediumShape,
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outline, width: 1),
          shape: mediumShape,
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          shape: mediumShape,
          padding: const EdgeInsets.symmetric(
            horizontal: spacing4,
            vertical: spacing2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colorScheme.outline, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colorScheme.outline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colorScheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacing3,
          vertical: spacing2,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        textColor: colorScheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primary.withValues(alpha: 0.22),
        selectionHandleColor: colorScheme.primary,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(radiusLg),
            bottomRight: Radius.circular(radiusLg),
          ),
        ),
      ),
    );
  }
}
