import { CheckCircle, Info, Loader2, Plus, X } from 'lucide-react';
import type { PayrollRow, sumPayroll } from '../calc';
import type { OverrideField, PayrollOverrides } from '../types';
import { EditableAmountCell } from './EditableAmountCell';

type Props = {
  rows: PayrollRow[];
  totals: ReturnType<typeof sumPayroll>;
  isMonthArchived: boolean;
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
  rows, totals, isMonthArchived, actionLoading, payrollOverrides,
  onSaveOverride, onClearOverride, onShowBreakdown, onAddAdjustment, onGenerateSlip, onRevertSlip,
}: Props) {
  const filteredPayroll = rows;
  const renderEditableCell = (emp: PayrollRow, field: OverrideField, displayValue: number, colorClass: string, prefixSign = '') => (
    <EditableAmountCell
      row={emp}
      field={field}
      displayValue={displayValue}
      colorClass={colorClass}
      prefixSign={prefixSign}
      isOverridden={payrollOverrides[emp.id]?.[field] !== undefined}
      onSave={(value) => onSaveOverride(emp.id, field, value)}
      onClear={() => onClearOverride(emp.id, field)}
    />
  );

  return (
    <div className="overflow-x-auto rounded-2xl border border-slate-800/60 print:border-none print:shadow-none">
      <table className="w-full text-right border-collapse">
        <thead>
          <tr className="bg-slate-950/80 text-slate-300 text-xs font-bold border-b border-slate-800/80">
            <th className="p-4">اسم الموظف</th>
            <th className="p-4">الفرع</th>
            <th className="p-4 text-slate-200">الراتب الأساسي</th>
            <th className="p-4 text-emerald-400">مكافآت (+)</th>
            <th className="p-4 text-amber-500">خصم غيابات الدوام (-)</th>
            <th className="p-4 text-rose-400">خصومات أخرى (-)</th>
            <th className="p-4 text-orange-400">السلف (-)</th>
            <th className="p-4 text-teal-300 text-lg">الراتب الصافي (Net)</th>
            <th className="p-4 text-left print:hidden">الإجراءات</th>
          </tr>
        </thead>
        <tbody>
          {filteredPayroll.length === 0 ? (
            <tr>
              <td colSpan={9} className="p-8 text-center text-slate-500 text-xs">
                لا توجد بيانات موظفين مطابقة للشروط
              </td>
            </tr>
          ) : (
            filteredPayroll.map(emp => (
              <tr key={emp.id} className="border-b border-slate-800/40 hover:bg-slate-900/30 text-xs transition-colors">
                <td className="p-4">
                  <div className="flex flex-col">
                    <span className="font-bold text-white text-xs">{emp.full_name}</span>
                    
                    {/* Smart Validation Badges */}
                    <div className="flex flex-wrap gap-1 mt-1 justify-start print:hidden">
                      {emp.isNetNegative && (
                        <span className="px-2 py-0.5 bg-rose-500/15 border border-rose-500/30 text-rose-400 rounded-lg text-[9px] font-bold flex items-center gap-1 select-none">
                          <span>الراتب الصافي سالب</span>
                          <span>⚠️</span>
                        </span>
                      )}
                      {emp.isAttendanceMissing && (
                        <span className="px-2 py-0.5 bg-amber-500/15 border border-amber-500/30 text-amber-400 rounded-lg text-[9px] font-bold flex items-center gap-1 select-none">
                          <span>لا توجد بصمات حضور</span>
                          <span>⚠️</span>
                        </span>
                      )}
                      {emp.hasPendingLeave && (
                        <span className="px-2 py-0.5 bg-sky-500/15 border border-sky-500/30 text-sky-400 rounded-lg text-[9px] font-bold flex items-center gap-1 select-none">
                          <span>طلب إجازة معلق</span>
                          <span>⏳</span>
                        </span>
                      )}
                      {emp.unconfirmedAbsencesCount > 0 && (
                        <span className="px-2 py-0.5 bg-orange-500/15 border border-orange-500/30 text-orange-400 rounded-lg text-[9px] font-bold flex items-center gap-1 select-none">
                          <span>غياب غير مثبت ({emp.unconfirmedAbsencesCount} أيام)</span>
                          <span>⚠️</span>
                        </span>
                      )}
                    </div>
                    {isMonthArchived ? (
                      <span className="text-[10px] text-slate-500 font-bold mt-1 text-right select-none block">
                        📦 تم أرشفة وحذف السجلات التفصيلية
                      </span>
                    ) : (
                      <button 
                        onClick={() => onShowBreakdown(emp.id)}
                        className="text-[10px] text-teal-400 hover:text-teal-300 font-bold mt-1 text-right flex items-center gap-1 cursor-pointer print:hidden"
                      >
                        <Info className="w-3.5 h-3.5" />
                        <span>عرض تفاصيل الحضور والخصومات</span>
                      </button>
                    )}
                  </div>
                </td>
                <td className="p-4 text-slate-400 font-bold">{emp.branches?.name || '-'}</td>
                <td className="p-4 font-bold text-slate-200">{emp.basic.toLocaleString()} د.ع</td>
                <td className="p-4 font-bold text-emerald-400">
                  {renderEditableCell(emp, 'bonuses', emp.totalBonuses, 'text-emerald-400', '+ ')}
                </td>
                <td className="p-4 font-bold text-amber-500">
                  {renderEditableCell(emp, 'attendanceDeductions', emp.totalAttendanceDeductions, 'text-amber-500', '- ')}
                  {!emp.isAttendanceDeductionsOverridden && emp.totalAttendanceDeductions > 0 && (
                    <span className="block text-[9px] opacity-75 text-right mt-1">
                      ({emp.absencesCount} غياب ، {emp.halfDaysCount} نصف يوم)
                    </span>
                  )}
                </td>
                <td className="p-4 font-bold text-rose-400">
                  {renderEditableCell(emp, 'otherDeductions', (emp.totalDeductions - emp.totalAttendanceDeductions), 'text-rose-400', '- ')}
                </td>
                <td className="p-4 font-bold text-orange-400">
                  {emp.loanDeduction > 0 ? `- ${emp.loanDeduction.toLocaleString()} د.ع` : '-'}
                </td>
                <td className="p-4 font-black text-teal-300 text-sm bg-teal-900/10">
                  {emp.netSalary.toLocaleString()} د.ع
                </td>
                <td className="p-4 text-left print:hidden">
                  <div className="flex items-center justify-end gap-2">
                    {!isMonthArchived && (
                      <button
                        onClick={() => onAddAdjustment(emp)}
                        className="p-2 bg-slate-800 border border-slate-700 text-slate-300 hover:text-white hover:bg-slate-700 rounded-xl transition-all cursor-pointer"
                        title="إضافة تسوية مالية (مكافأة أو خصم)"
                      >
                        <Plus className="w-4 h-4" />
                      </button>
                    )}
                    
                    {emp.isIssued ? (
                      <div className="flex items-center gap-2">
                        <span className="flex items-center gap-1.5 px-3 py-2 bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 rounded-xl font-bold text-[10px]">
                          <CheckCircle className="w-3.5 h-3.5" />
                          <span>تم الاعتماد</span>
                        </span>
                        {!isMonthArchived && (
                          <button
                            disabled={actionLoading === `revert_${emp.id}`}
                            onClick={() => {
                              if(window.confirm('هل أنت متأكد من رغبتك في إلغاء اعتماد هذا الراتب؟ سيتم مسح قيود الخصم الأوتوماتيكية وإرجاع السلف إلى حالة غير مدفوعة.')) {
                                onRevertSlip(emp);
                              }
                            }}
                            className="p-2 bg-rose-500/10 border border-rose-500/20 text-rose-400 hover:bg-rose-500 hover:text-white rounded-xl transition-all cursor-pointer"
                            title="إلغاء الاعتماد والتعديل"
                          >
                            {actionLoading === `revert_${emp.id}` ? (
                              <Loader2 className="w-4 h-4 animate-spin" />
                            ) : (
                              <X className="w-4 h-4" />
                            )}
                          </button>
                        )}
                      </div>
                    ) : (
                      !isMonthArchived && (
                        <button
                          disabled={actionLoading === `slip_${emp.id}`}
                          onClick={() => onGenerateSlip(emp)}
                          className="flex items-center gap-1.5 px-3 py-2 bg-teal-650/20 hover:bg-teal-600/40 border border-teal-500/30 text-teal-400 rounded-xl transition-all cursor-pointer font-bold text-[10px]"
                        >
                          {actionLoading === `slip_${emp.id}` ? (
                            <Loader2 className="w-3.5 h-3.5 animate-spin" />
                          ) : (
                            <>
                              <CheckCircle className="w-3.5 h-3.5" />
                              <span>اعتماد الراتب</span>
                            </>
                          )}
                        </button>
                      )
                    )}
                  </div>
                </td>
              </tr>
            ))
          )}
        </tbody>
        <tfoot>
          <tr className="bg-slate-950 font-bold border-t border-slate-800 text-xs print:bg-slate-100 print:text-black">
            <td className="p-4 text-right">إجمالي المجموع</td>
            <td className="p-4 text-slate-400 print:text-slate-600">-</td>
            <td className="p-4 text-slate-200 print:text-black">{totals.basic.toLocaleString()} د.ع</td>
            <td className="p-4 text-emerald-450 print:text-green-800">+ {totals.bonuses.toLocaleString()} د.ع</td>
            <td className="p-4 text-amber-500 print:text-amber-800">- {totals.attendanceDeductions.toLocaleString()} د.ع</td>
            <td className="p-4 text-rose-400 print:text-red-800">- {totals.otherDeductions.toLocaleString()} د.ع</td>
            <td className="p-4 text-orange-400 print:text-orange-900">- {totals.loans.toLocaleString()} د.ع</td>
            <td className="p-4 text-teal-300 text-sm bg-teal-900/20 print:bg-green-50 print:text-green-900">
              {totals.net.toLocaleString()} د.ع
            </td>
            <td className="p-4 print:hidden"></td>
          </tr>
        </tfoot>
      </table>
    </div>
  );
}
