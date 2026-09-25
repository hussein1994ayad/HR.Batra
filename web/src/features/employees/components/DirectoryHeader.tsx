'use client';

import type { BranchOption } from '../types';
import { Users, Search, Plus, Building } from 'lucide-react';

interface DirectoryHeaderProps {
  branches: BranchOption[];
  searchTerm: string;
  selectedBranch: string;
  onSearchChange: (value: string) => void;
  onBranchChange: (branchId: string) => void;
  onAdd: () => void;
}

/** عنوان الدليل مع البحث وفلتر الفرع وزر الإضافة. */
export function DirectoryHeader({ branches, searchTerm, selectedBranch, onSearchChange, onBranchChange, onAdd }: DirectoryHeaderProps) {
  return (
    <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
      <div>
        <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
          <Users className="w-5 h-5 text-teal-400" />
          <span>دليل موظفي المؤسسة وإدارة الهواتف</span>
        </h3>
        <p className="text-[11px] text-slate-400">تحديث وتعديل الموظفين، وقرنهم بالفروع والأقسام كلياً</p>
      </div>

      <div className="flex flex-col sm:flex-row gap-3 items-center w-full lg:w-auto flex-1 max-w-2xl justify-end">
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <input
            type="text"
            placeholder="ابحث بالاسم، الكود، البريد، الهاتف، الفرع..."
            value={searchTerm}
            onChange={(e) => onSearchChange(e.target.value)}
            className="w-full bg-slate-950/80 border border-slate-800 focus:border-teal-500 focus:ring-1 focus:ring-teal-500 rounded-2xl py-2.5 px-4 pr-10 text-xs text-white placeholder-slate-500 transition-all outline-none animate-glass"
          />
          <Search className="absolute right-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500" />
        </div>

        <div className="flex items-center gap-2 bg-slate-950/80 border border-slate-800 rounded-2xl px-3 py-2.5 min-w-[140px]">
          <Building className="w-4 h-4 text-teal-400" />
          <select 
            value={selectedBranch}
            onChange={(e) => onBranchChange(e.target.value)}
            className="bg-transparent border-none text-white text-xs outline-none cursor-pointer w-full"
          >
            <option value="all" className="bg-slate-900">جميع الفروع</option>
            {branches.map(b => (
              <option key={b.id} value={b.id} className="bg-slate-900">{b.name}</option>
            ))}
          </select>
        </div>

        <button
          type="button"
          onClick={onAdd}
          className="flex items-center gap-1.5 py-2.5 px-4 bg-teal-600 hover:bg-teal-500 text-white rounded-2xl text-xs font-bold transition-all shadow-md shadow-teal-500/10 cursor-pointer whitespace-nowrap active:scale-95"
        >
          <Plus className="w-4 h-4" />
          <span>إضافة موظف جديد</span>
        </button>
      </div>
    </div>
  );
}
