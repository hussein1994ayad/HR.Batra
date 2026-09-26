// =========================================================================
// HR Pro v6.0 - Notification Service (FCM + Local + Attendance Reminders)
// =========================================================================

import 'dart:async';

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;

import '../../core/design/design.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message: ${message.messageId}');
}

class NotificationService {
  // FirebaseMessaging.instance يرمي خطأ إذا لم يُهيّأ Firebase (مثلاً iOS قبل
  // إضافة GoogleService-Info.plist)، لذلك يُستعمل فقط عندما يكون جاهزاً.
  static FirebaseMessaging get _firebaseMessaging => FirebaseMessaging.instance;
  static bool get _firebaseReady => Firebase.apps.isNotEmpty;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static String lastError = '';

  // قنوات الإشعارات
  static const String channelId = 'hr_pro_channel_v6';
  static const String channelName = 'HR Pro Notifications';
  static const String reminderChannelId = 'hr_pro_attendance_reminders_v1';
  static const String reminderChannelName = 'تذكيرات بصمة الدوام';
  static const String syncChannelId = 'hrpro_sync_v2';
  static const String syncChannelName = 'HR Pro Background Sync';

  static Future<void> init() async {
    if (_initialized) return;
    try {
      // 1. تهيئة التوقيت والمناطق الزمنية للمواعيد المجدولة
      try {
        tz.initializeTimeZones();
      } catch (e) {
        debugPrint('Timezones init warning: $e');
      }

      if (_firebaseReady) {
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      }

      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
          iOS: DarwinInitializationSettings(
            
          ),
        ),
      );

      // إعداد قنوات الأندرويد
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // طلب إذن المنبهات والتنبيهات الدقيقة في Android 12+
        try {
          await androidPlugin.requestExactAlarmsPermission();
        } catch (_) {}

        // حذف القنوات القديمة
        try {
          await androidPlugin.deleteNotificationChannel('hr_pro_channel_v5');
          await androidPlugin.deleteNotificationChannel('hrpro_location_service');
        } catch (_) {}

