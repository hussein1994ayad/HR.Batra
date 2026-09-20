// =========================================================================
// نظام HR Pro v6.0 - خدمة التتبع الجغرافي والـ Geofencing (Location Service)
// =========================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../constants/constants.dart';
import 'ios_region_monitor.dart';
import 'supabase_service.dart';

/// خدمة للتحكم في التتبع الجغرافي للموظفين في الخلفية والتحقق من السياج الجغرافي وكشف التزييف
class LocationService {
  static bool _isTracking = false;
  static bool get isTracking => _isTracking;

  static StreamSubscription<Position>? _positionStreamSubscription;
  static Position? _lastUploadedPosition;
  static DateTime? _lastUploadedTime;
  static List<dynamic>? _cachedGeofenceZones;
  static DateTime? _lastGeofencesFetchTime;
  static String? _activeEmployeeId;

  // الاحتفاظ بالحالة الأخيرة لكل منطقة جيوفينس لمنع تكرار تسجيل المخالفات المتتالية
  static final Map<String, bool> _lastGeofenceStates = {};

  /// تهيئة وتأسيس خدمة الخلفية لتتبع الموقع
  static Future<void> initializeBackgroundService() async {
    try {
      final service = FlutterBackgroundService();
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: 'hrpro_sync_v2',
          initialNotificationTitle: 'HR Pro',
          initialNotificationContent: 'تحديث تلقائي...',
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onForeground,
          onBackground: onIosBackground,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ تعذر تكوين خدمة الخلفية: $e');
    }
  }

  @pragma('vm:entry-point')
  static void onForeground(ServiceInstance service) {
    debugPrint('Background Service: iOS Foreground state.');
  }

  @pragma('vm:entry-point')
  static bool onIosBackground(ServiceInstance service) {
    debugPrint('Background Service: iOS Background state.');
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      if (!SupabaseService.isAuthenticated) {
        await SupabaseService.init();
      }
    } catch (e) {
      debugPrint('Background Service Isolate: Supabase init check: $e');
    }

