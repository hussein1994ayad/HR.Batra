'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import { CheckCircle2, Eraser, FileSpreadsheet, History, ShieldAlert, Trash2, XCircle } from 'lucide-react';
import { useConfirm } from '@/components/confirm';
import { Button, Card, CardHeader, Field, InfoNote, Select, Toggle } from '@/components/ui';
import { errorMessage, formatDate } from '@/lib/format';
import { FIRST_ENGINE_MONTH, arabicDate, currentPayrollMonth, payrollMonthName, shiftPayrollMonth } from '@/features/payroll/period';
import { useFirstPayrollMonth } from '@/features/payroll/useFirstPayrollMonth';
import { fetchCleanupPreview, fetchLoansCleanupPreview, runPayrollCleanup } from '../api';
import { downloadCleanupReport } from '../cleanupReport';
import { attendanceBlockers, cleanupSummary, formatBytes } from '../logic';
import type { CleanupPreview, CleanupSelection, LoansCleanupPreview } from '../types';
import { LoansCleanupCard } from './LoansCleanupCard';

const NONE: CleanupSelection = { attendance: false, tracking: false, notifications: false };
const n = (v: number | null | undefined) => Number(v ?? 0).toLocaleString('en-US');

/**
 * تنظيف مسير مغلق لتوفير مساحة القاعدة: تختار المسير، تشوف الشروط وعدد السجلات قبل الحذف، تأكد، والسيرفر ينفذ
 * بمعاملة وحدة ويسجّل منو ومتى وكم سطر. كشوف الرواتب وتفاصيلها ما تنلمس، والحضور ما ينحذف إلا بعد ما تتسلم
 * رواتب المسير اللي بعده.
 */
