// =========================================================================
// HR Pro v6.0 — نموذج بيانات الموظف (Employee Model)
// =========================================================================
// الجدول المقابل في قاعدة البيانات: public.employees
//
// الحقول المخزنة في Supabase:
//   id            UUID       المعرف الفريد (مرتبط بـ auth.users)
//   full_name     TEXT       الاسم الكامل بالعربية
//   email         TEXT       البريد الإلكتروني (يُستخدم لتسجيل الدخول)
//   phone         TEXT       رقم الهاتف (اختياري)
//   role          TEXT       الصلاحية: 'employee' | 'admin' | 'superadmin'
//   department    TEXT       اسم القسم (مثال: المحاسبة، المبيعات)
//   branch_id     UUID       معرف الفرع الذي ينتمي له الموظف
//   avatar_url    TEXT       رابط صورة الملف الشخصي (في Supabase Storage)
//   salary        NUMERIC    الراتب الشهري بالدينار العراقي
//   hire_date     DATE       تاريخ التعيين
//   is_active     BOOL       حساب مفعّل أم موقوف
//   device_id     TEXT       معرف الجهاز المقيّد (لنظام قفل الجهاز الواحد)
//   must_change_password BOOL هل يجب تغيير كلمة المرور عند أول دخول؟
//   national_id   TEXT       رقم الهوية الوطنية (للتقارير والرواتب)
//   notes         TEXT       ملاحظات إدارية (اختيارية)
// =========================================================================

/// يمثّل سجل موظف كامل كما يأتي من قاعدة البيانات.
/// استخدم [EmployeeModel.fromMap] لتحويل Map<String,dynamic> من Supabase.
/// استخدم [EmployeeModel.toMap] لإعادة التحويل عند الإدراج أو التحديث.
class EmployeeModel {
  // ─── الحقول ───────────────────────────────────────────────────────────

  /// المعرف الفريد للموظف (UUID من auth.users)
  final String id;

  /// الاسم الكامل بالعربية
  final String fullName;

  /// البريد الإلكتروني
  final String email;

  /// رقم الهاتف (قد يكون فارغاً)
  final String? phone;

  /// الصلاحية: 'employee' | 'admin' | 'superadmin'
  final String role;

  /// اسم القسم
  final String? department;

  /// معرف الفرع التابع له
  final String? branchId;

  /// رابط صورة الملف الشخصي
  final String? avatarUrl;

  /// الراتب الشهري
  final double? salary;

  /// تاريخ التعيين
  final DateTime? hireDate;

  /// هل الحساب مفعّل؟
  final bool isActive;

  /// معرف الجهاز المقيّد (null = غير مقيّد)
  final String? deviceId;

  /// هل يجب تغيير كلمة المرور؟
  final bool mustChangePassword;

  /// رقم الهوية الوطنية
  final String? nationalId;

  /// ملاحظات إدارية
  final String? notes;

  // ─── Constructor ──────────────────────────────────────────────────────

  const EmployeeModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.phone,
    this.department,
    this.branchId,
    this.avatarUrl,
    this.salary,
    this.hireDate,
    this.isActive = true,
    this.deviceId,
    this.mustChangePassword = false,
    this.nationalId,
    this.notes,
  });

  // ─── Factory: من Map (Supabase) إلى Model ────────────────────────────

  /// يحوّل نتيجة استعلام Supabase إلى كائن [EmployeeModel].
  ///
  /// مثال:
  /// ```dart
  /// final data = await SupabaseService.client.from('employees').select().single();
  /// final employee = EmployeeModel.fromMap(data);
  /// ```
  factory EmployeeModel.fromMap(Map<String, dynamic> map) {
    return EmployeeModel(
      id:                  map['id'] as String,
      fullName:            (map['full_name'] ?? map['name'] ?? 'موظف') as String,
      email:               (map['email'] ?? '') as String,
      role:                (map['role'] ?? 'employee') as String,
      phone:               map['phone'] as String?,
      department:          map['department'] as String?,
      branchId:            map['branch_id'] as String?,
      avatarUrl:           map['avatar_url'] as String?,
      salary:              (map['salary'] as num?)?.toDouble(),
      hireDate:            map['hire_date'] != null
                               ? DateTime.tryParse(map['hire_date'] as String)
                               : null,
      isActive:            (map['is_active'] as bool?) ?? true,
      deviceId:            map['device_id'] as String?,
      mustChangePassword:  (map['must_change_password'] as bool?) ?? false,
      nationalId:          map['national_id'] as String?,
      notes:               map['notes'] as String?,
    );
  }

  // ─── toMap: من Model إلى Map (للإرسال لـ Supabase) ───────────────────

  /// يحوّل الكائن إلى Map جاهز للإدراج أو التحديث في Supabase.
  Map<String, dynamic> toMap() {
    return {
      'id':                   id,
      'full_name':            fullName,
      'email':                email,
      'role':                 role,
      if (phone != null)       'phone':       phone,
      if (department != null)  'department':  department,
      if (branchId != null)    'branch_id':   branchId,
      if (avatarUrl != null)   'avatar_url':  avatarUrl,
      if (salary != null)      'salary':      salary,
      if (hireDate != null)    'hire_date':   hireDate!.toIso8601String().split('T')[0],
      'is_active':             isActive,
      if (deviceId != null)    'device_id':   deviceId,
      'must_change_password':  mustChangePassword,
      if (nationalId != null)  'national_id': nationalId,
      if (notes != null)       'notes':       notes,
    };
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  /// هل الموظف مدير؟
  bool get isAdmin => role == 'admin' || role == 'superadmin';

  /// هل الموظف سوبر أدمن؟
  bool get isSuperAdmin => role == 'superadmin';

  /// الحرف الأول من الاسم (للـ Avatar)
  String get initials => fullName.isNotEmpty ? fullName[0] : '؟';

  @override
  String toString() => 'EmployeeModel(id: $id, name: $fullName, role: $role)';
}
