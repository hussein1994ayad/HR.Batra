import { describe, expect, it } from 'vitest';
import type { AttendanceRecord, LeaveRequest } from '@/lib/db-types';
import { buildAttendanceRows } from './logic';

// إجازة يوم 28 أيلول بتوقيت بغداد تُخزَّن 2026-09-27T21:00:00Z
const leave = {
  id: 'l1', employee_id: 'e1', status: 'approved', is_hourly: false,
  start_date: '2026-09-27T21:00:00Z', end_date: '2026-09-27T21:00:00Z',
} as unknown as LeaveRequest;
const row = (date: string) => ({
  id: `a_${date}`, employee_id: 'e1', branch_id: 'b', work_date: date, status: 'absent',
  check_in_time: null, check_out_time: null,
}) as unknown as AttendanceRecord;

describe('attendance rows on an approved leave day', () => {
  it('reads the leave on its Baghdad date (not the UTC day before)', () => {
    const rows = buildAttendanceRows([row('2026-09-27'), row('2026-09-28'), row('2026-09-29')], [], [leave]);
    expect(rows.map((r) => r.on_leave)).toEqual([false, true, false]);
  });

  it('ignores pending and hourly leaves', () => {
    const pending = { ...leave, status: 'pending' } as LeaveRequest;
    const hourly = { ...leave, is_hourly: true } as LeaveRequest;
    expect(buildAttendanceRows([row('2026-09-28')], [], [pending, hourly])[0].on_leave).toBe(false);
  });
});

describe('manual attendance status', () => {
  const shift = { check_in_time: '09:00:00', grace_period_minutes: 15 };
  it('is late only after the start time plus the grace period', async () => {
    const { manualAttendanceStatus } = await import('./logic');
    expect(manualAttendanceStatus(shift, '09:15')).toBe('present');
    expect(manualAttendanceStatus(shift, '09:16')).toBe('late');
    expect(manualAttendanceStatus(shift, '09:30')).toBe('late');
    expect(manualAttendanceStatus(undefined, '11:00')).toBe('present');
  });
});
