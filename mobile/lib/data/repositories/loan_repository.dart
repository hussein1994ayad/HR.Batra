// =========================================================================
// سلف الموظفين: السجل الكامل للإدارة، ومنح سلفة مباشرة، وطلبات الموظف نفسه وإلغاؤها
// =========================================================================

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/models.dart';
import '../../core/services/file_upload_service.dart';
import '../../core/services/supabase_service.dart';

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
    final results = await Future.wait<Object?>([
      _db.from('branches').select('id, name').order('name'),
      _db
          .from('employees')
          .select('id, full_name, monthly_salary_iqd, branch_id, branches(name)')
          .eq('is_active', true)
          .order('full_name'),
      _db.from('loans').select('''
            *,
            employees!loans_employee_id_fkey(
              id, full_name, avatar_url, monthly_salary_iqd, branch_id, department_id,
              branches(name),
              departments!employees_department_id_fkey(name)
            ),
            loan_installments(*)
          ''').order('created_at', ascending: false),
    ]);
    return LoansOverview(
      branches: rowsOf(results[0]).map(BranchModel.fromMap).toList(),
      employees: rowsOf(results[1]).map(LoanEmployeeOption.fromMap).toList(),
      loans: rowsOf(results[2]).map(LoanRecord.fromMap).toList(),
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
  Future<List<Map<String, dynamic>>> fetchMyLoans(String userId) async {
    final data = await _db.from('loans').select('*, loan_installments(*)').eq('employee_id', userId).order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  /// راتب الموظف الشهري (لتنبيه القسط فوق نص الراتب أو فوق الراتب كله).
  Future<double?> fetchMySalary(String userId) async {
    final me = await _db.from('employees').select('monthly_salary_iqd').eq('id', userId).maybeSingle();
    return (me?['monthly_salary_iqd'] as num?)?.toDouble();
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
