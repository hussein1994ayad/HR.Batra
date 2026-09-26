'use client';

import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { TrendingDown, TrendingUp } from 'lucide-react';
import { AmountInput, Field, Input, Modal, ModalFooter, cn } from '@/components/ui';

type Props = {
  employee: { id: string; full_name: string };
  initialType: 'bonus' | 'deduction';
  saving: boolean;
  onClose: () => void;
  onSubmit: (entry: { employeeId: string; type: 'bonus' | 'deduction'; amount: number; reason: string }) => Promise<boolean>;
};

/** نافذة إضافة مكافأة أو خصم يدوي لموظف. */
export function AddAdjustmentModal({ employee, initialType, saving, onClose, onSubmit }: Props) {
  const [type, setType] = useState<'bonus' | 'deduction'>(initialType);
  const [amount, setAmount] = useState(0);
  const [reason, setReason] = useState('');

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (amount <= 0) {
      toast.error('أدخل مبلغاً أكبر من صفر');
      return;
    }
    if (await onSubmit({ employeeId: employee.id, type, amount, reason })) onClose();
  };

  return (
    <Modal
      title="تسوية مالية يدوية"
      subtitle={employee.full_name}
      icon={type === 'bonus' ? TrendingUp : TrendingDown}
      tone={type === 'bonus' ? 'emerald' : 'rose'}
      size="sm"
      onClose={onClose}
    >
      <form onSubmit={submit} className="space-y-4">
        <div className="grid grid-cols-2 gap-2">
          {(['bonus', 'deduction'] as const).map((t) => {
            const active = type === t;
            const Icon = t === 'bonus' ? TrendingUp : TrendingDown;
            return (
              <button
                key={t}
                type="button"
                onClick={() => setType(t)}
                className={cn(
                  'flex flex-col items-center gap-1.5 py-3 rounded-2xl border text-xs font-bold transition-colors cursor-pointer',
                  active
                    ? t === 'bonus'
                      ? 'border-emerald-400/50 bg-emerald-500/10 text-emerald-300'
                      : 'border-rose-400/50 bg-rose-500/10 text-rose-300'
                    : 'border-slate-800 bg-slate-950/50 text-slate-400 hover:text-slate-200',
                )}
              >
                <Icon className="w-5 h-5" />
                {t === 'bonus' ? 'مكافأة (+)' : 'خصم (−)'}
              </button>
            );
          })}
        </div>
        <Field label="المبلغ (د.ع)">
          <AmountInput required autoFocus value={amount} onValueChange={setAmount} placeholder="25,000" />
        </Field>
        <Field label="السبب">
          <Input required value={reason} onChange={(e) => setReason(e.target.value)} placeholder="مثال: ساعات إضافية، عقوبة إدارية..." />
        </Field>
        <ModalFooter onCancel={onClose} loading={saving} submitLabel="حفظ" variant={type === 'bonus' ? 'success' : 'danger'} />
      </form>
    </Modal>
  );
}
