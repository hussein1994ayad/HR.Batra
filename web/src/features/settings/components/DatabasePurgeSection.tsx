'use client';

import { useState } from 'react';
import toast from 'react-hot-toast';
import { Eraser, ShieldAlert, Trash2 } from 'lucide-react';
import { useConfirm } from '@/components/confirm';
import { Button, Card, CardHeader, Field, InfoNote, Select, Toggle } from '@/components/ui';
import { confetti } from '@/lib/lazy';
import { errorMessage } from '@/lib/format';
import { purgeMonthData } from '../api';
import { ARABIC_MONTH_NAMES, purgeSummary } from '../logic';

/** أداة حذف بيانات شهر قديم (بعد اعتماد رواتبه) لتوفير مساحة قاعدة البيانات. */
export function DatabasePurgeSection() {
  const confirm = useConfirm();
  const [month, setMonth] = useState(() => new Date().getMonth() + 1);
  const [year, setYear] = useState(() => new Date().getFullYear());
  const [notifications, setNotifications] = useState(false);
  const [tracking, setTracking] = useState(false);
  const [absences, setAbsences] = useState(false);
  const [purging, setPurging] = useState(false);
  const [years] = useState(() => {
    const last = new Date().getFullYear() + 1;
    return Array.from({ length: last - 2024 + 1 }, (_, i) => 2024 + i);
  });

  const run = async () => {
    if (!notifications && !tracking && !absences) {
      toast.error('يرجى تحديد فئة واحدة على الأقل لحذفها');
      return;
    }
    const categories = [
      notifications && 'الإشعارات',
      tracking && 'سجلات الحركة (GPS والوقفات والمخالفات)',
      absences && 'سجلات الحضور والغياب',
    ].filter(Boolean).join('، ');
    const ok = await confirm({
      title: `حذف بيانات ${ARABIC_MONTH_NAMES[month - 1]} ${year} نهائياً؟`,
      message: `سيتم حذف: ${categories}. لا يمكن التراجع، ولن تتم العملية إلا إذا كانت رواتب هذا الشهر معتمدة لكل الموظفين النشطين.`,
      confirmLabel: 'نعم، حذف نهائي',
      icon: Trash2,
    });
    if (!ok) return;

    setPurging(true);
    try {
      const options = { year, month, notifications, tracking, absences };
      const result = await purgeMonthData(options);
      toast.success(purgeSummary(options, result));
      confetti({ particleCount: 50, spread: 60, colors: ['#F59E0B', '#EF4444', '#10B981'] });
      setNotifications(false);
      setTracking(false);
      setAbsences(false);
    } catch (err) {
      toast.error(`فشل تنفيذ عملية التنظيف: ${errorMessage(err)}`);
    } finally {
      setPurging(false);
    }
  };

  return (
    <Card>
      <CardHeader
        icon={Eraser}
        tone="rose"
        title="تنظيف قاعدة البيانات"
        description="حذف يدوي للبيانات القديمة لشهر محدد لتوفير المساحة المجانية في Supabase"
      />
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-5">
          <div className="grid grid-cols-2 gap-3">
            <Field label="الشهر">
              <Select value={month} onChange={(e) => setMonth(Number(e.target.value))}>
                {ARABIC_MONTH_NAMES.map((name, i) => (
                  <option key={name} value={i + 1}>{i + 1} — {name}</option>
                ))}
              </Select>
            </Field>
            <Field label="السنة">
              <Select value={year} onChange={(e) => setYear(Number(e.target.value))}>
                {years.map((y) => <option key={y} value={y}>{y}</option>)}
              </Select>
            </Field>
          </div>
          <div className="space-y-3">
            <Toggle checked={notifications} onChange={setNotifications} label="حذف الإشعارات الموجهة للموظفين" />
            <Toggle checked={tracking} onChange={setTracking} label="حذف سجلات الحركة: إحداثيات GPS والوقفات ومخالفات السياج (تأخذ أكبر مساحة)" />
            <Toggle checked={absences} onChange={setAbsences} label="حذف سجلات الحضور والغياب لهذا الشهر" />
          </div>
          <Button variant="danger" icon={Trash2} loading={purging} onClick={run}>
            تصفية البيانات المحددة
          </Button>
        </div>
        <InfoNote tone="amber" icon={ShieldAlert}>
          <p className="font-bold text-amber-200 mb-1">قفل مالي</p>
          لا يمكن حذف بيانات أي شهر إلا بعد اعتماد ونشر رواتب جميع الموظفين النشطين لذلك الشهر، حتى تبقى
          الاستقطاعات والسلف والخصومات محفوظة داخل كشوف الرواتب. الحذف نهائي ولا يمكن التراجع عنه.
        </InfoNote>
      </div>
    </Card>
  );
}
