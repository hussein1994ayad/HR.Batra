// =========================================================================
// منطق السلف والأقساط — دوال نقية بدون React أو Supabase
// =========================================================================

import type { Loan, LoanInstallment } from '@/lib/db-types';
import { getLocalDateStr } from '@/lib/dates';
import { baghdadToday } from '@/features/payroll/period';

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

/**
 * القسط الشهري وآخر قسط بنفس قاعدة السيرفر (_insert_loan_installments): القسط = floor(المبلغ ÷ الأشهر)،
 * والقسط الأخير ياخذ فرق التقريب حتى يطلع المجموع = المبلغ بالضبط.
 */
export function installmentPlan(amount: number, months: number): { installment: number; last: number } {
  if (!(amount > 0) || !(months > 0)) return { installment: 0, last: 0 };
  const installment = Math.floor(amount / months);
  return { installment, last: amount - installment * (months - 1) };
}

/** نفس اليوم من الشهر القادم (تاريخ أول قسط المقترح عند الاعتماد). */
export function sameDayNextMonth(now: Date = new Date()): string {
  return addMonths(getLocalDateStr(now), 1);
}

/** رسالة خطأ إن كانت شروط الاعتماد غير متحققة، أو null. */
export function validateApproval(amount: number, months: number): string | null {
  if (!(amount > 0) || !(months > 0)) return 'يرجى إدخال مبلغ وعدد أشهر سداد أكبر من الصفر.';
  return null;
}

/**
 * نسبة الراتب اللي فوقها يطلع تنبيه بالسلفة (نص الراتب). تنبيه فقط وليس منعاً: بعض الموظفين
 * يسددون جزءاً نقداً، والسيرفر (`_validate_loan_terms`) ما يمنعها. نفس القيمة بالتطبيق: kLoanSalaryWarningRatio.
 */
export const LOAN_SALARY_WARNING_RATIO = 0.5;

/**
 * تنبيه (مو منع) إذا القسط أكثر من نص الراتب: مسموح للأدمن لأن بعض الموظفين
 * يسددون جزء نقداً. null = ضمن الحد أو الراتب غير معروف.
 */
export function overHalfSalaryWarning(amount: number, months: number, monthlySalary: number): string | null {
  if (!(monthlySalary > 0) || !(months > 0)) return null;
  const installment = Math.floor(amount / months);
  if (installment <= monthlySalary * LOAN_SALARY_WARNING_RATIO) return null;
  const fmt = (n: number) => Math.round(n).toLocaleString('en-US');
  return `القسط الشهري ${fmt(installment)} د.ع أكثر من نص الراتب (${fmt(monthlySalary * LOAN_SALARY_WARNING_RATIO)} د.ع)`
    + (installment > monthlySalary ? ` وأكثر من الراتب كله (${fmt(monthlySalary)} د.ع)، فكشف راتبه راح يطلع بالسالب إذا ما سدد نقداً.` : '.')
    + '\nالباقي يسدده الموظف نقداً من زر "تسجيل دفعة" بتفاصيل السلفة.';
}

