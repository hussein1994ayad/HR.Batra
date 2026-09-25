'use client';

import { useState } from 'react';
import toast from 'react-hot-toast';
import type { PayrollRow } from '../calc';
import type { OverrideField } from '../types';

type Props = {
  row: PayrollRow;
  field: OverrideField;
  displayValue: number;
  colorClass: string;
  prefixSign?: string;
  isOverridden: boolean;
  onSave: (value: number) => void;
  onClear: () => void;
};

/** خانة مبلغ قابلة للتعديل اليدوي (المكافآت، خصومات الدوام، الخصومات الأخرى). */
export function EditableAmountCell({ row: emp, field, displayValue, colorClass, prefixSign = '', isOverridden, onSave, onClear }: Props) {
  const [isEditing, setIsEditing] = useState(false);
  const saveOverride = (_employeeId: string, _field: OverrideField, value: number) => {
    onSave(value);
    setIsEditing(false);
  };
  const clearOverride = () => {
    onClear();
    setIsEditing(false);
  };

  return (
    <div className="relative inline-block">
      <button
        onClick={() => {
          if (emp.isIssued) {
            toast.error('الراتب معتمد ومقفل ولا يمكن تعديله 🔒');
            return;
          }
          setIsEditing(true);
        }}
        className={`font-bold border-b border-dashed border-slate-700 hover:border-teal-500 hover:text-teal-300 transition-colors cursor-pointer outline-none select-none ${colorClass} ${isOverridden ? 'bg-amber-500/10 px-2 py-1 rounded-xl border-amber-500/30 hover:border-amber-400' : ''}`}
        title="اضغط لتعديل القيمة يدوياً"
      >
        {displayValue > 0 ? `${prefixSign}${displayValue.toLocaleString()} د.ع` : '-'}
        {isOverridden && <span className="text-[9px] text-amber-400 font-black mr-1" title="معدل يدوياً">*</span>}
      </button>

      {isEditing && (
        <div className="absolute z-50 bottom-full mb-2 right-1/2 translate-x-1/2 bg-slate-900 border border-slate-800 rounded-3xl p-4 shadow-2xl w-48 text-right space-y-3 animate-glass font-sans">
          <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-teal-500 to-indigo-500 rounded-t-3xl"></div>
          
          <h5 className="text-[10px] font-bold text-slate-400">
            {field === 'bonuses' ? 'تعديل المكافآت يدوياً' : 
             field === 'attendanceDeductions' ? 'تعديل خصومات الدوام والغياب' : 
             'تعديل الخصومات الأخرى'}
          </h5>
          
          <input 
            type="number" 
            defaultValue={displayValue}
            className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2 text-xs text-white outline-none font-bold text-left"
            dir="ltr"
            autoFocus
            id="inline-edit-input"
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                saveOverride(emp.id, field, Number((e.target as HTMLInputElement).value));
              }
              if (e.key === 'Escape') {
                setIsEditing(false);
              }
            }}
          />
          
          <div className="flex gap-1.5 justify-end">
            {isOverridden && (
              <button 
                type="button" 
                onClick={clearOverride}
                className="text-[9px] text-amber-500 hover:text-amber-400 font-bold ml-auto"
              >
                تلقائي 🔄
              </button>
            )}
            <button 
              type="button" 
              onClick={() => setIsEditing(false)}
              className="px-2 py-1 text-[10px] text-slate-400 hover:text-white"
            >
              إلغاء
            </button>
            <button 
              type="button"
              onClick={() => {
                const input = document.getElementById('inline-edit-input') as HTMLInputElement;
                if (input) {
                  saveOverride(emp.id, field, Number(input.value));
                }
              }}
              className="px-3 py-1 bg-teal-650 hover:bg-teal-600 text-white rounded-xl text-[10px] font-bold shadow-md cursor-pointer active:scale-95 transition-all"
            >
              حفظ
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
