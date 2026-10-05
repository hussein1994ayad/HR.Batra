'use client';

// الملخص: مؤشرا قاعدة البيانات والتخزين السحابي (أحمر عند 80%) وشريط الاستهلاك الكلي.

import { Database, Cloud, TrendingUp } from 'lucide-react';
import { formatBytes } from '../logic';
import type { StorageState } from '../useStorageStats';

export function StorageSummary({ s }: { s: StorageState }) {
  const { dbSizeBytes, maxStorageBytes, maxDbBytes, totalStorageBytes, storageUsagePercent, dbUsagePercent, isStorageWarning, isDbWarning, totalCombinedBytes, maxCombinedBytes, combinedUsagePercent } = s;
  return (
    <>
    <div className="surface rounded-3xl p-5 md:p-6">

      {/* Two main gauges: Database + Storage side by side */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">

        {/* Database Gauge */}
        <div className="bg-slate-950/50 border border-slate-850 rounded-2xl p-6 space-y-4">
          <div className="flex items-center gap-2 mb-2">
            <Database className="w-5 h-5 text-violet-400" />
            <h4 className="text-sm font-extrabold text-white">قاعدة البيانات (Database)</h4>
            <span className="mr-auto text-[10px] text-slate-500 font-bold">الحد الأقصى: {formatBytes(maxDbBytes)}</span>
          </div>
          <div className="flex items-end justify-between">
            <div>
              <span className={`text-3xl font-black ${isDbWarning ? 'text-rose-400' : 'text-violet-400'}`}>
                {formatBytes(dbSizeBytes)}
              </span>
              <span className="text-slate-500 text-xs font-bold mr-2">مستهلك</span>
            </div>
            <div className="text-left">
              <span className={`text-lg font-extrabold ${isDbWarning ? 'text-rose-400' : 'text-violet-300'}`}>
                {dbUsagePercent.toFixed(1)}%
              </span>
              <span className="block text-[10px] text-slate-500 font-bold">
                المتبقي: {formatBytes(maxDbBytes - dbSizeBytes)}
              </span>
            </div>
          </div>
          <div className="w-full h-3 bg-slate-900 rounded-full overflow-hidden">
            <div 
              className={`h-full rounded-full transition-all duration-700 ${isDbWarning ? 'bg-gradient-to-l from-rose-500 to-rose-600' : 'bg-gradient-to-l from-violet-500 to-violet-600'}`}
              style={{ width: `${Math.min(dbUsagePercent, 100)}%` }}
            />
          </div>
        </div>

        {/* Storage Gauge */}
        <div className="bg-slate-950/50 border border-slate-850 rounded-2xl p-6 space-y-4">
          <div className="flex items-center gap-2 mb-2">
            <Cloud className="w-5 h-5 text-teal-400" />
            <h4 className="text-sm font-extrabold text-white">التخزين السحابي (Storage Buckets)</h4>
            <span className="mr-auto text-[10px] text-slate-500 font-bold">الحد الأقصى: {formatBytes(maxStorageBytes)}</span>
          </div>
          <div className="flex items-end justify-between">
            <div>
              <span className={`text-3xl font-black ${isStorageWarning ? 'text-rose-400' : 'text-teal-400'}`}>
                {formatBytes(totalStorageBytes)}
              </span>
              <span className="text-slate-500 text-xs font-bold mr-2">مستهلك</span>
            </div>
            <div className="text-left">
              <span className={`text-lg font-extrabold ${isStorageWarning ? 'text-rose-400' : 'text-teal-300'}`}>
                {storageUsagePercent.toFixed(1)}%
              </span>
              <span className="block text-[10px] text-slate-500 font-bold">
                المتبقي: {formatBytes(maxStorageBytes - totalStorageBytes)}
              </span>
            </div>
          </div>
          <div className="w-full h-3 bg-slate-900 rounded-full overflow-hidden">
            <div 
              className={`h-full rounded-full transition-all duration-700 ${isStorageWarning ? 'bg-gradient-to-l from-rose-500 to-rose-600' : 'bg-gradient-to-l from-teal-500 to-teal-600'}`}
              style={{ width: `${Math.min(storageUsagePercent, 100)}%` }}
            />
          </div>
        </div>
      </div>

      {/* Grand total bar */}
      <div className="mt-6 bg-slate-950/40 border border-slate-850 rounded-2xl p-5">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <TrendingUp className="w-4 h-4 text-amber-400" />
            <span className="text-xs font-extrabold text-white">إجمالي الاستهلاك الكلي من Supabase</span>
          </div>
          <span className="text-xs font-bold text-slate-400">
            {formatBytes(totalCombinedBytes)} من {formatBytes(maxCombinedBytes)}
          </span>
        </div>
        <div className="w-full h-4 bg-slate-900 rounded-full overflow-hidden flex">
          {/* DB portion */}
          <div 
            className="bg-gradient-to-l from-violet-500 to-violet-600 h-full transition-all duration-700"
            style={{ width: `${(dbSizeBytes / maxCombinedBytes) * 100}%` }}
            title={`قاعدة البيانات: ${formatBytes(dbSizeBytes)}`}
          />
          {/* Storage portion */}
          <div 
            className="bg-gradient-to-l from-teal-500 to-teal-600 h-full transition-all duration-700"
            style={{ width: `${(totalStorageBytes / maxCombinedBytes) * 100}%` }}
            title={`التخزين السحابي: ${formatBytes(totalStorageBytes)}`}
          />
        </div>
        <div className="flex items-center gap-6 mt-3 text-[10px] font-bold text-slate-500">
          <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full bg-violet-500 inline-block" /> قاعدة البيانات ({formatBytes(dbSizeBytes)})</span>
          <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full bg-teal-500 inline-block" /> التخزين السحابي ({formatBytes(totalStorageBytes)})</span>
          <span className="mr-auto">استهلاك {combinedUsagePercent.toFixed(2)}% — المتبقي {formatBytes(maxCombinedBytes - totalCombinedBytes)}</span>
        </div>
      </div>
    </div>
    </>
  );
}
