// استعلامات Supabase الخاصة بصفحة الرواتب.

import { supabase } from '@/lib/supabase';
import type {
  AttendanceRecord, BonusDeduction, Branch, Employee, LeaveRequest, LoanInstallment, SalarySlip, WorkSchedule,
} from '@/lib/db-types';
import type { SlipAdjustment } from './types';
import type { PayrollRow } from './calc';

export interface PayrollDataset {
  branches: Pick<Branch, 'id' | 'name'>[];
  employees: Employee[];
  bonusesAndDeductions: BonusDeduction[];
  loanInstallments: LoanInstallment[];
  attendanceLogs: AttendanceRecord[];
  leaveRequests: LeaveRequest[];
  workSchedules: WorkSchedule[];
  existingSlips: SalarySlip[];
  archivedMonths: string[];
}

/** يوم بداية ونهاية الدورة المالية من system_settings (payroll_policy)، أو null إن لم تُضبط. */
export async function fetchPayrollPolicy(): Promise<{ startDay: number; endDay: number } | null> {
  const { data, error } = await supabase
    .from('system_settings')
    .select('value')
    .eq('key', 'payroll_policy')
    .maybeSingle();
  if (error) throw error;
  if (!data?.value) return null;
  return {
    startDay: data.value.cycle_start_day || 25,
    endDay: data.value.cycle_end_day || 24,
  };
}

/** كل البيانات التي يحتاجها حساب رواتب دورة معيّنة. */
export async function fetchPayrollDataset(startDate: string, endDate: string, month: string): Promise<PayrollDataset> {
  const [resBrs, resEmps, resBds, resLoans, resAtt, resLvs, resScheds, resSlips, resArchived] = await Promise.all([
    supabase.from('branches').select('id, name'),
    supabase.from('employees')
      .select('id, full_name, monthly_salary_iqd, future_salary_iqd, future_salary_month, branch_id, department_id, created_at, join_date, branches(name)')
      .eq('is_active', true)
      .order('full_name'),
    supabase.from('bonuses_deductions').select('*').gte('issue_date', startDate).lte('issue_date', endDate),
    supabase.from('loan_installments')
      .select('*, loans!inner(employee_id)')
      .gte('due_date', startDate)
      .lte('due_date', endDate)
      .eq('is_paid', false),
    supabase.from('attendance').select('*').gte('work_date', startDate).lte('work_date', endDate),
    supabase.from('leave_requests')
      .select('*')
      .in('status', ['approved', 'pending'])
      .lte('start_date', endDate)
      .gte('end_date', startDate),
    supabase.from('work_schedules').select('*'),
    supabase.from('salary_slips').select('*').eq('work_month', month),
    supabase.from('archived_months').select('work_month'),
  ]);

  const firstError = [resBrs, resEmps, resBds, resLoans, resAtt, resLvs, resScheds, resSlips, resArchived]
    .find(r => r.error)?.error;
  if (firstError) throw firstError;

  return {
    branches: resBrs.data ?? [],
    // supabase-js بدون أنواع مولّدة يستنتج العلاقة branches كمصفوفة، وهي فعلياً كائن واحد
    employees: (resEmps.data ?? []) as unknown as Employee[],
    bonusesAndDeductions: resBds.data ?? [],
    loanInstallments: resLoans.data ?? [],
    attendanceLogs: resAtt.data ?? [],
    leaveRequests: resLvs.data ?? [],
    workSchedules: resScheds.data ?? [],
    existingSlips: resSlips.data ?? [],
    archivedMonths: (resArchived.data ?? []).map((r: { work_month: string }) => r.work_month),
  };
}

export async function insertBonusDeduction(entry: {
  employeeId: string;
  type: 'bonus' | 'deduction';
  amount: number;
  reason: string;
}): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser();
  const { error } = await supabase.from('bonuses_deductions').insert({
    employee_id: entry.employeeId,
    type: entry.type,
    amount: entry.amount,
    reason: entry.reason,
    issue_date: new Date().toISOString().split('T')[0],
    created_by: user?.id,
  });
  if (error) throw error;
}

/** الكشف + تسديد الأقساط + القيود كلها في transaction واحدة بالسيرفر. */
export async function approveSalarySlip(row: PayrollRow, month: string, adjustments: SlipAdjustment[]): Promise<void> {
  const { error } = await supabase.rpc('approve_salary_slip', {
    p_employee_id: row.id,
    p_work_month: month,
    p_basic_salary: row.basic,
    p_allowances: row.totalBonuses,
    p_deductions: row.totalDeductions,
    p_loans_deduction: row.loanDeduction,
    p_net_salary: row.netSalary,
    p_installment_ids: row.loanInstallmentIds ?? [],
    p_adjustments: adjustments,
  });
  if (error) throw error;
}

/** يحذف الكشف ويُرجع نفس الأقساط والقيود التي أنشأها (transaction واحدة). */
export async function revertSalarySlip(slipId: string, periodStart: string, periodEnd: string): Promise<void> {
  const { error } = await supabase.rpc('revert_salary_slip', {
    p_slip_id: slipId,
    p_period_start: periodStart,
    p_period_end: periodEnd,
  });
  if (error) throw error;
}

/**
 * يرسل إشعار "اعتماد كشف الراتب" لموظفي فرع لديهم كشف معتمد في الشهر.
 * يرجع عدد الإشعارات، أو رسالة توضح سبب عدم الإرسال.
 */
export async function notifyBranchPayslips(branchId: string, month: string): Promise<{ sent: number } | { reason: string }> {
  const { data: branchEmps, error: empErr } = await supabase
    .from('employees')
    .select('id, full_name')
    .eq('branch_id', branchId)
    .eq('is_active', true);
  if (empErr) throw empErr;
  if (!branchEmps || branchEmps.length === 0) return { reason: 'لم يتم العثور على موظفين في هذا الفرع.' };

  const { data: slips, error: slipsErr } = await supabase
    .from('salary_slips')
    .select('employee_id, net_salary')
    .in('employee_id', branchEmps.map(emp => emp.id))
    .eq('work_month', month);
  if (slipsErr) throw slipsErr;
  if (!slips || slips.length === 0) return { reason: 'لا توجد كشوف رواتب معتمدة/منشورة لهذا الفرع في الشهر المحدد.' };

  const { error: notifErr } = await supabase.from('notifications').insert(slips.map(slip => ({
    employee_id: slip.employee_id,
    title: 'اعتماد ونشر كشف الراتب 💸',
    body: `تم اعتماد وصرف كشف راتبك لشهر (${month}) بصافي مستلم قدره (${slip.net_salary.toLocaleString()} د.ع). يمكنك الاطلاع عليه من التطبيق.`,
    type: 'salary',
    is_read: false,
  })));
  if (notifErr) throw notifErr;
  return { sent: slips.length };
}

export type ArchiveResult =
  | { success: true; message?: string }
  | { success: false; error?: string; missing_employees?: string[] };

export async function archivePayrollMonth(month: string, cycleStartDay: number, cycleEndDay: number): Promise<ArchiveResult> {
  const { data, error } = await supabase.rpc('safe_archive_payroll_month', {
    target_month: month,
    cycle_start_day: cycleStartDay,
    cycle_end_day: cycleEndDay,
  });
  if (error) throw error;
  return data as ArchiveResult;
}
