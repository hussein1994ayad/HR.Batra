import { describe, expect, it } from 'vitest';
import type { AttendanceRecord, Employee, WorkSchedule } from '@/lib/db-types';
import { buildPayrollRows, buildSlipAdjustments, sumPayroll, type PayrollInput } from './calc';

// دورة 2026-08-25 → 2026-09-24، دوام 08:00–16:00 (480 دقيقة) من الأحد للخميس.
// الراتب 3,000,000 → أجرة اليوم 100,000.
const employee: Employee = {
  id: 'e1',
  employee_code: 'E1',
  full_name: 'موظف تجريبي',
  is_active: true,
  role: 'employee',
  branch_id: 'b1',
  department_id: null,
  monthly_salary_iqd: 3_000_000,
  join_date: '2025-01-01',
  created_at: '2025-01-01T00:00:00Z',
};

const schedule: WorkSchedule = {
  id: 's1',
  branch_id: 'b1',
  name: 'دوام الفرع',
  check_in_time: '08:00:00',
  check_out_time: '16:00:00',
  grace_period_minutes: 15,
  work_days: [0, 1, 2, 3, 4],
};

const att = (date: string, status: string, checkIn: string | null, checkOut: string | null): AttendanceRecord => ({
  id: `a-${date}`,
  employee_id: 'e1',
  branch_id: 'b1',
  work_date: date,
  status,
  check_in_time: checkIn,
  check_out_time: checkOut,
  deduction_status: 'applied',
});

const baseInput = (): PayrollInput => ({
  employees: [employee],
  workSchedules: [schedule],
  attendanceLogs: [
    att('2026-08-26', 'late', '2026-08-26T05:30:00Z', '2026-08-26T13:00:00Z'), // تأخير 30 دقيقة
    att('2026-08-27', 'absent', null, null),                                    // غياب
    att('2026-08-30', 'half_day', '2026-08-30T05:00:00Z', null),                // نصف يوم
    att('2026-08-31', 'present', '2026-08-31T05:00:00Z', '2026-08-31T12:00:00Z'), // خروج مبكر ساعة
  ],
  leaveRequests: [{
    id: 'l1', employee_id: 'e1', leave_type: 'annual', is_hourly: false, is_paid: true, status: 'approved',
    start_date: '2026-09-01T00:00:00', end_date: '2026-09-01T00:00:00',
  }],
  bonusesAndDeductions: [
    { id: 'bd1', employee_id: 'e1', type: 'bonus', amount: 50_000, reason: 'مكافأة', issue_date: '2026-09-10' },
    { id: 'bd2', employee_id: 'e1', type: 'deduction', amount: 20_000, reason: 'خصم', issue_date: '2026-09-11' },
  ],
  loanInstallments: [{
    id: 'i1', loan_id: 'loan1', due_date: '2026-09-20', amount: 100_000, is_paid: false,
    loans: { employee_id: 'e1' },
  }],
  existingSlips: [],
  payrollOverrides: {},
  excusedDays: {},
  selectedMonth: '2026-09',
  startDate: '2026-08-25',
  endDate: '2026-09-24',
  now: new Date('2026-10-01T12:00:00'),
});

describe('buildPayrollRows', () => {
  it('computes attendance deductions, bonuses, loans and net salary', () => {
    const [row] = buildPayrollRows(baseInput());

    expect(row.absenceDeduction).toBe(100_000);
    expect(row.halfDayDeduction).toBe(50_000);
    expect(row.totalLateMinutes).toBe(30);
    expect(row.latenessDeduction).toBe(6_250);
    expect(row.totalEarlyExitMinutes).toBe(60);
    expect(row.earlyExitDeduction).toBe(12_500);
    expect(row.totalAttendanceDeductions).toBe(168_750);
    expect(row.totalBonuses).toBe(50_000);
    expect(row.totalDeductions).toBe(188_750);
    expect(row.loanDeduction).toBe(100_000);
    expect(row.loanInstallmentIds).toEqual(['i1']);
    expect(row.netSalary).toBe(3_000_000 + 50_000 - 188_750 - 100_000);
    expect(row.paidLeavesCount).toBe(1);
    expect(row.isIssued).toBe(false);
  });

  it('applies manual overrides and records them as slip adjustments', () => {
    const input = baseInput();
    input.payrollOverrides = { e1: { bonuses: 80_000 } };
    const [row] = buildPayrollRows(input);

    expect(row.totalBonuses).toBe(80_000);
    expect(row.isBonusesOverridden).toBe(true);

    const adjustments = buildSlipAdjustments(row, input);
    expect(adjustments).toContainEqual({
      type: 'bonus', amount: 30_000, reason: 'تسوية زيادة مكافآت يدوياً لشهر 2026-09',
      issue_date: '2026-09-24', skip_if_exists: false,
    });
    // تفاصيل خصومات الحضور تُسجّل بدون تكرار
    expect(adjustments.filter(a => a.skip_if_exists).map(a => a.amount)).toEqual([100_000, 50_000, 6_250, 12_500]);
  });

  it('shows the stored figures once the slip is issued', () => {
    const input = baseInput();
    input.existingSlips = [{
      id: 'slip1', employee_id: 'e1', work_month: '2026-09', basic_salary: 3_000_000, allowances: 0,
      deductions: 0, loans_deduction: 0, net_salary: 2_900_000, status: 'published',
    }];
    const [row] = buildPayrollRows(input);
    expect(row.isIssued).toBe(true);
    expect(row.netSalary).toBe(2_900_000);
  });

  it('prorates the basic salary for mid-cycle joiners', () => {
    const input = baseInput();
    input.employees = [{ ...employee, join_date: '2026-09-10' }];
    const [row] = buildPayrollRows(input);
    // 31 يوم في الدورة، 15 يوم عمل منذ المباشرة
    expect(row.basic).toBe(Math.round((3_000_000 / 31) * 15));
  });

  it('skips employees who joined after the cycle', () => {
    const input = baseInput();
    input.employees = [{ ...employee, join_date: '2026-10-05' }];
    expect(buildPayrollRows(input)).toHaveLength(0);
  });

  it('sums columns', () => {
    const rows = buildPayrollRows(baseInput());
    expect(sumPayroll(rows)).toMatchObject({ basic: 3_000_000, bonuses: 50_000, loans: 100_000, otherDeductions: 20_000 });
  });
});
