import { describe, expect, it } from 'vitest';
import type { WorkSchedule } from '@/lib/db-types';
import {
  DEFAULT_COMPANY, DEFAULT_LEAVE_TYPES, DEFAULT_SCHEDULE_FORM, addLeaveType, buildScheduleRow, formatTime12h,
  parseCompany, parsePolicies, purgeSummary, scheduleTargetName, toggleWorkDay,
} from './logic';

describe('parsePolicies', () => {
  it('uses defaults for missing rows and fields', () => {
    expect(parsePolicies({ archive: null, payroll: null, leave: null })).toEqual({
      trackingDays: 180, cycleStartDay: 25, cycleEndDay: 24, defaultAnnual: 21, defaultSick: 15,
      leaveTypes: DEFAULT_LEAVE_TYPES,
    });
  });
  it('reads stored values', () => {
    const p = parsePolicies({
      archive: { value: { tracking_archive_days: 90 } },
      payroll: { value: { cycle_start_day: 1, cycle_end_day: 31 } },
      leave: { value: { default_annual: 30, active_types: [{ id: 'annual', name: 'سنوية' }] } },
    });
    expect(p).toMatchObject({ trackingDays: 90, cycleStartDay: 1, cycleEndDay: 31, defaultAnnual: 30, defaultSick: 15 });
    expect(p.leaveTypes).toEqual([{ id: 'annual', name: 'سنوية' }]);
  });
});

describe('parseCompany', () => {
  it('falls back to the default profile only when no row exists', () => {
    expect(parseCompany(null)).toBe(DEFAULT_COMPANY);
    expect(parseCompany({ name: 'بترا', phone: null }).phone).toBe('');
  });
});

describe('addLeaveType', () => {
  it('normalizes the id and rejects duplicates or blanks', () => {
    const r = addLeaveType([], ' Marriage Leave ', ' إجازة زواج ');
    expect(r).toEqual({ types: [{ id: 'marriage_leave', name: 'إجازة زواج' }] });
    expect(addLeaveType([{ id: 'x', name: 'x' }], 'X', 'y')).toMatchObject({ duplicate: true });
    expect(addLeaveType([], '', 'y')).toHaveProperty('error');
  });
});

describe('work schedules', () => {
  it('toggles days and keeps them sorted numerically', () => {
    expect(toggleWorkDay([6, 0, 1], 3)).toEqual([0, 1, 3, 6]);
    expect(toggleWorkDay([0, 1, 3], 1)).toEqual([0, 3]);
  });

  it('writes the target into the chosen scope column only', () => {
    const row = buildScheduleRow({ ...DEFAULT_SCHEDULE_FORM, name: ' دوام ', scope: 'department', targetId: 'd1' });
    expect(row).toEqual({
      name: 'دوام', check_in_time: '09:00:00', check_out_time: '17:00:00', grace_period_minutes: 15,
      work_days: [6, 0, 1, 2, 3, 4], department_id: 'd1',
    });
  });

  it('names the target with employee > department > branch priority', () => {
    const targets = { branches: [{ id: 'b', name: 'الكرادة' }], departments: [], employees: [{ id: 'e', full_name: 'علي' }] };
    const ws = (over: Partial<WorkSchedule>) => ({ id: 's', name: 'n', check_in_time: '', check_out_time: '', grace_period_minutes: 0, work_days: [], ...over }) as WorkSchedule;
    expect(scheduleTargetName(ws({ branch_id: 'b', employee_id: 'e' }), targets)).toBe('👤 موظف: علي');
    expect(scheduleTargetName(ws({ department_id: 'x' }), targets)).toBe('🏢 قسم: غير معروف');
    expect(scheduleTargetName(ws({ branch_id: 'b' }), targets)).toBe('📍 فرع: الكرادة');
  });

  it('formats times in 12h', () => {
    expect(formatTime12h('00:05:00')).toBe('12:05 AM');
    expect(formatTime12h('13:30')).toBe('1:30 PM');
    expect(formatTime12h(null)).toBe('--:--');
  });
});

describe('purgeSummary', () => {
  it('lists counts for the selected categories only', () => {
    const msg = purgeSummary(
      { year: 2026, month: 1, notifications: true, tracking: false, absences: true },
      { notifications_deleted: 4, absences_deleted: 10, tracking_deleted: 99 },
    );
    expect(msg).toBe('تم التنظيف بنجاح! 🧹 تم حذف: 4 إشعار، 10 سجل حضور وغياب');
  });
});
