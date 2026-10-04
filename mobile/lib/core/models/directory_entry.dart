// =========================================================================
// زميل بدليل الموظفين — من الدالة get_employee_directory (أعمدة غير حساسة فقط).
// الحقول nullable كما تصل؛ كل شاشة تعرض بديلها الخاص ('—'، 'القسم العام'، ...).
// =========================================================================

import '../utils/json_map.dart';

class DirectoryEntry {
  final String? fullName;
  final String? phone;
  final String? email;

  /// 'admin' | 'manager' | 'employee'
  final String? role;
  final String? avatarUrl;
  final String? employeeCode;
  final String? branchName;
  final String? departmentName;

  /// روابط الوثائق (تظهر للأدمن فقط).
  final List<String> documentUrls;

  const DirectoryEntry({
    this.fullName,
    this.phone,
    this.email,
    this.role,
    this.avatarUrl,
    this.employeeCode,
    this.branchName,
    this.departmentName,
    this.documentUrls = const [],
  });

  factory DirectoryEntry.fromMap(JsonRow map) => DirectoryEntry(
        fullName: map.str('full_name'),
        phone: map.str('phone'),
        email: map.str('email'),
        role: map.str('role'),
        avatarUrl: map.str('avatar_url'),
        employeeCode: map.str('employee_code'),
        branchName: map.str('branch_name'),
        departmentName: map.str('department_name'),
        documentUrls: [for (final u in (map['document_urls'] as List<dynamic>? ?? const [])) u.toString()],
      );
}
