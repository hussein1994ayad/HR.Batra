'use client';

import { Check, Info, Plus, Undo2 } from 'lucide-react';
import { useConfirm } from '@/components/confirm';
import { Avatar, Badge, Button, DataTable, IconButton, TableEmpty, cn } from '@/components/ui';
import { formatIQD } from '@/lib/format';
import { installmentOrigin } from '@/features/loans/logic';
import { attentionReasons, type PayrollRow, type sumPayroll } from '../calc';
import { arabicDate, payrollMonthName, payrollMonthOfDate } from '../period';
import type { OverrideField, PayrollOverrides } from '../types';
import { EditableAmountCell } from './EditableAmountCell';

type Props = {
  rows: PayrollRow[];
  totals: ReturnType<typeof sumPayroll>;
  isMonthArchived: boolean;
  /** المسير مغلق أو الشهر مؤرشف: لا تعديل ولا اعتماد. */
  locked: boolean;
  actionLoading: string | null;
  payrollOverrides: PayrollOverrides;
  onSaveOverride: (employeeId: string, field: OverrideField, value: number) => void;
  onClearOverride: (employeeId: string, field: OverrideField) => void;
  onShowBreakdown: (employeeId: string) => void;
  onAddAdjustment: (row: PayrollRow) => void;
  onGenerateSlip: (row: PayrollRow) => void;
  onRevertSlip: (row: PayrollRow) => void;
};

