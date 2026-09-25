import type {
  Attendance,
  BonusDeduction,
  Employee,
  LeaveRequest,
  LoanInstallment,
  SalarySlip,
  WorkSchedule,
} from './types';
import {
  DEFAULT_CHECK_IN,
  DEFAULT_CHECK_OUT,
  findSchedule,
  formatLateDurationArabic,
  isDateInRange,
  minutesEarly,
  minutesLate,
  workDaysFor,
} from './attendance';
import { formatClock, localDateStr } from './format';

const pad = (n: number) => n.toString().padStart(2, '0');

/**
 * Start and end dates (`YYYY-MM-DD`) of the payroll cycle that ends in
 * `monthStr` (`YYYY-MM`). When the start day is after the end day the cycle
 * begins in the previous month (the default is the 25th → 24th).
 */
export function getCycleDates(monthStr: string, startDay = 25, endDay = 24): { start: string; end: string } {
  if (!monthStr) return { start: '', end: '' };
  const [year, month] = monthStr.split('-').map(Number);
  const lastDaySelected = new Date(year, month, 0).getDate();

  if (startDay <= endDay) {
    const s = Math.min(startDay, lastDaySelected);
    const e = Math.min(endDay, lastDaySelected);
    return { start: `${year}-${pad(month)}-${pad(s)}`, end: `${year}-${pad(month)}-${pad(e)}` };
  }

  const prev = new Date(year, month - 2, 1);
  const prevYear = prev.getFullYear();
  const prevMonth = prev.getMonth() + 1;
  const lastDayPrev = new Date(prevYear, prevMonth, 0).getDate();
  const s = Math.min(startDay, lastDayPrev);
  const e = Math.min(endDay, lastDaySelected);
  return { start: `${prevYear}-${pad(prevMonth)}-${pad(s)}`, end: `${year}-${pad(month)}-${pad(e)}` };
}

export type PayrollField = 'bonuses' | 'attendanceDeductions' | 'otherDeductions';
export type PayrollOverrides = Partial<Record<PayrollField, number>>;

export type DayTone = 'present' | 'excused' | 'absent' | 'leave' | 'warning' | 'late' | 'future';

export interface PayrollDayLog {
  date: string;
  status: string;
  tone: DayTone;
  time: string;
  note: string;
  isAbsenceDay: boolean;
  isExcused?: boolean;
}

export interface PayrollRow extends Employee {
  basic: number;
  scheduledWorkDays: number;
  presentsCount: number;
  latesCount: number;
  totalLateMinutes: number;
  latenessDeduction: number;
  earlyExitsCount: number;
  totalEarlyExitMinutes: number;
  earlyExitDeduction: number;
  workdayMinutes: number;
  halfDaysCount: number;
  absencesCount: number;
  paidLeavesCount: number;
  absenceDeduction: number;
  halfDayDeduction: number;
  totalAttendanceDeductions: number;
  totalBonuses: number;
  totalDeductions: number;
  loanDeduction: number;
  loanInstallmentIds: string[];
  netSalary: number;
  isIssued: boolean;
  detailLogs: PayrollDayLog[];
  isNetNegative: boolean;
  isAttendanceMissing: boolean;
  hasPendingLeave: boolean;
  unconfirmedAbsencesCount: number;
  isBonusesOverridden: boolean;
  isAttendanceDeductionsOverridden: boolean;
  isOtherDeductionsOverridden: boolean;
  computedAttendanceDeductions: number;
  computedBonuses: number;
  computedOtherDeductions: number;
}

export interface PayrollContext {
  selectedMonth: string;
  startDate: string;
  endDate: string;
  schedules: WorkSchedule[];
  attendance: Attendance[];
  leaves: LeaveRequest[];
  bonusesAndDeductions: BonusDeduction[];
  installments: LoanInstallment[];
  slips: SalarySlip[];
  overrides: PayrollOverrides;
  excusedDays: string[];
  /** Injected for deterministic tests; defaults to the current time. */
  now?: Date;
}

function parseLocalDate(dateStr: string): Date {
  const [y, m, d] = dateStr.split('-').map(Number);
  return new Date(y, m - 1, d);
}

/** Basic salary for the month, honouring a scheduled future salary change. */
export function basicSalaryFor(emp: Employee, selectedMonth: string): number {
  let basic = Number(emp.monthly_salary_iqd) || 0;
  if (emp.future_salary_iqd && emp.future_salary_month) {
    if (selectedMonth >= emp.future_salary_month.substring(0, 7)) {
      basic = Number(emp.future_salary_iqd);
    }
  }
  return basic;
}

/** Length of the scheduled working day in minutes (defaults to 8 hours). */
export function workdayMinutesFor(schedule: WorkSchedule | undefined): number {
  if (schedule?.check_in_time && schedule?.check_out_time) {
    const [inH, inM] = schedule.check_in_time.split(':').map(Number);
    const [outH, outM] = schedule.check_out_time.split(':').map(Number);
    const diff = outH * 60 + outM - (inH * 60 + inM);
    if (diff > 0) return diff;
  }
  return 480;
}

