'use client';

// نافذة اعتماد طلب سلفة: تعديل المبلغ والمدة وتاريخ أول قسط قبل توليد الأقساط.

import { Settings2, Save } from 'lucide-react';
import { formatIQD } from '@/lib/format';
import { AmountInput, Field, Modal, ModalFooter } from '@/components/ui';
import type { LoansState } from '../useLoans';
import { FirstDeductionField } from './FirstDeductionField';

export function ApprovalModal({ s }: { s: LoansState }) {
  const { busy, approval, setApproval, submitApproval } = s;
  return (
    <>
    {approval && (
      <Modal title="اعتماد وجدولة السلفة" subtitle={approval.loan.employees?.full_name ?? undefined} icon={Settings2} tone="brand" onClose={() => setApproval(null)}>
        <form onSubmit={submitApproval} className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <Field label="المبلغ الإجمالي (د.ع)">
              <AmountInput required value={approval.amount} onValueChange={(v) => setApproval({ ...approval, amount: v })} />
            </Field>
            <Field label="عدد أشهر التقسيط">
              <AmountInput required value={approval.months} onValueChange={(v) => setApproval({ ...approval, months: v })} />
            </Field>
          </div>
          <FirstDeductionField value={approval.startDate} onChange={(startDate) => setApproval({ ...approval, startDate })} />
          <div className="rounded-2xl bg-indigo-500/5 border border-indigo-500/20 p-4 text-center">
            <p className="text-[11px] text-slate-400 mb-1">القسط الشهري</p>
            <p className="text-2xl font-extrabold text-indigo-200">{formatIQD(approval.months > 0 ? approval.amount / approval.months : 0)}</p>
          </div>
          <ModalFooter onCancel={() => setApproval(null)} loading={busy === 'approve'} submitLabel="حفظ وتوليد الأقساط" submitIcon={Save} />
        </form>
      </Modal>
    )}
    </>
  );
}
