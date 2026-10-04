'use client';

// تبويب "عام": بيانات الشركة، سياسة الإجازات وأنواعها، مسير الرواتب والإضافي، العطل، والأرشفة — حفظ واحد.

import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { Banknote, Building, CalendarRange, Clock, CreditCard, Globe, Image as ImageIcon, Mail, MapPin, Phone, Plus, Save, ShieldAlert, Trash2 } from 'lucide-react';
import { confetti } from '@/lib/lazy';
import { errorMessage } from '@/lib/format';
import type { LeaveTypeOption } from '@/lib/db-types';
import { currentPayrollMonth, previewPayrollPeriod } from '@/features/payroll/period';
import { Button, Card, CardHeader, Field, InfoNote, Input, Toggle } from '@/components/ui';
import { HolidaysCard } from './HolidaysCard';
import { saveGeneralSettings } from '../api';
import { PROTECTED_LEAVE_TYPES } from '../logic';
import type { SettingsData } from '../types';

export function GeneralSettings({ initial, onSaved }: { initial: SettingsData; onSaved: () => void }) {
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
  const [cutoffDay, setCutoffDay] = useState(initial.cutoffDay);
  const [paymentDay, setPaymentDay] = useState(initial.paymentDay);
  const [overtimeEnabled, setOvertimeEnabled] = useState(initial.overtimeEnabled);
  const [overtimeMultiplier, setOvertimeMultiplier] = useState(initial.overtimeMultiplier);
  const [overtimeMinMinutes, setOvertimeMinMinutes] = useState(initial.overtimeMinMinutes);
  const [defaultAnnual, setDefaultAnnual] = useState(initial.defaultAnnual);
  const [defaultSick, setDefaultSick] = useState(initial.defaultSick);
  const [hourlyMonthlyHours, setHourlyMonthlyHours] = useState(initial.hourlyMonthlyHours);
  const [leaveTypes, setLeaveTypes] = useState<LeaveTypeOption[]>(initial.leaveTypes);
  const [newTypeName, setNewTypeName] = useState('');
  const [newTypeId, setNewTypeId] = useState('');
  const [saving, setSaving] = useState(false);

  const cyclePreview = previewPayrollPeriod(currentPayrollMonth(cutoffDay), cutoffDay, paymentDay);

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
      await saveGeneralSettings({
        company,
        trackingDays,
        defaultAnnual,
        defaultSick,
        hourlyMonthlyHours,
        leaveTypes,
        cutoffDay,
        paymentDay,
        overtimeEnabled,
        overtimeMultiplier,
        overtimeMinMinutes,
      });

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
          <CardHeader icon={CalendarRange} tone="amber" title="سياسة الإجازات" description="رصيد كل الموظفين: السنوية والمرضية تتجدد كل سنة، والزمنيات كل شهر. تقدر تخصّص رصيد موظف من صفحة الموظفين." />
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-5">
            <Field label="رصيد الإجازة السنوية (يوم/سنة)">
              <Input type="number" min={0} required value={defaultAnnual} onChange={(e) => setDefaultAnnual(Number(e.target.value))} dir="ltr" className="text-left" />
            </Field>
            <Field label="رصيد الإجازة المرضية (يوم/سنة)">
              <Input type="number" min={0} required value={defaultSick} onChange={(e) => setDefaultSick(Number(e.target.value))} dir="ltr" className="text-left" />
            </Field>
            <Field label="الإجازات الزمنية (ساعة/شهر)">
              <Input
                type="number"
                min={0}
                step={0.5}
                required
                value={hourlyMonthlyHours}
                onChange={(e) => setHourlyMonthlyHours(Number(e.target.value))}
                dir="ltr"
                className="text-left"
              />
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
          <CardHeader icon={Banknote} tone="emerald" title="مسير الرواتب" />
          <div className="grid grid-cols-2 gap-3">
            <Field label="يوم قطع المسير" hint="الحركات بعده تُرحَّل للشهر التالي">
              <Input type="number" min={1} max={28} required value={cutoffDay} onChange={(e) => setCutoffDay(Number(e.target.value))} className="text-center" />
            </Field>
            <Field label="يوم صرف الرواتب">
              <Input type="number" min={1} max={31} required value={paymentDay} onChange={(e) => setPaymentDay(Number(e.target.value))} className="text-center" />
            </Field>
          </div>
          <InfoNote tone="emerald" icon={CalendarRange} className="mt-4">
            المسير الحالي: <span className="font-mono font-bold" dir="ltr">{cyclePreview.start}</span> ← <span className="font-mono font-bold" dir="ltr">{cyclePreview.end}</span>
            {' '}· الصرف <span className="font-mono font-bold" dir="ltr">{cyclePreview.payment}</span>
            <span className="block mt-1 text-slate-400">أجر اليوم = الراتب ÷ 30 دائماً. تغيير يوم القطع يطبَّق على المسيرات الجديدة فقط.</span>
          </InfoNote>

          <div className="mt-5 pt-4 border-t border-slate-800/70 space-y-3">
            <div className="flex items-center justify-between gap-3">
              <span className="text-sm font-bold text-slate-200 flex items-center gap-1.5">
                <Clock className="w-4 h-4 text-indigo-300" /> الساعات الإضافية
              </span>
              <Toggle
                checked={overtimeEnabled}
                onChange={setOvertimeEnabled}
                label={<span className={overtimeEnabled ? 'text-emerald-300' : 'text-slate-400'}>{overtimeEnabled ? 'مفعّلة' : 'متوقفة'}</span>}
              />
            </div>
            {overtimeEnabled && (
              <div className="grid grid-cols-2 gap-3">
                <Field label="معامل الأجر" hint="1 = نفس أجر الدقيقة">
                  <Input type="number" min={0.1} step={0.25} required value={overtimeMultiplier} onChange={(e) => setOvertimeMultiplier(Number(e.target.value))} className="text-center" dir="ltr" />
                </Field>
                <Field label="أقل مدة (دقيقة)">
                  <Input type="number" min={0} required value={overtimeMinMinutes} onChange={(e) => setOvertimeMinMinutes(Number(e.target.value))} className="text-center" dir="ltr" />
                </Field>
              </div>
            )}
            <p className="text-[11px] text-slate-500">
              تُحسب بعد نهاية الدوام، ولا تُضاف للراتب إلا بعد اعتمادك لكل يوم من صفحة الرواتب أو القرارات.
            </p>
          </div>
        </Card>

        <HolidaysCard />

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
