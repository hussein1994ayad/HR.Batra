import { describe, expect, it } from 'vitest';
import { basicSalaryFor, computePayrollRow, getCycleDates, workdayMinutesFor, type PayrollContext } from '@/lib/payroll';
import type { Attendance, Employee, LeaveRequest } from '@/lib/types';

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

describe('salary helpers', () => {
  const emp: Employee = { id: 'e', full_name: 'x', monthly_salary_iqd: 900000, future_salary_iqd: 1200000, future_salary_month: '2026-09-01' };
  it('applies a scheduled salary change from its month onwards', () => {
    expect(basicSalaryFor(emp, '2026-08')).toBe(900000);
    expect(basicSalaryFor(emp, '2026-09')).toBe(1200000);
    expect(basicSalaryFor(emp, '2026-10')).toBe(1200000);
  });
  it('derives the workday length from the schedule', () => {
    expect(workdayMinutesFor(undefined)).toBe(480);
    expect(
      workdayMinutesFor({ id: 's', name: 's', check_in_time: '08:00:00', check_out_time: '14:00:00', grace_period_minutes: 0, work_days: [] }),
    ).toBe(360);
  });
});

// Scenario: cycle 2026-08-25 → 2026-09-24 (31 days, 4 Fridays → 27 working days
// on the default Saturday–Thursday week). Times are Baghdad (UTC+3).
const employee: Employee = { id: 'e1', full_name: 'أحمد', monthly_salary_iqd: 900000, branch_id: 'b1', department_id: null };

const att = (date: string, status: string, extra: Partial<Attendance> = {}): Attendance => ({
  id: `a_${date}`,
  employee_id: 'e1',
  work_date: date,
  status,
  ...extra,
});

const leave = (start: string, end: string, isPaid: boolean): LeaveRequest => ({
  id: `l_${start}`,
  employee_id: 'e1',
  start_date: start,
  end_date: end,
  leave_type: 'annual',
  is_paid: isPaid,
  status: 'approved',
});

function context(over: Partial<PayrollContext> = {}): PayrollContext {
  return {
    selectedMonth: '2026-09',
    startDate: '2026-08-25',
    endDate: '2026-09-24',
    schedules: [],
    attendance: [
      att('2026-09-01', 'late', { check_in_time: '2026-09-01T06:30:00Z', deduction_status: 'applied' }), // 30 min late
      att('2026-09-02', 'absent', { deduction_status: 'applied' }),
      att('2026-09-03', 'half_day'),
      att('2026-09-06', 'present', { check_out_time: '2026-09-06T13:00:00Z', deduction_status: 'applied' }), // left 1h early
      att('2026-09-07', 'present'),
    ],
    leaves: [leave('2026-09-08', '2026-09-09', true), leave('2026-09-10', '2026-09-10', false)],
    bonusesAndDeductions: [
      { id: 'b', employee_id: 'e1', type: 'bonus', amount: 50000, reason: 'r', issue_date: '2026-09-05' },
      { id: 'd', employee_id: 'e1', type: 'deduction', amount: 20000, reason: 'r', issue_date: '2026-09-05' },
      { id: 'o', employee_id: 'someone-else', type: 'bonus', amount: 999999, reason: 'r', issue_date: '2026-09-05' },
    ],
    installments: [{ id: 'i1', loan_id: 'l1', due_date: '2026-09-01', amount: 100000, is_paid: false, loans: { employee_id: 'e1' } }],
    slips: [],
    overrides: {},
    excusedDays: ['2026-09-13'],
    now: new Date('2026-09-30T12:00:00+03:00'),
    ...over,
  };
}

