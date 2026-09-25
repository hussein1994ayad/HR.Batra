// أنواع أداة تنظيف قاعدة البيانات في صفحة الإعدادات.

export interface PurgeOptions {
  year: number;
  month: number;
  notifications: boolean;
  tracking: boolean;
  absences: boolean;
}

/** نتيجة manual_purge_month_data. */
export interface PurgeResult {
  notifications_deleted?: number | null;
  tracking_deleted?: number | null;
  stops_deleted?: number | null;
  violations_deleted?: number | null;
  absences_deleted?: number | null;
}
