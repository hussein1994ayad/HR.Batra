import { describe, expect, it } from 'vitest';
import { currentPayrollMonth, previewPayrollPeriod } from './period';

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
