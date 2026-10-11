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
  next_month: string | null;
  next_status: string | null;
  checks: { closed: boolean; next_closed: boolean; pending_decisions: number };
  counts: { attendance: number; tracking: number; stops: number; violations: number; notifications: number };
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
