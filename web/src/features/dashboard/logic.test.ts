import { describe, expect, it } from 'vitest';
import type { WorkSchedule } from '@/lib/db-types';
import { buildSecurityLogs, computeTodayAttendance, groupAbsenteesByBranch, sumBy } from './logic';
import type { EmployeeSummary } from './types';

const emp = (id: string, branch_id: string | null = 'b1'): EmployeeSummary => ({ id, full_name: id, branch_id, department_id: null });

describe('computeTodayAttendance', () => {
  // 2026-09-25 جمعة: خارج الدوام الافتراضي (السبت-الخميس)
  const friday = '2026-09-25';
  const thursday = '2026-09-24';
  const fridaySchedule: WorkSchedule = {
    id: 's', name: 'جمعة', branch_id: 'b2', check_in_time: '08:00:00', check_out_time: '16:00:00',
    grace_period_minutes: 0, work_days: [5],
  };

  it('counts present, explicit absences and employees without any record', () => {
    const r = computeTodayAttendance({
      todayStr: thursday,
      attendance: [
        { employee_id: 'a', status: 'present' },
        { employee_id: 'b', status: 'late' },
        { employee_id: 'c', status: 'absent' },
      ],
      employees: [emp('a'), emp('b'), emp('c'), emp('d'), emp('e')],
      leaves: [{ employee_id: 'e', start_date: '2026-09-20T00:00:00', end_date: '2026-09-24T00:00:00' }],
      schedules: [],
    });
    expect(r.present).toBe(2);
    expect(r.absent).toBe(2); // c مسجّل غائب، d بلا سجل؛ e في إجازة
    expect(r.absentList.map(e => e.id)).toEqual(['c', 'd']);
  });

  it('only counts absence on each employee\'s own working days', () => {
    const r = computeTodayAttendance({
      todayStr: friday,
      attendance: [{ employee_id: 'a', status: 'absent' }],
      employees: [emp('a'), emp('f', 'b2')],
      leaves: [],
      schedules: [fridaySchedule],
    });
    expect(r.absentList.map(e => e.id)).toEqual(['f']);
  });
});

describe('buildSecurityLogs', () => {
  it('merges both sources newest first and caps the list', () => {
    const logs = buildSecurityLogs(
      [{ id: 'm1', timestamp: '2026-09-25T08:00:00Z', app_used: 'Fake GPS', latitude: 33.3, longitude: 44.4, employees: { full_name: 'علي' } }],
      [{ id: 'g1', timestamp: '2026-09-25T09:00:00Z', violation_type: 'exit', employees: null, geofence_zones: { name: 'المصنع' } }],
      1,
    );
    expect(logs).toHaveLength(1);
    expect(logs[0]).toMatchObject({ id: 'g1', type: 'geofence', name: 'موظف غير معروف', details: 'خروج غير مصرح به في منطقة: المصنع' });
  });
});

describe('helpers', () => {
  it('sums numeric-ish values, ignoring nulls', () => {
    expect(sumBy([{ v: '10' }, { v: null }, { v: 5 }], r => r.v)).toBe(15);
    expect(sumBy(null, () => 1)).toBe(0);
  });

  it('groups absentees by branch order with an unassigned group last', () => {
    const groups = groupAbsenteesByBranch([emp('a', 'b2'), emp('b', null), emp('c', 'b1')], [
      { id: 'b1', name: 'الأول' }, { id: 'b2', name: 'الثاني' }, { id: 'b3', name: 'فارغ' },
    ]);
    expect(groups.map(g => [g.key, g.employees.map(e => e.id)])).toEqual([['b1', ['c']], ['b2', ['a']], ['none', ['b']]]);
  });
});
