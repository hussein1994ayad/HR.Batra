'use client';

import toast from 'react-hot-toast';
import type { Employee } from '@/lib/db-types';
import { X, Edit, FileImage, FolderOpen, FileText, Download, Eye, Share2 } from 'lucide-react';

interface EmployeeProfileModalProps {
  profileEmployee: Employee;
  onClose: () => void;
  onEdit: (emp: Employee) => void;
  onPreview: (url: string, title: string) => void;
}

/** ملف الموظف الشامل مع قائمة الوثائق المرفوعة. */
export function EmployeeProfileModal({ profileEmployee, onClose, onEdit, onPreview }: EmployeeProfileModalProps) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md overflow-y-auto">
      <div className="relative w-full max-w-2xl bg-slate-900 border border-slate-800 rounded-3xl shadow-2xl p-6 overflow-hidden my-8 animate-glass">
        <div className="absolute top-0 inset-x-0 h-1 bg-gradient-to-r from-purple-500 via-teal-500 to-blue-500"></div>

        <div className="flex items-center justify-between pb-4 border-b border-slate-800">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-2xl bg-purple-500/20 border border-purple-500/30 flex items-center justify-center text-purple-300 font-bold text-lg">
              {profileEmployee.full_name ? profileEmployee.full_name[0] : '?'}
            </div>
            <div>
              <h3 className="text-base font-bold text-white flex items-center gap-2">
                <span>{profileEmployee.full_name}</span>
                <span className={`px-2 py-0.5 rounded-full text-[9px] font-bold border ${
                  profileEmployee.role === 'admin' 
                    ? 'bg-rose-500/10 border-rose-500/20 text-rose-400' 
                    : profileEmployee.role === 'manager' 
                    ? 'bg-amber-500/10 border-amber-500/20 text-amber-400' 
                    : 'bg-blue-500/10 border-blue-500/20 text-blue-400'
                }`}>
                  {profileEmployee.role === 'admin' ? 'مدير عام' : profileEmployee.role === 'manager' ? 'مدير موارد' : 'موظف'}
                </span>
              </h3>
              <p className="text-xs text-slate-400 font-mono mt-0.5">
                كود الموظف: <span className="text-teal-400">{profileEmployee.employee_code || '-'}</span>
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 text-slate-400 hover:text-white rounded-xl hover:bg-slate-800 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="space-y-6 py-4">
          {/* Profile Details Grid */}
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 bg-slate-950/60 p-4 rounded-2xl border border-slate-800/80 text-xs">
            <div>
              <span className="text-slate-400 block text-[10px]">البريد الإلكتروني</span>
              <span className="text-white font-mono break-all">{profileEmployee.email || '-'}</span>
            </div>
            <div>
              <span className="text-slate-400 block text-[10px]">رقم الهاتف</span>
              <span className="text-white font-mono">{profileEmployee.phone || '-'}</span>
            </div>
            <div>
              <span className="text-slate-400 block text-[10px]">الفرع المعتمد</span>
              <span className="text-teal-400 font-bold">{profileEmployee.branches?.name || '-'}</span>
            </div>
            <div>
              <span className="text-slate-400 block text-[10px]">الراتب الشهري الأساسي</span>
              <span className="text-emerald-400 font-bold font-mono">
                {profileEmployee.monthly_salary_iqd ? profileEmployee.monthly_salary_iqd.toLocaleString() : '0'} د.ع
              </span>
            </div>
            <div>
              <span className="text-slate-400 block text-[10px]">حالة قفل الهاتف</span>
              <span className="text-slate-300">
                {profileEmployee.device_id_lock ? '🔒 مقفل على جهاز' : '🔓 غير مقيد'}
              </span>
            </div>
            <div>
              <span className="text-slate-400 block text-[10px]">الرمز السري المباشر</span>
              <span className="text-purple-400 font-mono font-bold bg-purple-500/10 px-2 py-0.5 rounded">
                {profileEmployee.plain_password || 'مخفي'}
              </span>
            </div>
          </div>

          {/* Documents Section */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h4 className="text-sm font-bold text-white flex items-center gap-2">
                <FolderOpen className="w-4 h-4 text-teal-400" />
                <span>المستمسكات والوثائق المرفوعة ({profileEmployee.document_urls?.length || 0})</span>
              </h4>
              {profileEmployee.document_urls && profileEmployee.document_urls.length > 0 && (
                <button
                  onClick={() => {
                    const urls = (profileEmployee.document_urls ?? []).join('\n');
                    void navigator.clipboard.writeText(urls);
                    toast.success('تم نسخ روابط كافة الوثائق 📋');
                  }}
                  className="text-[11px] text-teal-400 hover:text-teal-300 flex items-center gap-1 cursor-pointer font-bold"
                >
                  <Share2 className="w-3.5 h-3.5" />
                  <span>نسخ روابط الوثائق</span>
                </button>
              )}
            </div>

            {(!profileEmployee.document_urls || profileEmployee.document_urls.length === 0) ? (
              <div className="p-8 text-center bg-slate-950/40 rounded-2xl border border-slate-800/50 text-slate-500 text-xs">
                لا توجد وثائق أو مستمسكات مرفوعة لهذا الموظف حتى الآن. 📁
              </div>
            ) : (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 max-h-72 overflow-y-auto p-1">
                {profileEmployee.document_urls.map((url: string, idx: number) => {
                  const isPdf = url.toLowerCase().includes('.pdf');
                  return (
                    <div
                      key={idx}
                      className="flex items-center justify-between p-3 bg-slate-950/80 border border-slate-800 hover:border-teal-500/50 rounded-2xl transition-all group"
                    >
                      <div className="flex items-center gap-3 overflow-hidden">
                        <div className={`p-2.5 rounded-xl ${isPdf ? 'bg-rose-500/15 text-rose-400' : 'bg-teal-500/15 text-teal-400'}`}>
                          {isPdf ? <FileText className="w-5 h-5" /> : <FileImage className="w-5 h-5" />}
                        </div>
                        <div className="overflow-hidden">
                          <p className="text-xs font-bold text-white truncate">وثيقة رسمية #{idx + 1}</p>
                          <p className="text-[10px] text-slate-400">{isPdf ? 'ملف مستند PDF' : 'صورة مستمسك رسمية'}</p>
                        </div>
                      </div>

                      <div className="flex items-center gap-1.5">
                        <button
                          onClick={() => onPreview(url, `وثيقة ${profileEmployee.full_name} #${idx + 1}`)}
                          className="p-1.5 text-teal-400 hover:bg-teal-500/20 rounded-lg transition-colors cursor-pointer"
                          title="معاينة"
                        >
                          <Eye className="w-4 h-4" />
                        </button>
                        <a
                          href={url}
                          target="_blank"
                          rel="noreferrer"
                          download
                          className="p-1.5 text-blue-400 hover:bg-blue-500/20 rounded-lg transition-colors cursor-pointer"
                          title="فتح وتحميل في نافذة جديدة"
                        >
                          <Download className="w-4 h-4" />
                        </a>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>

        <div className="flex justify-between items-center pt-4 border-t border-slate-800">
          <button
            onClick={() => onEdit(profileEmployee)}
            className="px-4 py-2 bg-blue-500/10 border border-blue-500/20 text-blue-400 hover:bg-blue-500/20 rounded-xl text-xs font-bold transition-all cursor-pointer flex items-center gap-1.5"
          >
            <Edit className="w-3.5 h-3.5" />
            <span>تعديل مستمسكات وبيانات الموظف</span>
          </button>

          <button
            onClick={onClose}
            className="px-5 py-2 bg-slate-800 hover:bg-slate-700 text-white rounded-xl text-xs font-bold transition-colors"
          >
            إغلاق
          </button>
        </div>
      </div>
    </div>
  );
}
