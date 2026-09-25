'use client';

import type { Employee } from '@/lib/db-types';
import { Smartphone, Lock, Unlock, Trash2, Edit, FolderOpen } from 'lucide-react';

interface EmployeesTableProps {
  employees: Employee[];
  actionLoading: string | null;
  onOpenProfile: (emp: Employee) => void;
  onEdit: (emp: Employee) => void;
  onToggleLock: (emp: Employee) => void;
  onResetDevice: (emp: Employee) => void;
  onDelete: (emp: Employee) => void;
}

/** جدول الموظفين النشطين مع أزرار الملف والتعديل وقفل الجهاز والحذف. */
export function EmployeesTable({ employees, actionLoading, onOpenProfile, onEdit, onToggleLock, onResetDevice, onDelete }: EmployeesTableProps) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-right border-collapse">
        <thead>
          <tr className="border-b border-slate-800/80 text-slate-400 text-xs font-bold bg-slate-950/30">
            <th className="p-4">اسم الموظف الثلاثي</th>
            <th className="p-4">البريد الإلكتروني للعمل</th>
            <th className="p-4">رقم الهاتف</th>
            <th className="p-4">الرمز السري</th>
            <th className="p-4">الفرع الجغرافي</th>
            <th className="p-4">الدور / الصلاحية</th>
            <th className="p-4">الراتب الأساسي</th>
            <th className="p-4">ربط الهاتف وقفل الجهاز</th>
            <th className="p-4 text-left">إجراءات سريعة</th>
          </tr>
        </thead>
        <tbody>
          {employees.length === 0 ? (
            <tr>
              <td colSpan={9} className="p-8 text-center text-slate-500 text-xs">
                عذراً، لم نعثر على أي نتائج للبحث المكتوب.
              </td>
            </tr>
          ) : (
            employees.map((emp) => {
              const isLocked = emp.device_id_lock != null;
              const docCount = (emp.document_urls || []).length;
              return (
                <tr 
                  key={emp.id} 
                  className="border-b border-slate-800/40 hover:bg-slate-900/20 text-slate-300 text-xs transition-colors"
                >
                  <td className="p-4 font-bold text-white">
                    <button
                      onClick={() => onOpenProfile(emp)}
                      className="hover:text-teal-400 text-right cursor-pointer flex items-center gap-1.5 transition-colors"
                    >
                      <span>{emp.full_name}</span>
                      {docCount > 0 && (
                        <span className="text-[9px] px-1.5 py-0.5 bg-purple-500/20 border border-purple-500/30 text-purple-300 rounded-md font-mono">
                          {docCount} 📁
                        </span>
                      )}
                    </button>
                  </td>
                  <td className="p-4 font-mono text-slate-400">{emp.email}</td>
                  <td className="p-4 font-mono">{emp.phone || '-'}</td>
                  <td className="p-4 font-mono text-purple-400 bg-purple-500/10 rounded-lg px-2">{emp.plain_password || 'مخفي'}</td>
                  <td className="p-4 font-bold text-teal-400">{emp.branches?.name || '-'}</td>
                  <td className="p-4">
                    <span className={`px-2.5 py-0.5 rounded-full text-[9px] font-bold border ${
                      emp.role === 'admin' 
                        ? 'bg-rose-500/10 border-rose-500/20 text-rose-400' 
                        : emp.role === 'manager' 
                        ? 'bg-amber-500/10 border-amber-500/20 text-amber-400' 
                        : 'bg-blue-500/10 border-blue-500/20 text-blue-400'
                    }`}>
                      {emp.role === 'admin' ? 'مدير عام' : emp.role === 'manager' ? 'مدير موارد' : 'موظف'}
                    </span>
                  </td>
                  <td className="p-4 font-bold text-slate-200">
                    {emp.monthly_salary_iqd ? emp.monthly_salary_iqd.toLocaleString() : '0'} د.ع
                  </td>
                  <td className="p-4">
                    <div className="flex items-center gap-2">
                      {isLocked ? (
                        <span className="flex items-center gap-1 text-emerald-400 bg-emerald-500/10 border border-emerald-500/20 px-2 py-0.5 rounded-md font-bold text-[9px]">
                          <Lock className="w-3 h-3" />
                          <span>مربوط ومقفل</span>
                        </span>
                      ) : (
                        <span className="flex items-center gap-1 text-slate-400 bg-slate-800/50 border border-slate-700/30 px-2 py-0.5 rounded-md text-[9px]">
                          <Unlock className="w-3 h-3" />
                          <span>غير مربوط حالياً</span>
                        </span>
                      )}
                    </div>
                  </td>
                  <td className="p-4 text-left">
                    <div className="flex justify-end gap-2">
                      <button
                        onClick={() => onOpenProfile(emp)}
                        className="flex items-center gap-1.5 px-3 py-2 bg-purple-500/10 border border-purple-500/20 text-purple-400 hover:bg-purple-500/20 rounded-lg transition-all cursor-pointer font-bold text-[10px]"
                        title="عرض الملف الشامل والوثائق والمستمسكات"
                      >
                        <FolderOpen className="w-3.5 h-3.5" />
                        <span>الملف والوثائق</span>
                      </button>

                      <button
                        onClick={() => onEdit(emp)}
                        className="flex items-center gap-1.5 px-3 py-2 bg-blue-500/10 border border-blue-500/20 text-blue-400 hover:bg-blue-500/20 rounded-lg transition-all cursor-pointer font-bold text-[10px]"
                        title="تعديل بيانات، راتب، وصلاحيات الموظف"
                      >
                        <Edit className="w-3.5 h-3.5" />
                        <span>تعديل</span>
                      </button>

                      <button
                        disabled={actionLoading === emp.id}
                        onClick={() => onToggleLock(emp)}
                        className={`p-2 rounded-lg border transition-all cursor-pointer ${
                          isLocked 
                            ? 'bg-amber-500/10 border-amber-500/20 text-amber-400 hover:bg-amber-500/20' 
                            : 'bg-teal-500/10 border-teal-500/20 text-teal-400 hover:bg-teal-500/20'
                        }`}
                        title={isLocked ? 'فك قفل الجهاز مؤقتاً' : 'تفعيل قفل الهاتف الافتراضي'}
                      >
                        {isLocked ? <Unlock className="w-4 h-4" /> : <Lock className="w-4 h-4" />}
                      </button>

                      {isLocked && (
                        <button
                          disabled={actionLoading === emp.id + '_reset'}
                          onClick={() => onResetDevice(emp)}
                          className="p-2 bg-red-500/10 hover:bg-red-500/20 border border-red-500/20 text-red-400 rounded-lg transition-all cursor-pointer"
                          title="إلغاء وربط هاتف جديد للموظف"
                        >
                          <Smartphone className="w-4 h-4" />
                        </button>
                      )}

                      <button
                        disabled={actionLoading === emp.id}
                        onClick={() => onDelete(emp)}
                        className="p-2 bg-red-500/10 hover:bg-red-500/25 border border-red-500/20 text-red-400 rounded-lg transition-all cursor-pointer"
                        title="حذف أو أرشفة الموظف"
                      >
                        <Trash2 className="w-4 h-4" />
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
