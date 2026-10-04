// منطق صفحة الإجازات بدون React أو Supabase.

import { toDateKey } from '@/lib/attendance';
import type { LeaveRequest } from '@/lib/db-types';

export const LEAVE_TYPES: Record<string, string> = {
  annual: 'إجازة سنوية',
  sick: 'إجازة مرضية',
  emergency: 'إجازة طارئة',
  maternity: 'إجازة أمومة',
};

/** عدد أيام الإجازة شامل اليومين (حسب تاريخ بغداد لكل طرف). */
export function leaveDays(req: Pick<LeaveRequest, 'start_date' | 'end_date'>): number {
  const start = new Date(toDateKey(req.start_date));
  const end = new Date(toDateKey(req.end_date));
  return Math.round(Math.abs(end.getTime() - start.getTime()) / 86_400_000) + 1;
}

/** بحث بالاسم بدون حساسية لحالة الأحرف. */
export function filterLeavesByName<T extends { employees?: { full_name?: string | null } | null }>(list: T[], search: string): T[] {
  const q = search.trim().toLowerCase();
  return q ? list.filter((r) => (r.employees?.full_name || '').toLowerCase().includes(q)) : list;
}
