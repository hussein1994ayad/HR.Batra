import { describe, expect, it } from 'vitest';
import { buildPayrollRows, buildSlipAdjustments, describeEvent, sumPayroll, type PayrollEvent, type PayrollRun, type RunRow } from './calc';

// مسير أيلول 2026: 1 → 26. راتب 600,000 → أجر اليوم 20,000، دوام 480 دقيقة.
const baseRow: RunRow = {
  employee_id: 'e1', full_name: 'موظف', branch_id: 'b1', branch_name: 'الفرع', is_active: true,
  period_days: 26, employed_days: 26, monthly_salary: 600000, daily_rate: 20000, minute_rate: 41.666667, shift_minutes: 480,
  basic: 600000, earnings: 3750, bonuses: 0, overtime: 3750, deductions: 48250, attendance_deductions: 41250, loans: 50000,
  net: 505500, pending_count: 2, missing_punches: 1, absence_days: 2, late_minutes: 30, early_minutes: 0, overtime_minutes: 60,
  paid_leave_days: 0, unpaid_leave_days: 0, slip: null,
};
const run: PayrollRun = {
  period: { period_month: '2026-09', start_date: '2026-09-01', cutoff_date: '2026-09-26', payment_date: '2026-09-30', status: 'open' },
  rows: [baseRow],
};
const ev = (id: string, type: PayrollEvent['event_type'], amount: number, direction: -1 | 0 | 1, extra: Partial<PayrollEvent> = {}): PayrollEvent => ({
  id, employee_id: 'e1', event_date: '2026-09-10', event_type: type, minutes: 0, days: 0, amount, direction,
  payroll_month: '2026-09', status: 'approved', source: 'attendance', ...extra,
});
const events: PayrollEvent[] = [
  ev('a1', 'absence', 20000, -1, { days: 1, event_date: '2026-09-10' }),
  ev('a2', 'absence', 20000, -1, { days: 1, event_date: '2026-09-26' }),
  ev('l1', 'late', 1250, -1, { minutes: 30, event_date: '2026-09-24' }),
  ev('o1', 'overtime', 3750, 1, { minutes: 60 }),
  ev('m1', 'manual_deduction', 7000, -1, { source: 'manual', notes: 'كسر زجاج' }),
  ev('p1', 'early_leave', 5000, -1, { status: 'pending', minutes: 120 }),
  ev('v1', 'absence', 20000, -1, { status: 'void' }),
];

describe('buildPayrollRows', () => {
  const [row] = buildPayrollRows({ run, events, overrides: {}, attendanceEmployeeIds: ['e1'] });

  it('shows the server numbers as they are', () => {
    expect(row.basic).toBe(600000);
    expect(row.totalBonuses).toBe(3750);
    expect(row.totalAttendanceDeductions).toBe(41250);
    expect(row.totalDeductions).toBe(48250);
    expect(row.loanDeduction).toBe(50000);
    expect(row.netSalary).toBe(600000 + 3750 - 48250 - 50000);
    expect(row.dailyRate).toBe(20000);
  });

  it('splits approved events into lists and ignores void/pending in totals', () => {
    expect(row.absenceDeduction).toBe(40000);
    expect(row.latenessDeduction).toBe(1250);
    expect(row.earlyExitDeduction).toBe(0);
    expect(row.bonusesList.map((b) => b.id)).toEqual(['o1']);
    expect(row.otherDeductionsList).toEqual([{ id: 'm1', reason: 'كسر زجاج', issue_date: '2026-09-10', amount: 7000 }]);
    expect(row.events.some((e) => e.id === 'v1')).toBe(false);
    expect(row.pendingCount).toBe(2);
  });

  it('applies manual overrides and recomputes the net', () => {
    const [o] = buildPayrollRows({ run, events, overrides: { e1: { bonuses: 10000, attendanceDeductions: 20000 } } });
    expect(o.totalBonuses).toBe(10000);
    expect(o.totalDeductions).toBe(20000 + 7000);
    expect(o.netSalary).toBe(600000 + 10000 - 27000 - 50000);
    expect(buildSlipAdjustments(o, '2026-09')).toEqual([
      { type: 'bonus', amount: 6250, reason: 'تعديل يدوي بزيادة المكافآت لمسير 2026-09' },
      { type: 'bonus', amount: 21250, reason: 'تعديل يدوي بتخفيض خصومات الدوام لمسير 2026-09' },
    ]);
    expect(buildSlipAdjustments(row, '2026-09')).toEqual([]);
  });

  it('an approved slip is shown with its stored numbers', () => {
    const slipRun: PayrollRun = {
      ...run,
      rows: [{ ...baseRow, slip: { id: 's1', basic_salary: 600000, allowances: 0, deductions: 20000, loans_deduction: 0, net_salary: 580000, legacy: false } }],
    };
    const [s] = buildPayrollRows({ run: slipRun, events, overrides: { e1: { bonuses: 99 } } });
    expect(s.isIssued).toBe(true);
    expect(s.netSalary).toBe(580000);
    expect(s.totalAttendanceDeductions).toBe(20000);
    expect(s.pendingCount).toBe(0);
  });

  it('flags missing attendance and negative nets', () => {
    const [m] = buildPayrollRows({ run: { ...run, rows: [{ ...baseRow, loans: 900000 }] }, events: [], overrides: {}, attendanceEmployeeIds: [] });
    expect(m.isAttendanceMissing).toBe(true);
    expect(m.isNetNegative).toBe(true);
    expect(sumPayroll([row]).attendanceDeductions).toBe(41250);
  });
});

describe('describeEvent', () => {
  it('uses minutes for partial events', () => {
    expect(describeEvent(events[2])).toBe('تأخير 30 دقيقة');
    expect(describeEvent(events[0])).toBe('غياب');
  });
});
