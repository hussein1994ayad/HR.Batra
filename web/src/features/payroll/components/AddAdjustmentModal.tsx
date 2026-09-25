'use client';

import React, { useState } from 'react';
import { Loader2, TrendingDown, TrendingUp } from 'lucide-react';

type Props = {
  employee: { id: string; full_name: string };
  initialType: 'bonus' | 'deduction';
  saving: boolean;
  onClose: () => void;
  onSubmit: (entry: { employeeId: string; type: 'bonus' | 'deduction'; amount: number; reason: string }) => Promise<boolean>;
};

/** نافذة إضافة مكافأة أو خصم يدوي لموظف. */
export function AddAdjustmentModal({ employee, initialType, saving, onClose, onSubmit }: Props) {
  const [bdType, setBdType] = useState<'bonus' | 'deduction'>(initialType);
  const [bdAmount, setBdAmount] = useState(0);
  const [bdReason, setBdReason] = useState('');

  const handleAddBonusDeduction = async (e: React.FormEvent) => {
    e.preventDefault();
    if (bdAmount <= 0) return;
    const ok = await onSubmit({ employeeId: employee.id, type: bdType, amount: bdAmount, reason: bdReason });
    if (ok) onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md">
      <div className="relative w-full max-w-md bg-slate-900/90 border border-slate-800 rounded-3xl shadow-2xl p-6 animate-glass text-right">
        <div className={`absolute top-0 inset-x-0 h-1 bg-gradient-to-r ${bdType === 'bonus' ? 'from-emerald-500 to-teal-500' : 'from-rose-500 to-red-500'}`}></div>
        
        <h3 className="text-lg font-bold text-white mb-6">إضافة تسوية مالية يدوية: {employee.full_name}</h3>
        
        <form onSubmit={handleAddBonusDeduction} className="space-y-4">
          <div className="flex gap-4">
            <label className={`flex-1 flex flex-col items-center justify-center gap-2 p-4 rounded-2xl border-2 cursor-pointer transition-all ${bdType === 'bonus' ? 'border-emerald-500 bg-emerald-500/10' : 'border-slate-800 bg-slate-950/50'}`}>
              <input type="radio" className="hidden" checked={bdType === 'bonus'} onChange={() => setBdType('bonus')} />
              <TrendingUp className={`w-6 h-6 ${bdType === 'bonus' ? 'text-emerald-400' : 'text-slate-500'}`} />
              <span className={`text-xs font-bold ${bdType === 'bonus' ? 'text-emerald-400' : 'text-slate-400'}`}>مكافأة (+)</span>
            </label>
            <label className={`flex-1 flex flex-col items-center justify-center gap-2 p-4 rounded-2xl border-2 cursor-pointer transition-all ${bdType === 'deduction' ? 'border-rose-500 bg-rose-500/10' : 'border-slate-800 bg-slate-950/50'}`}>
              <input type="radio" className="hidden" checked={bdType === 'deduction'} onChange={() => setBdType('deduction')} />
              <TrendingDown className={`w-6 h-6 ${bdType === 'deduction' ? 'text-rose-400' : 'text-slate-500'}`} />
              <span className={`text-xs font-bold ${bdType === 'deduction' ? 'text-rose-400' : 'text-slate-400'}`}>خصم يدوي (-)</span>
            </label>
          </div>

          <div>
            <label className="block text-xs text-slate-400 mb-1">المبلغ (د.ع)</label>
            <input
              type="text"
              required
              value={bdAmount || ''}
              onChange={(e) => setBdAmount(Number(e.target.value.replace(/\D/g, '')))}
              className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-sm text-white font-bold outline-none text-left"
              dir="ltr"
              placeholder="مثال: 25000"
            />
          </div>

          <div>
            <label className="block text-xs text-slate-400 mb-1">السبب / البيان</label>
            <input
              type="text"
              required
              value={bdReason}
              onChange={(e) => setBdReason(e.target.value)}
              placeholder="مثال: تسوية ساعات إضافية، عقوبة إدارية..."
              className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
            />
          </div>

          <div className="flex justify-end gap-3 pt-4 mt-2 border-t border-slate-800">
            <button type="button" onClick={onClose} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
            <button
              type="submit"
              disabled={saving}
              className={`px-6 py-2 text-white rounded-xl text-xs font-bold shadow-lg flex items-center gap-2 ${bdType === 'bonus' ? 'bg-emerald-600 hover:bg-emerald-500' : 'bg-rose-600 hover:bg-rose-500'}`}
            >
              {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <span>تأكيد وحفظ</span>}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
