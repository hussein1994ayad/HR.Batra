'use client';

// تسجيل دفعة بأي مبلغ مع معاينة الأقساط بعدها (الزيادة من آخر الأقساط، والنقص لآخر قسط).

import { Banknote } from 'lucide-react';
import { formatIQD } from '@/lib/format';
import { AmountInput, Badge, Field, Input, Modal, ModalFooter, SegmentedTabs } from '@/components/ui';
import type { LoansState } from '../useLoans';

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
            <Field label="المبلغ المدفوع (د.ع)" hint="الزيادة تُخصم من آخر الأقساط، والنقص يُضاف لآخر قسط.">
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
          <Field label="ملاحظة (اختياري)">
            <Input value={payPrompt.note} onChange={(e) => setPayPrompt({ ...payPrompt, note: e.target.value })} placeholder="مثال: وصل استلام رقم 12" />
          </Field>

          {paymentPreview.error ? (
            <p className="text-xs font-bold text-rose-400">{paymentPreview.error}</p>
          ) : (
            <div>
              <div className="flex items-center justify-between mb-2">
                <h4 className="text-xs font-bold text-slate-300">الأقساط بعد هذه الدفعة</h4>
                <span className="text-xs text-slate-400">
                  المتبقي بعدها: <b className="text-amber-300">{formatIQD(paymentPreview.remaining)}</b>
                </span>
              </div>
              <div className="max-h-56 overflow-y-auto rounded-2xl border border-slate-800/80 divide-y divide-slate-800/70">
                {paymentPreview.rows.map((r, idx) => (
                  <div key={`${r.due_date}-${idx}`} className={`px-3 py-2 flex items-center justify-between text-xs ${r.current ? 'bg-emerald-500/10' : ''}`}>
                    <span className="flex items-center gap-2">
                      <span className="w-6 text-slate-500 font-bold">{idx + 1}</span>
                      <span className="font-mono text-slate-300" dir="ltr">{r.due_date}</span>
                    </span>
                    <span className="flex items-center gap-2">
                      <b className="text-white">{formatIQD(r.amount)}</b>
                      {r.current ? (
                        <Badge tone="emerald" dot>هذه الدفعة</Badge>
                      ) : r.is_paid ? (
                        <Badge tone="sky">مسدد</Badge>
                      ) : r.added ? (
                        <Badge tone="amber">شهر إضافي</Badge>
                      ) : (
                        <Badge tone="slate">قادم</Badge>
                      )}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}
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
