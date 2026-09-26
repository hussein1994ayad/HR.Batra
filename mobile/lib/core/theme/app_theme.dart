// =========================================================================
// HR Pro — ثيم التطبيق (داكن فقط)
// =========================================================================
// يُبنى بالكامل من رموز التصميم في lib/core/design/. الشاشات لا تكتب ألواناً
// أو أحجاماً مباشرة — تستعمل AppColors / AppSpace / AppRadius / AppText
// ومكوّنات lib/presentation/shared/ui/.
// =========================================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/design.dart';

class AppTheme {
  AppTheme._();

  // اختصارات قديمة ما زالت مستعملة في ملفات قليلة — تشير لنفس الرموز.
  static const double space1 = AppSpace.xs;
  static const double space2 = AppSpace.sm;
  static const double space3 = AppSpace.md;
  static const double space4 = AppSpace.lg;
  static const double space5 = AppSpace.xl;
  static const double space6 = AppSpace.xxl;
  static const double space8 = AppSpace.x3;
  static const double radiusXs = AppRadius.xs;
  static const double radiusSm = AppRadius.sm;
  static const double radiusMd = AppRadius.md;
  static const double radiusLg = AppRadius.lg;
  static const double radiusXl = AppRadius.xl;
  static const Duration motionFast = AppMotion.fast;
  static const Duration motionNormal = AppMotion.normal;
  static const Duration motionSlow = AppMotion.slow;

