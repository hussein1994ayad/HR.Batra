'use client';

import { Loader2, Settings } from 'lucide-react';
import { useSettings } from '@/features/settings/useSettings';
import { AnnouncementsSection } from '@/features/settings/components/AnnouncementsSection';
import { DatabasePurgeSection } from '@/features/settings/components/DatabasePurgeSection';
import { GeneralSettingsForm } from '@/features/settings/components/GeneralSettingsForm';
import { WorkSchedulesSection } from '@/features/settings/components/WorkSchedulesSection';

export default function SettingsPage() {
  const s = useSettings();

  if (s.loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  if (!s.data) {
    return (
      <div className="flex-grow flex items-center justify-center text-slate-400 text-sm">
        تعذر تحميل الإعدادات. يرجى تحديث الصفحة.
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12">
      <div className="bg-slate-900/60 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
        <div>
          <h3 className="text-xl font-extrabold text-white flex items-center gap-2 mb-2">
            <Settings className="w-6 h-6 text-teal-400 animate-spin-slow" />
            <span>إعدادات النظام والشركة العامة</span>
          </h3>
          <p className="text-xs text-slate-400">تحديث وتعديل بيانات ومحددات الشركة، وسياسات أرشفة التتبع والملفات</p>
        </div>
      </div>

      {/* يُعاد إنشاء النموذج بعد كل تحميل حتى يعرض القيم المحفوظة */}
      <GeneralSettingsForm key={s.version} initial={s.data.general} saving={s.saving} onSave={(values) => void s.saveGeneral(values)} />

      <DatabasePurgeSection onPurge={s.purge} />

      <WorkSchedulesSection
        workSchedules={s.data.workSchedules}
        branchesList={s.data.branches}
        departmentsList={s.data.departments}
        employeesList={s.data.employees}
        onAdd={s.addSchedule}
        onDelete={(id) => void s.removeSchedule(id)}
      />

      <AnnouncementsSection
        announcements={s.data.announcements}
        loadingAnnouncements={s.loadingAnnouncements}
        onDelete={(id) => void s.removeAnnouncement(id)}
        onDeleteAll={() => void s.removeAllAnnouncements()}
      />
    </div>
  );
}
