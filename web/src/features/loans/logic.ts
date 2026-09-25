// =========================================================================
// منطق السلف والأقساط — دوال نقية بدون React أو Supabase
// =========================================================================

import type { Loan, LoanInstallment } from '@/lib/db-types';
import { getLocalDateStr } from '@/lib/dates';
import type { EditLoanDraft, ScheduledInstallment } from './types';

/**
 * يضيف أشهراً لتاريخ YYYY-MM-DD مع تثبيت اليوم على آخر الشهر عند الحاجة
 * (31 كانون الثاني + شهر = 28/29 شباط، وليس 3 آذار كما يفعل Date.setMonth).
 */
export function addMonths(dateStr: string, months: number): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  const target = new Date(Date.UTC(y, m - 1 + months, 1));
  const lastDay = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  target.setUTCDate(Math.min(d, lastDay));
  return target.toISOString().slice(0, 10);
}

/** يقسم المبلغ على عدد الأقساط؛ القسط الأخير يأخذ فرق التقريب حتى يساوي المجموع المبلغ بالضبط. */
export function splitAmount(total: number, count: number): number[] {
  if (count <= 0) return [];
  const base = Math.floor(total / count);
  const amounts = Array<number>(count).fill(base);
  amounts[count - 1] = base + (total - base * count);
  return amounts;
}

/** جدول أقساط شهرية يبدأ من firstDue. */
export function buildInstallmentSchedule(total: number, count: number, firstDue: string): ScheduledInstallment[] {
  return splitAmount(total, count).map((amount, i) => ({ due_date: addMonths(firstDue, i), amount }));
}

/** أول يوم من الشهر القادم (بداية جدولة الأقساط المتبقية عند التعديل). */
export function firstOfNextMonth(now: Date = new Date()): string {
  return getLocalDateStr(new Date(now.getFullYear(), now.getMonth() + 1, 1));
}

/** نفس اليوم من الشهر القادم (تاريخ أول قسط المقترح عند الاعتماد). */
export function sameDayNextMonth(now: Date = new Date()): string {
  return addMonths(getLocalDateStr(now), 1);
}

/** رسالة خطأ إن كانت شروط الاعتماد غير متحققة، أو null. */
export function validateApproval(amount: number, months: number, monthlySalary: number): string | null {
  if (!(amount > 0) || !(months > 0)) return 'يرجى إدخال مبلغ وعدد أشهر سداد أكبر من الصفر.';
  if (monthlySalary > 0 && Math.floor(amount / months) > monthlySalary * 0.5) {
    return 'مبلغ القسط يتجاوز 50% من راتب الموظف. يرجى زيادة مدة السداد أو تقليل المبلغ.';
  }
  return null;
}

/** الأقساط مرتبة حسب تاريخ الاستحقاق (نسخة جديدة؛ لا تعدّل مصفوفة الحالة). */
export function sortInstallments(installments: LoanInstallment[] | null | undefined): LoanInstallment[] {
  return [...(installments ?? [])].sort((a, b) => a.due_date.localeCompare(b.due_date));
}

export function nextUnpaidInstallment(loan: Loan): { next: LoanInstallment | null; unpaidCount: number } {
  const unpaid = sortInstallments(loan.loan_installments).filter(i => !i.is_paid);
  return { next: unpaid[0] ?? null, unpaidCount: unpaid.length };
}

export function splitLoansByCompletion(loans: Loan[]): { incomplete: Loan[]; completed: Loan[] } {
  return {
    incomplete: loans.filter(l => Number(l.remaining_amount) > 0),
    completed: loans.filter(l => Number(l.remaining_amount) <= 0),
  };
}

export function paidAmount(loan: Loan): number {
  return (Number(loan.amount) - Number(loan.remaining_amount)) || 0;
}

export function loanToEditDraft(loan: Loan): EditLoanDraft {
  return {
    loan,
    amount: Number(loan.amount),
    installmentAmount: Number(loan.installment_amount),
    installmentCount: Number(loan.installment_count),
    remainingAmount: Number(loan.remaining_amount),
  };
}
