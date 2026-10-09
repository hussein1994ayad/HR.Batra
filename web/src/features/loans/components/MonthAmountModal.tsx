'use client';

// «هالشهر يكدر يدفع بس X»: القسط يبقى غير مسدد بمبلغ X (الرواتب تخصمه من راتب ذاك الشهر)،
// والباقي يصير شهر جديد بآخر السلفة مكتوب عليه «باقي شهر …». (set_month_installment)

import { TrendingDown } from 'lucide-react';
import { formatIQD } from '@/lib/format';
import { AmountInput, Field, Input, Modal, ModalFooter } from '@/components/ui';
import { monthLabel } from '../logic';
import type { LoansState } from '../useLoans';
import { SchedulePreview } from './SchedulePreview';

export function MonthAmountModal({ s }: { s: LoansState }) {
  const { busy, scheduleLoan, monthPrompt, setMonthPrompt, monthPreview, recordMonthAmount } = s;
  if (!monthPrompt || !scheduleLoan || !monthPreview) return null;
  const month = monthLabel(monthPrompt.installment.due_date);
  return (
    <Modal
      title={`قسط شهر ${month} أقل`}
      subtitle={`القسط المجدول: ${formatIQD(monthPrompt.installment.amount)} · الرواتب تخصم المبلغ الجديد، والباقي يصير شهر بالأخير`}
      icon={TrendingDown}
      tone="amber"
      onClose={() => setMonthPrompt(null)}
    >
      <form onSubmit={recordMonthAmount} className="space-y-4">
        <Field label={`المبلغ اللي يكدر يدفعه بشهر ${month} (د.ع)`} hint="إذا ما يكدر يدفع شي هالشهر، استعمل زر التأجيل.">
          <AmountInput required autoFocus value={monthPrompt.amount} onValueChange={(v) => setMonthPrompt({ ...monthPrompt, amount: v })} />
        </Field>
        <Field label="ملاحظة (اختياري)">
          <Input value={monthPrompt.note} onChange={(e) => setMonthPrompt({ ...monthPrompt, note: e.target.value })} placeholder="مثال: الموظف كال ما يكدر هالشهر" />
        </Field>
        <SchedulePreview preview={monthPreview} title="الأقساط بعد التعديل" currentLabel="هالشهر" />
        <ModalFooter
          onCancel={() => setMonthPrompt(null)}
          loading={busy === 'month'}
          disabled={!!monthPreview.error}
          submitLabel="حفظ"
        />
      </form>
    </Modal>
  );
}