  /// لون الزر الرئيسي (بدون تدرّج صارخ).
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [AppColors.brand, AppColors.brandStrong],
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
  );

  static final ThemeData darkTheme = _build();

  static ThemeData _build() {
    const scheme = ColorScheme.dark(
      primary: AppColors.brand,
      onPrimary: AppColors.onBrand,
      primaryContainer: AppColors.brandContainer,
      onPrimaryContainer: AppColors.onBrandContainer,
      secondary: AppColors.accent,
      onSecondary: AppColors.bg,
      secondaryContainer: AppColors.accentContainer,
      onSecondaryContainer: AppColors.textPrimary,
      tertiary: AppColors.info,
      surface: AppColors.surface1,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.bg,
      surfaceContainerLow: AppColors.surface1,
      surfaceContainer: AppColors.surface1,
      surfaceContainerHigh: AppColors.surface2,
      surfaceContainerHighest: AppColors.surface3,
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.border,
      error: AppColors.danger,
      onError: AppColors.onStatus,
      errorContainer: AppColors.dangerContainer,
      onErrorContainer: AppColors.textPrimary,
      shadow: AppColors.shadow,
      scrim: AppColors.scrim,
    );
    final text = AppText.textTheme();
    const controlShape = RoundedRectangleBorder(borderRadius: AppRadius.control);
    const buttonMin = Size(0, AppSpace.touch);
    const buttonPad = EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: AppSpace.md);

    OutlineInputBorder field(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: AppRadius.control, borderSide: BorderSide(color: c, width: w));

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: AppText.family,
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      dividerColor: AppColors.border,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: AppSpace.lg,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        titleTextStyle: AppText.titleSm,
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 24),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card, side: BorderSide(color: AppColors.border)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.onBrand,
          disabledBackgroundColor: AppColors.surface2,
          disabledForegroundColor: AppColors.textDisabled,
          minimumSize: buttonMin,
          padding: buttonPad,
          shape: controlShape,
          textStyle: AppText.label,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.onBrand,
          disabledBackgroundColor: AppColors.surface2,
          disabledForegroundColor: AppColors.textDisabled,
          elevation: 0,
          minimumSize: buttonMin,
          padding: buttonPad,
          shape: controlShape,
          textStyle: AppText.label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: buttonMin,
          padding: buttonPad,
          side: const BorderSide(color: AppColors.borderStrong),
          shape: controlShape,
          textStyle: AppText.label,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brand,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          shape: controlShape,
          textStyle: AppText.label,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.square(AppSpace.touch),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onBrand,
        elevation: 1,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.md))),
        extendedTextStyle: AppText.label,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md + 2),
        border: field(AppColors.border),
        enabledBorder: field(AppColors.border),
        disabledBorder: field(Colors.transparent),
        focusedBorder: field(AppColors.brand, 1.5),
        errorBorder: field(AppColors.danger),
        focusedErrorBorder: field(AppColors.danger, 1.5),
        hintStyle: AppText.body.copyWith(color: AppColors.textMuted),
        labelStyle: AppText.body.copyWith(color: AppColors.textSecondary),
        floatingLabelStyle: AppText.bodySm.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700),
        helperStyle: AppText.caption,
        errorStyle: AppText.caption.copyWith(color: AppColors.danger),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface2,
        selectedColor: AppColors.brandContainer,
        disabledColor: AppColors.surface1,
        checkmarkColor: AppColors.brand,
        labelStyle: AppText.bodySm.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        secondaryLabelStyle: AppText.bodySm.copyWith(color: AppColors.onBrandContainer, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
        side: const BorderSide(color: AppColors.border),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        minVerticalPadding: AppSpace.md,
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.lg),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface3,
        contentTextStyle: AppText.body.copyWith(fontSize: 14),
        actionTextColor: AppColors.brand,
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.control),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface1,
        modalBackgroundColor: AppColors.surface1,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.borderStrong,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.sheet),
        constraints: BoxConstraints(maxWidth: 640),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface2,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg))),
        titleTextStyle: AppText.titleSm,
        contentTextStyle: AppText.body.copyWith(color: AppColors.textSecondary),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.surface3,
        surfaceTintColor: Colors.transparent,
        textStyle: AppText.body,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.brand,
        linearTrackColor: AppColors.surface2,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.onBrand : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.brand : AppColors.surface3),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.brand : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(AppColors.onBrand),
        side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.brand : AppColors.textMuted),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.brand,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: AppColors.border,
        labelStyle: AppText.label,
        unselectedLabelStyle: AppText.label.copyWith(fontWeight: FontWeight.w600),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface1,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.brandContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => AppText.caption.copyWith(
            color: s.contains(WidgetState.selected) ? AppColors.textPrimary : AppColors.textMuted,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.brand : AppColors.textMuted, size: 24),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface1,
        indicatorColor: AppColors.brandContainer,
        selectedIconTheme: const IconThemeData(color: AppColors.brand),
        unselectedIconTheme: const IconThemeData(color: AppColors.textMuted),
        selectedLabelTextStyle: AppText.caption.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: AppText.caption,
        labelType: NavigationRailLabelType.all,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.surface1,
          foregroundColor: AppColors.textSecondary,
          selectedBackgroundColor: AppColors.brandContainer,
          selectedForegroundColor: AppColors.onBrandContainer,
          side: const BorderSide(color: AppColors.border),
          textStyle: AppText.bodySm.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: AppColors.surface2,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.surface3,
        headerForegroundColor: AppColors.textPrimary,
        dayStyle: AppText.bodySm,
        yearStyle: AppText.bodySm,
        todayBorder: BorderSide(color: AppColors.brand),
        rangeSelectionBackgroundColor: AppColors.brandContainer,
      ),
      timePickerTheme: const TimePickerThemeData(backgroundColor: AppColors.surface2),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.all(Radius.circular(AppRadius.xs))),
        textStyle: AppText.caption.copyWith(color: AppColors.textPrimary),
      ),
      badgeTheme: const BadgeThemeData(backgroundColor: AppColors.danger, textColor: AppColors.textPrimary),
      scrollbarTheme: const ScrollbarThemeData(thumbColor: WidgetStatePropertyAll(AppColors.borderStrong)),
      cupertinoOverrideTheme: const CupertinoThemeData(brightness: Brightness.dark, primaryColor: AppColors.brand),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
