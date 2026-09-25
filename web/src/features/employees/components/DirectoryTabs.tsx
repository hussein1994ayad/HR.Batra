'use client';


interface DirectoryTabsProps {
  activeTab: 'active' | 'archived';
  archivedCount: number;
  onTabChange: (tab: 'active' | 'archived') => void;
}

/** التبديل بين دليل الموظفين النشطين والأرشيف. */
export function DirectoryTabs({ activeTab, archivedCount, onTabChange }: DirectoryTabsProps) {
  return (
    <div className="flex gap-2 p-1.5 bg-slate-950/80 border border-slate-800 rounded-2xl w-fit mb-4">
      <button
        type="button"
        onClick={() => onTabChange('active')}
        className={`px-4 py-2 rounded-xl text-xs font-bold transition-all cursor-pointer ${
          activeTab === 'active' 
            ? 'bg-teal-600 text-white shadow-md shadow-teal-500/10' 
            : 'text-slate-400 hover:text-white'
        }`}
      >
        👤 دليل الكوادر النشطة
      </button>
      <button
        type="button"
        onClick={() => onTabChange('archived')}
        className={`px-4 py-2 rounded-xl text-xs font-bold transition-all cursor-pointer ${
          activeTab === 'archived' 
            ? 'bg-amber-600 text-white shadow-md shadow-amber-500/10' 
            : 'text-slate-400 hover:text-white'
        }`}
      >
        🗄️ الأرشيف والحذف المجدول ({archivedCount})
      </button>
    </div>
  );
}
