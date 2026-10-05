'use client';

// نافذة إضافة/تعديل فرع: الاسم، الموقع (رابط Google Maps أو إحداثيات يُستخرج تلقائياً)، نطاق البصمة، والعنوان.

import React, { useEffect, useState } from 'react';
import toast from 'react-hot-toast';
import { CheckCircle2, Link2, Loader2, Pencil, Plus, Save } from 'lucide-react';
import { confetti } from '@/lib/lazy';
import { resolveMapUrl } from '@/lib/geo';
import { errorMessage } from '@/lib/format';
import { Field, Input, Modal, ModalFooter, Textarea } from '@/components/ui';
import { saveBranch } from '../api';
import type { BranchDraft } from '../logic';

export function BranchFormModal({ draft, onClose, onSaved }: { draft: BranchDraft; onClose: () => void; onSaved: (id?: string) => void }) {
  const [form, setForm] = useState(draft);
  const [mapLink, setMapLink] = useState('');
  const [resolving, setResolving] = useState(false);
  const [resolved, setResolved] = useState(false);
  const [saving, setSaving] = useState(false);
  const isEdit = !!draft.id;

  // Resolve pasted Google Maps links / coordinates shortly after typing stops.
  useEffect(() => {
    const text = mapLink.trim();
    if (!text) return;
    let cancelled = false;
    const timer = setTimeout(() => {
      setResolving(true);
      setResolved(false);
      resolveMapUrl(text)
        .then((coords) => {
          if (cancelled) return;
          if (coords) {
            setForm((f) => ({ ...f, lat: coords.lat, lng: coords.lng }));
            setResolved(true);
          } else {
            toast.error('تعذر استخراج الإحداثيات من الرابط');
          }
        })
        .finally(() => !cancelled && setResolving(false));
    }, 600);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [mapLink]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (form.radius <= 0) {
      toast.error('يجب أن يكون نطاق البصمة أكبر من 0 متر');
      return;
    }
    setSaving(true);
    try {
      const payload = { name: form.name, latitude: form.lat, longitude: form.lng, radius_meters: form.radius, address: form.address };
      await saveBranch(payload, draft.id);
      confetti({ particleCount: 80, spread: 60, colors: ['#2DD4BF', '#818CF8'] });
      toast.success(isEdit ? 'تم تحديث بيانات الفرع' : 'تم إضافة الفرع ونطاق البصمة');
      onSaved(draft.id);
    } catch (err) {
      toast.error(errorMessage(err));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title={isEdit ? 'تعديل الفرع' : 'إضافة فرع جديد'} subtitle="حدد الموقع ونطاق البصمة المسموح" icon={isEdit ? Pencil : Plus} tone="brand" onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="اسم الفرع">
          <Input required value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="مثال: فرع المنصور" />
        </Field>

        <Field
          label={
            <span className="flex items-center justify-between">
              <span>رابط Google Maps أو إحداثيات</span>
              {resolving ? (
                <span className="flex items-center gap-1 text-amber-300"><Loader2 className="w-3 h-3 animate-spin" /> جاري الاستخراج</span>
              ) : resolved ? (
                <span className="flex items-center gap-1 text-emerald-300"><CheckCircle2 className="w-3 h-3" /> تم التحديث</span>
              ) : null}
            </span>
          }
          hint="الصق رابط الموقع من خرائط Google وستُملأ الإحداثيات تلقائياً."
        >
          <div className="relative">
            <Link2 className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />
            <Input value={mapLink} onChange={(e) => setMapLink(e.target.value)} placeholder="https://maps.app.goo.gl/... أو 33.3152, 44.3661" className="pr-9" dir="ltr" />
          </div>
        </Field>

        <div className="grid grid-cols-2 gap-3">
          <Field label="خط العرض (Latitude)">
            <Input type="number" step="any" required value={form.lat} onChange={(e) => setForm({ ...form, lat: Number(e.target.value) })} dir="ltr" className="text-left font-mono" />
          </Field>
          <Field label="خط الطول (Longitude)">
            <Input type="number" step="any" required value={form.lng} onChange={(e) => setForm({ ...form, lng: Number(e.target.value) })} dir="ltr" className="text-left font-mono" />
          </Field>
        </div>

        <Field label={`نطاق البصمة: ${form.radius} متر`}>
          <div className="flex items-center gap-3">
            <input
              type="range"
              min={20}
              max={1000}
              step={10}
              value={form.radius}
              onChange={(e) => setForm({ ...form, radius: Number(e.target.value) })}
              className="flex-1"
            />
            <Input type="number" min={1} required value={form.radius} onChange={(e) => setForm({ ...form, radius: Number(e.target.value) })} className="w-24 text-left font-mono" dir="ltr" />
          </div>
        </Field>

        <Field label="العنوان (اختياري)">
          <Textarea rows={2} value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} placeholder="مثال: بغداد، شارع المنصور، قرب مول المنصور" />
        </Field>

        <ModalFooter onCancel={onClose} loading={saving} submitLabel={isEdit ? 'حفظ التعديلات' : 'إضافة الفرع'} submitIcon={isEdit ? Save : Plus} />
      </form>
    </Modal>
  );
}
