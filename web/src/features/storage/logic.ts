// منطق صفحة التخزين — بدون React/Supabase.

export interface TableSizeRow {
  table_name: string;
  row_count: number;
  total_bytes: number;
  pretty_size: string;
}

// Arabic-friendly names for tables
export const TABLE_LABELS: Record<string, string> = {
  employees: 'الموظفين',
  attendance: 'الحضور والغياب',
  salary_slips: 'كشوف الرواتب',
  loans: 'السلف والقروض',
  loan_installments: 'أقساط السلف',
  leave_requests: 'طلبات الإجازات',
  leave_balances: 'أرصدة الإجازات',
  notifications: 'الإشعارات',
  location_tracking: 'تتبع المواقع GPS',
  tracked_stops: 'الوقفات المرصودة',
  geofence_violations: 'مخالفات السياج الجغرافي',
  geofence_zones: 'مناطق السياج الجغرافي',
  employee_geofence_assignments: 'تعيينات السياج للموظفين',
  mock_gps_attempts: 'محاولات GPS المزيف',
  departments: 'الأقسام',
  branches: 'الفروع',
  branch_schedules: 'جداول الفروع',
  work_schedules: 'جداول العمل',
  tracking_schedules: 'جداول التتبع',
  company_settings: 'إعدادات الشركة',
  system_settings: 'إعدادات النظام',
  announcements: 'الإعلانات',
  bonuses_deductions: 'المكافآت والخصومات',
  documents: 'المستندات',
  deleted_files: 'الملفات المحذوفة',
  archived_employees: 'الموظفين المؤرشفين',
  archived_months: 'الأشهر المؤرشفة',
  fcm_tokens: 'رموز الإشعارات FCM',
  device_tokens: 'رموز الأجهزة',
  employee_devices: 'أجهزة الموظفين',
  app_versions: 'إصدارات التطبيق',
};

// Color assignment based on table category
export const getTableColor = (name: string): string => {
  if (['location_tracking', 'tracked_stops', 'geofence_violations', 'mock_gps_attempts', 'geofence_zones', 'employee_geofence_assignments'].includes(name)) return 'bg-red-500';
  if (['attendance'].includes(name)) return 'bg-amber-500';
  if (['notifications', 'announcements'].includes(name)) return 'bg-blue-500';
  if (['salary_slips', 'loans', 'loan_installments', 'bonuses_deductions'].includes(name)) return 'bg-emerald-500';
  if (['employees', 'employee_devices', 'departments', 'branches'].includes(name)) return 'bg-purple-500';
  if (['leave_requests', 'leave_balances'].includes(name)) return 'bg-cyan-500';
  return 'bg-slate-500';
};

export const getTableDotColor = (name: string): string => {
  if (['location_tracking', 'tracked_stops', 'geofence_violations', 'mock_gps_attempts', 'geofence_zones', 'employee_geofence_assignments'].includes(name)) return 'bg-red-400';
  if (['attendance'].includes(name)) return 'bg-amber-400';
  if (['notifications', 'announcements'].includes(name)) return 'bg-blue-400';
  if (['salary_slips', 'loans', 'loan_installments', 'bonuses_deductions'].includes(name)) return 'bg-emerald-400';
  if (['employees', 'employee_devices', 'departments', 'branches'].includes(name)) return 'bg-purple-400';
  if (['leave_requests', 'leave_balances'].includes(name)) return 'bg-cyan-400';
  return 'bg-slate-400';
};

// حدود باقة Supabase المجانية
export const MAX_STORAGE_BYTES = 1.0 * 1024 * 1024 * 1024; // 1 GB Storage
export const MAX_DB_BYTES = 500 * 1024 * 1024; // 500 MB Database

/** حجم مقروء (B/KB/MB/GB). يختلف عن formatBytes في lib/format بأنه ما يصعد لـ TB — مقصود للعرض الحالي. */
export const formatBytes = (bytes: number) => {
  if (bytes < 1024) return `${bytes.toFixed(0)} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
};
