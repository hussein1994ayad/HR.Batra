// منطق أداة تنظيف قاعدة البيانات — دوال نقية.

import type { PurgeOptions, PurgeResult } from './types';

export const ARABIC_MONTH_NAMES = [
  'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
  'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
];

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
