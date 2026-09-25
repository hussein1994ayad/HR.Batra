import { Banknote, CheckCircle, Info, Loader2, X } from 'lucide-react';
import { sumPayroll, type PayrollRow } from '../calc';

type Props = {
  branchName: string;
  selectedMonth: string;
  startDate: string;
  endDate: string;
  pendingRows: PayrollRow[];
  approving: boolean;
  onClose: () => void;
  onConfirm: () => void;
};

/** اعتماد رواتب كل موظفي الفرع المعلقين دفعة واحدة. */
export function BulkApproveModal({ branchName, selectedMonth, startDate, endDate, pendingRows, approving, onClose, onConfirm }: Props) {
  const pendingBranchEmps = pendingRows;
  const totals = sumPayroll(pendingRows);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/85 backdrop-blur-md">
      <div className="relative w-full max-w-lg bg-slate-900/90 border border-slate-800 rounded-3xl shadow-2xl p-6 animate-glass text-right">
        <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-teal-500 to-cyan-500"></div>
        
        <button 
          onClick={onClose}
          className="absolute top-4 left-4 p-2 text-slate-400 hover:text-white bg-slate-950/40 rounded-xl hover:bg-slate-950 transition-colors cursor-pointer"
        >
          <X className="w-4 h-4" />
        </button>

        <h3 className="text-lg font-extrabold text-white flex items-center gap-2 mb-2 border-b border-slate-800 pb-4">
          <Banknote className="w-5 h-5 text-teal-400" />
          <span>احتساب واعتماد رواتب فرع: {branchName}</span>
        </h3>
        
        <div className="py-4 space-y-4">
          <p className="text-xs text-slate-400">
            تقوم هذه العملية باحتساب رواتب جميع موظفي الفرع المحدّد للفترة المالية الحالية (<span className="text-white font-bold">{startDate}</span> إلى <span className="text-white font-bold">{endDate}</span>) واعتماد كشوف رواتبهم بشكل نهائي دفعة واحدة.
          </p>

          {pendingBranchEmps.length === 0 ? (
            <div className="p-6 bg-emerald-950/10 border border-emerald-500/20 rounded-2xl text-center space-y-2">
              <CheckCircle className="w-8 h-8 text-emerald-400 mx-auto" />
              <p className="text-sm font-bold text-white">كل رواتب الموظفين معتمدة! ✅</p>
              <p className="text-xs text-slate-400">تم بالفعل اعتماد كشوف الرواتب لجميع موظفي هذا الفرع لشهر {selectedMonth}.</p>
            </div>
          ) : (
            <>
              {/* Summary Stats Grid */}
              <div className="grid grid-cols-2 gap-3">
                <div className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                  <span className="text-[10px] text-slate-500 block">عدد الموظفين المعلقين</span>
                  <span className="text-md font-bold text-white">{pendingBranchEmps.length} موظف</span>
                </div>
                <div className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                  <span className="text-[10px] text-slate-500 block">إجمالي الرواتب الأساسية</span>
                  <span className="text-md font-bold text-slate-200">{totals.basic.toLocaleString()} د.ع</span>
                </div>
                <div className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                  <span className="text-[10px] text-emerald-500 block">إجمالي المكافآت (+)</span>
                  <span className="text-md font-bold text-emerald-400">+{totals.bonuses.toLocaleString()} د.ع</span>
                </div>
                <div className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                  <span className="text-[10px] text-amber-500 block">إجمالي الخصومات والغياب (-)</span>
                  <span className="text-md font-bold text-amber-500">-{totals.deductions.toLocaleString()} د.ع</span>
                </div>
                <div className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80">
                  <span className="text-[10px] text-orange-400 block">إجمالي خصومات السلف (-)</span>
                  <span className="text-md font-bold text-orange-400">-{totals.loans.toLocaleString()} د.ع</span>
                </div>
                <div className="bg-slate-950/60 p-3 rounded-xl border border-slate-800/80 col-span-2 bg-teal-950/10 border-teal-500/20">
                  <span className="text-[10px] text-teal-400 block font-bold font-sans">إجمالي صافي الرواتب المستحق صرفها (Net)</span>
                  <span className="text-xl font-black text-teal-300">{totals.net.toLocaleString()} د.ع</span>
                </div>
              </div>

              <div className="p-3 bg-amber-950/10 border border-amber-500/20 rounded-xl text-xs text-amber-400 flex items-start gap-2">
                <Info className="w-4 h-4 shrink-0 mt-0.5" />
                <span>
                  تنبيّه: بعد تأكيد الاعتماد، سيتم إرسال إشعارات فورية لجميع الموظفين البالغ عددهم ({pendingBranchEmps.length}) بكشوف رواتبهم الجديدة وتحديث حالة السلف والخصومات تلقائياً.
                </span>
              </div>
            </>
          )}
        </div>

        <div className="flex justify-end gap-3 pt-6 border-t border-slate-800">
          <button 
            type="button" 
            onClick={onClose} 
            className="px-4 py-2 text-slate-400 hover:text-white"
          >
            إلغاء
          </button>
          {pendingBranchEmps.length > 0 && (
            <button
              type="button"
              disabled={approving}
              onClick={onConfirm}
              className="px-6 py-2.5 bg-teal-600 hover:bg-teal-500 text-white rounded-xl text-xs font-bold transition-all flex items-center gap-2 cursor-pointer active:scale-95"
            >
              {approving ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <>
                  <CheckCircle className="w-4 h-4" />
                  <span>اعتماد وصرف رواتب الفرع بالكامل</span>
                </>
              )}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
