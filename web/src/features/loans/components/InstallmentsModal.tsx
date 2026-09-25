'use client';

import type { Loan, LoanInstallment } from '@/lib/db-types';
import { paidAmount, sortInstallments } from '../logic';
import { Coins, Calendar, Settings } from 'lucide-react';

interface InstallmentsModalProps {
  selectedLoanForInstallments: Loan;
  actionLoading: string | null;
  onClose: () => void;
  onEditLoan: (loan: Loan) => void;
  onCashPayment: (installment: LoanInstallment) => void;
  onPostpone: (installment: LoanInstallment) => void;
  onEditInstallment: (installment: LoanInstallment) => void;
  onRevert: (installmentId: string) => void;
  onDeletePaid: (installmentId: string) => void;
}

/** جدول أقساط السلفة مع السداد النقدي والتأجيل والتعديل والتراجع. */
export function InstallmentsModal({ selectedLoanForInstallments, actionLoading, onClose, onEditLoan, onCashPayment, onPostpone, onEditInstallment, onRevert, onDeletePaid }: InstallmentsModalProps) {
  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/85 backdrop-blur-md p-4 overflow-y-auto">
      <div className="relative w-full max-w-2xl bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 text-right animate-glass my-8">
        <button 
          onClick={onClose} 
          className="absolute top-4 left-4 p-2 text-slate-400 hover:text-white bg-slate-950/40 rounded-xl hover:bg-slate-950 transition-colors cursor-pointer"
        >
          ✕
        </button>

        <h3 className="text-md font-extrabold text-white flex items-center gap-2 mb-2 border-b border-slate-800 pb-4">
          <Coins className="w-5 h-5 text-teal-400" />
          <span>جدول سداد وأقساط سلفة: {selectedLoanForInstallments.employees?.full_name}</span>
        </h3>

        {/* Loan Status Cards */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
          <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
            <span className="text-[10px] text-slate-500 block mb-1">المبلغ الكلي للسلفة</span>
            <span className="text-xs font-black text-white">{Number(selectedLoanForInstallments.amount).toLocaleString()} د.ع</span>
          </div>
          <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
            <span className="text-[10px] text-emerald-400 block mb-1">إجمالي ما تم سداده</span>
            <span className="text-xs font-black text-emerald-400">
              {paidAmount(selectedLoanForInstallments).toLocaleString()} د.ع
            </span>
          </div>
          <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
            <span className="text-[10px] text-amber-500 block mb-1">المبلغ المتبقي للسداد</span>
            <span className="text-xs font-black text-amber-500">{Number(selectedLoanForInstallments.remaining_amount).toLocaleString()} د.ع</span>
          </div>
          <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
            <span className="text-[10px] text-indigo-400 block mb-1">القسط الشهري الافتراضي</span>
            <span className="text-xs font-black text-indigo-400">{Number(selectedLoanForInstallments.installment_amount).toLocaleString()} د.ع</span>
          </div>
        </div>

        {/* Actions for Entire Loan */}
        <div className="flex gap-3 mb-6 bg-slate-950/20 p-3 rounded-2xl border border-slate-850 justify-between items-center flex-wrap">
          <span className="text-[10px] text-slate-400 font-bold">إجراءات السلفة العامة:</span>
          <div className="flex flex-wrap gap-2">
            {selectedLoanForInstallments.pledge_url && (
              <a
                href={selectedLoanForInstallments.pledge_url}
                target="_blank"
                rel="noreferrer"
                className="px-3 py-1.5 bg-teal-500/10 hover:bg-teal-500/20 border border-teal-500/20 hover:border-teal-500/30 text-teal-400 hover:text-teal-300 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-1.5"
              >
                <span>عرض التعهد الخطي 📄</span>
              </a>
            )}
            <button
              onClick={() => window.print()}
              className="px-3 py-1.5 bg-amber-500/10 hover:bg-amber-500/20 border border-amber-500/20 hover:border-amber-500/30 text-amber-400 hover:text-amber-300 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-1.5"
            >
              <span>طباعة كشف الحركة 🖨️</span>
            </button>
            <button
              onClick={() => onEditLoan(selectedLoanForInstallments)}
              className="px-3 py-1.5 bg-blue-500/10 hover:bg-blue-500/20 border border-blue-500/20 text-blue-400 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-1.5"
            >
              <Settings className="w-3.5 h-3.5" />
              <span>تعديل السلفة وإعادة الجدولة</span>
            </button>
          </div>
        </div>

        {/* Installments Table */}
        <h4 className="text-xs font-bold text-slate-400 mb-3 flex items-center gap-1.5">
          <Calendar className="w-4 h-4 text-teal-400" />
          <span>تفاصيل الأقساط وجدول السداد:</span>
        </h4>

        <div className="overflow-y-auto max-h-[300px] border border-slate-800 rounded-2xl bg-slate-950/20 divide-y divide-slate-800/80">
          {sortInstallments(selectedLoanForInstallments.loan_installments).map((inst: LoanInstallment, idx: number) => {
              const isPaid = inst.is_paid;
              
              return (
                <div key={inst.id} className="p-3.5 flex flex-col sm:flex-row sm:items-center justify-between gap-3 text-xs hover:bg-slate-900/40 transition-colors">
                  <div className="flex items-center gap-4">
                    <span className="font-bold text-slate-500 w-12">قسط #{idx + 1}</span>
                    <span className="font-mono text-slate-300 font-bold bg-slate-900 border border-slate-800 px-2 py-0.5 rounded-lg">{inst.due_date}</span>
                    <span className="font-bold text-white">{Number(inst.amount).toLocaleString()} د.ع</span>
                  </div>

                  <div className="flex items-center gap-3 justify-end">
                    {/* Status Badge */}
                    <span className={`px-2.5 py-1 rounded-xl font-bold text-[9px] ${
                      isPaid 
                        ? (inst.payment_type === 'cash' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/15' : 'bg-blue-500/10 text-blue-400 border border-blue-500/15')
                        : 'bg-slate-800 text-slate-400'
                    }`}>
                      {isPaid 
                        ? (inst.payment_type === 'cash' ? `مدفوع نقداً 💵 ${inst.payment_note ? `(${inst.payment_note})` : ''}` : 'مدفوع استقطاع راتب 💸')
                        : 'غير مدفوع ⏳'
                      }
                    </span>

                    {/* Actions */}
                    <div className="flex gap-1.5">
                      {!isPaid ? (
                        <>
                          <button
                            disabled={actionLoading !== null}
                            onClick={() => onCashPayment(inst)}
                            className="px-2 py-1 bg-emerald-500/10 hover:bg-emerald-500/20 border border-emerald-500/20 text-emerald-400 rounded-lg text-[10px] font-bold transition-all cursor-pointer"
                            title="تسجيل سداد نقدي كاش خارج الراتب"
                          >
                            دفع نقدي 💵
                          </button>
                          <button
                            disabled={actionLoading !== null}
                            onClick={() => onPostpone(inst)}
                            className="px-2 py-1 bg-indigo-500/10 hover:bg-indigo-500/20 border border-indigo-500/20 text-indigo-400 rounded-lg text-[10px] font-bold transition-all cursor-pointer"
                            title="تأجيل هذا القسط والأقساط اللاحقة شهراً إضافياً"
                          >
                            تأجيل قسط 🔄
                          </button>
                          <button
                            disabled={actionLoading !== null}
                            onClick={() => onEditInstallment(inst)}
                            className="px-2 py-1 bg-blue-500/10 hover:bg-blue-500/20 border border-blue-500/20 text-blue-400 rounded-lg text-[10px] font-bold transition-all cursor-pointer"
                            title="تعديل قيمة هذا القسط يدوياً"
                          >
                            تعديل ✏️
                          </button>
                        </>
                      ) : (
                        <div className="flex gap-1.5">
                          <button
                            disabled={actionLoading !== null}
                            onClick={() => onRevert(inst.id)}
                            className="px-2 py-1 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/20 text-rose-400 rounded-lg text-[10px] font-bold transition-all cursor-pointer"
                            title="التراجع عن دفع القسط وإعادته لغير مدفوع"
                          >
                            تراجع عن الدفع 🔄
                          </button>
                          <button
                            type="button"
                            disabled={actionLoading !== null}
                            onClick={() => onDeletePaid(inst.id)}
                            className="px-2 py-1 bg-red-500/15 hover:bg-red-650 border border-red-500/20 text-red-400 hover:text-white rounded-lg text-[10px] font-bold transition-all cursor-pointer flex items-center gap-1"
                            title="حذف القسط المسدد نهائياً من قاعدة البيانات لتوفير المساحة"
                          >
                            <span>حذف نهائي 🗑️</span>
                          </button>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
        </div>

        <div className="flex justify-end pt-6 mt-6 border-t border-slate-800">
          <button 
            onClick={onClose}
            className="px-6 py-2.5 bg-slate-950 hover:bg-slate-900 text-white rounded-xl text-xs font-bold transition-all border border-slate-800 cursor-pointer"
          >
            موافق وإغلاق
          </button>
        </div>
      </div>
    </div>
  );
}
