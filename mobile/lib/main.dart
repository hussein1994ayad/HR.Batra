// =========================================================================
// نظام HR Pro v6.0 - نقطة الدخول الرئيسية
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/routes/app_router.dart';
import 'core/services/supabase_service.dart';
import 'core/services/location_service.dart';
import 'package:hr_pro/core/services/notification_service.dart';
import 'package:hr_pro/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';

import 'dart:ui';

void main() async {
  // 1. ضمان استقرار المحرك ومعالجة كافة الأخطاء غير الملتقطة لمنع توقف التطبيق نهائياً
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('🛑 Flutter Framework Error: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('🛑 PlatformDispatcher Handled Async Error: $error\n$stack');
    // إرجاع true يمنع النظام (Android/iOS) من إغلاق التطبيق قسرياً
    return true;
  };

  // 2. تهيئة Supabase بأمان
  try {
    await SupabaseService.init();
  } catch (e, stack) {
    debugPrint('⚠️ فشل تهيئة Supabase: $e\n$stack');
  }

  // 3. تهيئة Firebase والإشعارات (FCM) وقنوات الإشعار
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await NotificationService.init();
  } catch (e, stack) {
    debugPrint('⚠️ فشل تهيئة Firebase: $e\n$stack');
  }

  // 4. تهيئة خدمة الموقع بالخلفية بأمان تام
  try {
    await LocationService.initializeBackgroundService();
  } catch (e, stack) {
    debugPrint('⚠️ فشل تهيئة خدمة الموقع بالخلفية: $e\n$stack');
  }

  runApp(
    const ProviderScope(
      child: HRProApp(),
    ),
  );
}

class HRProApp extends StatelessWidget {
  const HRProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HR Pro',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'IQ'),
      supportedLocales: const [
        Locale('ar', 'IQ'),
        Locale('ar', ''),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
  }
}
