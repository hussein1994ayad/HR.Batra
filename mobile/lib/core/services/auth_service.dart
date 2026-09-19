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

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'device_service.dart';
import '../providers/app_container.dart';
import '../providers/auth_provider.dart';
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

  /// الدور الحالي للمستخدم — مقروء من قِبل الـ Router والشاشات.
  /// يُمسح إلى null عند تسجيل الخروج أو انتهاء الجلسة.
  static String? currentUserRole;

  /// Set the current role in both the static field (backward-compat) and
  /// the Riverpod provider (source of truth for widgets).
  static void _setRole(String? role) {
    currentUserRole = role;
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
      await _handleDeviceLock(
        userId: user.id,
        fullName: employee['full_name'] as String? ?? 'موظف',
        deviceIdLock: employee['device_id_lock'] as String?,
      );

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

  /// هل يجب على المستخدم الحالي تغيير كلمة المرور؟
  /// (يُحدّث currentUserRole في نفس الاستدعاء).
  static Future<bool> checkMustChangePassword() async {
    final User? user = SupabaseService.currentUser;
    if (user == null) return false;

    final data = await SupabaseService.client
        .from('employees')
        .select('must_change_password, role')
        .eq('id', user.id)
        .maybeSingle();

    if (data != null) {
      _setRole(data['role'] as String?);
    }
    return (data?['must_change_password'] as bool?) ?? false;
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
      final maxMs = _sessionMaxIdleDays * 24 * 60 * 60 * 1000;
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
            'is_active, must_change_password, full_name, device_id_lock, role')
        .eq('id', userId)
        .maybeSingle();

    if (data == null) {
      await signOut();
      throw Exception('بيانات الموظف غير موجودة في قاعدة بيانات النظام.');
    }
    return data;
  }

  /// منطق قفل الجهاز الواحد — أربع حالات، كل واحدة معلّقة بوضوح.
  static Future<void> _handleDeviceLock({
    required String userId,
    required String fullName,
    required String? deviceIdLock,
  }) async {
    final deviceUUID = await DeviceService.getDeviceUUID();
    final deviceModel = await DeviceService.getDeviceModel();
    final osVersion = await DeviceService.getOSVersion();

    // -------------------------------------------------------------------
    // الحالة 1: القفل معطّل (deviceIdLock == null|empty)
    // → الدخول مفتوح من أي جهاز، ونسجّل الجهاز الحالي كافتراضي.
    // -------------------------------------------------------------------
    if (deviceIdLock == null || deviceIdLock.isEmpty) {
      await _replaceDeviceRecord(
          userId, deviceUUID, deviceModel, osVersion);
      return;
    }

    final devices = await SupabaseService.client
        .from('employee_devices')
        .select()
        .eq('employee_id', userId);

    // -------------------------------------------------------------------
    // الحالة 2: أول دخول (deviceIdLock موجود لكن لا سجل أجهزة)
    // → نعتمد هذا الجهاز تلقائياً كجهاز الموظف الرسمي.
    // -------------------------------------------------------------------
    if (devices.isEmpty) {
      await _insertDevice(userId, deviceUUID, deviceModel, osVersion,
          approved: true);
      await SupabaseService.client
          .from('employees')
          .update({'device_id_lock': deviceUUID}).eq('id', userId);
      return;
    }

    // -------------------------------------------------------------------
    // الحالة 3: الأدمن فعّل "force_lock_active" لإعادة الضبط
    // → نحذف كل الأجهزة القديمة ونعتمد الجهاز الحالي.
    // -------------------------------------------------------------------
    if (deviceIdLock == 'force_lock_active') {
      await SupabaseService.client
          .from('employee_devices')
          .delete()
          .eq('employee_id', userId);
      await _insertDevice(userId, deviceUUID, deviceModel, osVersion,
          approved: true);
      await SupabaseService.client
          .from('employees')
          .update({'device_id_lock': deviceUUID}).eq('id', userId);
      return;
    }

    // -------------------------------------------------------------------
    // الحالة 4: قفل على جهاز محدد
    // → نفحص إن كان الجهاز الحالي هو نفسه المعتمد. إن لم يكن:
    //   • نسجّل طلب "جهاز جديد" ينتظر موافقة الأدمن
    //   • ننشئ إشعار خرق أمني
    //   • نرمي DeviceLockedException
    // -------------------------------------------------------------------
    final registered = devices.first;
    final registeredUUID = registered['device_id'] as String?;
    final isApproved = registered['is_approved'] as bool? ?? false;

    final matches = registeredUUID == deviceUUID &&
        deviceIdLock == deviceUUID &&
        isApproved;

    if (matches) return; // كل شي تمام

    // خرق محتمل — نسجّل ونرمي استثناء
    await _recordSecurityBreach(
      userId: userId,
      fullName: fullName,
      deviceUUID: deviceUUID,
      deviceModel: deviceModel,
      osVersion: osVersion,
    );
    await signOut();
    throw DeviceLockedException();
  }

  static Future<void> _replaceDeviceRecord(String userId, String uuid,
      String model, String os) async {
    final devices = await SupabaseService.client
        .from('employee_devices')
        .select()
        .eq('employee_id', userId);
    if (devices.isEmpty || devices.first['device_id'] != uuid) {
      await SupabaseService.client
          .from('employee_devices')
          .delete()
          .eq('employee_id', userId);
      await _insertDevice(userId, uuid, model, os, approved: true);
    }
  }

  static Future<void> _insertDevice(
      String userId, String uuid, String model, String os,
      {required bool approved}) async {
    await SupabaseService.client.from('employee_devices').insert({
      'employee_id': userId,
      'device_id': uuid,
      'model': model,
      'os_version': os,
      'is_approved': approved,
      if (approved)
        'approved_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> _recordSecurityBreach({
    required String userId,
    required String fullName,
    required String deviceUUID,
    required String deviceModel,
    required String osVersion,
  }) async {
    // سجّل طلب جهاز جديد (فقط لو ما موجود)
    final existing = await SupabaseService.client
        .from('employee_devices')
        .select()
        .eq('employee_id', userId)
        .eq('device_id', deviceUUID);

    if (existing.isEmpty) {
      await _insertDevice(userId, deviceUUID, deviceModel, osVersion,
          approved: false);
    }

    // إشعار أمني للأدمن والموظف
    await SupabaseService.client.from('notifications').insert({
      'employee_id': userId,
      'title': 'محاولة خرق أمني للدخول ⚠️',
      'body':
          'تمت محاولة تسجيل دخول غير مصرح بها إلى حسابك ($fullName) من جهاز جديد ($deviceModel). '
              'تم تقديم طلب ربط جهاز جديد وبانتظار موافقة الإدارة.',
      'type': 'device',
    });
  }

  static Future<void> _touchActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _kLastActivityKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}