        // 1) قناة الإشعارات العامة
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: 'إشعارات إدارية وتنبيهات مهمة',
            importance: Importance.max,
            sound: RawResourceAndroidNotificationSound('special_chime'),
            enableLights: true,
            ledColor: AppColors.brandStrong,
          ),
        );

        // 2) قناة تذكيرات بصمة الدوام (أهمية قصوى مع رنين واهتزاز)
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            reminderChannelId,
            reminderChannelName,
            description: 'تنبيهات وتذكيرات مواعيد تسجيل بصمة الحضور والانصراف',
            importance: Importance.max,
            sound: RawResourceAndroidNotificationSound('special_chime'),
            enableLights: true,
            ledColor: AppColors.brandStrong,
          ),
        );

        // 3) قناة الخدمة الخلفية (صامتة)
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            syncChannelId,
            syncChannelName,
            description: 'مزامنة البيانات في الخلفية',
            importance: Importance.min,
            playSound: false,
            enableVibration: false,
            showBadge: false,
          ),
        );
      }

      // Foreground: استقبال + إظهار محلي مع صوت
      if (_firebaseReady) {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.notification == null) return;
        _localNotifications.show(
          message.hashCode,
          message.notification!.title,
          message.notification!.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              channelDescription: 'إشعارات إدارية وتنبيهات مهمة',
              importance: Importance.max,
              priority: Priority.max,
              icon: '@mipmap/launcher_icon',
              sound: const RawResourceAndroidNotificationSound('special_chime'),
              enableLights: true,
              ledColor: AppColors.brandStrong,
              category: AndroidNotificationCategory.message,
              visibility: NotificationVisibility.public,
              ticker: message.notification!.title,
              styleInformation: BigTextStyleInformation(
                message.notification!.body ?? '',
                contentTitle: message.notification!.title,
              ),
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
              sound: 'special_chime.wav',
              interruptionLevel: InterruptionLevel.active,
            ),
          ),
        );
      });
      }

      _initialized = true;
      lastError = '';

      // تحديث التوكن وجدولة التذكيرات في الخلفية لعدم إبطاء إقلاع التطبيق نهائياً
      unawaited(Future.microtask(() async {
        try {
          final hasPermission = await isPermissionGranted();
          final user = Supabase.instance.client.auth.currentUser;
          if (_firebaseReady && hasPermission && user != null) {
            final token = await _firebaseMessaging.getToken();
            if (token != null) await _saveTokenToSupabase(token);
            _firebaseMessaging.onTokenRefresh.listen(_saveTokenToSupabase);
          }
          if (user != null) {
            unawaited(cancelAllAttendanceReminders());
          }
        } catch (e) {
          debugPrint('Non-fatal background notification init error: $e');
        }
      }));

    } catch (e) {
      lastError = e.toString();
      debugPrint('❌ NotificationService init error: $e');
    }
  }

  /// طلب الصلاحيات وحفظ التوكن. يُستدعى بعد تسجيل الدخول.
  static Future<bool> requestPermissionAndSaveToken() async {
    if (!_firebaseReady) {
      await cancelAllAttendanceReminders();
      return false;
    }
    try {
      final settings = await _firebaseMessaging.requestPermission(
        
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return false;
      }
      final token = await _firebaseMessaging.getToken();
      if (token != null) await _saveTokenToSupabase(token);
      _firebaseMessaging.onTokenRefresh.listen(_saveTokenToSupabase);

      // إعادة جدولة التذكيرات بعد منح الصلاحيات
      await cancelAllAttendanceReminders();

      return true;
    } catch (e) {
      debugPrint('Error requesting permission: $e');
      return false;
    }
  }

  /// إظهار إشعار محلي فوراً
  static Future<void> showLocalNotification({
    required String title,
    required String body,
    String? channel,
  }) async {
    try {
      final targetChannel = channel ?? channelId;
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            targetChannel,
            targetChannel == reminderChannelId ? reminderChannelName : channelName,
            channelDescription: 'إشعارات إدارية وتنبيهات مهمة',
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/launcher_icon',
            sound: const RawResourceAndroidNotificationSound('special_chime'),
            enableLights: true,
            ledColor: AppColors.brandStrong,
            category: targetChannel == reminderChannelId 
                ? AndroidNotificationCategory.alarm 
                : AndroidNotificationCategory.message,
            visibility: NotificationVisibility.public,
            ticker: title,
            styleInformation: BigTextStyleInformation(
              body,
              contentTitle: title,
            ),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: 'special_chime.wav',
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );
    } catch (e) {
      debugPrint('showLocalNotification error: $e');
    }
  }

  // =========================================================================
  // نظام جدولة تذكيرات بصمة الدخول وبصمة الخروج (Check-in & Check-out Alarms)
  // =========================================================================

  /// إلغاء كافة تذكيرات البصمة المجدولة
  static Future<void> cancelAllAttendanceReminders() async {
    for (int day = 0; day <= 6; day++) {
      try {
        await _localNotifications.cancel(1000 + day);
        await _localNotifications.cancel(2000 + day);
      } catch (_) {}
    }
  }

  /// يفصل هذا الهاتف عن حساب المستخدم عند تسجيل الخروج: يحذف رمز الإشعارات
  /// من السيرفر ويلغيه من Firebase، حتى لا تصل إشعارات الحساب السابق لهذا الهاتف.
  /// يجب أن يُستدعى والجلسة ما زالت فعّالة.
  static Future<void> unregisterDevice() async {
    await cancelAllAttendanceReminders();
    final user = Supabase.instance.client.auth.currentUser;
    if (!_firebaseReady) return;
    try {
      final token = await _firebaseMessaging.getToken().timeout(const Duration(seconds: 5));
      if (token != null && user != null) {
        final db = Supabase.instance.client;
        await Future.wait([
          db.from('fcm_tokens').delete().eq('employee_id', user.id).eq('token', token),
          db.from('device_tokens').delete().eq('employee_id', user.id).eq('token', token),
          db.from('employees').update({'fcm_token': null}).eq('id', user.id).eq('fcm_token', token),
        ]).timeout(const Duration(seconds: 8));
      }
    } catch (e) {
      debugPrint('unregisterDevice: server cleanup failed: $e');
    }
    try {
      await _firebaseMessaging.deleteToken();
    } catch (e) {
      debugPrint('unregisterDevice: deleteToken failed: $e');
    }
  }

  static Future<void> _saveTokenToSupabase(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final platform = Platform.isAndroid ? 'android' : 'ios';

    try {
      await Supabase.instance.client
          .from('employees')
          .update({'fcm_token': token}).eq('id', user.id);
    } catch (_) {}

    try {
      await Supabase.instance.client.from('fcm_tokens').upsert({
        'employee_id': user.id,
        'token': token,
        'device_platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'employee_id,token');
    } catch (_) {}

    try {
      await Supabase.instance.client.from('device_tokens').upsert({
        'employee_id': user.id,
        'token': token,
        'platform': platform,
      });
    } catch (_) {}
  }

  static Future<bool> isPermissionGranted() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }
}

