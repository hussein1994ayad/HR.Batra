// =========================================================================
// صفوف جدول الرواتب — منطق نقي بدون React أو Supabase (قابل للاختبار)
// =========================================================================
// الحساب نفسه يجري في السيرفر (محرّك الرواتب: get_payroll_run / payroll_events):
//   أجر اليوم = الراتب ÷ 30، أجر الدقيقة = أجر اليوم ÷ دقائق دوام الموظف،
//   المسير من اليوم التالي لقطع الشهر السابق حتى يوم القطع (26).
// هنا فقط: تحويل نتيجة السيرفر لصفوف الجدول، وتطبيق التعديلات اليدوية قبل الاعتماد
// (تُرسل للسيرفر كمكافأة/خصم بسبب واضح).

import type { PayrollOverrides, SlipAdjustment } from './types';

export type PayrollEventType =
  | 'absence' | 'late' | 'early_leave' | 'missing_punch' | 'unpaid_leave' | 'paid_leave' | 'overtime'
  | 'manual_deduction' | 'bonus' | 'allowance' | 'advance' | 'adjustment' | 'other';

export type PayrollEventStatus = 'pending' | 'approved' | 'ignored' | 'void';

export interface PayrollEvent {
  id: string;
  employee_id: string;
  event_date: string;
  event_type: PayrollEventType;
  minutes: number;
  days: number;
  amount: number;
  direction: -1 | 0 | 1;
  payroll_month: string;
  carried_from?: string | null;
  status: PayrollEventStatus;
  source: string;
  notes?: string | null;
  decision_reason?: string | null;
  salary_slip_id?: string | null;
}

export interface PayrollPeriod {
  period_month: string;
  start_date: string;
  cutoff_date: string;
  payment_date: string;
  status: 'open' | 'closed';
  closed_at?: string | null;
  reopened_at?: string | null;
  reopen_reason?: string | null;
  archived?: boolean;
  /** شهر قبل نظام المسيرات: كشوف قديمة للعرض فقط. */
  legacy?: boolean;
  /** آخر «احتساب الرواتب» (calculate_payroll) */
  calculated_at?: string | null;
}

/** صف موظف كما يرجعه get_payroll_run. */
export interface RunRow {
  employee_id: string;
  full_name: string;
  branch_id: string | null;
  branch_name: string | null;
  join_date?: string | null;
  termination_date?: string | null;
  is_active: boolean;
  period_days: number;
  employed_days: number;
  monthly_salary: number;
  daily_rate: number;
  minute_rate: number;
  shift_minutes: number;
  basic: number;
  earnings: number;
  bonuses: number;
  overtime: number;
  deductions: number;
  attendance_deductions: number;
  loans: number;
  net: number;
  pending_count: number;
  missing_punches: number;
  absence_days: number;
  late_minutes: number;
  early_minutes: number;
  overtime_minutes: number;
  paid_leave_days: number;
  unpaid_leave_days: number;
  /** ترك العمل خلال المسير: ما يبقى من السلف بعد أقساط هذا المسير */
  loan_balance_after_exit?: number;
  /** أقساط السلف اللي تنخصم هالمسير وأسبابها */
  loan_items?: LoanItem[];
  /** أيام البصمة الفعلية / أيام الدوام المجدولة ضمن خدمته بالمسير */
  attended_days?: number;
  scheduled_days?: number;
  /** عنده جدول دوام (بدونه ما ينحسب تأخير ولا خروج مبكر) */
  has_schedule?: boolean;
  slip: null | {
    id: string;
    basic_salary: number;
    allowances: number;
    deductions: number;
    loans_deduction: number;
    net_salary: number;
    created_at?: string;
    legacy: boolean;
  };
}

export interface PayrollRun {
  period: PayrollPeriod;
  rows: RunRow[];
}

/** قسط سلفة ينخصم بهذا المسير (من payroll_employee_summary). */
export interface LoanItem {
  installment_id: string;
  loan_id: string;
  loan_amount: number;
  due_date: string;
  amount: number;
  origin_kind?: 'shortfall' | 'postponed' | null;
  origin_month?: string | null;
  amount_locked?: boolean;
  note?: string | null;
}

