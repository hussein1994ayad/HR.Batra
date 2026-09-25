'use client';

import React, { useState } from 'react';
import type { Loan } from '@/lib/db-types';
import { loanToEditDraft } from '../logic';
import type { EditLoanDraft } from '../types';
import { Loader2, Settings, Save } from 'lucide-react';

interface EditLoanModalProps {
  loan: Loan;
  saving: boolean;
  onClose: () => void;
  onSubmit: (draft: EditLoanDraft) => void;
}

/** تعديل سلفة جارية وإعادة جدولة أقساطها غير المدفوعة. */
export function EditLoanModal({ loan, saving, onClose, onSubmit }: EditLoanModalProps) {
  const [editLoanModal, setEditLoanModal] = useState<EditLoanDraft>(() => loanToEditDraft(loan));

  const handleUpdateActiveLoan = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(editLoanModal);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 w-full max-w-md shadow-2xl animate-glass">
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-lg font-bold text-white flex items-center gap-2">
            <Settings className="w-5 h-5 text-blue-400" />
            <span>تعديل السلفة وإعادة الجدولة</span>
          </h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white cursor-pointer">✕</button>
        </div>
        
        <form onSubmit={handleUpdateActiveLoan} className="space-y-4">
          <div className="p-4 bg-slate-950/50 rounded-xl mb-4 text-sm text-slate-300">
            <strong>الموظف:</strong> {editLoanModal.loan.employees?.full_name}
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">المبلغ الإجمالي للسلفة (د.ع)</label>
            <input 
              type="text" 
              value={editLoanModal.amount}
              onChange={(e) => setEditLoanModal({ ...editLoanModal, amount: Number(e.target.value.replace(/\D/g, '')) })}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-blue-500/50 outline-none transition-all font-mono text-left"
              dir="ltr"
              required
            />
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">القسط الشهري (د.ع)</label>
            <input 
              type="text" 
              value={editLoanModal.installmentAmount}
              onChange={(e) => setEditLoanModal({ ...editLoanModal, installmentAmount: Number(e.target.value.replace(/\D/g, '')) })}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-blue-500/50 outline-none transition-all font-mono text-left"
              dir="ltr"
              required
            />
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">عدد الأقساط الإجمالي (أشهر)</label>
            <input 
              type="text" 
              value={editLoanModal.installmentCount}
              onChange={(e) => setEditLoanModal({ ...editLoanModal, installmentCount: Number(e.target.value.replace(/\D/g, '')) })}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-blue-500/50 outline-none transition-all font-mono text-left"
              dir="ltr"
              required
            />
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">المبلغ المتبقي للسداد (د.ع)</label>
            <input 
              type="text" 
              value={editLoanModal.remainingAmount}
              onChange={(e) => setEditLoanModal({ ...editLoanModal, remainingAmount: Number(e.target.value.replace(/\D/g, '')) })}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-blue-500/50 outline-none transition-all font-mono text-left"
              dir="ltr"
              required
            />
          </div>

          <button
            type="submit"
            disabled={saving}
            className="w-full mt-6 bg-blue-600 hover:bg-blue-500 text-white font-bold py-3 rounded-xl transition-colors cursor-pointer flex items-center justify-center gap-2"
          >
            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
            <span>حفظ التعديلات وإعادة الجدولة</span>
          </button>
        </form>
      </div>
    </div>
  );
}
