'use client';

// تبويب جداول الدوام: إضافة جدول لفرع/قسم/موظف (الأولوية: الموظف ثم القسم ثم الفرع) وحذفه.

import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { CalendarClock, Plus, Save, Trash2 } from 'lucide-react';
import { DEFAULT_WORK_DAYS } from '@/lib/attendance';
import { WEEKDAYS_AR, errorMessage, formatTime12h } from '@/lib/format';
import type { WorkSchedule } from '@/lib/db-types';
import { useConfirm } from '@/components/confirm';
import { Badge, Button, Card, CardHeader, DataTable, Field, IconButton, Input, SegmentedTabs, Select, TableEmpty, cn } from '@/components/ui';
import { addWorkSchedule, deleteWorkSchedule } from '../api';
import { WEEK_ORDER } from '../logic';
import type { SettingsData } from '../types';

export function SchedulesSection({ data, onChanged }: { data: SettingsData; onChanged: () => void }) {
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
      await addWorkSchedule({
        name: name.trim(),
        check_in_time: `${checkIn}:00`,
        check_out_time: `${checkOut}:00`,
        grace_period_minutes: Number(grace),
        work_days: [...workDays].sort((a, b) => a - b),
        [`${scope}_id`]: targetId,
      });
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
    try {
      await deleteWorkSchedule(s.id);
    } catch (error) {
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