/** قيد مكافأة/خصم يُعرض في تفاصيل الموظف. */
export interface EntryItem {
  id: string;
  reason: string;
  issue_date: string;
  amount: number;
}

export const EVENT_LABELS: Record<PayrollEventType, string> = {
  absence: 'غياب',
  late: 'تأخير',
  early_leave: 'خروج مبكر',
  missing_punch: 'بصمة ناقصة',
  unpaid_leave: 'إجازة بدون راتب',
  paid_leave: 'إجازة مدفوعة',
  overtime: 'ساعات إضافية',
  manual_deduction: 'خصم',
  bonus: 'مكافأة',
  allowance: 'مخصصات',
  advance: 'سلفة',
  adjustment: 'تسوية',
  other: 'أخرى',
};

/** الحركات التي تنتظر قرار الإدارة (اعتماد أو إعفاء). */
export const DECIDABLE: PayrollEventType[] = ['absence', 'late', 'early_leave', 'missing_punch', 'overtime'];

const ATTENDANCE_TYPES: PayrollEventType[] = ['absence', 'late', 'early_leave', 'unpaid_leave'];
const n = (v: unknown) => Number(v) || 0;

export interface PayrollRowsInput {
  run: PayrollRun;
  events: PayrollEvent[];
  overrides: PayrollOverrides;
  /** موظفون لديهم طلب إجازة معلّق يتقاطع مع المسير. */
  pendingLeaveEmployeeIds?: string[];
  /** موظفون لديهم سجل حضور واحد على الأقل في المسير. */
  attendanceEmployeeIds?: string[];
}

