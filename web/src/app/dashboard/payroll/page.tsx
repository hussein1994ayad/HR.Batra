'use client';

import { useMemo, useState } from 'react';
import { Card, PageSkeleton } from '@/components/ui';
import { useConfirmNote } from '@/components/confirm';
import { DEDUCT_REASONS, EXCUSE_REASONS } from '@/features/payroll/decisionReasons';
import { ARABIC_MONTHS } from '@/lib/dates';
import { usePayroll } from '@/features/payroll/usePayroll';
import toast from 'react-hot-toast';
import { attentionReasons, sumPayroll, type PayrollRow } from '@/features/payroll/calc';
import { AddAdjustmentModal } from '@/features/payroll/components/AddAdjustmentModal';
import { AttendanceBreakdownModal } from '@/features/payroll/components/AttendanceBreakdownModal';
import { BulkApproveModal } from '@/features/payroll/components/BulkApproveModal';
import { PayrollHeader } from '@/features/payroll/components/PayrollHeader';
import { PayrollPrintHeader } from '@/features/payroll/components/PayrollPrintHeader';
import { PayrollPrintSignatures } from '@/features/payroll/components/PayrollPrintSignatures';
import { PayrollSteps } from '@/features/payroll/components/PayrollSteps';
import { PayrollTable } from '@/features/payroll/components/PayrollTable';
import { PayrollToolbar, type PayrollStatusFilter } from '@/features/payroll/components/PayrollToolbar';

