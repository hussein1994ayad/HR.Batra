// =========================================================================
// نظام HR Pro v6.0 - خدمة التتبع الجغرافي والـ Geofencing (Location Service)
// =========================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'supabase_service.dart';

/// خدمة للتحكم في التتبع الجغرافي للموظفين في الخلفية والتحقق من السياج الجغرافي وكشف التزييف
class LocationService {
  static Timer? _trackingTimer;
  static bool _isTracking = false;
  
  static StreamSubscription<Position>? _positionStreamSubscription;
  static Position? _lastUploadedPosition;
  static DateTime? _lastUploadedTime;
  
  // الاحتفاظ بالدولة الأخيرة لكل منطقة جيوفينس لمنع تكرار تسجيل المخالفات المتتالية
  // key: zoneId, value: isInside
  static final Map<String, bool> _lastGeofenceStates = {};

  /// بدء تتبع الموقع الجغرافي الذكي بناءً على جداول تتبع الموظف
  static void startTracking() {
    if (_isTracking) return;
    _isTracking = true;

    // تشغيل فحص دوري كل دقيقة للتحقق من حالة دوام الموظف وبدء/إيقاف التتبع الفعلي
    _trackingTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      await _evaluateTrackingState();
    });
    
    // تشغيل التقييم الأولي فوراً عند فتح التطبيق
    _evaluateTrackingState();
    
    debugPrint('تم تشغيل مؤقت خدمة التتبع الجغرافي الذكي بنجاح.');
  }

  /// إيقاف التتبع الجغرافي بالكامل وإلغاء كافة الاشتراكات
  static void stopTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _isTracking = false;
    _stopLocationUpdates();
    _lastGeofenceStates.clear();
    debugPrint('تم إيقاف خدمة التتبع الجغرافي بالكامل.');
  }

  /// تقييم حالة التتبع الحالية للموظف
  static Future<void> _evaluateTrackingState() async {
    final user = SupabaseService.currentUser;
    if (user == null) {
      _stopLocationUpdates();
      return;
    }

    final bool shouldTrack = await _shouldTrackLocation(user.id);
    if (shouldTrack) {
      if (_positionStreamSubscription == null) {
        _startLocationUpdates(user.id);
      }
    } else {
      if (_positionStreamSubscription != null) {
        _stopLocationUpdates();
      }
    }
  }

  /// التحقق من صلاحية اليوم والوقت وحالة تسجيل الدخول لتحديد ما إذا كان يجب بدء التتبع
  static Future<bool> _shouldTrackLocation(String userId) async {
    try {
      // 1. التحقق من حالة البصمة اليومية للموظف (يجب أن يكون مسجلاً حضوراً ولم يسجل انصرافاً بعد)
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final attendanceData = await SupabaseService.client
          .from('attendance')
          .select()
          .eq('employee_id', userId)
          .eq('work_date', todayStr)
          .maybeSingle();

      if (attendanceData == null) {
        // لم يبصم اليوم أبداً
        return false;
      }

      if (attendanceData['check_in_time'] == null || attendanceData['check_out_time'] != null) {
        // لم يبصم دخول أو بصم انصراف بالفعل
        return false;
      }

      // 2. جلب جدول التتبع المخصص للموظف من قاعدة البيانات
      final trackingSchedule = await SupabaseService.client
          .from('tracking_schedules')
          .select()
          .eq('employee_id', userId)
          .maybeSingle();

      // إذا لم يكن هناك جدول تتبع محدد للموظف حالياً، نتبعه طالما هو مسجل حضور (كافتراض افتراضي)
      if (trackingSchedule == null) {
        return true;
      }

      // 3. التحقق من مطابقة الأيام المسموح بها
      final now = DateTime.now();
      final int pgDay = now.weekday % 7; // Sunday = 0, Monday = 1, etc.
      final List<dynamic> trackingDays = trackingSchedule['tracking_days'] ?? [];
      
      if (!trackingDays.contains(pgDay)) {
        return false;
      }

      // 4. مطابقة الوقت الحالي مع أوقات الجدول
      final String startTimeStr = trackingSchedule['start_time'] ?? '08:00:00';
      final String endTimeStr = trackingSchedule['end_time'] ?? '17:00:00';

      return _isCurrentTimeBetween(startTimeStr, endTimeStr);
    } catch (e) {
      debugPrint('خطأ أثناء التحقق من صلاحية وقت التتبع للموظف: $e');
      return false;
    }
  }

  /// بدء الاستماع لتدفق إحداثيات الموقع الفعلي في الخلفية
  static void _startLocationUpdates(String userId) {
    debugPrint('بدء تشغيل تدفق التتبع الجغرافي للموظف: $userId');

    // إعدادات الموقع بناءً على نظام التشغيل لضمان الامتثال لمتطلبات المتاجر
    LocationSettings locationSettings;

    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 10),
        // تخصيص إشعار الخدمة ليكون غير ملفت ويظهر كمزامنة عادية للبيانات
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'HR Pro: المزامنة السحابية نشطة',
          notificationText: 'يتم تحديث البيانات وجدول العمل تلقائياً',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: false, // عدم إظهار الشريط الأزرق المزعج للمستخدم
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      // 1. كشف تزييف الموقع الجغرافي (Mock GPS)
      if (position.isMocked) {
        await _recordMockGpsAttempt(userId, position);
        return;
      }

      // 2. فلترة التحديثات لتقليل الاستهلاك المفرط للبطارية والسيرفر (كل 5 دقائق أو عند تحرك 50 متر)
      final now = DateTime.now();
      bool shouldUpload = false;

      if (_lastUploadedPosition == null || _lastUploadedTime == null) {
        shouldUpload = true;
      } else {
        final double distance = Geolocator.distanceBetween(
          _lastUploadedPosition!.latitude,
          _lastUploadedPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        final difference = now.difference(_lastUploadedTime!);

        if (distance >= 50 || difference >= const Duration(minutes: 5)) {
          shouldUpload = true;
        }
      }

      if (shouldUpload) {
        _lastUploadedPosition = position;
        _lastUploadedTime = now;

        try {
          await SupabaseService.client.from('location_tracking').insert({
            'employee_id': userId,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'battery_level': 100, // قيمة افتراضية للبطارية
            'is_moving': position.speed > 0.5,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          });
          debugPrint('تم تسجيل ورفع موقع جديد: (${position.latitude}, ${position.longitude})');
        } catch (e) {
          debugPrint('فشل في حفظ إحداثي التتبع بجدول المزامنة: $e');
        }
      }

      // 3. مطابقة إحداثيات الموقع الجغرافي مع السياج الجغرافي المخصص للموظف
      await _verifyGeofences(userId, position);

      // 4. تقييم سريع للحالة لإطفاء التتبع فور انتهاء أوقات العمل
      final bool stillOnDuty = await _shouldTrackLocation(userId);
      if (!stillOnDuty) {
        _stopLocationUpdates();
      }

    }, onError: (e) {
      debugPrint('حدث خطأ في استقبال تدفق بيانات الموقع: $e');
    });
  }

  /// إيقاف اشتراك الموقع الجغرافي
  static void _stopLocationUpdates() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _lastUploadedPosition = null;
    _lastUploadedTime = null;
    debugPrint('تم إيقاف اشتراك تدفق الموقع الجغرافي وإلغاء إشعار الخدمة.');
  }

  /// التحقق من وقوع الوقت الحالي بين وقت البدء والنهاية
  static bool _isCurrentTimeBetween(String startStr, String endStr) {
    final now = DateTime.now();
    final startParts = startStr.split(':');
    final endParts = endStr.split(':');

    if (startParts.length < 2 || endParts.length < 2) return false;

    final int startHour = int.tryParse(startParts[0]) ?? 8;
    final int startMinute = int.tryParse(startParts[1]) ?? 0;
    final int endHour = int.tryParse(endParts[0]) ?? 17;
    final int endMinute = int.tryParse(endParts[1]) ?? 0;

    final start = DateTime(
      now.year,
      now.month,
      now.day,
      startHour,
      startMinute,
    );

    var end = DateTime(
      now.year,
      now.month,
      now.day,
      endHour,
      endMinute,
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
