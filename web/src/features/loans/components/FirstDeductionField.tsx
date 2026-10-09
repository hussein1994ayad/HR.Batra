'use client';

// «أول شهر يستقطع من الراتب»: اختيار شهر رواتب بدل تاريخ حر. التاريخ ينحط يوم القطع (26) بداخل ذاك الشهر،
// فالقسط الأول ينخصم بنفس الشهر المختار (قبل: تاريخ مثل 28/10 كان ينخصم برواتب شهر 11 بدون ما ينتبه أحد).

import { Field, Select } from '@/components/ui';
import { arabicDate, currentPayrollMonth, cutoffDateOf, payrollMonthName, payrollMonthOfDate, shiftPayrollMonth } from '@/features/payroll/period';

export function FirstDeductionField({ value, onChange }: { value: string; onChange: (date: string) => void }) {
  const current = currentPayrollMonth();
  const selected = value ? payrollMonthOfDate(value) : current;
  const months = Array.from({ length: 12 }, (_, i) => shiftPayrollMonth(current, i));
  if (!months.includes(selected)) months.unshift(selected);
  return (
    <Field label="أول شهر يستقطع من الراتب" hint={value ? `القسط الأول بتاريخ ${arabicDate(value, true)}، وينخصم برواتب ${payrollMonthName(selected)}.` : undefined}>
      <Select value={selected} onChange={(e) => onChange(cutoffDateOf(e.target.value))}>
        {months.map((m) => <option key={m} value={m}>رواتب {payrollMonthName(m)}</option>)}
      </Select>
    </Field>
  );
}
