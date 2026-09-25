'use client';

import React, { useState } from 'react';
import type { Employee } from '@/lib/db-types';
import type { DeleteType } from '../types';
import { Loader2, Trash2 } from 'lucide-react';

interface DeleteEmployeeModalProps {
  employeeToDelete: Employee;
  saving: boolean;
  onClose: () => void;
  onSubmit: (deleteType: DeleteType, reason: string) => void;
}

/** اختيار طريقة إنهاء خدمة الموظف: أرشفة، حذف مجدول، أو حذف فوري. */
export function DeleteEmployeeModal({ employeeToDelete, saving, onClose, onSubmit }: DeleteEmployeeModalProps) {
  const [deleteType, setDeleteType] = useState<DeleteType>('archive');
  const [deleteReason, setDeleteReason] = useState('');

  const executeDeleteEmployee = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit(deleteType, deleteReason);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md overflow-y-auto">
      <div className="relative w-full max-w-md bg-slate-900/90 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden animate-glass">
        <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-red-500 to-amber-500"></div>
        
        <div className="flex items-center gap-2 text-red-400 mb-6">
          <Trash2 className="w-6 h-6 animate-pulse" />
          <h3 className="text-lg font-bold text-white">خيارات حذف وأرشفة الموظف</h3>
        </div>

        <p className="text-xs text-slate-300 leading-relaxed mb-4">
          أنت على وشك إلغاء تنشيط أو حذف الموظف <strong className="text-white font-extrabold">{employeeToDelete.full_name}</strong> (رمز الموظف: {employeeToDelete.employee_code || 'غير محدد'}). يرجى تحديد طريقة الإجراء المطلوبة بدقة:
        </p>

        <form onSubmit={executeDeleteEmployee} className="space-y-4">
          
          {/* Deletion / Archiving Radio Options */}
          <div className="space-y-3">
            <label className={`flex gap-3 p-3 rounded-2xl border-2 cursor-pointer transition-all ${
              deleteType === 'archive' ? 'border-teal-500 bg-teal-500/10' : 'border-slate-800 bg-slate-950/50 hover:bg-slate-900/30'
            }`}>
              <input 
                type="radio" 
                name="deleteType" 
                checked={deleteType === 'archive'} 
                onChange={() => setDeleteType('archive')} 
                className="mt-0.5"
              />
              <div>
                <h4 className="text-xs font-bold text-white">🗃️ أرشفة وتجميد الحساب (موصى به)</h4>
                <p className="text-[10px] text-slate-400 mt-1">يتم إيقاف تفعيل حساب الموظف ومنعه من التبصيم، مع الحفاظ الكامل على كافة بيانات حضور وسجلات الموظف في الأرشيف للرجوع إليها مستقبلاً.</p>
              </div>
            </label>

            <label className={`flex gap-3 p-3 rounded-2xl border-2 cursor-pointer transition-all ${
              deleteType === 'scheduled' ? 'border-amber-500 bg-amber-500/10' : 'border-slate-800 bg-slate-950/50 hover:bg-slate-900/30'
            }`}>
              <input 
                type="radio" 
                name="deleteType" 
                checked={deleteType === 'scheduled'} 
                onChange={() => setDeleteType('scheduled')} 
                className="mt-0.5"
              />
              <div>
                <h4 className="text-xs font-bold text-white">⏳ حذف مجدول بعد 30 يوماً</h4>
                <p className="text-[10px] text-slate-400 mt-1">تجميد حساب الموظف فوراً، وجدولة حذف ملفه وسجلاته بالكامل بشكل قطعي وتلقائي بعد 30 يوماً. سيتلقى الإدارة إشعار تذكير قبل التنفيذ بأسبوع.</p>
              </div>
            </label>

            <label className={`flex gap-3 p-3 rounded-2xl border-2 cursor-pointer transition-all ${
              deleteType === 'immediate' ? 'border-red-500 bg-red-500/10' : 'border-slate-800 bg-slate-950/50 hover:bg-slate-900/30'
            }`}>
              <input 
                type="radio" 
                name="deleteType" 
                checked={deleteType === 'immediate'} 
                onChange={() => setDeleteType('immediate')} 
                className="mt-0.5"
              />
              <div>
                <h4 className="text-xs font-bold text-white">⚠️ حذف فوري كامل ونهائي</h4>
                <p className="text-[10px] text-red-400 mt-1">حذف حساب الموظف، هويته، كافة بصمات حضوره وانصرافه، طلبات سلفه وإجازاته وسجلاته من قاعدة البيانات نهائياً وبدون أي إمكانية للاسترجاع!</p>
              </div>
            </label>
          </div>

          {/* Reason input */}
          <div className="space-y-1">
            <label className="block text-xs text-slate-400 font-bold">السبب أو البيان (اختياري)</label>
            <input
              type="text"
              placeholder="مثال: استقالة، انتهاء العقد، فصل إداري..."
              value={deleteReason}
              onChange={(e) => setDeleteReason(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
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
              disabled={saving}
              className={`px-5 py-2.5 rounded-xl text-xs font-bold transition-all shadow cursor-pointer active:scale-95 flex items-center gap-1.5 text-white ${
                deleteType === 'immediate' ? 'bg-red-600 hover:bg-red-500' : deleteType === 'scheduled' ? 'bg-amber-600 hover:bg-amber-500' : 'bg-teal-650 hover:bg-teal-500'
              }`}
            >
              {saving ? (
                <>
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  <span>جاري المعالجة والتنفيذ...</span>
                </>
              ) : (
                <span>تأكيد وتنفيذ الإجراء 🚀</span>
              )}
            </button>
          </div>

        </form>
      </div>
    </div>
  );
}
