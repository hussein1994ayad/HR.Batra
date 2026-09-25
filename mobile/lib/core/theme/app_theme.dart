// =========================================================================
// HR Pro - Design system: colors, typography and Material 3 component themes
// =========================================================================
//
// The palette matches the web dashboard (indigo/violet brand on a deep navy
// background). Legacy constant names (primaryTeal, neonCyan, cyberPurple…)
// are kept so every existing screen picks up the new look; they now point at
// the refined palette.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  AppTheme._();

  /// Bundled font family (see pubspec.yaml -> fonts).
  static const String fontFamily = 'Cairo';

  // ---------------------------------------------------------------------
  // Brand & semantic colors
  // ---------------------------------------------------------------------
  static const Color brand = Color(0xFF6366F1); // indigo 500
  static const Color brandLight = Color(0xFF818CF8); // indigo 400
  static const Color brandDeep = Color(0xFF4F46E5); // indigo 600
  static const Color violet = Color(0xFF7C3AED); // violet 600
  static const Color violetLight = Color(0xFFA78BFA); // violet 400
  static const Color sky = Color(0xFF38BDF8);
  static const Color pink = Color(0xFFF472B6);

  static const Color successGreen = Color(0xFF10B981);
  static const Color successLight = Color(0xFF34D399);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFBBF24);
  static const Color dangerRed = Color(0xFFF43F5E);
  static const Color dangerLight = Color(0xFFFB7185);

  // Legacy names, remapped to the new palette.
  static const Color primaryTeal = brand;
  static const Color primaryTealLight = brandLight;
  static const Color accentIndigo = violet;
  static const Color neonCyan = brandLight;
  static const Color neonPink = pink;
  static const Color cyberPurple = violetLight;

  // ---------------------------------------------------------------------
  // Surfaces & text (dark)
  // ---------------------------------------------------------------------
  static const Color darkBg = Color(0xFF070B14);
  static const Color darkSurface = Color(0xFF111729);
  static const Color darkSurfaceHigh = Color(0xFF161D2E);
  static const Color darkBorder = Color(0xFF232C42);
  static const Color darkTextPrimary = Color(0xFFEEF2F8);
  static const Color darkTextSecondary = Color(0xFF8B98AE);
  static const Color darkTextMuted = Color(0xFF647189);

  // Surfaces & text (light)
  static const Color lightBg = Color(0xFFF4F6FB);
  static const Color lightSurface = Colors.white;
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B);

  // ---------------------------------------------------------------------
  // Gradients
  // ---------------------------------------------------------------------
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [brand, violet],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static const LinearGradient cyberGradient = primaryGradient;

  static const LinearGradient accentGradient = LinearGradient(
    colors: [violet, Color(0xFF5B21B6)],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [successGreen, Color(0xFF047857)],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [dangerRed, Color(0xFFBE123C)],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  // ---------------------------------------------------------------------
  // Spacing & radii
  // ---------------------------------------------------------------------
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 26;

  /// Maximum content width on tablets / foldables / landscape.
  static const double maxContentWidth = 720;

  // ---------------------------------------------------------------------
  // Themes
  // ---------------------------------------------------------------------
  static final ThemeData darkTheme = _build(Brightness.dark);
  static final ThemeData lightTheme = _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? darkBg : lightBg;
    final surface = isDark ? darkSurface : lightSurface;
    final surfaceHigh = isDark ? darkSurfaceHigh : const Color(0xFFF1F4F9);
    final border = isDark ? darkBorder : lightBorder;
    final textPrimary = isDark ? darkTextPrimary : lightTextPrimary;
    final textSecondary = isDark ? darkTextSecondary : lightTextSecondary;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? brandLight : brand,
      onPrimary: Colors.white,
      primaryContainer: brand.withValues(alpha: isDark ? 0.22 : 0.12),
      onPrimaryContainer: isDark ? const Color(0xFFE0E7FF) : brandDeep,
      secondary: isDark ? violetLight : violet,
      onSecondary: Colors.white,
      secondaryContainer: violet.withValues(alpha: isDark ? 0.22 : 0.12),
      onSecondaryContainer: isDark ? const Color(0xFFEDE9FE) : violet,
      tertiary: sky,
      onTertiary: Colors.white,
      error: dangerRed,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainerLowest: bg,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHigh,
      outline: border,
      outlineVariant: border.withValues(alpha: 0.6),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: isDark ? darkTextPrimary : lightTextPrimary,
      onInverseSurface: isDark ? darkBg : Colors.white,
      surfaceTint: Colors.transparent,
    );

    final baseText = (isDark ? Typography.material2021().white : Typography.material2021().black).apply(
      fontFamily: fontFamily,
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );
    final textTheme = baseText.copyWith(
      headlineSmall: baseText.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.3),
      titleLarge: baseText.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 20, height: 1.3),
      titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 16, height: 1.35),
      titleSmall: baseText.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 14),
      bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 15, height: 1.55),
      bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 14, height: 1.55),
      bodySmall: baseText.bodySmall?.copyWith(fontSize: 12, height: 1.5, color: textSecondary),
      labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 14),
      labelMedium: baseText.labelMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
      labelSmall: baseText.labelSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 0),
    );

    final roundedMd = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd));
    const buttonText = TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 15);
    const buttonPadding = EdgeInsets.symmetric(vertical: 14, horizontal: 22);

    OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: textTheme,
      primaryColor: brand,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: border,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // Android 14+ predictive back animation; falls back gracefully.
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: isDark ? brandLight : brand, size: 22),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: brand.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          padding: buttonPadding,
          minimumSize: const Size(64, 50),
          shape: roundedMd,
          textStyle: buttonText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          padding: buttonPadding,
          minimumSize: const Size(64, 50),
          shape: roundedMd,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: border),
          padding: buttonPadding,
          minimumSize: const Size(64, 50),
          shape: roundedMd,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? brandLight : brand,
          shape: roundedMd,
          textStyle: buttonText.copyWith(fontSize: 14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF0C1220) : const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: inputBorder(border),
        enabledBorder: inputBorder(border),
        focusedBorder: inputBorder(isDark ? brandLight : brand, 1.6),
        errorBorder: inputBorder(dangerRed),
        focusedErrorBorder: inputBorder(dangerRed, 1.6),
        disabledBorder: inputBorder(border.withValues(alpha: 0.5)),
        hintStyle: TextStyle(fontFamily: fontFamily, color: isDark ? darkTextMuted : lightTextSecondary, fontSize: 14),
        labelStyle: TextStyle(fontFamily: fontFamily, color: textSecondary, fontSize: 14),
        floatingLabelStyle: TextStyle(fontFamily: fontFamily, color: isDark ? brandLight : brand, fontWeight: FontWeight.w600),
        errorStyle: const TextStyle(fontFamily: fontFamily, color: dangerLight, fontSize: 12),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF0B1120) : Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: brand.withValues(alpha: isDark ? 0.24 : 0.14),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? (isDark ? const Color(0xFFC7D2FE) : brand) : textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: fontFamily,
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? textPrimary : textSecondary,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: textPrimary,
        unselectedLabelColor: textSecondary,
        indicatorColor: isDark ? brandLight : brand,
        dividerColor: border,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w800, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: brand.withValues(alpha: 0.22),
        side: BorderSide(color: border),
        labelStyle: TextStyle(fontFamily: fontFamily, color: textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? darkSurfaceHigh : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: BorderSide(color: border),
        ),
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w800, color: textPrimary),
        contentTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 14, height: 1.6, color: textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? darkSurfaceHigh : Colors.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: isDark ? darkSurfaceHigh : Colors.white,
        showDragHandle: true,
        dragHandleColor: border,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF1C2438) : lightTextPrimary,
        contentTextStyle: const TextStyle(fontFamily: fontFamily, color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        actionTextColor: brandLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary),
        subtitleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 12.5, color: textSecondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? brandLight : brand,
        linearTrackColor: border,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? brand : surfaceHigh,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? brand : Colors.transparent,
        ),
        side: BorderSide(color: textSecondary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? (isDark ? brandLight : brand) : textSecondary,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: isDark ? darkSurfaceHigh : Colors.white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: brand,
        headerForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXl)),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: isDark ? darkSurfaceHigh : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXl)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? darkSurfaceHigh : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: border),
        ),
        textStyle: TextStyle(fontFamily: fontFamily, color: textPrimary, fontSize: 14),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C2438) : lightTextPrimary,
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        textStyle: const TextStyle(fontFamily: fontFamily, color: Colors.white, fontSize: 12),
      ),
      badgeTheme: const BadgeThemeData(backgroundColor: dangerRed, textColor: Colors.white),
    );
  }
}
