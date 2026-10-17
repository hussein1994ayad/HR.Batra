// =========================================================================
// الراتب ما ينقرا من جدول الموظفين مباشرة (تدقيق 14/10/2026، BUG-005)
// =========================================================================
// القاعدة تمنع أعمدة الراتب عن أي مستخدم. الأدمن يقراها من get_employee_pay، والموظف راتبه هو بس،
// والمدير ما يوصله شي. الشاشات تبقى تقرا 'monthly_salary_iqd' من نفس السطر بعد ما ينضاف هنا.
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/json_map.dart';

/// أعمدة الموظف المسموح قراءتها مباشرة (كل شي غير الراتب). نفس القائمة بملف القاعدة 20261018000000
/// (fcm_token انحذف بالمرحلة 10؛ رمز الإشعارات بـ fcm_tokens).
const String kEmployeeColumns =
    'id, employee_code, full_name, phone, email, avatar_url, is_active, role, department_id, branch_id, created_at, '
    'must_change_password, device_id_lock, document_urls, join_date, termination_date';

const _payKeys = ['monthly_salary_iqd', 'future_salary_iqd', 'future_salary_month'];

/// رواتب الموظفين (employee_id → أعمدة الراتب). بدون [ids] = كل اللي يحق للمستخدم يشوفهم.
Future<Map<String, JsonRow>> fetchEmployeePay(SupabaseClient db, {List<String>? ids}) async {
  List<JsonRow> rows;
  try {
    rows = rowsOf(await db.rpc<dynamic>('get_employee_pay', params: {'p_employee_ids': ?ids}));
  } on PostgrestException catch (e) {
    // سيرفر قبل تحديث 20261018000000 (الدالة بعدها ما موجودة): الراتب ينقرا مباشرة مثل قبل
    if (e.code != 'PGRST202') rethrow;
    var query = db.from('employees').select('id, ${_payKeys.join(', ')}');
    if (ids != null) query = query.inFilter('id', ids);
    rows = [for (final r in rowsOf(await query)) {...r, 'employee_id': r['id']}];
  }
  return {
    for (final r in rows)
      if (r.str('employee_id') != null) r.str('employee_id')!: {for (final k in _payKeys) k: r[k]},
  };
}

/// نسخة من [row] مع راتب صاحبها (إذا مسموح). [idKey] = عمود رقم الموظف بالسطر.
JsonRow withPay(JsonRow row, Map<String, JsonRow> pay, {String idKey = 'id'}) {
  final p = pay[row[idKey]?.toString()];
  return p == null ? row : {...row, ...p};
}
