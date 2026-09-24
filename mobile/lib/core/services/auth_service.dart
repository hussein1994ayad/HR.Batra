// =========================================================================
// HR Pro v6.0 — Authentication & Session Service
// =========================================================================
// المسؤوليات:
//  • تسجيل الدخول عبر Supabase Auth مع فحص جدول employees
//  • قفل الجهاز الواحد (Single-Device Locking) — انظر _handleDeviceLock
//  • فرض تغيير كلمة المرور المؤقتة عند أول دخول
//  • انتهاء الجلسة بعد فترة عدم استخدام (SessionTimeout)
//  • تنظيف الحالة الثابتة (currentUserRole) عند تسجيل الخروج
// =========================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/app_container.dart';
import '../providers/auth_provider.dart';
import 'device_service.dart';
import 'supabase_service.dart';

// -------------------------------------------------------------------------
// Exceptions — بأنواع محددة ليسهل معالجة كل حالة بشكل مستقل
// -------------------------------------------------------------------------

/// حساب معطّل من قبل الإدارة (is_active=false).
class InactiveAccountException implements Exception {
  final String message =
      'هذا الحساب معطل حالياً. يرجى مراجعة إدارة الموارد البشرية لتفعيله.';
  @override
  String toString() => message;
}

/// محاولة تسجيل دخول من جهاز غير معتمد (قفل الجهاز الواحد فعّال).
class DeviceLockedException implements Exception {
  final String message =
      'لا يمكن تسجيل الدخول من هذا الجهاز. هذا الحساب مقفل ومصرح به لجهاز آخر معتمد فقط. '
      'تم تسجيل هذه المحاولة كخرق أمني.';
  @override
  String toString() => message;
}

/// كلمة المرور المؤقتة تحتاج تغيير قبل استعمال النظام.
class MustChangePasswordException implements Exception {
  final String message =
      'يجب عليك تغيير كلمة المرور المؤقتة الممنوحة لك قبل التمكن من تصفح النظام.';
  @override
  String toString() => message;
}

/// وجهة شاشة البداية بعد فحص الجلسة.
enum StartupDestination { login, changePassword, home }

// -------------------------------------------------------------------------
// AuthService
// -------------------------------------------------------------------------

/// خدمة إدارة المصادقة والجلسات والأمن التطبيقي.
///
/// ملاحظة: تحتفظ بحقل ثابت `currentUserRole` لأغراض التحقق السريع من الصلاحيات
/// من داخل الـ Router و الشاشات. **يُمسح تلقائياً عند تسجيل الخروج** (انظر [signOut]).
class AuthService {
  // -----------------------------------------------------------------------
  // Session Timeout — عدد الأيام قبل انتهاء الجلسة تلقائياً بدون استخدام
  // -----------------------------------------------------------------------
  static const int _sessionMaxIdleDays = 30;
  static const String _kLastActivityKey = 'auth.last_activity_ms';
  static const String _kCachedRoleKey = 'auth.cached_role';

  /// الدور الحالي للمستخدم — مقروء من قِبل الـ Router والشاشات.
  /// يُمسح إلى null عند تسجيل الخروج أو انتهاء الجلسة.
  static String? currentUserRole;

  /// Set the current role in both the static field (backward-compat) and
  /// the Riverpod provider (source of truth for widgets).
  static void _setRole(String? role) {
    currentUserRole = role;
    unawaited(_cacheRole(role));
    try {
      appContainer.read(currentUserRoleProvider.notifier).state = role;
    } catch (e) {
      debugPrint('auth: role provider sync failed: $e');
    }
  }


  // =======================================================================
  // Public API
  // =======================================================================

  /// تسجيل الدخول الكامل مع كل فحوصات الأمان.
  ///
  /// يرمي أحد الاستثناءات المُعرَّفة أعلاه حسب الحالة.
  static Future<void> signIn(String email, String password) async {
    // 1) Supabase Auth
    final AuthResponse response =
        await SupabaseService.client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final User? user = response.user;
    if (user == null) {
      throw Exception(
          'فشل تسجيل الدخول، يرجى التحقق من البريد الإلكتروني وكلمة المرور.');
    }

    try {
      // 2) قراءة صف الموظف
      final employee = await _loadEmployee(user.id);
      _setRole(employee['role'] as String?);

      // 3) الحساب مفعّل؟
      if (!(employee['is_active'] as bool? ?? false)) {
        await signOut();
        throw InactiveAccountException();
      }

      // 4) قفل الجهاز
      await _handleDeviceLock();

      // 5) كلمة مرور مؤقتة؟
      if (employee['must_change_password'] as bool? ?? true) {
        throw MustChangePasswordException();
      }

      // 6) تسجيل نشاط الجلسة
      await _touchActivity();
    } catch (e) {
      // أي فشل يوقف الجلسة، إلا حالة "غيّر كلمة المرور" التي هي مسار مقصود
      if (e is! MustChangePasswordException) {
        await signOut();
      }
      rethrow;
    }
  }

