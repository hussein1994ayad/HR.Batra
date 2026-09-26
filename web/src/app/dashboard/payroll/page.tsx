'use client';

import { useMemo, useState } from 'react';
import { Card, PageSkeleton } from '@/components/ui';
import { ARABIC_MONTHS } from '@/lib/dates';
import { usePayroll } from '@/features/payroll/usePayroll';
import { sumPayroll, type PayrollRow } from '@/features/payroll/calc';
import { AddAdjustmentModal } from '@/features/payroll/components/AddAdjustmentModal';
import { AttendanceBreakdownModal } from '@/features/payroll/components/AttendanceBreakdownModal';
import { BulkApproveModal } from '@/features/payroll/components/BulkApproveModal';
import { PayrollHeader } from '@/features/payroll/components/PayrollHeader';
import { PayrollPrintHeader } from '@/features/payroll/components/PayrollPrintHeader';
import { PayrollPrintSignatures } from '@/features/payroll/components/PayrollPrintSignatures';
import { PayrollTable } from '@/features/payroll/components/PayrollTable';
import { PayrollToolbar, type PayrollStatusFilter } from '@/features/payroll/components/PayrollToolbar';

export default function PayrollPage() {
  const p = usePayroll();
  const [statusFilter, setStatusFilter] = useState<PayrollStatusFilter>('all');

  const [adjustmentFor, setAdjustmentFor] = useState<{ row: PayrollRow; type: 'bonus' | 'deduction' } | null>(null);
  const [breakdownEmployeeId, setBreakdownEmployeeId] = useState<string | null>(null);
  const [showBulkModal, setShowBulkModal] = useState(false);

  const visibleRows = useMemo(
    () => p.filteredRows.filter(r => statusFilter === 'all' || (statusFilter === 'issued' ? r.isIssued : !r.isIssued)),
    [p.filteredRows, statusFilter],
  );
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
        totals={p.totals}
        issuedCount={p.filteredRows.filter(r => r.isIssued).length}
        rowCount={p.filteredRows.length}
        branchLabel={branchLabel}
        onMonthChange={p.changeMonth}
      />

      <Card className="print:border-none print:bg-transparent print:p-0">
        <PayrollToolbar
          searchTerm={p.searchTerm}
          onSearchChange={p.setSearchTerm}
          selectedBranch={p.selectedBranch}
          onBranchChange={p.setSelectedBranch}
          branches={p.branches}
          statusFilter={statusFilter}
          onStatusFilterChange={setStatusFilter}
          pendingCount={p.pendingRows.length}
          isMonthArchived={p.isMonthArchived}
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
          actionLoading={p.actionLoading}
          payrollOverrides={p.payrollOverrides}
          onSaveOverride={p.saveOverride}
          onClearOverride={p.clearOverride}
          onShowBreakdown={setBreakdownEmployeeId}
          onAddAdjustment={(row) => setAdjustmentFor({ row, type: 'bonus' })}
          onGenerateSlip={p.generateSlip}
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
          onClose={() => setBreakdownEmployeeId(null)}
          onAddAdjustment={(type) => setAdjustmentFor({ row: breakdownRow, type })}
          onToggleExcuse={(date) => p.toggleExcuseDay(breakdownRow.id, date)}
        />
      )}

      {showBulkModal && (
        <BulkApproveModal
          branchName={branchName}
          selectedMonth={p.selectedMonth}
          startDate={p.startDate}
          endDate={p.endDate}
          pendingRows={p.pendingRows}
          approving={p.actionLoading === 'bulk_generate'}
          onClose={() => setShowBulkModal(false)}
          onConfirm={async () => {
            await p.bulkGenerateSlips(p.pendingRows);
            setShowBulkModal(false);
          }}
        />
      )}
    </div>
  );
}
