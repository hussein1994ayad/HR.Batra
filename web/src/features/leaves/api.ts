// بيانات صفحة الإجازات: الطلبات حسب الحالة، أعداد كل حالة، واعتماد/رفض طلب.
// إشعار الموظف بالقرار (مع سبب الرفض) يُرسل من قاعدة البيانات: trg_notify_employee_leave_decision

import { supabase } from '@/lib/supabase';
import type { LeaveRequest, RequestStatus } from '@/lib/db-types';

export async function fetchLeaves(status: RequestStatus): Promise<LeaveRequest[]> {
  const { data, error } = await supabase
    .from('leave_requests')
    .select(
      `*,
      employees!leave_requests_employee_id_fkey(full_name),
      approver:employees!leave_requests_approved_by_fkey(full_name)`,
    )
    .eq('status', status)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return (data ?? []) as LeaveRequest[];
}

/** عدد الطلبات بكل حالة (للأرقام على التبويبات) */
export async function fetchLeaveCounts(): Promise<Record<RequestStatus, number>> {
  const statuses: RequestStatus[] = ['pending', 'approved', 'rejected', 'cancelled'];
  const results = await Promise.all(statuses.map((st) =>
    supabase.from('leave_requests').select('id', { count: 'exact', head: true }).eq('status', st)));
  const firstError = results.find((r) => r.error)?.error;
  if (firstError) throw firstError;
  return Object.fromEntries(statuses.map((st, i) => [st, results[i].count ?? 0])) as Record<RequestStatus, number>;
}

/**
 * اعتماد أو رفض طلب إجازة باسم المستخدم الحالي.
 * يرجع false بدون جلسة (ما يصير شي)، ويرمي الخطأ إذا فشل التحديث.
 */
export async function decideLeave(
  requestId: string,
  { approve, isPaid, rejectionReason = '' }: { approve: boolean; isPaid: boolean; rejectionReason?: string },
): Promise<boolean> {
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return false;

  const { error } = await supabase
    .from('leave_requests')
    .update({
      status: approve ? 'approved' : 'rejected',
      is_paid: approve ? isPaid : undefined,
      rejection_reason: !approve && rejectionReason ? rejectionReason : undefined,
      approved_by: session.user.id,
      approved_at: new Date().toISOString(),
    })
    .eq('id', requestId);
  if (error) throw error;
  return true;
}
