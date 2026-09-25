'use client';

import type { SecurityLog } from '../types';
import { ShieldAlert, AlertTriangle, Clock, CheckCircle } from 'lucide-react';

interface SecurityIncidentsProps {
  securityLogs: SecurityLog[];
  incidentCount: number;
}

/** آخر محاولات تزييف الموقع ومخالفات السياج الجغرافي. */
export function SecurityIncidents({ securityLogs, incidentCount }: SecurityIncidentsProps) {
  return (
    <div className="lg:col-span-2 bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl flex flex-col">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h3 className="text-lg font-extrabold text-white flex items-center gap-2">
            <ShieldAlert className="w-5 h-5 text-rose-500" />
            <span>مركز المراقبة وسجلات الأمان لليوم</span>
          </h3>
          <p className="text-[11px] text-slate-400">سجل محاولات تزييف المواقع والخروقات المباشرة</p>
        </div>
        <div className="px-3 py-1 bg-rose-500/10 border border-rose-500/20 text-rose-400 rounded-full text-[10px] font-bold">
          {incidentCount} خرق مرصود
        </div>
      </div>

      <div className="flex-grow space-y-4">
        {securityLogs.length === 0 ? (
          <div className="h-48 flex flex-col items-center justify-center text-slate-500 text-xs">
            <CheckCircle className="w-10 h-10 text-emerald-500/40 mb-2 animate-bounce" />
            <span>كل شيء آمن اليوم! لا توجد خروقات مسجلة.</span>
          </div>
        ) : (
          securityLogs.map((log) => (
            <div 
              key={log.id} 
              className={`flex items-start gap-4 p-4 border rounded-2xl transition-all ${
                log.type === 'mock_gps' 
                  ? 'bg-rose-500/5 border-rose-500/10 hover:bg-rose-500/10' 
                  : 'bg-amber-500/5 border-amber-500/10 hover:bg-amber-500/10'
              }`}
            >
              <div className={`p-2.5 rounded-xl border shrink-0 ${
                log.type === 'mock_gps' ? 'bg-rose-500/10 border-rose-500/20 text-rose-400' : 'bg-amber-500/10 border-amber-500/20 text-amber-400'
              }`}>
                <AlertTriangle className="w-5 h-5" />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between mb-1">
                  <h4 className="text-sm font-bold text-white truncate">{log.name}</h4>
                  <span className="text-[9px] text-slate-400 flex items-center gap-1">
                    <Clock className="w-3.5 h-3.5" />
                    {(() => {
                      if (!log.timestamp) return 'غير محدد';
                      const d = new Date(log.timestamp);
                      return isNaN(d.getTime()) ? 'وقت غير صالح' : d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
                    })()}
                  </span>
                </div>
                <p className="text-xs text-slate-300 mb-1">{log.details}</p>
                {log.coords && (
                  <span className="text-[10px] bg-slate-950 px-2 py-0.5 rounded font-mono text-rose-400">
                    {log.coords}
                  </span>
                )}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
