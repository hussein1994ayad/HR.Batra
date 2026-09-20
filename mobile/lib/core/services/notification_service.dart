// =========================================================================
// HR Pro v6.0 - Notification Service (FCM + Local)
// =========================================================================
// إصلاحات هذه النسخة:
//  ✅ قناة v6 جديدة بصوت مضمون (نحذف القديمة v5 عن هذا الجهاز)
//  ✅ أهمية Max + priority High + vibration + light
//  ✅ صوت مخصص special_chime + fallback للـ default
//  ✅ خدمة الخلفية بنص محايد (لا يذكر "تتبع" — مزامنة آمنة نشطة)
// =========================================================================

import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message: ${message.messageId}');
}

class NotificationService {
  static final _firebaseMessaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static String lastError = '';

  // ⚠️ عند تغيير أي إعداد قناة (صوت/أهمية) لازم نبمب الرقم لأن Android
  // لا يحدّث القناة الموجودة — لا يعيد إنشاءها إلا بعنوان جديد.
  static const String channelId = 'hr_pro_channel_v6';
  static const String channelName = 'HR Pro Notifications';
  static const String syncChannelId = 'hrpro_sync_v2';
  static const String syncChannelName = 'HR Pro Background Sync';

  static Future<void> init() async {
    if (_initialized) return;
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          ),
        ),
      );

      // إعداد قنوات الأندرويد (idempotent — يعيد الإنشاء إذا لم تكن موجودة)
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // 1) احذف القنوات القديمة (v5) لضمان أن الجهاز يستخدم الجديدة
        try {
          await androidPlugin.deleteNotificationChannel('hr_pro_channel_v5');
          await androidPlugin.deleteNotificationChannel('hrpro_location_service');
        } catch (_) {}

        // 2) قناة الإشعارات الرئيسية بصوت وأهمية قصوى
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: 'إشعارات إدارية وتنبيهات مهمة',
            importance: Importance.max,
            sound: RawResourceAndroidNotificationSound('special_chime'),
            playSound: true,
            enableVibration: true,
            enableLights: true,
            ledColor: Color(0xFF0F766E),
            showBadge: true,
          ),
        );

        // 3) قناة الخدمة الخلفية — بدون صوت وبنص محايد
        // (Android يفرض إظهار notification للـ foreground service — لا يمكن إخفاؤها،
        //  لكن يمكن جعل النص عاماً وغير كاشف: "المزامنة الآمنة نشطة")
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
              icon: '@mipmap/ic_launcher',
              sound: const RawResourceAndroidNotificationSound('special_chime'),
              playSound: true,
              enableVibration: true,
              enableLights: true,
              ledColor: const Color(0xFF0F766E),
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
              sound: 'default',
              interruptionLevel: InterruptionLevel.active,
            ),
          ),
        );
      });

      _initialized = true;
      lastError = '';

      // تحديث التوكن إذا كان المستخدم مسجّل دخول
      final hasPermission = await isPermissionGranted();
      final user = Supabase.instance.client.auth.currentUser;
      if (hasPermission && user != null) {
        final token = await _firebaseMessaging.getToken();
        if (token != null) await _saveTokenToSupabase(token);
        _firebaseMessaging.onTokenRefresh.listen(_saveTokenToSupabase);
      }
    } catch (e) {
      lastError = e.toString();
      debugPrint('❌ NotificationService init error: $e');
    }
  }

  /// طلب الصلاحيات وحفظ التوكن. يُستدعى بعد تسجيل الدخول.
  static Future<bool> requestPermissionAndSaveToken() async {
    try {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return false;
      }
      final token = await _firebaseMessaging.getToken();
      if (token != null) await _saveTokenToSupabase(token);
      _firebaseMessaging.onTokenRefresh.listen(_saveTokenToSupabase);
      return true;
    } catch (e) {
      debugPrint('Error requesting permission: $e');
      return false;
    }
  }

  /// إظهار إشعار محلي فوراً — يستعمله المشترك الفوري (realtime) عند وصول
  /// صف جديد في notifications بينما التطبيق مفتوح.
  static Future<void> showLocalNotification({
    required String title,
    required String body,
  }) async {
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: 'إشعارات إدارية وتنبيهات مهمة',
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            sound: const RawResourceAndroidNotificationSound('special_chime'),
            playSound: true,
            enableVibration: true,
            enableLights: true,
            ledColor: const Color(0xFF0F766E),
            category: AndroidNotificationCategory.message,
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
            sound: 'default',
            interruptionLevel: InterruptionLevel.active,
          ),
        ),
      );
    } catch (e) {
      debugPrint('showLocalNotification error: $e');
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