describe('computePayrollRow', () => {
  it('tallies attendance for the cycle', () => {
    const row = computePayrollRow(employee, context());
    expect(row.scheduledWorkDays).toBe(27);
    expect(row.presentsCount).toBe(4); // late + two present days + one excused day
    expect(row.latesCount).toBe(1);
    expect(row.totalLateMinutes).toBe(30);
    expect(row.earlyExitsCount).toBe(1);
    expect(row.totalEarlyExitMinutes).toBe(60);
    expect(row.halfDaysCount).toBe(1);
    expect(row.absencesCount).toBe(2); // applied absence + unpaid leave
    expect(row.paidLeavesCount).toBe(2);
    expect(row.unconfirmedAbsencesCount).toBe(18);
    expect(row.detailLogs).toHaveLength(27);
  });

  it('computes deductions from the daily wage (salary / 30)', () => {
    const row = computePayrollRow(employee, context());
    expect(row.absenceDeduction).toBe(60000);
    expect(row.halfDayDeduction).toBe(15000);
    expect(row.latenessDeduction).toBe(1875); // 30 min × 30000/480
    expect(row.earlyExitDeduction).toBe(3750); // 60 min × 30000/480
    expect(row.totalAttendanceDeductions).toBe(80625);
  });

  it('computes the net salary with bonuses, deductions and loans', () => {
    const row = computePayrollRow(employee, context());
    expect(row.totalBonuses).toBe(50000);
    expect(row.totalDeductions).toBe(20000 + 80625);
    expect(row.loanDeduction).toBe(100000);
    expect(row.loanInstallmentIds).toEqual(['i1']);
    expect(row.netSalary).toBe(900000 + 50000 - 100625 - 100000);
    expect(row.isNetNegative).toBe(false);
    expect(row.isIssued).toBe(false);
  });

  it('applies manual overrides', () => {
    const row = computePayrollRow(employee, context({ overrides: { attendanceDeductions: 0, bonuses: 75000 } }));
    expect(row.totalAttendanceDeductions).toBe(0);
    expect(row.totalBonuses).toBe(75000);
    expect(row.computedAttendanceDeductions).toBe(80625);
    expect(row.isAttendanceDeductionsOverridden).toBe(true);
    expect(row.isBonusesOverridden).toBe(true);
    expect(row.isOtherDeductionsOverridden).toBe(false);
    expect(row.netSalary).toBe(900000 + 75000 - 20000 - 100000);
  });

  it('shows the stored figures once a slip is issued', () => {
    const row = computePayrollRow(
      employee,
      context({
        slips: [
          { id: 's', employee_id: 'e1', work_month: '2026-09', basic_salary: 900000, allowances: 1, deductions: 2, loans_deduction: 3, net_salary: 894, status: 'published' },
        ],
      }),
    );
    expect(row.isIssued).toBe(true);
    expect(row.netSalary).toBe(894);
    expect(row.totalBonuses).toBe(1);
    expect(row.unconfirmedAbsencesCount).toBe(0);
  });

  it('does not count days after today, and waits until 17:00 for today', () => {
    const row = computePayrollRow(
      employee,
      context({ attendance: [], leaves: [], excusedDays: [], now: new Date('2026-09-10T10:00:00+03:00') }),
    );
    // Aug 25 → Sep 10 contains 15 working days (Fridays Aug 28, Sep 4 excluded).
    expect(row.scheduledWorkDays).toBe(15);
    const today = row.detailLogs.find((l) => l.date === '2026-09-10');
    expect(today?.tone).toBe('future');
    expect(row.unconfirmedAbsencesCount).toBe(14);
  });

  it('flags missing attendance and negative net salary', () => {
    const row = computePayrollRow(
      { ...employee, monthly_salary_iqd: 10000 },
      context({ attendance: [], leaves: [], excusedDays: [] }),
    );
    expect(row.isAttendanceMissing).toBe(true);
    expect(row.isNetNegative).toBe(true);
  });

  it('respects a custom schedule (work days and hours)', () => {
    const row = computePayrollRow(
      employee,
      context({
        schedules: [
          { id: 's', name: 'short', employee_id: 'e1', check_in_time: '09:00:00', check_out_time: '13:00:00', grace_period_minutes: 0, work_days: [0] },
        ],
        attendance: [att('2026-09-06', 'late', { check_in_time: '2026-09-06T06:40:00Z', deduction_status: 'applied' })],
        leaves: [],
        excusedDays: [],
      }),
    );
    // Only Sundays: Aug 30, Sep 6, 13, 20.
    expect(row.scheduledWorkDays).toBe(4);
    expect(row.totalLateMinutes).toBe(40);
    // 40 min × (30000 / 240)
    expect(row.latenessDeduction).toBe(5000);
  });
});
