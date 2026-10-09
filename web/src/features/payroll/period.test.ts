import { describe, expect, it } from 'vitest';
import {
  arabicDate, baghdadToday, cutoffDateOf, monthLabel, payrollMonthName, payrollMonthOfDate, payrollMonthOptions, shiftPayrollMonth,
} from './period';

describe('payroll dates', () => {
  it('today is the Baghdad date even right after midnight (UTC is still the day before)', () => {
    expect(baghdadToday(new Date('2026-10-26T22:30:00Z'))).toBe('2026-10-27');
    expect(baghdadToday(new Date('2026-10-27T20:59:00Z'))).toBe('2026-10-27');
  });

  it('labels a payroll month like the app', () => {
    expect(monthLabel('2026-10')).toBe('شهر 10 سنة 2026');
    expect(monthLabel('2027-01')).toBe('شهر 1 سنة 2027');
  });
});

describe('payroll month in plain words', () => {
  it('names the month and the days in Arabic', () => {
    expect(payrollMonthName('2026-10')).toBe('تشرين الأول 2026');
    expect(arabicDate('2026-09-27')).toBe('الأحد 27 أيلول');
    expect(arabicDate('2026-10-26', true)).toBe('الاثنين 26 تشرين الأول 2026');
    expect(payrollMonthOptions('2026-10', 1, 1).map((o) => o.label)).toEqual(['رواتب أيلول 2026', 'رواتب تشرين الأول 2026', 'رواتب تشرين الثاني 2026']);
  });

  it('an installment belongs to the payroll month by the cutoff day (like the server)', () => {
    expect(payrollMonthOfDate('2026-10-26')).toBe('2026-10');
    expect(payrollMonthOfDate('2026-10-28')).toBe('2026-11');
    expect(payrollMonthOfDate('2026-12-27')).toBe('2027-01');
    expect(cutoffDateOf('2026-11')).toBe('2026-11-26');
    expect(shiftPayrollMonth('2026-12', 1)).toBe('2027-01');
  });
});
