'use client';

// تفصيل جداول قاعدة البيانات من الأكبر للأصغر (الأسماء العربية والألوان من logic.ts).

import { Table2, ArrowDownUp } from 'lucide-react';
import { TABLE_LABELS, getTableColor, getTableDotColor, formatBytes } from '../logic';
import type { StorageState } from '../useStorageStats';

export function TableSizesCard({ s }: { s: StorageState }) {
  const { tableSizes, totalTableBytes } = s;
  return (
    <>
    <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-8 shadow-xl">
      <div className="flex items-center gap-2 mb-6">
        <Table2 className="w-5 h-5 text-violet-400" />
        <h3 className="text-sm font-extrabold text-white">تفصيل جداول قاعدة البيانات — كل جدول وشقد ماخذ</h3>
        <span className="mr-auto text-[10px] text-slate-500 font-bold flex items-center gap-1">
          <ArrowDownUp className="w-3 h-3" /> مرتب من الأكبر للأصغر
        </span>
      </div>

      <div className="space-y-2">
        {tableSizes.map((table, i) => {
          const pctOfDb = totalTableBytes > 0 ? (table.total_bytes / totalTableBytes) * 100 : 0;
          const label = TABLE_LABELS[table.table_name] || table.table_name;
          const barColor = getTableColor(table.table_name);
          const dotColor = getTableDotColor(table.table_name);

          return (
            <div 
              key={table.table_name}
              className="bg-slate-950/30 border border-slate-850 hover:border-slate-800 rounded-xl p-3.5 transition-all group"
            >
              <div className="flex items-center gap-3">
                <span className="text-[10px] text-slate-600 font-mono w-5 text-center shrink-0">{i + 1}</span>
                <span className={`w-2.5 h-2.5 rounded-full shrink-0 ${dotColor}`} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between mb-1.5">
                    <div className="flex items-center gap-2 min-w-0">
                      <span className="text-xs font-bold text-white truncate">{label}</span>
                      <span className="text-[9px] text-slate-600 font-mono hidden sm:inline">({table.table_name})</span>
                    </div>
                    <div className="flex items-center gap-4 shrink-0">
                      <span className="text-[10px] text-slate-500 font-bold">{table.row_count.toLocaleString()} سجل</span>
                      <span className="text-xs font-extrabold text-white min-w-[60px] text-left">{table.pretty_size}</span>
                      <span className="text-[10px] font-mono text-slate-600 min-w-[45px] text-left">{pctOfDb.toFixed(1)}%</span>
                    </div>
                  </div>
                  <div className="w-full h-1.5 bg-slate-900 rounded-full overflow-hidden">
                    <div 
                      className={`h-full rounded-full transition-all duration-500 ${barColor}`}
                      style={{ width: `${Math.max(pctOfDb, 0.5)}%` }}
                    />
                  </div>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      <div className="flex items-center justify-between mt-4 pt-4 border-t border-slate-850 text-xs font-bold">
        <span className="text-slate-400">إجمالي جميع الجداول:</span>
        <span className="text-white">{formatBytes(totalTableBytes)} ({tableSizes.length} جدول)</span>
      </div>
    </div>
    </>
  );
}
