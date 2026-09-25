// =========================================================================
// نموذج الموظف — الجدول: public.employees
// =========================================================================

import '../utils/json_map.dart';

class EmployeeModel {
  final String id;
  final String employeeCode;
  final String fullName;
  final String? email;
  final String? phone;

  /// 'employee' | 'manager' | 'admin'
  final String role;
  final String? branchId;
  final String? branchName;
  final String? departmentId;
  final String? departmentName;
  final String? avatarUrl;
  final double? monthlySalary;
  final double? futureSalary;
  final String? futureSalaryMonth;
  final DateTime? joinDate;
  final bool isActive;
  final String? deviceIdLock;
  final bool mustChangePassword;
  final List<String> documentUrls;
  final DateTime? createdAt;

  const EmployeeModel({
    required this.id,
    required this.fullName,
    this.employeeCode = '',
    this.email,
    this.phone,
    this.role = 'employee',
    this.branchId,
    this.branchName,
    this.departmentId,
    this.departmentName,
    this.avatarUrl,
    this.monthlySalary,
    this.futureSalary,
    this.futureSalaryMonth,
    this.joinDate,
    this.isActive = true,
    this.deviceIdLock,
    this.mustChangePassword = false,
    this.documentUrls = const [],
    this.createdAt,
  });

  factory EmployeeModel.fromMap(JsonRow map) {
    final docs = map['document_urls'];
    return EmployeeModel(
      id: map.str('id') ?? '',
      employeeCode: map.str('employee_code') ?? '',
      fullName: map.str('full_name') ?? 'موظف',
      email: map.str('email'),
      phone: map.str('phone') ?? map.str('phone_number'),
      role: map.str('role') ?? 'employee',
      branchId: map.str('branch_id'),
      branchName: map.obj('branches')?.str('name'),
      departmentId: map.str('department_id'),
      departmentName: map.obj('departments')?.str('name'),
      avatarUrl: map.str('avatar_url'),
      monthlySalary: map.dbl('monthly_salary_iqd'),
      futureSalary: map.dbl('future_salary_iqd'),
      futureSalaryMonth: map.str('future_salary_month'),
      joinDate: DateTime.tryParse(map.str('join_date') ?? ''),
      isActive: map.boolean('is_active') ?? true,
      deviceIdLock: map.str('device_id_lock'),
      mustChangePassword: map.boolean('must_change_password') ?? false,
      documentUrls: docs is List ? docs.whereType<String>().toList() : const [],
      createdAt: map.date('created_at'),
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isManager => role == 'manager';
  bool get isDeviceLocked => deviceIdLock != null;
  String get initials => fullName.isNotEmpty ? fullName[0] : '؟';

  String get roleArabic {
    switch (role) {
      case 'admin':
        return 'مدير عام';
      case 'manager':
        return 'مدير موارد';
      default:
        return 'موظف';
    }
  }
}
