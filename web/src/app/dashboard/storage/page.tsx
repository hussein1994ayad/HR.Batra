'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import toast from 'react-hot-toast';
import { HardDrive, AlertTriangle, Trash2, RefreshCw, ShieldCheck, ArrowUpLeft } from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { confetti } from '@/lib/lazy';
import { useQuery } from '@/lib/useQuery';
import { bucketFor } from '@/lib/storage';
import { errorMessage, formatBytes } from '@/lib/format';
import type { DeletedFile, StorageStat } from '@/lib/types';
import { useConfirm } from '@/components/confirm';
import { Button, Card, CardHeader, InfoNote, PageHeader, PageSkeleton, cn } from '@/components/ui';

// Supabase free tier storage quota.
const MAX_CAPACITY_BYTES = 3 * 1024 * 1024 * 1024;

interface StorageData {
  avatars: number;
  documents: number;
  pledges: number;
  others: number;
  trash: number;
}

async function fetchStorage(): Promise<StorageData> {
  const [{ data: trashRows }, { data: stats }] = await Promise.all([
    supabase.from('deleted_files').select('file_size_bytes').is('restored_at', null),
    supabase.rpc('get_storage_stats'),
  ]);
  const result: StorageData = { avatars: 0, documents: 0, pledges: 0, others: 0, trash: 0 };
  (trashRows ?? []).forEach((r) => (result.trash += Number(r.file_size_bytes) || 0));
  ((stats ?? []) as StorageStat[]).forEach((s) => {
    const size = Number(s.total_size) || 0;
    if (s.bucket_name === 'avatars') result.avatars += size;
    else if (s.bucket_name === 'employee-documents') result.documents += size;
    else if (s.bucket_name === 'loan-pledges') result.pledges += size;
    else result.others += size;
  });
  return result;
}

