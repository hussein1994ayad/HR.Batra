// =========================================================================
// نظام HR Pro v6.0 - نقطة الدخول الرئيسية
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/routes/app_router.dart';
import 'core/services/supabase_service.dart';
import 'package:hr_pro/core/services/notification_service.dart';
import 'package:hr_pro/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. تهيئة Supabase
  await SupabaseService.init();

  // 3. تهيئة Firebase والإشعارات (FCM)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await NotificationService.init();
  } catch (e) {
    debugPrint('⚠️ فشل تهيئة Firebase: $e');
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
