// =========================================================================
// كشوف رواتب الموظف: سياسة الدورة المالية، الكشوف المعتمدة، مسير الشهر الحالي،
// وتفاصيل كل كشف (أسطر المحرّك أو المكافآت والخصومات للكشوف القديمة).
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/supabase_service.dart';

class PayslipsRepository {
  PayslipsRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// صف إعداد payroll_policy (قيمته فيها cycle_start_day و cycle_end_day).
  Future<Map<String, dynamic>?> fetchPayrollPolicy() {
    return _db.from('system_settings').select('value').eq('key', 'payroll_policy').maybeSingle();
  }

  /// [الكشوف المعتمدة (الأحدث أولاً)، اسم الموظف وفرعه] بالتوازي.
  Future<List<dynamic>> fetchSlipsAndProfile(String userId) {
    return Future.wait([
      _db.from('salary_slips').select().eq('employee_id', userId).eq('status', 'published').order('work_month', ascending: false),
      _db.from('employees').select('full_name, branch_id, branches(name)').eq('id', userId).maybeSingle(),
    ]);
  }

  /// مسير الشهر الحالي قبل الاعتماد.
  Future<dynamic> fetchPayrollPreview() => _db.rpc<dynamic>('get_my_payroll_preview');

  /// أسطر كشف محرّك الرواتب حسب التاريخ.
  Future<List<Map<String, dynamic>>> fetchSlipLines(String slipId) async {
    final lines = await _db.from('salary_slip_lines').select().eq('salary_slip_id', slipId).order('event_date', ascending: true);
    return List<Map<String, dynamic>>.from(lines);
  }

  /// المكافآت والخصومات المسجلة للموظف خلال الدورة (للكشوف القديمة).
  Future<List<Map<String, dynamic>>> fetchBonusesDeductions(String userId, {required String start, required String end}) async {
    final data = await _db
        .from('bonuses_deductions')
        .select()
        .eq('employee_id', userId)
        .gte('issue_date', start)
        .lte('issue_date', end)
        .order('issue_date', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }
}
