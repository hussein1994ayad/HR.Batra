// كشف السلفة ملف Excel: ينزل تلقائياً قبل حذف السلفة المسددة (الحذف يمسح الأقساط وتواريخ الدفع)،
// حتى يبقى عندك إثبات إذا صار نزاع. الرواتب القديمة ما تتأثر بالحذف (مبلغ القسط محفوظ بالكشف نفسه).

import * as XLSX from 'xlsx';
import type { Loan, SettledLoan } from '@/lib/db-types';
import { installmentOrigin, loanRef, monthLabel, paidAmount, sortInstallments } from './logic';
import { payrollMonthName } from '@/features/payroll/period';

/** صفوف كشف السلفة (مفصولة عن الملف حتى تنفحص). */
export function loanStatementRows(loan: Loan) {
  const summary = [
    { 'البند': 'رقم السلفة', 'القيمة': loanRef(loan.loan_no) },
    { 'البند': 'الموظف', 'القيمة': loan.employees?.full_name ?? '' },
    { 'البند': 'مبلغ السلفة (د.ع)', 'القيمة': Number(loan.amount) },
    { 'البند': 'القسط الشهري (د.ع)', 'القيمة': Number(loan.installment_amount) },
    { 'البند': 'عدد الأقساط', 'القيمة': loan.loan_installments?.length ?? loan.installment_count },
    { 'البند': 'المسدد (د.ع)', 'القيمة': paidAmount(loan) },
    { 'البند': 'الباقي (د.ع)', 'القيمة': Number(loan.remaining_amount) },
    { 'البند': 'تاريخ الاعتماد', 'القيمة': loan.approved_at ? loan.approved_at.slice(0, 10) : '' },
    { 'البند': 'تاريخ استخراج الكشف', 'القيمة': new Date().toISOString().slice(0, 10) },
  ];
  const installments = sortInstallments(loan.loan_installments).map((inst, i) => ({
    'ت': i + 1,
    'يستقطع من': `رواتب ${monthLabel(inst.due_date)}`,
    'تاريخ الاستحقاق': inst.due_date,
    'المبلغ (د.ع)': Number(inst.amount),
    'الحالة': inst.is_paid ? 'مسدد' : 'غير مسدد',
    'طريقة السداد': !inst.is_paid ? '' : inst.paid_by_slip_id ? 'خصم من الراتب' : inst.payment_type === 'cash' ? 'نقداً' : 'مسدد',
    'تاريخ السداد': inst.paid_at ? inst.paid_at.slice(0, 10) : '',
    'ملاحظة': [installmentOrigin(inst), inst.payment_note].filter(Boolean).join(' · '),
  }));
  return { summary, installments };
}

export function loanStatementFileName(loan: Loan): string {
  const name = (loan.employees?.full_name ?? 'موظف').trim().replace(/[\\/:*?"<>|\s]+/g, '_');
  return `كشف_سلفة_${name}_${(loan.approved_at ?? loan.created_at ?? '').slice(0, 10)}.xlsx`;
}

/** ينزّل كشف السلفة (ملخص + الأقساط). يرمي إذا فشل، حتى ما تنحذف السلفة بدون كشف. */
export function downloadLoanStatement(loan: Loan): void {
  const { summary, installments } = loanStatementRows(loan);
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(summary), 'ملخص السلفة');
  XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(installments), 'الأقساط');
  XLSX.writeFile(wb, loanStatementFileName(loan));
}

/** صفوف كشف سلفة مؤرشفة من سجلها الدائم (settled_loans). */
export function settledLoanRows(loan: SettledLoan) {
  const summary = [
    { 'البند': 'رقم السلفة', 'القيمة': loanRef(loan.loan_no) },
    { 'البند': 'الموظف', 'القيمة': loan.employee_name },
    { 'البند': 'كود الموظف', 'القيمة': loan.employee_code ?? '' },
    { 'البند': 'مبلغ السلفة (د.ع)', 'القيمة': Number(loan.amount) },
    { 'البند': 'مجموع المستقطع (د.ع)', 'القيمة': Number(loan.total_deducted) },
    { 'البند': 'الرصيد النهائي (د.ع)', 'القيمة': Number(loan.final_balance) },
    { 'البند': 'تاريخ الاعتماد', 'القيمة': loan.approved_at ? loan.approved_at.slice(0, 10) : '' },
    { 'البند': 'تاريخ التسوية', 'القيمة': loan.settled_at.slice(0, 10) },
    { 'البند': 'تاريخ الأرشفة', 'القيمة': loan.archived_at.slice(0, 10) },
  ];
  const installments = loan.installments.map((inst, i) => ({
    'ت': i + 1,
    'رواتب': payrollMonthName(inst.payroll_month),
    'تاريخ الاستحقاق': inst.due_date,
    'المبلغ (د.ع)': Number(inst.amount),
    'طريقة السداد': inst.method === 'salary' ? 'خصم من الراتب' : 'نقداً',
    'تاريخ السداد': inst.paid_at ? inst.paid_at.slice(0, 10) : '',
    'ملاحظة': inst.note ?? '',
  }));
  return { summary, installments };
}

/** ينزّل كشف سلفة مؤرشفة من سجلها الدائم. */
export function downloadSettledLoanStatement(loan: SettledLoan): void {
  const { summary, installments } = settledLoanRows(loan);
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(summary), 'ملخص السلفة');
  XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(installments), 'الاستقطاعات');
  const name = loan.employee_name.trim().replace(/[\\/:*?"<>|\s]+/g, '_');
  XLSX.writeFile(wb, `كشف_سلفة_${loanRef(loan.loan_no)}_${name}.xlsx`);
}
