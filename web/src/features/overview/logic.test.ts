import { describe, expect, it } from 'vitest';
import type { GeofenceViolation, LeaveRequest, MockGpsAttempt, WorkSchedule } from '@/lib/db-types';
import { buildSecurityLogs, computeTodayAttendance, type DirectoryEmployee } from './logic';

// 2026-10-04 = الأحد (0)
const today = '2026-10-04';
const emp = (id: string, branch_id = 'b1'): DirectoryEmployee => ({ id, full_name: id, branch_id, department_id: null });
const everyDay = { id: 's1', branch_id: 'b1', employee_id: null, department_id: null, work_days: [0, 1, 2, 3, 4, 5, 6] } as unknown as WorkSchedule;
const offSunday = { id: 's2', branch_id: 'b2', employee_id: null, department_id: null, work_days: [1, 2, 3, 4] } as unknown as WorkSchedule;

describe('computeTodayAttendance', () => {
  it('counts present/late/half_day, and absent only on a working day without leave', () => {
    const employees = [emp('a'), emp('b'), emp('c'), emp('d'), emp('e', 'b2')];
    const leave = { employee_id: 'd', status: 'approved', start_date: today, end_date: today } as unknown as LeaveRequest;
    const { present, absentList } = computeTodayAttendance(
      today,
      [{ employee_id: 'a', status: 'present' }, { employee_id: 'b', status: 'late' }],
      employees,
      [everyDay, offSunday],
      [leave],
    );
    expect(present).toBe(2);
    // c: لا سجل ويوم دوام ← غائب؛ d: مجاز؛ e: فرعه عطلة الأحد
    expect(absentList.map((e) => e.id)).toEqual(['c']);
  });

  it('an absent record on a day off is not counted', () => {
    const { present, absentList } = computeTodayAttendance(today, [{ employee_id: 'e', status: 'absent' }], [emp('e', 'b2')], [offSunday], []);
    expect(present).toBe(0);
    expect(absentList).toEqual([]);
  });
});

describe('buildSecurityLogs', () => {
  it('merges mock GPS and geofence events, newest first, max 5', () => {
    const mocks = Array.from({ length: 4 }, (_, i) => ({ id: `m${i}`, timestamp: `2026-10-0${i + 1}T10:00:00Z`, app_used: 'X', latitude: 33, longitude: 44, employees: { full_name: 'م' } })) as unknown as MockGpsAttempt[];
    const geos = [{ id: 'g1', timestamp: '2026-10-09T10:00:00Z', violation_type: 'exit', employees: null, geofence_zones: { name: 'Z' } }] as unknown as GeofenceViolation[];
    const logs = buildSecurityLogs(mocks, geos);
    expect(logs).toHaveLength(5);
    expect(logs[0]).toMatchObject({ id: 'g1', type: 'geofence', name: 'موظف غير معروف', details: 'خروج غير مصرح به في منطقة: Z' });
    expect(logs[1]).toMatchObject({ id: 'm3', coords: '33, 44' });
  });
});
