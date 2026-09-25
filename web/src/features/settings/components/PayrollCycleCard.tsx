'use client';

import type { SystemPolicies } from '../types';
import { CalendarRange } from 'lucide-react';

interface PayrollCycleCardProps {
  cycleStartDay: number;
  cycleEndDay: number;
  onChange: (patch: Partial<SystemPolicies>) => void;
}

/** يوم بداية ونهاية الدورة المالية للرواتب. */
export function PayrollCycleCard({ cycleStartDay, cycleEndDay, onChange }: PayrollCycleCardProps) {
  return (
    <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
      <div className="flex items-center gap-2 text-teal-400 pb-3 border-b border-slate-850">
        <CalendarRange className="w-5 h-5 text-teal-400" />
        <h4 className="text-sm font-extrabold text-white">إعدادات الدورة المالية للرواتب 💸</h4>
      </div>

      <div className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-[10px] text-slate-400 mb-1 font-bold">
              يوم بداية الدورة
            </label>
            <input
              type="number"
              required
              min={1}
              max={31}
              value={cycleStartDay}
              onChange={(e) => onChange({ cycleStartDay: Number(e.target.value) })}
              className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white text-center font-bold outline-none"
            />
          </div>
          <div>
            <label className="block text-[10px] text-slate-400 mb-1 font-bold">
              يوم نهاية الدورة
            </label>
            <input
              type="number"
              required
              min={1}
              max={31}
              value={cycleEndDay}
              onChange={(e) => onChange({ cycleEndDay: Number(e.target.value) })}
              className="w-full bg-slate-950 border border-slate-800 focus:border-teal-500 rounded-xl p-2.5 text-xs text-white text-center font-bold outline-none"
            />
          </div>
        </div>
        <p className="text-[10px] text-slate-505 leading-relaxed text-slate-500">
          حدد يوم البداية ويوم النهاية للشهر المالي. افتراضياً، تبدأ الدورة يوم 25 من الشهر السابق وتنتهي يوم 24 من الشهر الجاري.
        </p>
      </div>
    </div>
  );
}
