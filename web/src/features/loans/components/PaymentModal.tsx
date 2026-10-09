'use client';

// تسجيل دفعة بأي مبلغ مع معاينة الأقساط بعدها (الزيادة من آخر الأقساط، والنقص شهر جديد بالأخير).

import { Banknote } from 'lucide-react';
import { formatIQD } from '@/lib/format';
import { AmountInput, Field, Input, Modal, ModalFooter, SegmentedTabs } from '@/components/ui';
import type { LoansState } from '../useLoans';
import { SchedulePreview } from './SchedulePreview';

export function PaymentModal({ s }: { s: LoansState }) {
  const { busy, scheduleLoan, payPrompt, setPayPrompt, paymentPreview, recordPayment } = s;
  return (
    <>
    {payPrompt && scheduleLoan && paymentPreview && (
      <Modal
        title="تسجيل دفعة"
        subtitle={`القسط المجدول: ${formatIQD(payPrompt.installment.amount)} · المتبقي على السلفة: ${formatIQD(scheduleLoan.remaining_amount)}`}
        icon={Banknote}
        tone="emerald"
        onClose={() => setPayPrompt(null)}
      >
        <form onSubmit={recordPayment} className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <Field label="المبلغ المدفوع (د.ع)" hint="الزيادة تُخصم من آخر الأقساط، والنقص يصير شهر جديد بآخر السلفة.">
              <AmountInput required autoFocus value={payPrompt.amount} onValueChange={(v) => setPayPrompt({ ...payPrompt, amount: v })} />
            </Field>
            <Field label="طريقة السداد">
              <SegmentedTabs
                value={payPrompt.method}
                onChange={(method) => setPayPrompt({ ...payPrompt, method })}
                options={[
                  { value: 'cash', label: 'نقداً' },
                  { value: 'salary_deduction', label: 'استقطاع راتب' },
                ]}
              />
            </Field>
          </div>
          {payPrompt.method === 'salary_deduction' && (
            <p className="text-[11px] text-amber-300">
              «تسجيل دفعة» يعني المبلغ انستلم فعلاً. إذا الموظف هالشهر يكدر يدفع أقل من راتبه، استعمل «هالشهر أقل» حتى الرواتب تخصمه.
            </p>
          )}
          <Field label="ملاحظة (اختياري)">
            <Input value={payPrompt.note} onChange={(e) => setPayPrompt({ ...payPrompt, note: e.target.value })} placeholder="مثال: وصل استلام رقم 12" />
          </Field>

          <SchedulePreview preview={paymentPreview} title="الأقساط بعد هذه الدفعة" currentLabel="هذه الدفعة" />
          <ModalFooter
            onCancel={() => setPayPrompt(null)}
            loading={busy === 'pay'}
            disabled={!!paymentPreview.error}
            submitLabel="تأكيد الدفعة"
            variant="success"
          />
        </form>
      </Modal>
    )}
    </>
  );
}
