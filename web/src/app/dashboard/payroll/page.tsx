'use client';

import { useState } from 'react';
import { Loader2 } from 'lucide-react';
import { ARABIC_MONTHS } from '@/lib/dates';
import { usePayroll } from '@/features/payroll/usePayroll';
import type { PayrollRow } from '@/features/payroll/calc';
import { AddAdjustmentModal } from '@/features/payroll/components/AddAdjustmentModal';
import { AttendanceBreakdownModal } from '@/features/payroll/components/AttendanceBreakdownModal';
import { BulkApproveModal } from '@/features/payroll/components/BulkApproveModal';
import { PayrollHeader } from '@/features/payroll/components/PayrollHeader';
import { PayrollPrintHeader } from '@/features/payroll/components/PayrollPrintHeader';
import { PayrollPrintSignatures } from '@/features/payroll/components/PayrollPrintSignatures';
import { PayrollTable } from '@/features/payroll/components/PayrollTable';
import { PayrollToolbar } from '@/features/payroll/components/PayrollToolbar';

export default function PayrollPage() {
  const p = usePayroll();

  // النوافذ المنبثقة
  const [adjustmentFor, setAdjustmentFor] = useState<{ row: PayrollRow; type: 'bonus' | 'deduction' } | null>(null);
  const [breakdownEmployeeId, setBreakdownEmployeeId] = useState<string | null>(null);
  const [showBulkModal, setShowBulkModal] = useState(false);

  const [currentYearVal, currentMonthVal] = p.selectedMonth.split('-');
  const branchName = p.branches.find(b => b.id === p.selectedBranch)?.name ?? '';
  const breakdownRow = p.rows.find(r => r.id === breakdownEmployeeId);

  if (p.loading) {
    return (
      <div className="flex-grow flex items-center justify-center">
        <Loader2 className="w-10 h-10 text-teal-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="space-y-8 pb-12">
      <PayrollPrintHeader
        currentMonthName={ARABIC_MONTHS[currentMonthVal] || currentMonthVal}
        currentYearVal={currentYearVal}
        startDate={p.startDate}
        endDate={p.endDate}
        branchLabel={p.selectedBranch === 'all' ? 'كافة فروع الشركة' : branchName || '-'}
      />

      <PayrollHeader
        isMonthArchived={p.isMonthArchived}
        currentMonthVal={currentMonthVal}
        currentYearVal={currentYearVal}
        startDate={p.startDate}
        endDate={p.endDate}
        totalNetSalaries={p.totals.net}
        onMonthChange={p.changeMonth}
      />

      {/* Main Table Area */}
      <div className="bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl print:border-none print:bg-transparent print:p-0 print:shadow-none">
        <PayrollToolbar
          searchTerm={p.searchTerm}
          onSearchChange={p.setSearchTerm}
          selectedBranch={p.selectedBranch}
          onBranchChange={p.setSelectedBranch}
          branches={p.branches}
          selectedMonth={p.selectedMonth}
          isMonthArchived={p.isMonthArchived}
          sendingNotifs={p.sendingNotifs}
          archiving={p.actionLoading === 'archive_month'}
          onOpenBulk={() => setShowBulkModal(true)}
          onSendBranchNotifications={p.sendBranchNotifications}
          onArchiveMonth={p.archiveMonth}
        />

        <PayrollTable
          rows={p.filteredRows}
          totals={p.totals}
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
      </div>

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
