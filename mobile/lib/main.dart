// =========================================================================
// نظام HR Pro v6.0 - نقطة الدخول الرئيسية
// =========================================================================

import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/app_container.dart';
import 'core/routes/app_router.dart';
import 'core/services/location_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'presentation/shared/widgets/offline_banner.dart';

void main() async {
  // 1. ضمان استقرار المحرك ومعالجة كافة الأخطاء غير الملتقطة لمنع توقف التطبيق نهائياً
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('🛑 Flutter Framework Error: ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('🛑 PlatformDispatcher Handled Async Error: $error\n$stack');
    return true;
  };

  // 2. تهيئة Supabase + Firebase بشكل متوازٍ (كلاهما مستقل عن بعض)
  //    هذا يوفر ~300-500ms مقارنة بالتسلسل
  await Future.wait([
    // Supabase — ضرورية قبل فحص الجلسة
    Future(() async {
      try {
        await SupabaseService.init();
      } catch (e, stack) {
        debugPrint('⚠️ فشل تهيئة Supabase: $e\n$stack');
      }
    }),
    // Firebase + Notifications — مستقلة عن Supabase
    Future(() async {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        await NotificationService.init();
      } catch (e, stack) {
        debugPrint('⚠️ فشل تهيئة Firebase/Notifications: $e\n$stack');
      }
    }),
  ]);

  // 3. تشغيل التطبيق فوراً — بدون انتظار خدمة الموقع
  runApp(
    UncontrolledProviderScope(
      container: appContainer,
      child: const HRProApp(),
    ),
  );

  // 4. تهيئة الخدمات غير الحرجة بعد رسم الإطار الأول
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ConnectivityStatus.startPolling();

    // خدمة الموقع ثقيلة — نؤجلها بالكامل لما بعد ظهور الشاشة
    Future(() async {
      try {
        await LocationService.initializeBackgroundService();
      } catch (e, stack) {
        debugPrint('⚠️ فشل تهيئة خدمة الموقع بالخلفية: $e\n$stack');
      }
    });
  });
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