/** جدول رواتب الموظفين مع المجاميع والإجراءات لكل موظف. */
export function PayrollTable({
  rows, totals, isMonthArchived, locked, actionLoading, payrollOverrides,
  onSaveOverride, onClearOverride, onShowBreakdown, onAddAdjustment, onGenerateSlip, onRevertSlip,
}: Props) {
  const confirm = useConfirm();

  const cell = (row: PayrollRow, field: OverrideField, value: number, color: string, sign: string) => (
    <EditableAmountCell
      row={row}
      field={field}
      displayValue={value}
      colorClass={color}
      prefixSign={sign}
      disabled={locked || row.isIssued}
      isOverridden={payrollOverrides[row.id]?.[field] !== undefined}
      onSave={(v) => onSaveOverride(row.id, field, v)}
      onClear={() => onClearOverride(row.id, field)}
    />
  );

  const revert = async (row: PayrollRow) => {
    const ok = await confirm({
      title: 'إلغاء اعتماد الراتب؟',
      message: 'تعود أقساط السلف غير مدفوعة وتُلغى التعديلات اليدوية للكشف، ويمكن مراجعة الراتب واعتماده مجدداً.',
      confirmLabel: 'إلغاء الاعتماد',
      tone: 'warning',
    });
    if (ok) onRevertSlip(row);
  };

  return (
    <DataTable>
      <thead>
        <tr>
          <th>الموظف</th>
          <th>الأساسي</th>
          <th className="!text-emerald-300">مكافآت +</th>
          <th className="!text-amber-300">خصم الدوام −</th>
          <th className="!text-rose-300">خصومات أخرى −</th>
          <th className="!text-orange-300">السلف −</th>
          <th className="!text-white">الصافي</th>
          <th className="!text-left print:hidden">الإجراءات</th>
        </tr>
      </thead>
      <tbody>
        {rows.length === 0 ? (
          <TableEmpty colSpan={8}>لا توجد بيانات مطابقة</TableEmpty>
        ) : (
          rows.map((row) => (
            <tr key={row.id} className={cn(row.isIssued && 'bg-emerald-500/[0.03]')}>
              <td>
                <div className="flex items-start gap-2.5 min-w-[200px]">
                  <Avatar name={row.full_name} size="sm" />
                  <div className="min-w-0">
                    <p className="font-bold text-white truncate">{row.full_name}</p>
                    <p className="text-[10px] text-slate-500">
                      {row.branches?.name || 'بدون فرع'}
                      {row.terminationDate
                        ? ` · ترك العمل ${arabicDate(row.terminationDate)}`
                        : row.scheduledDays > 0 && !row.isIssued ? ` · داوم ${row.attendedDays} من ${row.scheduledDays} يوم` : ''}
                    </p>
                    {(() => {
                      // القرارات المعلّقة بشارتها، وباقي الأسباب بشارة «يحتاج انتباه» + أول سبب بكلام واضح
                      const others = attentionReasons(row).filter((r) => r.kind !== 'decisions');
                      if (row.pendingCount === 0 && others.length === 0) return null;
                      return (
                        <div className="mt-1 flex flex-wrap gap-1 print:hidden">
                          {row.pendingCount > 0 && !row.isIssued && <Badge tone="orange">{row.pendingCount} بانتظار قرارك</Badge>}
                          {others.length > 0 && <Badge tone="amber">يحتاج انتباه{others.length > 1 ? ` (${others.length})` : ''}</Badge>}
                          {others.slice(0, 1).map((r) => (
                            <p key={r.kind} className="basis-full text-[10px] text-amber-200/80 max-w-[260px]">{r.text}</p>
                          ))}
                        </div>
                      );
                    })()}
                    {isMonthArchived ? (
                      <p className="mt-1 text-[10px] text-slate-500">تم أرشفة السجلات التفصيلية</p>
                    ) : (
                      <button
                        type="button"
                        onClick={() => onShowBreakdown(row.id)}
                        className="mt-1 inline-flex items-center gap-1 text-[10px] font-bold text-indigo-300 hover:text-indigo-200 cursor-pointer print:hidden"
                      >
                        <Info className="w-3 h-3" /> التفاصيل والقرارات
                      </button>
                    )}
                  </div>
                </div>
              </td>
              <td className="font-bold text-slate-200 whitespace-nowrap">{row.basic.toLocaleString('en-US')}</td>
              <td>{cell(row, 'bonuses', row.totalBonuses, 'text-emerald-300', '+')}</td>
              <td>
                {cell(row, 'attendanceDeductions', row.totalAttendanceDeductions, 'text-amber-300', '−')}
                {!row.isAttendanceDeductionsOverridden && row.totalAttendanceDeductions > 0 && (
                  <span className="block text-[10px] text-slate-500 mt-0.5">{row.absencesCount} غياب · {row.totalLateMinutes} د تأخير</span>
                )}
              </td>
              <td>{cell(row, 'otherDeductions', row.totalDeductions - row.totalAttendanceDeductions, 'text-rose-300', '−')}</td>
              <td className="whitespace-nowrap">
                {row.loanDeduction > 0 ? (
                  <button type="button" onClick={() => onShowBreakdown(row.id)} className="text-right cursor-pointer print:cursor-auto">
                    <span className="block font-bold text-orange-300">−{row.loanDeduction.toLocaleString('en-US')}</span>
                    {row.loanItems.length > 0 && (
                      <span className="block text-[10px] text-slate-500">
                        {row.loanItems.length === 1
                          ? installmentOrigin({ ...row.loanItems[0], is_paid: false }) ?? `قسط ${payrollMonthName(payrollMonthOfDate(row.loanItems[0].due_date))}`
                          : `${row.loanItems.length} أقساط`}
                      </span>
                    )}
                  </button>
                ) : '—'}
              </td>
              <td className="whitespace-nowrap">
                <span className={cn('text-sm font-extrabold', row.netSalary < 0 ? 'text-rose-300' : 'text-white')}>{formatIQD(row.netSalary)}</span>
              </td>
              <td className="!text-left print:hidden">
                <div className="flex items-center justify-end gap-1.5">
                  {!locked && <IconButton icon={Plus} label="إضافة مكافأة أو خصم" tone="slate" onClick={() => onAddAdjustment(row)} />}
                  {row.isIssued ? (
                    <>
                      <Badge tone="emerald" dot>معتمد</Badge>
                      {!locked && (
                        <IconButton icon={Undo2} label="إلغاء الاعتماد" tone="amber" loading={actionLoading === `revert_${row.id}`} onClick={() => void revert(row)} />
                      )}
                    </>
                  ) : (
                    !locked && (
                      <Button
                        size="xs"
                        variant="soft-success"
                        icon={Check}
                        loading={actionLoading === `slip_${row.id}`}
                        disabled={actionLoading === 'bulk_generate'}
                        onClick={() => onGenerateSlip(row)}
                      >
                        اعتماد
                      </Button>
                    )
                  )}
                </div>
              </td>
            </tr>
          ))
        )}
      </tbody>
      <tfoot>
        <tr className="font-bold border-t border-slate-800 print:text-black">
          <td>الإجمالي</td>
          <td className="text-slate-200 whitespace-nowrap">{totals.basic.toLocaleString('en-US')}</td>
          <td className="text-emerald-300 whitespace-nowrap">+{totals.bonuses.toLocaleString('en-US')}</td>
          <td className="text-amber-300 whitespace-nowrap">−{totals.attendanceDeductions.toLocaleString('en-US')}</td>
          <td className="text-rose-300 whitespace-nowrap">−{totals.otherDeductions.toLocaleString('en-US')}</td>
          <td className="text-orange-300 whitespace-nowrap">−{totals.loans.toLocaleString('en-US')}</td>
          <td className="text-white whitespace-nowrap">{formatIQD(totals.net)}</td>
          <td className="print:hidden" />
        </tr>
      </tfoot>
    </DataTable>
  );
}
