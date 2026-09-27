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

export interface PaymentPreviewRow {
  due_date: string;
  amount: number;
  is_paid: boolean;
  /** القسط الذي يُسجَّل سداده الآن */
  current?: boolean;
  /** قسط جديد يُضاف لأن المدفوع أقل من المتبقي */
  added?: boolean;
}

export interface PaymentPreview {
  rows: PaymentPreviewRow[];
  remaining: number;
  error: string | null;
}

/**
 * معاينة سداد قسط بمبلغ مختلف عن المجدول — نفس قواعد التريجر
 * trg_update_loan_and_installments في القاعدة (pay_loan_installment):
 * الأقساط غير المدفوعة الباقية بقيمة القسط الأساسي، وآخرها يأخذ الفرق،
 * وما لا يبقى له رصيد يُحذف، وإن لم يبقَ قسط يُضاف شهر جديد بالفرق.
 */
export function previewPayment(loan: Loan, installmentId: string, amount: number): PaymentPreview {
  const all = sortInstallments(loan.loan_installments);
  const target = all.find((i) => i.id === installmentId);
  const paidBefore = all.filter((i) => i.is_paid).reduce((s, i) => s + Number(i.amount), 0);
  const before = Math.max(Number(loan.amount) - paidBefore, 0);
  const pay = Math.round(amount);

  if (!target || target.is_paid) return { rows: [], remaining: before, error: 'القسط غير موجود أو مسدد مسبقاً.' };
  if (!(pay > 0)) return { rows: [], remaining: before, error: 'يرجى إدخال مبلغ سداد أكبر من الصفر.' };
  if (pay > before) return { rows: [], remaining: before, error: `المبلغ أكبر من المتبقي على السلفة (${before.toLocaleString('en-US')}).` };

  const remaining = before - pay;
  const base = Number(loan.installment_amount);
  const rows: PaymentPreviewRow[] = [];
  const others = all.filter((i) => !i.is_paid && i.id !== installmentId);
  let allocated = 0;

  for (const i of all) {
    if (i.is_paid) rows.push({ due_date: i.due_date, amount: Number(i.amount), is_paid: true });
    else if (i.id === installmentId) rows.push({ due_date: i.due_date, amount: pay, is_paid: true, current: true });
  }
  others.forEach((i, idx) => {
    if (allocated >= remaining) return;
    const share = idx === others.length - 1 ? remaining - allocated : Math.min(base, remaining - allocated);
    rows.push({ due_date: i.due_date, amount: share, is_paid: false });
    allocated += share;
  });

  let last = all.reduce((max, i) => (i.due_date > max ? i.due_date : max), target.due_date);
  while (allocated < remaining) {
    last = addMonths(last, 1);
    const share = Math.min(base > 0 ? base : remaining, remaining - allocated);
    rows.push({ due_date: last, amount: share, is_paid: false, added: true });
    allocated += share;
  }

  rows.sort((a, b) => a.due_date.localeCompare(b.due_date));
  return { rows, remaining, error: null };
}
