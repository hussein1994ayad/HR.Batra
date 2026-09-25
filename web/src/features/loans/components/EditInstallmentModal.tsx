'use client';

import React, { useState } from 'react';
import type { InstallmentPrompt } from '../types';
import { Loader2, Settings } from 'lucide-react';

interface EditInstallmentModalProps {
  editInstallmentPrompt: InstallmentPrompt;
  saving: boolean;
  onClose: () => void;
  onSubmit: (amount: number) => void;
}

/** تعديل قيمة قسط واحد يدوياً. */
export function EditInstallmentModal({ editInstallmentPrompt, saving, onClose, onSubmit }: EditInstallmentModalProps) {
  const [newInstallmentAmtVal, setNewInstallmentAmtVal] = useState(Number(editInstallmentPrompt.amount));

  const handleUpdateInstallmentAmount = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(newInstallmentAmtVal);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-sm p-4">
      <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 w-full max-w-sm shadow-2xl animate-glass text-right">
        <h3 className="text-sm font-bold text-white flex items-center gap-2 mb-4">
          <Settings className="w-5 h-5 text-blue-400" />
          <span>تعديل قيمة قسط شهري</span>
        </h3>
        
        <form onSubmit={handleUpdateInstallmentAmount} className="space-y-4">
          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">مبلغ القسط الجديد (د.ع)</label>
            <input 
              type="text" 
              value={newInstallmentAmtVal || ''}
              onChange={(e) => setNewInstallmentAmtVal(Number(e.target.value.replace(/\D/g, '')))}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-blue-500/50 outline-none transition-all font-mono text-left"
              dir="ltr"
              required
            />
          </div>

          <div className="flex justify-end gap-3 pt-4 border-t border-slate-800 mt-4">
            <button type="button" onClick={onClose} className="px-4 py-2 text-xs text-slate-400">إلغاء</button>
            <button
              type="submit"
              disabled={saving}
              className="px-6 py-2 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold shadow-lg flex items-center gap-2 cursor-pointer"
            >
              {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <span>حفظ التعديل</span>}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
