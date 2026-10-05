// منطق دليل الموظفين بدون واجهة: قائمة الفروع للفلتر، والبحث العربي مع فلتر الفرع.

import '../../../core/models/models.dart';
import '../../../core/utils/arabic_format.dart';

/// 'all' أولاً ثم أسماء الفروع غير الفارغة بدون تكرار.
List<String> directoryBranchOptions(List<DirectoryEntry> list) =>
    {'all', ...list.map((e) => e.branchName ?? '').where((b) => b.isNotEmpty)}.toList();

/// البحث (الاسم، القسم، الفرع، الرقم الوظيفي، الهاتف، البريد) مع تسوية الحروف العربية، وفلتر الفرع.
List<DirectoryEntry> filterDirectory(List<DirectoryEntry> all, {required String query, required String branch}) {
  final normalizedQuery = normalizeArabicForSearch(query);
  return all.where((emp) {
    // تصفية الفرع
    if (branch != 'all' && (emp.branchName ?? '') != branch) {
      return false;
    }

    // إذا كان البحث فارغاً، يظهر جميع الموظفين في الفرع
    if (normalizedQuery.isEmpty) return true;

    final name = normalizeArabicForSearch(emp.fullName ?? '');
    final dept = normalizeArabicForSearch(emp.departmentName ?? '');
    final branchName = normalizeArabicForSearch(emp.branchName ?? '');
    final code = (emp.employeeCode ?? '').toLowerCase();
    final phone = emp.phone ?? '';
    final email = (emp.email ?? '').toLowerCase();

    return name.contains(normalizedQuery) ||
        dept.contains(normalizedQuery) ||
        branchName.contains(normalizedQuery) ||
        code.contains(normalizedQuery) ||
        phone.contains(query) ||
        email.contains(query.toLowerCase());
  }).toList();
}
