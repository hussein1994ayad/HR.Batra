'use client';

// معاينة جدول الأقساط بعد دفعة أو تعديل مبلغ شهر (نفس قواعد السيرفر من logic.ts).

import { formatIQD } from '@/lib/format';
import { Badge } from '@/components/ui';
import type { PaymentPreview } from '../logic';
import { payrollMonthName, payrollMonthOfDate } from '@/features/payroll/period';

export function SchedulePreview({ preview, title, currentLabel }: { preview: PaymentPreview; title: string; currentLabel: string }) {
  if (preview.error) return <p className="text-xs font-bold text-rose-400">{preview.error}</p>;
  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <h4 className="text-xs font-bold text-slate-300">{title}</h4>
        <span className="text-xs text-slate-400">
          المتبقي بعدها: <b className="text-amber-300">{formatIQD(preview.remaining)}</b>
        </span>
      </div>
      <div className="max-h-56 overflow-y-auto rounded-2xl border border-slate-800/80 divide-y divide-slate-800/70">
        {preview.rows.map((r, idx) => (
          <div key={`${r.due_date}-${idx}`} className={`px-3 py-2 flex items-center justify-between gap-2 text-xs ${r.current ? 'bg-emerald-500/10' : ''}`}>
            <span className="flex items-center gap-2">
              <span className="w-6 text-slate-500 font-bold">{idx + 1}</span>
              <span className="text-slate-300">رواتب {payrollMonthName(payrollMonthOfDate(r.due_date))}</span>
            </span>
            <span className="flex flex-wrap items-center justify-end gap-2">
              <b className="text-white">{formatIQD(r.amount)}</b>
              {r.current ? (
                <Badge tone="emerald" dot>{currentLabel}</Badge>
              ) : r.is_paid ? (
                <Badge tone="sky">مسدد</Badge>
              ) : r.added ? (
                <Badge tone="amber">{r.label ?? 'شهر إضافي'}</Badge>
              ) : r.label ? (
                <Badge tone="violet">{r.label}</Badge>
              ) : (
                <Badge tone="slate">قادم</Badge>
              )}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
