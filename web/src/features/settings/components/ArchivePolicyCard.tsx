'use client';

import type { SystemPolicies } from '../types';
import { ShieldAlert, Clock, HardDrive } from 'lucide-react';

interface ArchivePolicyCardProps {
  trackingDays: number;
  onChange: (patch: Partial<SystemPolicies>) => void;
}

/** مدة الاحتفاظ ببيانات التتبع قبل حذفها تلقائياً. */
export function ArchivePolicyCard({ trackingDays, onChange }: ArchivePolicyCardProps) {
  return (
    <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
      <div className="flex items-center gap-2 text-amber-400 pb-3 border-b border-slate-850">
        <ShieldAlert className="w-5 h-5" />
        <h4 className="text-sm font-extrabold text-white">سياسة الأرشفة والتتبع الجغرافي</h4>
      </div>

      <div className="space-y-4">
        <div>
          <label className="block text-xs text-slate-400 mb-1 flex items-center gap-1 font-bold">
            <Clock className="w-4 h-4 text-amber-400" />
            <span>فترة الاحتفاظ ببيانات التتبع والموقع</span>
          </label>
          <div className="flex gap-2">
            <input
              type="text"
              required
              value={trackingDays}
              onChange={(e) => onChange({ trackingDays: Number(e.target.value.replace(/\D/g, '')) })}
              className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-3 text-sm text-white font-bold outline-none text-left"
              dir="ltr"
            />
            <span className="bg-slate-800 border border-slate-700 px-4 py-3 rounded-xl text-xs text-slate-300 font-bold whitespace-nowrap flex items-center">يوم</span>
          </div>
          <p className="text-[10px] text-slate-500 mt-2 leading-relaxed">
            سيقوم النظام أوتوماتيكياً بمسح وتصفية إحداثيات ومواقع تتبع الموظفين ومخالفات السياج الجغرافي القديمة التي تتخطى هذه الفترة لضمان سرعة السيرفرات وتنظيف المساحة.
          </p>
        </div>

        <div className="p-4 bg-teal-950/10 border border-teal-500/20 rounded-2xl space-y-2">
          <div className="flex items-center gap-1 text-[10px] text-teal-400 font-bold">
            <HardDrive className="w-3.5 h-3.5" />
            <span>سلة المحذوفات للمستندات</span>
          </div>
          <p className="text-[9px] text-slate-400 leading-relaxed">
            نظام الأمان والملفات يضمن حفظ مستندات الموظفين وسجلات وتعهدات السلف المحذوفة لمدة **30 يوماً** تلقائياً في سلة المحذوفات قبل تصفيتها بشكل نهائي.
          </p>
        </div>
      </div>
    </div>
  );
}
