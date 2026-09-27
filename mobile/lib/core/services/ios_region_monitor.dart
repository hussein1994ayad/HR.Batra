// =========================================================================
// HR Pro v6.0 - iOS Region Monitor Bridge
// =========================================================================
// جسر Dart ⇄ Swift يتحكم بـ LocationMonitorIOS.
// على Android: هذي الطبقة NOP.
//
// كيف يعمل الحل الكامل:
//   1. عند تسجيل الدخول (login)       → configure() لتخزين مفاتيح Supabase
//   2. تلقائياً أو عند login/check-in → startMonitoring([فروع])
//   3. عند check-in                    → setCheckedIn(true)
//                                          → iOS يبدي المسار المستمر
//                                          → عند دخول فرع، يوقف المسار
//                                          → عند خروج فرع، يفعّل المسار
//   4. عند check-out                   → setCheckedIn(false)
//                                          → المسار المستمر يتوقف
//                                          → Region Monitoring يبقى للأمان
//   5. عند logout                       → stopMonitoring() (يوقف كل شي)
// =========================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'supabase_service.dart';

class IosRegionMonitor {
  IosRegionMonitor._();

  static const _channel = MethodChannel('com.batra.hrpro/ios_location');

  static bool get isSupported => Platform.isIOS;

  static Future<void> configure({
    required String supabaseUrl,
    required String supabaseAnonKey,
    required String employeeId,
    String? accessToken,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('configure', {
        'supabaseUrl': supabaseUrl,
        'supabaseAnonKey': supabaseAnonKey,
        'employeeId': employeeId,
        'accessToken': accessToken ?? '',
      });
    } catch (e) {
      debugPrint('IosRegionMonitor.configure error: $e');
    }
  }

  static Future<void> startMonitoring(
      List<Map<String, dynamic>> branches) async {
    if (!isSupported) return;
    if (branches.isEmpty) return;
    try {
      final limited = branches.take(20).toList();
      await _channel.invokeMethod('startMonitoring', {
        'branches': limited,
      });
      debugPrint('iOS: بدأت مراقبة ${limited.length} فرع');
    } catch (e) {
      debugPrint('IosRegionMonitor.startMonitoring error: $e');
    }
  }

  /// إبلاغ الطبقة الأصلية بحالة check-in (يفعّل/يوقف المسار المستمر)
  static Future<void> setCheckedIn(bool checkedIn) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('setCheckedIn', {'value': checkedIn});
      debugPrint('iOS: setCheckedIn($checkedIn)');
    } catch (e) {
      debugPrint('IosRegionMonitor.setCheckedIn error: $e');
    }
  }

  /// توكن الجلسة الجديد بعد كل تجديد (صلاحيته ساعة)، حتى يرفع iOS المواقع بتوكن صالح.
  static Future<void> updateAccessToken(String token) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('updateAccessToken', {'accessToken': token});
    } catch (e) {
      debugPrint('IosRegionMonitor.updateAccessToken error: $e');
    }
  }

  /// يرفع النقاط التي حفظها iOS لأن التوكن انتهى أو الشبكة انقطعت أثناء إغلاق التطبيق.
  /// يُرفع فقط ما يخص المستخدم الحالي.
  static Future<void> uploadPendingPoints() async {
    if (!isSupported) return;
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return;
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('drainPendingPoints') ?? const [];
      final rows = [
        for (final p in raw)
          if (p is Map && p['employee_id'] == userId)
            {'employee_id': userId, 'latitude': p['latitude'], 'longitude': p['longitude'], 'timestamp': p['timestamp']},
      ];
      for (var i = 0; i < rows.length; i += 200) {
        final end = i + 200 > rows.length ? rows.length : i + 200;
        await SupabaseService.client.from('location_tracking').insert(rows.sublist(i, end));
      }
      if (rows.isNotEmpty) debugPrint('iOS: رُفعت ${rows.length} نقطة موقع محفوظة');
    } catch (e) {
      debugPrint('IosRegionMonitor.uploadPendingPoints error: $e');
    }
  }

  static Future<void> stopMonitoring() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('stopMonitoring');
      debugPrint('iOS: توقفت المراقبة تماماً');
    } catch (e) {
      debugPrint('IosRegionMonitor.stopMonitoring error: $e');
    }
  }

  static Future<void> configureAndStartFromSupabase({
    required String supabaseUrl,
    required String supabaseAnonKey,
    required String employeeId,
    String? accessToken,
  }) async {
    if (!isSupported) return;
    try {
      await configure(
        supabaseUrl: supabaseUrl,
        supabaseAnonKey: supabaseAnonKey,
        employeeId: employeeId,
        accessToken: accessToken,
      );

      final data = await SupabaseService.client
          .from('branches')
          .select('id, name, latitude, longitude, radius_meters');

      final branches = <Map<String, dynamic>>[];
      for (final row in data as List) {
        if (row is! Map) continue;
        final id = row['id']?.toString();
        final lat = (row['latitude'] as num?)?.toDouble();
        final lng = (row['longitude'] as num?)?.toDouble();
        if (id == null || lat == null || lng == null) continue;
        branches.add({
          'id': id,
          'name': row['name']?.toString() ?? 'فرع',
          'lat': lat,
          'lng': lng,
          'radius': (row['radius_meters'] as num?)?.toDouble() ?? 100.0,
        });
      }

      if (branches.isNotEmpty) {
        await startMonitoring(branches);
      }
    } catch (e) {
      debugPrint('IosRegionMonitor.configureAndStartFromSupabase error: $e');
    }
  }
}
