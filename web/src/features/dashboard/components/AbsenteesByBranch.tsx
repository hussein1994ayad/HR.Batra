'use client';

import type { Branch } from '@/lib/db-types';
import { groupAbsenteesByBranch } from '../logic';
import type { EmployeeSummary } from '../types';
import { Users, MapPin, AlertTriangle, CheckCircle } from 'lucide-react';

interface AbsenteesByBranchProps {
  absentList: EmployeeSummary[];
  branches: Pick<Branch, 'id' | 'name'>[];
  absentCount: number;
}

/** غائبو اليوم مجمّعون حسب الفرع (مع مجموعة لمن ليس له فرع). */
export function AbsenteesByBranch({ absentList, branches, absentCount }: AbsenteesByBranchProps) {
  return (
    <div id="absent-section" className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl scroll-mt-24">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
            <AlertTriangle className="w-5 h-5 text-rose-500" />
            <span>قائمة غيابات اليوم (لم يسجلوا بصمة)</span>
          </h3>
          <p className="text-[11px] text-slate-400">قائمة بالموظفين الذين لم يسجلوا دخولهم اليوم وغير مجازين، مقسمة حسب الفروع</p>
        </div>
        <div className="px-3 py-1 bg-rose-500/10 border border-rose-500/20 text-rose-400 rounded-full text-[10px] font-bold">
          {absentCount} غائب
        </div>
      </div>

      {absentList.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-10 bg-slate-950/30 rounded-2xl border border-slate-800/40">
          <CheckCircle className="w-12 h-12 text-emerald-500/40 mb-3" />
          <span className="text-sm font-bold text-slate-300">الجميع حاضرون!</span>
          <span className="text-xs text-slate-500">لا يوجد غيابات مسجلة لهذا اليوم.</span>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {groupAbsenteesByBranch(absentList, branches).map(group => (
            <div key={group.key} className="bg-slate-950/50 border border-slate-800/60 rounded-2xl overflow-hidden flex flex-col">
              <div className="bg-slate-900 px-4 py-3 border-b border-slate-800/60 flex justify-between items-center">
                <span className="font-bold text-sm text-white flex items-center gap-2">
                  <MapPin className={`w-4 h-4 ${group.assigned ? 'text-blue-400' : 'text-slate-400'}`} />
                  {group.name}
                </span>
                <span className="bg-rose-500/20 text-rose-400 text-[10px] font-bold px-2 py-0.5 rounded-md">
                  {group.employees.length} غائب
                </span>
              </div>
              <div className="p-2 space-y-1 overflow-y-auto max-h-[250px] custom-scrollbar">
                {group.employees.map(emp => (
                  <div key={emp.id} className="px-3 py-2 bg-slate-900/30 rounded-lg border border-slate-800/30 flex items-center gap-3 hover:bg-slate-800/50 transition-colors">
                    <div className="w-8 h-8 rounded-full bg-slate-800 flex items-center justify-center text-slate-400 border border-slate-700/50 shrink-0">
                      <Users className="w-4 h-4" />
                    </div>
                    <div className="min-w-0">
                      <p className="text-xs font-bold text-slate-200 truncate">{emp.full_name}</p>
                      <p className="text-[10px] text-slate-500">غير متواجد حالياً</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
