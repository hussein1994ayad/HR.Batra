import type { WorkSchedule } from './db-types';
import { localDateStr } from './format';

/** Iraqi default working week: Saturday (6) through Thursday (4). */
export const DEFAULT_WORK_DAYS = [6, 0, 1, 2, 3, 4];

/**
 * فترة السماح الفعلية هي اللي يحددها الأدمن بجدول الدوام. العمود إلزامي بالقاعدة (NOT NULL DEFAULT 15)،
 * فهذا البديل للاحتياط فقط — ونفس رقم السيرفر (COALESCE(grace_period_minutes, 15)).
 */
export const DEFAULT_GRACE_MINUTES = 15;

interface ScheduleTarget {
  id: string;
  department_id?: string | null;
  branch_id?: string | null;
}

/**
 * Resolves the schedule that applies to an employee: an employee-specific
 * schedule wins over a department schedule, which wins over a branch one.
 */
export function findSchedule(emp: ScheduleTarget, schedules: WorkSchedule[]): WorkSchedule | undefined {
  return (
    schedules.find((s) => s.employee_id === emp.id) ||
    schedules.find((s) => !!emp.department_id && s.department_id === emp.department_id && !s.employee_id) ||
    schedules.find((s) => !!emp.branch_id && s.branch_id === emp.branch_id && !s.employee_id && !s.department_id)
  );
}

export function workDaysFor(schedule: WorkSchedule | undefined): number[] {
  return schedule?.work_days ?? DEFAULT_WORK_DAYS;
}

/** Day of week (0 = Sunday) for a `YYYY-MM-DD` string, evaluated in local time. */
export function weekdayOf(dateStr: string): number {
  const [y, m, d] = dateStr.split('-').map(Number);
  return new Date(y, m - 1, d).getDay();
}

/**
 * Normalises a leave boundary (either `YYYY-MM-DD` or a full timestamp) to
 * the local calendar date it refers to.
 */
export function toDateKey(value: string): string {
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  const d = new Date(value);
  return isNaN(d.getTime()) ? value.slice(0, 10) : localDateStr(d);
}

/** Inclusive check that `dateStr` (`YYYY-MM-DD`) falls within a leave period. */
export function isDateInRange(dateStr: string, start: string | null | undefined, end: string | null | undefined): boolean {
  if (!dateStr || !start || !end) return false;
  return dateStr >= toDateKey(start) && dateStr <= toDateKey(end);
}
