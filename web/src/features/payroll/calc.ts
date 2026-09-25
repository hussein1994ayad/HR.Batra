// =========================================================================
// حساب كشف الرواتب — منطق نقي بدون React أو Supabase (قابل للاختبار)
// =========================================================================
// منقول كما هو من صفحة الرواتب؛ الفرق الوحيد أن "الآن" يُمرَّر كمعامل (now)
// بدل new Date() حتى يمكن اختبار الحساب بتاريخ ثابت.

import type {
  AttendanceRecord, BonusDeduction, Employee, LeaveRequest, LoanInstallment, SalarySlip, WorkSchedule,
} from '@/lib/db-types';
import { formatLateDurationArabic, getBaghdadMinutesFromIso, parseScheduleMinutes } from '@/lib/dates';
import { resolveWorkSchedule } from '@/lib/schedules';
import type { DetailLog, ExcusedDays, PayrollOverrides, SlipAdjustment } from './types';

export interface PayrollInput {
  employees: Employee[];
  workSchedules: WorkSchedule[];
  attendanceLogs: AttendanceRecord[];
  leaveRequests: LeaveRequest[];
  bonusesAndDeductions: BonusDeduction[];
  loanInstallments: LoanInstallment[];
  existingSlips: SalarySlip[];
  payrollOverrides: PayrollOverrides;
  excusedDays: ExcusedDays;
  selectedMonth: string;
  startDate: string;
  endDate: string;
  /** اللحظة الحالية (للاختبار). */
  now?: Date;
}

