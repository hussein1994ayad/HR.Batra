// أنواع صفحة الإعدادات.

import type { Branch, Department, Employee } from '@/lib/db-types';

/** أعمدة company_settings القابلة للتعديل. */
export interface CompanyInfo {
  name: string;
  address: string;
  phone: string;
  email: string;
  website: string;
  tax_number: string;
  logo_url: string;
}

export interface LeaveType {
  id: string;
  name: string;
}

/** سياسات النظام المخزنة في system_settings (archive_policy, payroll_policy, leave_policy). */
export interface SystemPolicies {
  trackingDays: number;
  cycleStartDay: number;
  cycleEndDay: number;
  defaultAnnual: number;
  defaultSick: number;
  leaveTypes: LeaveType[];
}

export interface GeneralSettings {
  company: CompanyInfo;
  policies: SystemPolicies;
}

export type ScheduleScope = 'branch' | 'department' | 'employee';

export interface ScheduleForm {
  name: string;
  scope: ScheduleScope;
  targetId: string;
  checkIn: string;
  checkOut: string;
  grace: number;
  workDays: number[];
}

export interface ScheduleTargets {
  branches: Pick<Branch, 'id' | 'name'>[];
  departments: Department[];
  employees: Pick<Employee, 'id' | 'full_name'>[];
}

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
