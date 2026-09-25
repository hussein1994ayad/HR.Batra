type Props = {
  activeTab: 'monitoring' | 'decisions';
  pendingDecisions: number;
  onTabChange: (tab: 'monitoring' | 'decisions') => void;
};

/** التبديل بين المراقبة والخرائط وقرارات الغياب والتأخير. */
export function TrackingTabs({ activeTab, pendingDecisions, onTabChange }: Props) {
  return (
    <div className="flex border-b border-slate-800/80 mb-6 gap-6">
      <button
        onClick={() => onTabChange('monitoring')}
        className={`pb-4 text-xs sm:text-sm font-bold transition-all relative cursor-pointer ${
          activeTab === 'monitoring' 
            ? 'text-teal-400 border-b-2 border-teal-400' 
            : 'text-slate-400 hover:text-white'
        }`}
      >
        المراقبة والخرائط المباشرة
      </button>
      <button
        onClick={() => onTabChange('decisions')}
        className={`pb-4 text-xs sm:text-sm font-bold transition-all relative cursor-pointer flex items-center gap-2 ${
          activeTab === 'decisions' 
            ? 'text-teal-400 border-b-2 border-teal-400' 
            : 'text-slate-400 hover:text-white'
        }`}
      >
        <span>قرارات الغياب والتأخير</span>
        {pendingDecisions > 0 && (
          <span className="bg-amber-500 text-slate-950 font-extrabold text-[9px] px-1.5 py-0.5 rounded-full">
            {pendingDecisions}
          </span>
        )}
      </button>
    </div>
  );
}
