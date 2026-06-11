// =========================================================================
// نظام HR Pro v6.0 - خدمة المصادقة وأمن الجلسات (Authentication & Security Service)
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'device_service.dart';

/// استثناء خاص بالحسابات المعطلة
class InactiveAccountException implements Exception {
  final String message = 'هذا الحساب معطل حالياً. يرجى مراجعة إدارة الموارد البشرية لتفعيله.';
  @override
  String toString() => message;
}

/// استثناء خاص بمحاولة تسجيل الدخول من جهاز غير معتمد (قفل الجهاز الواحد)
class DeviceLockedException implements Exception {
  final String message = 'لا يمكن تسجيل الدخول من هذا الجهاز. هذا الحساب مقفل ومصرح به لجهاز آخر معتمد فقط. تم تسجيل هذه المحاولة كخرق أمني.';
  @override
  String toString() => message;
}

/// استثناء يطالب الموظف بضرورة تغيير كلمة المرور المؤقتة
class MustChangePasswordException implements Exception {
  final String message = 'يجب عليك تغيير كلمة المرور المؤقتة الممنوحة لك قبل التمكن من تصفح النظام.';
  @override
  String toString() => message;
}

/// خدمة لإدارة عمليات تسجيل الدخول والتحقق الأمني الشامل
class AuthService {
  
