import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// البصمة تحتاج الموقع الدقيق: أندرويد 12+ وiOS 14+ يسمحون للمستخدم يعطي موقعاً تقريبياً
/// (يبعد كيلومترات) فتفشل البصمة أو تطلع نتيجتها غلط.
class PreciseLocation {
  PreciseLocation._();

  /// أسوأ دقة GPS مقبولة للبصمة بالأمتار (نفس حد السيرفر في punch_attendance).
  static const double maxPunchAccuracyMeters = 100;

  /// الحد الفعلي لفرع معيّن: فرع نطاقه أوسع من 100 م يتحمّل دقة بقدر نطاقه.
  static double maxAccuracyFor(double branchRadius) =>
      branchRadius > maxPunchAccuracyMeters ? branchRadius : maxPunchAccuracyMeters;

  static const String reducedMessage =
      'الموقع الدقيق مطفي لتطبيق HR Pro، فما نگدر نتأكد إنك داخل الفرع. '
      'فعّل «الموقع الدقيق» من إعدادات الهاتف حتى تگدر تبصم.';

  static String lowAccuracyMessage(double accuracy) =>
      'دقة الموقع ضعيفة حالياً (± ${accuracy.round()} م). '
      'انتظر لحظات بمكان مفتوح حتى تتحسن الإشارة، ثم حاول مرة ثانية.';

  /// يتأكد إن الموقع الدقيق مفعّل، ويطلبه من المستخدم إذا كان تقريبياً.
  /// يرجع true إذا صار دقيقاً (أو النظام ما يدعم الخيار أصلاً).
  static Future<bool> ensure() async {
    try {
      if (await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.precise) return true;
      if (Platform.isIOS) {
        // نافذة النظام المؤقتة (NSLocationTemporaryUsageDescriptionDictionary في Info.plist)
        final status = await Geolocator.requestTemporaryFullAccuracy(purposeKey: 'PreciseLocationAttendance');
        return status == LocationAccuracyStatus.precise;
      }
      // أندرويد: إعادة طلب الصلاحية تعرض خيار الترقية إلى «دقيق»
      await Geolocator.requestPermission();
      return await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.precise;
    } catch (e) {
      // منصة/إصدار بدون خيار الموقع التقريبي: لا نمنع البصمة
      debugPrint('precise location check skipped: $e');
      return true;
    }
  }

  /// يفتح إعدادات التطبيق حتى يفعّل المستخدم الموقع الدقيق.
  static Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
  }
}
