// =========================================================================
// موظف بقوائم الإدارة والاختيار (اختيار مستلمي التعميم، فلاتر تقرير الحضور...).
// الحقول nullable كما تصل؛ كل شاشة تعرض بديلها.
// =========================================================================

import '../utils/json_map.dart';

class EmployeeRef {
  final String id;
  final String? fullName;
  final String? employeeCode;
  final String? branchId;
  final String? departmentId;

  /// تاريخ المباشرة (عمود DATE).
  final DateTime? joinDate;

  /// null إذا العمود ما انطلب.
  final bool? isActive;

  const EmployeeRef({required this.id, this.fullName, this.employeeCode, this.branchId, this.departmentId, this.joinDate, this.isActive});

  factory EmployeeRef.fromMap(JsonRow map) => EmployeeRef(
        id: map['id'] as String,
        fullName: map.str('full_name'),
        employeeCode: map.str('employee_code'),
        branchId: map.str('branch_id'),
        departmentId: map.str('department_id'),
        joinDate: DateTime.tryParse((map['join_date'] ?? '').toString()),
        isActive: map.boolean('is_active'),
      );
}
