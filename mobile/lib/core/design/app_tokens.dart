// =========================================================================
// HR Pro — المسافات، الزوايا، الظلال، الحركة، ونقاط التجاوب
// =========================================================================

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// مسافات على شبكة 4 نقاط.
abstract final class AppSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double x3 = 32;
  static const double x4 = 40;
  static const double x5 = 48;

  /// الهامش الجانبي للصفحة.
  static const double page = 16;

  /// أقل حجم لمنطقة اللمس (Material/Apple).
  static const double touch = 48;
}

abstract final class AppRadius {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double full = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius control = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius sheet = BorderRadius.vertical(top: Radius.circular(xl));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(full));
}

/// الظلال — خفيفة لأن الوضع داكن؛ العمق يأتي من درجات السطح.
abstract final class AppElevation {
  static const List<BoxShadow> none = [];
  static const List<BoxShadow> low = [
    BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> high = [
    BoxShadow(color: AppColors.shadow, blurRadius: 24, offset: Offset(0, 10)),
  ];
}

/// الحركة: 150–300ms، وتُلغى عند تفعيل "تقليل الحركة" في الجهاز.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 300);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// مدة الحركة مع احترام إعداد "تقليل الحركة".
  static Duration of(BuildContext context, [Duration d = normal]) => reduced(context) ? Duration.zero : d;
}

/// نقاط التجاوب (Material 3 window size classes).
enum WindowSize { compact, medium, expanded }

abstract final class AppBreakpoints {
  static const double medium = 600;
  static const double expanded = 840;

  /// أقصى عرض للمحتوى على التابلت والشاشات العريضة.
  static const double maxContent = 720;
  static const double maxForm = 560;

  static WindowSize of(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= expanded) return WindowSize.expanded;
    if (w >= medium) return WindowSize.medium;
    return WindowSize.compact;
  }
}
