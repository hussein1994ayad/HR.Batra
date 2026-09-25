'use client';

import { ArrowUpRight, UserPlus, Send } from 'lucide-react';

interface QuickActionsProps {
  onAddEmployee: () => void;
  onAnnounce: () => void;
}

/** اختصارات إضافة موظف وبث تعميم. */
export function QuickActions({ onAddEmployee, onAnnounce }: QuickActionsProps) {
  return (
    <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6 flex flex-col justify-between">
      <div>
        <h3 className="text-lg font-extrabold text-white mb-1">لوحة الإجراءات الفورية</h3>
        <p className="text-slate-400 text-xs mb-6">مجموع الإجراءات الإدارية المباشرة للأدمن</p>

        <div className="space-y-4">
          <button
            onClick={onAddEmployee}
            className="w-full flex items-center justify-between p-4 bg-gradient-to-l from-slate-800/80 to-slate-900/80 border border-slate-800 hover:border-indigo-500/40 rounded-2xl text-white transition-all duration-300 group cursor-pointer"
          >
            <div className="flex items-center gap-3">
              <div className="p-2.5 bg-indigo-500/10 rounded-xl text-indigo-400 border border-indigo-500/20 group-hover:scale-110 transition-transform">
                <UserPlus className="w-5 h-5" />
              </div>
              <div className="text-right">
                <span className="text-xs font-bold block text-slate-200">إضافة موظف جديد</span>
                <span className="text-[10px] text-slate-500 block">تسجيل حساب وتوليد الهوية</span>
              </div>
            </div>
            <ArrowUpRight className="w-5 h-5 text-slate-500 group-hover:text-indigo-400 transition-colors" />
          </button>

          <button
            onClick={onAnnounce}
            className="w-full flex items-center justify-between p-4 bg-gradient-to-l from-slate-800/80 to-slate-900/80 border border-slate-800 hover:border-violet-500/40 rounded-2xl text-white transition-all duration-300 group cursor-pointer"
          >
            <div className="flex items-center gap-3">
              <div className="p-2.5 bg-violet-500/10 rounded-xl text-violet-400 border border-violet-500/20 group-hover:scale-110 transition-transform">
                <Send className="w-5 h-5" />
              </div>
              <div className="text-right">
                <span className="text-xs font-bold block text-slate-200">بث تعميم إداري</span>
                <span className="text-[10px] text-slate-500 block">إعلان فوري في شريط الموبايل</span>
              </div>
            </div>
            <ArrowUpRight className="w-5 h-5 text-slate-500 group-hover:text-violet-400 transition-colors" />
          </button>
        </div>
      </div>

      <div className="pt-6 border-t border-slate-800/60 mt-6">
        <div className="flex items-center justify-between text-xs text-slate-400">
          <span>آخر مزامنة قاعدة بيانات</span>
          <span className="font-mono text-teal-400">منذ دقيقة</span>
        </div>
      </div>
    </div>
  );
}
