import { describe, expect, it } from 'vitest';
// حساب الرواتب نفسه صار في السيرفر (محرّك الرواتب) وله اختبارات قاعدة البيانات
// supabase/tests/test_payroll_engine.mjs؛ هنا تبقى أداة تواريخ الدورة القديمة.
import { getCycleDates } from '@/lib/dates';

describe('getCycleDates', () => {
  it('spans from the previous month when start day > end day', () => {
    expect(getCycleDates('2026-09', 25, 24)).toEqual({ start: '2026-08-25', end: '2026-09-24' });
  });
  it('crosses the year boundary', () => {
    expect(getCycleDates('2026-01', 25, 24)).toEqual({ start: '2025-12-25', end: '2026-01-24' });
  });
  it('clamps days that do not exist in short months', () => {
    expect(getCycleDates('2026-02', 1, 31)).toEqual({ start: '2026-02-01', end: '2026-02-28' });
    expect(getCycleDates('2026-03', 30, 29)).toEqual({ start: '2026-02-28', end: '2026-03-29' });
  });
  it('returns empty dates without a month', () => {
    expect(getCycleDates('')).toEqual({ start: '', end: '' });
  });
});
