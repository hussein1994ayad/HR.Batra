// =========================================================================
// HR Pro — الخطوط (Cairo مضمّن داخل التطبيق)
// =========================================================================
// سلّم خطوط واضح مع ارتفاع أسطر مريح للعربي. في الشاشات استعمل
// Theme.of(context).textTheme.titleMedium ... أو AppText.* مباشرة.
// =========================================================================

import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppText {
  static const String family = 'Cairo';

  static const TextStyle display = TextStyle(fontFamily: family, fontSize: 32, height: 1.25, fontWeight: FontWeight.w800, color: AppColors.textPrimary);
  static const TextStyle headline = TextStyle(fontFamily: family, fontSize: 24, height: 1.3, fontWeight: FontWeight.w800, color: AppColors.textPrimary);
  static const TextStyle title = TextStyle(fontFamily: family, fontSize: 20, height: 1.35, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const TextStyle titleSm = TextStyle(fontFamily: family, fontSize: 17, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const TextStyle subtitle = TextStyle(fontFamily: family, fontSize: 15, height: 1.45, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static const TextStyle body = TextStyle(fontFamily: family, fontSize: 15, height: 1.6, fontWeight: FontWeight.w500, color: AppColors.textPrimary);
  static const TextStyle bodySm = TextStyle(fontFamily: family, fontSize: 13, height: 1.55, fontWeight: FontWeight.w500, color: AppColors.textSecondary);
  static const TextStyle label = TextStyle(fontFamily: family, fontSize: 14, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const TextStyle caption = TextStyle(fontFamily: family, fontSize: 12, height: 1.45, fontWeight: FontWeight.w500, color: AppColors.textMuted);
  static const TextStyle overline = TextStyle(fontFamily: family, fontSize: 11, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.2);

  /// أرقام (مبالغ، ساعات) — أرقام بعرض ثابت حتى لا "ترقص" عند التحريك.
  static const TextStyle number = TextStyle(
    fontFamily: family,
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextTheme textTheme() => const TextTheme(
        displayLarge: display,
        displayMedium: TextStyle(fontFamily: family, fontSize: 28, height: 1.25, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        displaySmall: headline,
        headlineLarge: headline,
        headlineMedium: TextStyle(fontFamily: family, fontSize: 22, height: 1.3, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        headlineSmall: title,
        titleLarge: title,
        titleMedium: titleSm,
        titleSmall: subtitle,
        bodyLarge: body,
        bodyMedium: TextStyle(fontFamily: family, fontSize: 14, height: 1.6, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
        bodySmall: bodySm,
        labelLarge: label,
        labelMedium: TextStyle(fontFamily: family, fontSize: 13, height: 1.4, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        labelSmall: overline,
      );
}
