import { Archive, Bell, Building, CheckCircle, Loader2, Printer, Search } from 'lucide-react';
import type { Branch } from '@/lib/db-types';

type Props = {
  searchTerm: string;
  onSearchChange: (value: string) => void;
  selectedBranch: string;
  onBranchChange: (branchId: string) => void;
  branches: Pick<Branch, 'id' | 'name'>[];
  selectedMonth: string;
  isMonthArchived: boolean;
  sendingNotifs: boolean;
  archiving: boolean;
  onOpenBulk: () => void;
  onSendBranchNotifications: () => void;
  onArchiveMonth: () => void;
};

/** البحث وفلتر الفرع وأزرار الاعتماد الجماعي والإشعار والطباعة والأرشفة. */
export function PayrollToolbar({
  searchTerm, onSearchChange, selectedBranch, onBranchChange, branches, selectedMonth, isMonthArchived,
  sendingNotifs, archiving, onOpenBulk, onSendBranchNotifications, onArchiveMonth,
}: Props) {
  return (
    <div className="flex flex-col md:flex-row justify-between gap-4 mb-6 print:hidden">
      <div className="flex items-center gap-3 print:hidden">
        <div className="relative">
          <input
            type="text"
            placeholder="ابحث باسم الموظف..."
            value={searchTerm}
            onChange={(e) => onSearchChange(e.target.value)}
            className="w-full sm:w-64 bg-slate-950/80 border border-slate-800 focus:border-teal-500 focus:ring-1 focus:ring-teal-500 rounded-2xl py-2 px-4 pr-10 text-xs text-white placeholder-slate-500 outline-none transition-all"
          />
          <Search className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
        </div>
        
        <div className="flex items-center gap-2 bg-slate-950/80 border border-slate-800 rounded-2xl px-3 py-2">
          <Building className="w-4 h-4 text-teal-400" />
          <select 
            value={selectedBranch}
            onChange={(e) => onBranchChange(e.target.value)}
            className="bg-transparent border-none text-white text-xs outline-none cursor-pointer"
          >
            <option value="all" className="bg-slate-900">جميع الفروع</option>
            {branches.map(b => (
              <option key={b.id} value={b.id} className="bg-slate-900">{b.name}</option>
            ))}
          </select>
        </div>
      </div>
      
      <div className="flex items-center gap-3 print:hidden">
        {!isMonthArchived && selectedBranch !== 'all' && (
          <>
            <button
              onClick={onOpenBulk}
              className="flex items-center justify-center gap-2 py-2 px-4 bg-teal-650 hover:bg-teal-600 text-white rounded-2xl text-xs font-bold transition-all cursor-pointer active:scale-95"
            >
              <CheckCircle className="w-4 h-4" />
              <span>اعتماد رواتب الفرع لشهر {selectedMonth}</span>
            </button>
            <button
              onClick={onSendBranchNotifications}
              disabled={sendingNotifs}
              className="flex items-center justify-center gap-2 py-2 px-4 bg-blue-600 hover:bg-blue-500 disabled:bg-blue-800 text-white rounded-2xl text-xs font-bold transition-all cursor-pointer active:scale-95"
            >
              {sendingNotifs ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <Bell className="w-4 h-4" />
              )}
              <span>إرسال إشعار للفرع</span>
            </button>
          </>
        )}

        <button 
          onClick={() => window.print()}
          className="flex items-center justify-center gap-2 py-2 px-4 bg-slate-800 hover:bg-slate-700 border border-slate-700 text-white rounded-2xl text-xs font-bold transition-all cursor-pointer"
        >
          <Printer className="w-4 h-4" />
          <span>طباعة مسودة كشف الرواتب</span>
        </button>

        {isMonthArchived ? (
          <div className="flex items-center gap-1.5 px-3 py-2 bg-purple-500/10 border border-purple-500/20 text-purple-400 rounded-2xl font-bold text-xs select-none">
            <Archive className="w-4 h-4" />
            <span>مؤرشف ومغلق مالياً 📦</span>
          </div>
        ) : (
          <button 
            onClick={onArchiveMonth}
            disabled={archiving}
            className="flex items-center justify-center gap-2 py-2 px-4 bg-purple-650 hover:bg-purple-600 disabled:bg-purple-800 text-white rounded-2xl text-xs font-bold transition-all cursor-pointer active:scale-95"
            title="أرشفة وحذف سجلات الدوام التفصيلية لهذا الشهر بشكل نهائي"
          >
            {archiving ? (
              <Loader2 className="w-4 h-4 animate-spin" />
            ) : (
              <Archive className="w-4 h-4" />
            )}
            <span>أرشفة وإغلاق الشهر 📦</span>
          </button>
        )}
      </div>
    </div>
  );
}