/** صفوف جدول الرواتب من نتيجة السيرفر + التعديلات اليدوية غير المحفوظة. */
export function buildPayrollRows({ run, events, overrides, pendingLeaveEmployeeIds = [], attendanceEmployeeIds }: PayrollRowsInput) {
  const byEmployee = new Map<string, PayrollEvent[]>();
  for (const e of events) {
    if (e.status === 'void') continue;
    const list = byEmployee.get(e.employee_id) ?? [];
    list.push(e);
    byEmployee.set(e.employee_id, list);
  }

  return run.rows.map((r) => {
    const empEvents = (byEmployee.get(r.employee_id) ?? []).sort((a, b) => a.event_date.localeCompare(b.event_date));
    const approved = empEvents.filter((e) => e.status === 'approved');
    const sumOf = (types: PayrollEventType[]) =>
      approved.filter((e) => types.includes(e.event_type)).reduce((acc, e) => acc + n(e.amount), 0);
    const countOf = (type: PayrollEventType) => approved.filter((e) => e.event_type === type).length;

    const toEntry = (e: PayrollEvent): EntryItem => ({
      id: e.id,
      reason: e.notes || EVENT_LABELS[e.event_type],
      issue_date: e.event_date,
      amount: Math.round(n(e.amount)),
    });
    const isAttendance = (e: PayrollEvent) => ATTENDANCE_TYPES.includes(e.event_type);
    const bonusesList = approved.filter((e) => e.direction === 1).map(toEntry);
    const otherDeductionsList = approved.filter((e) => e.direction === -1 && !isAttendance(e)).map(toEntry);

    const computedBonuses = n(r.earnings);
    const computedAttendanceDeductions = n(r.attendance_deductions);
    const computedOtherDeductions = n(r.deductions) - computedAttendanceDeductions;

    const o = overrides[r.employee_id] ?? {};
    const totalBonuses = o.bonuses ?? computedBonuses;
    const attendanceDeductions = o.attendanceDeductions ?? computedAttendanceDeductions;
    const otherDeductions = o.otherDeductions ?? computedOtherDeductions;

    let basic = n(r.basic);
    let bonusesShown = totalBonuses;
    let attendanceShown = attendanceDeductions;
    let deductionsShown = attendanceDeductions + otherDeductions;
    let loans = n(r.loans);
    let net = basic + totalBonuses - deductionsShown - loans;

    const slip = r.slip;
    if (slip) {
      // الكشف المعتمد ثابت: نعرض أرقامه كما حُفظت
      basic = n(slip.basic_salary);
      bonusesShown = n(slip.allowances);
      deductionsShown = n(slip.deductions);
      attendanceShown = Math.min(deductionsShown, computedAttendanceDeductions);
      loans = n(slip.loans_deduction);
      net = n(slip.net_salary);
    }

    return {
      id: r.employee_id,
      full_name: r.full_name,
      branch_id: r.branch_id,
      branches: r.branch_name ? { name: r.branch_name } : null,
      joinDate: r.join_date ?? null,
      terminationDate: r.termination_date ?? null,
      isActive: r.is_active,

      monthlySalary: n(r.monthly_salary),
      dailyRate: n(r.daily_rate),
      minuteRate: n(r.minute_rate),
      shiftMinutes: n(r.shift_minutes),
      periodDays: n(r.period_days),
      employedDays: n(r.employed_days),

      basic,
      totalBonuses: bonusesShown,
      totalAttendanceDeductions: attendanceShown,
      totalDeductions: deductionsShown,
      loanDeduction: loans,
      netSalary: net,

      absencesCount: n(r.absence_days),
      absenceDeduction: sumOf(['absence']),
      latesCount: countOf('late'),
      totalLateMinutes: n(r.late_minutes),
      latenessDeduction: sumOf(['late']),
      earlyExitsCount: countOf('early_leave'),
      totalEarlyExitMinutes: n(r.early_minutes),
      earlyExitDeduction: sumOf(['early_leave']),
      unpaidLeaveDays: n(r.unpaid_leave_days),
      unpaidLeaveDeduction: sumOf(['unpaid_leave']),
      overtimeMinutes: n(r.overtime_minutes),
      overtimeAmount: n(r.overtime),
      paidLeavesCount: n(r.paid_leave_days),
      pendingCount: slip ? 0 : n(r.pending_count),
      missingPunches: n(r.missing_punches),
      loanBalanceAfterExit: n(r.loan_balance_after_exit),
      loanItems: slip ? [] : (r.loan_items ?? []),
      attendedDays: n(r.attended_days),
      hasSchedule: r.has_schedule ?? true,
      scheduledDays: n(r.scheduled_days),

      events: empEvents,
      bonusesList,
      otherDeductionsList,

      isIssued: !!slip,
      slipId: slip?.id ?? null,
      slipCreatedAt: slip?.created_at ?? null,
      isLegacySlip: !!slip?.legacy,

      isNetNegative: !slip && net < 0,
      isAttendanceMissing: !slip && attendanceEmployeeIds !== undefined && !attendanceEmployeeIds.includes(r.employee_id)
        && n(r.employed_days) > 0,
      hasPendingLeave: !slip && pendingLeaveEmployeeIds.includes(r.employee_id),

      isBonusesOverridden: o.bonuses !== undefined,
      isAttendanceDeductionsOverridden: o.attendanceDeductions !== undefined,
      isOtherDeductionsOverridden: o.otherDeductions !== undefined,
      computedBonuses,
      computedAttendanceDeductions,
      computedOtherDeductions,
    };
  });
}

export type PayrollRow = ReturnType<typeof buildPayrollRows>[number];

/**
 * الراتب ينعتمد بعد نهاية فترة الدوام، إلا آخر راتب لموظف ترك العمل وآخر يوم دوامه فات
 * (نفس شرط approve_payroll_slip بالسيرفر).
 */
export function canApproveNow(row: Pick<PayrollRow, 'isIssued' | 'terminationDate'>, startDate: string, endDate: string, today: string): boolean {
  if (row.isIssued || !endDate) return false;
  if (today > endDate) return true;
  const t = row.terminationDate;
  return !!t && t >= startDate && t <= endDate && t < today;
}

/** سبب يحتاج انتباه الأدمن قبل الاعتماد (بلغة بسيطة) مع نوعه للون والزر. */
export interface AttentionReason {
  kind: 'negative' | 'never_attended' | 'left_with_loan' | 'pending_leave' | 'decisions' | 'data';
  text: string;
}

