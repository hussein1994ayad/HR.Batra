// منطق دليل الموظفين بدون واجهة: قائمة الفروع للفلتر، والبحث العربي مع فلتر الفرع.

import '../../../core/utils/arabic_format.dart';

/// 'all' أولاً ثم أسماء الفروع غير الفارغة بدون تكرار.
List<String> directoryBranchOptions(List<Map<String, dynamic>> list) =>
    {'all', ...list.map((e) => (e['branch_name'] ?? '').toString()).where((b) => b.isNotEmpty)}.toList();

/// البحث (الاسم، القسم، الفرع، الرقم الوظيفي، الهاتف، البريد) مع تسوية الحروف العربية، وفلتر الفرع.
List<Map<String, dynamic>> filterDirectory(List<Map<String, dynamic>> all, {required String query, required String branch}) {
  final normalizedQuery = normalizeArabicForSearch(query);
  return all.where((emp) {
    // تصفية الفرع
    if (branch != 'all' && (emp['branch_name'] ?? '') != branch) {
      return false;
    }

    // إذا كان البحث فارغاً، يظهر جميع الموظفين في الفرع
    if (normalizedQuery.isEmpty) return true;

    final name = normalizeArabicForSearch((emp['full_name'] ?? '') as String);
    final dept = normalizeArabicForSearch((emp['department_name'] ?? '') as String);
    final branchName = normalizeArabicForSearch((emp['branch_name'] ?? '') as String);
    final code = (emp['employee_code'] ?? '').toString().toLowerCase();
    final phone = (emp['phone'] ?? '').toString();
    final email = (emp['email'] ?? '').toString().toLowerCase();

    return name.contains(normalizedQuery) ||
        dept.contains(normalizedQuery) ||
        branchName.contains(normalizedQuery) ||
        code.contains(normalizedQuery) ||
        phone.contains(query) ||
        email.contains(query.toLowerCase());
  }).toList();
}
