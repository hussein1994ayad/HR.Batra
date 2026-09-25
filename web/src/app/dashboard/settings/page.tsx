'use client';

import React, { useState } from 'react';
import toast from 'react-hot-toast';
import {
  Settings,
  Building,
  ShieldAlert,
  Save,
  Phone,
  Mail,
  Globe,
  CreditCard,
  Clock,
  CalendarRange,
  Trash2,
  Plus,
  Megaphone,
  Banknote,
  CalendarClock,
  Pin,
  AlertTriangle,
  Image as ImageIcon,
  MapPin,
} from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { confetti } from '@/lib/lazy';
import { useQuery } from '@/lib/useQuery';
import { getCycleDates } from '@/lib/payroll';
import { DEFAULT_WORK_DAYS } from '@/lib/attendance';
import { WEEKDAYS_AR, errorMessage, formatDateTime, formatTime12h } from '@/lib/format';
import type { Announcement, Branch, Department, Employee, LeaveTypeOption, WorkSchedule } from '@/lib/types';
import { useConfirm } from '@/components/confirm';
import {
  Badge,
  Button,
  Card,
  CardHeader,
  DataTable,
  EmptyState,
  Field,
  IconButton,
  InfoNote,
  Input,
  PageHeader,
  PageSkeleton,
  SegmentedTabs,
  Select,
  TableEmpty,
  cn,
} from '@/components/ui';

interface CompanySettings {
  name?: string | null;
  address?: string | null;
  phone?: string | null;
  email?: string | null;
  website?: string | null;
  tax_number?: string | null;
  logo_url?: string | null;
}

interface SettingsData {
  company: CompanySettings | null;
  trackingDays: number;
  cycleStartDay: number;
  cycleEndDay: number;
  defaultAnnual: number;
  defaultSick: number;
  leaveTypes: LeaveTypeOption[];
  announcements: Announcement[];
  schedules: WorkSchedule[];
  branches: Pick<Branch, 'id' | 'name'>[];
  departments: Department[];
  employees: Pick<Employee, 'id' | 'full_name'>[];
}

const DEFAULT_LEAVE_TYPES: LeaveTypeOption[] = [
  { id: 'annual', name: 'إجازة سنوية' },
  { id: 'sick', name: 'إجازة مرضية' },
  { id: 'emergency', name: 'إجازة طارئة' },
  { id: 'maternity', name: 'إجازة أمومة' },
  { id: 'other', name: 'إجازة أخرى' },
];
const PROTECTED_LEAVE_TYPES = ['annual', 'sick'];
// Saturday first, matching the Iraqi working week.
const WEEK_ORDER = [6, 0, 1, 2, 3, 4, 5];

async function fetchSettings(): Promise<SettingsData> {
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
    cycleStartDay: payroll.data?.value?.cycle_start_day || 25,
    cycleEndDay: payroll.data?.value?.cycle_end_day || 24,
    defaultAnnual: lp?.default_annual || 21,
    defaultSick: lp?.default_sick || 15,
    leaveTypes: lp?.active_types?.length ? lp.active_types : DEFAULT_LEAVE_TYPES,
    announcements: (ann.data ?? []) as Announcement[],
    schedules: (ws.data ?? []) as WorkSchedule[],
    branches: (br.data ?? []) as SettingsData['branches'],
    departments: (dep.data ?? []) as Department[],
    employees: (emp.data ?? []) as SettingsData['employees'],
  };
}

export default function SettingsPage() {
  const query = useQuery('settings', fetchSettings);
  const [section, setSection] = useState<'general' | 'schedules' | 'announcements'>('general');

  if (!query.data) {
    if (query.error) {
      return <EmptyState icon={AlertTriangle} tone="rose" title="تعذر تحميل الإعدادات" description={errorMessage(query.error)} action={<Button size="sm" variant="secondary" onClick={query.reload}>إعادة المحاولة</Button>} />;
    }
    return <PageSkeleton />;
  }

  return (
    <div className="space-y-6 pb-12">
      <PageHeader
        icon={Settings}
        title="الإعدادات"
        description="بيانات الشركة، سياسات الإجازات والرواتب، جداول الدوام، والتعاميم"
        actions={
          <SegmentedTabs
            value={section}
            onChange={setSection}
            options={[
              { value: 'general', label: 'عام', icon: Building },
              { value: 'schedules', label: 'جداول الدوام', icon: CalendarClock, count: query.data.schedules.length },
              { value: 'announcements', label: 'التعاميم', icon: Megaphone, count: query.data.announcements.length },
            ]}
          />
        }
      />

      {section === 'general' && <GeneralSettings initial={query.data} onSaved={query.reload} />}
      {section === 'schedules' && <SchedulesSection data={query.data} onChanged={query.reload} />}
      {section === 'announcements' && (
        <AnnouncementsSection
          announcements={query.data.announcements}
          onRemoved={(ids) => query.mutate((d) => ({ ...d, announcements: d.announcements.filter((a) => !ids.includes(a.id)) }))}
        />
      )}
    </div>
  );
}

