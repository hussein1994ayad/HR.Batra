'use client';

// تبويب أرشيف التعاميم: حالة كل تعميم حسب مدته، حذف تعميم، وإخلاء الأرشيف.

import { useState } from 'react';
import toast from 'react-hot-toast';
import { Clock, Megaphone, Pin, Trash2 } from 'lucide-react';
import { errorMessage, formatDateTime } from '@/lib/format';
import type { Announcement } from '@/lib/db-types';
import { useConfirm } from '@/components/confirm';
import { Badge, Button, Card, CardHeader, EmptyState, IconButton } from '@/components/ui';
import { deleteAllAnnouncements, deleteAnnouncement } from '../api';

/** حالة التعميم حسب مدته: ساري / مجدول / منتهٍ (المنتهي لا يظهر في التطبيق). */
function AnnouncementStatus({ a, now }: { a: Announcement; now: number }) {
  const starts = a.starts_at ? Date.parse(a.starts_at) : Date.parse(a.created_at);
  const ends = a.ends_at ? Date.parse(a.ends_at) : null;
  const audience = a.target_employee_ids?.length ? `${a.target_employee_ids.length} موظف` : a.target_branch_id ? 'فرع' : 'الجميع';
  const state =
    ends !== null && ends <= now
      ? { tone: 'slate' as const, label: 'منتهٍ' }
      : starts > now
        ? { tone: 'amber' as const, label: 'مجدول' }
        : { tone: 'emerald' as const, label: 'ساري' };
  return (
    <>
      <Badge tone={state.tone} dot>
        {state.label}
      </Badge>
      <Badge tone="sky">{audience}</Badge>
    </>
  );
}

export function AnnouncementsSection({ announcements, onRemoved }: { announcements: Announcement[]; onRemoved: (ids: string[]) => void }) {
  const [now] = useState(() => Date.now());
  const confirm = useConfirm();
  const [busy, setBusy] = useState<string | null>(null);

  const remove = async (a: Announcement) => {
    const ok = await confirm({ title: 'حذف التعميم؟', message: a.content, confirmLabel: 'حذف' });
    if (!ok) return;
    setBusy(a.id);
    const error = await deleteAnnouncement(a.id);
    setBusy(null);
    if (error) {
      toast.error(`فشل حذف التعميم: ${errorMessage(error)}`);
      return;
    }
    onRemoved([a.id]);
    toast.success('تم حذف التعميم');
  };

  const purge = async () => {
    const ok = await confirm({ title: 'إخلاء أرشيف التعاميم بالكامل؟', message: 'سيتم حذف كل التعاميم نهائياً ولا يمكن التراجع.', confirmLabel: 'إخلاء الأرشيف' });
    if (!ok) return;
    setBusy('purge');
    const error = await deleteAllAnnouncements();
    setBusy(null);
    if (error) {
      toast.error(`فشل إخلاء الأرشيف: ${errorMessage(error)}`);
      return;
    }
    onRemoved(announcements.map((a) => a.id));
    toast.success('تم إخلاء أرشيف التعاميم');
  };

  return (
    <Card>
      <CardHeader
        icon={Megaphone}
        tone="violet"
        title="أرشيف التعاميم"
        description="التعاميم المرسلة للموظفين من لوحة المؤشرات"
        actions={
          announcements.length > 0 && (
            <Button size="sm" variant="soft-danger" icon={Trash2} loading={busy === 'purge'} onClick={purge}>
              إخلاء الأرشيف
            </Button>
          )
        }
      />
      {announcements.length === 0 ? (
        <EmptyState icon={Megaphone} title="لا توجد تعاميم" description="التعاميم المرسلة من لوحة المؤشرات ستظهر هنا." />
      ) : (
        <div className="space-y-2">
          {announcements.map((a) => (
            <div key={a.id} className="flex items-start gap-3 p-4 rounded-2xl bg-slate-900/50 border border-slate-800/80">
              <div className="w-9 h-9 shrink-0 rounded-xl bg-violet-500/10 border border-violet-500/20 text-violet-300 flex items-center justify-center">
                <Megaphone className="w-4 h-4" />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex flex-wrap items-center gap-2 mb-1">
                  <h4 className="text-[13px] font-bold text-white">{a.title}</h4>
                  {a.is_pinned && <Badge tone="violet"><Pin className="w-3 h-3" /> مثبت</Badge>}
                  <AnnouncementStatus a={a} now={now} />
                  <span className="text-[10px] text-slate-500 flex items-center gap-1" dir="ltr">
                    <Clock className="w-3 h-3" /> {formatDateTime(a.starts_at ?? a.created_at)}
                    {a.ends_at ? <> → {formatDateTime(a.ends_at)}</> : null}
                  </span>
                </div>
                <p className="text-xs text-slate-400 leading-relaxed whitespace-pre-line">{a.content}</p>
              </div>
              <IconButton icon={Trash2} label="حذف التعميم" tone="rose" loading={busy === a.id} onClick={() => remove(a)} />
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
