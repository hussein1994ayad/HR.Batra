// استعلامات Supabase الخاصة بصفحة الرواتب.
// الحساب كله في السيرفر (محرّك الرواتب)؛ الموقع يعرض النتيجة ويرسل القرارات.

import { supabase } from '@/lib/supabase';
import { monthLabel } from './period';
import type { Branch } from '@/lib/db-types';
import type { PayrollEvent, PayrollRun } from './calc';
import type { SlipAdjustment } from './types';

export interface PayrollDataset {
  run: PayrollRun | null;
  events: PayrollEvent[];
  branches: Pick<Branch, 'id' | 'name'>[];
  pendingLeaveEmployeeIds: string[];
  attendanceEmployeeIds: string[];
}

/** مسير شهر (YYYY-MM): السيرفر يزامن الحركات ثم يرجع الفترة وصف لكل موظف. */
export async function fetchPayrollDataset(month: string): Promise<PayrollDataset> {
  const { data: run, error } = await supabase.rpc('get_payroll_run', { p_month: month });
  if (error) throw error;
  const period = (run as PayrollRun).period;

  const [resEvents, resBranches, resLeaves, resAtt] = await Promise.all([
    supabase.rpc('get_payroll_events', { p_month: month }),
    supabase.from('branches').select('id, name'),
    supabase.from('leave_requests')
      .select('employee_id')
      .eq('status', 'pending')
      .lte('start_date', `${period.cutoff_date}T23:59:59`)
      .gte('end_date', period.start_date),
    supabase.from('attendance')
      .select('employee_id')
      .gte('work_date', period.start_date)
      .lte('work_date', period.cutoff_date),
  ]);
  const firstError = [resEvents, resBranches, resLeaves, resAtt].find(r => r.error)?.error;
  if (firstError) throw firstError;

  const ids = (rows: { employee_id: string }[] | null) => [...new Set((rows ?? []).map(r => r.employee_id))];
  return {
    run: run as PayrollRun,
    events: (resEvents.data ?? []) as PayrollEvent[],
    branches: resBranches.data ?? [],
    pendingLeaveEmployeeIds: ids(resLeaves.data),
    attendanceEmployeeIds: ids(resAtt.data),
  };
}

export async function insertBonusDeduction(entry: {
  employeeId: string;
  type: 'bonus' | 'deduction';
  amount: number;
  reason: string;
  /** تاريخ القيد (يحدد مسيره: حتى يوم القطع لنفس الشهر، بعده للشهر التالي). */
  issueDate: string;
}): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser();
  const { error } = await supabase.from('bonuses_deductions').insert({
    employee_id: entry.employeeId,
    type: entry.type,
    amount: entry.amount,
    reason: entry.reason,
    issue_date: entry.issueDate,
    created_by: user?.id,
  });
  if (error) throw error;
}

/** اعتماد كشف موظف: السيرفر يحسب الأرقام ويحفظ التفاصيل ويسدد الأقساط (transaction واحدة). */
export async function approvePayrollSlip(employeeId: string, month: string, adjustments: SlipAdjustment[]): Promise<void> {
  const { error } = await supabase.rpc('approve_payroll_slip', {
    p_employee_id: employeeId,
    p_month: month,
    p_adjustments: adjustments,
  });
  if (error) throw error;
}

/** إلغاء اعتماد كشف (المسير يجب أن يكون مفتوحاً). */
export async function revertPayrollSlip(slipId: string): Promise<void> {
  const { error } = await supabase.rpc('revert_payroll_slip', { p_slip_id: slipId });
  if (error) throw error;
}

/** قرار الإدارة على حركة: اعتماد الخصم/الإضافي أو الإعفاء منه. */
export async function decidePayrollEvent(eventId: string, approve: boolean, reason?: string): Promise<void> {
  const { error } = await supabase.rpc('decide_payroll_event', {
    p_event_id: eventId,
    p_approve: approve,
    p_reason: reason ?? null,
  });
  if (error) throw error;
}

export type PeriodResult =
  | { success: true; message?: string }
  | { success: false; error?: string; missing_employees?: string[] };

export async function closePayrollPeriod(month: string): Promise<PeriodResult> {
  const { data, error } = await supabase.rpc('close_payroll_period', { p_month: month });
  if (error) throw error;
  return data as PeriodResult;
}

export async function reopenPayrollPeriod(month: string, reason: string): Promise<void> {
  const { error } = await supabase.rpc('reopen_payroll_period', { p_month: month, p_reason: reason });
  if (error) throw error;
}

