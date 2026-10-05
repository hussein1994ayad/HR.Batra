// أنواع صفحة الإعدادات (البيانات العامة + أداة تنظيف قاعدة البيانات).

import type { Announcement, Branch, Department, Employee, LeaveTypeOption, WorkSchedule } from '@/lib/db-types';

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
