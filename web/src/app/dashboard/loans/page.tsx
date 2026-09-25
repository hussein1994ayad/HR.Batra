'use client';

import { useState } from 'react';
import { Loader2 } from 'lucide-react';
import type { Loan } from '@/lib/db-types';
import { useLoans } from '@/features/loans/useLoans';
import type { InstallmentPrompt, LoansTab } from '@/features/loans/types';
import { ApprovalModal } from '@/features/loans/components/ApprovalModal';
import { CashPaymentModal } from '@/features/loans/components/CashPaymentModal';
import { EditInstallmentModal } from '@/features/loans/components/EditInstallmentModal';
import { EditLoanModal } from '@/features/loans/components/EditLoanModal';
import { InstallmentsModal } from '@/features/loans/components/InstallmentsModal';
import { LoanRequestsSection } from '@/features/loans/components/LoanRequestsSection';
import { LoansListSection } from '@/features/loans/components/LoansListSection';
import { LoanStatementPrint } from '@/features/loans/components/LoanStatementPrint';

export default function LoansPage() {
  const l = useLoans();
  const [loansTab, setLoansTab] = useState<LoansTab>('active');
  const [approvingLoan, setApprovingLoan] = useState<Loan | null>(null);
  const [editingLoan, setEditingLoan] = useState<Loan | null>(null);
  // يُحفظ المعرّف فقط حتى يعرض جدول الأقساط آخر نسخة بعد كل إعادة تحميل
  const [scheduleLoanId, setScheduleLoanId] = useState<string | null>(null);
  const [cashPrompt, setCashPrompt] = useState<InstallmentPrompt | null>(null);
  const [amountPrompt, setAmountPrompt] = useState<InstallmentPrompt | null>(null);

  const scheduleLoan = l.activeLoans.find(loan => loan.id === scheduleLoanId) ?? null;
  const busy = l.actionLoading !== null;

  if (l.loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  return (
    <>
      <div className="space-y-8 pb-12 print:hidden">
        <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl space-y-6">
          <LoanRequestsSection
            loanRequests={l.loanRequests}
            actionLoading={l.actionLoading}
            onApprove={(loan) => {
              if (l.canApprove(loan)) setApprovingLoan(loan);
            }}
            onReject={(loan) => void l.reject(loan)}
          />
          <LoansListSection
            loansTab={loansTab}
            incompleteLoans={l.incompleteLoans}
            completedLoans={l.completedLoans}
            actionLoading={l.actionLoading}
            onTabChange={setLoansTab}
            onOpenSchedule={(loan) => setScheduleLoanId(loan.id)}
            onDelete={(loan) => void l.deleteLoan(loan)}
          />
        </div>

        {approvingLoan && (
          <ApprovalModal
            loan={approvingLoan}
            saving={busy}
            onClose={() => setApprovingLoan(null)}
            onSubmit={async (draft) => {
              if (await l.approve(draft)) setApprovingLoan(null);
            }}
          />
        )}

        {editingLoan && (
          <EditLoanModal
            loan={editingLoan}
            saving={busy}
            onClose={() => setEditingLoan(null)}
            onSubmit={async (draft) => {
              if (await l.reschedule(draft)) setEditingLoan(null);
            }}
          />
        )}

        {scheduleLoan && (
          <InstallmentsModal
            selectedLoanForInstallments={scheduleLoan}
            actionLoading={l.actionLoading}
            onClose={() => setScheduleLoanId(null)}
            onEditLoan={setEditingLoan}
            onCashPayment={(inst) => setCashPrompt({ installmentId: inst.id, amount: inst.amount })}
            onPostpone={(inst) => void l.postpone(inst)}
            onEditInstallment={(inst) => setAmountPrompt({ installmentId: inst.id, amount: inst.amount })}
            onRevert={(id) => void l.revertPayment(id)}
            onDeletePaid={(id) => void l.deletePaidInstallment(id)}
          />
        )}

        {cashPrompt && (
          <CashPaymentModal
            cashPaymentPrompt={cashPrompt}
            saving={busy}
            onClose={() => setCashPrompt(null)}
            onSubmit={async (note) => {
              if (await l.payCash(cashPrompt.installmentId, note)) setCashPrompt(null);
            }}
          />
        )}

        {amountPrompt && (
          <EditInstallmentModal
            editInstallmentPrompt={amountPrompt}
            saving={busy}
            onClose={() => setAmountPrompt(null)}
            onSubmit={async (amount) => {
              if (await l.changeInstallmentAmount(amountPrompt.installmentId, amount)) setAmountPrompt(null);
            }}
          />
        )}
      </div>

      {scheduleLoan && <LoanStatementPrint selectedLoanForInstallments={scheduleLoan} />}
    </>
  );
}
