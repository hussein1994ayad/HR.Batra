'use client';

import type { Branch } from '@/lib/db-types';
import type { BranchAttendee } from '../logic';
import { MapPin, Users, ExternalLink, CheckCircle } from 'lucide-react';

interface BranchDetailsProps {
  branch: Branch;
  attendees: BranchAttendee[];
}

/** تفاصيل الفرع المحدد والموظفون الذين بصموا داخل نطاقه اليوم. */
export function BranchDetails({ branch, attendees }: BranchDetailsProps) {
  return (
    <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6 text-right animate-fadeIn">
      <div className="border-b border-slate-800 pb-4">
        <h3 className="text-sm font-extrabold text-white flex items-center gap-2">
          <MapPin className="w-5 h-5 text-teal-400" />
          <span>تفاصيل الفرع المحدد: {branch.name}</span>
        </h3>
        <p className="text-[10px] text-slate-400 mt-1">تأكيد النطاق وتفاصيل التواجد للموظفين داخل المدى الجغرافي حالياً</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
        {/* Branch Stats & Verification */}
        <div className="space-y-4 bg-slate-950/30 p-5 rounded-2xl border border-slate-850 flex flex-col justify-between">
          <div className="space-y-4">
            <div className="p-3 bg-teal-500/10 border border-teal-500/10 text-teal-350 rounded-xl text-xs flex items-start gap-2">
              <CheckCircle className="w-4 h-4 text-teal-450 mt-0.5 flex-shrink-0" />
              <div>
                <strong className="block text-[11px] text-white">📍 تأكيد الموقع المعتمد (هاي النقطة هنا صايرة)</strong>
                <span className="text-[10px] opacity-90 leading-relaxed block mt-1">
                  يقع هذا الفرع جغرافياً عند خط عرض <span className="font-mono text-teal-400 font-bold">{branch.latitude}</span> وخط طول <span className="font-mono text-teal-400 font-bold">{branch.longitude}</span>.
                  {branch.address && ` العنوان المعتمد: "${branch.address}".`}
                </span>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="p-3 bg-slate-900/50 rounded-xl border border-slate-800">
                <span className="text-[10px] text-slate-500 block">نطاق البصمة المسموح</span>
                <span className="text-xs font-bold text-white mt-1 block font-mono text-teal-400">
                  {branch.radius_meters || 150} متر
                </span>
              </div>
              <div className="p-3 bg-slate-900/50 rounded-xl border border-slate-800">
                <span className="text-[10px] text-slate-500 block">إجمالي المتواجدين اليوم</span>
                <span className="text-xs font-bold text-white mt-1 block font-mono text-teal-400">
                  {attendees.length} موظف
                </span>
              </div>
            </div>
          </div>

          <div className="pt-4 border-t border-slate-850 mt-4">
            <a
              href={`https://www.google.com/maps/search/?api=1&query=${branch.latitude},${branch.longitude}`}
              target="_blank"
              rel="noopener noreferrer"
              className="w-full py-2.5 bg-slate-950 hover:bg-slate-900 text-white rounded-xl text-xs font-bold transition-all border border-slate-800 flex items-center justify-center gap-2"
            >
              <ExternalLink className="w-3.5 h-3.5 text-teal-400" />
              <span>عرض النقطة على خرائط جوجل 🌐</span>
            </a>
          </div>
        </div>

        {/* Employees Checked-in inside this geofence */}
        <div className="space-y-4">
          <h4 className="text-xs font-bold text-slate-300 flex items-center gap-1.5">
            <Users className="w-4 h-4 text-teal-400" />
            <span>الموظفون المتواجدون داخل محيط الفرع ({attendees.length})</span>
          </h4>

          <div className="space-y-3 max-h-[220px] overflow-y-auto pr-1">
            {attendees.length === 0 ? (
              <div className="text-center py-10 bg-slate-950/20 border border-slate-900 rounded-2xl text-slate-500 text-xs leading-relaxed">
                لا يوجد أي موظفين قاموا بالتبصيم داخل نطاق هذا الفرع اليوم حتى الآن. 😴
              </div>
            ) : (
              attendees.map((emp) => (
                <div
                  key={emp.id}
                  className="p-3 bg-slate-950/50 border border-slate-850 hover:border-slate-800 transition-colors rounded-xl flex justify-between items-center text-xs"
                >
                  <div className="space-y-1">
                    <strong className="text-white block">{emp.name}</strong>
                    <span className="text-[10px] text-slate-500 block">الهاتف: {emp.phone}</span>
                  </div>
                  <div className="text-left space-y-1">
                    <span className="px-2 py-0.5 bg-teal-500/10 border border-teal-500/15 text-teal-400 rounded-md text-[9px] font-bold inline-block">
                      بصم دخول: {emp.checkInTime}
                    </span>
                    <span className="text-[9px] text-slate-400 block font-mono">
                      📍 {emp.distanceText}
                    </span>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
