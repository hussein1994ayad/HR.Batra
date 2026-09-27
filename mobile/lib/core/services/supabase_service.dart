// =========================================================================
// نظام HR Pro v6.0 - خدمة الاتصال بـ Supabase (Supabase Service)
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/constants.dart';

class SupabaseService {
  // كائن زبون Supabase الرئيسي
  static SupabaseClient get client => Supabase.instance.client;

  // تهيئة الاتصال بقاعدة البيانات والـ Storage عند إقلاع التطبيق
  static Future<void> init() async {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  }

  // مساعدات برمجية سريعة للجلسة الحالية
  static User? get currentUser {
    try {
      return client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }
  
  static bool get isAuthenticated => currentUser != null;

  // تسجيل الخروج التام
}
