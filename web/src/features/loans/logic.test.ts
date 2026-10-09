import { describe, expect, it } from 'vitest';
import type { Loan, LoanInstallment } from '@/lib/db-types';
import {
  addMonths, installmentPlan, sameDayNextMonth, sortInstallments,
  installmentOrigin, overHalfSalaryWarning, postponeTarget, previewMonthAmount, previewPayment, reschedulePlan, splitLoansByCompletion,
  validateApproval,
} from './logic';

const inst = (id: string, due_date: string, is_paid = false): LoanInstallment =>
  ({ id, loan_id: 'l', due_date, amount: 100, is_paid });
const loan = (over: Partial<Loan>): Loan => ({
  id: 'l', employee_id: 'e', amount: 1000, installment_amount: 100, installment_count: 10,
  remaining_amount: 1000, pledge_url: '', status: 'approved', ...over,
});

describe('addMonths', () => {
  it('clamps to the last day of shorter months', () => {
    expect(addMonths('2026-01-31', 1)).toBe('2026-02-28');
    expect(addMonths('2028-01-31', 1)).toBe('2028-02-29');
    expect(addMonths('2026-03-31', 1)).toBe('2026-04-30');
  });
  it('crosses year boundaries', () => {
    expect(addMonths('2026-11-15', 3)).toBe('2027-02-15');
  });
});

describe('installmentPlan', () => {
  it('rounds the installment down and puts the remainder on the last one (like the server)', () => {
    expect(installmentPlan(1000, 3)).toEqual({ installment: 333, last: 334 });
    expect(installmentPlan(900, 3)).toEqual({ installment: 300, last: 300 });
    expect(installmentPlan(500, 0)).toEqual({ installment: 0, last: 0 });
  });
});

describe('default dates', () => {
  it('proposes the same day next month for the first installment', () => {
    expect(sameDayNextMonth(new Date(2026, 0, 31, 23, 30))).toBe('2026-02-28');
  });
});

describe('validateApproval', () => {
  it('rejects zero values and installments above half the salary', () => {
    expect(validateApproval(0, 5)).toMatch(/أكبر من الصفر/);
    expect(validateApproval(1_200_000, 1)).toBeNull(); // فوق نص الراتب مسموح (تنبيه فقط)
  });
  it('warns (does not refuse) above half the salary', () => {
    expect(overHalfSalaryWarning(1_200_000, 2, 1_000_000)).toMatch(/أكثر من نص الراتب/);
    expect(overHalfSalaryWarning(1_200_000, 1, 1_000_000)).toMatch(/بالسالب/);
    expect(overHalfSalaryWarning(1_200_000, 3, 1_000_000)).toBeNull();
    expect(overHalfSalaryWarning(1_200_000, 1, 0)).toBeNull(); // الراتب غير معروف
  });
});

describe('installment helpers', () => {
  it('sorts by due date without mutating', () => {
    const list = [inst('b', '2026-03-01'), inst('a', '2026-01-01', true), inst('c', '2026-02-01')];
    expect(sortInstallments(list).map(i => i.id)).toEqual(['a', 'c', 'b']);
    expect(list[0].id).toBe('b');
  });

  it('splits loans by remaining amount', () => {
    const { incomplete, completed } = splitLoansByCompletion([loan({ id: '1' }), loan({ id: '2', remaining_amount: 0 })]);
    expect(incomplete.map(l => l.id)).toEqual(['1']);
    expect(completed.map(l => l.id)).toEqual(['2']);
  });
});

