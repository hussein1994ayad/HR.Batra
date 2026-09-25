'use client';

import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { PROTECTED_LEAVE_TYPES, addLeaveType } from '../logic';
import type { LeaveType, SystemPolicies } from '../types';
import { CalendarRange, Trash2, Plus } from 'lucide-react';

interface LeavePolicyCardProps {
  defaultAnnual: number;
  defaultSick: number;
  leaveTypes: LeaveType[];
  onChange: (patch: Partial<SystemPolicies>) => void;
}

/** الأرصدة الافتراضية للإجازات وأنواعها المتاحة. */
export function LeavePolicyCard({ defaultAnnual, defaultSick, leaveTypes, onChange }: LeavePolicyCardProps) {
  const [newLeaveTypeId, setNewLeaveTypeId] = useState('');
  const [newLeaveTypeName, setNewLeaveTypeName] = useState('');

  const handleAddLeaveType = (e: React.MouseEvent) => {
    e.preventDefault();
    const result = addLeaveType(leaveTypes, newLeaveTypeId, newLeaveTypeName);
    if ('error' in result) {
      if (result.duplicate) toast(result.error);
      else toast.error(result.error);
      return;
    }
    onChange({ leaveTypes: result.types });
    setNewLeaveTypeId('');
    setNewLeaveTypeName('');
  };

  const handleRemoveLeaveType = (idToRemove: string) => {
    if (PROTECTED_LEAVE_TYPES.includes(idToRemove)) {
      toast.error('لا يمكن حذف الإجازة السنوية أو المرضية الافتراضية لأنها مرتبطة بنظام الرواتب والأرصدة');
      return;
    }
    onChange({ leaveTypes: leaveTypes.filter(t => t.id !== idToRemove) });
  };

  return (
    <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
      <div className="flex items-center gap-2 text-teal-400 pb-3 border-b border-slate-850">
        <CalendarRange className="w-5 h-5" />
        <h4 className="text-sm font-extrabold text-white">إعدادات سياسات وأرصدة الإجازات العامة</h4>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <label className="block text-xs text-slate-400 mb-1 font-bold">
            <span>رصيد الإجازات السنوية الافتراضي (للموظفين الجدد)</span>
          </label>
          <div className="flex gap-2">
            <input
              type="number"
              required
              value={defaultAnnual}
              onChange={(e) => onChange({ defaultAnnual: Number(e.target.value) })}
              className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-sm text-white font-bold outline-none text-left"
              dir="ltr"
            />
            <span className="bg-slate-800 border border-slate-700 px-4 py-3 rounded-xl text-xs text-slate-300 font-bold flex items-center">يوم/سنة</span>
          </div>
        </div>

        <div>
          <label className="block text-xs text-slate-400 mb-1 font-bold">
            <span>رصيد الإجازات المرضية الافتراضي (للموظفين الجدد)</span>
          </label>
          <div className="flex gap-2">
            <input
              type="number"
              required
              value={defaultSick}
              onChange={(e) => onChange({ defaultSick: Number(e.target.value) })}
              className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-sm text-white font-bold outline-none text-left"
              dir="ltr"
            />
            <span className="bg-slate-800 border border-slate-700 px-4 py-3 rounded-xl text-xs text-slate-300 font-bold flex items-center">يوم/سنة</span>
          </div>
        </div>
      </div>

      <div className="space-y-4">
        <h5 className="text-xs font-bold text-slate-300">أنواع الإجازات المتاحة وتصنيفاتها:</h5>
        
        <div className="flex flex-wrap gap-2.5 p-4 bg-slate-950/40 border border-slate-850 rounded-2xl">
          {leaveTypes.length === 0 ? (
            <span className="text-xs text-slate-500">لا توجد أنواع إجازات مضافة</span>
          ) : (
            leaveTypes.map((type) => (
              <div 
                key={type.id} 
                className="flex items-center gap-2 px-3 py-1.5 bg-slate-900 border border-slate-800 hover:border-slate-700 text-xs text-slate-200 rounded-xl transition-all"
              >
                <span className="font-bold">{type.name}</span>
                <span className="text-[10px] text-slate-500 font-mono">({type.id})</span>
                {!PROTECTED_LEAVE_TYPES.includes(type.id) && (
                  <button
                    type="button"
                    onClick={() => handleRemoveLeaveType(type.id)}
                    className="text-slate-500 hover:text-rose-400 transition-colors p-0.5 rounded cursor-pointer"
                    title="حذف هذا النوع"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </button>
                )}
              </div>
            ))
          )}
        </div>

        {/* Add leave type form */}
        <div className="bg-slate-950/20 border border-slate-850 p-4 rounded-2xl space-y-4">
          <span className="text-[11px] font-bold text-slate-400 block">إضافة نوع إجازة مخصص جديد:</span>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 items-end">
            <div>
              <label className="block text-[10px] text-slate-400 mb-1">اسم الإجازة بالعربية</label>
              <input
                type="text"
                placeholder="مثال: إجازة زواج"
                value={newLeaveTypeName}
                onChange={(e) => setNewLeaveTypeName(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none"
              />
            </div>
            <div>
              <label className="block text-[10px] text-slate-400 mb-1">رمز فريد للإجازة (بالإنجليزي)</label>
              <input
                type="text"
                placeholder="مثال: marriage_leave"
                value={newLeaveTypeId}
                onChange={(e) => setNewLeaveTypeId(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white outline-none text-left font-mono"
                dir="ltr"
              />
            </div>
            <button
              type="button"
              onClick={handleAddLeaveType}
              className="flex items-center justify-center gap-1.5 py-2.5 px-4 bg-teal-650/20 hover:bg-teal-650/40 border border-teal-500/30 text-teal-400 rounded-xl text-xs font-bold transition-all cursor-pointer"
            >
              <Plus className="w-4 h-4" />
              <span>أضف للقائمة</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
