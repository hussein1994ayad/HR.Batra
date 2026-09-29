'use client';

import { useCallback, useEffect, useState } from 'react';
import toast from 'react-hot-toast';
import { CalendarOff, Plus, Trash2 } from 'lucide-react';
import { useConfirm } from '@/components/confirm';
import { Button, Card, CardHeader, Field, IconButton, InfoNote, Input } from '@/components/ui';
import { supabase } from '@/lib/supabase';
import { errorMessage } from '@/lib/format';

type Holiday = { holiday_date: string; name: string };

/**
 * العطل الرسمية: لا يُحسب فيها غياب "بدون بصمة" ولا تُرسل تذكيرات البصمة.
 * (داخل نموذج الإعدادات: كل الأزرار type="button" حتى لا تحفظ النموذج كله.)
 */
export function HolidaysCard() {
  const confirm = useConfirm();
  const [items, setItems] = useState<Holiday[]>([]);
  const [date, setDate] = useState('');
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    const { data, error } = await supabase
      .from('official_holidays')
      .select('holiday_date, name')
      .gte('holiday_date', new Date(Date.now() - 60 * 86400000).toISOString().slice(0, 10))
      .order('holiday_date');
    if (error) {
      toast.error(`تعذر تحميل العطل: ${errorMessage(error)}`);
      return;
    }
    setItems(data ?? []);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- تحميل أولي
    void load();
  }, [load]);

  const add = async () => {
    if (!date || !name.trim()) {
      toast.error('اختر التاريخ واكتب اسم العطلة');
      return;
    }
    setBusy(true);
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase.from('official_holidays').insert({ holiday_date: date, name: name.trim(), created_by: user?.id });
    setBusy(false);
    if (error) {
      toast.error(error.code === '23505' ? 'هذا اليوم مسجّل عطلة مسبقاً' : `تعذر الإضافة: ${errorMessage(error)}`);
      return;
    }
    toast.success('أُضيفت العطلة: لا غياب ولا تذكير بصمة في هذا اليوم');
    setDate('');
    setName('');
    await load();
  };

  const remove = async (h: Holiday) => {
    const ok = await confirm({
      title: 'حذف العطلة؟',
      message: `${h.name} (${h.holiday_date}) — سيُعامل اليوم كيوم دوام عادي.`,
      confirmLabel: 'حذف',
      tone: 'danger',
    });
    if (!ok) return;
    const { error } = await supabase.from('official_holidays').delete().eq('holiday_date', h.holiday_date);
    if (error) {
      toast.error(`تعذر الحذف: ${errorMessage(error)}`);
      return;
    }
    await load();
  };

  return (
    <Card>
      <CardHeader icon={CalendarOff} tone="sky" title="العطل الرسمية" />
      <div className="grid grid-cols-1 sm:grid-cols-[1fr_1.3fr_auto] gap-2 items-end">
        <Field label="التاريخ">
          <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} dir="ltr" />
        </Field>
        <Field label="اسم العطلة">
          <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="مثال: عيد الأضحى" />
        </Field>
        <Button type="button" variant="soft" icon={Plus} loading={busy} onClick={() => void add()}>
          إضافة
        </Button>
      </div>
      {items.length > 0 ? (
        <ul className="mt-4 divide-y divide-slate-800/70 rounded-xl border border-slate-800/80">
          {items.map((h) => (
            <li key={h.holiday_date} className="flex items-center justify-between gap-2 px-3 py-2 text-sm">
              <span className="text-white font-bold">{h.name}</span>
              <span className="flex items-center gap-2">
                <span className="font-mono text-xs text-slate-400" dir="ltr">{h.holiday_date}</span>
                <IconButton icon={Trash2} label="حذف العطلة" tone="rose" onClick={() => void remove(h)} />
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-4 text-xs text-slate-500">لا توجد عطل رسمية مسجلة.</p>
      )}
      <InfoNote tone="slate" icon={CalendarOff} className="mt-4">
        يوم العطلة لا يُحسب فيه غياب لمن لم يبصم، ولا تصل فيه تذكيرات البصمة. من بصم فيه يُحسب حضوره عادياً.
      </InfoNote>
    </Card>
  );
}
