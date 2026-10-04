// =========================================================================
// نظام HR Pro v6.0 - خدمة التتبع الجغرافي والـ Geofencing (Location Service)
//
// نقطة الدخول للتتبع: البدء/الإيقاف مع البصمة، خدمة الخلفية (أندرويد)، وتدفق الموقع الحي.
// التفاصيل بمجلد location/: متى نتتبع (tracking_schedule)، الرفع والطابور الأوفلاين
// (location_uploader)، السياج الجغرافي (geofence_monitor)، ودخول/خروج الفروع (branch_presence_monitor).
// =========================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/constants.dart';
import '../utils/app_log.dart';
import 'ios_region_monitor.dart';
import 'location/branch_presence_monitor.dart';
import 'location/geofence_monitor.dart';
import 'location/location_uploader.dart';
import 'location/tracking_schedule.dart';
import 'supabase_service.dart';

/// خدمة للتحكم في التتبع الجغرافي للموظفين في الخلفية والتحقق من السياج الجغرافي وكشف التزييف
// الكلاس نفسه لازم يكون entry-point حتى تگدر خدمة الخلفية (كود أندرويد) توصل لـ onStart؛
// بدونه تفشل الخدمة بـ "To access LocationService from native code, it must be annotated".
@pragma('vm:entry-point')
class LocationService {
  static bool _isTracking = false;
  static bool get isTracking => _isTracking;

