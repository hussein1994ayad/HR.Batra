'use client';

// تفصيل الملفات حسب الـ Bucket وسلة المحذوفات.

import { Cloud } from 'lucide-react';
import { formatBytes } from '../logic';
import type { StorageState } from '../useStorageStats';

export function BucketsCard({ s }: { s: StorageState }) {
  const { maxStorageBytes, totalStorageBytes, storageCategories } = s;
  return (
    <>
    <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-8 shadow-xl">
      <div className="flex items-center gap-2 mb-6">
        <Cloud className="w-5 h-5 text-teal-400" />
        <h3 className="text-sm font-extrabold text-white">تفصيل الملفات والتخزين السحابي (Storage Buckets)</h3>
      </div>

      {/* Bucket category bar */}
      <div className="w-full h-4 bg-slate-950 rounded-full overflow-hidden flex mb-6">
        {storageCategories.map((cat, i) => (
          <div 
            key={i} 
            className={`${cat.color} h-full transition-all duration-500`}
            style={{ width: totalStorageBytes > 0 ? `${(cat.size / maxStorageBytes) * 100}%` : '0%' }}
            title={`${cat.name}: ${formatBytes(cat.size)}`}
          />
        ))}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {storageCategories.map((cat, i) => (
          <div 
            key={i} 
            className="bg-slate-950/30 border border-slate-850 hover:border-slate-800 rounded-2xl p-4 flex items-center gap-4 transition-all"
          >
            <div className={`w-3.5 h-3.5 rounded-full shrink-0 ${cat.color}`} />
            <div className="flex-1 min-w-0">
              <span className="text-xs font-bold text-white block truncate mb-1">{cat.name}</span>
              <div className="flex justify-between items-center text-[10px] text-slate-400 font-bold">
                <span>{formatBytes(cat.size)}</span>
                <span className="font-mono">{totalStorageBytes > 0 ? ((cat.size / totalStorageBytes) * 100).toFixed(1) : '0.0'}%</span>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
    </>
  );
}
