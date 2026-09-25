'use client';

import type { ArchivedEmployee } from '@/lib/db-types';
import { daysUntil } from '../logic';

interface ArchivedEmployeesTableProps {
  archivedEmployees: ArchivedEmployee[];
  actionLoading: string | null;
  onRestore: (record: ArchivedEmployee) => void;
  onDestroy: (record: ArchivedEmployee) => void;
}

/** الموظفون المؤرشفون والمجدول حذفهم، مع الاستعادة أو الإتلاف النهائي. */
export function ArchivedEmployeesTable({ archivedEmployees, actionLoading, onRestore, onDestroy }: ArchivedEmployeesTableProps) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-right border-collapse">
        <thead>
          <tr className="border-b border-slate-800/80 text-slate-400 text-xs font-bold bg-slate-950/30">
            <th className="p-4">اسم الموظف الثلاثي</th>
            <th className="p-4">رمز الموظف</th>
            <th className="p-4">طريقة الإجراء</th>
            <th className="p-4">سبب الإجراء والبيان</th>
            <th className="p-4">حذف مجدول في</th>
            <th className="p-4">تاريخ الأرشفة</th>
            <th className="p-4 text-left">إجراءات استعادة / إتلاف</th>
          </tr>
        </thead>
        <tbody>
          {archivedEmployees.length === 0 ? (
            <tr>
              <td colSpan={7} className="p-8 text-center text-slate-500 text-xs">
                لا يوجد أي موظف في قائمة الأرشيف حالياً. 🗃️
              </td>
            </tr>
          ) : (
            archivedEmployees.map((arch) => {
              const expiryDate = arch.scheduled_deletion_date ? new Date(arch.scheduled_deletion_date) : null;
              const daysLeft = arch.scheduled_deletion_date ? daysUntil(arch.scheduled_deletion_date) : null;

              return (
                <tr 
                  key={arch.id} 
                  className="border-b border-slate-800/40 hover:bg-slate-900/20 text-slate-300 text-xs transition-colors"
                >
                  <td className="p-4 font-bold text-white">{arch.full_name}</td>
                  <td className="p-4 font-mono text-slate-400">{arch.employee_code || '-'}</td>
                  <td className="p-4">
                    <span className={`px-2.5 py-0.5 rounded-full text-[9px] font-bold border ${
                      arch.archive_type === 'permanent' 
                        ? 'bg-red-500/10 border-red-500/20 text-red-400' 
                        : arch.archive_type === 'scheduled_deletion' 
                        ? 'bg-amber-500/10 border-amber-500/20 text-amber-400 animate-pulse' 
                        : 'bg-blue-500/10 border-blue-500/20 text-blue-400'
                    }`}>
                      {arch.archive_type === 'permanent' 
                        ? 'إتلاف نهائي' 
                        : arch.archive_type === 'scheduled_deletion' 
                        ? 'حذف مجدول بعد 30 يوماً' 
                        : 'أرشفة مؤقتة'}
                    </span>
                  </td>
                  <td className="p-4 max-w-xs truncate" title={arch.archive_reason ?? undefined}>{arch.archive_reason || '-'}</td>
                  <td className="p-4 font-mono">
                    {expiryDate ? (
                      <span className="text-amber-400 font-bold">
                        {expiryDate.toLocaleDateString('ar-IQ')} ({daysLeft} يوم متبقي)
                      </span>
                    ) : '-'}
                  </td>
                  <td className="p-4 text-slate-400 font-mono">
                    {new Date(arch.archived_at).toLocaleDateString('ar-IQ')}
                  </td>
                  <td className="p-4 text-left">
                    <div className="flex justify-end gap-2">
                      {arch.archive_type !== 'permanent' && (
                        <button
                          type="button"
                          disabled={actionLoading === 'restore_' + arch.id}
                          onClick={() => onRestore(arch)}
                          className="flex items-center gap-1 px-3 py-1.5 bg-teal-600/20 hover:bg-teal-600/30 border border-teal-500/30 text-teal-400 rounded-xl transition-all cursor-pointer font-bold text-[10px]"
                        >
                          <span>إعادة تفعيل الحساب</span>
                        </button>
                      )}
                      <button
                        type="button"
                        disabled={actionLoading === 'perm_del_' + arch.id}
                        onClick={() => onDestroy(arch)}
                        className="flex items-center gap-1 px-3 py-1.5 bg-red-500/15 hover:bg-red-500/25 border border-red-500/20 text-red-400 rounded-xl transition-all cursor-pointer font-bold text-[10px]"
                      >
                        <span>إتلاف قطعي</span>
                      </button>
                    </div>
                  </td>
                </tr>
              );
            })
          )}
        </tbody>
      </table>
    </div>
  );
}
