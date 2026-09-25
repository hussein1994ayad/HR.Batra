import { Banknote, CalendarRange, Clock, Info, Plus, Printer, TrendingDown, TrendingUp, X } from 'lucide-react';
import type { BonusDeduction } from '@/lib/db-types';
import type { PayrollRow } from '../calc';
import type { DetailLog } from '../types';

type Props = {
  row: PayrollRow;
  startDate: string;
  endDate: string;
  onClose: () => void;
  onAddAdjustment: (type: 'bonus' | 'deduction') => void;
  onToggleExcuse: (date: string) => void;
};

/** تفاصيل حضور وخصومات موظف خلال الدورة مع إمكانية إعفاء أيام الغياب. */
export function AttendanceBreakdownModal({ row: selectedEmpForBreakdown, startDate, endDate, onClose, onAddAdjustment, onToggleExcuse }: Props) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md overflow-y-auto">
      <div className="relative w-full max-w-2xl bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 text-right animate-glass my-8">
        <button 
          onClick={onClose}
          className="absolute top-4 left-4 p-2 text-slate-400 hover:text-white bg-slate-950/40 rounded-xl hover:bg-slate-950 transition-colors cursor-pointer"
        >
          <X className="w-4 h-4" />
        </button>

        <h3 className="text-md font-extrabold text-white flex items-center gap-2 mb-2 border-b border-slate-800 pb-4">
          <CalendarRange className="w-5 h-5 text-teal-400" />
          <span>كشف حضور وخصومات الموظف: {selectedEmpForBreakdown.full_name}</span>
        </h3>

        {/* Attendance Stats Cards */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
          <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
            <span className="text-[10px] text-slate-500 block mb-1">أيام العمل المجدولة</span>
            <span className="text-sm font-black text-white">{selectedEmpForBreakdown.scheduledWorkDays} يوم</span>
          </div>
          <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
            <span className="text-[10px] text-emerald-400 block mb-1">الحضور والالتزام</span>
            <span className="text-sm font-black text-emerald-400">
              {selectedEmpForBreakdown.presentsCount} حضور 
              {selectedEmpForBreakdown.latesCount > 0 && ` (${selectedEmpForBreakdown.latesCount} متأخر)`}
              {selectedEmpForBreakdown.earlyExitsCount > 0 && ` (${selectedEmpForBreakdown.earlyExitsCount} خروج مبكر)`}
            </span>
          </div>
          <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
            <span className="text-[10px] text-amber-500 block mb-1">إجمالي غيابات الخصم</span>
            <span className="text-sm font-black text-amber-500">{selectedEmpForBreakdown.absencesCount} يوم</span>
          </div>
          <div className="bg-slate-950/40 border border-slate-850 p-3 rounded-2xl text-center">
            <span className="text-[10px] text-blue-400 block mb-1">إجازات معتمدة</span>
            <span className="text-sm font-black text-blue-400">{selectedEmpForBreakdown.paidLeavesCount} يوم</span>
          </div>
        </div>

        {/* Calculations logic breakdown card */}
        <div className="p-4 bg-teal-950/15 border border-teal-500/20 rounded-2xl space-y-2 mb-6">
          <span className="text-xs font-bold text-white flex items-center gap-1.5 mb-2">
            <Info className="w-4 h-4 text-teal-400" />
            <span>تفاصيل الاحتساب الجاري للخصم المعتمد:</span>
          </span>
          <div className="text-xs text-slate-350 space-y-1.5 leading-relaxed font-medium">
            <p>• أجرة اليوم الواحد = الراتب الأساسي ({selectedEmpForBreakdown.basic.toLocaleString()} د.ع) ÷ 30 = <span className="font-mono text-teal-400 font-bold">{Math.round(selectedEmpForBreakdown.basic / 30).toLocaleString()} د.ع/يوم</span></p>
            {selectedEmpForBreakdown.absencesCount > 0 && (
              <p>• خصم الغياب المطبق = {selectedEmpForBreakdown.absencesCount} أيام غياب × أجرة اليوم الكامل = <span className="font-mono text-amber-400 font-bold">{selectedEmpForBreakdown.absenceDeduction.toLocaleString()} د.ع</span></p>
            )}
            {selectedEmpForBreakdown.halfDaysCount > 0 && (
              <p>• خصم أنصاف الأيام = {selectedEmpForBreakdown.halfDaysCount} أيام × نصف أجرة يوم = <span className="font-mono text-amber-400 font-bold">{selectedEmpForBreakdown.halfDayDeduction.toLocaleString()} د.ع</span></p>
            )}
            {selectedEmpForBreakdown.totalLateMinutes > 0 && (
              <p>• خصم التأخير المطبق = {selectedEmpForBreakdown.totalLateMinutes} دقيقة تأخر × (أجرة اليوم ÷ 480 دقيقة) = <span className="font-mono text-amber-400 font-bold">{selectedEmpForBreakdown.latenessDeduction.toLocaleString()} د.ع</span></p>
            )}
            {selectedEmpForBreakdown.totalEarlyExitMinutes > 0 && (
              <p>• خصم الخروج المبكر المطبق = {selectedEmpForBreakdown.totalEarlyExitMinutes} دقيقة خروج مبكر × (أجرة اليوم ÷ 480 دقيقة) = <span className="font-mono text-amber-400 font-bold">{selectedEmpForBreakdown.earlyExitDeduction.toLocaleString()} د.ع</span></p>
            )}
            <p className="border-t border-slate-800 pt-2 font-bold text-white">
              • إجمالي خصومات الدوام والغياب المطبقة = <span className="font-mono text-teal-300 text-sm font-black">{selectedEmpForBreakdown.totalAttendanceDeductions.toLocaleString()} د.ع</span>
            </p>
          </div>
        </div>

        {/* Bonuses & Other Deductions Detailed Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
          {/* 1. قسم المكافآت والزيادات */}
          <div className="p-4 bg-emerald-950/20 border border-emerald-500/20 rounded-2xl">
            <div className="flex items-center justify-between mb-3 border-b border-emerald-500/10 pb-2">
              <span className="text-xs font-bold text-emerald-400 flex items-center gap-1.5">
                <TrendingUp className="w-4 h-4" />
                <span>المكافآت والزيادات ({selectedEmpForBreakdown.totalBonuses.toLocaleString()} د.ع)</span>
              </span>
              <button
                onClick={() => onAddAdjustment('bonus')}
                className="text-[10px] font-bold bg-emerald-500/10 hover:bg-emerald-500/20 text-emerald-400 px-2 py-0.5 rounded-lg border border-emerald-500/20 flex items-center gap-1 transition-all cursor-pointer"
              >
                <Plus className="w-3 h-3" />
                <span>إضافة مكافأة</span>
              </button>
            </div>

            {selectedEmpForBreakdown.bonusesList && selectedEmpForBreakdown.bonusesList.length > 0 ? (
              <div className="space-y-2 max-h-[140px] overflow-y-auto">
                {selectedEmpForBreakdown.bonusesList.map((b: BonusDeduction, idx: number) => (
                  <div key={idx} className="p-2 bg-slate-950/40 rounded-xl border border-emerald-500/10 text-xs flex justify-between items-start gap-2">
                    <div>
                      <div className="text-white font-bold">{b.reason || 'مكافأة تشجيعية'}</div>
                      <div className="text-[10px] text-slate-400 mt-0.5">التاريخ: {b.issue_date || '-'}</div>
                    </div>
                    <span className="font-mono text-emerald-400 font-bold text-xs shrink-0">
                      + {Number(b.amount).toLocaleString()} د.ع
                    </span>
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-center py-4 text-xs text-slate-500">
                لا توجد مكافآت مسجلة لهذا الموظف خلال هذه الدورة
              </div>
            )}
          </div>

          {/* 2. قسم الخصومات والجزاءات الإدارية */}
          <div className="p-4 bg-rose-950/20 border border-rose-500/20 rounded-2xl">
            <div className="flex items-center justify-between mb-3 border-b border-rose-500/10 pb-2">
              <span className="text-xs font-bold text-rose-400 flex items-center gap-1.5">
                <TrendingDown className="w-4 h-4" />
                <span>الخصومات والجزاءات ({((selectedEmpForBreakdown.totalDeductions || 0) - (selectedEmpForBreakdown.totalAttendanceDeductions || 0)).toLocaleString()} د.ع)</span>
              </span>
              <button
                onClick={() => onAddAdjustment('deduction')}
                className="text-[10px] font-bold bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 px-2 py-0.5 rounded-lg border border-rose-500/20 flex items-center gap-1 transition-all cursor-pointer"
              >
                <Plus className="w-3 h-3" />
                <span>إضافة خصم</span>
              </button>
            </div>

            {selectedEmpForBreakdown.otherDeductionsList && selectedEmpForBreakdown.otherDeductionsList.length > 0 ? (
              <div className="space-y-2 max-h-[140px] overflow-y-auto">
                {selectedEmpForBreakdown.otherDeductionsList.map((d: BonusDeduction, idx: number) => (
                  <div key={idx} className="p-2 bg-slate-950/40 rounded-xl border border-rose-500/10 text-xs flex justify-between items-start gap-2">
                    <div>
                      <div className="text-white font-bold">{d.reason || 'خصم إداري'}</div>
                      <div className="text-[10px] text-slate-400 mt-0.5">التاريخ: {d.issue_date || '-'}</div>
                    </div>
                    <span className="font-mono text-rose-400 font-bold text-xs shrink-0">
                      - {Number(d.amount).toLocaleString()} د.ع
                    </span>
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-center py-4 text-xs text-slate-500">
                لا توجد خصومات إدارية مسجلة لهذا الموظف خلال هذه الدورة
              </div>
            )}
          </div>
        </div>

        {/* 3. قسم خصومات أقساط السلف إذا وجدت */}
        {selectedEmpForBreakdown.loanDeduction > 0 && (
          <div className="p-3 bg-amber-950/20 border border-amber-500/20 rounded-2xl mb-6 flex justify-between items-center text-xs">
            <div className="flex items-center gap-2">
              <Banknote className="w-4 h-4 text-amber-400" />
              <span className="font-bold text-white">قسط السلفة المستحق لهذا الشهر:</span>
            </div>
            <span className="font-mono font-bold text-amber-400 text-sm">
              - {selectedEmpForBreakdown.loanDeduction.toLocaleString()} د.ع
            </span>
          </div>
        )}

        {/* Calendar logs list */}
        <h4 className="text-xs font-bold text-slate-400 mb-3 flex items-center justify-between">
          <span className="flex items-center gap-1">
            <Clock className="w-4 h-4" />
            <span>يوميات وسجلات الدورة المالية بالتفصيل (من {startDate} إلى {endDate}):</span>
          </span>
          <span className="text-[10px] text-amber-400 font-medium">
            * يمكنك الضغط على زر الإعفاء لإلغاء خصم غياب الموظف أو احتسابه يدوياً
          </span>
        </h4>
        
        <div className="overflow-y-auto max-h-[250px] border border-slate-800 rounded-2xl bg-slate-950/20 divide-y divide-slate-800/80">
          {selectedEmpForBreakdown.detailLogs.map((log: DetailLog, idx: number) => (
            <div key={idx} className="p-3 flex items-center justify-between text-xs hover:bg-slate-900/40 transition-colors">
              <div className="flex items-center gap-3">
                <span className="font-mono text-slate-400 font-semibold">{log.date}</span>
                <span className={`px-2 py-0.5 rounded-md font-bold text-[9px] ${
                  log.status.includes('حاضر') || log.status.includes('معفى') ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/15' :
                  log.status.includes('غياب') ? 'bg-rose-500/10 text-rose-400 border border-rose-500/15' :
                  log.status.includes('إجازة') ? 'bg-blue-500/10 text-blue-400 border border-blue-500/15' :
                  'bg-slate-800 text-slate-400'
                }`}>
                  {log.status}
                </span>
              </div>
              
              <div className="flex items-center gap-6">
                <span className="text-slate-400">
                  {log.time !== '-' ? `وقت البصمة: ${log.time}` : ''}
                </span>
                
                {log.isAbsenceDay ? (
                  <button
                    onClick={() => onToggleExcuse(log.date)}
                    className={`px-3 py-1 rounded-xl font-bold text-[10px] transition-all cursor-pointer ${
                      log.isExcused 
                        ? 'bg-rose-550/20 hover:bg-rose-550/30 text-rose-400 border border-rose-500/30' 
                        : 'bg-emerald-550/20 hover:bg-emerald-550/30 text-emerald-400 border border-emerald-500/30'
                    }`}
                  >
                    {log.isExcused ? 'إلغاء الإعفاء (احتساب غياب)' : 'إعفاء (إلغاء الخصم)'}
                  </button>
                ) : (
                  <span className="text-slate-500 text-[11px] font-medium min-w-[200px] text-left">
                    {log.note}
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>

        <div className="flex justify-between items-center pt-6 mt-6 border-t border-slate-800">
          <button 
            onClick={() => window.print()}
            className="px-4 py-2.5 bg-slate-800 hover:bg-slate-700 text-teal-300 rounded-xl text-xs font-bold transition-all border border-slate-700 flex items-center gap-2 cursor-pointer"
          >
            <Printer className="w-4 h-4" />
            <span>طباعة كشف راتب الموظف 📄</span>
          </button>
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
