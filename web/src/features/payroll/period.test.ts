import { describe, expect, it } from 'vitest';
import { currentPayrollMonth, payrollMonthOptions, previewPayrollPeriod } from './period';

describe('currentPayrollMonth', () => {
  it('day 26 stays in its month, 27 moves to the next (Baghdad time)', () => {
    expect(currentPayrollMonth(26, new Date('2026-09-26T12:00:00Z'))).toBe('2026-09');
    expect(currentPayrollMonth(26, new Date('2026-09-27T08:00:00Z'))).toBe('2026-10');
    // 26 أيلول 22:00 UTC = 27 أيلول 01:00 بغداد
    expect(currentPayrollMonth(26, new Date('2026-09-26T22:00:00Z'))).toBe('2026-10');
    expect(currentPayrollMonth(26, new Date('2026-12-30T08:00:00Z'))).toBe('2027-01');
  });
});

describe('previewPayrollPeriod', () => {
  it('runs from the day after last cutoff to this cutoff', () => {
    expect(previewPayrollPeriod('2026-10', 26, 30)).toEqual({ start: '2026-09-27', end: '2026-10-26', payment: '2026-10-30' });
    expect(previewPayrollPeriod('2027-01', 26, 30)).toEqual({ start: '2026-12-27', end: '2027-01-26', payment: '2027-01-30' });
  });
  it('caps days to short months', () => {
    expect(previewPayrollPeriod('2027-02', 26, 30)).toEqual({ start: '2027-01-27', end: '2027-02-26', payment: '2027-02-28' });
    expect(previewPayrollPeriod('2028-02', 26, 31)).toEqual({ start: '2028-01-27', end: '2028-02-26', payment: '2028-02-29' });
  });
});

describe('payrollMonthOptions', () => {
  it('lists payroll months as numbers, in order, with their periods', () => {
    const opts = payrollMonthOptions('2026-10', 26, 2, 1);
    expect(opts.map((o) => o.value)).toEqual(['2026-08', '2026-09', '2026-10', '2026-11']);
    expect(opts[0].label).toBe('08 / 2026 · كشوف قديمة');
    expect(opts[1].label).toBe('09 / 2026 · 01-09 ← 26-09');
    expect(opts[2].label).toBe('10 / 2026 · 27-09 ← 26-10');
    expect(opts[3].label).toBe('11 / 2026 · 27-10 ← 26-11');
  });
  it('crosses the year boundary', () => {
    expect(payrollMonthOptions('2027-01', 26, 1, 0).map((o) => o.label)).toEqual(['12 / 2026 · 27-11 ← 26-12', '01 / 2027 · 27-12 ← 26-01']);
  });
});
