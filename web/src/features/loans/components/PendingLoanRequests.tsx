'use client';

// طلبات السلف المعلّقة: اعتماد وجدولة، رفض بسبب، وعرض التعهد. تنبيه إذا عنده سلفة جارية (approve_loan يرفضها).

import toast from 'react-hot-toast';
import { Coins, X, Settings2, FileText, Hourglass } from 'lucide-react';
import { openStorageUrl } from '@/lib/signed-urls';
import { formatIQD } from '@/lib/format';
import { Avatar, Badge, Button, Card, CardHeader, EmptyState } from '@/components/ui';
import type { LoansState } from '../useLoans';

export function PendingLoanRequests({ s }: { s: LoansState }) {
  const { pending, active, busy, setRejecting, startApproval } = s;
  return (
    <>
    <Card>
      <CardHeader
        icon={Hourglass}
        tone="amber"
        title={<>طلبات بانتظار الاعتماد {pending.length > 0 && <Badge tone="amber">{pending.length}</Badge>}</>}
        description="راجع الطلب ثم اعتمده مع إمكانية تعديل المبلغ ومدة التقسيط"
      />
      {pending.length === 0 ? (
        <EmptyState icon={Coins} title="لا توجد طلبات سلف معلقة" description="ستظهر هنا الطلبات الجديدة فور رفعها من تطبيق الموظفين." />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {pending.map((loan) => {
            const amount = Number(loan.amount);
            const months = Number(loan.installment_count) || 1;
            return (
              <article key={loan.id} className="flex flex-col rounded-2xl bg-slate-900/50 border border-slate-800/80 hover:border-slate-700/80 transition-colors p-5">
                <div className="flex items-center gap-3 mb-4">
                  <Avatar name={loan.employees?.full_name} />
                  <div className="flex-1 min-w-0">
                    <h4 className="text-sm font-bold text-white truncate">{loan.employees?.full_name || 'موظف'}</h4>
                    <p className="text-[11px] text-slate-500">طلب سلفة مالية</p>
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-2 mb-3">
                  <div className="rounded-xl bg-slate-950/60 border border-slate-800/70 p-2.5">
                    <p className="text-[10px] text-slate-500 mb-0.5">المبلغ</p>
                    <p className="text-sm font-extrabold text-white">{formatIQD(amount)}</p>
                  </div>
                  <div className="rounded-xl bg-slate-950/60 border border-slate-800/70 p-2.5">
                    <p className="text-[10px] text-slate-500 mb-0.5">المدة</p>
                    <p className="text-sm font-extrabold text-white">{months} شهر</p>
                  </div>
                </div>
                <div className="flex items-center justify-between rounded-xl bg-sky-500/5 border border-sky-500/15 px-3 py-2.5 mb-3">
                  <span className="text-xs text-slate-400">القسط الشهري</span>
                  <span className="text-sm font-extrabold text-sky-300">{formatIQD(amount / months)}</span>
                </div>
                {/* الاعتماد يُرفض إذا عنده سلفة لم تُسدَّد (approve_loan) — ننبه قبل ما يحاول */}
                {active.some((l) => l.employee_id === loan.employee_id) && (
                  <p className="rounded-xl bg-amber-500/10 border border-amber-500/20 px-3 py-2 mb-3 text-[11px] font-bold text-amber-300">
                    عنده سلفة جارية لم تُسدَّد بعد، فما ينعتمد هذا الطلب إلا بعد إكمال سدادها.
                  </p>
                )}
                {loan.pledge_url && (
                  <button type="button" onClick={() => openStorageUrl(loan.pledge_url!).catch(() => toast.error('تعذر فتح التعهد'))} className="inline-flex items-center gap-1.5 text-xs font-bold text-indigo-300 hover:text-indigo-200 mb-3 cursor-pointer">
                  <FileText className="w-3.5 h-3.5" /> عرض التعهد الموقّع
                </button>
                )}
                <div className="flex gap-2 mt-auto pt-4 border-t border-slate-800/70">
                  <Button variant="primary" icon={Settings2} block disabled={busy === loan.id} onClick={() => startApproval(loan)}>
                    اعتماد وجدولة
                  </Button>
                  <Button variant="soft-danger" icon={X} block loading={busy === loan.id} onClick={() => setRejecting(loan)}>
                    رفض
                  </Button>
                </div>
              </article>
            );
          })}
        </div>
      )}
    </Card>
    </>
  );
}
