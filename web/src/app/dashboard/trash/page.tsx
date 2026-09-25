'use client';

import React, { useState } from 'react';
import toast from 'react-hot-toast';
import { Trash2, RotateCcw, Trash, FileIcon, Clock, User, HardDrive, AlertTriangle, Sparkles } from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { confetti } from '@/lib/lazy';
import { useQuery } from '@/lib/useQuery';
import { daysUntil, errorMessage, formatBytes, formatDate } from '@/lib/format';
import { bucketFor } from '@/lib/storage';
import type { DeletedFile } from '@/lib/types';
import { useConfirm } from '@/components/confirm';
import { Badge, Button, Card, EmptyState, PageHeader, StatTile } from '@/components/ui';

const TYPE_LABEL: Record<string, string> = {
  avatar: 'صورة شخصية',
  document: 'مستند رسمي',
  pledge: 'تعهد سلفة',
  logo: 'شعار الشركة',
};

async function fetchDeletedFiles(): Promise<DeletedFile[]> {
  const { data, error } = await supabase
    .from('deleted_files')
    .select('*, employees(full_name)')
    .is('restored_at', null)
    .order('deleted_at', { ascending: false });
  if (error) throw error;
  return (data ?? []) as DeletedFile[];
}

export default function TrashPage() {
  const confirm = useConfirm();
  const query = useQuery('trash', fetchDeletedFiles);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const files = query.data ?? [];
  const totalBytes = files.reduce((sum, f) => sum + (Number(f.file_size_bytes) || 0), 0);
  const expiringSoon = files.filter((f) => daysUntil(f.scheduled_deletion_date) <= 7).length;

  const removeLocally = (id: string) => query.mutate((list) => list.filter((f) => f.id !== id));

  const handleRestore = async (file: DeletedFile) => {
    setActionLoading(file.id);
    try {
      const { error } = await supabase.from('deleted_files').update({ restored_at: new Date().toISOString() }).eq('id', file.id);
      if (error) throw error;
      removeLocally(file.id);
      confetti({ particleCount: 50, spread: 40, colors: ['#818CF8', '#34D399'] });
      toast.success('تم استعادة الملف وإرجاعه لمساره الأصلي');
    } catch (err) {
      toast.error(`فشل استعادة الملف: ${errorMessage(err)}`);
    } finally {
      setActionLoading(null);
    }
  };

  const handlePermanentDelete = async (file: DeletedFile) => {
    const ok = await confirm({
      title: 'إتلاف الملف نهائياً؟',
      message: 'سيتم حذف الملف من الخادم بشكل نهائي ولا يمكن التراجع عن هذا الإجراء.',
      confirmLabel: 'إتلاف نهائي',
    });
    if (!ok) return;

    setActionLoading(`${file.id}_delete`);
    try {
      const bucket = bucketFor(file.file_type);
      const { error: storeErr } = await supabase.storage.from(bucket).remove([file.file_path]);
      if (storeErr) throw storeErr;
      const { error: dbErr } = await supabase.from('deleted_files').delete().eq('id', file.id);
      if (dbErr) throw dbErr;
      removeLocally(file.id);
      toast.success('تم إتلاف الملف نهائياً وتحرير مساحته');
    } catch (err) {
      toast.error(`فشل إتلاف الملف: ${errorMessage(err)}`);
    } finally {
      setActionLoading(null);
    }
  };

  return (
    <div className="space-y-6 pb-12">
      <PageHeader
        icon={Trash2}
        tone="rose"
        title="سلة المحذوفات"
        description="تُحفظ الملفات المحذوفة هنا 30 يوماً لإمكانية استعادتها قبل إتلافها تلقائياً"
      />

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <StatTile label="ملفات في السلة" value={files.length} icon={FileIcon} tone="indigo" />
        <StatTile label="المساحة المحجوزة" value={<span dir="ltr">{formatBytes(totalBytes)}</span>} icon={HardDrive} tone="sky" />
        <StatTile label="تُتلف خلال 7 أيام" value={expiringSoon} icon={Clock} tone={expiringSoon > 0 ? 'amber' : 'emerald'} />
      </div>

      <Card>
        {query.loading ? (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="skeleton h-48 rounded-2xl" />
            ))}
          </div>
        ) : query.error && !query.data ? (
          <EmptyState icon={AlertTriangle} tone="rose" title="تعذر تحميل سلة المحذوفات" description={errorMessage(query.error)} action={<Button size="sm" variant="secondary" onClick={query.reload}>إعادة المحاولة</Button>} />
        ) : files.length === 0 ? (
          <EmptyState icon={Sparkles} tone="emerald" title="سلة المحذوفات فارغة" description="لا توجد ملفات محذوفة حالياً. التخزين نظيف!" />
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {files.map((file) => {
              const filename = file.file_path.split('/').pop() || 'ملف مجهول';
              const daysLeft = daysUntil(file.scheduled_deletion_date);
              return (
                <article key={file.id} className="flex flex-col rounded-2xl bg-slate-900/50 border border-slate-800/80 hover:border-slate-700/80 transition-colors p-5">
                  <div className="flex items-start gap-3 mb-4">
                    <div className="w-10 h-10 shrink-0 rounded-xl bg-slate-800/80 border border-slate-700/70 flex items-center justify-center text-slate-300">
                      <FileIcon className="w-5 h-5" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <h4 className="text-xs font-bold text-white truncate" title={filename} dir="ltr">
                        {filename}
                      </h4>
                      <p className="text-[11px] text-slate-500 mt-0.5">{TYPE_LABEL[file.file_type] ?? 'ملف آخر'}</p>
                    </div>
                    <Badge tone={daysLeft <= 7 ? 'rose' : 'amber'}>{daysLeft > 0 ? `${daysLeft} يوم` : 'اليوم'}</Badge>
                  </div>

                  <dl className="space-y-1.5 text-[11px] text-slate-400 mb-4">
                    <div className="flex items-center justify-between">
                      <dt className="flex items-center gap-1.5"><HardDrive className="w-3.5 h-3.5" /> الحجم</dt>
                      <dd className="text-slate-200 font-mono" dir="ltr">{file.file_size_bytes ? formatBytes(file.file_size_bytes) : '—'}</dd>
                    </div>
                    <div className="flex items-center justify-between">
                      <dt className="flex items-center gap-1.5"><User className="w-3.5 h-3.5" /> حُذف بواسطة</dt>
                      <dd className="text-slate-200">{file.employees?.full_name || 'غير معروف'}</dd>
                    </div>
                    <div className="flex items-center justify-between">
                      <dt className="flex items-center gap-1.5"><Clock className="w-3.5 h-3.5" /> تاريخ الحذف</dt>
                      <dd className="text-slate-200 font-mono" dir="ltr">{formatDate(file.deleted_at)}</dd>
                    </div>
                  </dl>

                  <div className="flex gap-2 mt-auto pt-4 border-t border-slate-800/70">
                    <Button size="sm" variant="soft" icon={RotateCcw} block loading={actionLoading === file.id} onClick={() => handleRestore(file)}>
                      استعادة
                    </Button>
                    <Button size="sm" variant="soft-danger" icon={Trash} block loading={actionLoading === `${file.id}_delete`} onClick={() => handlePermanentDelete(file)}>
                      إتلاف نهائي
                    </Button>
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </Card>
    </div>
  );
}