/** صفوف جدول الرواتب: بيانات الموظف + الحضور + الخصومات + الصافي. */
export function buildPayrollRows(input: PayrollInput) {
  const {
    employees, workSchedules, attendanceLogs, leaveRequests, bonusesAndDeductions,
    loanInstallments, existingSlips, payrollOverrides, excusedDays, selectedMonth, startDate, endDate,
  } = input;
  const now = input.now ?? new Date();

  // Filter out employees who joined AFTER the end of this payroll cycle
  const validEmployees = employees.filter(emp => {
    const effectiveJoinDate = emp.join_date || emp.created_at;
    if (!effectiveJoinDate) return true;
    const createdDate = new Date(effectiveJoinDate).getTime();
    const cycleEnd = new Date(endDate + 'T23:59:59.999Z').getTime();
    return createdDate <= cycleEnd;
  });

  // Compile processed payroll data with smart attendance & absence calculation
  const processedPayroll = validEmployees.map(emp => {
    let nominalBasic = emp.monthly_salary_iqd || 0;
    
    if (emp.future_salary_iqd && emp.future_salary_month) {
      const futureMonthStr = emp.future_salary_month.substring(0, 7);
      if (selectedMonth >= futureMonthStr) {
        nominalBasic = emp.future_salary_iqd;
      }
    }

    let basic = nominalBasic;
    const start = new Date(startDate);
    const end = new Date(endDate);

    // Prorate salary if the employee joined mid-cycle
    const effectiveJoinDateStr = emp.join_date;
    if (effectiveJoinDateStr) {
      const joinDate = new Date(effectiveJoinDateStr);
      const joinDay = new Date(joinDate.getFullYear(), joinDate.getMonth(), joinDate.getDate());
      const startDay = new Date(start.getFullYear(), start.getMonth(), start.getDate());
      
      if (joinDay > startDay) {
        const totalCycleDays = Math.round((end.getTime() - startDay.getTime()) / (1000 * 3600 * 24)) + 1;
        const daysWorkedInCycle = Math.round((end.getTime() - joinDay.getTime()) / (1000 * 3600 * 24)) + 1;
        
        if (daysWorkedInCycle > 0 && daysWorkedInCycle < totalCycleDays) {
          basic = Math.round((nominalBasic / totalCycleDays) * daysWorkedInCycle);
        }
      }
    }
    
    // Dynamic Attendance Calculations
    
    // Define the limit day (if selectedRange is current month, calculate up to today)
    const today = new Date(now);
    const todayNormalized = new Date(today.getFullYear(), today.getMonth(), today.getDate());

    // Get work schedules for the employee (employee-specific -> department -> default)
    // Default working schedule in Iraq is Saturday(6) to Thursday(4)
    const empSched = resolveWorkSchedule(emp, workSchedules);
    const workDays = empSched ? empSched.work_days : [6, 0, 1, 2, 3, 4];

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

    const detailLogs: DetailLog[] = [];
    const empExcuses = excusedDays[emp.id] || [];

    let joinDay: Date | null = null;
    if (emp.created_at) {
      const jd = new Date(emp.created_at);
      joinDay = new Date(jd.getFullYear(), jd.getMonth(), jd.getDate());
    }

    const loopDate = new Date(start);
    while (loopDate <= end) {
      const year = loopDate.getFullYear();
      const month = loopDate.getMonth() + 1;
      const day = loopDate.getDate();
      const dateStr = `${year}-${month.toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}`;
      
      const weekday = loopDate.getDay(); // JS getDay: 0 is Sunday, 1 is Monday... 6 is Saturday
      const isWorkingDay = workDays.includes(weekday);
      
      if (isWorkingDay) {
        const isBeforeJoining = joinDay && loopDate < joinDay;

        if (isBeforeJoining) {
          detailLogs.push({
            date: dateStr,
            status: 'قبل التعيين 🕒',
            time: '-',
            note: 'هذا اليوم يسبق تاريخ مباشرة الموظف للعمل',
            isAbsenceDay: false
          });
        } else {
          const isPastOrToday = loopDate <= todayNormalized;
          if (isPastOrToday) {
            scheduledWorkDays++;
          }

          const isExcused = empExcuses.includes(dateStr);
          
          // Check attendance records
          const attRecord = attendanceLogs.find(log => log.employee_id === emp.id && log.work_date === dateStr);
          
          // Check approved leaves
          const isDateWithinRange = (date: Date, startStr: string, endStr: string) => {
            const d = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
            const s = new Date(new Date(startStr).getFullYear(), new Date(startStr).getMonth(), new Date(startStr).getDate()).getTime();
            const e = new Date(new Date(endStr).getFullYear(), new Date(endStr).getMonth(), new Date(endStr).getDate()).getTime();
            return d >= s && d <= e;
          };
          
          const leaveRecord = leaveRequests.find(l => l.employee_id === emp.id && l.status === 'approved' && isDateWithinRange(loopDate, l.start_date, l.end_date));

          if (attRecord) {
            const status = attRecord.status;
            const isApplied = attRecord.deduction_status === 'applied';
            const isIgnored = attRecord.deduction_status === 'ignored';

            let earlyExitMins = 0;
            if (attRecord.check_out_time) {
              const schedCheckOut = empSched ? empSched.check_out_time : '17:00:00';
              const schedOutMins = parseScheduleMinutes(schedCheckOut);
              const actualOutMins = getBaghdadMinutesFromIso(attRecord.check_out_time);
              const diffEarly = schedOutMins - actualOutMins;
              if (diffEarly > 0) {
                earlyExitMins = diffEarly;
              }
            }

            if (isPastOrToday) {
              if (status === 'present') presentsCount++;
              else if (status === 'late') {
                presentsCount++;
                if (isApplied) {
                  latesCount++;
                  // Calculate late minutes
                  const schedCheckIn = empSched ? empSched.check_in_time : '09:00:00';
                  const schedInMins = parseScheduleMinutes(schedCheckIn);
                  const actualInMins = attRecord.check_in_time ? getBaghdadMinutesFromIso(attRecord.check_in_time) : schedInMins;
                  const diffLate = actualInMins - schedInMins;
                  const lateMins = diffLate > 0 ? diffLate : 0;
                  totalLateMinutes += lateMins;
                }
              }
              else if (status === 'half_day') halfDaysCount++;
              else if (status === 'absent') {
                if (isApplied) absencesCount++;
              }

              // Early exit check
              if (earlyExitMins > 0 && isApplied) {
                earlyExitsCount++;
                totalEarlyExitMinutes += earlyExitMins;
              }
            }
            
            let statusAr = 'حاضر ✅';
            const noteParts = [];
            if (status === 'late') {
              statusAr = isApplied ? 'متأخر (تم تطبيق الخصم) ⚠️' : (isIgnored ? 'متأخر (تم تجاهل الخصم) 🟢' : 'متأخر (معلق) ⏳');
              // Calculate late minutes for display
              const schedCheckIn = empSched ? empSched.check_in_time : '09:00:00';
              const schedInMins = parseScheduleMinutes(schedCheckIn);
              const actualInMins = attRecord.check_in_time ? getBaghdadMinutesFromIso(attRecord.check_in_time) : schedInMins;
              const diffLate = actualInMins - schedInMins;
              const lateMins = diffLate > 0 ? diffLate : 0;
              noteParts.push(`تأخير: ${formatLateDurationArabic(lateMins)}`);
            } else if (status === 'half_day') {
              statusAr = 'نصف يوم 🌓';
              noteParts.push('دوام غير مكتمل');
            } else if (status === 'absent') {
              statusAr = isApplied ? 'غياب (تم تطبيق الخصم) ❌' : 'غياب (تم تجاهل الخصم) 🟢';
              noteParts.push(attRecord.deduction_reason || 'غياب غير مبرر');
            }

            if (earlyExitMins > 0) {
              noteParts.push(`خروج مبكر: ${formatLateDurationArabic(earlyExitMins)}`);
              if (status === 'present') {
                statusAr = isApplied ? 'خروج مبكر (خصم) ⚠️' : 'خروج مبكر (تجاهل الخصم) 🟢';
              }
            }

            const noteAr = noteParts.length > 0 ? noteParts.join(' | ') : 'بصمة دوام اعتيادية';

            detailLogs.push({
              date: dateStr,
              status: statusAr,
              time: attRecord.check_in_time ? new Date(attRecord.check_in_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }) : '-',
              note: noteAr,
              isAbsenceDay: false
            });
          } else if (leaveRecord) {
            if (isPastOrToday) {
              if (leaveRecord.is_paid) {
                paidLeavesCount++;
              } else {
                absencesCount++;
              }
            }
            detailLogs.push({
              date: dateStr,
              status: leaveRecord.is_paid ? 'إجازة معتمدة 🌴' : 'إجازة بدون راتب ❌',
              time: '-',
              note: leaveRecord.reason ? `سبب الإجازة: ${leaveRecord.reason}` : 'إجازة إدارية معتمدة',
              isAbsenceDay: false
            });
          } else {
            // No attendance record and no leave
            const isPast = loopDate < todayNormalized || (loopDate.getTime() === todayNormalized.getTime() && today.getHours() >= 17);
            if (isPast) {
              if (isExcused) {
                if (isPastOrToday) {
                  presentsCount++; // Treated as present (excused)
                }
                detailLogs.push({
                  date: dateStr,
                  status: 'معفى (عذر إداري) 🟢',
                  time: '-',
                  note: 'غياب تم إعفاؤه إدارياً بواسطة المدير المباشر',
                  isAbsenceDay: true,
                  isExcused: true
                });
              } else {
                // Not excused, no attendance, no leave -> Unconfirmed absence (no auto-deduction)
                if (isPastOrToday) {
                  unconfirmedAbsencesCount++;
                }
                detailLogs.push({
                  date: dateStr,
                  status: 'يوم بدون حضور ⚠️',
                  time: '-',
                  note: 'لم يتم تسجيل حضور، ولم يتم تطبيق خصم غياب من قبل الإدارة بعد',
                  isAbsenceDay: false,
                  isExcused: false
                });
              }
            } else {
              detailLogs.push({
                date: dateStr,
                status: 'لم يحن بعد ⏳',
                time: '-',
                note: loopDate.getTime() === todayNormalized.getTime() ? 'قيد الانتظار لموعد الدوام اليوم' : 'يوم عمل مجدول مستقبلي',
                isAbsenceDay: false
              });
            }
          }
        }
      }

      // Advance loopDate by 1 day
      loopDate.setDate(loopDate.getDate() + 1);
    }

    // Salary deductions calculation
    let workdayMinutes = 480; // Default fallback: 8 hours (480 mins)
    if (empSched && empSched.check_in_time && empSched.check_out_time) {
      const [inH, inM] = empSched.check_in_time.split(':').map(Number);
      const [outH, outM] = empSched.check_out_time.split(':').map(Number);
      const inMinutes = inH * 60 + inM;
      const outMinutes = outH * 60 + outM;
      if (outMinutes > inMinutes) {
        workdayMinutes = outMinutes - inMinutes;
      }
    }

    // Use nominalBasic for daily wage calculations, so mid-month joiners aren't under-penalized
    const dailyWage = nominalBasic / 30;
    const absenceDeduction = Math.round(absencesCount * dailyWage);
    const halfDayDeduction = Math.round(halfDaysCount * dailyWage * 0.5);
    const latenessDeduction = Math.round(totalLateMinutes * (dailyWage / workdayMinutes));
    const earlyExitDeduction = Math.round(totalEarlyExitMinutes * (dailyWage / workdayMinutes));

    // Apply overrides
    const empOverrides = payrollOverrides[emp.id] || {};

    const computedAttendanceDeductions = absenceDeduction + halfDayDeduction + latenessDeduction + earlyExitDeduction;
    const finalAttendanceDeductions = empOverrides.attendanceDeductions !== undefined 
      ? empOverrides.attendanceDeductions 
      : computedAttendanceDeductions;

    const empBDs = bonusesAndDeductions.filter(bd => bd.employee_id === emp.id);
    
    const computedBonuses = empBDs.filter(bd => bd.type === 'bonus').reduce((sum, bd) => sum + Number(bd.amount), 0);
    const finalBonuses = empOverrides.bonuses !== undefined 
      ? empOverrides.bonuses 
      : computedBonuses;

    const computedOtherDeductions = empBDs.filter(bd => bd.type === 'deduction').reduce((sum, bd) => sum + Number(bd.amount), 0);
    const finalOtherDeductions = empOverrides.otherDeductions !== undefined 
      ? empOverrides.otherDeductions 
      : computedOtherDeductions;

    const finalDeductions = finalOtherDeductions + finalAttendanceDeductions;
    
    const empLoans = loanInstallments.filter(l => l.loans?.employee_id === emp.id);
    const loanDeduction = empLoans.reduce((sum, l) => sum + Number(l.amount), 0);
    const loanInstallmentIds = empLoans.map(l => l.id);

    const netSalary = basic + finalBonuses - finalDeductions - loanDeduction;
    const isIssued = existingSlips.some(slip => slip.employee_id === emp.id);

    let displayBasic = basic;
    let displayBonuses = finalBonuses;
    let displayAttendanceDeductions = finalAttendanceDeductions;
    let displayDeductions = finalDeductions;
    let displayLoanDeduction = loanDeduction;
    let displayNetSalary = netSalary;

    const issuedSlip = existingSlips.find(slip => slip.employee_id === emp.id);
    if (issuedSlip) {
      displayBasic = Number(issuedSlip.basic_salary);
      displayBonuses = Number(issuedSlip.allowances);
      displayLoanDeduction = Number(issuedSlip.loans_deduction);
      displayDeductions = Number(issuedSlip.deductions);
      displayNetSalary = Number(issuedSlip.net_salary);
      displayAttendanceDeductions = Math.min(displayDeductions, finalAttendanceDeductions);
    }

    return {
      ...emp,
      basic: displayBasic,
      scheduledWorkDays,
      presentsCount,
      latesCount,
      totalLateMinutes,
      latenessDeduction,
      earlyExitsCount,
      totalEarlyExitMinutes,
      earlyExitDeduction,
      halfDaysCount,
      absencesCount,
      paidLeavesCount,
      absenceDeduction,
      halfDayDeduction,
      totalAttendanceDeductions: displayAttendanceDeductions,
      totalBonuses: displayBonuses,
      totalDeductions: displayDeductions,
      loanDeduction: displayLoanDeduction,
      loanInstallmentIds,
      netSalary: displayNetSalary,
      isIssued,
      detailLogs,
      bonusesList: empBDs.filter(bd => bd.type === 'bonus'),
      otherDeductionsList: empBDs.filter(bd => bd.type === 'deduction'),
      loanInstallmentsList: empLoans,
      
      // Smart Validation Flags
      isNetNegative: !isIssued && displayNetSalary < 0,
      isAttendanceMissing: !isIssued && scheduledWorkDays > 0 && presentsCount === 0 && absencesCount === 0 && halfDaysCount === 0 && paidLeavesCount === 0,
      hasPendingLeave: !isIssued && leaveRequests.some(l => l.employee_id === emp.id && l.status === 'pending'),
      unconfirmedAbsencesCount: isIssued ? 0 : unconfirmedAbsencesCount,

      // Overridden flags for styling and database adjustments
      isBonusesOverridden: empOverrides.bonuses !== undefined,
      isAttendanceDeductionsOverridden: empOverrides.attendanceDeductions !== undefined,
      isOtherDeductionsOverridden: empOverrides.otherDeductions !== undefined,
      computedAttendanceDeductions,
      computedBonuses,
      computedOtherDeductions
    };
  });

  return processedPayroll;
}

