'use client';

import React, { useState } from 'react';
import type { InstallmentPrompt } from '../types';
import { Coins, Loader2 } from 'lucide-react';

interface CashPaymentModalProps {
  cashPaymentPrompt: InstallmentPrompt;
  saving: boolean;
  onClose: () => void;
  onSubmit: (note: string) => void;
}

/** تسجيل سداد نقدي لقسط خارج استقطاع الراتب. */
export function CashPaymentModal({ cashPaymentPrompt, saving, onClose, onSubmit }: CashPaymentModalProps) {
  const [cashNote, setCashNote] = useState('');

  const handleRecordCashPayment = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(cashNote);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-sm p-4">
      <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 w-full max-w-sm shadow-2xl animate-glass text-right">
        <h3 className="text-sm font-bold text-white flex items-center gap-2 mb-4">
          <Coins className="w-5 h-5 text-emerald-400" />
          <span>تسجيل سداد نقدي (كاش) للقسط</span>
        </h3>
        
        <form onSubmit={handleRecordCashPayment} className="space-y-4">
          <div className="p-3.5 bg-slate-950/50 rounded-xl text-xs text-slate-350 space-y-1">
            <p>• قيمة القسط المراد سداده: <span className="font-mono text-white font-bold">{Number(cashPaymentPrompt.amount).toLocaleString()} د.ع</span></p>
            <p className="text-[10px] text-amber-400">* سيتم خصم هذا القسط وتحديث رصيد السلفة فورياً وتخطيه في الراتب القادم.</p>
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">ملاحظات السداد (اختياري)</label>
            <input 
              type="text" 
              value={cashNote}
              onChange={(e) => setCashNote(e.target.value)}
              placeholder="مثال: دفع كاش بالكامل بوصل استلام يدوي"
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-xs focus:border-emerald-500/50 outline-none transition-all"
            />
          </div>

          <div className="flex justify-end gap-3 pt-4 border-t border-slate-800 mt-4">
            <button type="button" onClick={onClose} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
            <button
              type="submit"
              disabled={saving}
              className="px-6 py-2 bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl text-xs font-bold shadow-lg flex items-center gap-2 cursor-pointer"
            >
              {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <span>تأكيد السداد</span>}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