/* ------------------------------ General ------------------------------ */

function GeneralSettings({ initial, onSaved }: { initial: SettingsData; onSaved: () => void }) {
  const c = initial.company;
  const [company, setCompany] = useState({
    name: c?.name ?? '',
    address: c?.address ?? '',
    phone: c?.phone ?? '',
    email: c?.email ?? '',
    website: c?.website ?? '',
    tax_number: c?.tax_number ?? '',
    logo_url: c?.logo_url ?? '',
  });
  const [trackingDays, setTrackingDays] = useState(initial.trackingDays);
  const [cycleStart, setCycleStart] = useState(initial.cycleStartDay);
  const [cycleEnd, setCycleEnd] = useState(initial.cycleEndDay);
  const [defaultAnnual, setDefaultAnnual] = useState(initial.defaultAnnual);
  const [defaultSick, setDefaultSick] = useState(initial.defaultSick);
  const [leaveTypes, setLeaveTypes] = useState<LeaveTypeOption[]>(initial.leaveTypes);
  const [newTypeName, setNewTypeName] = useState('');
  const [newTypeId, setNewTypeId] = useState('');
  const [saving, setSaving] = useState(false);

  const now = new Date();
  const currentMonth = `${now.getFullYear()}-${(now.getMonth() + 1).toString().padStart(2, '0')}`;
  const cyclePreview = getCycleDates(currentMonth, cycleStart, cycleEnd);

  const addLeaveType = () => {
    const id = newTypeId.trim().toLowerCase().replace(/\s+/g, '_');
    if (!id || !newTypeName.trim()) {
      toast.error('يرجى كتابة اسم ورمز نوع الإجازة');
      return;
    }
    if (leaveTypes.some((t) => t.id === id)) {
      toast.error('رمز الإجازة هذا موجود بالفعل');
      return;
    }
    setLeaveTypes([...leaveTypes, { id, name: newTypeName.trim() }]);
    setNewTypeId('');
    setNewTypeName('');
  };

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    try {
      const companyData = { ...company, updated_at: new Date().toISOString() };
      const { data: existing } = await supabase.from('company_settings').select('id').maybeSingle();
      const { error: compErr } = existing
        ? await supabase.from('company_settings').update(companyData).eq('id', existing.id)
        : await supabase.from('company_settings').insert(companyData);
      if (compErr) throw compErr;

      const { error: sysErr } = await supabase.from('system_settings').upsert([
        {
          key: 'archive_policy',
          value: { tracking_archive_days: Number(trackingDays) },
          description: 'إعدادات أرشفة بيانات تتبع الحضور والمواقع وسلة المحذوفات تلقائياً',
        },
        {
          key: 'leave_policy',
          value: { default_annual: Number(defaultAnnual), default_sick: Number(defaultSick), active_types: leaveTypes },
          description: 'سياسة الإجازات العامة وأنواعها المتاحة بالشركة',
        },
        {
          key: 'payroll_policy',
          value: { cycle_start_day: Number(cycleStart), cycle_end_day: Number(cycleEnd) },
          description: 'إعدادات تحديد دورة الحسابات المالية والرواتب الشهرية',
        },
      ]);
      if (sysErr) throw sysErr;

      confetti({ particleCount: 80, spread: 60, colors: ['#818CF8', '#10B981'] });
      toast.success('تم حفظ الإعدادات');
      onSaved();
    } catch (err) {
      toast.error(`فشل حفظ الإعدادات: ${errorMessage(err)}`);
    } finally {
      setSaving(false);
    }
  };

  const setCompanyField = (key: keyof typeof company) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setCompany((prev) => ({ ...prev, [key]: e.target.value }));

  return (
    <form onSubmit={save} className="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <div className="lg:col-span-2 space-y-6">
        <Card>
          <CardHeader icon={Building} title="بيانات الشركة" description="تظهر في كشوف الرواتب وتطبيق الموظفين" />
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <Field label="اسم الشركة">
              <Input required value={company.name} onChange={setCompanyField('name')} />
            </Field>
            <Field label="العنوان">
              <div className="relative">
                <MapPin className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />
                <Input value={company.address} onChange={setCompanyField('address')} className="pr-9" />
              </div>
            </Field>
            <Field label="رقم الهاتف">
              <div className="relative">
                <Phone className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />
                <Input type="tel" value={company.phone} onChange={setCompanyField('phone')} dir="ltr" className="text-left pl-9" />
              </div>
            </Field>
            <Field label="البريد الإلكتروني">
              <div className="relative">
                <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />
                <Input type="email" value={company.email} onChange={setCompanyField('email')} dir="ltr" className="text-left pl-9" />
              </div>
            </Field>
            <Field label="الموقع الإلكتروني">
              <div className="relative">
                <Globe className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />
                <Input value={company.website} onChange={setCompanyField('website')} dir="ltr" className="text-left pl-9" />
              </div>
            </Field>
            <Field label="الرقم الضريبي (اختياري)">
              <div className="relative">
                <CreditCard className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />
                <Input value={company.tax_number} onChange={setCompanyField('tax_number')} dir="ltr" className="text-left pl-9" />
              </div>
            </Field>
            <Field label="رابط شعار الشركة" className="md:col-span-2">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 shrink-0 rounded-xl bg-slate-900 border border-slate-800 flex items-center justify-center overflow-hidden">
                  {company.logo_url ? (
                    // eslint-disable-next-line @next/next/no-img-element -- arbitrary external logo URL
                    <img src={company.logo_url} alt="" className="w-full h-full object-contain" />
                  ) : (
                    <ImageIcon className="w-4 h-4 text-slate-600" />
                  )}
                </div>
                <Input value={company.logo_url} onChange={setCompanyField('logo_url')} placeholder="https://example.com/logo.png" dir="ltr" className="text-left font-mono" />
              </div>
            </Field>
          </div>
        </Card>

        <Card>
          <CardHeader icon={CalendarRange} tone="amber" title="سياسة الإجازات" description="الأرصدة الافتراضية للموظفين الجدد وأنواع الإجازات المتاحة" />
          <div className="grid grid-cols-2 gap-4 mb-5">
            <Field label="رصيد الإجازة السنوية (يوم/سنة)">
              <Input type="number" min={0} required value={defaultAnnual} onChange={(e) => setDefaultAnnual(Number(e.target.value))} dir="ltr" className="text-left" />
            </Field>
            <Field label="رصيد الإجازة المرضية (يوم/سنة)">
              <Input type="number" min={0} required value={defaultSick} onChange={(e) => setDefaultSick(Number(e.target.value))} dir="ltr" className="text-left" />
            </Field>
          </div>
          <p className="text-[11px] font-bold text-slate-400 mb-2">أنواع الإجازات</p>
          <div className="flex flex-wrap gap-2 mb-4">
            {leaveTypes.map((t) => (
              <span key={t.id} className="inline-flex items-center gap-1.5 pr-3 pl-1.5 h-8 rounded-xl bg-slate-900 border border-slate-800 text-xs text-slate-200">
                <span className="font-bold">{t.name}</span>
                <span className="text-[10px] text-slate-500 font-mono">{t.id}</span>
                {PROTECTED_LEAVE_TYPES.includes(t.id) ? (
                  <span className="w-5" />
                ) : (
                  <button
                    type="button"
                    onClick={() => setLeaveTypes(leaveTypes.filter((x) => x.id !== t.id))}
                    className="p-1 rounded-md text-slate-500 hover:text-rose-400 hover:bg-rose-500/10 cursor-pointer"
                    aria-label={`حذف ${t.name}`}
                  >
                    <Trash2 className="w-3 h-3" />
                  </button>
                )}
              </span>
            ))}
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-[1fr_1fr_auto] gap-2 items-end">
            <Field label="اسم نوع جديد">
              <Input value={newTypeName} onChange={(e) => setNewTypeName(e.target.value)} placeholder="مثال: إجازة زواج" />
            </Field>
            <Field label="الرمز (بالإنجليزية)">
              <Input value={newTypeId} onChange={(e) => setNewTypeId(e.target.value)} placeholder="marriage" dir="ltr" className="text-left font-mono" />
            </Field>
            <Button variant="soft" icon={Plus} onClick={addLeaveType}>
              إضافة
            </Button>
          </div>
        </Card>
      </div>

      <div className="space-y-6">
        <Card>
          <CardHeader icon={Banknote} tone="emerald" title="الدورة المالية للرواتب" />
          <div className="grid grid-cols-2 gap-3">
            <Field label="يوم البداية">
              <Input type="number" min={1} max={31} required value={cycleStart} onChange={(e) => setCycleStart(Number(e.target.value))} className="text-center" />
            </Field>
            <Field label="يوم النهاية">
              <Input type="number" min={1} max={31} required value={cycleEnd} onChange={(e) => setCycleEnd(Number(e.target.value))} className="text-center" />
            </Field>
          </div>
          <InfoNote tone="emerald" icon={CalendarRange} className="mt-4">
            دورة الشهر الحالي: <span className="font-mono font-bold" dir="ltr">{cyclePreview.start}</span> ← <span className="font-mono font-bold" dir="ltr">{cyclePreview.end}</span>
          </InfoNote>
        </Card>

        <Card>
          <CardHeader icon={ShieldAlert} tone="amber" title="الأرشفة والتتبع" />
          <Field label="الاحتفاظ ببيانات التتبع (يوم)" hint="تُحذف إحداثيات التتبع ومخالفات السياج الأقدم من هذه المدة تلقائياً.">
            <Input type="number" min={1} required value={trackingDays} onChange={(e) => setTrackingDays(Number(e.target.value))} dir="ltr" className="text-left" />
          </Field>
          <InfoNote tone="slate" icon={Trash2} className="mt-4">
            تُحفظ المستندات المحذوفة 30 يوماً في سلة المحذوفات قبل إتلافها نهائياً.
          </InfoNote>
        </Card>

        <div className="lg:sticky lg:top-4">
          <Button type="submit" icon={Save} loading={saving} block size="lg">
            {saving ? 'جاري الحفظ...' : 'حفظ الإعدادات'}
          </Button>
        </div>
      </div>
    </form>
  );
}

