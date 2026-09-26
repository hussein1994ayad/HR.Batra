import { CheckCircle2, Map as MapIcon, ShieldAlert, Timer } from 'lucide-react';
import { StatTile } from '@/components/ui';

type Props = {
  attendanceCount: number;
  lateCount: number;
  mockAttempts: number;
  activeZones: number;
};

/** بطاقات الإحصاء فوق سجل الحضور. */
export function MonitoringStats({ attendanceCount, lateCount, mockAttempts, activeZones }: Props) {
  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
      <StatTile label="سجلات الحضور" value={attendanceCount} icon={CheckCircle2} tone="emerald" />
      <StatTile label="متأخرون" value={lateCount} icon={Timer} tone={lateCount > 0 ? 'amber' : 'slate'} />
      <StatTile label="محاولات موقع وهمي" value={mockAttempts} icon={ShieldAlert} tone={mockAttempts > 0 ? 'rose' : 'emerald'} />
      <StatTile label="مناطق السياج النشطة" value={activeZones} icon={MapIcon} tone="sky" />
    </div>
  );
}