/** ليش هذا الراتب يحتاج نظرة قبل الاعتماد. فارغ = جاهز. */
export function attentionReasons(row: PayrollRow): AttentionReason[] {
  if (row.isIssued) return [];
  const out: AttentionReason[] = [];
  if (row.pendingCount > 0) out.push({ kind: 'decisions', text: `${row.pendingCount} حركة تنتظر قرارك (غياب/تأخير)` });
  if (row.scheduledDays > 0 && row.attendedDays === 0 && row.isActive && !row.terminationDate) {
    out.push({ kind: 'never_attended', text: 'ما داوم ولا يوم بهذا المسير. إذا ترك العمل عطّله بآخر يوم دوام حتى ينحسب له بس الأيام اللي اشتغلها.' });
  }
  if (row.loanBalanceAfterExit > 0) {
    out.push({ kind: 'left_with_loan', text: `ترك العمل وباقي عليه سلفة ${row.loanBalanceAfterExit.toLocaleString('en-US')} د.ع` });
  }
  if (row.isNetNegative) out.push({ kind: 'negative', text: 'الصافي بالسالب: الخصومات والسلف أكثر من الراتب' });
  const missing = [
    row.monthlySalary <= 0 && 'الراتب صفر',
    !row.branch_id && 'بدون فرع',
    !row.hasSchedule && 'بدون جدول دوام (ما ينحسب عليه تأخير)',
  ].filter(Boolean);
  if (missing.length > 0) out.push({ kind: 'data', text: `بيانات ناقصة: ${missing.join('، ')}. صلّحها من صفحة الموظفين.` });
  if (row.hasPendingLeave) out.push({ kind: 'pending_leave', text: 'عنده طلب إجازة معلّق بهذا المسير' });
  return out;
}

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

/**
 * التعديلات اليدوية على خانات الجدول ← مكافأة/خصم يُضاف مع الكشف بسبب واضح.
 * السيرفر يحسب كل شيء آخر من الحركات.
 */
export function buildSlipAdjustments(row: PayrollRow, month: string): SlipAdjustment[] {
  const out: SlipAdjustment[] = [];
  const push = (diff: number, raise: string, lower: string, raiseType: SlipAdjustment['type']) => {
    const amount = Math.round(Math.abs(diff));
    if (amount === 0) return;
    const lowerType: SlipAdjustment['type'] = raiseType === 'bonus' ? 'deduction' : 'bonus';
    out.push(diff > 0
      ? { type: raiseType, amount, reason: `${raise} لمسير ${month}` }
      : { type: lowerType, amount, reason: `${lower} لمسير ${month}` });
  };

  if (row.isBonusesOverridden) {
    push(row.totalBonuses - row.computedBonuses, 'تعديل يدوي بزيادة المكافآت', 'تعديل يدوي بتخفيض المكافآت', 'bonus');
  }
  if (row.isAttendanceDeductionsOverridden) {
    push(row.totalAttendanceDeductions - row.computedAttendanceDeductions,
      'تعديل يدوي بزيادة خصومات الدوام', 'تعديل يدوي بتخفيض خصومات الدوام', 'deduction');
  }
  if (row.isOtherDeductionsOverridden) {
    const other = row.totalDeductions - row.totalAttendanceDeductions;
    push(other - row.computedOtherDeductions, 'تعديل يدوي بزيادة الخصومات', 'تعديل يدوي بتخفيض الخصومات', 'deduction');
  }
  return out;
}

/** وصف مختصر لحركة: "غياب يوم" / "تأخير 30 دقيقة" / "إجازة زمنية 120 دقيقة". */
export function describeEvent(e: PayrollEvent): string {
  const label = EVENT_LABELS[e.event_type] ?? e.event_type;
  const minutes = n(e.minutes);
  const days = n(e.days);
  if (minutes > 0) return `${label} ${minutes} دقيقة`;
  if (days > 0 && days !== 1) return `${label} ${days} يوم`;
  return label;
}
