// منطق وثوابت صفحة الإعدادات — بدون React/Supabase.

import type { LeaveTypeOption } from '@/lib/db-types';
import type { PurgeOptions, PurgeResult } from './types';
import { MONTH_ORDINALS } from '@/lib/dates';

/** "الشهر الأول" … "الشهر الثاني عشر" (بالترتيب بدل الأسماء). */
export const ARABIC_MONTH_NAMES = MONTH_ORDINALS.map((o) => `الشهر ${o}`);

/** رسالة نجاح التنظيف بعدد السجلات المحذوفة لكل فئة مختارة. */
export function purgeSummary(options: PurgeOptions, result: PurgeResult | null | undefined): string {
  const r = result ?? {};
  const parts: string[] = [];
  if (options.notifications) parts.push(`${r.notifications_deleted || 0} إشعار`);
  if (options.tracking) {
    parts.push(`${r.tracking_deleted || 0} إحداثي تتبع، ${r.stops_deleted || 0} وقفات، ${r.violations_deleted || 0} مخالفات`);
  }
  if (options.absences) parts.push(`${r.absences_deleted || 0} سجل حضور وغياب`);
  return `تم التنظيف بنجاح! 🧹 تم حذف: ${parts.join('، ')}`;
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
