// =========================================================================
// نظام HR Pro v6.0 - خدمة معلومات وتحديد هوية الجهاز (Device Service)
// =========================================================================

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// خدمة للتعامل مع معلومات الجهاز الحالي للحفاظ على أمان الحساب
/// وتفعيل خاصية قفل الحساب على جهاز واحد (Single-device locking).
class DeviceService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const MethodChannel _channel = MethodChannel('com.batra.hrpro/device');

  /// المفتاح القديم: معرّف عشوائي في SharedPreferences يضيع عند حذف التطبيق.
  static const String _kLegacyUuidKey = 'device_uuid';

  static String? _cachedId;

  /// معرّف ثابت للجهاز يبقى بعد حذف التطبيق وإعادة تثبيته:
  /// Android → ANDROID_ID، iOS → UUID محفوظ في Keychain.
  /// إذا فشلت القناة الأصلية نرجع للمعرّف المحفوظ محلياً.
  static Future<String> getDeviceUUID() async {
    if (_cachedId != null) return _cachedId!;
    try {
      final id = await _channel.invokeMethod<String>('getStableDeviceId');
      if (id != null && id.isNotEmpty) return _cachedId = id;
    } catch (e) {
      debugPrint('device: stable id unavailable, using local id: $e');
    }
    return _cachedId = await _localFallbackId();
  }

  /// المعرّف القديم (إن وُجد) لترحيل قفل الأجهزة الحالية إلى المعرّف الثابت.
  static Future<String?> getLegacyDeviceUUID() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kLegacyUuidKey);
    } catch (_) {
      return null;
    }
  }

  static Future<String> _localFallbackId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kLegacyUuidKey);
    if (existing != null) return existing;
    final id = 'device_${const Uuid().v4()}';
    await prefs.setString(_kLegacyUuidKey, id);
    return id;
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
