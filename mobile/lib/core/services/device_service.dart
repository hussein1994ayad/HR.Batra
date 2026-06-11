// =========================================================================
// نظام HR Pro v6.0 - خدمة معلومات وتحديد هوية الجهاز (Device Service)
// =========================================================================

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة للتعامل مع معلومات الجهاز الحالي للحفاظ على أمان الحساب
/// وتفعيل خاصية قفل الحساب على جهاز واحد (Single-device locking).
class DeviceService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// جلب المعرف الفريد للجهاز (UUID) للتحقق من هوية الجهاز
  static Future<String> getDeviceUUID() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? uuid = prefs.getString('device_uuid');
      if (uuid == null) {
        // إذا لم يكن هناك UUID محفوظ، نقم بإنشاء واحد جديد وحفظه
        uuid = 'device_${DateTime.now().millisecondsSinceEpoch}_${(1000 + DateTime.now().microsecond).toString()}';
        await prefs.setString('device_uuid', uuid);
      }
      return uuid;
    } catch (e) {
      return 'fallback-uuid';
    }
  }

  /// جلب موديل الجهاز الحالي (مثال: Samsung SM-G998B)
  static Future<String> getDeviceModel() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.model;
      }
      return Platform.operatingSystem;
    } catch (e) {
      return 'طراز غير معروف';
    }
  }

  /// جلب نسخة نظام التشغيل الحالية
  static Future<String> getOSVersion() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return 'Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return 'iOS ${iosInfo.systemVersion}';
      }
      return Platform.operatingSystemVersion;
    } catch (e) {
      return 'نسخة نظام غير معروفة';
    }
  }
}
