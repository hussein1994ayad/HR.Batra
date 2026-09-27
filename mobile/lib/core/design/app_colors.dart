// =========================================================================
// HR Pro — ألوان التصميم (Design tokens: color)
// =========================================================================
// التطبيق بالوضع الداكن فقط. كل الشاشات تأخذ ألوانها من هنا —
// لا تكتب Color(0x...) أو Colors.white داخل الشاشات.
//
//   الخلفية والسطوح: bg ← surface1 (بطاقات) ← surface2 (حقول/مرتفع) ← surface3 (نوافذ)
//   النص:            textPrimary / textSecondary / textMuted / textDisabled
//   الحالات:          success / warning / danger / info (+ Container للخلفية الخفيفة)
//
// كل ألوان النص تحقق تباين WCAG AA (4.5:1 أو أكثر) على bg وsurface1.
// =========================================================================

import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── الخلفية والسطوح ─────────────────────────────────────────────────────
  static const Color bg = Color(0xFF0A0E16);
  static const Color surface1 = Color(0xFF121824);
  static const Color surface2 = Color(0xFF1A2130);
  static const Color surface3 = Color(0xFF232C3D);

  // ── الحدود ─────────────────────────────────────────────────────────────
  static const Color border = Color(0x1AFFFFFF); // 10%
  static const Color borderStrong = Color(0x33FFFFFF); // 20%

  // ── النص والأيقونات ────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF1F5F9); // 16:1
  static const Color textSecondary = Color(0xFFB6BFCD); // 10:1
  static const Color textMuted = Color(0xFF8C97A8); // 6:1
  static const Color textDisabled = Color(0xFF5E6878);

  // ── هوية الشركة (Teal) ─────────────────────────────────────────────────
  static const Color brand = Color(0xFF2DD4BF);
  static const Color brandStrong = Color(0xFF14B8A6);
  static const Color onBrand = Color(0xFF032E2A);
  static const Color brandContainer = Color(0xFF0D3B37);
  static const Color onBrandContainer = Color(0xFF99F6E4);

  // لون ثانوي هادئ للتمييز (الإدارة، التعاميم...)
  static const Color accent = Color(0xFFA78BFA);
  static const Color accentContainer = Color(0xFF2A2350);

  // ── الحالات ────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF34D399);
  static const Color successContainer = Color(0xFF0E3A2D);
  static const Color warning = Color(0xFFFBBF24);
  static const Color warningContainer = Color(0xFF3B2D0B);
  static const Color danger = Color(0xFFF87171);
  static const Color dangerContainer = Color(0xFF3E1719);
  static const Color info = Color(0xFF60A5FA);
  static const Color infoContainer = Color(0xFF122A4A);

  /// نص فوق لون حالة ممتلئ (زر أخضر/أحمر...).
  static const Color onStatus = Color(0xFF0A0E16);

  // ── طبقات ──────────────────────────────────────────────────────────────
  static const Color scrim = Color(0x99000000);
  static const Color shadow = Color(0x66000000);
  static const Color overlay = Color(0x0FFFFFFF); // hover/pressed 6%
}

/// درجة لونية لحالة ما: لون أساسي + خلفية خفيفة. تُستعمل للشارات والبطاقات.
enum AppTone {
  brand(AppColors.brand, AppColors.brandContainer),
  success(AppColors.success, AppColors.successContainer),
  warning(AppColors.warning, AppColors.warningContainer),
  danger(AppColors.danger, AppColors.dangerContainer),
  info(AppColors.info, AppColors.infoContainer),
  accent(AppColors.accent, AppColors.accentContainer),
  neutral(AppColors.textSecondary, AppColors.surface2);

  const AppTone(this.color, this.container);
  final Color color;
  final Color container;
}
