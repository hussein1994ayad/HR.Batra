'use client';

import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { emptyEmployeeForm } from '../logic';
import type { BranchOption, EmployeeFormValues } from '../types';
import { Users, Lock, X, Loader2, Plus, Building, Briefcase, DollarSign, Phone, Mail, Upload, FileImage, Calendar } from 'lucide-react';

interface AddEmployeeModalProps {
  branches: BranchOption[];
  saving: boolean;
  onClose: () => void;
  onSubmit: (values: EmployeeFormValues, documents: File[]) => void;
}

/** نموذج إضافة موظف جديد مع رفع المستمسكات. */
export function AddEmployeeModal({ branches, saving, onClose, onSubmit }: AddEmployeeModalProps) {
  const [initial] = useState(emptyEmployeeForm);
  const [fullName, setFullName] = useState(initial.fullName);
  const [email, setEmail] = useState(initial.email);
  const [phone, setPhone] = useState(initial.phone);
  const [password, setPassword] = useState(initial.password);
  const [role, setRole] = useState(initial.role);
  const [branchId, setBranchId] = useState(initial.branchId);
  const [monthlySalary, setMonthlySalary] = useState(initial.monthlySalary);
  const [joinDate, setJoinDate] = useState(initial.joinDate);
  const [newDocuments, setNewDocuments] = useState<File[]>([]);

  const handleCreateEmployee = (e: React.FormEvent) => {
    e.preventDefault();
    if (!fullName.trim()) {
      toast.error('يرجى إدخال اسم الموظف');
      return;
    }
    if (!email.trim()) {
      toast.error('يرجى إدخال البريد الإلكتروني');
      return;
    }
    if (!password || password.length < 6) {
      toast.error('يجب أن تكون كلمة المرور 6 أحرف على الأقل');
      return;
    }
    const { futureSalary, futureSalaryMonth } = initial;
    onSubmit({ fullName, email, phone, password, role, branchId, monthlySalary, futureSalary, futureSalaryMonth, joinDate }, newDocuments);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md overflow-y-auto">
      <div className="relative w-full max-w-xl bg-slate-900/90 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden my-8 animate-glass">
        <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-teal-500 to-emerald-500"></div>
        
        <div className="flex items-center gap-2 text-teal-400 mb-6">
          <Plus className="w-6 h-6" />
          <h3 className="text-lg font-bold text-white">إضافة موظف جغرافي جديد للمؤسسة</h3>
        </div>

        <form onSubmit={handleCreateEmployee} className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                <Users className="w-3.5 h-3.5 text-teal-400" />
                <span>اسم الموظف الثلاثي</span>
              </label>
              <input
                type="text"
                required
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                placeholder="محمد علي عبد الحسين"
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
              />
            </div>

            <div>
              <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                <Mail className="w-3.5 h-3.5 text-teal-400" />
                <span>البريد الإلكتروني للعمل</span>
              </label>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="mohammed@hrpro.com"
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                dir="ltr"
              />
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                <Phone className="w-3.5 h-3.5 text-teal-400" />
                <span>رقم الهاتف (العراق)</span>
              </label>
              <input
                type="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="077XXXXXXXX"
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                dir="ltr"
              />
            </div>

            <div>
              <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                <Lock className="w-3.5 h-3.5 text-teal-400" />
                <span>كلمة مرور الحساب (6 أحرف فأكثر)</span>
              </label>
              <input
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
                dir="ltr"
              />
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                <Building className="w-3.5 h-3.5 text-teal-400" />
                <span>الفرع الجغرافي</span>
              </label>
              <select
                required
                value={branchId}
                onChange={(e) => setBranchId(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
              >
                <option value="">اختر الفرع...</option>
                {branches.map(b => (
                  <option key={b.id} value={b.id}>{b.name}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                <Briefcase className="w-3.5 h-3.5 text-teal-400" />
                <span>الصلاحية</span>
              </label>
              <select
                required
                value={role}
                onChange={(e) => setRole(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
              >
                <option value="employee">موظف عادي</option>
                <option value="manager">مدير موارد</option>
                <option value="admin">مدير عام</option>
              </select>
            </div>

            <div>
              <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
                <Calendar className="w-3.5 h-3.5 text-teal-400" />
                <span>تاريخ المباشرة بالعمل</span>
              </label>
              <input
                type="date"
                required
                value={joinDate}
                onChange={(e) => setJoinDate(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none"
                dir="ltr"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1">
              <DollarSign className="w-3.5 h-3.5 text-teal-400" />
              <span>الراتب الأساسي الشهري (د.ع)</span>
            </label>
            <input
              type="text"
              required
              value={monthlySalary || ''}
              onChange={(e) => setMonthlySalary(Number(e.target.value.replace(/\D/g, '')))}
              placeholder="1500000"
              className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-xs text-white outline-none text-left"
              dir="ltr"
            />
          </div>

          <div>
            <label className="block text-xs text-slate-400 mb-2 flex items-center gap-1">
              <FileImage className="w-3.5 h-3.5 text-teal-400" />
              <span>المستمسكات الثبوتية (اختياري)</span>
            </label>
            <div className="flex flex-wrap gap-3">
              {newDocuments.map((file, idx) => (
                <div key={idx} className="relative group">
                  <img src={URL.createObjectURL(file)} alt="doc" className="w-16 h-16 object-cover rounded-xl border border-slate-700" />
                  <button type="button" onClick={() => setNewDocuments(prev => prev.filter((_, i) => i !== idx))} className="absolute -top-2 -right-2 bg-red-500 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 transition-opacity shadow-md">
                    <X className="w-3 h-3" />
                  </button>
                </div>
              ))}
              <label className="w-16 h-16 flex items-center justify-center border-2 border-dashed border-slate-700 rounded-xl cursor-pointer hover:border-teal-500 hover:bg-slate-800/50 transition-colors">
                <input type="file" multiple accept="image/*" className="hidden" onChange={(e) => {
                  if (e.target.files) {
                    setNewDocuments(prev => [...prev, ...Array.from(e.target.files as FileList)]);
                  }
                }} />
                <Upload className="w-5 h-5 text-slate-500" />
              </label>
            </div>
            <p className="text-[10px] text-slate-500 mt-2">يمكنك رفع عدة صور. سيتم ضغط الصور تلقائياً وبشكل احترافي قبل الرفع.</p>
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
              className="px-5 py-2.5 bg-teal-600 hover:bg-teal-500 text-white rounded-xl text-xs font-bold transition-all shadow cursor-pointer active:scale-95 flex items-center gap-1.5"
            >
              {saving ? (
                <>
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  <span>جاري التسجيل...</span>
                </>
              ) : (
                <span>تثبيت وتسجيل الموظف 🎯</span>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
