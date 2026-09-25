'use client';

import React, { useState } from 'react';
import type { Loan } from '@/lib/db-types';
import { sameDayNextMonth } from '../logic';
import type { ApprovalDraft } from '../types';
import { Loader2, Settings, Save } from 'lucide-react';

interface ApprovalModalProps {
  loan: Loan;
  saving: boolean;
  onClose: () => void;
  onSubmit: (draft: ApprovalDraft) => void;
}

/** اعتماد السلفة مع إمكانية تعديل المبلغ والمدة وتاريخ أول قسط. */
export function ApprovalModal({ loan, saving, onClose, onSubmit }: ApprovalModalProps) {
  const [approvalModal, setApprovalModal] = useState<ApprovalDraft>(() => ({
    loan,
    amount: Number(loan.amount),
    months: Number(loan.installment_count),
    startDate: sameDayNextMonth(),
  }));

  const submitSmartApproval = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(approvalModal);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
      <div className="bg-slate-900 border border-slate-800 rounded-3xl p-6 w-full max-w-md shadow-2xl">
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-lg font-bold text-white flex items-center gap-2">
            <Settings className="w-5 h-5 text-teal-400" />
            <span>الاعتماد والجدولة الذكية للسلفة</span>
          </h3>
          <button onClick={onClose} className="text-slate-400 hover:text-white cursor-pointer">✕</button>
        </div>
        
        <form onSubmit={submitSmartApproval} className="space-y-4">
          <div className="p-4 bg-slate-950/50 rounded-xl mb-4 text-sm text-slate-300">
            <strong>الموظف:</strong> {approvalModal.loan.employees?.full_name}
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">المبلغ الإجمالي (د.ع)</label>
            <input 
              type="text" 
              value={approvalModal.amount}
              onChange={(e) => setApprovalModal({ ...approvalModal, amount: Number(e.target.value.replace(/\D/g, '')) })}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 outline-none transition-all font-mono text-left"
              dir="ltr"
              required
            />
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">عدد أشهر التقسيط</label>
            <input 
              type="text" 
              value={approvalModal.months}
              onChange={(e) => setApprovalModal({ ...approvalModal, months: Number(e.target.value.replace(/\D/g, '')) })}
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 outline-none transition-all font-mono text-left"
              dir="ltr"
              required
            />
          </div>

          <div className="p-3 bg-teal-950/20 border border-teal-900/30 rounded-xl text-center">
            <span className="text-[10px] text-teal-500 block mb-1">القسط الشهري الجديد</span>
            <span className="text-lg font-black text-teal-400 font-mono">
              {(approvalModal.months > 0 ? Math.round(approvalModal.amount / approvalModal.months) : 0).toLocaleString()} د.ع
            </span>
          </div>

          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold">تاريخ استحقاق أول قسط (YYYY-MM-DD)</label>
            <input 
              type="text" 
              value={approvalModal.startDate}
              onChange={(e) => setApprovalModal({ ...approvalModal, startDate: e.target.value })}
              placeholder="2026-06-01"
              className="w-full bg-slate-950 border border-slate-800 text-white rounded-xl px-4 py-2.5 text-sm focus:border-teal-500/50 outline-none transition-all font-mono text-left"
              dir="ltr"
              required
            />
          </div>

          <button
            type="submit"
            disabled={saving}
            className="w-full mt-6 bg-teal-600 hover:bg-teal-500 text-white font-bold py-3 rounded-xl transition-colors cursor-pointer flex items-center justify-center gap-2"
          >
            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
            <span>حفظ وتوليد الأقساط</span>
          </button>
        </form>
      </div>
    </div>
  );
}
