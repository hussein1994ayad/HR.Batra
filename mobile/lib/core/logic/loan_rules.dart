// =========================================================================
// تصفية سجل السلف وإحصاءاته — دوال نقية
// =========================================================================

import '../models/loan_model.dart';

enum LoanStatusFilter { all, active, completed, pending }

/// تصفية حسب الاسم والفرع والحالة (نشطة = معتمدة وعليها متبقي).
List<LoanRecord> filterLoans(
  List<LoanRecord> records, {
  String query = '',
  String branchId = 'all',
  LoanStatusFilter status = LoanStatusFilter.all,
}) {
  final q = query.trim().toLowerCase();
  return records.where((r) {
    final loan = r.loan;
    if (q.isNotEmpty && !(loan.employeeName ?? '').toLowerCase().contains(q)) return false;
    if (branchId != 'all' && r.branchId != branchId) return false;
    switch (status) {
      case LoanStatusFilter.active:
        return loan.isActive;
      case LoanStatusFilter.completed:
        return loan.isApproved && loan.remainingAmount <= 0;
      case LoanStatusFilter.pending:
        return loan.isPending;
      case LoanStatusFilter.all:
        return true;
    }
  }).toList();
}

class LoanKpis {
  final double total;
  final double paid;
  final double remaining;
  final int activeCount;

  const LoanKpis({this.total = 0, this.paid = 0, this.remaining = 0, this.activeCount = 0});

  /// إجمالي السلف المعتمدة في الفرع المختار.
  factory LoanKpis.of(List<LoanRecord> records, {String branchId = 'all'}) {
    double total = 0;
    double remaining = 0;
    int active = 0;
    for (final r in records) {
      if (branchId != 'all' && r.branchId != branchId) continue;
      if (!r.loan.isApproved) continue;
      total += r.loan.amount;
      remaining += r.loan.remainingAmount;
      if (r.loan.isActive) active++;
    }
    final paid = total - remaining;
    return LoanKpis(total: total, paid: paid > 0 ? paid : 0, remaining: remaining, activeCount: active);
  }
}

/// نسبة السداد بين 0 و 1.
double loanProgress(LoanModel loan) => loan.amount > 0 ? (loan.paidAmount / loan.amount).clamp(0.0, 1.0) : 0.0;
