// =========================================================================
// كشوف رواتب الموظف: سياسة الدورة المالية، الكشوف المعتمدة، مسير الشهر الحالي،
// وتفاصيل كل كشف (أسطر المحرّك أو المكافآت والخصومات للكشوف القديمة).
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';

/// اسم الموظف وفرعه لترويسة الـ PDF.
class PayslipOwner {
  const PayslipOwner({this.fullName, required this.branchName});
  final String? fullName;

  /// '' إذا الموظف بلا فرع.
  final String branchName;
}

class PayslipsData {
  const PayslipsData({required this.slips, this.owner});
  final List<SalarySlipModel> slips;

  /// null إذا ما رجع صف الموظف.
  final PayslipOwner? owner;
}

class PayslipsRepository {
  PayslipsRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// صف إعداد payroll_policy (قيمته فيها cycle_start_day و cycle_end_day).
  Future<Map<String, dynamic>?> fetchPayrollPolicy() {
    return _db.from('system_settings').select('value').eq('key', 'payroll_policy').maybeSingle();
  }

  /// الكشوف المعتمدة (الأحدث أولاً) واسم الموظف وفرعه — بالتوازي.
  Future<PayslipsData> fetchSlipsAndProfile(String userId) async {
    final results = await Future.wait([
      _db.from('salary_slips').select().eq('employee_id', userId).eq('status', 'published').order('work_month', ascending: false),
      _db.from('employees').select('full_name, branch_id, branches(name)').eq('id', userId).maybeSingle(),
    ]);
    final me = rowOf(results[1]);
    final branches = me?['branches'];
    return PayslipsData(
      slips: rowsOf(results[0]).map(SalarySlipModel.fromMap).toList(),
      owner: me == null ? null : PayslipOwner(fullName: me.str('full_name'), branchName: branches is Map ? (branches['name'] ?? '').toString() : ''),
    );
  }

  /// مسير الشهر الحالي قبل الاعتماد؛ null إذا الدالة ما رجعت كائن.
  Future<PayrollPreview?> fetchPayrollPreview() async {
    final p = await _db.rpc<dynamic>('get_my_payroll_preview');
    return p is Map ? PayrollPreview.fromMap(Map<String, dynamic>.from(p)) : null;
  }

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
