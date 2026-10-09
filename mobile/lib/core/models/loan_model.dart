// =========================================================================
// نموذج السلفة وأقساطها — الجداول: public.loans و public.loan_installments
// =========================================================================

import '../design/formatters.dart';
import '../utils/json_map.dart';

/// يوم قطع الرواتب (سياسة payroll_policy.cutoff_day).
const int kPayrollCutoffDay = 26;

/// شهر الرواتب اللي يتبعه تاريخ: لحد يوم القطع نفس الشهر، وبعده الشهر الجاي.
DateTime payrollMonthOf(DateTime d) => d.day <= kPayrollCutoffDay ? DateTime(d.year, d.month) : DateTime(d.year, d.month + 1);

class LoanInstallment {
  final String id;
  final String loanId;
  final DateTime dueDate;
  final double amount;
  final bool isPaid;
  final DateTime? paidAt;

  /// 'cash' | 'salary_deduction' | null
  final String? paymentType;
  final String? paymentNote;

  /// 'shortfall' (باقي شهر ما انسدد كامل) | 'postponed' (قسط شهر مؤجّل) | null
  final String? originKind;

  /// الشهر الأصلي للباقي أو المؤجّل.
  final DateTime? originMonth;

  /// مبلغ هالشهر حدده الأدمن (يكدر يدفع أقل هالشهر).
  final bool amountLocked;

  const LoanInstallment({
    required this.id,
    required this.loanId,
    required this.dueDate,
    required this.amount,
    this.isPaid = false,
    this.paidAt,
    this.paymentType,
    this.paymentNote,
    this.originKind,
    this.originMonth,
    this.amountLocked = false,
  });

  factory LoanInstallment.fromMap(JsonRow map) => LoanInstallment(
        id: map.str('id') ?? '',
        loanId: map.str('loan_id') ?? '',
        // due_date عمود DATE؛ يُقرأ كتاريخ محلي بدون تحويل منطقة
        dueDate: DateTime.tryParse(map.str('due_date') ?? '') ?? DateTime(1970),
        amount: map.dbl('amount') ?? 0,
        isPaid: map.boolean('is_paid') ?? false,
        paidAt: map.date('paid_at'),
        paymentType: map.str('payment_type'),
        paymentNote: map.str('payment_note'),
        originKind: map.str('origin_kind'),
        originMonth: DateTime.tryParse(map.str('origin_month') ?? ''),
        amountLocked: map.boolean('amount_locked') ?? false,
      );

  bool get isCash => paymentType == 'cash';

  /// شهر الرواتب اللي ينخصم بيه القسط: بعد يوم القطع (26) = الشهر الجاي (نفس payroll_month_of بالسيرفر).
  DateTime get payrollMonth => payrollMonthOf(dueDate);

  /// ليش هذا القسط موجود: «باقي الشهر العاشر 2026» أو «مؤجّل من الشهر الثاني عشر 2026» أو «مبلغ هالشهر مخفّض» (نفس الموقع).
  String? get originLabel {
    String month(DateTime d) => Fmt.monthOf(payrollMonthOf(d));
    if (originKind == 'shortfall') return originMonth == null ? 'باقي شهر سابق' : 'باقي ${month(originMonth!)}';
    if (originKind == 'postponed') return originMonth == null ? 'مؤجّل' : 'مؤجّل من ${month(originMonth!)}';
    if (amountLocked && !isPaid) return 'مبلغ هالشهر مخفّض';
    return null;
  }
}

class LoanModel {
  final String id;
  final String employeeId;
  final String? employeeName;
  final double? employeeSalary;
  final double amount;
  final double installmentAmount;
  final int installmentCount;
  final double remainingAmount;
  final String? pledgeUrl;

  /// 'pending' | 'approved' | 'rejected'
  final String status;
  final String? rejectionReason;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final List<LoanInstallment> installments;

  const LoanModel({
    required this.id,
    required this.employeeId,
    required this.amount,
    required this.installmentAmount,
    required this.installmentCount,
    required this.remainingAmount,
    required this.status,
    this.employeeName,
    this.employeeSalary,
    this.pledgeUrl,
    this.rejectionReason,
    this.createdAt,
    this.approvedAt,
    this.installments = const [],
  });

  factory LoanModel.fromMap(JsonRow map) {
    final employee = map.obj('employees');
    final installments = map.list('loan_installments').map(LoanInstallment.fromMap).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return LoanModel(
      id: map.str('id') ?? '',
      employeeId: map.str('employee_id') ?? '',
      employeeName: employee?.str('full_name'),
      employeeSalary: employee?.dbl('monthly_salary_iqd'),
      amount: map.dbl('amount') ?? 0,
      installmentAmount: map.dbl('installment_amount') ?? 0,
      installmentCount: map.integer('installment_count') ?? 0,
      remainingAmount: map.dbl('remaining_amount') ?? 0,
      pledgeUrl: map.str('pledge_url'),
      status: map.str('status') ?? 'pending',
      rejectionReason: map.str('rejection_reason'),
      createdAt: map.date('created_at'),
      approvedAt: map.date('approved_at'),
      installments: installments,
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  /// سلفة معتمدة لم يكتمل سدادها.
  bool get isActive => isApproved && remainingAmount > 0;

  double get paidAmount => amount - remainingAmount;

  List<LoanInstallment> get unpaidInstallments => installments.where((i) => !i.isPaid).toList();

  LoanInstallment? get nextInstallment {
    final unpaid = unpaidInstallments;
    return unpaid.isEmpty ? null : unpaid.first;
  }
}

/// موظف في قائمة اختيار المستفيد.
class LoanEmployeeOption {
  final String id;
  final String fullName;
  final String? branchName;
  final double? monthlySalary;

  const LoanEmployeeOption({required this.id, required this.fullName, this.branchName, this.monthlySalary});

  factory LoanEmployeeOption.fromMap(JsonRow map) => LoanEmployeeOption(
        id: map.str('id') ?? '',
        fullName: map.str('full_name') ?? 'بدون اسم',
        branchName: map.obj('branches')?.str('name'),
        monthlySalary: map.dbl('monthly_salary_iqd'),
      );
}

/// سلفة مع بيانات موظفها المعروضة في شاشة المتابعة.
class LoanRecord {
  final LoanModel loan;
  final String? avatarUrl;
  final String? branchId;
  final String branchName;
  final String departmentName;
  final String? notes;

  const LoanRecord({
    required this.loan,
    this.avatarUrl,
    this.branchId,
    this.branchName = 'الفرع الرئيسي',
    this.departmentName = 'عام',
    this.notes,
  });

  factory LoanRecord.fromMap(JsonRow map) {
    final emp = map.obj('employees');
    return LoanRecord(
      loan: LoanModel.fromMap(map),
      avatarUrl: emp?.str('avatar_url'),
      branchId: emp?.str('branch_id'),
      branchName: emp?.obj('branches')?.str('name') ?? 'الفرع الرئيسي',
      departmentName: emp?.obj('departments')?.str('name') ?? 'عام',
      notes: map.str('notes'),
    );
  }
}
