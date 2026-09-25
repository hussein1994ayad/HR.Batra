import { describe, expect, it } from 'vitest';
import {
  DEFAULT_WORK_DAYS,
  findSchedule,
  formatLateDurationArabic,
  isDateInRange,
  minutesEarly,
  minutesLate,
  toDateKey,
  weekdayOf,
  workDaysFor,
} from '@/lib/attendance';
import type { WorkSchedule } from '@/lib/types';

const sched = (over: Partial<WorkSchedule>): WorkSchedule => ({
  id: over.id ?? 'x',
  name: 'جدول',
  check_in_time: '08:00:00',
  check_out_time: '16:00:00',
  grace_period_minutes: 15,
  work_days: [0, 1, 2, 3, 4],
  ...over,
});

describe('findSchedule', () => {
  const branch = sched({ id: 'branch', branch_id: 'b1', department_id: null, employee_id: null });
  const dept = sched({ id: 'dept', department_id: 'd1', employee_id: null });
  const personal = sched({ id: 'personal', employee_id: 'e1' });

  it('prefers employee, then department, then branch schedules', () => {
    const emp = { id: 'e1', department_id: 'd1', branch_id: 'b1' };
    expect(findSchedule(emp, [branch, dept, personal])?.id).toBe('personal');
    expect(findSchedule({ ...emp, id: 'e2' }, [branch, dept, personal])?.id).toBe('dept');
    expect(findSchedule({ id: 'e3', department_id: 'd9', branch_id: 'b1' }, [branch, dept])?.id).toBe('branch');
  });

  it('does not match a branch schedule of another branch for employees without a department', () => {
    const otherBranch = sched({ id: 'other', branch_id: 'b2', department_id: null, employee_id: null });
    expect(findSchedule({ id: 'e4', department_id: null, branch_id: 'b1' }, [otherBranch])).toBeUndefined();
  });

  it('falls back to the default Iraqi working week', () => {
    expect(workDaysFor(undefined)).toEqual(DEFAULT_WORK_DAYS);
    expect(workDaysFor(branch)).toEqual([0, 1, 2, 3, 4]);
  });
});

describe('dates', () => {
  it('computes the weekday in local time', () => {
    expect(weekdayOf('2026-09-25')).toBe(5); // Friday
    expect(weekdayOf('2026-09-26')).toBe(6); // Saturday
  });

  it('normalises leave boundaries to local dates', () => {
    expect(toDateKey('2026-09-01')).toBe('2026-09-01');
    expect(toDateKey('2026-09-01T00:00:00+00:00')).toBe('2026-09-01');
    // Midnight in Baghdad stored as UTC belongs to the next calendar day.
    expect(toDateKey('2026-08-31T21:00:00+00:00')).toBe('2026-09-01');
  });

  it('checks inclusive leave ranges', () => {
    expect(isDateInRange('2026-09-01', '2026-09-01', '2026-09-03')).toBe(true);
    expect(isDateInRange('2026-09-03', '2026-09-01T00:00:00Z', '2026-09-03T00:00:00Z')).toBe(true);
    expect(isDateInRange('2026-09-04', '2026-09-01', '2026-09-03')).toBe(false);
    expect(isDateInRange('2026-09-01', null, '2026-09-03')).toBe(false);
  });
});

describe('lateness', () => {
  it('measures minutes after the scheduled start', () => {
    // 09:25 Baghdad = 06:25 UTC
    expect(minutesLate('2026-09-20T06:25:00Z', '09:00:00')).toBe(25);
    expect(minutesLate('2026-09-20T05:55:00Z', '09:00:00')).toBe(0);
    expect(minutesLate(null)).toBe(0);
  });

  it('measures minutes before the scheduled end', () => {
    // 16:15 Baghdad = 13:15 UTC
    expect(minutesEarly('2026-09-20T13:15:00Z', '17:00:00')).toBe(45);
    expect(minutesEarly('2026-09-20T14:30:00Z', '17:00:00')).toBe(0);
  });

  it('describes durations in Arabic', () => {
    expect(formatLateDurationArabic(0)).toBe('0 دقيقة');
    expect(formatLateDurationArabic(1)).toBe('دقيقة واحدة');
    expect(formatLateDurationArabic(2)).toBe('دقيقتين');
    expect(formatLateDurationArabic(7)).toBe('7 دقائق');
    expect(formatLateDurationArabic(25)).toBe('25 دقيقة');
    expect(formatLateDurationArabic(60)).toBe('ساعة');
    expect(formatLateDurationArabic(125)).toBe('ساعتين و 5 دقائق');
    expect(formatLateDurationArabic(3 * 60 + 11)).toBe('3 ساعات و 11 دقيقة');
  });
});
