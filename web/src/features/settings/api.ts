// بيانات صفحة الإعدادات. أداة التنظيف: حذف بيانات شهر (بعد اعتماد رواتبه) عبر RPC يتحقق من القفل المالي.

import { supabase } from '@/lib/supabase';
import type { Announcement, Department, LeaveTypeOption, WorkSchedule } from '@/lib/db-types';
import { DEFAULT_LEAVE_TYPES } from './logic';
import type { CompanySettings, PurgeOptions, PurgeResult, SettingsData } from './types';

export async function purgeMonthData(options: PurgeOptions): Promise<PurgeResult | null> {
  const { data, error } = await supabase.rpc('manual_purge_month_data', {
    p_year: Number(options.year),
    p_month: Number(options.month),
    p_notifications: options.notifications,
    p_tracking: options.tracking,
    p_absences: options.absences,
  });
  if (error) throw error;
  return (data as PurgeResult[] | null)?.[0] ?? null;
}

/** تحميل الإعدادات كلها بالتوازي، مع القيم الافتراضية للسياسات غير المحفوظة. */
export async function fetchSettings(): Promise<SettingsData> {
  const [comp, archive, payroll, leave, ann, ws, br, dep, emp] = await Promise.all([
    supabase.from('company_settings').select('*').maybeSingle(),
    supabase.from('system_settings').select('*').eq('key', 'archive_policy').maybeSingle(),
    supabase.from('system_settings').select('*').eq('key', 'payroll_policy').maybeSingle(),
    supabase.from('system_settings').select('*').eq('key', 'leave_policy').maybeSingle(),
    supabase.from('announcements').select('*').order('created_at', { ascending: false }),
    supabase.from('work_schedules').select('*'),
    supabase.from('branches').select('id, name'),
    supabase.from('departments').select('id, name'),
    supabase.from('employees').select('id, full_name').eq('is_active', true).order('full_name'),
  ]);
  const lp = leave.data?.value;
  return {
    company: (comp.data as CompanySettings | null) ?? null,
    trackingDays: archive.data?.value?.tracking_archive_days || 180,
    cutoffDay: payroll.data?.value?.cutoff_day || 26,
    paymentDay: payroll.data?.value?.payment_day || 30,
    overtimeEnabled: payroll.data?.value?.overtime_enabled === true,
    overtimeMultiplier: Number(payroll.data?.value?.overtime_multiplier) || 1,
    overtimeMinMinutes: payroll.data?.value?.overtime_min_minutes ?? 30,
    defaultAnnual: lp?.default_annual || 21,
    defaultSick: lp?.default_sick || 15,
    hourlyMonthlyHours: lp?.hourly_monthly_hours ?? 8,
    leaveTypes: lp?.active_types?.length ? lp.active_types : DEFAULT_LEAVE_TYPES,
    announcements: (ann.data ?? []) as Announcement[],
    schedules: (ws.data ?? []) as WorkSchedule[],
    branches: (br.data ?? []) as SettingsData['branches'],
    departments: (dep.data ?? []) as Department[],
    employees: (emp.data ?? []) as SettingsData['employees'],
  };
}

/**
 * حفظ تبويب "عام" بالترتيب: بيانات الشركة (تحديث أو إنشاء)، ثم سياستا الأرشفة والإجازات،
 * ثم سياسة الرواتب عبر set_payroll_policy (السيرفر يتحقق من القيم ويحافظ على بقية المفاتيح). ترمي عند الخطأ.
 */
export async function saveGeneralSettings(s: {
  company: Record<string, string>;
  trackingDays: number;
  defaultAnnual: number;
  defaultSick: number;
  hourlyMonthlyHours: number;
  leaveTypes: LeaveTypeOption[];
  cutoffDay: number;
  paymentDay: number;
  overtimeEnabled: boolean;
  overtimeMultiplier: number;
  overtimeMinMinutes: number;
}): Promise<void> {
  const companyData = { ...s.company, updated_at: new Date().toISOString() };
  const { data: existing } = await supabase.from('company_settings').select('id').maybeSingle();
  const { error: compErr } = existing
    ? await supabase.from('company_settings').update(companyData).eq('id', existing.id)
    : await supabase.from('company_settings').insert(companyData);
  if (compErr) throw compErr;

  const { error: sysErr } = await supabase.from('system_settings').upsert([
    {
      key: 'archive_policy',
      value: { tracking_archive_days: Number(s.trackingDays) },
      description: 'إعدادات أرشفة بيانات تتبع الحضور والمواقع وسلة المحذوفات تلقائياً',
    },
    {
      key: 'leave_policy',
      value: {
        default_annual: Number(s.defaultAnnual),
        default_sick: Number(s.defaultSick),
        hourly_monthly_hours: Number(s.hourlyMonthlyHours),
        active_types: s.leaveTypes,
      },
      description: 'سياسة الإجازات العامة وأنواعها المتاحة بالشركة',
    },
  ]);
  if (sysErr) throw sysErr;

  const { error: payErr } = await supabase.rpc('set_payroll_policy', {
    p_cutoff_day: Number(s.cutoffDay),
    p_payment_day: Number(s.paymentDay),
    p_overtime_enabled: s.overtimeEnabled,
    p_overtime_multiplier: Number(s.overtimeMultiplier),
    p_overtime_min_minutes: Number(s.overtimeMinMinutes),
  });
  if (payErr) throw payErr;
}

/** جدول دوام جديد لفرع/قسم/موظف (المفتاح branch_id أو department_id أو employee_id). ترمي عند الخطأ. */
export async function addWorkSchedule(row: Record<string, unknown>): Promise<void> {
  const { error } = await supabase.from('work_schedules').insert(row);
  if (error) throw error;
}

export async function deleteWorkSchedule(id: string): Promise<void> {
  const { error } = await supabase.from('work_schedules').delete().eq('id', id);
  if (error) throw error;
}

// دالتا التعاميم ترجعان الخطأ بدل رميه: الواجهة تطفي مؤشر التحميل قبل فحصه.
export async function deleteAnnouncement(id: string) {
  const { error } = await supabase.from('announcements').delete().eq('id', id);
  return error;
}

export async function deleteAllAnnouncements() {
  const { error } = await supabase.from('announcements').delete().gt('created_at', '1970-01-01');
  return error;
}

// ── العطل الرسمية (HolidaysCard) — ترجع الخطأ بدل رميه: الواجهة تعرض رسالة حسب نوعه ──

export type Holiday = { holiday_date: string; name: string };

/** العطل من قبل 60 يوماً فما بعد، مرتبة بالتاريخ. */
export async function fetchRecentHolidays() {
  const { data, error } = await supabase
    .from('official_holidays')
    .select('holiday_date, name')
    .gte('holiday_date', new Date(Date.now() - 60 * 86400000).toISOString().slice(0, 10))
    .order('holiday_date');
  return { data: (data ?? null) as Holiday[] | null, error };
}

/** إضافة عطلة باسم المستخدم الحالي. الخطأ 23505 = اليوم مسجّل مسبقاً. */
export async function addHoliday(date: string, name: string) {
  const { data: { user } } = await supabase.auth.getUser();
  const { error } = await supabase.from('official_holidays').insert({ holiday_date: date, name, created_by: user?.id });
  return error;
}

export async function deleteHoliday(date: string) {
  const { error } = await supabase.from('official_holidays').delete().eq('holiday_date', date);
  return error;
}
