'use client';

// حالة المساحة ونصيحة التوفير، وزر إفراغ سلة المحذوفات، وحدود الباقة المجانية.

import { Trash2, Database, Cloud, Info, ShieldCheck } from 'lucide-react';
import { formatBytes } from '../logic';
import type { StorageState } from '../useStorageStats';

export function StorageStatusPanel({ s }: { s: StorageState }) {
  const { actionLoading, trashSizeBytes, dbSizeBytes, maxStorageBytes, maxDbBytes, handleEmptyTrash, totalStorageBytes, storageUsagePercent, dbUsagePercent, isStorageWarning, isDbWarning } = s;
  return (
    <>
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
      
      {/* Status */}
      <div className="lg:col-span-2 space-y-4">
        {/* DB warning */}
        <div className={`bg-slate-900/40 backdrop-blur-xl border rounded-2xl p-5 flex items-start gap-4 shadow-xl ${isDbWarning ? 'border-rose-500/30' : 'border-slate-850'}`}>
          <div className={`p-2.5 rounded-xl border shrink-0 ${isDbWarning ? 'bg-rose-500/10 border-rose-500/20 text-rose-400' : 'bg-violet-500/10 border-violet-500/20 text-violet-400'}`}>
            <Database className="w-5 h-5 shrink-0" />
          </div>
          <div>
            <h4 className="font-extrabold text-xs text-white mb-1">
              {isDbWarning ? '⚠️ تحذير: قاعدة البيانات تقترب من الحد الأقصى!' : '✅ قاعدة البيانات مستقرة'}
            </h4>
            <p className="text-[11px] text-slate-400 leading-relaxed">
              {isDbWarning 
                ? `استهلاك قاعدة البيانات وصل ${dbUsagePercent.toFixed(1)}%. استخدم أداة تنظيف البيانات في الإعدادات لحذف سجلات التتبع والحضور القديمة بعد اعتماد الرواتب.`
                : `قاعدة البيانات تستهلك ${dbUsagePercent.toFixed(1)}% فقط (${formatBytes(dbSizeBytes)} من ${formatBytes(maxDbBytes)}). المتبقي ${formatBytes(maxDbBytes - dbSizeBytes)}.`}
            </p>
          </div>
        </div>

        {/* Storage warning */}
        <div className={`bg-slate-900/40 backdrop-blur-xl border rounded-2xl p-5 flex items-start gap-4 shadow-xl ${isStorageWarning ? 'border-rose-500/30' : 'border-slate-850'}`}>
          <div className={`p-2.5 rounded-xl border shrink-0 ${isStorageWarning ? 'bg-rose-500/10 border-rose-500/20 text-rose-400' : 'bg-teal-500/10 border-teal-500/20 text-teal-400'}`}>
            <Cloud className="w-5 h-5 shrink-0" />
          </div>
          <div>
            <h4 className="font-extrabold text-xs text-white mb-1">
              {isStorageWarning ? '⚠️ تحذير: التخزين السحابي يوشك على الامتلاء!' : '✅ التخزين السحابي مستقر'}
            </h4>
            <p className="text-[11px] text-slate-400 leading-relaxed">
              {isStorageWarning 
                ? 'لقد تجاوزت نسبة استهلاك التخزين 80%. يرجى إفراغ سلة المحذوفات وتقليل أحجام الملفات.'
                : `التخزين السحابي يستهلك ${storageUsagePercent.toFixed(1)}% فقط (${formatBytes(totalStorageBytes)} من ${formatBytes(maxStorageBytes)}). المتبقي ${formatBytes(maxStorageBytes - totalStorageBytes)}.`}
            </p>
          </div>
        </div>

        {/* Info box */}
        <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-850 rounded-2xl p-5 flex items-start gap-4 shadow-xl">
          <div className="p-2.5 rounded-xl bg-amber-500/10 border border-amber-500/20 text-amber-400 shrink-0">
            <Info className="w-5 h-5" />
          </div>
          <div>
            <h4 className="font-extrabold text-xs text-white mb-1">💡 نصيحة لتوفير المساحة</h4>
            <p className="text-[11px] text-slate-400 leading-relaxed">
              أكبر مستهلك للمساحة عادةً هو جدول <strong className="text-white">تتبع المواقع GPS</strong> وجدول <strong className="text-white">الحضور والغياب</strong>. بعد اعتماد رواتب الشهر بالكامل، يمكنك حذف هذه السجلات من قسم <strong className="text-amber-400">إعدادات النظام → أداة تنظيف قاعدة البيانات</strong> بأمان تام.
            </p>
          </div>
        </div>
      </div>

      {/* Purge panel */}
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-850 rounded-3xl p-6 shadow-xl flex flex-col justify-between">
        <div>
          <h4 className="font-extrabold text-sm text-white mb-2">إجراءات تصفية المساحة</h4>
          <p className="text-xs text-slate-400 mb-6">إفراغ سلة المحذوفات لتحرير مساحة التخزين السحابي فوراً</p>

          <button
            disabled={actionLoading || trashSizeBytes === 0}
            onClick={handleEmptyTrash}
            className="w-full flex items-center justify-center gap-2 py-4 px-4 bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 hover:text-rose-300 border border-rose-500/20 hover:border-rose-500/30 rounded-2xl font-bold transition-all text-xs cursor-pointer disabled:opacity-40 disabled:pointer-events-none"
          >
            <Trash2 className="w-4.5 h-4.5" />
            <span>إفراغ سلة المحذوفات بالكامل 🗑️</span>
          </button>
        </div>

        <div className="mt-6 p-4 bg-slate-950/50 border border-slate-850 rounded-2xl">
          <div className="flex items-center gap-2 mb-2">
            <ShieldCheck className="w-4 h-4 text-emerald-400" />
            <span className="text-[10px] font-bold text-white">حدود الباقة المجانية</span>
          </div>
          <ul className="text-[10px] text-slate-400 space-y-1.5 font-bold">
            <li className="flex justify-between">
              <span>قاعدة البيانات:</span>
              <span className="text-slate-300">500 MB</span>
            </li>
            <li className="flex justify-between">
              <span>التخزين السحابي:</span>
              <span className="text-slate-300">1 GB</span>
            </li>
            <li className="flex justify-between border-t border-slate-850 pt-1.5 mt-1.5">
              <span>الإجمالي المتاح:</span>
              <span className="text-teal-400">1.5 GB</span>
            </li>
          </ul>
        </div>
      </div>
    </div>
    </>
  );
}
