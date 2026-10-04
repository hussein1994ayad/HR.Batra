'use client';

// مركز المراقبة الأمنية بالرئيسية: آخر محاولات الموقع الوهمي وخروقات السياج.

import { AlertTriangle, Clock, MapPin, ShieldAlert, ShieldCheck } from 'lucide-react';
import { Badge, Card, CardHeader, EmptyState, cn } from '@/components/ui';
import { formatLogTime, type SecurityLog } from '../logic';

export function SecurityCenter({ securityLogs, incidents }: { securityLogs: SecurityLog[]; incidents: number }) {
  return (
    <Card className="lg:col-span-2 flex flex-col">
      <CardHeader
        icon={ShieldAlert}
        tone="rose"
        title="مركز المراقبة الأمنية"
        description="أحدث محاولات تزييف المواقع وخروقات السياج الجغرافي"
        actions={
          <Badge tone={incidents > 0 ? 'rose' : 'emerald'}>{incidents} خرق مرصود</Badge>
        }
      />
      {securityLogs.length === 0 ? (
        <EmptyState icon={ShieldCheck} tone="emerald" title="كل شيء آمن" description="لا توجد خروقات مسجلة حالياً" className="flex-grow" />
      ) : (
        <ol className="relative space-y-3 before:absolute before:top-2 before:bottom-2 before:right-[19px] before:w-px before:bg-slate-800">
          {securityLogs.map((log) => {
            const isMock = log.type === 'mock_gps';
            return (
              <li key={log.id} className="relative flex items-start gap-4">
                <div
                  className={cn(
                    'relative z-10 w-10 h-10 shrink-0 rounded-xl border flex items-center justify-center',
                    isMock ? 'bg-rose-950 border-rose-500/30 text-rose-400' : 'bg-amber-950 border-amber-500/30 text-amber-400',
                  )}
                >
                  {isMock ? <MapPin className="w-[18px] h-[18px]" /> : <AlertTriangle className="w-[18px] h-[18px]" />}
                </div>
                <div className="flex-1 min-w-0 p-3.5 rounded-2xl bg-slate-900/50 border border-slate-800/70 hover:border-slate-700/70 transition-colors">
                  <div className="flex items-center justify-between gap-2 mb-1">
                    <h4 className="text-[13px] font-bold text-white truncate">{log.name}</h4>
                    <span className="shrink-0 text-[10px] text-slate-500 flex items-center gap-1" dir="ltr">
                      <Clock className="w-3 h-3" />
                      {formatLogTime(log.timestamp)}
                    </span>
                  </div>
                  <p className="text-xs text-slate-400 leading-relaxed">{log.details}</p>
                  {log.coords && (
                    <span className="inline-block mt-2 text-[10px] bg-slate-950 border border-slate-800 px-2 py-0.5 rounded-md font-mono text-slate-400" dir="ltr">
                      {log.coords}
                    </span>
                  )}
                </div>
              </li>
            );
          })}
        </ol>
      )}
    </Card>
  );
}