  static StreamSubscription<Position>? _positionStreamSubscription;
  static Position? _lastUploadedPosition;
  static DateTime? _lastUploadedTime;
  static String? _activeEmployeeId;

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
          initialNotificationContent: 'مزامنة بيانات الدوام',
        ),
        // iOS: إعداد شكلي فقط — النظام يرفض مهمة خلفية المكتبة، والتتبع من LocationMonitorIOS.swift
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onForeground,
          onBackground: onIosBackground,
        ),
      );
    } catch (e) {
      appLog('⚠️ تعذر تكوين خدمة الخلفية: $e');
    }
  }

  @pragma('vm:entry-point')
  static void onForeground(ServiceInstance service) {
    appLog('Background Service: iOS Foreground state.');
  }

  @pragma('vm:entry-point')
  static bool onIosBackground(ServiceInstance service) {
    appLog('Background Service: iOS Background state.');
    return true;
  }

  @pragma('vm:entry-point')
  static Future<void> onStart(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      if (!SupabaseService.isAuthenticated) {
        await SupabaseService.init();
      }
    } catch (e) {
      appLog('Background Service Isolate: Supabase init check: $e');
    }

    try {
      if (service is AndroidServiceInstance) {
        unawaited(service.setAsForegroundService());
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
          appLog('⚠️ خطأ في دورة فحص التتبع بالخلفية: $e');
        }
      });

      await _evaluateTrackingStateInService(service);
    } catch (e) {
      appLog('⚠️ خطأ في تهيئة onStart لخدمة الخلفية: $e');
    }
  }

  /// طلب صلاحيات الموقع الكافية للتتبع الدقيق
  static Future<bool> requestLocationPermissions() async {
    try {
      // 1. التحقق من تفعيل خدمة GPS في الجهاز
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        appLog('⚠️ خدمة GPS معطلة في الجهاز');
      }

      // 2. طلب الصلاحية العادية أولاً (In Use)
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
        if (!status.isGranted) {
          appLog('⚠️ صلاحية الموقع العادية مرفوضة.');
          return false;
        }
      }

      // 3. طلب صلاحية الخلفية (Always Allow) للأندرويد والآيفون إذا أمكن
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          var alwaysStatus = await Permission.locationAlways.status;
          if (!alwaysStatus.isGranted) {
            appLog('📍 طلب صلاحية الموقع بالخلفية (Always Allow)...');
            await Permission.locationAlways.request();
          }
        } catch (e) {
          appLog('تعذّر طلب صلاحية الموقع بالخلفية: $e');
        }
      }
      return true;
    } catch (e) {
      appLog('⚠️ خطأ في طلب صلاحيات الموقع: $e');
      return false;
    }
  }

  /// بدء خدمة التتبع الجغرافي للموظف فوراً
  static Future<void> startTracking({String? employeeId}) async {
    try {
      final userId = employeeId ?? SupabaseService.currentUser?.id ?? _activeEmployeeId;
      if (userId == null) {
        appLog('⚠️ لم يتم العثور على معرف الموظف لبدء التتبع');
        return;
      }

      _activeEmployeeId = userId;

      final hasPermission = await requestLocationPermissions();
      if (!hasPermission) {
        appLog('⚠️ تم إلغاء بدء خدمة التتبع لعدم توفر الصلاحيات المطلوبة.');
        return;
      }

      _isTracking = true;

      // حفظ حالة الدوام والتتبع محلياً للعمل في وضع الأوفلاين
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      await TrackingSchedule.saveState(
        hasCheckedIn: true,
        checkedInDate: todayStr,
        userId: userId,
      );

      // مزامنة أي نقاط سابقة مخزنة محلياً
      unawaited(LocationUploader.syncOffline());

      // طلب استثناء قيود البطارية للأندرويد
      if (Platform.isAndroid) {
        unawaited(_requestBatteryOptimizationExemption());
      }

      // 1. تشغيل التدفق المباشر للموقع في التطبيق فوراً
      if (_positionStreamSubscription == null) {
        _startLocationUpdates(userId);
      }

      // 2. التقاط ورفع موقع أولي فوري للتسجيل اللحظي
      unawaited(_captureInstantLocation(userId));

      // 3. خدمة الخلفية: فعلياً لأندرويد (Foreground Service). على الآيفون iOS يرفض تسجيل مهمتها
      // ("Registration rejected") فالتتبع هناك من LocationMonitorIOS.swift — الخطوة التالية.
      try {
        final service = FlutterBackgroundService();
        final isRunning = await service.isRunning();
        if (!isRunning) {
          await service.startService();
        }
      } catch (e) {
        appLog('⚠️ تعذر تشغيل BackgroundService: $e');
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
          appLog('⚠️ فشل تهيئة iOS Region Monitor: $e');
        }
      }

      appLog('✅ تم تفعيل وتشغيل نظام التتبع الجغرافي بنجاح للموظف: $userId');
    } catch (e) {
      appLog('⚠️ خطأ أثناء بدء التتبع الجغرافي: $e');
    }
  }

  /// إيقاف التتبع الجغرافي بالكامل عند الانصراف
  static Future<void> stopTracking() async {
    // Check-out: نخبر Swift إن الموظف طلع، فيتوقف المسار المستمر
    // (نبقي Region Monitoring نشط للأمان — دخول فرع بالغلط يُسجَّل)
    // الانصراف يوقف كل تتبع iOS (لا مواقع خارج الدوام)
    try {
      await IosRegionMonitor.stopMonitoring();
    } catch (e) {
      appLog('تعذّر إيقاف مراقبة المناطق (iOS) عند الانصراف: $e');
    }

    try {
      final service = FlutterBackgroundService();
      service.invoke('stopService');
    } catch (e) {
      appLog('تعذّر إيقاف خدمة التتبع بالخلفية: $e');
    }

    _isTracking = false;
    _activeEmployeeId = null;
    _stopLocationUpdates();
    GeofenceMonitor.clearStates();

    // حفظ انتهاء الدوام محلياً
    final todayStr = DateTime.now().toIso8601String().split('T')[0];
    await TrackingSchedule.saveState(
      hasCheckedIn: false,
      checkedInDate: todayStr,
    );

    appLog('🛑 تم إيقاف خدمة التتبع الجغرافي بالكامل.');
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
      appLog('📍 تم تسجيل نقطة موقع فورية: ($latitude, $longitude)');
      unawaited(LocationUploader.syncOffline());
    } catch (e) {
      appLog('⚠️ تعذر رفع الموقع الفوري، سيتم حفظه محلياً أوفلاين: $e');
      await LocationUploader.cacheOffline(locationData);
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

      _lastUploadedPosition = position;
      _lastUploadedTime = DateTime.now();
      await recordInstantLocation(
        employeeId: userId,
        latitude: position.latitude,
        longitude: position.longitude,
        isMoving: position.speed > 0.5,
      );
        } catch (e) {
      appLog('⚠️ خطأ في التقاط الموقع الأولي: $e');
    }
  }

  /// تقييم حالة التتبع الحالية للموظف داخل الخدمة
  static Future<void> _evaluateTrackingStateInService(ServiceInstance service) async {
    String? userId = _activeEmployeeId ?? SupabaseService.currentUser?.id;

    if (userId == null) {
      final cached = await TrackingSchedule.readState();
      userId = cached?['user_id'] as String?;
    }

    if (userId == null) {
      _stopLocationUpdates();
      return;
    }

    // كل دقيقتين نرفع ما خُزّن أوفلاين: النقاط، ثم أحداث الفروع والسياج.
    // ملاحظة: أحداث الفروع/السياج تُرفع فقط إذا كان بطابور النقاط شيء (سلوك قائم، انظر LocationUploader).
    unawaited(LocationUploader.syncOffline());

    final bool shouldTrack = await TrackingSchedule.shouldTrack(userId, isTrackingFallback: _isTracking);
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
        } catch (e) {
          appLog('تعذّر تحديث حالة الحضور لمراقب iOS: $e');
        }
      }
    }

    // تحديث إشعار الخدمة الخلفية للأندرويد بشكل تفاعلي
    if (service is AndroidServiceInstance) {
      // نص واضح للموظف (سياسات Google و Apple تشترط الإفصاح عن استعمال الموقع في الخلفية)
      unawaited(service.setForegroundNotificationInfo(
        title: 'HR Pro',
        content: shouldTrack ? 'يسجّل موقع العمل أثناء ساعات الدوام' : 'مزامنة بيانات الدوام',
      ));
    }
  }

  /// بدء الاستماع لتدفق إحداثيات الموقع الفعلي في الخلفية والواجهة
  static void _startLocationUpdates(String userId) {
    appLog('🚀 بدء تشغيل تدفق التتبع الجغرافي الحي للموظف: $userId');

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
          appLog('⚠️ تم تجاهل نقطة موقع ذات دقة منخفضة: ${position.accuracy}m');
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
            await SupabaseService.client
                .from('location_tracking')
                .insert(locationData)
                .timeout(const Duration(seconds: 8));
            appLog('📍 تم رفع نقطة تتبع حية للسيرفر: (${position.latitude}, ${position.longitude})');
            unawaited(LocationUploader.syncOffline());
          } catch (e) {
            appLog('💾 وضع أوفلاين: تعذر الاتصال، تم تخزين النقطة محلياً: $e');
            await LocationUploader.cacheOffline(locationData);
          }
        }

        // 4. مطابقة إحداثيات الموقع مع السياج الجغرافي (يعمل أوفلاين ويزامن لاحقاً)
        await GeofenceMonitor.verify(userId, position);

        // 5. رصد دخول/خروج الفروع (يعمل أوفلاين ويزامن لاحقاً)
        await BranchPresenceMonitor.check(userId, position);
      } catch (e, stack) {
        appLog('⚠️ خطأ داخل مستمع الموقع: $e\n$stack');
      }
    }, onError: (dynamic e) {
      appLog('⚠️ خطأ في استقبال تدفق بيانات الموقع: $e');
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
    appLog('تم إيقاف تدفق الموقع الجغرافي.');
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

      appLog('🚨 تم كشف وتوثيق محاولة تزييف موقع جغرافي للموظف: $employeeId');
    } catch (e) {
      appLog('خطأ في تسجيل خرق تزييف الموقع: $e');
    }
  }

  /// طلب استثناء التطبيق من تحسينات البطارية للأندرويد
  static Future<void> _requestBatteryOptimizationExemption() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (!status.isGranted) {
        appLog('🔋 طلب استثناء التطبيق من قيود البطارية...');
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      appLog('⚠️ فشل طلب استثناء البطارية: $e');
    }
  }
}
