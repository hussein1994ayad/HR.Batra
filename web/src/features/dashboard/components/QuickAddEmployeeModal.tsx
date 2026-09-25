'use client';

import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { getLocalDateStr } from '@/lib/dates';
import type { Branch, Department } from '@/lib/db-types';
import type { EmployeeFormValues } from '@/features/employees/types';
import { X, Upload, FileImage } from 'lucide-react';

interface QuickAddEmployeeModalProps {
  branches: Pick<Branch, 'id' | 'name'>[];
  departments: Department[];
  actionLoading: boolean;
  onClose: () => void;
  /** يرجع رسالة الخطأ أو null عند النجاح. */
  onSubmit: (values: EmployeeFormValues, documents: File[]) => Promise<string | null>;
}

/** إضافة سريعة لموظف مع القسم والمستمسكات. */
export function QuickAddEmployeeModal({ branches, departments, actionLoading, onClose, onSubmit }: QuickAddEmployeeModalProps) {
  const [newEmpEmail, setNewEmpEmail] = useState('');
  const [newEmpPassword, setNewEmpPassword] = useState('');
  const [newEmpName, setNewEmpName] = useState('');
  const [newEmpPhone, setNewEmpPhone] = useState('');
  const [newEmpRole, setNewEmpRole] = useState('employee');
  const [newEmpSalary, setNewEmpSalary] = useState(600000);
  const [newEmpBranch, setNewEmpBranch] = useState('');
  const [newEmpDept, setNewEmpDept] = useState('');
  const [newDocuments, setNewDocuments] = useState<File[]>([]);
  const [actionError, setActionError] = useState<string | null>(null);

  const handleAddEmployee = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newEmpName.trim()) {
      toast.error('يرجى إدخال اسم الموظف');
      return;
    }
    if (!newEmpEmail.trim()) {
      toast.error('يرجى إدخال البريد الإلكتروني');
      return;
    }
    if (!newEmpPassword || newEmpPassword.length < 6) {
      toast.error('يجب أن تكون كلمة المرور 6 أحرف على الأقل');
      return;
    }
    setActionError(null);
    const error = await onSubmit({
      fullName: newEmpName,
      email: newEmpEmail,
      phone: newEmpPhone,
      password: newEmpPassword,
      role: newEmpRole,
      branchId: newEmpBranch,
      departmentId: newEmpDept,
      monthlySalary: newEmpSalary,
      futureSalary: 0,
      futureSalaryMonth: '',
      joinDate: getLocalDateStr(),
    }, newDocuments);
    if (error) setActionError(error);
    else onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm overflow-y-auto">
      <div className="relative w-full max-w-lg bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden my-8">
        <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-teal-500 to-blue-500"></div>
        <h3 className="text-lg font-bold text-white mb-4">إضافة حساب موظف جديد لكادر الشركة 👤</h3>
        
        {actionError && (
          <div className="p-3 bg-rose-500/10 border border-rose-500/20 text-rose-300 rounded-xl text-xs mb-4">
            {actionError}
          </div>
        )}

        <form onSubmit={handleAddEmployee} className="space-y-4">
          <div>
            <label className="block text-xs text-slate-400 mb-1">الاسم الكامل للموظف الثلاثي</label>
            <input
              type="text"
              required
              value={newEmpName}
              onChange={(e) => setNewEmpName(e.target.value)}
              placeholder="محمد علي حسين"
              className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none"
            />
          </div>

          <div>
            <label className="block text-xs text-slate-400 mb-1">البريد الإلكتروني للعمل</label>
            <input
              type="email"
              required
              value={newEmpEmail}
              onChange={(e) => setNewEmpEmail(e.target.value)}
              placeholder="name@company.com"
              className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
              dir="ltr"
            />
          </div>

          <div>
            <label className="block text-xs text-slate-400 mb-1">كلمة مرور الحساب الافتراضية</label>
            <input
              type="password"
              required
              value={newEmpPassword}
              onChange={(e) => setNewEmpPassword(e.target.value)}
              placeholder="••••••••••••"
              className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
              dir="ltr"
            />
          </div>

          <div>
            <label className="block text-xs text-slate-400 mb-1">رقم الهاتف للاتصال</label>
            <input
              type="text"
              value={newEmpPhone}
              onChange={(e) => setNewEmpPhone(e.target.value)}
              placeholder="077XXXXXXXX"
              className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
              dir="ltr"
            />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs text-slate-400 mb-1">فرع العمل والموقع الجغرافي</label>
              <select
                value={newEmpBranch}
                onChange={(e) => setNewEmpBranch(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none"
              >
                <option value="">-- اختر الفرع --</option>
                {branches.map(b => (
                  <option key={b.id} value={b.id}>{b.name}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs text-slate-400 mb-1">القسم الإداري للموظف</label>
              <select
                value={newEmpDept}
                onChange={(e) => setNewEmpDept(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none"
              >
                <option value="">-- اختر القسم --</option>
                {departments.map(d => (
                  <option key={d.id} value={d.id}>{d.name}</option>
                ))}
              </select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-xs text-slate-400 mb-1">الدور الإداري والصلاحية</label>
              <select
                value={newEmpRole}
                onChange={(e) => setNewEmpRole(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none"
              >
                <option value="employee">موظف (كادر اعتيادي)</option>
                <option value="manager">مدير قسم / مدير موارد</option>
                <option value="admin">مسؤول أدمن النظام كاملاً</option>
              </select>
            </div>

            <div>
              <label className="block text-xs text-slate-400 mb-1">الراتب الشهري الأساسي (د.ع)</label>
              <input
                type="number"
                required
                value={newEmpSalary}
                onChange={(e) => setNewEmpSalary(Number(e.target.value))}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-white focus:border-teal-500 outline-none text-left"
                dir="ltr"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs text-slate-400 mb-2">المستمسكات الثبوتية للموظف (اختياري)</label>
            <label className="flex flex-col items-center justify-center w-full h-32 border-2 border-slate-800 border-dashed rounded-xl cursor-pointer bg-slate-950 hover:bg-slate-900 transition-colors">
              <div className="flex flex-col items-center justify-center pt-5 pb-6">
                <Upload className="w-8 h-8 text-teal-500 mb-2" />
                <p className="mb-2 text-xs text-slate-400">
                  <span className="font-semibold text-teal-400">اضغط لرفع الصور</span> أو اسحبها وأفلتها هنا
                </p>
                <p className="text-[10px] text-slate-500">يتم ضغط الصور تلقائياً (Max 1MB)</p>
              </div>
              <input 
                type="file" 
                className="hidden" 
                multiple 
                accept="image/*"
                onChange={(e) => {
                  if (e.target.files) {
                    setNewDocuments(prev => [...prev, ...Array.from(e.target.files!)]);
                  }
                }} 
              />
            </label>

            {newDocuments.length > 0 && (
              <div className="mt-3 flex flex-wrap gap-2">
                {newDocuments.map((file, idx) => (
                  <div key={idx} className="relative group bg-slate-900 border border-slate-700 rounded-lg p-1.5 flex items-center gap-2 pr-2">
                    <FileImage className="w-4 h-4 text-teal-500" />
                    <span className="text-[10px] text-slate-300 max-w-[100px] truncate" dir="ltr">{file.name}</span>
                    <button
                      type="button"
                      onClick={() => setNewDocuments(prev => prev.filter((_, i) => i !== idx))}
                      className="p-1 hover:bg-rose-500/20 text-rose-400 rounded-md transition-colors"
                    >
                      <X className="w-3 h-3" />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          <div className="flex justify-end gap-3 pt-4">
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
              className="px-5 py-2.5 bg-teal-650 hover:bg-teal-600 text-white rounded-xl text-xs font-bold transition-all shadow-md shadow-teal-500/20 cursor-pointer"
            >
              {actionLoading ? 'جاري إنشاء الحساب...' : 'إضافة الموظف الآن 👥'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
