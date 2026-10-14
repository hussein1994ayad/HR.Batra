import { describe, expect, it } from 'vitest';
import type { AttendanceRecord, WorkSchedule } from '@/lib/db-types';
import { analyzeTrail, buildAttendanceRows, buildDecisions, formatHours, needsOfflineReview, parseZonePolygons, punchTimeInfo } from './logic';
import type { TrackedEmployee } from './types';

describe('analyzeTrail', () => {
  it('drops stationary duplicates and detects stops of 5+ minutes', () => {
    const t = (min: number) => new Date(Date.UTC(2026, 8, 1, 6, min)).toISOString();
    const { coords, stops } = analyzeTrail([
      { latitude: 33.3, longitude: 44.4, timestamp: t(0) },
      { latitude: 33.30001, longitude: 44.4, timestamp: t(3) },  // نفس المكان
      { latitude: 33.30002, longitude: 44.4, timestamp: t(10) }, // بقي 10 دقائق
      { latitude: 33.31, longitude: 44.41, timestamp: t(12) },   // تحرّك
      { latitude: 33.32, longitude: 44.42, timestamp: t(14) },
    ]);
    expect(coords).toHaveLength(3);
    expect(stops).toHaveLength(1);
    expect(stops[0].duration).toBe(10);
  });
});

describe('buildDecisions', () => {
  const emp: TrackedEmployee = { id: 'e1', full_name: 'موظف', branch_id: 'b1', department_id: null, role: 'employee' };
  const schedule: WorkSchedule = {
    id: 's1', branch_id: 'b1', name: 'فرع', check_in_time: '08:00:00', check_out_time: '16:00:00',
    grace_period_minutes: 15, work_days: [0, 1, 2, 3, 4],
  };
  const base = {
    employees: [emp], workSchedules: [schedule], leaveRequests: [],
    selectedBranch: 'all', selectedEmployee: 'all',
    startDate: '2026-09-01', endDate: '2026-09-03', // ثلاثاء، أربعاء، خميس
  };

  it('lists late check-ins, recorded absences and days without any punch', () => {
    const attendanceLogs: AttendanceRecord[] = [
      { id: 'a1', employee_id: 'e1', branch_id: 'b1', work_date: '2026-09-01', status: 'late', check_in_time: '2026-09-01T05:20:00Z' },
      { id: 'a2', employee_id: 'e1', branch_id: 'b1', work_date: '2026-09-02', status: 'absent' },
    ];
    const list = buildDecisions({ ...base, attendanceLogs });
    expect(list.map(d => d.type)).toEqual(['late', 'absent', 'virtual_absent']);
    expect(list[0].suggestedAmount).toBe(0); // المبلغ من محرّك الرواتب فقط (لا مبالغ ثابتة)
    expect(list[2].date).toBe('2026-09-03');

    // قبل المباشرة: لا غياب
    expect(buildDecisions({ ...base, attendanceLogs: [], employees: [{ ...emp, join_date: '2026-09-03' }] }).map(d => d.date)).toEqual(['2026-09-03']);
    // بعد آخر يوم عمل: لا غياب
    expect(buildDecisions({ ...base, attendanceLogs: [], employees: [{ ...emp, termination_date: '2026-09-01' }] }).map(d => d.date)).toEqual(['2026-09-01']);
    // يوم عطلة رسمية: لا غياب افتراضي
    expect(buildDecisions({ ...base, attendanceLogs, holidays: ['2026-09-03'] }).map(d => d.type)).toEqual(['late', 'absent']);

    const rows = buildAttendanceRows(attendanceLogs, list);
    expect(rows.filter(r => r.is_virtual)).toHaveLength(1);
  });

  it('respects approved leave and non-working days', () => {
    const list = buildDecisions({
      ...base,
      startDate: '2026-09-03', endDate: '2026-09-05', // خميس، جمعة، سبت
      attendanceLogs: [],
      leaveRequests: [{
        id: 'l1', employee_id: 'e1', leave_type: 'annual', is_hourly: false, is_paid: true, status: 'approved',
        start_date: '2026-09-03T00:00:00', end_date: '2026-09-03T00:00:00',
      }],
    });
    expect(list).toHaveLength(0);
  });
});

describe('parseZonePolygons', () => {
  it('accepts every stored coordinate shape', () => {
    const [a, b, c] = parseZonePolygons([
      { id: '1', name: 'arrays', coordinates: [[33.1, 44.1], ['33.2', '44.2']] },
      { id: '2', name: 'lat/lng', coordinates: JSON.stringify([{ lat: 33.3, lng: 44.3 }]) },
      { id: '3', name: 'legacy', polygon_coordinates: [{ latitude: 33.4, longitude: 44.4 }] },
    ]);
    expect(a.coords).toEqual([[33.1, 44.1], [33.2, 44.2]]);
    expect(b.coords).toEqual([[33.3, 44.3]]);
    expect(c.coords).toEqual([[33.4, 44.4]]);
  });
});

describe('formatHours', () => {
  it('formats worked duration', () => {
    expect(formatHours('2026-09-01T05:00:00Z', '2026-09-01T13:15:00Z')).toBe('8 س و 15 د');
    expect(formatHours(null, '2026-09-01T13:15:00Z')).toBe('-');
  });
});

describe('punchTimeInfo (offline punches, audit 14/10 BUG-001)', () => {
  const t = '2026-10-15T06:30:00Z';
  it('an online punch shows nothing', () => {
    expect(punchTimeInfo(t, 'online', null)).toBeNull();
    expect(punchTimeInfo(t, null, null)).toBeNull();
  });
  it('an offline punch with a changed phone clock shows the difference in minutes', () => {
    expect(punchTimeInfo(t, 'offline_verified', '2026-10-15T04:30:00Z')).toEqual({ kind: 'offline', clockDiffMinutes: 120 });
  });
  it('flags punches that need review until they are reviewed', () => {
    expect(punchTimeInfo(t, 'offline_review', t)?.kind).toBe('review');
    expect(needsOfflineReview({ check_in_time_source: 'online', check_out_time_source: 'offline_review' })).toBe(true);
    expect(needsOfflineReview({ check_in_time_source: 'offline_reviewed', check_out_time_source: 'manual' })).toBe(false);
  });
});
