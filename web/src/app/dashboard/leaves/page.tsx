'use client';

import React, { useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import { ReasonModal } from '@/components/ReasonModal';
import {
  CalendarRange,
  Check,
  X,
  Calendar,
  FileText,
  ShieldCheck,
  Paperclip,
  Clock,
  Hourglass,
  CheckCircle2,
  XCircle,
  AlertTriangle,
} from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { confetti } from '@/lib/lazy';
import { useQuery } from '@/lib/useQuery';
import { toDateKey } from '@/lib/attendance';
import { errorMessage, formatDateTime } from '@/lib/format';
import type { LeaveRequest, RequestStatus } from '@/lib/types';
import { Avatar, Badge, Button, Card, EmptyState, PageHeader, SearchInput, SegmentedTabs, Toggle, cn } from '@/components/ui';
import { openStorageUrl } from '@/lib/signed-urls';

const LEAVE_TYPES: Record<string, string> = {
  annual: 'إجازة سنوية',
  sick: 'إجازة مرضية',
  emergency: 'إجازة طارئة',
  maternity: 'إجازة أمومة',
};

async function fetchLeaves(status: RequestStatus): Promise<LeaveRequest[]> {
  const { data, error } = await supabase
    .from('leave_requests')
    .select(
      `*,
      employees!leave_requests_employee_id_fkey(full_name),
      approver:employees!leave_requests_approved_by_fkey(full_name)`,
    )
    .eq('status', status)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return (data ?? []) as LeaveRequest[];
}

function leaveDays(req: LeaveRequest): number {
  const start = new Date(toDateKey(req.start_date));
  const end = new Date(toDateKey(req.end_date));
  return Math.round(Math.abs(end.getTime() - start.getTime()) / 86_400_000) + 1;
}

export default function LeavesPage() {
  const [activeTab, setActiveTab] = useState<RequestStatus>('pending');
  const [search, setSearch] = useState('');
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  // Admin may override whether a pending leave is paid before approving it.
  const [paidOverride, setPaidOverride] = useState<Record<string, boolean>>({});

  const query = useQuery(`leaves:${activeTab}`, () => fetchLeaves(activeTab));
  const requests = useMemo(() => {
    const list = query.refreshing ? [] : query.data ?? [];
    const q = search.trim().toLowerCase();
    return q ? list.filter((r) => (r.employees?.full_name || '').toLowerCase().includes(q)) : list;
  }, [query.data, query.refreshing, search]);
  const isLoading = query.loading || query.refreshing;

  const [rejecting, setRejecting] = useState<LeaveRequest | null>(null);

  const handleProcess = async (req: LeaveRequest, approve: boolean, isPaid: boolean, rejectionReason = '') => {
    setRejecting(null);
    setActionLoading(req.id);
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession();
      if (!session) return;

      const { error } = await supabase
        .from('leave_requests')
        .update({
          status: approve ? 'approved' : 'rejected',
          is_paid: approve ? isPaid : undefined,
          rejection_reason: !approve && rejectionReason ? rejectionReason : undefined,
          approved_by: session.user.id,
          approved_at: new Date().toISOString(),
        })
        .eq('id', req.id);
      if (error) throw error;

      // إشعار الموظف بالقرار (مع سبب الرفض) يُرسل من قاعدة البيانات: trg_notify_employee_leave_decision

      query.mutate((list) => list.filter((r) => r.id !== req.id));
      if (approve) confetti({ particleCount: 80, spread: 60, colors: ['#10B981', '#059669', '#34D399'] });
      toast.success(approve ? 'تمت الموافقة على طلب الإجازة' : 'تم رفض طلب الإجازة');
    } catch (err) {
      toast.error(`فشل في معالجة طلب الإجازة: ${errorMessage(err)}`);
    } finally {
      setActionLoading(null);
    }
  };

  return (
    <div className="space-y-6 pb-12">
      <PageHeader
        icon={CalendarRange}
        tone="amber"
        title="الإجازات"
        description="مراجعة واعتماد طلبات الإجازات وأرشيف القرارات السابقة"
        actions={
          <SegmentedTabs
            value={activeTab}
            onChange={setActiveTab}
            options={[
              { value: 'pending', label: 'معلقة', icon: Hourglass, count: activeTab === 'pending' && !isLoading ? requests.length : undefined },
              { value: 'approved', label: 'معتمدة', icon: CheckCircle2 },
              { value: 'rejected', label: 'مرفوضة', icon: XCircle },
            ]}
          />
        }
      />

      <Card>
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-5">
          <p className="text-xs text-slate-400">
            {isLoading ? 'جاري التحميل...' : `${requests.length} طلب`}
          </p>
          <SearchInput value={search} onChange={setSearch} placeholder="ابحث باسم الموظف..." className="w-full sm:w-64" />
        </div>

        {isLoading ? (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="skeleton h-64 rounded-2xl" />
            ))}
          </div>
        ) : query.error && !query.data ? (
          <EmptyState icon={AlertTriangle} tone="rose" title="تعذر تحميل الطلبات" description={errorMessage(query.error)} action={<Button size="sm" variant="secondary" onClick={query.reload}>إعادة المحاولة</Button>} />
        ) : requests.length === 0 ? (
          <EmptyState
            icon={Calendar}
            tone="amber"
            title={search ? 'لا توجد نتائج مطابقة' : 'لا توجد طلبات في هذا القسم'}
            description={activeTab === 'pending' && !search ? 'ستظهر هنا طلبات الإجازة الجديدة فور رفعها من تطبيق الموظفين.' : undefined}
          />
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {requests.map((req) => {
              const isPaid = paidOverride[req.id] ?? req.is_paid;
              const busy = actionLoading === req.id;
              return (
                <article key={req.id} className="flex flex-col rounded-2xl bg-slate-900/50 border border-slate-800/80 hover:border-slate-700/80 transition-colors p-5">
                  <div className="flex items-center gap-3 mb-4">
                    <Avatar name={req.employees?.full_name} />
                    <div className="flex-1 min-w-0">
                      <h4 className="text-sm font-bold text-white truncate">{req.employees?.full_name || 'موظف غير معروف'}</h4>
                      <p className="text-[11px] text-slate-500">{LEAVE_TYPES[req.leave_type] ?? 'إجازة أخرى'}</p>
                    </div>
                    {req.is_hourly ? <Badge tone="violet">ساعية</Badge> : <Badge tone="sky">{leaveDays(req)} يوم</Badge>}
                  </div>

                  <div className="grid grid-cols-2 gap-2 mb-3">
                    <div className="rounded-xl bg-slate-950/60 border border-slate-800/70 p-2.5">
                      <p className="text-[10px] text-slate-500 mb-0.5">من</p>
                      <p className="text-xs font-bold text-slate-200 font-mono" dir="ltr">{toDateKey(req.start_date)}</p>
                    </div>
                    <div className="rounded-xl bg-slate-950/60 border border-slate-800/70 p-2.5">
                      <p className="text-[10px] text-slate-500 mb-0.5">إلى</p>
                      <p className="text-xs font-bold text-slate-200 font-mono" dir="ltr">{toDateKey(req.end_date)}</p>
                    </div>
                  </div>

                  {req.is_hourly && (
                    <p className="flex items-center gap-1.5 text-xs text-violet-300 mb-3">
                      <Clock className="w-3.5 h-3.5" />
                      <span dir="ltr">{req.start_hour?.substring(0, 5)} – {req.end_hour?.substring(0, 5)}</span>
                    </p>
                  )}

                  {req.reason && (
                    <div className="rounded-xl bg-slate-950/40 border border-slate-800/60 p-3 mb-3">
                      <p className="flex items-center gap-1 text-[10px] text-slate-500 mb-1">
                        <FileText className="w-3 h-3" /> سبب الطلب
                      </p>
                      <p className="text-xs text-slate-300 leading-relaxed">{req.reason}</p>
                    </div>
                  )}

                  {req.attachment_url && (
                    <button
                      type="button"
                      onClick={() => openStorageUrl(req.attachment_url!).catch(() => toast.error('تعذر فتح الملف'))}
                      className="inline-flex items-center gap-1.5 text-xs font-bold text-indigo-300 hover:text-indigo-200 mb-3 cursor-pointer"
                    >
                      <Paperclip className="w-3.5 h-3.5" /> عرض المستند المرفق
                    </button>
                  )}

                  <div className="mt-auto pt-4 border-t border-slate-800/70">
                    {activeTab === 'pending' ? (
                      <>
                        <div className="flex items-center justify-between mb-3">
                          <span className="text-xs font-semibold text-slate-400">صرف الراتب لهذه الإجازة</span>
                          <Toggle
                            checked={isPaid}
                            onChange={(v) => setPaidOverride((prev) => ({ ...prev, [req.id]: v }))}
                            label={<span className={isPaid ? 'text-emerald-300' : 'text-rose-300'}>{isPaid ? 'مدفوعة' : 'مستقطعة'}</span>}
                          />
                        </div>
                        <div className="flex gap-2">
                          <Button variant="success" icon={Check} block loading={busy} onClick={() => handleProcess(req, true, isPaid)}>
                            موافقة
                          </Button>
                          <Button variant="soft-danger" icon={X} block disabled={busy} onClick={() => setRejecting(req)}>
                            رفض
                          </Button>
                        </div>
                      </>
                    ) : (
                      <div className="space-y-2">
                        <div className="flex flex-wrap gap-1.5">
                          <Badge tone={activeTab === 'approved' ? 'emerald' : 'rose'} dot>
                            {activeTab === 'approved' ? 'تمت الموافقة' : 'مرفوض'}
                          </Badge>
                          {activeTab === 'approved' && (
                            <Badge tone={req.is_paid ? 'emerald' : 'amber'}>{req.is_paid ? 'مدفوعة الراتب' : 'مستقطعة الراتب'}</Badge>
                          )}
                        </div>
                        <p className={cn('flex items-center gap-1.5 text-[11px] text-slate-500')}>
                          <ShieldCheck className="w-3.5 h-3.5" />
                          {req.approver?.full_name || 'مدير النظام'} · <span dir="ltr">{formatDateTime(req.approved_at)}</span>
                        </p>
                      </div>
                    )}
                  </div>
                </article>
              );
            })}
          </div>
        )}
      </Card>

      {rejecting && (
        <ReasonModal
          title="رفض طلب الإجازة؟"
          message={`سيتم إشعار ${rejecting.employees?.full_name || 'الموظف'} برفض الطلب مع السبب إن كتبته.`}
          confirmLabel="رفض الطلب"
          onCancel={() => setRejecting(null)}
          onConfirm={(reason) => void handleProcess(rejecting, false, false, reason)}
        />
      )}
    </div>
  );
}
