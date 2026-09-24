// =========================================================================
// HR Pro v6.0 - Notification Service (FCM + Local + Attendance Reminders)
// =========================================================================

import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message: ${message.messageId}');
}

class NotificationService {
  static final _firebaseMessaging = FirebaseMessaging.instance;
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

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
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
            playSound: true,
            enableVibration: true,
            enableLights: true,
            ledColor: Color(0xFF0F766E),
            showBadge: true,
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
            playSound: true,
            enableVibration: true,
            enableLights: true,
            ledColor: Color(0xFF0F766E),
            showBadge: true,
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
              sound: 'special_chime.wav',
              interruptionLevel: InterruptionLevel.active,
            ),
          ),
        );
      });

      _initialized = true;
      lastError = '';

      // تحديث التوكن وجدولة التذكيرات في الخلفية لعدم إبطاء إقلاع التطبيق نهائياً
      Future.microtask(() async {
        try {
          final hasPermission = await isPermissionGranted();
          final user = Supabase.instance.client.auth.currentUser;
          if (hasPermission && user != null) {
            final token = await _firebaseMessaging.getToken();
            if (token != null) await _saveTokenToSupabase(token);
            _firebaseMessaging.onTokenRefresh.listen(_saveTokenToSupabase);
          }
          if (user != null) {
            scheduleAttendanceReminders();
          }
        } catch (e) {
          debugPrint('Non-fatal background notification init error: $e');
        }
      });

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
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return false;
      }
      final token = await _firebaseMessaging.getToken();
      if (token != null) await _saveTokenToSupabase(token);
      _firebaseMessaging.onTokenRefresh.listen(_saveTokenToSupabase);

      // إعادة جدولة التذكيرات بعد منح الصلاحيات
      await scheduleAttendanceReminders();

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
            playSound: true,
            enableVibration: true,
            enableLights: true,
            ledColor: const Color(0xFF0F766E),
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

  /// جدولة تذكيرات بصمة الحضور والانصراف تلقائياً بناءً على جدول عمل الموظف
  static Future<void> scheduleAttendanceReminders({
    Map<String, dynamic>? schedule,
    int reminderMinutesBeforeCheckIn = 15,
    int reminderMinutesBeforeCheckOut = 0,
  }) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      Map<String, dynamic>? activeSchedule = schedule;

      // إذا لم يتم تمرير الجدول، نحاول جلبه من السيرفر
      if (activeSchedule == null) {
        try {
          final empRes = await Supabase.instance.client
              .from('employees')
              .select('branch_id, department_id')
              .eq('id', user.id)
              .maybeSingle();

          if (empRes != null) {
            final List<String> orFilters = ['employee_id.eq.${user.id}'];
            if (empRes['department_id'] != null) {
              orFilters.add('department_id.eq.${empRes['department_id']}');
            }
            if (empRes['branch_id'] != null) {
              orFilters.add('branch_id.eq.${empRes['branch_id']}');
            }

            final schedRes = await Supabase.instance.client
                .from('work_schedules')
                .select()
                .or(orFilters.join(','))
                .limit(1)
                .maybeSingle();

            activeSchedule = schedRes;
          }
        } catch (e) {
          debugPrint('⚠️ تعذر جلب جدول العمل للجدولة: $e');
        }
      }

      // أوقات الدوام الافتراضية إذا لم يوجد جدول محدد
      final String checkInStr = activeSchedule?['check_in_time'] ?? '08:30:00';
      final String checkOutStr = activeSchedule?['check_out_time'] ?? '16:30:00';
      final List<dynamic> rawWorkDays = activeSchedule?['work_days'] ?? [0, 1, 2, 3, 4, 6]; // الأحد إلى الخميس + السبت

      final List<int> workDays = rawWorkDays.map((e) => int.tryParse(e.toString()) ?? 0).toList();

      // تحليل وقت الحضور والانصراف
      final inParts = checkInStr.split(':');
      final outParts = checkOutStr.split(':');
      if (inParts.length < 2 || outParts.length < 2) return;

      final int inHour = int.parse(inParts[0]);
      final int inMin = int.parse(inParts[1]);
      final int outHour = int.parse(outParts[0]);
      final int outMin = int.parse(outParts[1]);

      // إلغاء أي تذكيرات قديمة مبرمجة سابقاً
      await cancelAllAttendanceReminders();

      // حساب وقت التنبيه قبل الحضور
      int targetInMin = inMin - reminderMinutesBeforeCheckIn;
      int targetInHour = inHour;
      if (targetInMin < 0) {
        targetInMin += 60;
        targetInHour -= 1;
        if (targetInHour < 0) targetInHour = 23;
      }

      // حساب وقت التنبيه للانصراف
      int targetOutMin = outMin - reminderMinutesBeforeCheckOut;
      int targetOutHour = outHour;
      if (targetOutMin < 0) {
        targetOutMin += 60;
        targetOutHour -= 1;
        if (targetOutHour < 0) targetOutHour = 23;
      }

      // جدولة لكل يوم من أيام الدوام الأسبوعية
      for (final dbDay in workDays) {
        final dartWeekday = _dbDayToDartWeekday(dbDay);

        // 1. تذكير بصمة الحضور (Check-in Reminder)
        final inId = 1000 + dbDay;
        final inScheduledDate = _nextInstanceOfWeekdayAndTime(dartWeekday, targetInHour, targetInMin);

        await _localNotifications.zonedSchedule(
          inId,
          'تذكير: موعد بصمة الحضور 🟢',
          reminderMinutesBeforeCheckIn > 0 
              ? 'يبدأ دوامك بعد $reminderMinutesBeforeCheckIn دقيقة ($checkInStr). يرجى التواجد في الفرع لتسجيل الحضور.'
              : 'حان موعد بدء الدوام الرسمي ($checkInStr). يرجى تسجيل بصمة الحضور الآن.',
          inScheduledDate,
          NotificationDetails(
            android: AndroidNotificationDetails(
              reminderChannelId,
              reminderChannelName,
              channelDescription: 'تنبيهات وتذكيرات مواعيد تسجيل بصمة الحضور والانصراف',
              importance: Importance.max,
              priority: Priority.max,
              icon: '@mipmap/launcher_icon',
              sound: const RawResourceAndroidNotificationSound('special_chime'),
              playSound: true,
              enableVibration: true,
              enableLights: true,
              ledColor: const Color(0xFF0F766E),
              category: AndroidNotificationCategory.alarm,
              visibility: NotificationVisibility.public,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
              sound: 'special_chime.wav',
              interruptionLevel: InterruptionLevel.timeSensitive,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );

        // 2. تذكير بصمة الانصراف (Check-out Reminder)
        final outId = 2000 + dbDay;
        final outScheduledDate = _nextInstanceOfWeekdayAndTime(dartWeekday, targetOutHour, targetOutMin);

        await _localNotifications.zonedSchedule(
          outId,
          'تذكير: موعد بصمة الانصراف 🔴',
          'انتهى وقت الدوام الرسمي المقرّر ($checkOutStr). يرجى تسجيل بصمة الانصراف قبل مغادرة الفرع.',
          outScheduledDate,
          NotificationDetails(
            android: AndroidNotificationDetails(
              reminderChannelId,
              reminderChannelName,
              channelDescription: 'تنبيهات وتذكيرات مواعيد تسجيل بصمة الحضور والانصراف',
              importance: Importance.max,
              priority: Priority.max,
              icon: '@mipmap/launcher_icon',
              sound: const RawResourceAndroidNotificationSound('special_chime'),
              playSound: true,
              enableVibration: true,
              enableLights: true,
              ledColor: const Color(0xFF0F766E),
              category: AndroidNotificationCategory.alarm,
              visibility: NotificationVisibility.public,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
              sound: 'special_chime.wav',
              interruptionLevel: InterruptionLevel.timeSensitive,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }

      debugPrint('✅ تم بنجاح جدولة تذكيرات الحضور والانصراف لـ ${workDays.length} أيام عمل أسبوعية.');
    } catch (e, stack) {
      debugPrint('❌ خطأ في جدولة تذكيرات الحضور والانصراف: $e\n$stack');
    }
  }

  /// إلغاء كافة تذكيرات البصمة المجدولة
  static Future<void> cancelAllAttendanceReminders() async {
    for (int day = 0; day <= 6; day++) {
      try {
        await _localNotifications.cancel(1000 + day);
        await _localNotifications.cancel(2000 + day);
      } catch (_) {}
    }
  }

  /// إلغاء تذكير حضور اليوم (يُستدعى فور قيام الموظف بالتبصيم)
  static Future<void> cancelTodayCheckInReminder() async {
    try {
      final now = DateTime.now();
      final dbDay = now.weekday % 7; // Sunday = 0, Monday = 1...
      await _localNotifications.cancel(1000 + dbDay);
      debugPrint('تم إلغاء تذكير حضور اليوم بعد اكتمال البصمة.');
    } catch (_) {}
  }

  /// إلغاء تذكير انصراف اليوم (يُستدعى فور تسجيل الانصراف)
  static Future<void> cancelTodayCheckOutReminder() async {
    try {
      final now = DateTime.now();
      final dbDay = now.weekday % 7;
      await _localNotifications.cancel(2000 + dbDay);
      debugPrint('تم إلغاء تذكير انصراف اليوم بعد اكتمال البصمة.');
    } catch (_) {}
  }

  /// حساب التوقيت القادم ليوم محدد وساعة محددة
  static tz.TZDateTime _nextInstanceOfWeekdayAndTime(int dartWeekday, int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    while (scheduledDate.weekday != dartWeekday || scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  /// تحويل ترميز اليوم في قاعدة البيانات (0=الأحد ... 6=السبت) إلى ترميز Dart (1=الإثنين ... 7=الأحد)
  static int _dbDayToDartWeekday(int dbDay) {
    if (dbDay == 0) return DateTime.sunday; // 7
    return dbDay; // 1 = monday, 2 = tuesday, 3 = wednesday, 4 = thursday, 5 = friday, 6 = saturday
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

