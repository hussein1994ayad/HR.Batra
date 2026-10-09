import { describe, expect, it } from 'vitest';
import { attentionReasons, buildPayrollRows, canApproveNow, buildSlipAdjustments, describeEvent, sumPayroll, type PayrollEvent, type PayrollRun, type RunRow } from './calc';

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

  it('flags a leaver who still owes a loan', () => {
    const [x] = buildPayrollRows({ run: { ...run, rows: [{ ...baseRow, termination_date: '2026-09-20', loan_balance_after_exit: 200000 }] }, events: [], overrides: {} });
    expect(x.loanBalanceAfterExit).toBe(200000);
    expect(row.loanBalanceAfterExit).toBe(0);
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

describe('attention before approving', () => {
  const rowOf = (over: Partial<RunRow>) =>
    buildPayrollRows({ run: { ...run, rows: [{ ...baseRow, pending_count: 0, ...over }] }, events: [], overrides: {} })[0];

  it('ready rows need nothing', () => {
    expect(attentionReasons(rowOf({ attended_days: 20, scheduled_days: 22 }))).toEqual([]);
  });

  it('never attended, left with a loan, negative net and pending decisions are explained in plain words', () => {
    const kinds = (r: ReturnType<typeof rowOf>) => attentionReasons(r).map((a) => a.kind);
    expect(kinds(rowOf({ attended_days: 0, scheduled_days: 22 }))).toEqual(['never_attended']);
    expect(kinds(rowOf({ attended_days: 3, scheduled_days: 3, termination_date: '2026-09-03', loan_balance_after_exit: 400000 })))
      .toEqual(['left_with_loan']);
    expect(kinds(rowOf({ basic: 100000, loans: 500000 }))).toContain('negative');
    expect(kinds(rowOf({ pending_count: 3 }))).toEqual(['decisions']);
    // بيانات ناقصة: راتب صفر / بدون فرع / بدون جدول
    const data = attentionReasons(rowOf({ monthly_salary: 0, branch_id: null, has_schedule: false })).find((x) => x.kind === 'data');
    expect(data?.text).toContain('الراتب صفر');
    expect(data?.text).toContain('بدون فرع');
    expect(data?.text).toContain('بدون جدول');
  });

  it('this month loan installments come through for the details', () => {
    const r = rowOf({ loan_items: [{ installment_id: 'i', loan_id: 'l', loan_amount: 500000, due_date: '2026-09-26', amount: 50000 }] });
    expect(r.loanItems).toHaveLength(1);
  });
});

describe('approval after the payroll period ends', () => {
  const row = (terminationDate: string | null = null, isIssued = false) => ({ terminationDate, isIssued });
  it('waits for the cutoff, except the last salary of someone who already left', () => {
    expect(canApproveNow(row(), '2026-09-27', '2026-10-26', '2026-10-09')).toBe(false);
    expect(canApproveNow(row(), '2026-09-27', '2026-10-26', '2026-10-27')).toBe(true);
    expect(canApproveNow(row('2026-10-05'), '2026-09-27', '2026-10-26', '2026-10-09')).toBe(true);
    expect(canApproveNow(row('2026-10-12'), '2026-09-27', '2026-10-26', '2026-10-09')).toBe(false);
    expect(canApproveNow(row(null, true), '2026-09-27', '2026-10-26', '2026-10-30')).toBe(false);
  });
});