/**
 * Computes one employee's payroll line for a cycle: attendance tallies,
 * automatic deductions, bonuses, loan installments and the net salary.
 * Slips that were already issued keep their stored figures.
 */
export function computePayrollRow(emp: Employee, ctx: PayrollContext): PayrollRow {
  const basic = basicSalaryFor(emp, ctx.selectedMonth);
  const now = ctx.now ?? new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  const schedule = findSchedule(emp, ctx.schedules);
  const workDays = workDaysFor(schedule);
  const scheduledIn = schedule?.check_in_time ?? DEFAULT_CHECK_IN;
  const scheduledOut = schedule?.check_out_time ?? DEFAULT_CHECK_OUT;

  let presentsCount = 0;
  let latesCount = 0;
  let totalLateMinutes = 0;
  let earlyExitsCount = 0;
  let totalEarlyExitMinutes = 0;
  let halfDaysCount = 0;
  let absencesCount = 0;
  let paidLeavesCount = 0;
  let scheduledWorkDays = 0;
  let unconfirmedAbsencesCount = 0;
  const detailLogs: PayrollDayLog[] = [];

  const empAttendance = ctx.attendance.filter((a) => a.employee_id === emp.id);
  const empApprovedLeaves = ctx.leaves.filter((l) => l.employee_id === emp.id && l.status === 'approved');

  if (ctx.startDate && ctx.endDate) {
    const end = parseLocalDate(ctx.endDate);
    for (let day = parseLocalDate(ctx.startDate); day <= end; day.setDate(day.getDate() + 1)) {
      if (!workDays.includes(day.getDay())) continue;

      const dateStr = localDateStr(day);
      const isPastOrToday = day <= today;
      if (isPastOrToday) scheduledWorkDays++;

      const att = empAttendance.find((a) => a.work_date === dateStr);
      const leave = empApprovedLeaves.find((l) => isDateInRange(dateStr, l.start_date, l.end_date));

      if (att) {
        const isApplied = att.deduction_status === 'applied';
        const isIgnored = att.deduction_status === 'ignored';
        const earlyMins = minutesEarly(att.check_out_time, scheduledOut);
        const lateMins = att.status === 'late' ? minutesLate(att.check_in_time, scheduledIn) : 0;

        if (isPastOrToday) {
          if (att.status === 'present') presentsCount++;
          else if (att.status === 'late') {
            presentsCount++;
            if (isApplied) {
              latesCount++;
              totalLateMinutes += lateMins;
            }
          } else if (att.status === 'half_day') halfDaysCount++;
          else if (att.status === 'absent' && isApplied) absencesCount++;

          if (earlyMins > 0 && isApplied) {
            earlyExitsCount++;
            totalEarlyExitMinutes += earlyMins;
          }
        }

        let status = 'حاضر';
        let tone: DayTone = 'present';
        const notes: string[] = [];
        if (att.status === 'late') {
          status = isApplied ? 'متأخر (خصم مطبق)' : isIgnored ? 'متأخر (معفى)' : 'متأخر (معلق)';
          tone = isApplied ? 'late' : isIgnored ? 'excused' : 'warning';
          notes.push(`تأخير: ${formatLateDurationArabic(lateMins)}`);
        } else if (att.status === 'half_day') {
          status = 'نصف يوم';
          tone = 'warning';
          notes.push('دوام غير مكتمل');
        } else if (att.status === 'absent') {
          status = isApplied ? 'غياب (خصم مطبق)' : 'غياب (معفى)';
          tone = isApplied ? 'absent' : 'excused';
          notes.push(att.deduction_reason || 'غياب غير مبرر');
        }
        if (earlyMins > 0) {
          notes.push(`خروج مبكر: ${formatLateDurationArabic(earlyMins)}`);
          if (att.status === 'present') {
            status = isApplied ? 'خروج مبكر (خصم)' : 'خروج مبكر (معفى)';
            tone = isApplied ? 'late' : 'excused';
          }
        }

        detailLogs.push({
          date: dateStr,
          status,
          tone,
          time: formatClock(att.check_in_time),
          note: notes.length > 0 ? notes.join(' | ') : 'بصمة دوام اعتيادية',
          isAbsenceDay: false,
        });
      } else if (leave) {
        if (isPastOrToday) {
          if (leave.is_paid) paidLeavesCount++;
          else absencesCount++;
        }
        detailLogs.push({
          date: dateStr,
          status: leave.is_paid ? 'إجازة معتمدة' : 'إجازة بدون راتب',
          tone: leave.is_paid ? 'leave' : 'absent',
          time: '-',
          note: leave.reason ? `سبب الإجازة: ${leave.reason}` : 'إجازة إدارية معتمدة',
          isAbsenceDay: false,
        });
      } else {
        const isToday = day.getTime() === today.getTime();
        const isPast = day < today || (isToday && now.getHours() >= 17);
        if (!isPast) {
          detailLogs.push({
            date: dateStr,
            status: 'لم يحن بعد',
            tone: 'future',
            time: '-',
            note: isToday ? 'قيد الانتظار لموعد الدوام اليوم' : 'يوم عمل مجدول مستقبلي',
            isAbsenceDay: false,
          });
        } else if (ctx.excusedDays.includes(dateStr)) {
          if (isPastOrToday) presentsCount++;
          detailLogs.push({
            date: dateStr,
            status: 'معفى (عذر إداري)',
            tone: 'excused',
            time: '-',
            note: 'غياب تم إعفاؤه إدارياً بواسطة المدير المباشر',
            isAbsenceDay: true,
            isExcused: true,
          });
        } else {
          // No record and no leave: flagged for review, never deducted automatically.
          if (isPastOrToday) unconfirmedAbsencesCount++;
          detailLogs.push({
            date: dateStr,
            status: 'يوم بدون حضور',
            tone: 'warning',
            time: '-',
            note: 'لم يتم تسجيل حضور، ولم يتم تطبيق خصم غياب من قبل الإدارة بعد',
            isAbsenceDay: false,
            isExcused: false,
          });
        }
      }
    }
  }

  const workdayMinutes = workdayMinutesFor(schedule);
  const dailyWage = basic / 30;
  const absenceDeduction = Math.round(absencesCount * dailyWage);
  const halfDayDeduction = Math.round(halfDaysCount * dailyWage * 0.5);
  const latenessDeduction = Math.round(totalLateMinutes * (dailyWage / workdayMinutes));
  const earlyExitDeduction = Math.round(totalEarlyExitMinutes * (dailyWage / workdayMinutes));

  const ov = ctx.overrides;
  const computedAttendanceDeductions = absenceDeduction + halfDayDeduction + latenessDeduction + earlyExitDeduction;
  const finalAttendanceDeductions = ov.attendanceDeductions ?? computedAttendanceDeductions;

  const empBDs = ctx.bonusesAndDeductions.filter((bd) => bd.employee_id === emp.id);
  const computedBonuses = empBDs.filter((bd) => bd.type === 'bonus').reduce((sum, bd) => sum + Number(bd.amount), 0);
  const computedOtherDeductions = empBDs
    .filter((bd) => bd.type === 'deduction')
    .reduce((sum, bd) => sum + Number(bd.amount), 0);
  const finalBonuses = ov.bonuses ?? computedBonuses;
  const finalOtherDeductions = ov.otherDeductions ?? computedOtherDeductions;
  const finalDeductions = finalOtherDeductions + finalAttendanceDeductions;

  const empLoans = ctx.installments.filter((l) => l.loans?.employee_id === emp.id);
  const loanDeduction = empLoans.reduce((sum, l) => sum + Number(l.amount), 0);
  const netSalary = basic + finalBonuses - finalDeductions - loanDeduction;

  const slip = ctx.slips.find((s) => s.employee_id === emp.id);
  const isIssued = !!slip;
  const display = slip
    ? {
        basic: Number(slip.basic_salary),
        bonuses: Number(slip.allowances),
        loans: Number(slip.loans_deduction),
        deductions: Number(slip.deductions),
        net: Number(slip.net_salary),
        attendance: Math.min(Number(slip.deductions), finalAttendanceDeductions),
      }
    : {
        basic,
        bonuses: finalBonuses,
        loans: loanDeduction,
        deductions: finalDeductions,
        net: netSalary,
        attendance: finalAttendanceDeductions,
      };

  return {
    ...emp,
    basic: display.basic,
    scheduledWorkDays,
    presentsCount,
    latesCount,
    totalLateMinutes,
    latenessDeduction,
    earlyExitsCount,
    totalEarlyExitMinutes,
    earlyExitDeduction,
    workdayMinutes,
    halfDaysCount,
    absencesCount,
    paidLeavesCount,
    absenceDeduction,
    halfDayDeduction,
    totalAttendanceDeductions: display.attendance,
    totalBonuses: display.bonuses,
    totalDeductions: display.deductions,
    loanDeduction: display.loans,
    loanInstallmentIds: empLoans.map((l) => l.id),
    netSalary: display.net,
    isIssued,
    detailLogs,
    isNetNegative: !isIssued && display.net < 0,
    isAttendanceMissing:
      !isIssued && scheduledWorkDays > 0 && presentsCount === 0 && absencesCount === 0 && halfDaysCount === 0 && paidLeavesCount === 0,
    hasPendingLeave: !isIssued && ctx.leaves.some((l) => l.employee_id === emp.id && l.status === 'pending'),
    unconfirmedAbsencesCount: isIssued ? 0 : unconfirmedAbsencesCount,
    isBonusesOverridden: ov.bonuses !== undefined,
    isAttendanceDeductionsOverridden: ov.attendanceDeductions !== undefined,
    isOtherDeductionsOverridden: ov.otherDeductions !== undefined,
    computedAttendanceDeductions,
    computedBonuses,
    computedOtherDeductions,
  };
}
