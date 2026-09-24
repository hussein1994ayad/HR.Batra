// =========================================================================
// نظام HR Pro v6.0 - نظام التصميم الموحّد (Design System)
// =========================================================================
// تحديث: بنية أكثر عصرية مع الحفاظ التام على توافق الأسماء القديمة.
// - Material 3 كامل مع ColorScheme متكامل
// - Design tokens: spacing، radius، elevation، durations
// - Typography scale مضبوطة للعربية (Cairo)
// - Shadows متعددة الطبقات، smooth ripple، micro-animations
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// نظام التصميم الموحّد للتطبيق
class AppTheme {
  AppTheme._();

  // ==========================================================================
  // 1. لوحة الألوان (Color Palette) — أسماء محفوظة للتوافق الخلفي
  // ==========================================================================
  static const Color primaryTeal = Color(0xFF0F766E);
  static const Color primaryTealLight = Color(0xFF14B8A6);
  static const Color primaryTealDark = Color(0xFF115E59);
  static const Color accentIndigo = Color(0xFF4F46E5);

  // ألوان تمييزية (Accent Colors)
  static const Color neonCyan = Color(0xFF06B6D4);
  static const Color neonPink = Color(0xFFEC4899);
  static const Color cyberPurple = Color(0xFF8B5CF6);

  // ألوان الحالات
  static const Color successGreen = Color(0xFF10B981);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color dangerRed = Color(0xFFEF4444);
  static const Color infoBlue = Color(0xFF3B82F6);