export function PayrollCleanupSection() {
  const confirm = useConfirm();
  // المسيرات من قبل الحالي ورجوع (الحالي مفتوح فما ينظف)
  const firstMonth = useFirstPayrollMonth() ?? FIRST_ENGINE_MONTH;
  const months = useMemo(() => {
    const out: string[] = [];
    for (let m = shiftPayrollMonth(currentPayrollMonth(), -1); m >= firstMonth && out.length < 24; m = shiftPayrollMonth(m, -1)) out.push(m);
    return out;
  }, [firstMonth]);
  // المسير المختار؛ لحد ما يختار الأدمن = أول مسير بالقائمة (القائمة تكمل بعد ما يوصل أول مسير من القاعدة)
  const [picked, setMonth] = useState('');
  const month = months.includes(picked) ? picked : (months[0] ?? '');
  const [preview, setPreview] = useState<CleanupPreview | null>(null);
  const [loadError, setLoadError] = useState('');
  const [pick, setPick] = useState<CleanupSelection>(NONE);
  const [busy, setBusy] = useState(false);
  const [loans, setLoans] = useState<LoansCleanupPreview | null>(null);

  const loadLoans = useCallback(async () => {
    try {
      setLoans(await fetchLoansCleanupPreview());
    } catch {
      setLoans(null); // سيرفر قديم بدون الدالة: القسم ما يطلع
    }
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- جلب معاينة السلف مرة عند فتح القسم
    void loadLoans();
  }, [loadLoans]);

  const load = useCallback(async (m: string) => {
    if (!m) return;
    setLoadError('');
    try {
      setPreview(await fetchCleanupPreview(m));
    } catch (err) {
      setPreview(null);
      setLoadError(errorMessage(err));
    }
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- جلب المعاينة عند تغيّر المسير
    void load(month);
  }, [month, load]);

  const blockers = preview ? attendanceBlockers(preview) : [];
  const trackingTotal = preview ? preview.counts.tracking + preview.counts.stops + preview.counts.violations : 0;
  // تقدير المساحة للفئات المختارة (حجم السطور بدون الفهارس — تقريبي)
  const pickedBytes = preview
    ? (pick.attendance ? Number(preview.bytes?.attendance ?? 0) : 0) + (pick.tracking ? Number(preview.bytes?.tracking ?? 0) : 0)
      + (pick.notifications ? Number(preview.bytes?.notifications ?? 0) : 0)
    : 0;

  const run = async () => {
    if (!preview) return;
    if (!pick.attendance && !pick.tracking && !pick.notifications) {
      toast.error('اختار فئة وحدة على الأقل');
      return;
    }
    const lines = [
      pick.attendance && `• ${n(preview.counts.attendance)} سجل حضور وبصمة`,
      pick.tracking && `• ${n(trackingTotal)} سجل تتبع (نقاط GPS ووقفات ومخالفات)`,
      pick.notifications && `• ${n(preview.counts.notifications)} إشعار`,
    ].filter(Boolean).join('\n');
    const ok = await confirm({
      title: `تنظيف رواتب ${payrollMonthName(month)} نهائياً؟`,
      message: `راح ينحذف من القاعدة:\n${lines}\n\nكشوف الرواتب وتفاصيلها تبقى مثل ما هي. الحذف نهائي وما يتراجع.`,
      confirmLabel: 'نعم، حذف نهائي',
      icon: Trash2,
    });
    if (!ok) return;
    setBusy(true);
    try {
      toast.success(cleanupSummary(await runPayrollCleanup(month, pick)));
      setPick(NONE);
      await load(month);
    } catch (err) {
      toast.error(`ما تم التنظيف: ${errorMessage(err)}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-6">
    <Card>
      <CardHeader
        icon={Eraser}
        tone="rose"
        title="تنظيف مسير مغلق"
        description="حذف سجلات الحضور والتتبع والإشعارات لمسير رواتب خلص وتسلّم، لتوفير مساحة القاعدة. كشوف الرواتب ما تنلمس."
        actions={
          <Button size="sm" variant="soft" icon={FileSpreadsheet} disabled={!preview && !loans} onClick={() => downloadCleanupReport(preview, loans).catch(() => toast.error('ما نزل تقرير المعاينة'))}>
            تقرير المعاينة Excel
          </Button>
        }
      />
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-5">
          <Field label="المسير" hint={preview ? `من ${arabicDate(preview.start_date, true)} إلى ${arabicDate(preview.end_date, true)}` : undefined}>
            <Select value={month} onChange={(e) => { setMonth(e.target.value); setPick(NONE); }} aria-label="المسير">
              {months.length === 0 && <option value="">ماكو مسير سابق بعد</option>}
              {months.map((m) => <option key={m} value={m}>رواتب {payrollMonthName(m)}</option>)}
            </Select>
          </Field>

          {loadError && <InfoNote tone="rose" icon={XCircle}>{loadError}</InfoNote>}

          {preview && (
            <>
              <ul className="space-y-1.5 text-xs">
                <Check ok={preview.checks.closed} text={preview.checks.closed ? 'المسير معتمد ومغلق' : 'المسير بعده مفتوح (ما ينظف منه شي)'} />
                <Check ok={preview.checks.next_closed}
                  text={preview.checks.next_closed
                    ? `رواتب المسير اللي بعده${preview.next_month ? ` (${payrollMonthName(preview.next_month)})` : ''} معتمدة ومغلقة`
                    : `رواتب المسير اللي بعده${preview.next_month ? ` (${payrollMonthName(preview.next_month)})` : ''} بعدها ما انغلقت — الحضور ينتظرها`} />
                <Check ok={preview.checks.next_delivered}
                  text={preview.checks.next_delivered
                    ? 'تأكد تسليم رواتب المسير اللي بعده'
                    : 'تسليم رواتب المسير اللي بعده ما تأكد بعد (من صفحة الرواتب ← «تم تسليم الرواتب»)'} />
                <Check ok={preview.checks.pending_decisions === 0}
                  text={preview.checks.pending_decisions === 0 ? 'ماكو حركات تنتظر قرار لأيام هذا المسير' : `${preview.checks.pending_decisions} حركة لأيام هذا المسير تنتظر قرارك`} />
              </ul>

              <div className="space-y-3">
                <Toggle
                  checked={pick.attendance}
                  onChange={(v) => setPick((p) => ({ ...p, attendance: v }))}
                  disabled={!preview.can.attendance}
                  label={`سجلات الحضور والبصمات — ${n(preview.counts.attendance)} سجل${preview.done.attendance ? ' (منظّف)' : ''}`}
                />
                {!preview.can.attendance && blockers.length > 0 && (
                  <ul className="text-[11px] text-amber-300/90 space-y-1 pr-4 list-disc">
                    {blockers.map((b) => <li key={b}>{b}</li>)}
                  </ul>
                )}
                {(preview.pending_list?.length ?? 0) > 0 && (
                  <div className="rounded-2xl border border-slate-800 p-3">
                    <p className="text-[11px] font-bold text-slate-300 mb-2">مستثنى: حركات تنتظر قرارك ({preview.pending_list.length})</p>
                    <ul className="space-y-1 text-[11px] text-slate-400 max-h-40 overflow-y-auto">
                      {preview.pending_list.map((e, i) => (
                        <li key={`${e.employee}_${e.date}_${i}`}>{e.employee} · <span dir="ltr" className="font-mono">{e.date}</span> · {e.type}</li>
                      ))}
                    </ul>
                  </div>
                )}
                <Toggle
                  checked={pick.tracking}
                  onChange={(v) => setPick((p) => ({ ...p, tracking: v }))}
                  disabled={!preview.can.tracking}
                  label={`سجلات التتبع: نقاط GPS والوقفات والمخالفات — ${n(trackingTotal)} سجل (أكبر مساحة)`}
                />
                <Toggle
                  checked={pick.notifications}
                  onChange={(v) => setPick((p) => ({ ...p, notifications: v }))}
                  disabled={!preview.can.notifications}
                  label={`الإشعارات بتاريخ هذا المسير — ${n(preview.counts.notifications)} إشعار`}
                />
              </div>

              <div className="flex flex-wrap items-center gap-3">
                <Button variant="danger" icon={Trash2} loading={busy} onClick={run}
                  disabled={!preview.checks.closed || (!pick.attendance && !pick.tracking && !pick.notifications)}>
                  تنظيف المحدد
                </Button>
                {pickedBytes > 0 && <span className="text-[11px] text-slate-400">المساحة التقريبية: {formatBytes(pickedBytes)}</span>}
              </div>

              {preview.history.length > 0 && (
                <div className="rounded-2xl border border-slate-800 p-3">
                  <p className="text-[11px] font-bold text-slate-300 mb-2 flex items-center gap-1.5"><History className="w-3.5 h-3.5" /> سجل تنظيف هذا المسير</p>
                  <ul className="space-y-1 text-[11px] text-slate-400">
                    {preview.history.map((h) => (
                      <li key={h.at}>
                        {formatDate(h.at)} · {h.by ?? 'النظام'} ·{' '}
                        {[
                          h.attendance != null && `${n(h.attendance)} حضور`,
                          h.tracking != null && `${n((h.tracking ?? 0) + (h.stops ?? 0) + (h.violations ?? 0))} تتبع`,
                          h.notifications != null && `${n(h.notifications)} إشعار`,
                        ].filter(Boolean).join('، ')}
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </>
          )}
        </div>
        <InfoNote tone="amber" icon={ShieldAlert}>
          <p className="font-bold text-amber-200 mb-1">شنو ينحذف وشنو يبقى</p>
          ينحذف: سطور الحضور والبصمات، نقاط التتبع، والإشعارات لهذا المسير بس. يبقى: كشوف الرواتب وتفاصيلها (الخصومات
          والسلف والصافي) وكل شي يخص المسيرات الثانية. الحضور ما ينحذف إلا بعد ما تنغلق رواتب المسير اللي بعده ويتأكد تسليمها، وأيامه
          بعدها ما ينعاد حسابها. الحذف نهائي.
        </InfoNote>
      </div>
    </Card>
    {loans && <LoansCleanupCard preview={loans} onDone={() => void loadLoans()} />}
    </div>
  );
}

function Check({ ok, text }: { ok: boolean; text: string }) {
  const Icon = ok ? CheckCircle2 : XCircle;
  return (
    <li className={`flex items-center gap-2 ${ok ? 'text-emerald-300' : 'text-amber-300'}`}>
      <Icon className="w-3.5 h-3.5 shrink-0" /> {text}
    </li>
  );
}
