'use client';

import { useState } from 'react';
import toast from 'react-hot-toast';
import { RotateCcw } from 'lucide-react';
import { AmountInput, Button, cn } from '@/components/ui';
import type { PayrollRow } from '../calc';
import type { OverrideField } from '../types';

type Props = {
  row: PayrollRow;
  field: OverrideField;
  displayValue: number;
  colorClass: string;
  prefixSign?: string;
  isOverridden: boolean;
  disabled?: boolean;
  onSave: (value: number) => void;
  onClear: () => void;
};

const TITLES: Record<OverrideField, string> = {
  bonuses: 'تعديل المكافآت يدوياً (د.ع)',
  attendanceDeductions: 'تعديل خصومات الدوام والغياب (د.ع)',
  otherDeductions: 'تعديل الخصومات الأخرى (د.ع)',
};

/** خانة مبلغ قابلة للتعديل اليدوي (المكافآت، خصومات الدوام، الخصومات الأخرى). */
export function EditableAmountCell({ row, field, displayValue, colorClass, prefixSign = '', isOverridden, disabled, onSave, onClear }: Props) {
  const [editing, setEditing] = useState(false);
  const [value, setValue] = useState(displayValue);

  const open = () => {
    if (row.isIssued) {
      toast.error('الراتب معتمد ومقفل ولا يمكن تعديله');
      return;
    }
    setValue(displayValue);
    setEditing(true);
  };

  return (
    <div className="relative inline-block">
      <button
        type="button"
        disabled={disabled}
        onClick={open}
        title="اضغط لتعديل القيمة يدوياً"
        className={cn(
          'font-bold whitespace-nowrap border-b border-dashed border-slate-700 hover:border-indigo-400 transition-colors cursor-pointer disabled:cursor-default',
          colorClass,
          isOverridden && 'bg-amber-500/10 px-2 py-0.5 rounded-lg border-amber-500/40',
        )}
      >
        {displayValue > 0 ? `${prefixSign}${displayValue.toLocaleString('en-US')}` : '—'}
        {isOverridden && <span className="text-amber-300 mr-1" title="معدل يدوياً">*</span>}
      </button>

      {editing && (
        <div
          className="absolute z-30 top-full mt-2 right-1/2 translate-x-1/2 w-52 surface-solid rounded-2xl p-3 space-y-2.5 animate-glass text-right print:hidden"
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              onSave(value);
              setEditing(false);
            } else if (e.key === 'Escape') {
              e.stopPropagation();
              setEditing(false);
            }
          }}
        >
          <p className="text-[10px] font-bold text-slate-400">{TITLES[field]}</p>
          <AmountInput autoFocus value={value} onValueChange={setValue} className="h-9" />
          <div className="flex items-center gap-1.5">
            {isOverridden && (
              <Button size="xs" variant="ghost" icon={RotateCcw} className="ml-auto" onClick={() => { onClear(); setEditing(false); }}>
                تلقائي
              </Button>
            )}
            <Button size="xs" variant="ghost" className={isOverridden ? '' : 'mr-auto'} onClick={() => setEditing(false)}>
              إلغاء
            </Button>
            <Button size="xs" onClick={() => { onSave(value); setEditing(false); }}>
              حفظ
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
