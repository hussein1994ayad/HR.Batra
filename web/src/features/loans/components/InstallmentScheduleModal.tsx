'use client';

// جدول أقساط سلفة: تسجيل دفعة، تأجيل، تراجع عن سداد، حذف قسط مسدد، طباعة، وتعديل السلفة.

import { Calendar, CalendarClock, Pencil, Undo2, Trash2, Banknote, Printer } from 'lucide-react';
import { formatIQD } from '@/lib/format';
import { Badge, Button, IconButton, Modal, StatTile } from '@/components/ui';
import { sortInstallments } from '../logic';
import type { LoansState } from '../useLoans';

export function InstallmentScheduleModal({ s }: { s: LoansState }) {
  const { busy, setEditDraft, scheduleLoan, setScheduleLoanId, setPayPrompt, revertPayment, deletePaidInstallment, postponeFrom } = s;
  return (
    <>
    {scheduleLoan && (
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
          {sortInstallments(scheduleLoan.loan_installments).map((inst, idx) => (
            <div key={inst.id} className="p-3 flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:bg-slate-900/40 transition-colors">
              <div className="flex items-center gap-3 text-xs">
                <span className="w-7 h-7 shrink-0 rounded-lg bg-slate-800 text-slate-400 font-bold flex items-center justify-center text-[11px]">{idx + 1}</span>
                <span className="font-mono text-slate-300" dir="ltr">{inst.due_date}</span>
                <span className="font-bold text-white">{formatIQD(inst.amount)}</span>
                {inst.is_paid ? (
                  <Badge tone={inst.payment_type === 'cash' ? 'emerald' : 'sky'} dot>
                    {inst.payment_type === 'cash' ? `نقداً${inst.payment_note ? ` · ${inst.payment_note}` : ''}` : 'استقطاع راتب'}
                  </Badge>
                ) : (
                  <Badge tone="slate">غير مدفوع</Badge>
                )}
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
                    <IconButton icon={CalendarClock} label="تأجيل هذا القسط وما بعده شهراً" tone="indigo" loading={busy === `postpone_${inst.id}`} disabled={!!busy} onClick={() => postponeFrom(inst)} />
                  </>
                ) : (
                  <>
                    <IconButton icon={Undo2} label="التراجع عن السداد" tone="amber" loading={busy === `revert_${inst.id}`} disabled={!!busy} onClick={() => revertPayment(inst)} />
                    <IconButton icon={Trash2} label="حذف القسط المسدد نهائياً" tone="rose" loading={busy === `delete_${inst.id}`} disabled={!!busy} onClick={() => deletePaidInstallment(inst)} />
                  </>
                )}
              </div>
            </div>
          ))}
        </div>
      </Modal>
    )}
    </>
  );
}
