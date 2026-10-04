// =========================================================================
// موظف بشاشة إدارة الموظفين — employees مع employee_devices و branches و departments.
// الحقول nullable كما تصل؛ الشاشة ونافذة الملف تعرض بدائلها ('بدون اسم'، '—'، 'غير محدد'...).
// =========================================================================

import '../utils/json_map.dart';

String? _joinedName(Object? v) => v is Map ? v['name']?.toString() : null;

class ManagedEmployee {
  final String id;
  final String? fullName;
  final String? email;
  final String? employeeCode;

  /// phone_number وإلا phone.
  final String? phone;
  final String? avatarUrl;

  /// 'admin' | 'manager' | 'employee'
  final String? role;

  /// كل شي غير false يُعتبر نشط (نفس شرط الشاشة).
  final bool isActive;
  final num? monthlySalary;
  final String? branchName;
  final String? departmentName;
  final List<String> documentUrls;

  /// عدد الأجهزة المربوطة، وطراز أولها.
  final int deviceCount;
  final String? firstDeviceModel;

  const ManagedEmployee({
    required this.id,
    this.fullName,
    this.email,
    this.employeeCode,
    this.phone,
    this.avatarUrl,
    this.role,
    this.isActive = true,
    this.monthlySalary,
    this.branchName,
    this.departmentName,
    this.documentUrls = const [],
    this.deviceCount = 0,
    this.firstDeviceModel,
  });

  factory ManagedEmployee.fromMap(JsonRow map) {
    final devices = map['employee_devices'] as List<dynamic>? ?? const [];
    return ManagedEmployee(
      id: map.str('id') ?? '',
      fullName: map.str('full_name'),
      email: map.str('email'),
      employeeCode: map.str('employee_code'),
      phone: (map['phone_number'] ?? map['phone'])?.toString(),
      avatarUrl: map.str('avatar_url'),
      role: map.str('role'),
      isActive: map['is_active'] != false,
      monthlySalary: map['monthly_salary_iqd'] as num?,
      branchName: _joinedName(map['branches']),
      departmentName: _joinedName(map['departments']),
      documentUrls: [for (final u in (map['document_urls'] as List<dynamic>? ?? const [])) u.toString()],
      deviceCount: devices.length,
      firstDeviceModel: devices.isEmpty ? null : (devices.first as Map)['model']?.toString(),
    );
  }

  bool get hasDevice => deviceCount > 0;
}