export type PayrollRow = ReturnType<typeof buildPayrollRows>[number];

/** مجاميع أعمدة الجدول لمجموعة صفوف. */
export function sumPayroll(rows: PayrollRow[]) {
  const sum = (pick: (r: PayrollRow) => number) => rows.reduce((acc, r) => acc + pick(r), 0);
  return {
    net: sum(r => r.netSalary),
    basic: sum(r => r.basic),
    bonuses: sum(r => r.totalBonuses),
    attendanceDeductions: sum(r => r.totalAttendanceDeductions),
    otherDeductions: sum(r => r.totalDeductions - r.totalAttendanceDeductions),
    deductions: sum(r => r.totalDeductions),
    loans: sum(r => r.loanDeduction),
  };
}

/** قيود المكافآت والخصومات التي تُنشأ مع كشف الراتب (تسويات يدوية + تفاصيل خصومات الحضور). */
export function buildSlipAdjustments(
  empData: PayrollRow,
  period: { selectedMonth: string; startDate: string; endDate: string },
): SlipAdjustment[] {
  const { selectedMonth, startDate, endDate } = period;
  const adjustments: SlipAdjustment[] = [];
  const add = (type: SlipAdjustment['type'], amount: number, reason: string, skipIfExists = false) => {
    if (amount > 0) adjustments.push({ type, amount, reason, issue_date: endDate, skip_if_exists: skipIfExists });
  };

  if (empData.isBonusesOverridden) {
    const diff = empData.totalBonuses - empData.computedBonuses;
    if (diff > 0) add('bonus', diff, `تسوية زيادة مكافآت يدوياً لشهر ${selectedMonth}`);
    else add('deduction', Math.abs(diff), `تسوية تخفيض مكافآت يدوياً لشهر ${selectedMonth}`);
  }

  if (empData.isOtherDeductionsOverridden) {
    const diff = (empData.totalDeductions - empData.totalAttendanceDeductions) - empData.computedOtherDeductions;
    if (diff > 0) add('deduction', diff, `تسوية زيادة خصومات يدوياً لشهر ${selectedMonth}`);
    else add('bonus', Math.abs(diff), `تسوية تخفيض خصومات يدوياً لشهر ${selectedMonth}`);
  }

  if (empData.isAttendanceDeductionsOverridden) {
    add('deduction', empData.totalAttendanceDeductions, `خصم غياب وحضور معدل يدوياً للفترة من ${startDate} إلى ${endDate}`);
  } else if (empData.totalAttendanceDeductions > 0) {
    // تفاصيل خصومات الحضور التلقائية للتدقيق (لا تُكرر إن وُجدت سابقاً)
    add('deduction', empData.absenceDeduction, `خصم غياب غير مبرر (${empData.absencesCount} يوم) للفترة من ${startDate} إلى ${endDate}`, true);
    add('deduction', empData.halfDayDeduction, `خصم نصف يوم (${empData.halfDaysCount} يوم) للفترة من ${startDate} إلى ${endDate}`, true);
    add('deduction', empData.latenessDeduction, `خصم تأخير الحضور (${formatLateDurationArabic(empData.totalLateMinutes)}) للفترة من ${startDate} إلى ${endDate}`, true);
    add('deduction', empData.earlyExitDeduction, `خصم خروج مبكر (${formatLateDurationArabic(empData.totalEarlyExitMinutes)}) للفترة من ${startDate} إلى ${endDate}`, true);
  }

  return adjustments;
}
