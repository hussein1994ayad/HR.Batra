// استعلامات Supabase الخاصة بصفحة الإعدادات. كل دالة ترمي عند الخطأ.

import { supabase } from '@/lib/supabase';
import type { Announcement, WorkSchedule } from '@/lib/db-types';
import { parseCompany, parsePolicies } from './logic';
import type { GeneralSettings, PurgeOptions, PurgeResult, ScheduleTargets } from './types';

export interface SettingsDataset extends ScheduleTargets {
  general: GeneralSettings;
  announcements: Announcement[];
  workSchedules: WorkSchedule[];
}

export async function fetchSettingsDataset(): Promise<SettingsDataset> {
  const policy = (key: string) => supabase.from('system_settings').select('value').eq('key', key).maybeSingle();
  const [comp, archive, payroll, leave, ann, ws, branches, depts, emps] = await Promise.all([
    supabase.from('company_settings').select('*').limit(1).maybeSingle(),
    policy('archive_policy'),
    policy('payroll_policy'),
    policy('leave_policy'),
    supabase.from('announcements').select('*').order('created_at', { ascending: false }),
    supabase.from('work_schedules').select('*'),
    supabase.from('branches').select('id, name'),
    supabase.from('departments').select('id, name'),
    supabase.from('employees').select('id, full_name').eq('is_active', true).order('full_name'),
  ]);
  const firstError = [comp, archive, payroll, leave, ann, ws, branches, depts, emps].find(r => r.error)?.error;
  if (firstError) throw firstError;

  return {
    general: {
      company: parseCompany(comp.data),
      policies: parsePolicies({ archive: archive.data, payroll: payroll.data, leave: leave.data }),
    },
    announcements: ann.data ?? [],
    workSchedules: ws.data ?? [],
    branches: branches.data ?? [],
    departments: depts.data ?? [],
    employees: emps.data ?? [],
  };
}

export async function fetchAnnouncements(): Promise<Announcement[]> {
  const { data, error } = await supabase.from('announcements').select('*').order('created_at', { ascending: false });
  if (error) throw error;
  return data ?? [];
}

/** يحفظ بيانات الشركة (صف واحد) وسياسات النظام الثلاث. */
export async function saveGeneralSettings({ company, policies }: GeneralSettings) {
  const { data: existing, error: findErr } = await supabase.from('company_settings').select('id').limit(1).maybeSingle();
  if (findErr) throw findErr;

  const companyRow = { ...company, updated_at: new Date().toISOString() };
  const { error: compErr } = existing
    ? await supabase.from('company_settings').update(companyRow).eq('id', existing.id)
    : await supabase.from('company_settings').insert(companyRow);
  if (compErr) throw compErr;

  // key هو المفتاح الأساسي، فـ upsert يُنشئ الصف أو يحدّثه
  const { error } = await supabase.from('system_settings').upsert([
    {
      key: 'archive_policy',
      value: { tracking_archive_days: Number(policies.trackingDays) },
      description: 'إعدادات أرشفة بيانات تتبع الحضور والمواقع وسلة المحذوفات تلقائياً',
    },
    {
      key: 'leave_policy',
      value: {
        default_annual: Number(policies.defaultAnnual),
        default_sick: Number(policies.defaultSick),
        active_types: policies.leaveTypes,
      },
      description: 'سياسة الإجازات العامة وأنواعها المتاحة بالشركة',
    },
    {
      key: 'payroll_policy',
      value: { cycle_start_day: Number(policies.cycleStartDay), cycle_end_day: Number(policies.cycleEndDay) },
      description: 'إعدادات تحديد دورة الحسابات المالية والرواتب الشهرية',
    },
  ], { onConflict: 'key' });
  if (error) throw error;
}

/** حذف بيانات شهر (بعد اعتماد رواتبه) عبر RPC يتحقق من القفل المالي. */
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

export async function insertWorkSchedule(row: Omit<WorkSchedule, 'id'>) {
  const { error } = await supabase.from('work_schedules').insert(row);
  if (error) throw error;
}

export async function deleteWorkSchedule(id: string) {
  const { error } = await supabase.from('work_schedules').delete().eq('id', id);
  if (error) throw error;
}

export async function deleteAnnouncement(id: string) {
  const { error } = await supabase.from('announcements').delete().eq('id', id);
  if (error) throw error;
}

export async function deleteAllAnnouncements() {
  // PostgREST يرفض DELETE بدون شرط، فالشرط يشمل كل الصفوف
  const { error } = await supabase.from('announcements').delete().gt('created_at', '1970-01-01');
  if (error) throw error;
}