/**
 * يرسل إشعار "اعتماد كشف الراتب" لموظفي فرع لديهم كشف معتمد في الشهر.
 * يرجع عدد الإشعارات، أو رسالة توضح سبب عدم الإرسال.
 */
export async function notifyBranchPayslips(branchId: string, month: string): Promise<{ sent: number; skipped: number } | { reason: string }> {
  const { data: branchEmps, error: empErr } = await supabase
    .from('employees')
    .select('id')
    .eq('branch_id', branchId)
    .eq('is_active', true);
  if (empErr) throw empErr;
  if (!branchEmps || branchEmps.length === 0) return { reason: 'لم يتم العثور على موظفين في هذا الفرع.' };

  const { data: slips, error: slipsErr } = await supabase
    .from('salary_slips')
    .select('employee_id, net_salary, created_at')
    .in('employee_id', branchEmps.map(emp => emp.id))
    .eq('work_month', month);
  if (slipsErr) throw slipsErr;
  if (!slips || slips.length === 0) return { reason: 'لا توجد كشوف رواتب معتمدة/منشورة لهذا الفرع في الشهر المحدد.' };

  // لا نكرر الإشعار: من وصله إشعار اعتماد لكشفه الحالي (بعد تاريخ الكشف) ما ينبعث له مرة ثانية
  const notified = await salaryNotifiedEmployees(slips.map(s => s.employee_id), month);
  const toSend = slips.filter(slip => {
    const at = notified.get(slip.employee_id);
    return !at || at < slip.created_at;
  });
  if (toSend.length === 0) return { reason: 'كل موظفي الفرع وصلهم إشعار كشف هذا الشهر مسبقاً.' };

  const label = monthLabel(month);
  const { error: notifErr } = await supabase.from('notifications').insert(toSend.map(slip => ({
    employee_id: slip.employee_id,
    title: 'اعتماد ونشر كشف الراتب 💸',
    body: `تم اعتماد وصرف كشف راتبك لـ${label} بصافي مستلم قدره (${Number(slip.net_salary).toLocaleString('en-US')} د.ع). يمكنك الاطلاع عليه من التطبيق.`,
    type: 'salary',
    is_read: false,
  })));
  if (notifErr) throw notifErr;
  return { sent: toSend.length, skipped: slips.length - toSend.length };
}

/** آخر وقت وصل فيه لكل موظف إشعار "اعتماد كشف الراتب" لهذا الشهر (الصيغة الجديدة والقديمة). */
async function salaryNotifiedEmployees(employeeIds: string[], month: string): Promise<Map<string, string>> {
  const { data, error } = await supabase
    .from('notifications')
    .select('employee_id, created_at, body')
    .in('employee_id', employeeIds)
    .eq('type', 'salary')
    // القيم بين علامتي تنصيص لأن "(" و"," لها معنى بصيغة or
    .or(`body.ilike."%${monthLabel(month)}%",body.ilike."%(${month})%"`)
    .order('created_at', { ascending: true });
  if (error) throw error;
  const last = new Map<string, string>();
  for (const n of (data ?? []) as { employee_id: string; created_at: string; body: string }[]) {
    if (n.body.includes('إلغاء')) last.delete(n.employee_id);
    else last.set(n.employee_id, n.created_at);
  }
  return last;
}

/**
 * بعد إلغاء اعتماد كشف: إذا الموظف وصله إشعار "تم اعتماد وصرف راتبك" لهذا الكشف، نبلغه بالإلغاء
 * (قبل: يبقى عنده إشعار صرف لراتب صار غير معتمد).
 */
export async function notifySlipReverted(employeeId: string, month: string, slipCreatedAt: string | null): Promise<void> {
  const notified = await salaryNotifiedEmployees([employeeId], month);
  const at = notified.get(employeeId);
  if (!at || (slipCreatedAt && at < slipCreatedAt)) return;
  const { error } = await supabase.from('notifications').insert({
    employee_id: employeeId,
    title: 'إلغاء اعتماد كشف الراتب',
    body: `تم إلغاء اعتماد كشف راتبك لـ${monthLabel(month)} للمراجعة، وراح يوصلك إشعار عند اعتماده من جديد.`,
    type: 'salary',
    is_read: false,
  });
  if (error) throw error;
}

export async function archivePayrollMonth(month: string): Promise<PeriodResult> {
  // أشهر المحرّك تُؤرشف بتواريخ مسيرها المحفوظة؛ الأيام هنا للأشهر القديمة فقط
  const { data, error } = await supabase.rpc('safe_archive_payroll_month', {
    target_month: month,
    cycle_start_day: 1,
    cycle_end_day: 31,
  });
  if (error) throw error;
  return data as PeriodResult;
}
