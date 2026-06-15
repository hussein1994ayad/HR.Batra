// =========================================================================
// نظام HR Pro v6.0 - خدمة الإشعارات (Firebase Cloud Messaging)
// =========================================================================

import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // هذا المعالج يعمل في الخلفية حتى لو التطبيق مغلق تماماً
  debugPrint('Handling a background message: ${message.messageId}');
}

class NotificationService {
  static final _firebaseMessaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();
  
  static bool _initialized = false;
  static String lastError = '';

  static const String channelId = 'hr_pro_channel_v4';
  static const String channelName = 'HR Pro Notifications';

  static Future<void> init() async {
    if (_initialized) return;
    try {
      // 1. تسجيل معالج الإشعارات في الخلفية
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 2. إعداد Flutter Local Notifications للإشعارات أثناء فتح التطبيق (Foreground)
      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );

      // 3. إنشاء قناة إشعارات عالية الأهمية للأندرويد مع الصوت المخصص
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              channelId,
              channelName,
              description: 'إشعارات إدارية وتنبيهات هامة',
              importance: Importance.max,
              sound: RawResourceAndroidNotificationSound('special_chime'),
              playSound: true,
            ),
          );

      // 4. الاستماع للإشعارات أثناء فتح التطبيق
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
        
        if (message.notification != null) {
          _localNotifications.show(
            message.hashCode,
            message.notification!.title,
            message.notification!.body,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                channelId,
                channelName,
                importance: Importance.max,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
                sound: RawResourceAndroidNotificationSound('special_chime'),
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            ),
          );
        }
      });

      _initialized = true;
      lastError = '';
      debugPrint('✅ Firebase NotificationService initialized');
      
      // 5. تحديث التوكن تلقائياً إذا كان مسجلاً للدخول مسبقاً ولديه صلاحية
      final hasPermission = await isPermissionGranted();
      final user = Supabase.instance.client.auth.currentUser;
      if (hasPermission && user != null) {
        debugPrint('Auto-fetching FCM token on startup...');
        String? token = await _firebaseMessaging.getToken();
        if (token != null) {
           await _saveTokenToSupabase(token);
        }
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
           _saveTokenToSupabase(newToken);
        });
      }
    } catch (e) {
      lastError = e.toString();
      debugPrint('❌ Error initializing NotificationService: $e');
    }
  }

  // طلب صلاحيات الإشعارات وربط توكن الجهاز بالسيرفر
  static Future<bool> requestPermissionAndSaveToken() async {
    try {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted permission');
        
        // جلب الـ Token الخاص بالجهاز
        String? token = await _firebaseMessaging.getToken();
        debugPrint('FCM Token: $token');
        
        if (token != null) {
           await _saveTokenToSupabase(token);
        }

        // تحديث التوكن في حال تغيّر
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
           _saveTokenToSupabase(newToken);
        });

        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error requesting permission: $e');
      return false;
    }
  }

  static Future<void> _saveTokenToSupabase(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final platform = Platform.isAndroid ? 'android' : 'ios';
      
      // 1. تحديث حقل fcm_token في جدول الموظفين (للتوافق القديم)
      try {
        await Supabase.instance.client
            .from('employees')
            .update({'fcm_token': token})
            .eq('id', user.id);
        debugPrint('✅ FCM Token saved to employees table for user: ${user.id}');
      } catch (e) {
        debugPrint('❌ Failed to save FCM Token to employees: $e');
      }

      // 2. تحديث جدول fcm_tokens (التصميم الجديد للأجهزة المتعددة)
      try {
        await Supabase.instance.client
            .from('fcm_tokens')
            .upsert({
              'employee_id': user.id,
              'token': token,
              'device_platform': platform,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }, onConflict: 'employee_id,token');
        debugPrint('✅ FCM Token saved to fcm_tokens table');
      } catch (e) {
        debugPrint('❌ Failed to save FCM Token to fcm_tokens: $e');
      }

      // 3. تحديث جدول device_tokens (للتوافق الإضافي)
      try {
        await Supabase.instance.client
            .from('device_tokens')
            .upsert({
              'employee_id': user.id,
              'token': token,
              'platform': platform,
            });
        debugPrint('✅ FCM Token saved to device_tokens table');
      } catch (e) {
        debugPrint('❌ Failed to save FCM Token to device_tokens: $e');
      }
    }
  }

  static Future<bool> isPermissionGranted() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }
}
