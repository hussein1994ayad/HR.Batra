import { describe, expect, it } from 'vitest';
import type { Loan, LoanInstallment } from '@/lib/db-types';
import {
  addMonths, buildInstallmentSchedule, firstOfNextMonth, nextUnpaidInstallment, sameDayNextMonth, sortInstallments,
  splitAmount, splitLoansByCompletion, validateApproval,
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

describe('splitAmount / buildInstallmentSchedule', () => {
  it('puts the rounding remainder on the last installment so the sum is exact', () => {
    expect(splitAmount(1000, 3)).toEqual([333, 333, 334]);
    expect(splitAmount(900, 3)).toEqual([300, 300, 300]);
    expect(splitAmount(500, 0)).toEqual([]);
  });
  it('schedules monthly due dates from the first date', () => {
    expect(buildInstallmentSchedule(1000, 3, '2026-01-31')).toEqual([
      { due_date: '2026-01-31', amount: 333 },
      { due_date: '2026-02-28', amount: 333 },
      { due_date: '2026-03-31', amount: 334 },
    ]);
  });
});

describe('default dates', () => {
  it('starts rescheduled installments on the first of next month', () => {
    expect(firstOfNextMonth(new Date(2026, 11, 20))).toBe('2027-01-01');
  });
  it('proposes the same day next month for the first installment', () => {
    expect(sameDayNextMonth(new Date(2026, 0, 31, 23, 30))).toBe('2026-02-28');
  });
});

describe('validateApproval', () => {
  it('rejects zero values and installments above half the salary', () => {
    expect(validateApproval(0, 5, 1_000_000)).toMatch(/أكبر من الصفر/);
    expect(validateApproval(1_200_000, 2, 1_000_000)).toMatch(/50%/);
    expect(validateApproval(1_200_000, 3, 1_000_000)).toBeNull();
    expect(validateApproval(1_200_000, 1, 0)).toBeNull(); // الراتب غير معروف
  });
});

describe('installment helpers', () => {
  it('sorts without mutating and finds the next unpaid one', () => {
    const list = [inst('b', '2026-03-01'), inst('a', '2026-01-01', true), inst('c', '2026-02-01')];
    expect(sortInstallments(list).map(i => i.id)).toEqual(['a', 'c', 'b']);
    expect(list[0].id).toBe('b');
    const { next, unpaidCount } = nextUnpaidInstallment(loan({ loan_installments: list }));
    expect(next?.id).toBe('c');
    expect(unpaidCount).toBe(2);
  });

  it('splits loans by remaining amount', () => {
    const { incomplete, completed } = splitLoansByCompletion([loan({ id: '1' }), loan({ id: '2', remaining_amount: 0 })]);
    expect(incomplete.map(l => l.id)).toEqual(['1']);
    expect(completed.map(l => l.id)).toEqual(['2']);
  });
});
