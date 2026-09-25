'use client';

import type { Loan } from '@/lib/db-types';
import { nextUnpaidInstallment } from '../logic';
import type { LoansTab } from '../types';
import { Loader2, Calendar, CreditCard, Trash2 } from 'lucide-react';

interface LoansListSectionProps {
  loansTab: LoansTab;
  incompleteLoans: Loan[];
  completedLoans: Loan[];
  actionLoading: string | null;
  onTabChange: (tab: LoansTab) => void;
  onOpenSchedule: (loan: Loan) => void;
  onDelete: (loan: Loan) => void;
}

/** جدول السلف الجارية أو المكتملة مع التبديل بينهما. */
export function LoansListSection({ loansTab, incompleteLoans, completedLoans, actionLoading, onTabChange, onOpenSchedule, onDelete }: LoansListSectionProps) {
  const displayedLoans = loansTab === 'active' ? incompleteLoans : completedLoans;

  return (
    <div className="mt-12 pt-8 border-t border-slate-800/80">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6 border-b border-slate-800 pb-4">
        <div className="flex items-center gap-2">
          <CreditCard className="w-5 h-5 text-indigo-400" />
          <h3 className="text-lg font-extrabold text-white">
            {loansTab === 'active' ? 'إدارة السلف الجارية (النشطة)' : 'سجل السلف المكتملة المسددة'}
          </h3>
        </div>
        
        {/* Tab Bar (شريط التبويب) */}
        <div className="flex bg-slate-950 p-1 rounded-xl border border-slate-800">
          <button
            type="button"
            onClick={() => onTabChange('active')}
            className={`px-4 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${
              loansTab === 'active'
                ? 'bg-teal-600 text-white shadow-md'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            السلف الجارية ({incompleteLoans.length})
          </button>
          <button
            type="button"
            onClick={() => onTabChange('completed')}
            className={`px-4 py-1.5 rounded-lg text-xs font-bold transition-all cursor-pointer ${
              loansTab === 'completed'
                ? 'bg-teal-600 text-white shadow-md'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            السلف المكتملة ({completedLoans.length})
          </button>
        </div>
      </div>
      
      <div className="overflow-x-auto rounded-2xl border border-slate-800/60">
        <table className="w-full text-sm text-right">
          <thead className="bg-slate-900/80 text-slate-300 text-xs border-b border-slate-800/80">
            <tr>
              <th className="px-4 py-4 font-bold">الموظف</th>
              <th className="px-4 py-4 font-bold">المبلغ الكلي</th>
              <th className="px-4 py-4 font-bold">المبلغ المتبقي (الأقساط)</th>
              <th className="px-4 py-4 font-bold">القسط القادم</th>
              <th className="px-4 py-4 font-bold text-center">الإجراءات الذكية</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-800/60 bg-slate-950/30">
            {displayedLoans.length === 0 ? (
              <tr>
                <td colSpan={5} className="px-4 py-12 text-center text-slate-500 text-xs">
                  {loansTab === 'active' ? 'لا توجد سلف جارية حالياً' : 'لا توجد سلف مكتملة حالياً'}
                </td>
              </tr>
            ) : (
              displayedLoans.map((loan) => {
                const { next: nextInstallment, unpaidCount } = nextUnpaidInstallment(loan);
                
                return (
                  <tr key={loan.id} className="hover:bg-slate-900/40 transition-colors">
                    <td className="px-4 py-3 font-bold text-white text-xs">{loan.employees?.full_name}</td>
                    <td className="px-4 py-3 text-teal-400 font-bold text-xs">{Number(loan.amount).toLocaleString()} د.ع</td>
                    <td className="px-4 py-3 text-xs font-bold">
                      <div className="flex flex-col">
                        <span className={Number(loan.remaining_amount) > 0 ? 'text-amber-500 font-black text-xs' : 'text-emerald-400 font-black text-xs'}>
                          {Number(loan.remaining_amount).toLocaleString()} د.ع
                        </span>
                        <span className="text-[10px] text-slate-500">({unpaidCount} أقساط متبقية)</span>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-amber-400 text-xs font-mono">
                      {nextInstallment ? nextInstallment.due_date : 'اكتمل السداد ✨'}
                    </td>
                    <td className="px-4 py-3 flex items-center justify-center gap-2">
                      <button
                        type="button"
                        onClick={() => onOpenSchedule(loan)}
                        className="px-3.5 py-2 bg-teal-500/10 hover:bg-teal-500/20 border border-teal-500/20 hover:border-teal-500/40 text-teal-400 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-1.5"
                      >
                        <Calendar className="w-4 h-4" />
                        <span>جدول الأقساط والسداد</span>
                      </button>
                      {loansTab === 'completed' && (
                        <button
                          type="button"
                          disabled={actionLoading === 'delete_loan_' + loan.id}
                          onClick={() => onDelete(loan)}
                          className="px-3.5 py-2 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/20 hover:border-rose-500/40 text-rose-400 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-1.5"
                          title="حذف نهائي لتوفير المساحة"
                        >
                          {actionLoading === 'delete_loan_' + loan.id ? <Loader2 className="w-4 h-4 animate-spin" /> : <Trash2 className="w-4 h-4" />}
                          <span>إتلاف السجل</span>
                        </button>
                      )}
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
