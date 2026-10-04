'use client';

// "سلفة لموظف": سلفة معتمدة مباشرة من الأدمن (كانت بالتطبيق فقط). التعهد الموقّع إلزامي.

import React, { useEffect, useState } from 'react';
import toast from 'react-hot-toast';
import { Coins, Plus } from 'lucide-react';
import { Field, Input, Modal, ModalFooter, Select } from '@/components/ui';
import { formatIQD } from '@/lib/format';
import { errorMessage } from '@/lib/error-utils';
import { useConfirm } from '@/components/confirm';
import { LOAN_SALARY_WARNING_RATIO, overHalfSalaryWarning } from '../logic';
import { createDirectLoan, fetchLoanEmployees } from '../api';

type Props = {
  defaultFirstDue: string;
  onClose: () => void;
  onCreated: () => void;
};

export function CreateLoanModal({ defaultFirstDue, onClose, onCreated }: Props) {
  const [employees, setEmployees] = useState<{ id: string; full_name: string; monthly_salary_iqd: number | null }[]>([]);
  const [employeeId, setEmployeeId] = useState('');
  const [amount, setAmount] = useState('');
  const [months, setMonths] = useState('2');
  const [firstDue, setFirstDue] = useState(defaultFirstDue);
  const [pledge, setPledge] = useState<File | null>(null);
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const confirm = useConfirm();

  useEffect(() => {
    fetchLoanEmployees().then(setEmployees).catch((err: unknown) => toast.error(`تعذر تحميل الموظفين: ${errorMessage(err)}`));
  }, []);

  const amountNum = Number(amount.replace(/,/g, '')) || 0;
  const monthsNum = Math.max(0, Math.floor(Number(months) || 0));
  const installment = monthsNum > 0 ? Math.ceil(amountNum / monthsNum) : 0;
  const salary = Number(employees.find((e) => e.id === employeeId)?.monthly_salary_iqd ?? 0);
  const overHalf = salary > 0 && installment > salary * LOAN_SALARY_WARNING_RATIO;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!employeeId) return void toast.error('اختر الموظف');
    if (amountNum <= 0 || monthsNum <= 0) return void toast.error('اكتب المبلغ وعدد الأشهر');
    if (!pledge) return void toast.error('ارفع صورة التعهد الموقّع (إلزامي)');
    const warning = overHalfSalaryWarning(amountNum, monthsNum, salary);
    if (warning && !(await confirm({ title: 'القسط أكثر من نص الراتب', message: warning, confirmLabel: 'إعطاء رغم ذلك', tone: 'warning' }))) return;
    setSaving(true);
    try {
      await createDirectLoan({ employeeId, amount: amountNum, months: monthsNum, firstDue, pledge, notes });
      toast.success('انعطت السلفة وتولّدت أقساطها، ووصل إشعار للموظف ✅');
      onCreated();
    } catch (err: unknown) {
      toast.error(`تعذر إنشاء السلفة: ${errorMessage(err)}`);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title="سلفة لموظف" subtitle="سلفة معتمدة مباشرة تُقسط على راتبه" icon={Coins} tone="amber" size="sm" onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="الموظف">
          <Select required value={employeeId} onChange={(e) => setEmployeeId(e.target.value)}>
            <option value="">اختر الموظف...</option>
            {employees.map((emp) => <option key={emp.id} value={emp.id}>{emp.full_name}</option>)}
          </Select>
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="المبلغ (د.ع)">
            <Input inputMode="numeric" required value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^\d,]/g, ''))} placeholder="500,000" dir="ltr" />
          </Field>
          <Field label="عدد الأشهر">
            <Input type="number" min={1} max={60} required value={months} onChange={(e) => setMonths(e.target.value)} dir="ltr" />
          </Field>
        </div>
        <p className={overHalf ? 'text-xs font-bold text-amber-300' : 'text-xs text-slate-400'}>
          القسط الشهري: {formatIQD(installment)}{salary > 0 && ` · نص الراتب ${formatIQD(salary * LOAN_SALARY_WARNING_RATIO)}${overHalf ? ' (أكثر من النص: مسموح، والباقي يتسدد نقداً)' : ''}`}
        </p>
        <Field label="تاريخ أول قسط">
          <Input type="date" required value={firstDue} onChange={(e) => setFirstDue(e.target.value)} dir="ltr" />
        </Field>
        <Field label="صورة التعهد الموقّع (إلزامي)">
          <Input type="file" accept="image/*,application/pdf" required onChange={(e) => setPledge(e.target.files?.[0] ?? null)} />
        </Field>
        <Field label="ملاحظات (اختياري)">
          <Input value={notes} onChange={(e) => setNotes(e.target.value)} />
        </Field>
        <ModalFooter onCancel={onClose} loading={saving} submitLabel="إعطاء السلفة" submitIcon={Plus} />
      </form>
    </Modal>
  );
}
