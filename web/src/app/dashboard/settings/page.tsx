'use client';

// صفحة الإعدادات: 4 تبويبات (عام، جداول الدوام، التعاميم، تنظيف البيانات).
// البيانات في features/settings/api، وكل تبويب مكوّن في features/settings/components.

import { useState } from 'react';
import { AlertTriangle, Building, CalendarClock, Eraser, Megaphone, Settings } from 'lucide-react';
import { useQuery } from '@/lib/useQuery';
import { errorMessage } from '@/lib/format';
import { Button, EmptyState, PageHeader, PageSkeleton, SegmentedTabs } from '@/components/ui';
import { fetchSettings } from '@/features/settings/api';
import { GeneralSettings } from '@/features/settings/components/GeneralSettings';
import { SchedulesSection } from '@/features/settings/components/SchedulesSection';
import { AnnouncementsSection } from '@/features/settings/components/AnnouncementsSection';
import { DatabasePurgeSection } from '@/features/settings/components/DatabasePurgeSection';

export default function SettingsPage() {
  const query = useQuery('settings', fetchSettings);
  const [section, setSection] = useState<'general' | 'schedules' | 'announcements' | 'cleanup'>('general');

  if (!query.data) {
    if (query.error) {
      return <EmptyState icon={AlertTriangle} tone="rose" title="تعذر تحميل الإعدادات" description={errorMessage(query.error)} action={<Button size="sm" variant="secondary" onClick={query.reload}>إعادة المحاولة</Button>} />;
    }
    return <PageSkeleton />;
  }

  return (
    <div className="space-y-6 pb-12">
      <PageHeader
        icon={Settings}
        title="الإعدادات"
        description="بيانات الشركة، سياسات الإجازات والرواتب، جداول الدوام، والتعاميم"
        actions={
          <SegmentedTabs
            value={section}
            onChange={setSection}
            options={[
              { value: 'general', label: 'عام', icon: Building },
              { value: 'schedules', label: 'جداول الدوام', icon: CalendarClock, count: query.data.schedules.length },
              { value: 'announcements', label: 'التعاميم', icon: Megaphone, count: query.data.announcements.length },
              { value: 'cleanup', label: 'تنظيف البيانات', icon: Eraser },
            ]}
          />
        }
      />

      {section === 'general' && <GeneralSettings initial={query.data} onSaved={query.reload} />}
      {section === 'schedules' && <SchedulesSection data={query.data} onChanged={query.reload} />}
      {section === 'cleanup' && <DatabasePurgeSection />}
      {section === 'announcements' && (
        <AnnouncementsSection
          announcements={query.data.announcements}
          onRemoved={(ids) => query.mutate((d) => ({ ...d, announcements: d.announcements.filter((a) => !ids.includes(a.id)) }))}
        />
      )}
    </div>
  );
}
