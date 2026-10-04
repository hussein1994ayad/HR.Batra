'use client';

import { LogOut } from 'lucide-react';

export function LogoutConfirm({ onConfirm, onCancel }: { onConfirm: () => void; onCancel: () => void }) {
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm" onClick={onCancel}>
      <div className="w-full max-w-sm surface-solid rounded-2xl p-6 text-right animate-glass" onClick={(e) => e.stopPropagation()}>
        <div className="w-11 h-11 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 flex items-center justify-center mb-4">
          <LogOut className="w-5 h-5" />
        </div>
        <h3 className="text-base font-bold text-white mb-1">تسجيل الخروج</h3>
        <p className="text-xs text-slate-400 leading-relaxed mb-6">هل أنت متأكد من رغبتك في تسجيل الخروج من لوحة التحكم؟</p>
        <div className="flex gap-2">
          <button
            onClick={onConfirm}
            className="flex-1 py-2.5 rounded-xl bg-rose-600 hover:bg-rose-500 text-white text-xs font-bold transition-colors cursor-pointer"
          >
            تسجيل الخروج
          </button>
          <button
            autoFocus
            onClick={onCancel}
            className="flex-1 py-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-bold transition-colors cursor-pointer"
          >
            إلغاء
          </button>
        </div>
      </div>
    </div>
  );
}
