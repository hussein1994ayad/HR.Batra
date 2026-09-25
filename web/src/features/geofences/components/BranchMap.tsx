'use client';

import MapComponent from '@/components/MapComponent';
import type { MapCircle } from '../logic';
import { Globe } from 'lucide-react';

interface BranchMapProps {
  mapCircles: MapCircle[];
  selectedBranchId: string | null;
  mapCenter: [number, number];
  mapZoom: number;
  onSelect: (branchId: string) => void;
  onMapClick: (lat: number, lng: number) => void;
}

/** خريطة دوائر الفروع؛ النقر على الخريطة يبدأ إضافة فرع في تلك النقطة. */
export function BranchMap({ mapCircles, selectedBranchId, mapCenter, mapZoom, onSelect, onMapClick }: BranchMapProps) {
  return (
    <div className="lg:col-span-2 bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl flex flex-col justify-between min-h-[500px]">
      <div className="mb-4">
        <h3 className="text-sm font-extrabold text-white flex items-center gap-1.5">
          <Globe className="w-5 h-5 text-teal-400" />
          <span>مخطط الفروع الجغرافية التفاعلي (Geofence Circles)</span>
        </h3>
        <p className="text-[10px] text-slate-400">انقر على الخريطة لتحديد إحداثيات الفرع وتعبئة الحقول فوراً، أو اضغط على دائرة الفرع لعرض تفاصيلها</p>
      </div>

      <div className="flex-grow relative h-full">
        <MapComponent 
          circles={mapCircles}
          selectedCircleId={selectedBranchId}
          center={mapCenter}
          zoom={mapZoom}
          onCircleClick={onSelect}
          onMapClick={onMapClick}
        />
      </div>
    </div>
  );
}
