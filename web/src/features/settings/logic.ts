// منطق وثوابت صفحة الإعدادات — بدون React/Supabase.

import type { LeaveTypeOption } from '@/lib/db-types';
import type { CleanupPreview, CleanupResult, LoansCleanupPreview } from './types';
import { payrollMonthName } from '@/features/payroll/period';
import { MONTH_ORDINALS } from '@/lib/dates';

/** "الشهر الأول" … "الشهر الثاني عشر" (بالترتيب بدل الأسماء). */
export const ARABIC_MONTH_NAMES = MONTH_ORDINALS.map((o) => `الشهر ${o}`);

/** رسالة نجاح التنظيف بعدد السجلات المحذوفة لكل فئة انطلبت (null = ما انطلبت). */
export function cleanupSummary(result: CleanupResult | null | undefined): string {
  const r = result ?? {};
  const parts: string[] = [];
  if (r.attendance_deleted != null) parts.push(`${r.attendance_deleted} سجل حضور`);
  if (r.tracking_deleted != null) {
    parts.push(`${r.tracking_deleted} نقطة تتبع، ${r.stops_deleted ?? 0} وقفة، ${r.violations_deleted ?? 0} مخالفة`);
  }
  if (r.notifications_deleted != null) parts.push(`${r.notifications_deleted} إشعار`);
  return `تم التنظيف 🧹 انحذف: ${parts.join('، ')}`;
}

/** ليش حضور هذا المسير ما ينحذف هسه (فارغ = ينحذف). نفس شروط السيرفر payroll_cleanup_run. */
export function attendanceBlockers(p: CleanupPreview): string[] {
  if (p.done.attendance) return ['حضور هذا المسير منظّف مسبقاً.'];
  const out: string[] = [];
  if (!p.checks.closed) out.push('المسير بعده مفتوح: اعتمد الرواتب وأغلقه أولاً.');
  if (!p.checks.next_closed) {
    out.push(`لازم تعتمد وتغلق رواتب المسير اللي بعده${p.next_month ? ` (${payrollMonthName(p.next_month)})` : ''} أولاً، حتى نتأكد ماكو شي يخص هذا المسير بعده معلّق.`);
  }
  else if (!p.checks.next_delivered) {
    out.push(`أكد «تم تسليم الرواتب» للمسير اللي بعده${p.next_month ? ` (${payrollMonthName(p.next_month)})` : ''} من صفحة الرواتب أولاً.`);
  }
  if (p.checks.pending_decisions > 0) out.push(`اكو ${p.checks.pending_decisions} حركة (غياب/تأخير) لأيام هذا المسير تنتظر قرارك. احسمها أولاً.`);
  return out;
}

/** حجم تقريبي مقروء: 1536 ← «1.5 KB». */
export function formatBytes(bytes: number | null | undefined): string {
  const b = Number(bytes ?? 0);
  if (b < 1024) return `${Math.round(b)} B`;
  if (b < 1024 * 1024) return `${(b / 1024).toFixed(1)} KB`;
  return `${(b / 1024 / 1024).toFixed(1)} MB`;
}

/** مجموع المساحة التقريبية اللي تتحرر من السلف (سطور + صور التعهد). */
export function loansCleanupBytes(p: LoansCleanupPreview, settled: boolean, requests: boolean): number {
  return (settled ? Number(p.bytes.settled_rows) + Number(p.bytes.settled_files) : 0)
    + (requests ? Number(p.bytes.requests_rows) + Number(p.bytes.requests_files) : 0);
}

/** أنواع الإجازات إذا ما محفوظة سياسة إجازات بعد. */
export const DEFAULT_LEAVE_TYPES: LeaveTypeOption[] = [
  { id: 'annual', name: 'إجازة سنوية' },
  { id: 'sick', name: 'إجازة مرضية' },
  { id: 'emergency', name: 'إجازة طارئة' },
  { id: 'maternity', name: 'إجازة أمومة' },
  { id: 'other', name: 'إجازة أخرى' },
];
/** السنوية والمرضية لها أرصدة بالسيرفر فما تنحذف من الأنواع. */
export const PROTECTED_LEAVE_TYPES = ['annual', 'sick'];
// Saturday first, matching the Iraqi working week.
export const WEEK_ORDER = [6, 0, 1, 2, 3, 4, 5];