    try {
      if (service is AndroidServiceInstance) {
        service.setAsForegroundService();
      }

      service.on('stopService').listen((event) {
        try {
          service.stopSelf();
        } catch (_) {}
      });

      // تشغيل فحص دوري كل دقيقتين للتحقق من حالة دوام الموظف ومزامنة المسار
      Timer.periodic(const Duration(minutes: 2), (timer) async {
        try {
          await _evaluateTrackingStateInService(service);
        } catch (e) {
          debugPrint('⚠️ خطأ في دورة فحص التتبع بالخلفية: $e');
        }
      });

      await _evaluateTrackingStateInService(service);
    } catch (e) {
      debugPrint('⚠️ خطأ في تهيئة onStart لخدمة الخلفية: $e');
    }
  }

  /// طلب صلاحيات الموقع الكافية للتتبع الدقيق
  static Future<bool> requestLocationPermissions() async {
    try {
      // 1. التحقق من تفعيل خدمة GPS في الجهاز
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('⚠️ خدمة GPS معطلة في الجهاز');
      }

      // 2. طلب الصلاحية العادية أولاً (In Use)
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
        if (!status.isGranted) {
          debugPrint('⚠️ صلاحية الموقع العادية مرفوضة.');
          return false;
        }
      }

      // 3. طلب صلاحية الخلفية (Always Allow) للأندرويد والآيفون إذا أمكن
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          var alwaysStatus = await Permission.locationAlways.status;
          if (!alwaysStatus.isGranted) {
            debugPrint('📍 طلب صلاحية الموقع بالخلفية (Always Allow)...');
            await Permission.locationAlways.request();
          }
        } catch (_) {}
      }
      return true;
    } catch (e) {
      debugPrint('⚠️ خطأ في طلب صلاحيات الموقع: $e');
      return false;
    }
  }

  /// بدء خدمة التتبع الجغرافي للموظف فوراً
  static Future<void> startTracking({String? employeeId}) async {
    try {
      final userId = employeeId ?? SupabaseService.currentUser?.id ?? _activeEmployeeId;
      if (userId == null) {
        debugPrint('⚠️ لم يتم العثور على معرف الموظف لبدء التتبع');
        return;
      }

      _activeEmployeeId = userId;

      final hasPermission = await requestLocationPermissions();
      if (!hasPermission) {
        debugPrint('⚠️ تم إلغاء بدء خدمة التتبع لعدم توفر الصلاحيات المطلوبة.');
        return;
      }

      _isTracking = true;

      // حفظ حالة الدوام والتتبع محلياً للعمل في وضع الأوفلاين
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      await _saveTrackingStateOffline(
        hasCheckedIn: true,
        checkedInDate: todayStr,
        userId: userId,
      );

      // مزامنة أي نقاط سابقة مخزنة محلياً
      unawaited(_syncOfflineLocations());

      // طلب استثناء قيود البطارية للأندرويد
      if (Platform.isAndroid) {
        _requestBatteryOptimizationExemption();
      }

      // 1. تشغيل التدفق المباشر للموقع في التطبيق فوراً
      if (_positionStreamSubscription == null) {
        _startLocationUpdates(userId);
      }

      // 2. التقاط ورفع موقع أولي فوري للتسجيل اللحظي
      unawaited(_captureInstantLocation(userId));

      // 3. تشغيل خدمة الخلفية للأندرويد والآيفون
      try {
        final service = FlutterBackgroundService();
        final isRunning = await service.isRunning();
        if (!isRunning) {
          await service.startService();
        }
      } catch (e) {
        debugPrint('⚠️ تعذر تشغيل BackgroundService: $e');
      }

      // على iOS: فعّل Region Monitoring لتحمّل حالة التطبيق المقفل
      if (Platform.isIOS) {
        try {
          final session = SupabaseService.client.auth.currentSession;
          await IosRegionMonitor.configureAndStartFromSupabase(
            supabaseUrl: AppConstants.supabaseUrl,
            supabaseAnonKey: AppConstants.supabaseAnonKey,
            employeeId: userId,
            accessToken: session?.accessToken,
          );
          // فعّل مسار مستمر (المسار الكامل) — Swift يوقفه تلقائياً داخل الفروع
          await IosRegionMonitor.setCheckedIn(true);
        } catch (e) {
          debugPrint('⚠️ فشل تهيئة iOS Region Monitor: $e');
        }
      }

      debugPrint('✅ تم تفعيل وتشغيل نظام التتبع الجغرافي بنجاح للموظف: $userId');
    } catch (e) {
      debugPrint('⚠️ خطأ أثناء بدء التتبع الجغرافي: $e');
    }
  }

  /// إيقاف التتبع الجغرافي بالكامل عند الانصراف
  static Future<void> stopTracking() async {
    // Check-out: نخبر Swift إن الموظف طلع، فيتوقف المسار المستمر
    // (نبقي Region Monitoring نشط للأمان — دخول فرع بالغلط يُسجَّل)
    try {
      await IosRegionMonitor.setCheckedIn(false);
    } catch (_) {}

    try {
      final service = FlutterBackgroundService();
      service.invoke('stopService');
    } catch (_) {}

    _isTracking = false;
    _activeEmployeeId = null;
    _stopLocationUpdates();
    _lastGeofenceStates.clear();

    // حفظ انتهاء الدوام محلياً
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    await _saveTrackingStateOffline(
      hasCheckedIn: false,
      checkedInDate: todayStr,
      userId: null,
    );

    debugPrint('🛑 تم إيقاف خدمة التتبع الجغرافي بالكامل.');
  }

  /// تسجيل موقع لحظي فوري (يُستدعى عند البصمة)
  static Future<void> recordInstantLocation({
    required String employeeId,
    required double latitude,
    required double longitude,
    bool isMoving = false,
  }) async {
    final locationData = {
      'employee_id': employeeId,
      'latitude': latitude,
      'longitude': longitude,
      'battery_level': 100,
      'is_moving': isMoving,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await SupabaseService.client.from('location_tracking').insert(locationData);
      debugPrint('📍 تم تسجيل نقطة موقع فورية: ($latitude, $longitude)');
      unawaited(_syncOfflineLocations());
    } catch (e) {
      debugPrint('⚠️ تعذر رفع الموقع الفوري، سيتم حفظه محلياً أوفلاين: $e');
      await _cacheLocationOffline(locationData);
    }
  }

  /// التقاط الموقع الحالي فوراً ورفعه
  static Future<void> _captureInstantLocation(String userId) async {
    try {
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (position != null) {
        _lastUploadedPosition = position;
        _lastUploadedTime = DateTime.now();
        await recordInstantLocation(
          employeeId: userId,
          latitude: position.latitude,
          longitude: position.longitude,
          isMoving: position.speed > 0.5,
        );
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في التقاط الموقع الأولي: $e');
    }
  }

  /// تقييم حالة التتبع الحالية للموظف داخل الخدمة
  static Future<void> _evaluateTrackingStateInService(ServiceInstance service) async {
    String? userId = _activeEmployeeId ?? SupabaseService.currentUser?.id;

    if (userId == null) {
      final cached = await _getTrackingStateOffline();
      userId = cached?['user_id'] as String?;
    }

    if (userId == null) {
      _stopLocationUpdates();
      return;
    }

    final bool shouldTrack = await _shouldTrackLocation(userId);
    if (shouldTrack) {
      if (_positionStreamSubscription == null) {
        _startLocationUpdates(userId);
      }
    } else {
      if (_positionStreamSubscription != null) {
        _stopLocationUpdates();
      }
      // على iOS: نتوقف عن المسار المستمر لكن نبقي Region Monitoring نشط
      if (Platform.isIOS) {
        try {
          await IosRegionMonitor.setCheckedIn(false);
        } catch (_) {}
      }
    }

    // تحديث إشعار الخدمة الخلفية للأندرويد بشكل تفاعلي
    if (service is AndroidServiceInstance) {
      if (shouldTrack) {
        service.setForegroundNotificationInfo(
          title: 'HR Pro',
          content: 'تحديث تلقائي...',
        );
      } else {
        service.setForegroundNotificationInfo(
          title: 'HR Pro',
          content: 'تحديث تلقائي...',
        );
      }
    }
  }

  /// التحقق من صلاحية اليوم والوقت وحالة تسجيل الدخول لتحديد ما إذا كان يجب استمرار التتبع
  static Future<bool> _shouldTrackLocation(String userId) async {
    final todayStr = DateTime.now().toIso8601String().split('T')[0];

    // 1. محاولة قراءة الحالة المخزنة محلياً
    final cached = await _getTrackingStateOffline();
    if (cached != null && cached['checked_in_date'] == todayStr) {
      final updatedAtStr = cached['updated_at'] as String?;
      if (updatedAtStr != null) {
        final updatedAt = DateTime.tryParse(updatedAtStr);
        if (updatedAt != null) {
          final difference = DateTime.now().difference(updatedAt.toLocal());
          if (difference < const Duration(minutes: 10)) {
            return _evaluateStateFromCache(cached);
          }
        }
      }
    }

    // 2. إذا مضى وقت أو لم يوجد كاش، نحاول التحديث من السيرفر
    try {
      final attendanceData = await SupabaseService.client
          .from('attendance')
          .select()
          .eq('employee_id', userId)
          .eq('work_date', todayStr)
          .maybeSingle();

      bool hasCheckedIn = false;
      if (attendanceData != null) {
        if (attendanceData['check_in_time'] != null && attendanceData['check_out_time'] == null) {
          hasCheckedIn = true;
        }
      }

      dynamic trackingSchedule = await SupabaseService.client
          .from('tracking_schedules')
          .select()
          .eq('employee_id', userId)
          .maybeSingle();

      // Fallback: لو ما فيه tracking_schedule، استخدم work_schedule (الأوقات الرسمية للدوام)
      if (trackingSchedule == null) {
        final workSchedule = await SupabaseService.client
            .from('work_schedules')
            .select('check_in_time, check_out_time, work_days')
            .eq('employee_id', userId)
            .maybeSingle();
        if (workSchedule != null) {
          trackingSchedule = {
            'start_time': workSchedule['check_in_time'],
            'end_time': workSchedule['check_out_time'],
            'tracking_days': workSchedule['work_days'],
          };
        }
      }

      await _saveTrackingStateOffline(
        hasCheckedIn: hasCheckedIn,
        checkedInDate: todayStr,
        userId: userId,
        schedule: trackingSchedule,
      );

      if (!hasCheckedIn) return false;
      if (trackingSchedule == null) return true;

      return _evaluateSchedule(trackingSchedule);
    } catch (e) {
      debugPrint('⚠️ وضع الأوفلاين نشط، الاعتماد على الحالة المحلية: $e');
      if (cached != null && cached['checked_in_date'] == todayStr) {
        return _evaluateStateFromCache(cached);
      }
      // إذا كان الموظف مسجلاً في الجلسة الحالية نعتبره نشطاً
      return _isTracking;
    }
  }

  static bool _evaluateStateFromCache(Map<String, dynamic> cached) {
    final bool hasCheckedIn = cached['has_checked_in'] ?? false;
    if (!hasCheckedIn) return false;

    final schedule = cached['schedule'] as Map<String, dynamic>?;
    if (schedule == null) return true;

    return _evaluateSchedule(schedule);
  }

  static bool _evaluateSchedule(Map<String, dynamic> schedule) {
    final now = DateTime.now();
    final int pgDay = now.weekday % 7; // Sunday = 0, Monday = 1, etc.
    final List<dynamic> trackingDays = schedule['tracking_days'] ?? [];

    if (trackingDays.isNotEmpty && !trackingDays.contains(pgDay)) {
      return false;
    }

    final String startTimeStr = schedule['start_time'] ?? '08:00:00';
    final String endTimeStr = schedule['end_time'] ?? '18:00:00';

    return _isCurrentTimeBetween(startTimeStr, endTimeStr);
  }

  /// بدء الاستماع لتدفق إحداثيات الموقع الفعلي في الخلفية والواجهة
  static void _startLocationUpdates(String userId) {
    debugPrint('🚀 بدء تشغيل تدفق التتبع الجغرافي الحي للموظف: $userId');

    // إعدادات الموقع للأندرويد والآيفون مع الامتثال الصارم لسياسات آبل
    LocationSettings locationSettings;

    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20, // تحديث كل 20 متر
        intervalDuration: const Duration(seconds: 15),
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        allowBackgroundLocationUpdates: true,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true, // مؤشر أزرق شفاف أثناء فترة الدوام امتثالاً لآبل
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      );
    }

    try {
      _positionStreamSubscription?.cancel();
    } catch (_) {}

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      try {
        // 1. كشف تزييف الموقع الجغرافي (Mock GPS)
        if (position.isMocked) {
          await _recordMockGpsAttempt(userId, position);
          return;
        }

        // 2. تصفية النقاط غير الدقيقة (دقة ضعيفة تتجاوز 100 متر)
        if (position.accuracy > 100.0) {
          debugPrint('⚠️ تم تجاهل نقطة موقع ذات دقة منخفضة: ${position.accuracy}m');
          return;
        }

        // 3. فلترة التحديثات: رفع عند التحرك >= 25 متر أو مرور دقيقتين أثناء الحركة أو 5 دقائق عند الثبات
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
          final bool isMoving = position.speed > 0.6;

          if (distance >= 25 || (isMoving && difference >= const Duration(minutes: 2)) || difference >= const Duration(minutes: 5)) {
            shouldUpload = true;
          }
        }

        if (shouldUpload) {
          _lastUploadedPosition = position;
          _lastUploadedTime = now;

          final locationData = {
            'employee_id': userId,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'battery_level': 100,
            'is_moving': position.speed > 0.6,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          };

          try {
            await SupabaseService.client.from('location_tracking').insert(locationData);
            debugPrint('📍 تم رفع نقطة تتبع حية للسيرفر: (${position.latitude}, ${position.longitude})');
            unawaited(_syncOfflineLocations());
          } catch (e) {
            debugPrint('💾 وضع أوفلاين: تعذر الاتصال، تم تخزين النقطة محلياً: $e');
            await _cacheLocationOffline(locationData);
          }
        }

        // 4. مطابقة إحداثيات الموقع مع السياج الجغرافي
        await _verifyGeofences(userId, position);
      } catch (e, stack) {
        debugPrint('⚠️ خطأ داخل مستمع الموقع: $e\n$stack');
      }
    }, onError: (e) {
      debugPrint('⚠️ خطأ في استقبال تدفق بيانات الموقع: $e');
    });
  }

  /// إيقاف اشتراك الموقع الجغرافي
  static void _stopLocationUpdates() {
    try {
      _positionStreamSubscription?.cancel();
    } catch (_) {}
    _positionStreamSubscription = null;
    _lastUploadedPosition = null;
    _lastUploadedTime = null;
    debugPrint('تم إيقاف تدفق الموقع الجغرافي.');
  }

  /// التحقق من وقوع الوقت الحالي بين وقت البدء والنهاية
  static bool _isCurrentTimeBetween(String startStr, String endStr) {
    try {
      final now = DateTime.now();
      final startParts = startStr.split(':');
      final endParts = endStr.split(':');

      if (startParts.length < 2 || endParts.length < 2) return false;

      final int startHour = int.tryParse(startParts[0]) ?? 8;
      final int startMinute = int.tryParse(startParts[1]) ?? 0;
      final int endHour = int.tryParse(endParts[0]) ?? 18;
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

      if (end.isBefore(start)) {
        end = end.add(const Duration(days: 1));
      }

      return now.isAfter(start) && now.isBefore(end);
    } catch (_) {
      return false;
    }
  }

  /// تسجيل محاولات التزييف الفوري وإرسال إشعارات
  static Future<void> _recordMockGpsAttempt(String employeeId, Position position) async {
    try {
      await SupabaseService.client.from('mock_gps_attempts').insert({
        'employee_id': employeeId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'app_used': 'تطبيق تزييف موقع مكتشف',
      });

      await SupabaseService.client.from('notifications').insert({
        'employee_id': employeeId,
        'title': 'إنذار أمني: محاولة تزييف موقع 🚨',
        'body': 'تم رصد محاولة تشغيل موقع وهمي لتسجيل الحضور والتتبع الجغرافي. تم تدوين المخالفة وحظر التتبع مؤقتاً.',
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
      final now = DateTime.now();

      if (_cachedGeofenceZones == null ||
          _lastGeofencesFetchTime == null ||
          now.difference(_lastGeofencesFetchTime!) > const Duration(minutes: 15)) {
        try {
          final assignments = await SupabaseService.client
              .from('employee_geofence_assignments')
              .select('zone_id, geofence_zones(*)')
              .eq('employee_id', employeeId);

          _cachedGeofenceZones = assignments;
          _lastGeofencesFetchTime = now;
        } catch (e) {
          debugPrint('⚠️ فشل جلب السياج الجغرافي من السيرفر: $e');
        }
      }

      if (_cachedGeofenceZones == null || _cachedGeofenceZones!.isEmpty) return;

      final currentLatLng = LatLng(position.latitude, position.longitude);

      for (var assignment in _cachedGeofenceZones!) {
        dynamic zoneRaw = assignment['geofence_zones'];
        if (zoneRaw == null) continue;

        Map<String, dynamic>? zone;
        if (zoneRaw is Map<String, dynamic>) {
          zone = zoneRaw;
        } else if (zoneRaw is List && zoneRaw.isNotEmpty && zoneRaw.first is Map) {
          zone = Map<String, dynamic>.from(zoneRaw.first);
        }

        if (zone == null) continue;

        final String? zoneId = zone['id']?.toString();
        if (zoneId == null) continue;
        final String zoneName = zone['name']?.toString() ?? 'منطقة مجهولة';

        final dynamic coordsRaw = zone['coordinates'];
        List<LatLng> polygon = [];

        try {
          List<dynamic> coordsList = [];
          if (coordsRaw is String) {
            final decoded = jsonDecode(coordsRaw);
            if (decoded is List) coordsList = decoded;
          } else if (coordsRaw is List) {
            coordsList = coordsRaw;
          }

          for (var item in coordsList) {
            if (item is Map) {
              final double lat = double.tryParse(item['lat']?.toString() ?? '0') ?? 0.0;
              final double lng = double.tryParse(item['lng']?.toString() ?? '0') ?? 0.0;
              if (lat != 0.0 && lng != 0.0) {
                polygon.add(LatLng(lat, lng));
              }
            }
          }
        } catch (e) {
          debugPrint('خطأ في فك تشفير إحداثيات الجيوفينس للمنطقة $zoneName: $e');
          continue;
        }

        if (polygon.isEmpty) continue;

        final bool isCurrentlyInside = _isPointInPolygon(currentLatLng, polygon);
        final bool? lastState = _lastGeofenceStates[zoneId];

        if (lastState != null && lastState != isCurrentlyInside) {
          final String violationType = isCurrentlyInside ? 'entry' : 'exit';
          final String violationName = isCurrentlyInside ? 'دخول' : 'خروج';

          try {
            await SupabaseService.client.from('geofence_violations').insert({
              'employee_id': employeeId,
              'zone_id': zoneId,
              'violation_type': violationType,
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            });

            await SupabaseService.client.from('notifications').insert({
              'employee_id': employeeId,
              'title': 'تنبيه سياج جغرافي 📍',
              'body': 'تم رصد حالة ($violationName) من حدود منطقة السياج الجغرافي المعينة لك: ($zoneName).',
              'type': 'system',
            });

            debugPrint('📍 مخالفة جيوفينس: تم رصد $violationName للموظف من منطقة $zoneName');
          } catch (e) {
            debugPrint('⚠️ فشل تسجيل خرق السياج الجغرافي (أوفلاين): $e');
          }
        }

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

  // ==========================================
  // مساعدات التخزين المحلي والمزامنة دون إنترنت
  // ==========================================

  static Future<File> get _cacheFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/offline_locations.json');
  }

  static Future<File> get _trackingStateFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/tracking_state.json');
  }

  /// حفظ حالة تتبع الموظف والجدول محلياً للعمل دون اتصال بالإنترنت
  static Future<void> _saveTrackingStateOffline({
    required bool hasCheckedIn,
    required String checkedInDate,
    String? userId,
    Map<String, dynamic>? schedule,
  }) async {
    try {
      final file = await _trackingStateFile;
      final data = {
        'has_checked_in': hasCheckedIn,
        'checked_in_date': checkedInDate,
        'user_id': userId,
        'schedule': schedule,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data));
      debugPrint('💾 تم حفظ حالة التتبع محلياً للعمل أوفلاين.');
    } catch (e) {
      debugPrint('❌ فشل في حفظ حالة التتبع محلياً: $e');
    }
  }

  /// قراءة حالة تتبع الموظف المخزنة محلياً
  static Future<Map<String, dynamic>?> _getTrackingStateOffline() async {
    try {
      final file = await _trackingStateFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          return jsonDecode(content) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('❌ فشل في قراءة حالة التتبع المحلية: $e');
    }
    return null;
  }

  /// تخزين الإحداثي محلياً عند فشل الاتصال بالإنترنت
  static Future<void> _cacheLocationOffline(Map<String, dynamic> locationData) async {
    try {
      final file = await _cacheFile;
      List<dynamic> cachedList = [];

      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          cachedList = jsonDecode(content) as List<dynamic>;
        }
      }

      cachedList.add(locationData);
      await file.writeAsString(jsonEncode(cachedList));
      debugPrint('📍 تم تخزين نقطة الموقع محلياً (أوفلاين). الإجمالي المخزن: ${cachedList.length}');
    } catch (e) {
      debugPrint('❌ فشل في تخزين الموقع محلياً: $e');
    }
  }

  /// محاولة مزامنة المواقع المخزنة محلياً ورفعها بحزم (batch) عند توفر الاتصال.
  /// إذا فشلت حزمة، تبقى في المخزن للمحاولة لاحقاً — بدون تكرار في السيرفر.
  static Future<void> _syncOfflineLocations() async {
    try {
      final file = await _cacheFile;
      if (!await file.exists()) return;

      final content = await file.readAsString();
      if (content.isEmpty) return;

      final List<dynamic> cachedList = jsonDecode(content) as List<dynamic>;
      if (cachedList.isEmpty) return;

      // إزالة التكرارات (بنفس timestamp + employee_id) قبل الرفع
      final seen = <String>{};
      final dedup = <Map<String, dynamic>>[];
      for (final raw in cachedList) {
        if (raw is! Map) continue;
        final key = '${raw["employee_id"]}|${raw["timestamp"]}';
        if (seen.add(key)) {
          dedup.add(Map<String, dynamic>.from(raw));
        }
      }

      const int batchSize = 50;
      final List<Map<String, dynamic>> remaining = [];
      int uploaded = 0;

      for (int i = 0; i < dedup.length; i += batchSize) {
        final end = (i + batchSize).clamp(0, dedup.length);
        final batch = dedup.sublist(i, end);
        try {
          await SupabaseService.client.from('location_tracking').insert(batch);
          uploaded += batch.length;
        } catch (e) {
          debugPrint('⚠️ فشل رفع دفعة $i-$end: $e — سنعيد المحاولة لاحقاً.');
          remaining.addAll(batch);
        }
      }

      // احتفظ بالحزم اللي فشلت للمحاولة القادمة
      if (remaining.isEmpty) {
        await file.delete();
      } else {
        await file.writeAsString(jsonEncode(remaining));
      }
      debugPrint('✅ رُفعت $uploaded نقطة، بقيت ${remaining.length} للمحاولة القادمة.');

      // مزامنة أحداث الدخول/الخروج للفروع (إن وجدت)
      await _syncOfflineBranchEvents();
    } catch (e) {
      debugPrint('⚠️ لم تكتمل مزامنة النقاط المحلية (الشبكة غير متاحة): $e');
    }
  }

  // ==========================================================================
  // Branch entry/exit detection — دخول وخروج الفروع
  // ==========================================================================
  static List<Map<String, dynamic>>? _cachedBranches;
  static DateTime? _lastBranchesFetchTime;
  static final Map<String, bool> _lastBranchInsideStates = {};

  static Future<File> get _branchEventsCacheFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/branch_events_offline.json');
  }

  /// يفحص إذا الموظف دخل أو غادر أي فرع، وينشئ إشعار مناسب.
  /// يعمل أوفلاين — يخزن الأحداث ويزامنها لاحقاً.
  static Future<void> _checkBranchEntryExit(String employeeId, Position position) async {
    try {
      final now = DateTime.now();

      // تحديث cache الفروع كل 15 دقيقة
      if (_cachedBranches == null ||
          _lastBranchesFetchTime == null ||
          now.difference(_lastBranchesFetchTime!) > const Duration(minutes: 15)) {
        try {
          final data = await SupabaseService.client
              .from('branches')
              .select('id, name, latitude, longitude, radius_meters');
          _cachedBranches = List<Map<String, dynamic>>.from(data);
          _lastBranchesFetchTime = now;
        } catch (_) {
          // نستخدم الـ cache القديم لو الشبكة غير متاحة
        }
      }

      if (_cachedBranches == null || _cachedBranches!.isEmpty) return;

      for (final branch in _cachedBranches!) {
        final id = branch['id']?.toString();
        if (id == null) continue;
        final name = branch['name']?.toString() ?? 'فرع';
        final bLat = (branch['latitude'] as num?)?.toDouble() ?? 0;
        final bLng = (branch['longitude'] as num?)?.toDouble() ?? 0;
        final radius = (branch['radius_meters'] as num?)?.toDouble() ?? 100;

        final distance = Geolocator.distanceBetween(
          position.latitude, position.longitude, bLat, bLng,
        );
        final isInside = distance <= radius;
        final wasInside = _lastBranchInsideStates[id];

        if (wasInside != null && wasInside != isInside) {
          final event = {
            'employee_id': employeeId,
            'branch_id': id,
            'branch_name': name,
            'event_type': isInside ? 'enter' : 'exit',
            'latitude': position.latitude,
            'longitude': position.longitude,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          };
          await _recordOrCacheBranchEvent(event);
        }
        _lastBranchInsideStates[id] = isInside;
      }
    } catch (e) {
      debugPrint('⚠️ فشل فحص دخول/خروج الفروع: $e');
    }
  }

  /// يحاول تسجيل حدث الدخول/الخروج مباشرة، ولو فشل يخزنه للمزامنة لاحقاً.
  static Future<void> _recordOrCacheBranchEvent(Map<String, dynamic> event) async {
    try {
      // نسجّله في notifications (يظهر للموظف وللأدمن بحسب حاجتك)
      await SupabaseService.client.from('notifications').insert({
        'employee_id': event['employee_id'],
        'title': event['event_type'] == 'enter'
            ? 'دخول فرع ${event['branch_name']}'
            : 'خروج من فرع ${event['branch_name']}',
        'body': 'تم رصد ${event['event_type'] == 'enter' ? 'دخولك إلى' : 'خروجك من'} فرع '
            '${event['branch_name']} في ${event['timestamp']}',
        'type': 'attendance',
      });
      debugPrint('📍 branch event uploaded: ${event['event_type']} ${event['branch_name']}');
    } catch (_) {
      // فشل الرفع → نضيفه للـ cache للمزامنة لاحقاً
      try {
        final file = await _branchEventsCacheFile;
        List<dynamic> list = [];
        if (await file.exists()) {
          final s = await file.readAsString();
          if (s.isNotEmpty) list = jsonDecode(s) as List<dynamic>;
        }
        list.add(event);
        await file.writeAsString(jsonEncode(list));
        debugPrint('💾 branch event cached offline (${list.length} pending).');
      } catch (e) {
        debugPrint('⚠️ فشل حفظ حدث الفرع محلياً: $e');
      }
    }
  }

  /// مزامنة الأحداث المخزنة أوفلاين
  static Future<void> _syncOfflineBranchEvents() async {
    try {
      final file = await _branchEventsCacheFile;
      if (!await file.exists()) return;
      final content = await file.readAsString();
      if (content.isEmpty) return;
      final list = jsonDecode(content) as List<dynamic>;
      if (list.isEmpty) return;

      final remaining = <Map<String, dynamic>>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final ev = Map<String, dynamic>.from(raw);
        try {
          await SupabaseService.client.from('notifications').insert({
            'employee_id': ev['employee_id'],
            'title': ev['event_type'] == 'enter'
                ? 'دخول فرع ${ev['branch_name']} (مؤرشف)'
                : 'خروج من فرع ${ev['branch_name']} (مؤرشف)',
            'body': 'تم رصد ${ev['event_type'] == 'enter' ? 'دخولك إلى' : 'خروجك من'} فرع '
                '${ev['branch_name']} في ${ev['timestamp']}',
            'type': 'attendance',
          });
        } catch (_) {
          remaining.add(ev);
        }
      }
      if (remaining.isEmpty) {
        await file.delete();
      } else {
        await file.writeAsString(jsonEncode(remaining));
      }
      debugPrint('✅ branch-events sync: ${list.length - remaining.length} uploaded, ${remaining.length} pending.');
    } catch (e) {
      debugPrint('⚠️ branch-events sync failed: $e');
    }
  }

  /// طلب استثناء التطبيق من تحسينات البطارية للأندرويد
  static Future<void> _requestBatteryOptimizationExemption() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        debugPrint('🔋 طلب استثناء التطبيق من قيود البطارية...');
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      debugPrint('⚠️ فشل طلب استثناء البطارية: $e');
    }
  }
}
