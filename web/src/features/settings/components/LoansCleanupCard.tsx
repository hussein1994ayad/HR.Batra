'use client';

import { useState } from 'react';
import toast from 'react-hot-toast';
import { Archive, CreditCard, ShieldAlert } from 'lucide-react';
import { useConfirm } from '@/components/confirm';
import { Button, Card, CardHeader, InfoNote, Toggle } from '@/components/ui';
import { errorMessage, formatIQD } from '@/lib/format';
import { loanRef } from '@/features/loans/logic';
import { runLoansCleanup } from '../api';
import { formatBytes, loansCleanupBytes } from '../logic';
import type { LoansCleanupPreview } from '../types';

/**
 * تنظيف السلف: السلفة المسددة بالكامل تتأرشف (سجل مالي دائم مختصر ثم ينحذف سجلها وصورة تعهدها)، والطلبات
 * المرفوضة/الملغاة الأقدم من 30 يوم تنحذف. السلف اللي عليها باقي أو قسطها براتب مسير مفتوح مستثناة مع السبب.
 */
export function LoansCleanupCard({ preview, onDone }: { preview: LoansCleanupPreview; onDone: () => void }) {
  const confirm = useConfirm();
  const [settled, setSettled] = useState(false);
  const [requests, setRequests] = useState(false);
  const [busy, setBusy] = useState(false);

  const run = async () => {
    const lines = [
      settled && `• أرشفة ${preview.settled.length} سلفة مسددة (ينحفظ سجلها المالي، وينحذف سجلها التشغيلي وصورة التعهد)`,
      requests && `• حذف ${preview.requests.length} طلب سلفة مرفوض/ملغى ويا صورته`,
    ].filter(Boolean).join('\n');
    const ok = await confirm({
      title: 'تنظيف السلف؟',
      message: `${lines}\n\nكشوف الرواتب ما تتغير: مبلغ كل قسط محفوظ بكشف راتبه. الحذف نهائي.`,
      confirmLabel: 'نعم، نفّذ',
      icon: Archive,
      tone: 'warning',
    });
    if (!ok) return;
    setBusy(true);
    try {
      const r = await runLoansCleanup(settled, requests);
      const parts = [
        r.loans_archived != null && `${r.loans_archived} سلفة تأرشفت`,
        r.loan_requests_deleted != null && `${r.loan_requests_deleted} طلب انحذف`,
      ].filter(Boolean).join('، ');
      toast.success(`تم 🧹 ${parts}`);
      setSettled(false);
      setRequests(false);
      onDone();
    } catch (err) {
      toast.error(`ما تم تنظيف السلف: ${errorMessage(err)}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card>
      <CardHeader
        icon={CreditCard}
        tone="amber"
        title="تنظيف السلف"
        description="السلفة المسددة بالكامل تتأرشف بسجل مالي دائم ثم ينحذف سجلها. المؤرشفة تلكاها بصفحة السلف ← «المؤرشفة»."
      />
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-4">
          <Toggle checked={settled} onChange={setSettled} disabled={preview.settled.length === 0}
            label={`أرشفة السلف المسددة بالكامل — ${preview.settled.length} سلفة`} />
          {preview.settled.length > 0 && (
            <ul className="text-[11px] text-slate-400 space-y-1 pr-4 list-disc">
              {preview.settled.slice(0, 20).map((l) => (
                <li key={l.id}><span className="font-mono" dir="ltr">{loanRef(l.loan_no)}</span> · {l.employee} · {formatIQD(l.amount)}</li>
              ))}
            </ul>
          )}

          <Toggle checked={requests} onChange={setRequests} disabled={preview.requests.length === 0}
            label={`حذف طلبات السلف المرفوضة/الملغاة الأقدم من 30 يوم — ${preview.requests.length} طلب`} />
          {preview.requests_recent > 0 && (
            <p className="text-[11px] text-slate-500 pr-4">{preview.requests_recent} طلب مرفوض/ملغى أحدث من 30 يوم يبقى (الموظف بعده يشوف سبب الرفض).</p>
          )}

          {preview.excluded.length > 0 && (
            <div className="rounded-2xl border border-slate-800 p-3">
              <p className="text-[11px] font-bold text-slate-300 mb-2">مستثناة (ما تنلمس) — {preview.excluded.length} سلفة</p>
              <ul className="space-y-1 text-[11px] text-slate-400">
                {preview.excluded.slice(0, 30).map((l) => (
                  <li key={l.loan_no}>
                    <span className="font-mono" dir="ltr">{loanRef(l.loan_no)}</span> · {l.employee} · <span className="text-amber-300/90">{l.reason}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          <div className="flex flex-wrap items-center gap-3">
            <Button variant="warning" icon={Archive} loading={busy} onClick={run} disabled={!settled && !requests}>
              تنظيف السلف المحددة
            </Button>
            {(settled || requests) && (
              <span className="text-[11px] text-slate-400">المساحة التقريبية: {formatBytes(loansCleanupBytes(preview, settled, requests))}</span>
            )}
          </div>
        </div>
        <InfoNote tone="amber" icon={ShieldAlert}>
          <p className="font-bold text-amber-200 mb-1">شنو يبقى من السلفة</p>
          رقمها المرجعي، الموظف، المبلغ الأصلي، كل استقطاع (تاريخه ومبلغه ورواتب يا شهر)، تاريخ التسوية، والرصيد صفر.
          ما تتأرشف سلفة عليها باقي، ولا سلفة قسطها مخصوم براتب مسير بعده مفتوح. عدد المؤرشفة لهسه: {preview.archived_total}.
        </InfoNote>
      </div>
    </Card>
  );
}