/** الأقساط مرتبة حسب تاريخ الاستحقاق (نسخة جديدة؛ لا تعدّل مصفوفة الحالة). */
export function sortInstallments(installments: LoanInstallment[] | null | undefined): LoanInstallment[] {
  return [...(installments ?? [])].sort((a, b) => a.due_date.localeCompare(b.due_date));
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

export interface PaymentPreviewRow {
  due_date: string;
  amount: number;
  is_paid: boolean;
  /** القسط الذي يتعدّل الآن (دفعة أو مبلغ شهر مخفّض) */
  current?: boolean;
  /** قسط جديد بالأخير (باقي شهر ما انسدد كامل) */
  added?: boolean;
  /** «باقي شهر 10/2026» / «مؤجّل من 12/2026» */
  label?: string;
}

export interface PaymentPreview {
  rows: PaymentPreviewRow[];
  remaining: number;
  error: string | null;
}

/** 2026-10-01 ← «10/2026». */
export function monthLabel(date: string | null | undefined): string {
  if (!date) return '';
  const [y, m] = date.split('-');
  return `${m}/${y}`;
}

/** وصف القسط: باقي شهر / مؤجّل / مبلغ هالشهر مخفّض (نفس أعمدة origin_kind و origin_month و amount_locked). */
export function installmentOrigin(inst: Pick<LoanInstallment, 'origin_kind' | 'origin_month' | 'amount_locked' | 'is_paid'>): string | null {
  if (inst.origin_kind === 'shortfall') return inst.origin_month ? `باقي شهر ${monthLabel(inst.origin_month)}` : 'باقي شهر سابق';
  if (inst.origin_kind === 'postponed') return inst.origin_month ? `مؤجّل من ${monthLabel(inst.origin_month)}` : 'مؤجّل';
  if (inst.amount_locked && !inst.is_paid) return 'مبلغ هالشهر مخفّض';
  return null;
}

/**
 * توزيع الباقي على الأقساط غير المسددة — نفس التريجر update_loan_and_installments_trigger:
 * كل قسط = أقل شي بين القسط الشهري والباقي (المقفل يبقى بمبلغه)، وما يبقى له رصيد يُحذف،
 * والزايد أشهر جديدة بالأخير (كل شهر ≤ القسط الشهري) تتعلّم «باقي شهر …».
 */
function rebalance(
  unpaid: { due_date: string; amount: number; locked?: boolean; current?: boolean; label?: string }[],
  base: number,
  remaining: number,
  lastDue: string,
  origin: string | null,
): PaymentPreviewRow[] {
  const rows: PaymentPreviewRow[] = [];
  let left = remaining;
  for (const u of unpaid) {
    if (left <= 0) break;
    const amount = u.locked ? Math.min(u.amount, left) : Math.min(base, left);
    rows.push({ due_date: u.due_date, amount, is_paid: false, current: u.current, label: u.label });
    left -= amount;
  }
  let last = lastDue;
  while (left > 0) {
    last = addMonths(last, 1);
    const amount = Math.min(base > 0 ? base : left, left);
    rows.push({ due_date: last, amount, is_paid: false, added: true, label: origin ? `باقي شهر ${monthLabel(origin)}` : undefined });
    left -= amount;
  }
  return rows;
}

function scheduleParts(loan: Loan, installmentId: string) {
  const all = sortInstallments(loan.loan_installments);
  const target = all.find((i) => i.id === installmentId);
  const paidBefore = all.filter((i) => i.is_paid).reduce((s, i) => s + Number(i.amount), 0);
  const before = Math.max(Number(loan.amount) - paidBefore, 0);
  const lastDue = all.reduce((max, i) => (i.due_date > max ? i.due_date : max), target?.due_date ?? '');
  const paidRows: PaymentPreviewRow[] = all.filter((i) => i.is_paid).map((i) => ({ due_date: i.due_date, amount: Number(i.amount), is_paid: true }));
  return { all, target, before, lastDue, paidRows, base: Number(loan.installment_amount) };
}

const unpaidOf = (all: LoanInstallment[], skipId?: string) =>
  all.filter((i) => !i.is_paid && i.id !== skipId)
    .map((i) => ({ due_date: i.due_date, amount: Number(i.amount), locked: !!i.amount_locked, label: installmentOrigin(i) ?? undefined }));

/**
 * معاينة سداد قسط بأي مبلغ (pay_loan_installment): الزيادة تصغّر آخر الأقساط، والنقص يصير شهر جديد بالأخير.
 */
export function previewPayment(loan: Loan, installmentId: string, amount: number): PaymentPreview {
  const { all, target, before, lastDue, paidRows, base } = scheduleParts(loan, installmentId);
  const pay = Math.round(amount);
  if (!target || target.is_paid) return { rows: [], remaining: before, error: 'القسط غير موجود أو مسدد مسبقاً.' };
  if (!(pay > 0)) return { rows: [], remaining: before, error: 'يرجى إدخال مبلغ سداد أكبر من الصفر.' };
  if (pay > before) return { rows: [], remaining: before, error: `المبلغ أكبر من المتبقي على السلفة (${before.toLocaleString('en-US')}).` };

  const remaining = before - pay;
  const rows = [
    ...paidRows,
    { due_date: target.due_date, amount: pay, is_paid: true, current: true },
    ...rebalance(unpaidOf(all, target.id), base, remaining, lastDue, pay < base ? target.due_date : null),
  ];
  rows.sort((a, b) => a.due_date.localeCompare(b.due_date));
  return { rows, remaining, error: null };
}

/**
 * معاينة «هالشهر يكدر يدفع بس X» (set_month_installment): القسط يبقى غير مسدد بمبلغ X (الرواتب تخصمه)،
 * والنقص يصير شهر جديد بالأخير «باقي شهر …».
 */
export function previewMonthAmount(loan: Loan, installmentId: string, amount: number): PaymentPreview {
  const { all, target, before, lastDue, paidRows, base } = scheduleParts(loan, installmentId);
  const value = Math.round(amount);
  if (!target || target.is_paid) return { rows: [], remaining: before, error: 'القسط غير موجود أو مسدد مسبقاً.' };
  if (!(value > 0)) return { rows: [], remaining: before, error: 'اكتب المبلغ اللي يكدر يدفعه. إذا ما يكدر يدفع شي، استعمل التأجيل.' };
  if (value >= Number(target.amount)) {
    return { rows: [], remaining: before, error: `المبلغ لازم يكون أقل من قسط الشهر (${Number(target.amount).toLocaleString('en-US')}).` };
  }
  const unpaid = all.filter((i) => !i.is_paid).map((i) => i.id === target.id
    ? { due_date: i.due_date, amount: value, locked: true, current: true, label: 'مبلغ هالشهر مخفّض' }
    : { due_date: i.due_date, amount: Number(i.amount), locked: !!i.amount_locked, label: installmentOrigin(i) ?? undefined });
  const rows = [...paidRows, ...rebalance(unpaid, base, before, lastDue, target.due_date)];
  rows.sort((a, b) => a.due_date.localeCompare(b.due_date));
  return { rows, remaining: before, error: null };
}

/** تأجيل قسط: ينتقل لشهر جديد بعد آخر قسط (postpone_loan_installment). */
export function postponeTarget(loan: Loan, installmentId: string): string | null {
  const all = sortInstallments(loan.loan_installments);
  if (!all.some((i) => i.id === installmentId && !i.is_paid)) return null;
  return addMonths(all[all.length - 1].due_date, 1);
}

/**
 * تعديل السلفة (reschedule_loan): أقساط بالقسط الشهري بالضبط وآخرها الباقي؛ العدد ينحسب.
 */
export function reschedulePlan(amount: number, paid: number, installment: number): { count: number; last: number; remaining: number } {
  const remaining = Math.max(Math.round(amount) - paid, 0);
  const base = Math.round(installment);
  if (!(base > 0) || remaining === 0) return { count: 0, last: 0, remaining };
  const count = Math.ceil(remaining / base);
  return { count, last: remaining - base * (count - 1), remaining };
}

/** تاريخ أول قسط افتراضياً للسلفة المباشرة: يوم القطع (26) القادم بتوقيت بغداد. */
export function nextCutoffDate(): string {
  const [y, m, d] = baghdadToday().split('-').map(Number);
  const [yy, mm] = d <= 26 ? [y, m] : m === 12 ? [y + 1, 1] : [y, m + 1];
  return `${yy}-${String(mm).padStart(2, '0')}-26`;
}
