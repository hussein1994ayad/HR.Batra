'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';
import { errorMessage } from '@/lib/error-utils';
import { getCycleDates } from '@/lib/dates';
import {
  approveSalarySlip, archivePayrollMonth, fetchPayrollDataset, fetchPayrollPolicy, insertBonusDeduction,
  notifyBranchPayslips, revertSalarySlip, type PayrollDataset,
} from './api';
import { buildPayrollRows, buildSlipAdjustments, sumPayroll, type PayrollRow } from './calc';
import type { ExcusedDays, OverrideField, PayrollOverrides } from './types';

const EMPTY_DATASET: PayrollDataset = {
  branches: [], employees: [], bonusesAndDeductions: [], loanInstallments: [], attendanceLogs: [],
  leaveRequests: [], workSchedules: [], existingSlips: [], archivedMonths: [],
};

const currentMonth = () => {
  const d = new Date();
  return `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}`;
};

/** حالة صفحة الرواتب: البيانات، الفلاتر، التعديلات اليدوية، والإجراءات. */
export function usePayroll() {
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [sendingNotifs, setSendingNotifs] = useState(false);
  const [data, setData] = useState<PayrollDataset>(EMPTY_DATASET);

  const [selectedMonth, setSelectedMonth] = useState(currentMonth);
  const [cycleStartDay, setCycleStartDay] = useState(25);
  const [cycleEndDay, setCycleEndDay] = useState(24);
  const [period, setPeriod] = useState(() => getCycleDates(currentMonth()));
  const { start: startDate, end: endDate } = period;

  const [searchTerm, setSearchTerm] = useState('');
  const [selectedBranch, setSelectedBranch] = useState('all');
  const [payrollOverrides, setPayrollOverrides] = useState<PayrollOverrides>({});
  const [excusedDays, setExcusedDays] = useState<ExcusedDays>({});

  const loadData = useCallback(async () => {
    if (!startDate || !endDate) return;
    setLoading(true);
    try {
      const policy = await fetchPayrollPolicy();
      if (policy) {
        setCycleStartDay(policy.startDay);
        setCycleEndDay(policy.endDay);
        const expected = getCycleDates(selectedMonth, policy.startDay, policy.endDay);
        if (expected.start !== startDate || expected.end !== endDate) {
          setPeriod(expected); // يعيد التحميل بالفترة الصحيحة
          return;
        }
      }
      setData(await fetchPayrollDataset(startDate, endDate, selectedMonth));
    } catch (err: unknown) {
      console.error(err);
      toast.error(`تعذر تحميل بيانات الرواتب: ${errorMessage(err)}`);
    } finally {
      setLoading(false);
    }
  }, [startDate, endDate, selectedMonth]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- جلب البيانات عند تغيّر الفترة
    void loadData();
  }, [loadData]);

  const changeMonth = (month: string) => {
    setSelectedMonth(month);
    setPeriod(getCycleDates(month, cycleStartDay, cycleEndDay));
  };

  // ------------------------------------------------------------------
  // الحساب
  // ------------------------------------------------------------------
  const rows = useMemo(() => buildPayrollRows({
    ...data, payrollOverrides, excusedDays, selectedMonth, startDate, endDate,
  }), [data, payrollOverrides, excusedDays, selectedMonth, startDate, endDate]);

  const filteredRows = useMemo(() => rows.filter(row => {
    const matchesSearch = (row.full_name || '').toLowerCase().includes(searchTerm.toLowerCase());
    const matchesBranch = selectedBranch === 'all' || row.branch_id === selectedBranch;
    return matchesSearch && matchesBranch;
  }), [rows, searchTerm, selectedBranch]);

  const totals = useMemo(() => sumPayroll(filteredRows), [filteredRows]);
  const pendingRows = useMemo(() => filteredRows.filter(r => !r.isIssued), [filteredRows]);
  const isMonthArchived = data.archivedMonths.includes(selectedMonth);
  const isSlipIssued = (employeeId: string) =>
    data.existingSlips.some(s => s.employee_id === employeeId && s.work_month === selectedMonth);

  // ------------------------------------------------------------------
  // التعديلات اليدوية والإعفاءات
  // ------------------------------------------------------------------
  const saveOverride = (employeeId: string, field: OverrideField, value: number) => {
    setPayrollOverrides(prev => ({ ...prev, [employeeId]: { ...prev[employeeId], [field]: value } }));
    toast.success('تم تعديل القيمة وتحديث صافي الراتب! 💸');
  };

  const clearOverride = (employeeId: string, field: OverrideField) => {
    setPayrollOverrides(prev => {
      const empOverrides = { ...prev[employeeId] };
      delete empOverrides[field];
      const updated = { ...prev };
      if (Object.keys(empOverrides).length === 0) delete updated[employeeId];
      else updated[employeeId] = empOverrides;
      return updated;
    });
    toast.success('تمت استعادة القيمة التلقائية المحتسبة! 🔄');
  };

  const toggleExcuseDay = (employeeId: string, dateStr: string) => {
    setExcusedDays(prev => {
      const current = prev[employeeId] || [];
      const updated = current.includes(dateStr) ? current.filter(d => d !== dateStr) : [...current, dateStr];
      return { ...prev, [employeeId]: updated };
    });
  };

  // ------------------------------------------------------------------
  // الإجراءات
  // ------------------------------------------------------------------
  const addBonusDeduction = async (entry: { employeeId: string; type: 'bonus' | 'deduction'; amount: number; reason: string }) => {
    setActionLoading('add_bd');
    try {
      await insertBonusDeduction(entry);
      confetti({ particleCount: 50, spread: 40 });
      toast.success('تم إضافة السجل بنجاح! ✅');
      await loadData();
      return true;
    } catch {
      toast.error('حدث خطأ أثناء الإضافة');
      return false;
    } finally {
      setActionLoading(null);
    }
  };

  const approveRow = (row: PayrollRow) =>
    approveSalarySlip(row, selectedMonth, buildSlipAdjustments(row, { selectedMonth, startDate, endDate }));

  const generateSlip = async (row: PayrollRow) => {
    if (isSlipIssued(row.id)) {
      toast.error('تم صرف الراتب مسبقاً لهذا الموظف في هذا الشهر.');
      return;
    }
    setActionLoading(`slip_${row.id}`);
    try {
      await approveRow(row);
      confetti({ particleCount: 100, spread: 60, colors: ['#10B981', '#059669'] });
      toast.success('تم اعتماد راتب الموظف بنجاح! 💸');
      await loadData();
    } catch (err: unknown) {
      toast.error(`فشل اعتماد الراتب: ${errorMessage(err)}`);
    } finally {
      setActionLoading(null);
    }
  };

  const bulkGenerateSlips = async (rowsToProcess: PayrollRow[]) => {
    setActionLoading('bulk_generate');
    let successCount = 0;
    const failed: string[] = [];
    try {
      for (const row of rowsToProcess) {
        if (isSlipIssued(row.id)) continue;
        try {
          await approveRow(row);
          successCount++;
        } catch (err: unknown) {
          console.error(`Error generating slip for ${row.full_name}:`, err);
          failed.push(row.full_name);
        }
      }
      if (successCount > 0) {
        confetti({ particleCount: 150, spread: 80, colors: ['#10B981', '#3B82F6'] });
        toast.success(`تم اعتماد رواتب (${successCount}) موظف بنجاح! 💸`);
      }
      if (failed.length > 0) toast.error(`تعذر اعتماد رواتب (${failed.length}) موظف: ${failed.join('، ')}`);
      await loadData();
      return true;
    } finally {
      setActionLoading(null);
    }
  };

  const revertSlip = async (row: PayrollRow) => {
    if (isMonthArchived) {
      toast.error('هذا الشهر مؤرشف مالياً ومقفل تماماً 🔒');
      return;
    }
    const slip = data.existingSlips.find(s => s.employee_id === row.id);
    if (!slip) return;

    setActionLoading(`revert_${row.id}`);
    try {
      await revertSalarySlip(slip.id, startDate, endDate);
      toast.success('تم التراجع عن اعتماد الراتب بنجاح! 🔄');
      await loadData();
    } catch (err: unknown) {
      toast.error(`فشل في التراجع عن الاعتماد: ${errorMessage(err)}`);
    } finally {
      setActionLoading(null);
    }
  };

  const sendBranchNotifications = async () => {
    if (selectedBranch === 'all') {
      toast.error('يرجى اختيار فرع محدد أولاً لإرسال الإشعارات له.');
      return;
    }
    setSendingNotifs(true);
    try {
      const result = await notifyBranchPayslips(selectedBranch, selectedMonth);
      if ('reason' in result) {
        toast.error(result.reason);
        return;
      }
      confetti({ particleCount: 80, spread: 50, colors: ['#3B82F6', '#60A5FA'] });
      toast.success(`تم إرسال إشعارات كشوف الرواتب بنجاح لـ (${result.sent}) موظف في الفرع! 🔔`);
    } catch (err: unknown) {
      toast.error(`فشل إرسال إشعارات الفرع: ${errorMessage(err)}`);
    } finally {
      setSendingNotifs(false);
    }
  };

  const archiveMonth = async () => {
    const confirmed = window.confirm(
      `⚠️ تحذير أمني: هل أنت متأكد من أرشفة كشوف الرواتب لشهر (${selectedMonth})؟\n\n` +
      `عند الأرشفة:\n` +
      `- سيتم حذف سجلات الحضور والغياب التفصيلية لهذا الشهر بشكل نهائي لتوفير المساحة.\n` +
      `- سيتم حذف سجلات المكافآت والخصومات التفصيلية (حيث تم حفظ المبالغ الصافية نهائياً في كشوف الرواتب).\n` +
      `- سيتم قفل الشهر مالياً ولن تتمكن من تعديل أو التراجع عن أي راتب بعد الآن.\n` +
      `- لا يمكن التراجع عن هذه العملية لاحقاً.\n\n` +
      `هل تريد المتابعة؟`,
    );
    if (!confirmed) return;

    setActionLoading('archive_month');
    try {
      const result = await archivePayrollMonth(selectedMonth, cycleStartDay, cycleEndDay);
      if (result && result.success === false) {
        let msg = result.error ?? '';
        if (result.missing_employees?.length) {
          msg += `\n\nالموظفون الذين لم يتم اعتماد رواتبهم بعد:\n- ` + result.missing_employees.join('\n- ');
        }
        alert(msg);
        toast.error(result.error || 'فشلت عملية الأرشفة');
      } else {
        toast.success(result?.message || 'تمت أرشفة الشهر بنجاح! 📦');
        confetti({ particleCount: 100, spread: 70, origin: { y: 0.6 } });
        await loadData();
      }
    } catch (err: unknown) {
      console.error(err);
      toast.error(`خطأ أثناء الأرشفة: ${errorMessage(err)}`);
    } finally {
      setActionLoading(null);
    }
  };

  return {
    loading, actionLoading, sendingNotifs,
    branches: data.branches,
    selectedMonth, startDate, endDate, changeMonth,
    searchTerm, setSearchTerm, selectedBranch, setSelectedBranch,
    rows, filteredRows, pendingRows, totals, isMonthArchived,
    payrollOverrides, saveOverride, clearOverride, toggleExcuseDay,
    addBonusDeduction, generateSlip, bulkGenerateSlips, revertSlip, sendBranchNotifications, archiveMonth,
  };
}

export type PayrollState = ReturnType<typeof usePayroll>;
