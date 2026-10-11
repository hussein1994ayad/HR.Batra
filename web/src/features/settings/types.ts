// أنواع صفحة الإعدادات (البيانات العامة + أداة تنظيف المسيرات المغلقة).

import type { Announcement, Branch, Department, Employee, LeaveTypeOption, WorkSchedule } from '@/lib/db-types';

/** الفئات اللي تنحذف بتنظيف مسير. */
export interface CleanupSelection {
  attendance: boolean;
  tracking: boolean;
  notifications: boolean;
}

/** نتيجة payroll_cleanup_run (null = الفئة ما انطلبت). */
export interface CleanupResult {
  attendance_deleted?: number | null;
  tracking_deleted?: number | null;
  stops_deleted?: number | null;
  violations_deleted?: number | null;
  notifications_deleted?: number | null;
}

/** معاينة payroll_cleanup_preview. */
export interface CleanupPreview {
  month: string;
  start_date: string;
  end_date: string;
  status: string;
  /** الأدمن أكد إن رواتب هذا المسير تسلّمت */
  delivered_at?: string | null;
  next_month: string | null;
  next_status: string | null;
  next_delivered_at?: string | null;
  checks: { closed: boolean; next_closed: boolean; next_delivered: boolean; pending_decisions: number };
  /** المستثنى وسببه: حركات تنتظر قرار لأيام هذا المسير (تمنع حذف الحضور) */
  pending_list: { employee: string; date: string; type: string; amount: number }[];
  counts: { attendance: number; tracking: number; stops: number; violations: number; notifications: number };
  /** تقدير المساحة بالبايت (حجم السطور بدون الفهارس) */
  bytes: { attendance: number; tracking: number; notifications: number };
  done: CleanupSelection;
  can: CleanupSelection;
  history: {
    at: string;
    by: string | null;
    attendance: number | null;
    tracking: number | null;
    stops: number | null;
    violations: number | null;
    notifications: number | null;
  }[];
}

export interface CompanySettings {
  name?: string | null;
  address?: string | null;
  phone?: string | null;
  email?: string | null;
  website?: string | null;
  tax_number?: string | null;
  logo_url?: string | null;
}

/** كل ما تحتاجه صفحة الإعدادات بتحميل واحد (القيم الافتراضية مطبّقة في fetchSettings). */
export interface SettingsData {
  company: CompanySettings | null;
  trackingDays: number;
  cutoffDay: number;
  paymentDay: number;
  overtimeEnabled: boolean;
  overtimeMultiplier: number;
  overtimeMinMinutes: number;
  defaultAnnual: number;
  defaultSick: number;
  hourlyMonthlyHours: number;
  leaveTypes: LeaveTypeOption[];
  announcements: Announcement[];
  schedules: WorkSchedule[];
  branches: Pick<Branch, 'id' | 'name'>[];
  departments: Department[];
  employees: Pick<Employee, 'id' | 'full_name'>[];
}

/** معاينة تنظيف السلف (loans_cleanup_preview). */
export interface LoansCleanupPreview {
  /** مسددة بالكامل ومؤهلة للأرشفة */
  settled: { id: string; loan_no: number; employee: string; amount: number; settled_at: string | null }[];
  /** معتمدة بس ما تتأرشف هسه، مع السبب */
  excluded: { loan_no: number; employee: string; amount: number; remaining: number; reason: string }[];
  /** طلبات مرفوضة/ملغاة أقدم من 30 يوم */
  requests: { id: string; loan_no: number; employee: string; amount: number; status: string; created_at: string }[];
  requests_recent: number;
  bytes: { settled_rows: number; settled_files: number; requests_rows: number; requests_files: number };
  archived_total: number;
}

/** نتيجة loans_cleanup_run (null = الفئة ما انطلبت). */
export interface LoansCleanupResult {
  loans_archived: number | null;
  loan_requests_deleted: number | null;
  pledge_urls: string[];
}
