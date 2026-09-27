// =========================================================================
// HR Pro — الاهتزاز الخفيف عند الأفعال المهمة (بصمة، إرسال، خطأ)
// =========================================================================

import 'package:flutter/services.dart';

abstract final class AppHaptics {
  /// بصمة حضور/انصراف ناجحة.
  static Future<void> success() => HapticFeedback.mediumImpact();

  /// إرسال طلب أو حفظ.
  static Future<void> submit() => HapticFeedback.lightImpact();

  /// خطأ أو رفض.
  static Future<void> error() => HapticFeedback.heavyImpact();

  /// اختيار عنصر (chip، تبويب).
  static Future<void> select() => HapticFeedback.selectionClick();
}
