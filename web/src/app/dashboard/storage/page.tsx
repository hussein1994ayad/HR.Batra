'use client';

// صفحة التخزين والمساحة: استهلاك قاعدة البيانات والتخزين السحابي مقابل حدود باقة Supabase المجانية.
// البيانات في features/storage/api، والحالة والنسب في features/storage/useStorageStats.

import { Gauge, RefreshCw } from 'lucide-react';
import { Button, PageHeader, PageSkeleton } from '@/components/ui';
import { useStorageStats } from '@/features/storage/useStorageStats';
import { StorageSummary } from '@/features/storage/components/StorageSummary';
import { TableSizesCard } from '@/features/storage/components/TableSizesCard';
import { BucketsCard } from '@/features/storage/components/BucketsCard';
import { StorageStatusPanel } from '@/features/storage/components/StorageStatusPanel';

export default function StoragePage() {
  const s = useStorageStats();

  if (s.loading) return <PageSkeleton />;

  return (
    <div className="space-y-6 pb-12" dir="rtl">
      <PageHeader
        icon={Gauge}
        tone="teal"
        title="التخزين والمساحة"
        description="عرض لحظي لكل شيء يستهلك مساحة من خوادم Supabase: قاعدة البيانات والتخزين السحابي للملفات"
        actions={<Button size="sm" variant="secondary" icon={RefreshCw} onClick={s.fetchAllStats}>تحديث لحظي</Button>}
      />

      <StorageSummary s={s} />
      <TableSizesCard s={s} />
      <BucketsCard s={s} />
      <StorageStatusPanel s={s} />
    </div>
  );
}
