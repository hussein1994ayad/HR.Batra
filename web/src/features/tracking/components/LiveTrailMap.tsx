import dynamic from 'next/dynamic';
import { Map as MapIcon, Radio } from 'lucide-react';
import type { AttendanceRecord } from '@/lib/db-types';
import { Card, CardHeader, Select, Toggle } from '@/components/ui';
import type { DetectedStop, MapMarker } from '../types';

const MapComponent = dynamic(() => import('@/components/MapComponent'), {
  ssr: false,
  loading: () => <div className="skeleton w-full h-full min-h-[420px] rounded-2xl" />,
});

type Props = {
  attendanceLogs: AttendanceRecord[];
  selectedEmployeeForTrail: string | null;
  liveTrackingActive: boolean;
  trailCoordinates: [number, number][];
  detectedStops?: DetectedStop[];
  markers: MapMarker[];
  polygons: { name: string; coords: [number, number][] }[];
  center: [number, number];
  zoom: number;
  onSelectEmployee: (employeeId: string | null) => void;
  onLiveTrackingChange: (active: boolean) => void;
};

/** خريطة البصمات والمواقع الوهمية ومسار حركة الموظف المختار مع توقفاته. */
export function LiveTrailMap({
  attendanceLogs, selectedEmployeeForTrail, liveTrackingActive, trailCoordinates, detectedStops = [], markers, polygons,
  center, zoom, onSelectEmployee, onLiveTrackingChange,
}: Props) {
  // موظف واحد في القائمة حتى لو له أكثر من سجل في الفترة
  const trackable = [...new Map(attendanceLogs.map(l => [l.employee_id, l.employees?.full_name ?? 'موظف'])).entries()];

  return (
    <Card>
      <CardHeader
        icon={MapIcon}
        tone="sky"
        title="خريطة التتبع المباشر"
        description="مواقع بصمات الحضور، محاولات المواقع الوهمية، ومسار حركة الموظف المختار"
        actions={
          <>
            <Select
              value={selectedEmployeeForTrail ?? ''}
              onChange={(e) => onSelectEmployee(e.target.value || null)}
              className="h-9 w-56 text-xs"
            >
              <option value="">اختر موظفاً لعرض مساره...</option>
              {trackable.map(([id, name]) => <option key={id} value={id}>{name}</option>)}
            </Select>
            {selectedEmployeeForTrail && <Toggle checked={liveTrackingActive} onChange={onLiveTrackingChange} label="بث مباشر" />}
          </>
        }
      />
      {selectedEmployeeForTrail && (
        <div className="flex flex-wrap items-center justify-between gap-2 mb-4 px-3.5 py-2.5 rounded-xl bg-sky-500/5 border border-sky-500/15 text-xs">
          <span className="text-slate-300">
            {trailCoordinates.length} نقطة تتبع في آخر يوم من الفترة
            {detectedStops.length > 0 && ` · ${detectedStops.length} توقف لمدة 5 دقائق فأكثر`}
          </span>
          {liveTrackingActive && (
            <span className="flex items-center gap-1.5 font-bold text-emerald-300">
              <Radio className="w-3.5 h-3.5 animate-pulse" /> تحديث مباشر
            </span>
          )}
        </div>
      )}
      <div className="h-[520px]">
        <MapComponent
          markers={markers}
          polygons={polygons}
          polylines={
            selectedEmployeeForTrail && trailCoordinates.length >= 2
              ? [{ coords: trailCoordinates, color: '#60A5FA', weight: 4 }]
              : []
          }
          center={center}
          zoom={zoom}
        />
      </div>
    </Card>
  );
}
