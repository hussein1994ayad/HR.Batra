// =========================================================================
// HR Pro v6.0 — نموذج طلب السلفة (Loan Model)
// =========================================================================
// الجدول المقابل في قاعدة البيانات: public.loans
//
// الحقول:
//   id              UUID    معرف السلفة
//   employee_id     UUID    معرف الموظف
//   amount          NUMERIC مبلغ السلفة بالدينار العراقي
//   reason          TEXT    سبب طلب السلفة
//   status          TEXT    الحالة: 'pending'|'approved'|'rejected'|'paid'
//   monthly_deduct  NUMERIC مبلغ الاستقطاع الشهري من الراتب
//   months          INT     عدد الأشهر للاسترداد
//   paid_months     INT     عدد الأشهر المدفوعة فعلياً
//   approved_by     UUID    معرف المدير الموافق
//   admin_notes     TEXT    ملاحظات المدير
//   created_at      TIMESTAMPTZ تاريخ تقديم الطلب
// =========================================================================

/// يمثّل طلب سلفة مالية.
class LoanModel {
  final String id;
  final String employeeId;

  /// مبلغ السلفة بالدينار العراقي
  final double amount;

  final String reason;

  /// الحالة: 'pending' | 'approved' | 'rejected' | 'paid'
  final String status;

  /// مبلغ الاستقطاع الشهري
  final double? monthlyDeduct;

  /// عدد أشهر الاسترداد
  final int? months;

  /// عدد الأشهر المدفوعة فعلياً
  final int paidMonths;

  final String? approvedBy;
  final String? adminNotes;
  final DateTime? createdAt;

  const LoanModel({
    required this.id,
    required this.employeeId,
    required this.amount,
    required this.reason,
    required this.status,
    this.monthlyDeduct,
    this.months,
    this.paidMonths = 0,
    this.approvedBy,
    this.adminNotes,
    this.createdAt,
  });

  factory LoanModel.fromMap(Map<String, dynamic> map) {
    return LoanModel(
      id:             (map['id'] ?? '') as String,
      employeeId:     (map['employee_id'] ?? '') as String,
      amount:         (map['amount'] as num).toDouble(),
      reason:         (map['reason'] ?? '') as String,
      status:         (map['status'] ?? 'pending') as String,
      monthlyDeduct:  (map['monthly_deduct'] as num?)?.toDouble(),
      months:         map['months'] as int?,
      paidMonths:     (map['paid_months'] as int?) ?? 0,
      approvedBy:     map['approved_by'] as String?,
      adminNotes:     map['admin_notes'] as String?,
      createdAt:      map['created_at'] != null
                          ? DateTime.parse(map['created_at'] as String)
                          : null,
    );
  }

  bool get isPending  => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isPaid     => status == 'paid';

  /// المبلغ المتبقي للاسترداد
  double? get remainingAmount {
    if (monthlyDeduct == null || months == null) return null;
    return (months! - paidMonths) * monthlyDeduct!;
  }
}
