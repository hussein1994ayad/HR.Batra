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
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  // مساعدات برمجية سريعة للجلسة الحالية
  static User? get currentUser => client.auth.currentUser;
  
  static bool get isAuthenticated => currentUser != null;

  // تسجيل الخروج التام
  static Future<void> signOut() async {
    await client.auth.signOut();
  }
}
