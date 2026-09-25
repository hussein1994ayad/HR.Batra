'use client';

import type { EmployeeDevice } from '@/lib/db-types';
import { Smartphone, Check, X } from 'lucide-react';

interface DeviceRequestsAlertProps {
  deviceRequests: EmployeeDevice[];
  actionLoading: string | null;
  onProcess: (request: EmployeeDevice, approve: boolean) => void;
}

/** طلبات ربط الأجهزة الجديدة بانتظار اعتماد الإدارة. */
export function DeviceRequestsAlert({ deviceRequests, actionLoading, onProcess }: DeviceRequestsAlertProps) {
  return (
    <div className="bg-purple-950/20 border border-purple-500/20 rounded-3xl p-6 shadow-xl space-y-4">
      <div className="flex items-center gap-2 text-purple-400">
        <Smartphone className="w-6 h-6 animate-pulse" />
        <h3 className="text-base font-extrabold text-white">طلبات ربط واعتماد الأجهزة المعلقة ({deviceRequests.length})</h3>
      </div>
      <p className="text-xs text-slate-300 leading-relaxed">
        قام الموظفون أدناه بتسجيل الدخول من هواتف جديدة أو طلبوا تغيير جهازهم المقفل. يرجى مراجعة واعتماد طلباتهم لتفعيل تسجيل دوامهم الجغرافي بأمان.
      </p>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 pt-2">
        {deviceRequests.map((req) => (
          <div 
            key={req.id} 
            className="bg-slate-900/60 backdrop-blur border border-slate-800/80 rounded-2xl p-4 flex flex-col justify-between"
          >
            <div className="mb-4">
              <div className="flex items-center justify-between mb-2">
                <h4 className="text-xs font-bold text-white">{req.employees?.full_name || 'موظف'}</h4>
                <span className="text-[9px] bg-purple-500/20 text-purple-300 px-2 py-0.5 rounded-full border border-purple-500/30">
                  طلب اعتماد
                </span>
              </div>
              <div className="space-y-1 text-[10px] text-slate-400">
                <p>موديل الجهاز: <span className="text-slate-200 font-bold">{req.model || 'غير محدد'}</span></p>
                <p>نظام التشغيل: <span className="text-slate-200">{req.os_version || 'غير محدد'}</span></p>
                <p className="font-mono text-purple-300">ID: {req.device_id}</p>
              </div>
            </div>

            <div className="flex gap-2">
              <button
                disabled={actionLoading === req.id}
                onClick={() => onProcess(req, true)}
                className="flex-1 flex items-center justify-center gap-1.5 py-2 px-3 bg-teal-650 hover:bg-teal-500 text-white rounded-xl text-[10px] font-bold shadow transition-colors cursor-pointer"
              >
                <Check className="w-3.5 h-3.5" />
                <span>اعتماد واعتماد القفل</span>
              </button>
              <button
                disabled={actionLoading === req.id}
                onClick={() => onProcess(req, false)}
                className="flex-1 flex items-center justify-center gap-1.5 py-2 px-3 bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/20 rounded-xl text-[10px] font-bold transition-colors cursor-pointer"
              >
                <X className="w-3.5 h-3.5" />
                <span>رفض الطلب</span>
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
