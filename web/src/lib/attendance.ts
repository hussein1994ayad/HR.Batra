import type { WorkSchedule } from './types';
import { localDateStr } from './format';

/** Iraqi default working week: Saturday (6) through Thursday (4). */
export const DEFAULT_WORK_DAYS = [6, 0, 1, 2, 3, 4];
export const DEFAULT_CHECK_IN = '09:00:00';
export const DEFAULT_CHECK_OUT = '17:00:00';

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

function atScheduleTime(reference: Date, hhmmss: string): Date {
  const [h, m, s] = hhmmss.split(':').map(Number);
  const d = new Date(reference);
  d.setHours(h || 0, m || 0, s || 0, 0);
  return d;
}

/** Minutes the employee checked in after the scheduled start (0 if on time). */
export function minutesLate(checkInIso: string | null | undefined, scheduledIn: string = DEFAULT_CHECK_IN): number {
  if (!checkInIso) return 0;
  const checkIn = new Date(checkInIso);
  if (isNaN(checkIn.getTime())) return 0;
  const diff = checkIn.getTime() - atScheduleTime(checkIn, scheduledIn).getTime();
  return diff > 0 ? Math.floor(diff / 60000) : 0;
}

/** Minutes the employee checked out before the scheduled end (0 if not early). */
export function minutesEarly(checkOutIso: string | null | undefined, scheduledOut: string = DEFAULT_CHECK_OUT): number {
  if (!checkOutIso) return 0;
  const checkOut = new Date(checkOutIso);
  if (isNaN(checkOut.getTime())) return 0;
  const diff = atScheduleTime(checkOut, scheduledOut).getTime() - checkOut.getTime();
  return diff > 0 ? Math.floor(diff / 60000) : 0;
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

/** Human-readable Arabic duration, e.g. `ساعتين و 5 دقائق`. */
export function formatLateDurationArabic(minutes: number): string {
  if (minutes <= 0) return '0 دقيقة';
  const hrs = Math.floor(minutes / 60);
  const mins = minutes % 60;

  let hrsStr = '';
  if (hrs > 0) {
    if (hrs === 1) hrsStr = 'ساعة';
    else if (hrs === 2) hrsStr = 'ساعتين';
    else if (hrs >= 3 && hrs <= 10) hrsStr = `${hrs} ساعات`;
    else hrsStr = `${hrs} ساعة`;
  }

  let minsStr = '';
  if (mins > 0) {
    if (mins === 1) minsStr = 'دقيقة واحدة';
    else if (mins === 2) minsStr = 'دقيقتين';
    else if (mins >= 3 && mins <= 10) minsStr = `${mins} دقائق`;
    else minsStr = `${mins} دقيقة`;
  }

  if (hrsStr && minsStr) return `${hrsStr} و ${minsStr}`;
  return hrsStr || minsStr;
}
