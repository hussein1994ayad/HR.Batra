'use client';

import type { Branch } from '@/lib/db-types';
import { Building, Plus, Trash2, Edit } from 'lucide-react';

interface BranchListProps {
  branches: Branch[];
  selectedBranchId: string | null;
  actionLoading: string | null;
  onAdd: () => void;
  onSelect: (branchId: string) => void;
  onEdit: (branch: Branch) => void;
  onDelete: (branchId: string) => void;
}

/** قائمة الفروع مع التحديد والتعديل والحذف. */
export function BranchList({ branches, selectedBranchId, actionLoading, onAdd, onSelect, onEdit, onDelete }: BranchListProps) {
  return (
    <div className="lg:col-span-1 bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6 flex flex-col justify-between">
      <div className="space-y-6">
        <div className="flex justify-between items-center">
          <div>
            <h3 className="text-sm font-extrabold text-white flex items-center gap-2">
              <Building className="w-5 h-5 text-teal-400" />
              <span>الفروع الجغرافية المعتمدة ({branches.length})</span>
            </h3>
            <p className="text-[10px] text-slate-500">إضافة وتعديل فروع الشركة وحدود بصماتها</p>
          </div>
          <button
            onClick={onAdd}
            className="p-2 bg-teal-650 hover:bg-teal-600 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/10 cursor-pointer"
            title="إضافة فرع جديد"
          >
            <Plus className="w-4 h-4" />
          </button>
        </div>

        <div className="space-y-4 max-h-[380px] overflow-y-auto pr-1">
          {branches.length === 0 ? (
            <div className="text-center py-8 text-slate-500 text-xs">
              لم يتم إضافة أي فروع جغرافية للشركة بعد.
            </div>
          ) : (
            branches.map((b) => (
              <div 
                key={b.id} 
                onClick={() => onSelect(b.id)}
                className={`p-4 border rounded-2xl flex items-center justify-between transition-all text-right cursor-pointer ${
                  selectedBranchId === b.id 
                    ? 'bg-teal-950/20 border-teal-500/50 shadow-md shadow-teal-500/5' 
                    : 'bg-slate-950/40 border-slate-850 hover:border-slate-800'
                }`}
              >
                <div className="space-y-1 min-w-[65%]">
                  <span className="text-xs font-bold text-white block truncate">{b.name}</span>
                  <span className="text-[10px] text-slate-400 block truncate">{b.address || 'لا يوجد عنوان نصي'}</span>
                  <span className="text-[9px] text-teal-400 block font-mono">
                    مدى البصمة: {b.radius_meters} متر
                  </span>
                </div>
                <div className="flex gap-2">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onEdit(b);
                    }}
                    className="p-2 bg-blue-500/15 border border-blue-500/20 text-blue-400 hover:bg-blue-500/25 rounded-lg transition-colors cursor-pointer"
                    title="تعديل الفرع"
                  >
                    <Edit className="w-4 h-4" />
                  </button>
                  <button
                    disabled={actionLoading === b.id + '_delete'}
                    onClick={(e) => {
                      e.stopPropagation();
                      onDelete(b.id);
                    }}
                    className="p-2 bg-red-500/15 border border-red-500/20 text-red-400 hover:bg-red-500/25 rounded-lg transition-colors cursor-pointer"
                    title="حذف الفرع نهائياً"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </div>

      <div className="pt-6 border-t border-slate-900 mt-6 bg-slate-950/20 p-4 rounded-2xl border border-slate-900">
        <span className="text-[10px] text-slate-400 block leading-relaxed text-right">
          📢 <strong>ملاحظة هامة:</strong> النطاق الجغرافي (مدى البصمة بالامتار) يمثل دائرة قطرها يحيط بموقع الفرع. لن يتمكن الموظف التابع لهذا الفرع من تسجيل حضوره أو انصرافه عبر التطبيق إلا إذا كان متواجداً جغرافياً داخل هذا النطاق وبإنترنت فعال.
        </span>
      </div>
    </div>
  );
}
