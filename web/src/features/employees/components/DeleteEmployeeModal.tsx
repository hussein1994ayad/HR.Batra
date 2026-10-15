'use client';

import React, { useEffect, useState } from 'react';
import { Archive, Calculator, Clock, Loader2, ShieldAlert, UserMinus } from 'lucide-react';
import type { Employee } from '@/lib/db-types';
import { Field, InfoNote, Input, Modal, ModalFooter, cn, type Tone } from '@/components/ui';
import { getLocalDateStr } from '@/lib/dates';
import { errorMessage, formatIQD } from '@/lib/format';
import { fetchEndOfServicePreview, fetchLastPunchDate } from '../api';
import { endOfServiceBlocks } from '../logic';
import type { DeleteType, EndOfServicePreview } from '../types';

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

/** إنهاء خدمات الموظف: آخر يوم عمل + معاينة آخر راتب (تدقيق 14/10 PAY-001)، وطريقة التعامل مع حسابه. */
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

  // معاينة آخر راتب لهذا اليوم: أيام الدوام بس + الخصومات اللي قررتها الإدارة (السيرفر يحسب وما يحفظ شي)
  const [preview, setPreview] = useState<EndOfServicePreview | null>(null);
  const [previewState, setPreviewState] = useState<'idle' | 'loading' | 'error' | 'unavailable'>('idle');
  const [previewError, setPreviewError] = useState('');
  useEffect(() => {
    if (!lastDay) return;
    let alive = true;
    const t = setTimeout(() => {
      setPreviewState('loading');
      fetchEndOfServicePreview(employeeToDelete.id, lastDay)
        .then((p) => {
          if (!alive) return;
          setPreview(p);
          setPreviewState(p ? 'idle' : 'unavailable');
        })
        .catch((err) => {
          if (!alive) return;
          setPreview(null);
          setPreviewError(errorMessage(err));
          setPreviewState('error');
        });
    }, 350);
    return () => { alive = false; clearTimeout(t); };
  }, [employeeToDelete.id, lastDay]);
  const blocks = preview ? endOfServiceBlocks(preview) : [];

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(type, reason, lastDay);
  };

  return (
    <Modal
      title="إنهاء خدمات الموظف"
      subtitle={`${employeeToDelete.full_name} · ${employeeToDelete.employee_code || 'بدون رمز'}`}
      icon={UserMinus}
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
        <Field label="آخر يوم عمل" hint={lastPunch ? `آخر بصمة له كانت يوم ${lastPunch}. يُحسب راتبه لأيام الدوام لحد هذا اليوم.` : 'يُحسب راتبه لأيام الدوام لحد هذا اليوم.'}>
          <Input type="date" required value={lastDay} onChange={(e) => setLastDay(e.target.value)} dir="ltr" />
        </Field>
        <div className="rounded-2xl border border-slate-800 bg-slate-950/40 p-3.5 space-y-3" aria-live="polite" data-testid="end-of-service-preview">
          <p className="text-xs font-bold text-white flex items-center gap-1.5">
            <Calculator className="w-4 h-4 text-indigo-300" /> شلون ينحسب آخر راتب
            {previewState === 'loading' && <Loader2 className="w-3.5 h-3.5 animate-spin text-slate-400" />}
          </p>
          {previewState === 'error' && <p className="text-[11px] text-rose-300">تعذّر حساب المعاينة: {previewError}</p>}
          {previewState === 'unavailable' && <p className="text-[11px] text-slate-400">المعاينة تشتغل بعد تحديث قاعدة البيانات.</p>}
          {blocks.map((b) => (
            <div key={b.title} className="text-[11px] leading-relaxed">
              <p className="font-bold text-slate-200">{b.title}</p>
              {b.lines.map((l) => <p key={l} className="text-slate-400">• {l}</p>)}
              <p className="text-emerald-300 font-bold">الصافي: {b.net} <span className="font-normal text-slate-500">· {b.when}</span></p>
            </div>
          ))}
          {preview && blocks.length === 0 && <p className="text-[11px] text-slate-400">ما عنده راتب مفتوح لهاليوم (رواتبه معتمدة).</p>}
          {preview && blocks.length > 1 && (
            <p className="text-xs font-bold text-white border-t border-slate-800 pt-2">المجموع المستحق: {formatIQD(preview.total_net)}</p>
          )}
          {preview && Number(preview.loans_left_after) > 0 && (
            <InfoNote tone="amber">باقي عليه سلف {formatIQD(preview.loans_left_after)} بعد آخر راتب: تسويها ويا الموظف خارج النظام.</InfoNote>
          )}
          <p className="text-[10px] text-slate-500">الجمع والعطل الرسمية ما تنحسب. ينخصم بس الغياب والتأخير والإجازات اللي قررتها أنت.</p>
        </div>
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