describe('previewPayment', () => {
  const schedule = (paid: number[], planned: number[]): Loan => {
    const insts: LoanInstallment[] = [...paid, ...planned].map((amount, i) => ({
      id: `i${i}`, loan_id: 'l', due_date: `2026-0${i + 1}-10`, amount, is_paid: i < paid.length,
    }));
    return loan({ amount: 500000, installment_amount: 100000, installment_count: 5, loan_installments: insts });
  };
  const amounts = (p: ReturnType<typeof previewPayment>) => p.rows.map((r) => r.amount / 1000).join();

  it('paying more shrinks the last installment', () => {
    const p = previewPayment(schedule([100000], [100000, 100000, 100000, 100000]), 'i1', 150000);
    expect(amounts(p)).toBe('100,150,100,100,50');
    expect(p.remaining).toBe(250000);
  });

  it('paying less: the rest becomes a new last month marked with the month it came from (not a bigger last installment)', () => {
    const p = previewPayment(schedule([100000], [100000, 100000, 100000, 100000]), 'i1', 50000);
    expect(amounts(p)).toBe('100,50,100,100,100,50');
    expect(p.rows.at(-1)).toMatchObject({ due_date: '2026-06-10', added: true, label: 'باقي شهر 02/2026' });
  });

  it('a large payment removes installments that are no longer needed', () => {
    expect(amounts(previewPayment(schedule([100000], [100000, 100000, 100000, 100000]), 'i1', 350000))).toBe('100,350,50');
  });

  it('underpaying the last installment adds a new month', () => {
    const p = previewPayment(schedule([100000, 100000, 100000, 100000], [100000]), 'i4', 20000);
    expect(amounts(p)).toBe('100,100,100,100,20,80');
    expect(p.rows.at(-1)).toMatchObject({ due_date: '2026-06-10', added: true, label: 'باقي شهر 05/2026' });
  });

  it('rejects zero and amounts above the remaining balance', () => {
    const l = schedule([100000], [100000, 100000, 100000, 100000]);
    expect(previewPayment(l, 'i1', 0).error).toMatch('أكبر من الصفر');
    expect(previewPayment(l, 'i1', 400001).error).toMatch('أكبر من المتبقي');
  });
});

describe('smart installments', () => {
  const l = (): Loan => loan({
    amount: 300000, installment_amount: 100000, installment_count: 3,
    loan_installments: [0, 1, 2].map((i) => ({ id: `m${i}`, loan_id: 'l', due_date: `2026-1${i}-01`, amount: 100000, is_paid: false })),
  });
  const amounts = (rows: { amount: number }[]) => rows.map((r) => r.amount / 1000).join();

  it('this month pays less: the month keeps the reduced amount, the rest is a new last month', () => {
    const p = previewMonthAmount(l(), 'm0', 40000);
    expect(amounts(p.rows)).toBe('40,100,100,60');
    expect(p.rows[0]).toMatchObject({ current: true, is_paid: false });
    expect(p.rows[3]).toMatchObject({ due_date: '2027-01-01', added: true, label: 'باقي شهر 10/2026' });
    expect(p.remaining).toBe(300000);
  });

  it('this month: zero (use postpone) and amounts not below the installment are refused', () => {
    expect(previewMonthAmount(l(), 'm0', 0).error).toMatch('التأجيل');
    expect(previewMonthAmount(l(), 'm0', 100000).error).toMatch('أقل من قسط الشهر');
  });

  it('postponing moves the month after the last installment', () => {
    expect(postponeTarget(l(), 'm1')).toBe('2027-01-01');
  });

  it('labels explain each installment', () => {
    expect(installmentOrigin({ origin_kind: 'shortfall', origin_month: '2026-10-01', is_paid: false })).toBe('باقي شهر 10/2026');
    expect(installmentOrigin({ origin_kind: 'postponed', origin_month: '2026-12-01', is_paid: false })).toBe('مؤجّل من 12/2026');
    expect(installmentOrigin({ amount_locked: true, is_paid: false })).toBe('مبلغ هالشهر مخفّض');
    expect(installmentOrigin({ is_paid: true })).toBeNull();
  });

  it('editing the loan: exactly the monthly installment, the last takes the rest, the count is computed', () => {
    expect(reschedulePlan(10000000, 766667, 700000)).toEqual({ count: 14, last: 133333, remaining: 9233333 });
    expect(reschedulePlan(900000, 0, 300000)).toEqual({ count: 3, last: 300000, remaining: 900000 });
    expect(reschedulePlan(500000, 500000, 100000).count).toBe(0);
  });
});

