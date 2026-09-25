type Props = {
  attendanceCount: number;
  mockAttempts: number;
  activeZones: number;
};

/** مؤشرات سريعة: الحضور، محاولات التزييف، السياجات. */
export function MonitoringStats({ attendanceCount, mockAttempts, activeZones }: Props) {
  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
      <div className="bg-slate-950/40 border border-slate-850 rounded-2xl p-4 text-center">
        <span className="text-[10px] text-slate-400 block mb-1">الموظفين الحاضرين بالخريطة</span>
        <span className="text-xl font-black text-teal-400">{attendanceCount}</span>
      </div>
      <div className="bg-slate-950/40 border border-slate-850 rounded-2xl p-4 text-center">
        <span className="text-[10px] text-slate-400 block mb-1">رصد التزييف الجغرافي (Mock)</span>
        <span className="text-xl font-black text-rose-500">{mockAttempts}</span>
      </div>
      <div className="bg-slate-950/40 border border-slate-850 rounded-2xl p-4 text-center">
        <span className="text-[10px] text-slate-400 block mb-1">سياجات جغرافية نشطة</span>
        <span className="text-xl font-black text-blue-400">{activeZones}</span>
      </div>
      <div className="bg-slate-950/40 border border-slate-850 rounded-2xl p-4 text-center">
        <span className="text-[10px] text-slate-400 block mb-1">نسبة الأمان للمؤسسة</span>
        <span className="text-xl font-black text-emerald-400">
          {mockAttempts === 0 ? '100%' : '94.2%'}
        </span>
      </div>
    </div>
  );
}
