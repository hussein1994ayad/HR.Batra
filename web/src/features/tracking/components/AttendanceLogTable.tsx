import { Clock, Download, Edit, LogOut } from 'lucide-react';
import { formatHours } from '../logic';
import type { AttendanceRow } from '../types';

type Props = {
  attendanceRows: AttendanceRow[];
  onExport: () => void;
  onEdit: (row: AttendanceRow) => void;
  onForceCheckout: (recordId: string) => void;
};

/** سجل الحضور والانصراف مع التعديل والخروج الإجباري والتصدير. */
export function AttendanceLogTable({ attendanceRows, onExport, onEdit, onForceCheckout }: Props) {
  return (
    <div className="mb-8">
      <div className="flex items-center justify-between mb-6">
        <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
          <Clock className="w-5 h-5 text-teal-400" />
          <span>سجل الحضور والانصراف المتقدم</span>
        </h3>
        <button
          onClick={onExport}
          className="flex items-center gap-2 py-2 px-4 bg-emerald-600 hover:bg-emerald-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-emerald-500/10 cursor-pointer"
        >
          <Download className="w-4 h-4" />
          <span className="hidden sm:inline">تصدير Excel</span>
        </button>
      </div>
      
      <div className="overflow-x-auto rounded-2xl border border-slate-800/60">
        <table className="w-full text-sm text-right">
          <thead className="bg-slate-900/80 text-slate-300 text-xs border-b border-slate-800/80">
            <tr>
              <th className="px-4 py-4 font-bold">اسم الموظف</th>
              <th className="px-4 py-4 font-bold">التاريخ</th>
              <th className="px-4 py-4 font-bold">وقت الدخول</th>
              <th className="px-4 py-4 font-bold">وقت الخروج</th>
              <th className="px-4 py-4 font-bold">ساعات العمل</th>
              <th className="px-4 py-4 font-bold text-center">الإجراءات</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-800/60 bg-slate-950/30">
            {attendanceRows.length === 0 ? (
              <tr>
                <td colSpan={6} className="px-4 py-12 text-center text-slate-500 text-xs">
                  لا توجد سجلات حضور لهذه الفترة
                </td>
              </tr>
            ) : (
              attendanceRows.map((log) => (
                <tr key={log.id} className={`hover:bg-slate-900/40 transition-colors ${log.is_virtual ? 'bg-rose-500/5' : ''}`}>
                  <td className="px-4 py-3 font-bold text-white text-xs flex items-center gap-2">
                    {log.employees?.full_name || 'موظف'}
                    {log.is_virtual && <span className="bg-rose-500/20 text-rose-400 text-[9px] px-1.5 py-0.5 rounded border border-rose-500/30">لم يبصم (غائب)</span>}
                  </td>
                  <td className="px-4 py-3 text-slate-400 text-xs font-mono">{log.work_date}</td>
                  <td className="px-4 py-3 text-emerald-400 text-xs font-mono">
                    {log.check_in_time ? new Date(log.check_in_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }) : '-'}
                  </td>
                  <td className="px-4 py-3 text-rose-400 text-xs font-mono">
                    {log.check_out_time ? new Date(log.check_out_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }) : '-'}
                  </td>
                  <td className="px-4 py-3 text-slate-300 text-xs font-bold">
                    {formatHours(log.check_in_time, log.check_out_time)}
                  </td>
                  <td className="px-4 py-3 flex items-center justify-center gap-2">
                    {!log.is_virtual && (
                      <>
                        <button
                          onClick={() => onEdit(log)}
                          className="p-1.5 bg-slate-800 hover:bg-slate-700 border border-slate-700 rounded-lg text-teal-400 transition-colors cursor-pointer"
                          title="تعديل وقت الدخول/الخروج"
                        >
                          <Edit className="w-3.5 h-3.5" />
                        </button>
                        {!log.check_out_time && (
                          <button
                            onClick={() => onForceCheckout(log.id)}
                            className="p-1.5 bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/20 rounded-lg text-rose-400 transition-colors cursor-pointer flex items-center gap-1"
                            title="تسجيل خروج إجباري الآن"
                          >
                            <LogOut className="w-3.5 h-3.5" />
                          </button>
                        )}
                      </>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
