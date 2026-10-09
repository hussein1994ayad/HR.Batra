'use client';

// تعديل سلفة جارية: القسط الشهري هو الأساس. الأقساط غير المدفوعة تنكتب بالقسط الشهري بالضبط وآخرها الباقي،
// وعدد الأقساط ينحسب وحده (المسدَّد لا يتغير). السيرفر يبدي من شهر الرواتب المفتوح إذا كشفه ما صادر.

import { Save, Pencil } from 'lucide-react';
import { formatIQD } from '@/lib/format';
import { AmountInput, Field, Modal, ModalFooter } from '@/components/ui';
import { reschedulePlan } from '../logic';
import type { LoansState } from '../useLoans';

export function EditLoanModal({ s }: { s: LoansState }) {
  const { busy, editDraft, setEditDraft, submitEdit } = s;
  if (!editDraft) return null;
  const paid = Number(editDraft.loan.amount) - Number(editDraft.loan.remaining_amount);
  const plan = reschedulePlan(editDraft.amount, paid, editDraft.installmentAmount);
  return (
    <Modal
      title="تعديل السلفة وإعادة الجدولة"
      subtitle="الأقساط الباقية تنكتب بالقسط الشهري بالضبط وآخرها الباقي، من شهر الرواتب الحالي (المسدَّد لا يتغير)"
      icon={Pencil}
      tone="sky"
      onClose={() => setEditDraft(null)}
    >
      <form onSubmit={submitEdit} className="grid grid-cols-2 gap-4">
        <Field label="المبلغ الإجمالي (د.ع)">
          <AmountInput required value={editDraft.amount} onValueChange={(v) => setEditDraft({ ...editDraft, amount: v })} />
        </Field>
        <Field label="القسط الشهري (د.ع)">
          <AmountInput required value={editDraft.installmentAmount} onValueChange={(v) => setEditDraft({ ...editDraft, installmentAmount: v })} />
        </Field>
        <Field label="المبلغ المتبقي (يُحسب تلقائياً)" hint="المبلغ الإجمالي − ما سُدِّد">
          <div className="h-10 flex items-center px-3 rounded-xl bg-slate-950/60 border border-slate-800 font-mono font-bold text-slate-200" dir="ltr">
            {formatIQD(plan.remaining)}
          </div>
        </Field>
        <Field label="الأقساط الباقية (تُحسب تلقائياً)">
          <div className="h-10 flex items-center px-3 rounded-xl bg-slate-950/60 border border-slate-800 text-xs font-bold text-slate-200">
            {plan.count === 0
              ? 'السلفة مسددة بالكامل'
              : plan.count === 1
                ? `قسط واحد ${formatIQD(plan.last)}`
                : plan.last === Math.round(editDraft.installmentAmount)
                  ? `${plan.count} × ${formatIQD(plan.last)}`
                  : `${plan.count - 1} × ${formatIQD(Math.round(editDraft.installmentAmount))} + آخر قسط ${formatIQD(plan.last)}`}
          </div>
        </Field>
        <div className="col-span-2">
          <ModalFooter onCancel={() => setEditDraft(null)} loading={busy === 'edit'} submitLabel="حفظ وإعادة الجدولة" submitIcon={Save} />
        </div>
      </form>
    </Modal>
  );
}