/* ------------------------------ Work schedules ------------------------------ */

function SchedulesSection({ data, onChanged }: { data: SettingsData; onChanged: () => void }) {
  const confirm = useConfirm();
  const [name, setName] = useState('');
  const [scope, setScope] = useState<'branch' | 'department' | 'employee'>('branch');
  const [targetId, setTargetId] = useState('');
  const [checkIn, setCheckIn] = useState('09:00');
  const [checkOut, setCheckOut] = useState('17:00');
  const [grace, setGrace] = useState(15);
  const [workDays, setWorkDays] = useState<number[]>(DEFAULT_WORK_DAYS);
  const [saving, setSaving] = useState(false);

  const targets = scope === 'branch' ? data.branches : scope === 'department' ? data.departments : data.employees.map((e) => ({ id: e.id, name: e.full_name }));

  const targetName = (s: WorkSchedule) => {
    if (s.employee_id) return { label: 'موظف', name: data.employees.find((e) => e.id === s.employee_id)?.full_name };
    if (s.department_id) return { label: 'قسم', name: data.departments.find((d) => d.id === s.department_id)?.name };
    if (s.branch_id) return { label: 'فرع', name: data.branches.find((b) => b.id === s.branch_id)?.name };
    return { label: 'عام', name: '' };
  };

  const add = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!targetId) {
      toast.error('يرجى تحديد الجهة المستهدفة');
      return;
    }
    if (workDays.length === 0) {
      toast.error('اختر يوم عمل واحداً على الأقل');
      return;
    }
    setSaving(true);
    try {
      const { error } = await supabase.from('work_schedules').insert({
        name: name.trim(),
        check_in_time: `${checkIn}:00`,
        check_out_time: `${checkOut}:00`,
        grace_period_minutes: Number(grace),
        work_days: [...workDays].sort((a, b) => a - b),
        [`${scope}_id`]: targetId,
      });
      if (error) throw error;
      toast.success('تم إضافة جدول الدوام');
      setName('');
      setTargetId('');
      onChanged();
    } catch (err) {
      toast.error(`فشل إضافة الجدول: ${errorMessage(err)}`);
    } finally {
      setSaving(false);
    }
  };

  const remove = async (s: WorkSchedule) => {
    const ok = await confirm({ title: `حذف جدول «${s.name}»؟`, message: 'سيعود الموظفون المشمولون إلى الجدول الأعم التالي أو الدوام الافتراضي.', confirmLabel: 'حذف' });
    if (!ok) return;
    const { error } = await supabase.from('work_schedules').delete().eq('id', s.id);
    if (error) {
      toast.error(`فشل حذف الجدول: ${errorMessage(error)}`);
      return;
    }
    toast.success('تم حذف جدول الدوام');
    onChanged();
  };

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <Card>
        <CardHeader icon={Plus} title="جدول دوام جديد" description="يُطبّق حسب الأولوية: الموظف ثم القسم ثم الفرع" />
        <form onSubmit={add} className="space-y-4">
          <Field label="اسم الجدول">
            <Input required value={name} onChange={(e) => setName(e.target.value)} placeholder="مثال: دوام فرع بغداد" />
          </Field>
          <Field label="نطاق التطبيق">
            <SegmentedTabs
              value={scope}
              onChange={(v) => {
                setScope(v);
                setTargetId('');
              }}
              className="w-full"
              options={[
                { value: 'branch', label: 'فرع' },
                { value: 'department', label: 'قسم' },
                { value: 'employee', label: 'موظف' },
              ]}
            />
          </Field>
          <Field label="الجهة المستهدفة">
            <Select required value={targetId} onChange={(e) => setTargetId(e.target.value)}>
              <option value="">اختر...</option>
              {targets.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name}
                </option>
              ))}
            </Select>
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="الدخول">
              <Input type="time" required value={checkIn} onChange={(e) => setCheckIn(e.target.value)} dir="ltr" />
            </Field>
            <Field label="الخروج">
              <Input type="time" required value={checkOut} onChange={(e) => setCheckOut(e.target.value)} dir="ltr" />
            </Field>
          </div>
          <Field label="فترة السماح للتأخير (دقيقة)">
            <Input type="number" min={0} required value={grace} onChange={(e) => setGrace(Number(e.target.value))} dir="ltr" className="text-left" />
          </Field>
          <Field label="أيام العمل">
            <div className="grid grid-cols-4 gap-1.5">
              {WEEK_ORDER.map((d) => {
                const on = workDays.includes(d);
                return (
                  <button
                    key={d}
                    type="button"
                    onClick={() => setWorkDays(on ? workDays.filter((x) => x !== d) : [...workDays, d])}
                    className={cn(
                      'h-9 rounded-lg text-[11px] font-bold border transition-colors cursor-pointer',
                      on ? 'bg-indigo-500/15 border-indigo-400/40 text-indigo-200' : 'bg-slate-950/60 border-slate-800 text-slate-500 hover:text-slate-300',
                    )}
                  >
                    {WEEKDAYS_AR[d]}
                  </button>
                );
              })}
            </div>
          </Field>
          <Button type="submit" icon={Save} loading={saving} block>
            حفظ الجدول
          </Button>
        </form>
      </Card>

      <Card className="lg:col-span-2">
        <CardHeader icon={CalendarClock} tone="sky" title="جداول الدوام المسجلة" description="بدون جدول يُعتمد الدوام الافتراضي: السبت–الخميس من 9 ص إلى 5 م" />
        <DataTable>
          <thead>
            <tr>
              <th>الجدول</th>
              <th>يطبق على</th>
              <th>الأوقات</th>
              <th>أيام الدوام</th>
              <th className="!text-left" />
            </tr>
          </thead>
          <tbody>
            {data.schedules.length === 0 ? (
              <TableEmpty colSpan={5}>لا توجد جداول دوام مضافة</TableEmpty>
            ) : (
              data.schedules.map((s) => {
                const t = targetName(s);
                return (
                  <tr key={s.id}>
                    <td className="font-bold text-white">{s.name}</td>
                    <td>
                      <Badge tone="slate">{t.label}</Badge> <span className="text-slate-300">{t.name || 'غير معروف'}</span>
                    </td>
                    <td className="whitespace-nowrap">
                      <span className="font-mono text-indigo-200" dir="ltr">{formatTime12h(s.check_in_time)} – {formatTime12h(s.check_out_time)}</span>
                      <span className="block text-[10px] text-slate-500">سماح {s.grace_period_minutes} دقيقة</span>
                    </td>
                    <td>
                      <div className="flex flex-wrap gap-1 max-w-[260px]">
                        {WEEK_ORDER.filter((d) => (s.work_days || []).includes(d)).map((d) => (
                          <span key={d} className="px-1.5 py-0.5 rounded-md bg-slate-800/80 text-[10px] text-slate-300">{WEEKDAYS_AR[d]}</span>
                        ))}
                      </div>
                    </td>
                    <td className="!text-left">
                      <IconButton icon={Trash2} label="حذف الجدول" tone="rose" onClick={() => remove(s)} />
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </DataTable>
      </Card>
    </div>
  );
}

/* ------------------------------ Announcements ------------------------------ */

function AnnouncementsSection({ announcements, onRemoved }: { announcements: Announcement[]; onRemoved: (ids: string[]) => void }) {
  const confirm = useConfirm();
  const [busy, setBusy] = useState<string | null>(null);

  const remove = async (a: Announcement) => {
    const ok = await confirm({ title: 'حذف التعميم؟', message: a.content, confirmLabel: 'حذف' });
    if (!ok) return;
    setBusy(a.id);
    const { error } = await supabase.from('announcements').delete().eq('id', a.id);
    setBusy(null);
    if (error) {
      toast.error(`فشل حذف التعميم: ${errorMessage(error)}`);
      return;
    }
    onRemoved([a.id]);
    toast.success('تم حذف التعميم');
  };

  const purge = async () => {
    const ok = await confirm({ title: 'إخلاء أرشيف التعاميم بالكامل؟', message: 'سيتم حذف كل التعاميم نهائياً ولا يمكن التراجع.', confirmLabel: 'إخلاء الأرشيف' });
    if (!ok) return;
    setBusy('purge');
    const { error } = await supabase.from('announcements').delete().gt('created_at', '1970-01-01');
    setBusy(null);
    if (error) {
      toast.error(`فشل إخلاء الأرشيف: ${errorMessage(error)}`);
      return;
    }
    onRemoved(announcements.map((a) => a.id));
    toast.success('تم إخلاء أرشيف التعاميم');
  };

  return (
    <Card>
      <CardHeader
        icon={Megaphone}
        tone="violet"
        title="أرشيف التعاميم"
        description="التعاميم المرسلة للموظفين من لوحة المؤشرات"
        actions={
          announcements.length > 0 && (
            <Button size="sm" variant="soft-danger" icon={Trash2} loading={busy === 'purge'} onClick={purge}>
              إخلاء الأرشيف
            </Button>
          )
        }
      />
      {announcements.length === 0 ? (
        <EmptyState icon={Megaphone} title="لا توجد تعاميم" description="التعاميم المرسلة من لوحة المؤشرات ستظهر هنا." />
      ) : (
        <div className="space-y-2">
          {announcements.map((a) => (
            <div key={a.id} className="flex items-start gap-3 p-4 rounded-2xl bg-slate-900/50 border border-slate-800/80">
              <div className="w-9 h-9 shrink-0 rounded-xl bg-violet-500/10 border border-violet-500/20 text-violet-300 flex items-center justify-center">
                <Megaphone className="w-4 h-4" />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex flex-wrap items-center gap-2 mb-1">
                  <h4 className="text-[13px] font-bold text-white">{a.title}</h4>
                  {a.is_pinned && <Badge tone="violet"><Pin className="w-3 h-3" /> مثبت</Badge>}
                  <span className="text-[10px] text-slate-500 flex items-center gap-1" dir="ltr">
                    <Clock className="w-3 h-3" /> {formatDateTime(a.created_at)}
                  </span>
                </div>
                <p className="text-xs text-slate-400 leading-relaxed whitespace-pre-line">{a.content}</p>
              </div>
              <IconButton icon={Trash2} label="حذف التعميم" tone="rose" loading={busy === a.id} onClick={() => remove(a)} />
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
