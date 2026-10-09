'use client';

import React, { useEffect, useState } from 'react';
import { Archive, Clock, ShieldAlert, Trash2 } from 'lucide-react';
import type { Employee } from '@/lib/db-types';
import { Field, Input, Modal, ModalFooter, cn, type Tone } from '@/components/ui';
import { getLocalDateStr } from '@/lib/dates';
import { fetchLastPunchDate } from '../api';
import type { DeleteType } from '../types';

const DELETE_OPTIONS: { value: DeleteType; icon: typeof Archive; tone: Tone; title: string; body: string }[] = [
  {
    value: 'archive',
    icon: Archive,
    tone: 'indigo',
    title: 'أرشفة وتجميد الحساب (موصى به)',
    body: 'يُمنع الموظف من تسجيل الدوام مع الحفاظ على كل سجلاته في الأرشيف للرجوع إليها.',
  },
  {
    value: 'scheduled',
    icon: Clock,
    tone: 'amber',
    title: 'حذف مجدول بعد 30 يوماً',
    body: 'يُجمّد الحساب فوراً، وبعد 30 يوماً يُحذف حساب الدخول وبياناته الشخصية. تبقى كشوف رواتبه وسلفه وحضوره.',
  },
  {
    value: 'immediate',
    icon: ShieldAlert,
    tone: 'rose',
    title: 'حذف فوري ونهائي',
    body: 'يحذف حساب الدخول ويُخفي البيانات الشخصية فوراً ولا يمكن استرجاعه. تبقى كشوف رواتبه وسلفه وحضوره للمحاسبة.',
  },
];

type Props = {
  employeeToDelete: Employee;
  saving: boolean;
  onClose: () => void;
  onSubmit: (deleteType: DeleteType, reason: string, lastDay: string) => void;
};

/** اختيار طريقة إنهاء خدمة الموظف: أرشفة، حذف مجدول، أو حذف فوري. */
export function DeleteEmployeeModal({ employeeToDelete, saving, onClose, onSubmit }: Props) {
  const [type, setType] = useState<DeleteType>('archive');
  const [reason, setReason] = useState('');
  // آخر يوم عمل فعلي: يُحسب راتبه حتى هذا اليوم (كان يُعتمد يوم الضغط على الزر)
  const [lastDay, setLastDay] = useState(() => getLocalDateStr());
  // ذكي: آخر يوم عمل المقترح = آخر يوم بصم بيه (الراتب ينحسب للأيام اللي اشتغلها بالضبط)
  const [lastPunch, setLastPunch] = useState<string | null>(null);
  useEffect(() => {
    let alive = true;
    void fetchLastPunchDate(employeeToDelete.id).then((d) => {
      if (!alive || !d) return;
      setLastPunch(d);
      setLastDay((cur) => (d < cur ? d : cur));
    });
    return () => { alive = false; };
  }, [employeeToDelete.id]);

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(type, reason, lastDay);
  };

  return (
    <Modal
      title="حذف أو أرشفة الموظف"
      subtitle={`${employeeToDelete.full_name} · ${employeeToDelete.employee_code || 'بدون رمز'}`}
      icon={Trash2}
      tone="rose"
      onClose={onClose}
    >
      <form onSubmit={submit} className="space-y-4">
        <div className="space-y-2">
          {DELETE_OPTIONS.map((opt) => {
            const active = type === opt.value;
            return (
              <label
                key={opt.value}
                className={cn(
                  'flex gap-3 p-3.5 rounded-2xl border cursor-pointer transition-colors',
                  active ? 'border-indigo-400/50 bg-indigo-500/10' : 'border-slate-800 bg-slate-950/40 hover:border-slate-700',
                )}
              >
                <input type="radio" name="deleteType" checked={active} onChange={() => setType(opt.value)} className="mt-1" />
                <opt.icon className={cn('w-4 h-4 mt-0.5 shrink-0', opt.tone === 'rose' ? 'text-rose-400' : opt.tone === 'amber' ? 'text-amber-400' : 'text-indigo-300')} />
                <div>
                  <p className="text-xs font-bold text-white">{opt.title}</p>
                  <p className={cn('text-[11px] mt-1 leading-relaxed', opt.tone === 'rose' ? 'text-rose-300/90' : 'text-slate-400')}>{opt.body}</p>
                </div>
              </label>
            );
          })}
        </div>
        <Field label="آخر يوم عمل" hint={lastPunch ? `آخر بصمة له كانت يوم ${lastPunch}. يُحسب راتبه للأيام اللي اشتغلها لحد هذا اليوم.` : 'يُحسب راتبه في المسير الأخير حتى هذا اليوم.'}>
          <Input type="date" required value={lastDay} onChange={(e) => setLastDay(e.target.value)} dir="ltr" />
        </Field>
        <Field label="السبب (اختياري)">
          <Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="مثال: استقالة، انتهاء العقد..." />
        </Field>
        <ModalFooter
          onCancel={onClose}
          loading={saving}
          submitLabel="تأكيد وتنفيذ"
          variant={type === 'immediate' ? 'danger' : type === 'scheduled' ? 'warning' : 'primary'}
        />
      </form>
    </Modal>
  );
}
