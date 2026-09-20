// =========================================================================
// HR Pro v6.0 - iOS Region Monitor Bridge
// =========================================================================
// جسر Dart ⇄ Swift يتحكم بـ Region Monitoring على iOS.
// على Android: هذي الطبقة NOP — نستخدم flutter_background_service بدلاً منها.
//
// كيف يشتغل الحل الكامل على iOS:
//   1. الموظف يعمل check-in                → configure() ثم startMonitoring([فروع])
//   2. iOS يوقظ التطبيق عند دخول/خروج فرع  → Swift يرفع لـ Supabase مباشرة
//   3. الموظف يعمل check-out              → stopMonitoring()
//   4. أوقات الدوام انتهت                → auto-stop عبر schedule check
//
// حدود Apple: 20 منطقة كحد أقصى في نفس الوقت.
// =========================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'supabase_service.dart';

class IosRegionMonitor {
  IosRegionMonitor._();

  static const _channel = MethodChannel('com.batra.hrpro/ios_location');

  /// هل الطبقة هذه فعّالة؟ (iOS فقط)
  static bool get isSupported => Platform.isIOS;

  /// إعداد Supabase URL + anon key + employee id + optional access token.
  /// يُستدعى مرة واحدة عند تسجيل الدخول.
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
        'accessToken': accessToken ?? supabaseAnonKey,
      });
    } catch (e) {
      debugPrint('IosRegionMonitor.configure error: $e');
    }
  }

  /// بدء مراقبة قائمة الفروع (max 20 من Apple).
  /// كل branch: {id, name, lat, lng, radius}
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

  /// إيقاف كل المراقبة — يُستدعى عند check-out أو انتهاء الدوام.
  static Future<void> stopMonitoring() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('stopMonitoring');
      debugPrint('iOS: توقفت المراقبة الجغرافية');
    } catch (e) {
      debugPrint('IosRegionMonitor.stopMonitoring error: $e');
    }
  }

  /// راحة: جلب فروع من Supabase وتشغيل المراقبة عليها.
  /// يُستدعى من LocationService.startTracking() على iOS.
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
