'use client';

// جدول أقساط سلفة: تسجيل دفعة، «هالشهر أقل»، تأجيل لآخر السلفة، تراجع عن سداد، حذف قسط مسدد، طباعة، وتعديل السلفة.
// كل قسط يبين ليش موجود: «باقي شهر 10/2026» أو «مؤجّل من 12/2026» أو «مبلغ هالشهر مخفّض».

import { Calendar, CalendarClock, Pencil, Undo2, Trash2, Banknote, Printer, TrendingDown } from 'lucide-react';
import { formatIQD } from '@/lib/format';
import { Badge, Button, IconButton, Modal, StatTile } from '@/components/ui';
import { installmentOrigin, monthLabel, sortInstallments } from '../logic';
import type { LoansState } from '../useLoans';

export function InstallmentScheduleModal({ s }: { s: LoansState }) {
  const { busy, setEditDraft, scheduleLoan, setScheduleLoanId, setPayPrompt, setMonthPrompt, revertPayment, deletePaidInstallment, postponeFrom } = s;
  if (!scheduleLoan) return null;
  const installments = sortInstallments(scheduleLoan.loan_installments);
  // الأشهر المؤجّلة تبين بمكانها الأصلي (سطر توضيحي، مو قسط)
  const postponed = installments.filter((i) => i.origin_kind === 'postponed' && i.origin_month);
  return (
    <Modal
      title="جدول الأقساط والسداد"
      subtitle={scheduleLoan.employees?.full_name ?? undefined}
      icon={Calendar}
      tone="sky"
      size="lg"
      onClose={() => setScheduleLoanId(null)}
    >
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
        <StatTile label="المبلغ الكلي" value={formatIQD(scheduleLoan.amount)} tone="slate" className="!p-3" />
        <StatTile label="المسدد" value={formatIQD(Number(scheduleLoan.amount) - Number(scheduleLoan.remaining_amount))} tone="emerald" className="!p-3" />
        <StatTile label="المتبقي" value={formatIQD(scheduleLoan.remaining_amount)} tone="amber" className="!p-3" />
        <StatTile label="القسط الشهري" value={formatIQD(scheduleLoan.installment_amount)} tone="indigo" className="!p-3" />
      </div>

      <div className="flex items-center justify-between mb-3">
        <h4 className="text-xs font-bold text-slate-300">الأقساط</h4>
        <div className="flex gap-2">
          <Button size="sm" variant="secondary" icon={Printer} onClick={() => window.print()}>
            طباعة كشف الحساب
          </Button>
          <Button
            size="sm"
            variant="secondary"
            icon={Pencil}
            onClick={() =>
              setEditDraft({
                loan: scheduleLoan,
                amount: Number(scheduleLoan.amount),
                installmentAmount: Number(scheduleLoan.installment_amount),
                installmentCount: Number(scheduleLoan.installment_count),
                remainingAmount: Number(scheduleLoan.remaining_amount),
              })
            }
          >
            تعديل السلفة وإعادة الجدولة
          </Button>
        </div>
      </div>

      <div className="max-h-[360px] overflow-y-auto rounded-2xl border border-slate-800/80 divide-y divide-slate-800/70">
        {installments.map((inst, idx) => {
          const origin = installmentOrigin(inst);
          const movedHere = postponed.filter((p) => p.origin_month! > (installments[idx - 1]?.due_date ?? '') && p.origin_month! <= inst.due_date && p.id !== inst.id);
          return (
            <div key={inst.id}>
              {movedHere.map((p) => (
                <div key={`moved-${p.id}`} className="px-3 py-2 text-[11px] text-slate-500 flex items-center gap-2">
                  <CalendarClock className="w-3.5 h-3.5" />
                  شهر {monthLabel(p.origin_month)} مؤجّل ← انتقل لشهر {monthLabel(p.due_date)}{p.payment_note ? ` · ${p.payment_note}` : ''}
                </div>
              ))}
              <div className="p-3 flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:bg-slate-900/40 transition-colors">
                <div className="flex flex-wrap items-center gap-3 text-xs">
                  <span className="w-7 h-7 shrink-0 rounded-lg bg-slate-800 text-slate-400 font-bold flex items-center justify-center text-[11px]">{idx + 1}</span>
                  <span className="font-mono text-slate-300" dir="ltr">{inst.due_date}</span>
                  <span className="font-bold text-white">{formatIQD(inst.amount)}</span>
                  {inst.is_paid ? (
                    <Badge tone={inst.payment_type === 'cash' ? 'emerald' : 'sky'} dot>
                      {inst.payment_type === 'cash' ? 'نقداً' : 'استقطاع راتب'}
                      {inst.paid_at ? ` · ${new Date(inst.paid_at).toLocaleDateString('en-GB')}` : ''}
                    </Badge>
                  ) : (
                    <Badge tone="slate">غير مدفوع</Badge>
                  )}
                  {origin && <Badge tone={inst.origin_kind === 'postponed' ? 'violet' : 'amber'}>{origin}</Badge>}
                  {inst.payment_note && <span className="text-[11px] text-slate-500">{inst.payment_note}</span>}
                </div>
                <div className="flex items-center gap-1.5 justify-end">
                  {!inst.is_paid ? (
                    <>
                      <Button
                        size="xs"
                        variant="soft-success"
                        icon={Banknote}
                        disabled={!!busy}
                        onClick={() => setPayPrompt({ installment: inst, amount: Number(inst.amount), method: 'cash', note: '' })}
                      >
                        تسجيل دفعة
                      </Button>
                      <IconButton
                        icon={TrendingDown}
                        label="هالشهر يكدر يدفع أقل (الباقي يصير شهر بالأخير)"
                        tone="amber"
                        disabled={!!busy}
                        onClick={() => setMonthPrompt({ installment: inst, amount: Math.round(Number(inst.amount) / 2), note: '' })}
                      />
                      <IconButton icon={CalendarClock} label="تأجيل هذا القسط لآخر السلفة" tone="indigo" loading={busy === `postpone_${inst.id}`} disabled={!!busy} onClick={() => postponeFrom(inst)} />
                    </>
                  ) : (
                    <>
                      <IconButton icon={Undo2} label="التراجع عن السداد" tone="amber" loading={busy === `revert_${inst.id}`} disabled={!!busy} onClick={() => revertPayment(inst)} />
                      <IconButton icon={Trash2} label="حذف القسط المسدد نهائياً" tone="rose" loading={busy === `delete_${inst.id}`} disabled={!!busy} onClick={() => deletePaidInstallment(inst)} />
                    </>
                  )}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </Modal>
  );
}