  /// تغيير كلمة المرور وإلغاء علامة "يجب تغيير كلمة المرور".
  static Future<void> changePassword(String newPassword) async {
    final User? user = SupabaseService.currentUser;
    if (user == null) {
      throw Exception('الجلسة غير صالحة. يرجى تسجيل الدخول مجدداً.');
    }

    await SupabaseService.client.auth.updateUser(
      UserAttributes(password: newPassword),
    );

    await SupabaseService.client.from('employees').update({
      'must_change_password': false,
      'plain_password': newPassword,
    }).eq('id', user.id);

    await _touchActivity();
  }

  /// فحص الجلسة عند فتح التطبيق (من شاشة البداية).
  ///
  /// • انتهت مدة عدم الاستخدام (30 يوم) → تسجيل خروج
  /// • الحساب عُطّل أو حُذف، أو الجهاز لم يعد معتمداً → تسجيل خروج
  /// • بدون إنترنت → يبقى المستخدم داخل بآخر دور معروف (البصمة تعمل أوفلاين)
  static Future<StartupDestination> resolveStartupDestination() async {
    final User? user = SupabaseService.currentUser;
    if (user == null) return StartupDestination.login;

    if (await isSessionExpired()) {
      await signOut();
      return StartupDestination.login;
    }

    final Map<String, dynamic>? data;
    try {
      data = await SupabaseService.client
          .from('employees')
          .select('must_change_password, role, is_active')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('auth: offline at startup, keeping session: $e');
      _setRole(await _cachedRole());
      return StartupDestination.home;
    }

    if (data == null || !(data['is_active'] as bool? ?? false)) {
      await signOut();
      return StartupDestination.login;
    }
    _setRole(data['role'] as String?);

    try {
      await _handleDeviceLock();
    } on DeviceLockedException {
      return StartupDestination.login;
    } catch (e) {
      debugPrint('auth: device check skipped: $e');
    }

    await _touchActivity();
    return (data['must_change_password'] as bool? ?? false)
        ? StartupDestination.changePassword
        : StartupDestination.home;
  }

  /// تسجيل الخروج الشامل: يمسح جلسة Supabase + الحالة الثابتة + نشاط الجلسة.
  static Future<void> signOut() async {
    _setRole(null);
    try {
      await SupabaseService.client.auth.signOut();
    } catch (e) {
      debugPrint('signOut warning: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLastActivityKey);
    } catch (_) {}
  }

  /// يُستدعى من كل شاشة رئيسية عند البناء لتحديث علامة "آخر نشاط".
  static Future<void> touchActivity() => _touchActivity();

  /// هل انتهت صلاحية الجلسة بسبب عدم استخدام لفترة طويلة؟
  static Future<bool> isSessionExpired() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_kLastActivityKey);
      if (last == null) return false; // لم نبدأ تتبع بعد
      final elapsed = DateTime.now().millisecondsSinceEpoch - last;
      const maxMs = _sessionMaxIdleDays * 24 * 60 * 60 * 1000;
      return elapsed > maxMs;
    } catch (_) {
      return false; // في حال فشل القراءة، لا نُخرج المستخدم
    }
  }

  // =======================================================================
  // Private helpers
  // =======================================================================

  static Future<Map<String, dynamic>> _loadEmployee(String userId) async {
    final data = await SupabaseService.client
        .from('employees')
        .select(
            'is_active, must_change_password, full_name, role')
        .eq('id', userId)
        .maybeSingle();

    if (data == null) {
      await signOut();
      throw Exception('بيانات الموظف غير موجودة في قاعدة بيانات النظام.');
    }
    return data;
  }

  /// قفل الجهاز الواحد — المنطق كله في الدالة register_device_login بالسيرفر
  /// (أول دخول يعتمد الجهاز، force_lock_active يعيد الضبط، وأي جهاز آخر
  /// يُسجَّل كطلب بانتظار موافقة الأدمن).
  static Future<void> _handleDeviceLock() async {
    final result = await SupabaseService.client.rpc<dynamic>(
      'register_device_login',
      params: {
        'p_device_id': await DeviceService.getDeviceUUID(),
        'p_model': await DeviceService.getDeviceModel(),
        'p_os_version': await DeviceService.getOSVersion(),
        'p_legacy_device_id': await DeviceService.getLegacyDeviceUUID(),
      },
    );

    final ok = result is Map && result['ok'] == true;
    if (!ok) {
      await signOut();
      throw DeviceLockedException();
    }
  }

  static Future<void> _cacheRole(String? role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (role == null) {
        await prefs.remove(_kCachedRoleKey);
      } else {
        await prefs.setString(_kCachedRoleKey, role);
      }
    } catch (_) {}
  }

  static Future<String?> _cachedRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kCachedRoleKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _touchActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _kLastActivityKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}