export default function PayrollPage() {
  const p = usePayroll();
  const confirmNote = useConfirmNote();
  const [statusFilter, setStatusFilter] = useState<PayrollStatusFilter>('all');

  const [adjustmentFor, setAdjustmentFor] = useState<{ row: PayrollRow; type: 'bonus' | 'deduction' } | null>(null);
  const [breakdownEmployeeId, setBreakdownEmployeeId] = useState<string | null>(null);
  const [showBulkModal, setShowBulkModal] = useState(false);

  const visibleRows = useMemo(
    () => p.filteredRows.filter((r) => {
      switch (statusFilter) {
        case 'decisions': return r.pendingCount > 0;
        case 'attention': return attentionReasons(r).some((a) => a.kind !== 'decisions');
        case 'issued': return r.isIssued;
        case 'pending': return !r.isIssued;
        default: return true;
      }
    }),
    [p.filteredRows, statusFilter],
  );
  const attentionCount = useMemo(
    () => p.filteredRows.filter((r) => attentionReasons(r).some((a) => a.kind !== 'decisions')).length,
    [p.filteredRows],
  );

  // ترك العمل وعليه سلفة: الأدمن يحدد المبلغ (المقترح = الأقل بين الباقي وصافي راتبه)
  const settleExit = async (row: PayrollRow) => {
    const suggested = Math.max(0, Math.min(row.loanBalanceAfterExit, Math.round(row.netSalary)));
    const answer = await confirmNote({
      title: 'اخصم باقي السلفة من آخر راتب؟',
      message: `باقي عليه ${row.loanBalanceAfterExit.toLocaleString('en-US')} د.ع بعد قسط هالشهر، وصافي راتبه الأخير ${Math.round(row.netSalary).toLocaleString('en-US')} د.ع. اكتب المبلغ اللي ينخصم؛ الباقي يبقى يسدده نقداً.`,
      confirmLabel: 'خصم من آخر راتب',
      tone: 'warning',
      note: { initial: String(suggested), placeholder: 'المبلغ بالدينار' },
    });
    if (answer === null) return;
    const amount = Number(answer.replace(/[^\d]/g, ''));
    if (!(amount > 0)) {
      toast.error('اكتب مبلغ صحيح');
      return;
    }
    await p.settleExit(row.id, amount);
  };
  const visibleTotals = useMemo(() => sumPayroll(visibleRows), [visibleRows]);

  if (p.loading) return <PageSkeleton rows={8} />;

  const [currentYearVal, currentMonthVal] = p.selectedMonth.split('-');
  const branchName = p.branches.find(b => b.id === p.selectedBranch)?.name ?? '';
  const branchLabel = p.selectedBranch === 'all' ? 'كافة فروع الشركة' : branchName || '-';
  const breakdownRow = p.rows.find(r => r.id === breakdownEmployeeId);

  return (
    <div className="space-y-6 pb-12">
      <PayrollPrintHeader
        currentMonthName={ARABIC_MONTHS[currentMonthVal] || currentMonthVal}
        currentYearVal={currentYearVal}
        startDate={p.startDate}
        endDate={p.endDate}
        branchLabel={branchLabel}
      />

      <PayrollHeader
        isMonthArchived={p.isMonthArchived}
        currentMonthVal={currentMonthVal}
        currentYearVal={currentYearVal}
        startDate={p.startDate}
        endDate={p.endDate}
        paymentDate={p.period?.payment_date}
        periodStatus={p.period?.status ?? null}
        legacy={!!p.period?.legacy}
        reopening={p.actionLoading === 'reopen_period'}
        onReopenPeriod={p.reopenPeriod}
        totals={p.totals}
        issuedCount={p.filteredRows.filter(r => r.isIssued).length}
        rowCount={p.filteredRows.length}
        branchLabel={branchLabel}
        onMonthChange={p.changeMonth}
      />

      {!p.isMonthArchived && !p.period?.legacy && (
        <PayrollSteps
          pendingDecisions={p.pendingDecisions}
          attentionCount={attentionCount}
          issuedCount={p.filteredRows.filter(r => r.isIssued).length}
          rowCount={p.filteredRows.length}
          periodStatus={p.period?.status ?? null}
          locked={p.isLocked}
          closing={p.actionLoading === 'close_period'}
          onFilter={setStatusFilter}
          approvableCount={p.approvableRows.length}
          calculatedAt={p.period?.calculated_at}
          calculating={p.actionLoading === 'calculate'}
          onCalculate={() => void p.calculate()}
          approveFrom={p.endDate}
          onOpenBulk={() => setShowBulkModal(true)}
          onClosePeriod={p.closePeriod}
        />
      )}

      <Card className="print:border-none print:bg-transparent print:p-0">
        <PayrollToolbar
          searchTerm={p.searchTerm}
          onSearchChange={p.setSearchTerm}
          selectedBranch={p.selectedBranch}
          onBranchChange={p.setSelectedBranch}
          branches={p.branches}
          statusFilter={statusFilter}
          onStatusFilterChange={setStatusFilter}
          pendingCount={p.approvableRows.length}
          isMonthArchived={p.isMonthArchived}
          locked={p.isLocked}
          canArchive={p.isPeriodClosed || !!p.period?.legacy}
          sendingNotifs={p.sendingNotifs}
          archiving={p.actionLoading === 'archive_month'}
          onOpenBulk={() => setShowBulkModal(true)}
          onSendBranchNotifications={p.sendBranchNotifications}
          onArchiveMonth={p.archiveMonth}
        />

        <PayrollTable
          rows={visibleRows}
          totals={visibleTotals}
          isMonthArchived={p.isMonthArchived}
          locked={p.isLocked}
          actionLoading={p.actionLoading}
          payrollOverrides={p.payrollOverrides}
          onSaveOverride={p.saveOverride}
          onClearOverride={p.clearOverride}
          onShowBreakdown={setBreakdownEmployeeId}
          onAddAdjustment={(row) => setAdjustmentFor({ row, type: 'bonus' })}
          onGenerateSlip={p.generateSlip}
          canApprove={p.canApprove}
          approveFrom={p.endDate}
          onRevertSlip={p.revertSlip}
        />

        <PayrollPrintSignatures />
      </Card>

      {adjustmentFor && (
        <AddAdjustmentModal
          key={`${adjustmentFor.row.id}-${adjustmentFor.type}`}
          employee={adjustmentFor.row}
          initialType={adjustmentFor.type}
          saving={p.actionLoading === 'add_bd'}
          onClose={() => setAdjustmentFor(null)}
          onSubmit={p.addBonusDeduction}
        />
      )}

      {breakdownRow && (
        <AttendanceBreakdownModal
          row={breakdownRow}
          startDate={p.startDate}
          endDate={p.endDate}
          locked={p.isLocked}
          actionLoading={p.actionLoading}
          onClose={() => setBreakdownEmployeeId(null)}
          onAddAdjustment={(type) => setAdjustmentFor({ row: breakdownRow, type })}
          onSettleExit={() => void settleExit(breakdownRow)}
          onDecide={async (id, approve) => {
            // قرار مالي: تأكيد قبل التنفيذ، مع ملاحظة تنحفظ بالقرار (مثل: نسي البصمة وهو مداوم)
            const note = await confirmNote({
              title: approve ? 'اعتماد هذه الحركة؟' : 'إعفاء من هذه الحركة؟',
              message: approve
                ? 'تنحسب على راتب هذا المسير، ويوصل للموظف إشعار بالخصم.'
                : 'ما تنحسب على الراتب، وما يوصل للموظف إشعار. الملاحظة تنحفظ مع القرار.',
              confirmLabel: approve ? 'اعتماد' : 'إعفاء',
              tone: approve ? 'warning' : 'primary',
              note: { presets: approve ? DEDUCT_REASONS : EXCUSE_REASONS, placeholder: 'ملاحظة (اختياري)' },
            });
            if (note !== null) await p.decideEvent(id, approve, note || undefined);
          }}
        />
      )}

      {showBulkModal && (
        <BulkApproveModal
          branchName={branchName}
          selectedMonth={p.selectedMonth}
          startDate={p.startDate}
          endDate={p.endDate}
          pendingRows={p.approvableRows}
          approving={p.actionLoading === 'bulk_generate'}
          onClose={() => setShowBulkModal(false)}
          onConfirm={async () => {
            await p.bulkGenerateSlips(p.approvableRows);
            setShowBulkModal(false);
          }}
        />
      )}
    </div>
  );
}
