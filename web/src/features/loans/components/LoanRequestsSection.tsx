'use client';

import type { Loan } from '@/lib/db-types';
import { Coins, X, Settings } from 'lucide-react';

interface LoanRequestsSectionProps {
  loanRequests: Loan[];
  actionLoading: string | null;
  onApprove: (loan: Loan) => void;
  onReject: (loan: Loan) => void;
}

/** عنوان الصفحة وبطاقات طلبات السلف المعلقة. */
export function LoanRequestsSection({ loanRequests, actionLoading, onApprove, onReject }: LoanRequestsSectionProps) {
  return (
    <>
      <div>
        <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
          <Coins className="w-5 h-5 text-teal-400" />
          <span>طلبات سلف الموظفين وتوليد الأقساط الشهرية</span>
        </h3>
        <p className="text-[11px] text-slate-400">اعتماد طلبات السلف المالية وتوليد أقساط وجداول السداد الشهرية بشكل مؤتمت وتفاعلي</p>
      </div>

      {loanRequests.length === 0 ? (
        <div className="h-64 flex flex-col items-center justify-center text-slate-500 text-xs">
          <Coins className="w-12 h-12 text-teal-500/20 mb-2 animate-pulse" />
          <span>لا توجد طلبات سلف معلقة للمراجعة حالياً. ✨</span>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {loanRequests.map((req) => {
            const amount = Number(req.amount);
            const months = Number(req.installment_count);
            const monthly = amount / months;
            
            return (
              <div 
                key={req.id} 
                className="relative bg-slate-950/40 border border-slate-850 hover:border-slate-800 rounded-2xl p-6 shadow-lg flex flex-col justify-between"
              >
                <div className="space-y-4">
                  <div className="flex items-center justify-between border-b border-slate-900 pb-3">
                    <h4 className="font-extrabold text-sm text-white">{req.employees?.full_name || 'موظف'}</h4>
                    <span className="text-[10px] bg-teal-500/10 text-teal-300 font-bold border border-teal-500/20 px-2 py-0.5 rounded-full">
                      طلب سلفة مالية
                    </span>
                  </div>

                  <div className="grid grid-cols-2 gap-4 text-xs">
                    <div>
                      <span className="text-slate-500 text-[10px] block mb-0.5">قيمة السلفة الكلية</span>
                      <span className="text-white font-extrabold text-sm">{amount.toLocaleString()} د.ع</span>
                    </div>
                    <div>
                      <span className="text-slate-500 text-[10px] block mb-0.5">أشهر السداد المقترحة</span>
                      <span className="text-slate-300 font-bold">{months} شهر تقسيط</span>
                    </div>
                  </div>

                  <div className="p-4 bg-teal-950/10 border border-teal-500/10 rounded-2xl">
                    <div className="flex justify-between items-center text-xs">
                      <span className="text-slate-400 font-semibold">القسط الشهري التلقائي:</span>
                      <span className="text-teal-400 font-extrabold text-sm">
                        {Math.round(monthly).toLocaleString()} د.ع / شهر
                      </span>
                    </div>
                  </div>

                  {req.pledge_url && (
                    <div className="p-3 bg-slate-900/60 rounded-xl border border-slate-850 flex items-center justify-between">
                      <span className="text-slate-400 text-xs font-semibold">التعهد الخطي الموقّع:</span>
                      <a 
                        href={req.pledge_url} 
                        target="_blank" 
                        rel="noreferrer"
                        className="text-[10px] bg-teal-500/10 hover:bg-teal-500/20 border border-teal-500/20 hover:border-teal-500/30 text-teal-300 font-bold px-3 py-1.5 rounded-lg transition-colors cursor-pointer"
                      >
                        تحميل التعهد المالي 📄
                      </a>
                    </div>
                  )}
                </div>

                <div className="flex gap-3 pt-6 border-t border-slate-900 mt-6">
                  <button
                    disabled={actionLoading === req.id}
                    onClick={() => onApprove(req)}
                    className="flex-1 flex items-center justify-center gap-1.5 py-3 px-4 bg-teal-600 hover:bg-teal-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/20 cursor-pointer"
                  >
                    <Settings className="w-4 h-4" />
                    <span>اعتماد وجدولة ذكية</span>
                  </button>
                  <button
                    disabled={actionLoading === req.id}
                    onClick={() => onReject(req)}
                    className="flex-1 flex items-center justify-center gap-1.5 py-3 px-4 bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/20 rounded-xl text-xs font-bold transition-all cursor-pointer"
                  >
                    <X className="w-4 h-4" />
                    <span>رفض الطلب</span>
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </>
  );
}