  // Light mode
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Colors.white;
  static const Color lightSurfaceVariant = Color(0xFFF1F5F9);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF94A3B8);

  // Dark mode
  static const Color darkBg = Color(0xFF0B0F19);
  static const Color darkSurface = Color(0xFF111827);
  static const Color darkSurfaceVariant = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);

  // ==========================================================================
  // 2. Design Tokens — Spacing / Radius / Elevation / Motion
  // ==========================================================================

  /// مسافات موحّدة (Spacing scale — 4pt grid)
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;
  static const double space12 = 48;

  /// أنصاف أقطار موحّدة (Radius tokens)
  static const double radiusXs = 8;
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 24;
  static const double radiusFull = 999;

  /// مُدد الحركة (Motion durations)
  static const Duration motionFast = Duration(milliseconds: 150);
  static const Duration motionNormal = Duration(milliseconds: 250);
  static const Duration motionSlow = Duration(milliseconds: 400);

  /// منحنيات الحركة (Motion curves)
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveEmphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  // ==========================================================================
  // 3. Shadows — طبقات متعددة لعمق طبيعي
  // ==========================================================================
  static List<BoxShadow> shadowSm(bool isDark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> shadowMd(bool isDark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> shadowLg(bool isDark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
          blurRadius: 24,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
          blurRadius: 6,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> glowPrimary({double opacity = 0.35}) => [
        BoxShadow(
          color: primaryTeal.withValues(alpha: opacity),
          blurRadius: 24,
          spreadRadius: 2,
          offset: const Offset(0, 8),
        ),
      ];

  // ==========================================================================
  // 4. تدرجات لونية (Gradients)
  // ==========================================================================
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryTealLight, primaryTeal, primaryTealDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyberGradient = LinearGradient(
    colors: [neonCyan, cyberPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentIndigo, Color(0xFF3730A3)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF34D399), successGreen, Color(0xFF047857)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0xFFFBBF24), warningOrange, Color(0xFFB45309)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFF87171), dangerRed, Color(0xFFB91C1C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // خلفيات ناعمة
  static const LinearGradient lightBgGradient = LinearGradient(
    colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient darkBgGradient = LinearGradient(
    colors: [Color(0xFF0B0F19), Color(0xFF0F172A), Color(0xFF111827)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ==========================================================================
  // 5. Typography Scale
  // ==========================================================================
  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    final base = GoogleFonts.cairoTextTheme();
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        color: primary,
        fontSize: 34,
        fontWeight: FontWeight.w900,
        height: 1.2,
        letterSpacing: -0.5,
      ),
      displayMedium: base.displayMedium?.copyWith(
        color: primary,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.25,
      ),
      displaySmall: base.displaySmall?.copyWith(
        color: primary,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        color: primary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        color: primary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: primary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.titleMedium?.copyWith(
        color: primary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: primary,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.5,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: primary,
        fontSize: 14,
        height: 1.5,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: secondary,
        fontSize: 12,
        height: 1.5,
      ),
      labelLarge: base.labelLarge?.copyWith(
        color: primary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }

  // ==========================================================================
  // 6. Light Theme
  // ==========================================================================
  static final ThemeData lightTheme = _buildLightTheme();

  static ThemeData _buildLightTheme() {
    const scheme = ColorScheme.light(
      primary: primaryTeal,
      primaryContainer: Color(0xFFCCFBF1),
      onPrimaryContainer: primaryTealDark,
      secondary: accentIndigo,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE0E7FF),
      onSecondaryContainer: Color(0xFF312E81),
      tertiary: cyberPurple,
      onSurface: lightTextPrimary,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFFAFBFC),
      surfaceContainer: lightSurfaceVariant,
      surfaceContainerHigh: Color(0xFFE2E8F0),
      surfaceContainerHighest: Color(0xFFCBD5E1),
      outline: lightBorder,
      outlineVariant: Color(0xFFE2E8F0),
      error: dangerRed,
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF7F1D1D),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      primaryColor: primaryTeal,
      scaffoldBackgroundColor: lightBg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _buildTextTheme(lightTextPrimary, lightTextSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: lightSurface,
        foregroundColor: lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: lightTextPrimary,
        ),
        iconTheme: const IconThemeData(color: lightTextPrimary, size: 24),
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: lightBorder),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryTeal,
          foregroundColor: Colors.white,
          disabledBackgroundColor: lightSurfaceVariant,
          disabledForegroundColor: lightTextMuted,
          elevation: 0,
          shadowColor: primaryTeal.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 16),
          animationDuration: motionFast,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryTeal,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: primaryTeal, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryTeal,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: primaryTeal, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: dangerRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: dangerRed, width: 2),
        ),
        hintStyle: GoogleFonts.cairo(color: lightTextMuted, fontSize: 14),
        labelStyle: GoogleFonts.cairo(color: lightTextSecondary, fontSize: 14),
        floatingLabelStyle: GoogleFonts.cairo(color: primaryTeal, fontSize: 14, fontWeight: FontWeight.w600),
        prefixIconColor: lightTextMuted,
        suffixIconColor: lightTextMuted,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightSurfaceVariant,
        selectedColor: primaryTeal.withValues(alpha: 0.12),
        labelStyle: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusFull)),
        side: BorderSide.none,
      ),
      dividerTheme: const DividerThemeData(color: lightBorder, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: lightTextPrimary,
        contentTextStyle: GoogleFonts.cairo(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
        showDragHandle: true,
        dragHandleColor: lightBorder,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
        titleTextStyle: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w800, color: lightTextPrimary),
        contentTextStyle: GoogleFonts.cairo(fontSize: 14, color: lightTextSecondary, height: 1.5),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryTeal,
        linearTrackColor: lightBorder,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryTeal,
        unselectedLabelColor: lightTextSecondary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  // ==========================================================================
  // 7. Dark Theme
  // ==========================================================================
  static final ThemeData darkTheme = _buildDarkTheme();

  static ThemeData _buildDarkTheme() {
    const scheme = ColorScheme.dark(
      primary: primaryTealLight,
      onPrimary: Color(0xFF00201D),
      primaryContainer: primaryTealDark,
      onPrimaryContainer: Color(0xFFCCFBF1),
      secondary: Color(0xFF818CF8),
      onSecondary: Color(0xFF1E1B4B),
      secondaryContainer: Color(0xFF3730A3),
      onSecondaryContainer: Color(0xFFE0E7FF),
      tertiary: cyberPurple,
      surface: darkSurface,
      onSurface: darkTextPrimary,
      surfaceContainerLowest: Color(0xFF060911),
      surfaceContainerLow: Color(0xFF0F172A),
      surfaceContainer: darkSurfaceVariant,
      surfaceContainerHigh: Color(0xFF334155),
      surfaceContainerHighest: Color(0xFF475569),
      outline: darkBorder,
      outlineVariant: Color(0xFF1E293B),
      error: Color(0xFFF87171),
      onError: Color(0xFF450A0A),
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: Color(0xFFFEE2E2),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      primaryColor: primaryTeal,
      scaffoldBackgroundColor: darkBg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: _buildTextTheme(darkTextPrimary, darkTextSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.cairo(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: darkTextPrimary,
        ),
        iconTheme: const IconThemeData(color: darkTextPrimary, size: 24),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: darkBorder.withValues(alpha: 0.5)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryTeal,
          foregroundColor: Colors.white,
          disabledBackgroundColor: darkSurfaceVariant,
          disabledForegroundColor: darkTextMuted,
          elevation: 0,
          shadowColor: primaryTeal.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 16),
          animationDuration: motionFast,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryTealLight,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 22),
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: primaryTealLight, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryTealLight,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: primaryTealLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: dangerRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: dangerRed, width: 2),
        ),
        hintStyle: GoogleFonts.cairo(color: darkTextMuted, fontSize: 14),
        labelStyle: GoogleFonts.cairo(color: darkTextSecondary, fontSize: 14),
        floatingLabelStyle: GoogleFonts.cairo(color: primaryTealLight, fontSize: 14, fontWeight: FontWeight.w600),
        prefixIconColor: darkTextMuted,
        suffixIconColor: darkTextMuted,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkSurfaceVariant,
        selectedColor: primaryTealLight.withValues(alpha: 0.2),
        labelStyle: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: darkTextPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusFull)),
        side: BorderSide.none,
      ),
      dividerTheme: DividerThemeData(color: darkBorder.withValues(alpha: 0.5), thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkSurfaceVariant,
        contentTextStyle: GoogleFonts.cairo(color: darkTextPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          side: BorderSide(color: darkBorder.withValues(alpha: 0.5)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
        showDragHandle: true,
        dragHandleColor: darkBorder,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
        titleTextStyle: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w800, color: darkTextPrimary),
        contentTextStyle: GoogleFonts.cairo(fontSize: 14, color: darkTextSecondary, height: 1.5),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryTealLight,
        linearTrackColor: darkBorder,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryTealLight,
        unselectedLabelColor: darkTextSecondary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
