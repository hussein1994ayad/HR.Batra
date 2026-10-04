import { describe, expect, it } from 'vitest';
import {
  DEFAULT_WORK_DAYS,
  isDateInRange,
  toDateKey,
  weekdayOf,
  workDaysFor,
} from '@/lib/attendance';
import { formatLateDurationArabic } from '@/lib/dates';
import type { WorkSchedule } from '@/lib/db-types';
import { resolveWorkSchedule } from '@/lib/schedules';

const sched = (over: Partial<WorkSchedule>): WorkSchedule => ({
  id: over.id ?? 'x',
  name: 'جدول',
  check_in_time: '08:00:00',
  check_out_time: '16:00:00',
  grace_period_minutes: 15,
  work_days: [0, 1, 2, 3, 4],
  ...over,
});

describe('resolveWorkSchedule', () => {
  const branch = sched({ id: 'branch', branch_id: 'b1', department_id: null, employee_id: null });
  const dept = sched({ id: 'dept', department_id: 'd1', employee_id: null });
  const personal = sched({ id: 'personal', employee_id: 'e1' });

  it('prefers employee, then department, then branch schedules', () => {
    const emp = { id: 'e1', department_id: 'd1', branch_id: 'b1' };
    expect(resolveWorkSchedule(emp, [branch, dept, personal])?.id).toBe('personal');
    expect(resolveWorkSchedule({ ...emp, id: 'e2' }, [branch, dept, personal])?.id).toBe('dept');
    expect(resolveWorkSchedule({ id: 'e3', department_id: 'd9', branch_id: 'b1' }, [branch, dept])?.id).toBe('branch');
  });

  it('picks the newest schedule when two apply at the same level (like the server)', () => {
    const older = sched({ id: 'old', branch_id: 'b1', department_id: null, employee_id: null, created_at: '2026-01-01T00:00:00Z' });
    const newer = sched({ id: 'new', branch_id: 'b1', department_id: null, employee_id: null, created_at: '2026-06-01T00:00:00Z' });
    expect(resolveWorkSchedule({ id: 'e5', department_id: null, branch_id: 'b1' }, [older, newer])?.id).toBe('new');
  });

  it('does not match a branch schedule of another branch for employees without a department', () => {
    const otherBranch = sched({ id: 'other', branch_id: 'b2', department_id: null, employee_id: null });
    expect(resolveWorkSchedule({ id: 'e4', department_id: null, branch_id: 'b1' }, [otherBranch])).toBeUndefined();
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

describe('Arabic durations', () => {
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
