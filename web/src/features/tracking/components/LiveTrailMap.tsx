import { Map, Users } from 'lucide-react';
import MapComponent from '@/components/MapComponent';
import type { AttendanceRecord } from '@/lib/db-types';
import type { MapMarker } from '../types';

type Props = {
  attendanceLogs: AttendanceRecord[];
  selectedEmployeeForTrail: string | null;
  liveTrackingActive: boolean;
  trailCoordinates: [number, number][];
  markers: MapMarker[];
  polygons: { name: string; coords: [number, number][] }[];
  center: [number, number];
  zoom: number;
  onSelectEmployee: (employeeId: string | null) => void;
  onLiveTrackingChange: (active: boolean) => void;
};

/** خريطة التتبع ومسار حركة الموظف المختار (مع بث مباشر اختياري). */
export function LiveTrailMap({
  attendanceLogs, selectedEmployeeForTrail, liveTrackingActive, trailCoordinates, markers, polygons, center, zoom,
  onSelectEmployee, onLiveTrackingChange,
}: Props) {
  return (
    <div className="mt-8 pt-8 border-t border-slate-800/80 space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h3 className="text-lg font-extrabold text-white flex items-center gap-2 mb-1">
            <Map className="w-5 h-5 text-teal-400" />
            <span>خريطة التتبع المباشر وحركة الموظفين</span>
          </h3>
          <p className="text-[11px] text-slate-400">تتبع مسار حركة الموظفين ميدانياً على الخريطة في الوقت الفعلي أثناء ساعات العمل</p>
        </div>

        <div className="flex flex-wrap items-center gap-3 bg-slate-950/40 p-2 border border-slate-800 rounded-2xl">
          {/* Select Employee to Track */}
          <div className="flex items-center gap-2 bg-slate-900 border border-slate-800 rounded-xl px-3 py-1.5">
            <Users className="w-3.5 h-3.5 text-teal-400" />
            <select
              value={selectedEmployeeForTrail || ''}
              onChange={(e) => onSelectEmployee(e.target.value || null)}
              className="bg-transparent border-none text-white text-xs outline-none cursor-pointer"
            >
              <option value="" className="bg-slate-900">اختر موظف لتتبع مساره...</option>
              {attendanceLogs.map((log) => (
                <option key={log.employee_id} value={log.employee_id} className="bg-slate-900">
                  {log.employees?.full_name}
                </option>
              ))}
            </select>
          </div>

          {selectedEmployeeForTrail && (
            <label className="flex items-center gap-2 cursor-pointer bg-slate-900 border border-slate-800 rounded-xl px-3 py-1.5 select-none">
              <input
                type="checkbox"
                checked={liveTrackingActive}
                onChange={(e) => onLiveTrackingChange(e.target.checked)}
                className="rounded border-slate-800 text-teal-500 focus:ring-teal-500 bg-slate-950 w-3.5 h-3.5"
              />
              <span className="text-xs text-slate-300 font-bold">بث مباشر متواصل (أونلاين) 🟢</span>
            </label>
          )}
        </div>
      </div>

      {selectedEmployeeForTrail && trailCoordinates.length > 0 && (
        <div className="p-4 bg-teal-950/10 border border-teal-500/10 rounded-2xl flex justify-between items-center text-xs animate-glass">
          <div className="space-y-1">
            <p className="text-slate-300">
              • إجمالي نقاط الحركة المرصودة اليوم: <strong className="text-white font-bold">{trailCoordinates.length} نقطة تتبع</strong>
            </p>
            <p className="text-[10px] text-slate-400">
              * يربط الخط المتقطع الأزرق بين مسار تنقلات الموظف منذ بصمة الحضور وحتى اللحظة.
            </p>
          </div>
          {liveTrackingActive && (
            <span className="flex items-center gap-1.5 text-xs text-teal-400 font-black animate-pulse">
              <span className="w-2.5 h-2.5 bg-teal-400 rounded-full"></span>
              <span>تحديث فوري نشط...</span>
            </span>
          )}
        </div>
      )}

      <div className="flex-grow min-h-[500px] relative rounded-2xl overflow-hidden border border-slate-800/60">
        <MapComponent 
          markers={markers}
          polygons={polygons}
          polylines={
            selectedEmployeeForTrail && trailCoordinates.length >= 2
              ? [{ coords: trailCoordinates, color: '#3B82F6', weight: 4.5 }]
              : []
          }
          center={center}
          zoom={zoom}
        />
      </div>
    </div>
  );
}
