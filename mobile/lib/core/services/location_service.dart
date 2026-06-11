// =========================================================================
// نظام HR Pro v6.0 - خدمة التتبع الجغرافي والـ Geofencing (Location Service)
// =========================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'supabase_service.dart';

/// خدمة للتحكم في التتبع الجغرافي للموظفين في الخلفية والتحقق من السياج الجغرافي وكشف التزييف
class LocationService {
  static Timer? _trackingTimer;
  static bool _isTracking = false;
  
  // الاحتفاظ بالدولة الأخيرة لكل منطقة جيوفينس لمنع تكرار تسجيل المخالفات المتتالية
  // key: zoneId, value: isInside
  static final Map<String, bool> _lastGeofenceStates = {};

  /// بدء تتبع الموقع الجغرافي الذكي بناءً على جداول تتبع الموظف
  static void startTracking() {
    if (_isTracking) return;
    _isTracking = true;

    // تشغيل فحص دوري كل دقيقة واحدة
    _trackingTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      await _checkAndTrack();
    });
    
    debugPrint('تم تشغيل مؤقت خدمة التتبع الجغرافي بنجاح.');
  }

  /// إيقاف التتبع الجغرافي
  static void stopTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _isTracking = false;
    _lastGeofenceStates.clear();
    debugPrint('تم إيقاف خدمة التتبع الجغرافي.');
  }

  /// التحقق من جدول تتبع الموظف الحالي وجلب الموقع عند الحاجة
  static Future<void> _checkAndTrack() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      // 1. جلب جدول التتبع المخصص للموظف
      final trackingSchedule = await SupabaseService.client
          .from('tracking_schedules')
          .select()
          .eq('employee_id', user.id)
          .maybeSingle();

      if (trackingSchedule == null) {
        // لا يوجد جدول تتبع محدد للموظف حالياً
        return;
      }

      // 2. التحقق من صلاحية اليوم والوقت الحاليين للتتبع
      final now = DateTime.now();
      
      // مطابقة اليوم (Sunday = 0, Monday = 1, ..., Saturday = 6)
      final int pgDay = now.weekday % 7; 
      final List<dynamic> trackingDays = trackingSchedule['tracking_days'] ?? [];
      
      if (!trackingDays.contains(pgDay)) {
        // اليوم ليس من أيام التتبع المحددة للموظف
        return;
      }

      // مطابقة الوقت الحالي مع start_time و end_time
      final String startTimeStr = trackingSchedule['start_time'] ?? '08:00:00';
      final String endTimeStr = trackingSchedule['end_time'] ?? '17:00:00';

      if (!_isCurrentTimeBetween(startTimeStr, endTimeStr)) {
        // الوقت الحالي خارج أوقات التتبع الجغرافي
        return;
      }

      // 3. التحقق من الفاصل الزمني (Interval) لمنع الإفراط في الاستهلاك
      final int intervalMinutes = trackingSchedule['interval_minutes'] ?? 5;
      final int currentMinute = now.minute;

      // نجلب فقط عندما يتطابق الوقت مع الفاصل الزمني (مثلاً كل 5 دقائق)
      if (currentMinute % intervalMinutes != 0) {
        return;
      }

      // 4. الحصول على إحداثيات الموقع الحالي بدقة متوسطة وموفرة للطاقة
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 10,
          ),
        ).timeout(const Duration(seconds: 10));
      } catch (e) {
        // Fallback to last known position if current position times out or fails
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        debugPrint('تعذر جلب الموقع الفعلي أو السابق لتتبع الخلفية.');
        return;
      }

      // 5. كشف ومكافحة تزييف الموقع الجغرافي (Mock GPS Detection)
      if (position.isMocked) {
        await _recordMockGpsAttempt(user.id, position);
        return;
      }

      // 6. تسجيل إحداثيات التتبع الفعلي في جدول location_tracking
      await SupabaseService.client.from('location_tracking').insert({
        'employee_id': user.id,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'battery_level': 100, // يمكن جلب البطارية عند الرغبة
        'is_moving': position.speed > 0.5,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      // 7. مطابقة إحداثيات الموقع الجغرافي مع السياج الجغرافي (Geofencing Zones) للموظف
      await _verifyGeofences(user.id, position);

    } catch (e) {
      debugPrint('خطأ في معالجة تتبع الموقع: $e');
    }
  }

  /// التحقق من وقوع الوقت الحالي بين وقت البدء والنهاية
  static bool _isCurrentTimeBetween(String startStr, String endStr) {
    final now = DateTime.now();
    final startParts = startStr.split(':');
    final endParts = endStr.split(':');

    if (startParts.length < 2 || endParts.length < 2) return false;

    final start = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(startParts[0]),
      int.parse(startParts[1]),
    );

    var end = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(endParts[0]),
      int.parse(endParts[1]),
    );

    // إذا كان وقت الانتهاء في اليوم التالي
    if (end.isBefore(start)) {
      end = end.add(const Duration(days: 1));
    }

    return now.isAfter(start) && now.isBefore(end);
  }

  /// تسجيل محاولات التزييف الفوري وإرسال إشعارات
  static Future<void> _recordMockGpsAttempt(String employeeId, Position position) async {
    try {
      // 1. تسجيل المحاولة الخبيثة في mock_gps_attempts
      await SupabaseService.client.from('mock_gps_attempts').insert({
        'employee_id': employeeId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'app_used': 'تطبيق تزييف موقع مكتشف في الخلفية',
      });

      // 2. إرسال إشعار فوري في لوحة الإشعارات
      await SupabaseService.client.from('notifications').insert({
        'employee_id': employeeId,
        'title': 'إنذار أمني: محاولة تزييف موقع 🚨',
        'body': 'تم رصد محاولة تشغيل موقع وهمي في الخلفية لتسجيل الحضور والتتبع الجغرافي. تم تدوين المخالفة وحظر التتبع مؤقتاً.',
        'type': 'system',
      });
      
      debugPrint('🚨 تم كشف وتوثيق محاولة تزييف موقع جغرافي للموظف: $employeeId');
    } catch (e) {
      debugPrint('خطأ في تسجيل خرق تزييف الموقع: $e');
    }
  }

  /// التحقق من مناطق الجيوفينس ومطابقة الإحداثيات للموظف
  static Future<void> _verifyGeofences(String employeeId, Position position) async {
    try {
      // 1. جلب التعيينات والمناطق المخصصة للموظف
      final assignments = await SupabaseService.client
          .from('employee_geofence_assignments')
          .select('zone_id, geofence_zones(*)')
          .eq('employee_id', employeeId);

      if (assignments.isEmpty) return;

      final currentLatLng = LatLng(position.latitude, position.longitude);

      for (var assignment in assignments) {
        final zone = assignment['geofence_zones'];
        if (zone == null) continue;

        final String zoneId = zone['id'];
        final String zoneName = zone['name'] ?? 'منطقة مجهولة';
        
        // جلب الإحداثيات المرسومة للمضلع الجغرافي
        final dynamic coordsRaw = zone['coordinates'];
        List<LatLng> polygon = [];

        try {
          List<dynamic> coordsList;
          if (coordsRaw is String) {
            coordsList = jsonDecode(coordsRaw);
          } else {
            coordsList = coordsRaw as List<dynamic>;
          }

          polygon = coordsList.map((item) {
            final lat = (item['lat'] as num).toDouble();
            final lng = (item['lng'] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();

        } catch (e) {
          debugPrint('خطأ في فك تشفير إحداثيات الجيوفينس للمنطقة $zoneName: $e');
          continue;
        }

        if (polygon.isEmpty) continue;

        // التحقق مما إذا كان الإحداثي الحالي يقع داخل المضلع
        final bool isCurrentlyInside = _isPointInPolygon(currentLatLng, polygon);
        final bool? lastState = _lastGeofenceStates[zoneId];

        // في حال تغيرت الحالة، نسجل مخالفة
        if (lastState != null && lastState != isCurrentlyInside) {
          final String violationType = isCurrentlyInside ? 'entry' : 'exit';
          final String violationName = isCurrentlyInside ? 'دخول' : 'خروج';

          // 1. تسجيل المخالفة في geofence_violations
          await SupabaseService.client.from('geofence_violations').insert({
            'employee_id': employeeId,
            'zone_id': zoneId,
            'violation_type': violationType,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });

          // 2. إشعار الموظف والمدراء عبر جدول الإشعارات
          await SupabaseService.client.from('notifications').insert({
            'employee_id': employeeId,
            'title': 'تنبيه سياج جغرافي 📍',
            'body': 'تم رصد حالة ($violationName) من حدود منطقة السياج الجغرافي المعينة لك: ($zoneName).',
            'type': 'system',
          });

          debugPrint('📍 مخالفة جيوفينس: تم رصد $violationName للموظف من منطقة $zoneName');
        }

        // تحديث الحالة الأخيرة
        _lastGeofenceStates[zoneId] = isCurrentlyInside;
      }
    } catch (e) {
      debugPrint('خطأ أثناء التحقق من مخالفات السياج الجغرافي: $e');
    }
  }

  /// خوارزمية Ray-Casting للتحقق من وقوع إحداثي داخل مضلع جغرافي
  static bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int i, j = polygon.length - 1;
    bool oddNodes = false;
    final double x = point.longitude;
    final double y = point.latitude;

    for (i = 0; i < polygon.length; i++) {
      final double latI = polygon[i].latitude;
      final double lngI = polygon[i].longitude;
      final double latJ = polygon[j].latitude;
      final double lngJ = polygon[j].longitude;

      if ((latI < y && latJ >= y || latJ < y && latI >= y) &&
          (lngI + (y - latI) / (latJ - latI) * (lngJ - lngI) < x)) {
        oddNodes = !oddNodes;
      }
      j = i;
    }
    return oddNodes;
  }
}