export default function StoragePage() {
  const confirm = useConfirm();
  const query = useQuery('storage', fetchStorage);
  const [emptying, setEmptying] = useState(false);

  if (!query.data) return <PageSkeleton rows={3} />;

  const s = query.data;
  const total = s.avatars + s.documents + s.pledges + s.others + s.trash;
  const ratio = total / MAX_CAPACITY_BYTES;
  const isWarning = ratio >= 0.8;
  const categories = [
    { name: 'المستندات والوثائق', size: s.documents, color: 'bg-indigo-400' },
    { name: 'تعهدات السلف', size: s.pledges, color: 'bg-sky-400' },
    { name: 'الصور الشخصية', size: s.avatars, color: 'bg-violet-400' },
    { name: 'سلة المحذوفات', size: s.trash, color: 'bg-rose-400' },
    { name: 'ملفات أخرى', size: s.others, color: 'bg-amber-400' },
  ];

  const handleEmptyTrash = async () => {
    const ok = await confirm({
      title: 'إفراغ سلة المحذوفات بالكامل؟',
      message: 'سيتم حذف كل الملفات الموجودة في السلة من الخادم نهائياً ولن تتمكن من استعادتها.',
      confirmLabel: 'إفراغ السلة',
    });
    if (!ok) return;

    setEmptying(true);
    try {
      const { data: files } = await supabase.from('deleted_files').select('*').is('restored_at', null);
      for (const file of (files ?? []) as DeletedFile[]) {
        await supabase.storage.from(bucketFor(file.file_type)).remove([file.file_path]);
      }
      const { error } = await supabase.from('deleted_files').delete().is('restored_at', null);
      if (error) throw error;
      query.mutate((prev) => ({ ...prev, trash: 0 }));
      confetti({ particleCount: 100, spread: 70, colors: ['#F43F5E', '#FB7185'] });
      toast.success('تم إفراغ سلة المحذوفات وتحرير المساحة');
    } catch (err) {
      toast.error(`فشل إفراغ السلة: ${errorMessage(err)}`);
    } finally {
      setEmptying(false);
    }
  };

  return (
    <div className="space-y-6 pb-12">
      <PageHeader
        icon={HardDrive}
        tone="sky"
        title="التخزين"
        description="المساحة المستهلكة من باقة Supabase Storage موزعة حسب نوع الملفات"
        actions={
          <Button variant="secondary" size="sm" icon={RefreshCw} loading={query.refreshing} onClick={query.reload}>
            تحديث
          </Button>
        }
      />

      <Card>
        <div className="flex flex-col md:flex-row md:items-end justify-between gap-4 mb-6">
          <div>
            <p className="text-xs text-slate-400 mb-1">المساحة المستهلكة</p>
            <p className={cn('text-4xl font-extrabold tracking-tight', isWarning ? 'text-rose-400' : 'text-white')} dir="ltr">
              {formatBytes(total)}
            </p>
            <p className="text-xs text-slate-500 mt-1">
              من أصل <span dir="ltr">{formatBytes(MAX_CAPACITY_BYTES)}</span> · متبقي <span dir="ltr">{formatBytes(Math.max(MAX_CAPACITY_BYTES - total, 0))}</span>
            </p>
          </div>
          <div className={cn('text-2xl font-extrabold', isWarning ? 'text-rose-300' : 'text-indigo-200')} dir="ltr">
            {(ratio * 100).toFixed(1)}%
          </div>
        </div>

        <div className="w-full h-3 bg-slate-950 rounded-full overflow-hidden flex border border-slate-800" dir="ltr">
          {categories.map((cat) => (
            <div
              key={cat.name}
              className={cn(cat.color, 'h-full transition-all duration-700')}
              style={{ width: `${(cat.size / MAX_CAPACITY_BYTES) * 100}%` }}
              title={`${cat.name}: ${formatBytes(cat.size)}`}
            />
          ))}
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3 mt-6">
          {categories.map((cat) => (
            <div key={cat.name} className="rounded-2xl bg-slate-900/50 border border-slate-800/80 p-4">
              <div className="flex items-center gap-2 mb-2">
                <span className={cn('w-2.5 h-2.5 rounded-full', cat.color)} />
                <span className="text-xs font-bold text-slate-200 truncate">{cat.name}</span>
              </div>
              <div className="flex items-baseline justify-between">
                <span className="text-sm font-extrabold text-white" dir="ltr">{formatBytes(cat.size)}</span>
                <span className="text-[11px] text-slate-500 font-mono" dir="ltr">
                  {total > 0 ? ((cat.size / total) * 100).toFixed(1) : '0.0'}%
                </span>
              </div>
            </div>
          ))}
        </div>
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <Card className="lg:col-span-2">
          <CardHeader
            icon={isWarning ? AlertTriangle : ShieldCheck}
            tone={isWarning ? 'rose' : 'emerald'}
            title={isWarning ? 'التخزين يوشك على الامتلاء' : 'حالة التخزين مستقرة'}
            className="mb-3"
          />
          <InfoNote tone={isWarning ? 'rose' : 'emerald'}>
            {isWarning
              ? 'تجاوز الاستهلاك 80% من المساحة المتاحة. أفرغ سلة المحذوفات أو قلّص أحجام الملفات لتجنب توقف رفع المستندات وتعهدات السلف.'
              : 'المساحة ضمن الحدود الآمنة. يُنصح بتصفية سلة المحذوفات دورياً للحفاظ على أفضل أداء.'}
          </InfoNote>
        </Card>

        <Card>
          <CardHeader icon={Trash2} tone="rose" title="تحرير المساحة" description="إتلاف كل الملفات الموجودة في سلة المحذوفات" className="mb-4" />
          <Button variant="soft-danger" icon={Trash2} block size="lg" loading={emptying} disabled={s.trash === 0} onClick={handleEmptyTrash}>
            إفراغ السلة ({formatBytes(s.trash)})
          </Button>
          <Link href="/dashboard/trash" className="mt-3 flex items-center justify-center gap-1 text-[11px] font-semibold text-slate-400 hover:text-white">
            استعراض محتويات السلة <ArrowUpLeft className="w-3.5 h-3.5" />
          </Link>
        </Card>
      </div>
    </div>
  );
}