  /// التحقق من بيانات الدخول وتأمين حماية الحساب
  static Future<void> signIn(String email, String password) async {
    // 1. تسجيل الدخول عبر Supabase Auth
    final AuthResponse response = await SupabaseService.client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final User? user = response.user;
    if (user == null) {
      throw Exception('فشل تسجيل الدخول، يرجى التحقق من البريد الإلكتروني وكلمة المرور.');
    }

    try {
      // 2. التحقق من حالة الموظف وفرض كلمة المرور من جدول الموظفين
      final employeeData = await SupabaseService.client
          .from('employees')
          .select('is_active, must_change_password, full_name, device_id_lock')
          .eq('id', user.id)
          .maybeSingle();

      if (employeeData == null) {
        await SupabaseService.signOut();
        throw Exception('بيانات الموظف غير موجودة في قاعدة بيانات النظام.');
      }

      final bool isActive = employeeData['is_active'] ?? false;
      final bool mustChangePassword = employeeData['must_change_password'] ?? true;
      final String fullName = employeeData['full_name'] ?? 'موظف';
      final String? deviceIdLock = employeeData['device_id_lock'];

      // التحقق من تفعيل الحساب
      if (!isActive) {
        await SupabaseService.signOut();
        throw InactiveAccountException();
      }

      // 3. التحقق من قفل الحساب على جهاز واحد (Single-device locking)
      final String deviceUUID = await DeviceService.getDeviceUUID();
      final String deviceModel = await DeviceService.getDeviceModel();
      final String osVersion = await DeviceService.getOSVersion();

      if (deviceIdLock != null && deviceIdLock.isNotEmpty) {
        final List<dynamic> devices = await SupabaseService.client
            .from('employee_devices')
            .select()
            .eq('employee_id', user.id);

        if (devices.isEmpty) {
          // هذا هو الدخول الأول للموظف، نسجل جهازه تلقائياً كجهاز معتمد
          await SupabaseService.client.from('employee_devices').insert({
            'employee_id': user.id,
            'device_id': deviceUUID,
            'model': deviceModel,
            'os_version': osVersion,
            'is_approved': true,
            'approved_at': DateTime.now().toUtc().toIso8601String(),
          });
          
          await SupabaseService.client
              .from('employees')
              .update({'device_id_lock': deviceUUID})
              .eq('id', user.id);
        } else {
          // يوجد جهاز مسجل مسبقاً
          if (deviceIdLock == 'force_lock_active') {
            // مسح أي تسجيلات سابقة
            await SupabaseService.client
                .from('employee_devices')
                .delete()
                .eq('employee_id', user.id);

            // إدخال الجهاز الحالي كجهاز معتمد تلقائياً
            await SupabaseService.client.from('employee_devices').insert({
              'employee_id': user.id,
              'device_id': deviceUUID,
              'model': deviceModel,
              'os_version': osVersion,
              'is_approved': true,
              'approved_at': DateTime.now().toUtc().toIso8601String(),
            });

            // تحديث قفل الجهاز ليكون الجهاز الجديد
            await SupabaseService.client
                .from('employees')
                .update({'device_id_lock': deviceUUID})
                .eq('id', user.id);
          } else {
            // يوجد قفل محدد بجهاز معين
            final registeredDevice = devices.first;
            final String registeredDeviceUUID = registeredDevice['device_id'];
            final bool isApproved = registeredDevice['is_approved'] ?? false;

            if (registeredDeviceUUID != deviceUUID || deviceIdLock != deviceUUID || !isApproved) {
              // محاولة خرق أمني لجهاز آخر أو دخول من جهاز غير معتمد!
              
              // تحقق إذا كان هذا الجهاز قد تم تقديم طلب له مسبقاً لمنع التكرار
              final List<dynamic> existingReq = await SupabaseService.client
                  .from('employee_devices')
                  .select()
                  .eq('employee_id', user.id)
                  .eq('device_id', deviceUUID);

              if (existingReq.isEmpty) {
                // إدراج طلب ربط جهاز جديد غير معتمد ينتظر موافقة الأدمن
                await SupabaseService.client.from('employee_devices').insert({
                  'employee_id': user.id,
                  'device_id': deviceUUID,
                  'model': deviceModel,
                  'os_version': osVersion,
                  'is_approved': false,
                });
              }

              // نقوم بتسجيل إشعار أمني في قاعدة البيانات للأدمن والموظف نفسه
              await SupabaseService.client.from('notifications').insert({
                'employee_id': user.id,
                'title': 'محاولة خرق أمني للدخول ⚠️',
                'body': 'تمت محاولة تسجيل دخول غير مصرح بها إلى حسابك ($fullName) من جهاز جديد ($deviceModel). تم تقديم طلب ربط جهاز جديد وبانتظار موافقة الإدارة.',
                'type': 'device',
              });

              await SupabaseService.signOut();
              throw DeviceLockedException();
            }
          }
        }
      } else {
        // إذا كان قفل الجهاز ملغى (device_id_lock == null)، نسمح بالدخول من أي جهاز ونقوم بتحديث معرف الجهاز المخزن
        final List<dynamic> devices = await SupabaseService.client
            .from('employee_devices')
            .select()
            .eq('employee_id', user.id);

        if (devices.isEmpty || devices.first['device_id'] != deviceUUID) {
          // مسح أي تسجيلات سابقة للماك أو الآي دي القديم
          await SupabaseService.client
              .from('employee_devices')
              .delete()
              .eq('employee_id', user.id);

          // إدخال الجهاز الحالي كجهاز افتراضي
          await SupabaseService.client.from('employee_devices').insert({
            'employee_id': user.id,
            'device_id': deviceUUID,
            'model': deviceModel,
            'os_version': osVersion,
            'is_approved': true,
            'approved_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      }

      // 4. التحقق من فرض تغيير كلمة المرور المؤقتة
      if (mustChangePassword) {
        throw MustChangePasswordException();
      }

    } catch (e) {
      // في حال حدوث أي استثناء، نضمن تسجيل الخروج التام لحماية الجلسة
      if (e is! MustChangePasswordException) {
        await SupabaseService.signOut();
      }
      rethrow;
    }
  }

  /// تغيير كلمة المرور للموظف وإلغاء حالة الفرض بعد النجاح
  static Future<void> changePassword(String newPassword) async {
    final User? user = SupabaseService.currentUser;
    if (user == null) {
      throw Exception('الجلسة غير صالحة. يرجى تسجيل الدخول مجدداً.');
    }

    // 1. تحديث كلمة المرور في Supabase Auth
    await SupabaseService.client.auth.updateUser(
      UserAttributes(password: newPassword),
    );

    // 2. تحديث حالة الموظف في جدول الموظفين
    await SupabaseService.client
        .from('employees')
        .update({'must_change_password': false})
        .eq('id', user.id);
  }

  /// التحقق من حالة الموظف الحالية (هل يجب تغيير كلمة المرور؟)
  static Future<bool> checkMustChangePassword() async {
    final User? user = SupabaseService.currentUser;
    if (user == null) return false;

    final data = await SupabaseService.client
        .from('employees')
        .select('must_change_password')
        .eq('id', user.id)
        .maybeSingle();

    return data?['must_change_password'] ?? false;
  }
}
