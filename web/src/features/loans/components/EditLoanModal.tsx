'use client';

// تعديل سلفة جارية: الأقساط غير المدفوعة يُعاد توزيعها بالتساوي (المسدَّد لا يتغير).

import { Save, Pencil } from 'lucide-react';
import { formatIQD } from '@/lib/format';
import { AmountInput, Field, Modal, ModalFooter } from '@/components/ui';
import type { LoansState } from '../useLoans';

export function EditLoanModal({ s }: { s: LoansState }) {
  const { busy, editDraft, setEditDraft, submitEdit } = s;
  return (
    <>
    {editDraft && (
      <Modal title="تعديل السلفة وإعادة الجدولة" subtitle="الأقساط غير المدفوعة يُعاد توزيعها بالتساوي ابتداءً من الشهر القادم (المسدَّد لا يتغير)" icon={Pencil} tone="sky" onClose={() => setEditDraft(null)}>
        <form onSubmit={submitEdit} className="grid grid-cols-2 gap-4">
          <Field label="المبلغ الإجمالي (د.ع)">
            <AmountInput required value={editDraft.amount} onValueChange={(v) => setEditDraft({ ...editDraft, amount: v })} />
          </Field>
          <Field label="القسط الشهري (د.ع)">
            <AmountInput required value={editDraft.installmentAmount} onValueChange={(v) => setEditDraft({ ...editDraft, installmentAmount: v })} />
          </Field>
          <Field label="عدد الأقساط الكلي">
            <AmountInput required value={editDraft.installmentCount} onValueChange={(v) => setEditDraft({ ...editDraft, installmentCount: v })} />
          </Field>
          <Field label="المبلغ المتبقي (يُحسب تلقائياً)" hint="المبلغ الإجمالي − ما سُدِّد">
            <div className="h-10 flex items-center px-3 rounded-xl bg-slate-950/60 border border-slate-800 font-mono font-bold text-slate-200" dir="ltr">
              {formatIQD(Math.max(editDraft.amount - (Number(editDraft.loan.amount) - Number(editDraft.loan.remaining_amount)), 0))}
            </div>
          </Field>
          <div className="col-span-2">
            <ModalFooter onCancel={() => setEditDraft(null)} loading={busy === 'edit'} submitLabel="حفظ وإعادة الجدولة" submitIcon={Save} />
          </div>
        </form>
      </Modal>
    )}
    </>
  );
}
