// =========================================================================
// سلف الموظفين: السجل الكامل للإدارة، ومنح سلفة مباشرة، وطلبات الموظف نفسه وإلغاؤها
// =========================================================================

import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/logic/payroll_settings.dart';
import '../../core/models/models.dart';
import '../../core/services/file_upload_service.dart';
import '../../core/services/supabase_service.dart';
import 'employee_pay.dart';

class LoansOverview {
  final List<LoanRecord> loans;
  final List<BranchModel> branches;
  final List<LoanEmployeeOption> employees;
  const LoansOverview({required this.loans, required this.branches, required this.employees});
}

class LoanRepository {
  LoanRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  Future<LoansOverview> loadOverview() async {
    unawaited(_refreshPayrollSettings());
    final results = await Future.wait<Object?>([
      _db.from('branches').select('id, name').order('name'),
      _db
          .from('employees')
          .select('id, full_name, branch_id, branches(name)')
          .eq('is_active', true)
          .order('full_name'),
      _db.from('loans').select('''
            *,
            employees!loans_employee_id_fkey(
              id, full_name, avatar_url, branch_id, department_id,
              branches(name),
              departments!employees_department_id_fkey(name)
            ),
            loan_installments(*)
          ''').order('created_at', ascending: false),
      // الراتب (لتنبيه القسط فوق نص الراتب) من السيرفر، ما ينقرا بالربط المباشر
      fetchEmployeePay(_db),
    ]);
    final pay = results[3]! as Map<String, JsonRow>;
    return LoansOverview(
      branches: rowsOf(results[0]).map(BranchModel.fromMap).toList(),
      employees: rowsOf(results[1]).map((e) => LoanEmployeeOption.fromMap(withPay(e, pay))).toList(),
      loans: rowsOf(results[2])
          .map((l) => LoanRecord.fromMap({...l, 'employees': withPay(l.obj('employees') ?? const {}, pay)}))
          .toList(),
    );
  }

  /// يرفع صورة التعهد ويرجع رابطها العام.
  Future<String> uploadPledge(String employeeId, File file) {
    final ext = file.path.split('.').last;
    return FileUploadService.uploadFile(
      bucketName: 'loan-pledges',
      remotePath: 'pledges/$employeeId/${const Uuid().v4()}.$ext',
      file: file,
    );
  }

  /// سلفة معتمدة مباشرة مع أقساطها وإشعار الموظف، في معاملة واحدة (create_direct_loan).
  Future<void> createDirectLoan({
    required String employeeId,
    required double amount,
    required int months,
    required DateTime firstDue,
    required String pledgeUrl,
    String? notes,
  }) async {
    await _db.rpc<Object?>('create_direct_loan', params: {
      'p_employee_id': employeeId,
      'p_amount': amount,
      'p_months': months,
      'p_first_due':
          '${firstDue.year}-${firstDue.month.toString().padLeft(2, '0')}-${firstDue.day.toString().padLeft(2, '0')}',
      'p_pledge_url': pledgeUrl,
      'p_notes': notes,
    });
  }

  // ── طلبات الموظف نفسه (شاشة السلف) ──

  /// سلف الموظف مع أقساطها، الأحدث أولاً.
  /// يوم القطع من إعدادات السيرفر (لأسماء أشهر الأقساط). أي خطأ = يبقى آخر يوم معروف.
  Future<void> _refreshPayrollSettings() async {
    try {
      final row = await _db.from('system_settings').select('value').eq('key', 'payroll_policy').maybeSingle();
      PayrollSettings.apply(row?['value']);
    } catch (_) {}
  }

  Future<List<LoanModel>> fetchMyLoans(String userId) async {
    unawaited(_refreshPayrollSettings());
    final data = await _db.from('loans').select('*, loan_installments(*)').eq('employee_id', userId).order('created_at', ascending: false);
    return rowsOf(data).map(LoanModel.fromMap).toList();
  }

  /// راتب الموظف الشهري (لتنبيه القسط فوق نص الراتب أو فوق الراتب كله).
  Future<double?> fetchMySalary(String userId) async {
    final pay = await fetchEmployeePay(_db, ids: [userId]);
    return (pay[userId]?['monthly_salary_iqd'] as num?)?.toDouble();
  }

  /// طلب سلفة جديد (pending). إشعار المدراء يُرسل من قاعدة البيانات (trg_notify_admins_new_loan_request).
  Future<void> submitLoanRequest(Map<String, dynamic> row) async {
    await _db.from('loans').insert(row);
  }

  /// إلغاء طلب سلفة ما زال قيد المراجعة.
  Future<void> cancelMyLoanRequest(Object? loanId) async {
    await _db.rpc<void>('cancel_my_loan_request', params: {'p_loan_id': loanId});
  }
}
