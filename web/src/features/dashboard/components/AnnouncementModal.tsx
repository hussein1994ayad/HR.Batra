'use client';

import React, { useState } from 'react';
import type { Branch } from '@/lib/db-types';
import type { AnnouncementTarget, EmployeeSummary } from '../types';
import { Loader2 } from 'lucide-react';

interface AnnouncementModalProps {
  branches: Pick<Branch, 'id' | 'name'>[];
  employeesList: EmployeeSummary[];
  actionLoading: boolean;
  onClose: () => void;
  onSubmit: (target: AnnouncementTarget, text: string) => void;
}

/** بث تعميم إداري للكل أو لفرع أو لموظفين محددين. */
export function AnnouncementModal({ branches, employeesList, actionLoading, onClose, onSubmit }: AnnouncementModalProps) {
  const [announcement, setAnnouncement] = useState('');
  const [targetType, setTargetType] = useState<AnnouncementTarget['type']>('all');
  const [targetBranchId, setTargetBranchId] = useState('');
  const [targetEmployeeIds, setTargetEmployeeIds] = useState<string[]>([]);
  const [empSearchTerm, setEmpSearchTerm] = useState('');

  const handlePostAnnouncement = (e: React.FormEvent) => {
    e.preventDefault();
    const target: AnnouncementTarget =
      targetType === 'branch' ? { type: 'branch', branchId: targetBranchId }
        : targetType === 'employee' ? { type: 'employee', employeeIds: targetEmployeeIds }
          : { type: 'all' };
    onSubmit(target, announcement);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm overflow-y-auto">
      <div className="relative w-full max-w-lg bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden my-8 animate-glass text-right">
        <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-blue-500 to-teal-500"></div>
        
        <h3 className="text-lg font-bold text-white mb-6 flex items-center gap-2">
          <span>بث تعميم وإعلان إداري هام 📢</span>
        </h3>
        
        <form onSubmit={handlePostAnnouncement} className="space-y-4">
          
          {/* Target Type Selector */}
          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold block text-right">المستلمون المستهدفون (نطاق الإرسال)</label>
            <select
              value={targetType}
              onChange={(e) => setTargetType(e.target.value as AnnouncementTarget['type'])}
              className="w-full bg-slate-950 border border-slate-850 text-white rounded-xl p-3 text-xs focus:border-blue-500 outline-none"
            >
              <option value="all">📢 الكل (جميع موظفي الشركة)</option>
              <option value="branch">🏢 موظفي فرع معين</option>
              <option value="employee">👤 موظفين محددين (شخص أو أشخاص)</option>
            </select>
          </div>

          {/* Specific Branch Selector */}
          {targetType === 'branch' && (
            <div className="space-y-1.5 animate-glass">
              <label className="text-xs text-slate-400 font-bold block text-right">اختر الفرع المستهدف</label>
              <select
                value={targetBranchId}
                onChange={(e) => setTargetBranchId(e.target.value)}
                required
                className="w-full bg-slate-950 border border-slate-850 text-white rounded-xl p-3 text-xs focus:border-blue-500 outline-none"
              >
                <option value="">اختر الفرع...</option>
                {branches.map(b => (
                  <option key={b.id} value={b.id}>{b.name}</option>
                ))}
              </select>
            </div>
          )}

          {/* Specific Employees Selector */}
          {targetType === 'employee' && (
            <div className="space-y-2 animate-glass">
              <label className="text-xs text-slate-400 font-bold block text-right">اختر الموظفين المستهدفين ({targetEmployeeIds.length} محدد)</label>
              
              {/* Employee search filter */}
              <input
                type="text"
                placeholder="ابحث باسم الموظف لتحديده..."
                value={empSearchTerm}
                onChange={(e) => setEmpSearchTerm(e.target.value)}
                className="w-full bg-slate-950 border border-slate-850 text-white rounded-xl px-3 py-2 text-xs focus:border-blue-500 outline-none"
              />
              
              <div className="max-h-[160px] overflow-y-auto border border-slate-800 rounded-xl p-3 bg-slate-950/50 space-y-2 text-right" dir="rtl">
                {employeesList
                  .filter(emp => emp && (emp.full_name || '').toLowerCase().includes(empSearchTerm.toLowerCase()))
                  .map(emp => {
                    const isChecked = targetEmployeeIds.includes(emp.id);
                    return (
                      <label key={emp.id} className="flex items-center gap-2.5 text-xs text-slate-300 cursor-pointer hover:text-white transition-colors">
                        <input
                          type="checkbox"
                          checked={isChecked}
                          onChange={() => {
                            if (isChecked) {
                              setTargetEmployeeIds(prev => prev.filter(id => id !== emp.id));
                            } else {
                              setTargetEmployeeIds(prev => [...prev, emp.id]);
                            }
                          }}
                          className="rounded border-slate-800 text-blue-600 focus:ring-blue-500"
                        />
                        <span>{emp.full_name}</span>
                      </label>
                    );
                  })}
              </div>
            </div>
          )}

          {/* Announcement Content */}
          <div className="space-y-1.5">
            <label className="text-xs text-slate-400 font-bold block text-right">نص التعميم الإداري</label>
            <textarea
              value={announcement}
              onChange={(e) => setAnnouncement(e.target.value)}
              required
              rows={4}
              placeholder="اكتب الإعلان أو التعميم إداري هنا وسيصل الموظفون فوراً رنين إشعار متوهج على شاشاتهم..."
              className="w-full bg-slate-950 border border-slate-850 rounded-2xl p-4 text-xs text-white placeholder-slate-500 focus:border-blue-500 outline-none resize-none"
            />
          </div>

          <div className="flex justify-end gap-3 pt-4 border-t border-slate-800/80">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-xs text-slate-400 hover:text-white"
            >
              إلغاء
            </button>
            <button
              type="submit"
              disabled={actionLoading}
              className="px-5 py-2.5 bg-blue-600 hover:bg-blue-500 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-blue-500/20 cursor-pointer active:scale-95 flex items-center gap-1.5"
            >
              {actionLoading ? (
                <>
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  <span>جاري إرسال التعميم...</span>
                </>
              ) : (
                <span>بث التعميم المستهدف فوراً 🚀</span>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
