'use client';

// صفحة السلف والأقساط: الطلبات المعلّقة، السلف المعتمدة، والنوافذ (اعتماد، جدول الأقساط، تعديل، دفعة، رفض).
// الحالة والإجراءات في features/loans/useLoans، والاستعلامات في features/loans/api.

import { AlertTriangle, CheckCircle2, Coins, CreditCard, Hourglass, Plus, Wallet } from 'lucide-react';
import { errorMessage, formatIQD } from '@/lib/format';
import { ReasonModal } from '@/components/ReasonModal';
import { Button, EmptyState, PageHeader, PageSkeleton, StatTile } from '@/components/ui';
import { useLoans } from '@/features/loans/useLoans';
import { nextCutoffDate } from '@/features/loans/logic';
import { LoanStatementPrint } from '@/features/loans/components/LoanStatementPrint';
import { CreateLoanModal } from '@/features/loans/components/CreateLoanModal';
import { PendingLoanRequests } from '@/features/loans/components/PendingLoanRequests';
import { ApprovedLoansTable } from '@/features/loans/components/ApprovedLoansTable';
import { ApprovalModal } from '@/features/loans/components/ApprovalModal';
import { InstallmentScheduleModal } from '@/features/loans/components/InstallmentScheduleModal';
import { EditLoanModal } from '@/features/loans/components/EditLoanModal';
import { PaymentModal } from '@/features/loans/components/PaymentModal';
import { MonthAmountModal } from '@/features/loans/components/MonthAmountModal';

export default function LoansPage() {
  const s = useLoans();
  const { query, pending, active, completed, outstanding, creating, setCreating, rejecting, setRejecting, rejectLoan, scheduleLoan } = s;

  if (!query.data) {
    if (query.error) {
      return (
        <EmptyState icon={AlertTriangle} tone="rose" title="تعذر تحميل السلف" description={errorMessage(query.error)} action={<Button size="sm" variant="secondary" onClick={query.reload}>إعادة المحاولة</Button>} />
      );
    }
    return <PageSkeleton />;
  }

  return (
    <div className="space-y-6 pb-12">
      <PageHeader
        icon={Coins}
        tone="sky"
        title="السلف والأقساط"
        description="اعتماد طلبات السلف وجدولة الأقساط الشهرية ومتابعة السداد"
        actions={<Button icon={Plus} onClick={() => setCreating(true)}>سلفة لموظف</Button>}
      />
      {creating && (
        <CreateLoanModal
          defaultFirstDue={nextCutoffDate()}
          onClose={() => setCreating(false)}
          onCreated={() => {
            setCreating(false);
            query.reload();
          }}
        />
      )}

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatTile label="طلبات معلقة" value={pending.length} icon={Hourglass} tone={pending.length > 0 ? 'amber' : 'slate'} />
        <StatTile label="سلف جارية" value={active.length} icon={CreditCard} tone="sky" />
        <StatTile label="المبالغ المتبقية" value={formatIQD(outstanding)} icon={Wallet} tone="indigo" />
        <StatTile label="سلف مكتملة" value={completed.length} icon={CheckCircle2} tone="emerald" />
      </div>

      <PendingLoanRequests s={s} />
      <ApprovedLoansTable s={s} />

      <ApprovalModal s={s} />
      <InstallmentScheduleModal s={s} />
      <EditLoanModal s={s} />
      <PaymentModal s={s} />
      <MonthAmountModal s={s} />
      {rejecting && (
        <ReasonModal
          title="رفض طلب السلفة؟"
          message={`سيتم إشعار ${rejecting.employees?.full_name || 'الموظف'} برفض الطلب.`}
          confirmLabel="رفض الطلب"
          onCancel={() => setRejecting(null)}
          onConfirm={(reason) => void rejectLoan(rejecting, reason)}
        />
      )}
      {scheduleLoan && <LoanStatementPrint selectedLoanForInstallments={scheduleLoan} />}
    </div>
  );
}
