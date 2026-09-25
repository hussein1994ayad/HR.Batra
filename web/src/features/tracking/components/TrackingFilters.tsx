import { Building2, Calendar as CalendarIcon, MapPin, RefreshCw, Users } from 'lucide-react';
import type { Branch } from '@/lib/db-types';
import type { TrackedEmployee } from '../types';

type Props = {
  branches: Branch[];
  employees: TrackedEmployee[];
  selectedBranch: string;
  selectedEmployee: string;
  startDate: string;
  endDate: string;
  onBranchChange: (branchId: string) => void;
  onEmployeeChange: (employeeId: string) => void;
  onStartDateChange: (date: string) => void;
  onEndDateChange: (date: string) => void;
  onRefresh: () => void;
  onManualAttendance: () => void;
};

/** العنوان وفلاتر الفرع والفترة والموظف وزر الحضور اليدوي. */
export function TrackingFilters({
  branches, employees, selectedBranch, selectedEmployee, startDate, endDate,
  onBranchChange, onEmployeeChange, onStartDateChange, onEndDateChange, onRefresh, onManualAttendance,
}: Props) {
  return (
    <>
      {/* Header controller */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 mb-6">
        <div>
          <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
            <MapPin className="w-5 h-5 text-teal-400" />
            <span>مراقبة وإدارة الانضباط الوظيفي اليومي</span>
          </h3>
          <p className="text-[11px] text-slate-400">مراقبة وتسجيل حضور وانصراف الموظفين جغرافياً مع اتخاذ قرارات خصم الغيابات والتأخير يدوياً</p>
        </div>

        <div className="flex flex-col sm:flex-row items-center gap-3">
          <div className="flex items-center gap-2 bg-slate-800/60 border border-slate-700/60 rounded-xl px-3 py-2">
            <Building2 className="w-4 h-4 text-teal-400" />
            <select 
              value={selectedBranch}
              onChange={(e) => onBranchChange(e.target.value)}
              className="bg-transparent border-none text-white text-xs outline-none cursor-pointer min-w-[120px]"
            >
              <option value="all" className="bg-slate-900">جميع الفروع</option>
              {branches.map(b => (
                <option key={b.id} value={b.id} className="bg-slate-900">{b.name}</option>
              ))}
            </select>
          </div>

          <div className="flex items-center gap-2 bg-slate-800/60 border border-slate-700/60 rounded-xl px-3 py-2">
            <CalendarIcon className="w-4 h-4 text-teal-400" />
            <span className="text-[10px] text-slate-400 font-bold">من</span>
            <input 
              type="date" 
              value={startDate}
              onChange={(e) => onStartDateChange(e.target.value)}
              className="bg-transparent border-none text-white text-xs outline-none cursor-pointer"
            />
          </div>

          <div className="flex items-center gap-2 bg-slate-800/60 border border-slate-700/60 rounded-xl px-3 py-2">
            <CalendarIcon className="w-4 h-4 text-amber-400" />
            <span className="text-[10px] text-slate-400 font-bold">إلى</span>
            <input 
              type="date" 
              value={endDate}
              onChange={(e) => onEndDateChange(e.target.value)}
              className="bg-transparent border-none text-white text-xs outline-none cursor-pointer"
            />
          </div>

          <div className="flex items-center gap-2 bg-slate-800/60 border border-slate-700/60 rounded-xl px-3 py-2">
            <Users className="w-4 h-4 text-violet-400" />
            <select
              value={selectedEmployee}
              onChange={(e) => onEmployeeChange(e.target.value)}
              className="bg-transparent border-none text-white text-xs outline-none appearance-none cursor-pointer min-w-[80px]"
            >
              <option value="all" className="bg-slate-900">جميع الموظفين</option>
              {employees.filter(emp => selectedBranch === 'all' || emp.branch_id === selectedBranch).map(emp => (
                <option key={emp.id} value={emp.id} className="bg-slate-900">{emp.full_name}</option>
              ))}
            </select>
          </div>
          
          <button
            onClick={onRefresh}
            className="flex items-center gap-2 py-2 px-4 bg-slate-800 hover:bg-slate-750 text-white rounded-xl text-xs font-bold transition-all border border-slate-700/60 cursor-pointer"
          >
            <RefreshCw className="w-4 h-4" />
            <span className="hidden sm:inline">تحديث</span>
          </button>

          <button
            onClick={onManualAttendance}
            className="flex items-center gap-2 py-2 px-4 bg-teal-600 hover:bg-teal-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/10 cursor-pointer"
          >
            <Users className="w-4 h-4" />
            <span>تسجيل حضور يدوي</span>
          </button>
        </div>
      </div>
    </>
  );
}
