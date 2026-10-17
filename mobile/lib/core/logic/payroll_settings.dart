// =========================================================================
// HR Pro — إعدادات الرواتب من السيرفر (system_settings.payroll_policy)
// =========================================================================
// يوم القطع نفس اللي يحسب بيه السيرفر والموقع: إذا تغيّر من الإعدادات، التطبيق يتبعه
// (تدقيق 14/10، المرحلة 9: CODE-004؛ كان 26 مكتوب ثابت بالتطبيق). يتحدث كل ما تنقرا السلف.
// =========================================================================

abstract final class PayrollSettings {
  static const int defaultCutoffDay = 26;

  /// يوم القطع الحالي (آخر قيمة وصلت من السيرفر، وإلا 26).
  static int cutoffDay = defaultCutoffDay;

  /// يوم القطع من قيمة payroll_policy (null = ماكو قيمة صالحة، فيبقى الحالي).
  static int? cutoffDayFrom(Object? policy) {
    if (policy is! Map) return null;
    final v = policy['cutoff_day'];
    final n = v is num ? v.toInt() : int.tryParse('$v');
    return n != null && n >= 1 && n <= 31 ? n : null;
  }

  /// يحدّث يوم القطع من قيمة payroll_policy.
  static void apply(Object? policy) => cutoffDay = cutoffDayFrom(policy) ?? cutoffDay;

  /// يوم بداية ونهاية الدورة للكشوف القديمة (cycle_start_day / cycle_end_day؛ الافتراضي 25 و24).
  /// null = قيمة مكتوبة غلط، فتبقى الأيام الحالية.
  static ({int start, int end})? cycleDaysFrom(Object? policy) {
    if (policy is! Map) return null;
    int? day(String key, int fallback) {
      final v = policy[key];
      return v == null ? fallback : int.tryParse('$v');
    }

    final start = day('cycle_start_day', 25), end = day('cycle_end_day', 24);
    return start == null || end == null ? null : (start: start, end: end);
  }
}
