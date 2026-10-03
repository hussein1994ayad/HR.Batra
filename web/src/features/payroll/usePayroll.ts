'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';
import { errorMessage } from '@/lib/error-utils';
import {
  approvePayrollSlip, archivePayrollMonth, closePayrollPeriod, decidePayrollEvent, fetchPayrollDataset,
  insertBonusDeduction, notifyBranchPayslips, notifySlipReverted, reopenPayrollPeriod, revertPayrollSlip, type PayrollDataset,
} from './api';
import { buildPayrollRows, buildSlipAdjustments, sumPayroll, type PayrollRow } from './calc';
import { baghdadToday, currentPayrollMonth, monthLabel } from './period';
import { useConfirm } from '@/components/confirm';
import type { OverrideField, PayrollOverrides } from './types';

const EMPTY_DATASET: PayrollDataset = {
  run: null, events: [], branches: [], pendingLeaveEmployeeIds: [], attendanceEmployeeIds: [],
};

/** حالة صفحة الرواتب: مسير الشهر من السيرفر، الفلاتر، التعديلات اليدوية، والإجراءات. */
export function usePayroll() {
  const confirm = useConfirm();
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [sendingNotifs, setSendingNotifs] = useState(false);
  const [data, setData] = useState<PayrollDataset>(EMPTY_DATASET);

  const [selectedMonth, setSelectedMonth] = useState(() => currentPayrollMonth());
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedBranch, setSelectedBranch] = useState('all');
  const [payrollOverrides, setPayrollOverrides] = useState<PayrollOverrides>({});

  const period = data.run?.period ?? null;
  const startDate = period?.start_date ?? '';
  const endDate = period?.cutoff_date ?? '';

  /** quiet: تحديث بالخلفية بدون هيكل التحميل (حتى تبقى النوافذ المفتوحة مثل تفاصيل الخصم) */
  const loadData = useCallback(async (opts?: { quiet?: boolean }) => {
    if (!opts?.quiet) setLoading(true);
    try {
      setData(await fetchPayrollDataset(selectedMonth));
    } catch (err: unknown) {
      console.error(err);
      setData(EMPTY_DATASET);
      toast.error(`تعذر تحميل بيانات الرواتب: ${errorMessage(err)}`);
    } finally {
      setLoading(false);
    }
  }, [selectedMonth]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- جلب البيانات عند تغيّر الشهر
    void loadData();
  }, [loadData]);

  const changeMonth = (month: string) => {
    setSelectedMonth(month);
    setPayrollOverrides({});
  };

  // ------------------------------------------------------------------
  // الصفوف (أرقام السيرفر + التعديلات اليدوية)
  // ------------------------------------------------------------------
  const rows = useMemo(() => (data.run ? buildPayrollRows({
    run: data.run,
    events: data.events,
    overrides: payrollOverrides,
    pendingLeaveEmployeeIds: data.pendingLeaveEmployeeIds,
    attendanceEmployeeIds: data.attendanceEmployeeIds,
  }) : []), [data, payrollOverrides]);

  const filteredRows = useMemo(() => rows.filter(row => {
    const matchesSearch = (row.full_name || '').toLowerCase().includes(searchTerm.toLowerCase());
    const matchesBranch = selectedBranch === 'all' || row.branch_id === selectedBranch;
    return matchesSearch && matchesBranch;
  }), [rows, searchTerm, selectedBranch]);

  const totals = useMemo(() => sumPayroll(filteredRows), [filteredRows]);
  const pendingRows = useMemo(() => filteredRows.filter(r => !r.isIssued), [filteredRows]);
  const isMonthArchived = !!period?.archived;
  const isPeriodClosed = period?.status === 'closed';
  /** لا اعتماد ولا تعديل: الشهر مؤرشف أو المسير مغلق. */
  const isLocked = isMonthArchived || isPeriodClosed;
  const pendingDecisions = useMemo(() => rows.reduce((acc, r) => acc + r.pendingCount, 0), [rows]);

  // ------------------------------------------------------------------
  // التعديلات اليدوية
  // ------------------------------------------------------------------
  const saveOverride = (employeeId: string, field: OverrideField, value: number) => {
    setPayrollOverrides(prev => ({ ...prev, [employeeId]: { ...prev[employeeId], [field]: value } }));
    toast.success('تم تعديل القيمة — ستُحفظ كمكافأة/خصم عند الاعتماد 💸');
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
    toast.success('تمت استعادة القيمة المحتسبة! 🔄');
  };

  const clearEmployeeOverrides = (employeeId: string) =>
    setPayrollOverrides(prev => {
      const updated = { ...prev };
      delete updated[employeeId];
      return updated;
    });

  // ------------------------------------------------------------------
  // الإجراءات
  // ------------------------------------------------------------------
  const run = async <T,>(key: string, fn: () => Promise<T>, onError: string): Promise<T | undefined> => {
    setActionLoading(key);
    try {
      return await fn();
    } catch (err: unknown) {
      toast.error(`${onError}: ${errorMessage(err)}`);
      return undefined;
    } finally {
      setActionLoading(null);
    }
  };

  const addBonusDeduction = async (entry: { employeeId: string; type: 'bonus' | 'deduction'; amount: number; reason: string }) => {
    // القيد يُسجَّل بآخر يوم في المسير المعروض حتى يدخل فيه (أو بتاريخ اليوم إن كان أقدم)
    // اليوم بتوقيت بغداد: UTC كان يرجع اليوم السابق بعد منتصف الليل، فيدخل القيد بالمسير السابق
    const today = baghdadToday();
    const issued = rows.find(r => r.id === entry.employeeId)?.isIssued ?? false;
    const issueDate = endDate && today > endDate ? endDate : today < startDate ? startDate : today;
    const ok = await run('add_bd', async () => {
      await insertBonusDeduction({ ...entry, issueDate });
      return true;
    }, 'حدث خطأ أثناء الإضافة');
    if (!ok) return false;
    confetti({ particleCount: 50, spread: 40 });
    toast.success(issued
      ? 'انضاف ✅ — كشف هذا الشهر معتمد، فينحسب بمسير الشهر الجاي'
      : 'تم إضافة السجل بنجاح! ✅', { duration: issued ? 6000 : 3000 });
    await loadData({ quiet: true });
    return true;
  };

  const decideEvent = async (eventId: string, approve: boolean, reason?: string) => {
    const ok = await run(`decide_${eventId}`, async () => {
      await decidePayrollEvent(eventId, approve, reason);
      return true;
    }, 'تعذر حفظ القرار');
    if (!ok) return;
    toast.success(approve ? 'تم اعتماد الحركة ✅' : 'تم الإعفاء 🟢');
    await loadData({ quiet: true });
  };

  const approveRow = async (row: PayrollRow) => {
    await approvePayrollSlip(row.id, selectedMonth, buildSlipAdjustments(row, selectedMonth));
    clearEmployeeOverrides(row.id);
  };

  const generateSlip = async (row: PayrollRow) => {
    if (row.isIssued) {
      toast.error('تم صرف الراتب مسبقاً لهذا الموظف في هذا الشهر.');
      return;
    }
    // اعتماد راتب = قرار مالي: تأكيد، وتنبيه إذا المسير ما خلص بعد
    const midPeriod = !!endDate && baghdadToday() < endDate;
    const confirmed = await confirm({
      title: `اعتماد راتب ${row.full_name}؟`,
      message: (
        `الصافي: ${Math.round(row.netSalary).toLocaleString('en-US')} د.ع لـ${monthLabel(selectedMonth)}.` +
        (midPeriod ? `

تنبيه: المسير ما خلص بعد (ينتهي ${endDate}). أي غياب أو تأخير أو خصم بعد اليوم ينحسب بمسير الشهر الجاي.` : '')
      ),
      confirmLabel: 'اعتماد الراتب',
      tone: midPeriod ? 'warning' : 'primary',
    });
    if (!confirmed) return;
    const ok = await run(`slip_${row.id}`, async () => {
      await approveRow(row);
      return true;
    }, 'فشل اعتماد الراتب');
    if (!ok) return;
    confetti({ particleCount: 100, spread: 60, colors: ['#10B981', '#059669'] });
    toast.success('تم اعتماد راتب الموظف بنجاح! 💸');
    await loadData();
  };

  const bulkGenerateSlips = async (rowsToProcess: PayrollRow[]) => {
    setActionLoading('bulk_generate');
    let successCount = 0;
    const failed: string[] = [];
    try {
      for (const row of rowsToProcess) {
        if (row.isIssued) continue;
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
    if (isLocked) {
      toast.error(isMonthArchived ? 'هذا الشهر مؤرشف مالياً ومقفل تماماً 🔒' : 'المسير مغلق. أعد فتحه أولاً 🔒');
      return;
    }
    if (!row.slipId) return;
    const slipId = row.slipId;
    const slipCreatedAt = row.slipCreatedAt ?? null;
    const ok = await run(`revert_${row.id}`, async () => {
      await revertPayrollSlip(slipId);
      return true;
    }, 'فشل في التراجع عن الاعتماد');
    if (!ok) return;
    toast.success('تم التراجع عن اعتماد الراتب بنجاح! 🔄');
    // إذا وصله "تم اعتماد وصرف راتبك" نبلغه بالإلغاء
    try {
      await notifySlipReverted(row.id, selectedMonth, slipCreatedAt);
    } catch (err: unknown) {
      console.error('notifySlipReverted', err);
    }
    await loadData();
  };

  const closePeriod = async () => {
    const confirmed = window.confirm(
      `إغلاق مسير (${selectedMonth})؟\n\n` +
      `- لن يمكن اعتماد أو إلغاء أي كشف في هذا المسير.\n` +
      `- أي تعديل لاحق على أيامه (غياب/تأخير/إعفاء) يُحسب تلقائياً كتسوية في أول مسير مفتوح.\n` +
      `- الحركات المعلّقة بدون قرار تنتقل للمسير التالي.\n` +
      `- يمكن إعادة فتحه لاحقاً مع كتابة السبب.`,
    );
    if (!confirmed) return;
    const result = await run('close_period', () => closePayrollPeriod(selectedMonth), 'تعذر إغلاق المسير');
    if (!result) return;
    if (!result.success) {
      let msg = result.error ?? '';
      if (result.missing_employees?.length) msg += `\n\nبدون كشف معتمد:\n- ${result.missing_employees.join('\n- ')}`;
      alert(msg);
      return;
    }
    toast.success(result.message || 'تم إغلاق المسير 🔒');
    await loadData();
  };

  const reopenPeriod = async () => {
    const reason = window.prompt('سبب إعادة فتح المسير (يُسجَّل للتدقيق):')?.trim();
    if (!reason) return;
    const ok = await run('reopen_period', async () => {
      await reopenPayrollPeriod(selectedMonth, reason);
      return true;
    }, 'تعذر إعادة فتح المسير');
    if (!ok) return;
    toast.success('تمت إعادة فتح المسير 🔓');
    await loadData();
  };

  const sendBranchNotifications = async () => {
    if (selectedBranch === 'all') {
      toast.error('يرجى اختيار فرع محدد أولاً لإرسال الإشعارات له.');
      return;
    }
    const branchName = data.branches.find(b => b.id === selectedBranch)?.name ?? 'الفرع';
    const confirmed = await confirm({
      title: 'إرسال إشعار كشف الراتب؟',
      message: `يوصل إشعار "تم اعتماد وصرف راتبك لـ${monthLabel(selectedMonth)}" لموظفي ${branchName} الي كشوفهم معتمدة. الي وصلهم الإشعار قبل ما ينبعثلهم مرة ثانية.`,
      confirmLabel: 'إرسال',
      tone: 'primary',
    });
    if (!confirmed) return;
    setSendingNotifs(true);
    try {
      const result = await notifyBranchPayslips(selectedBranch, selectedMonth);
      if ('reason' in result) {
        toast.error(result.reason);
        return;
      }
      confetti({ particleCount: 80, spread: 50, colors: ['#3B82F6', '#60A5FA'] });
      toast.success(`تم إرسال إشعارات كشوف الرواتب لـ (${result.sent}) موظف 🔔${result.skipped ? ` — و${result.skipped} وصلهم قبل` : ''}`);
    } catch (err: unknown) {
      toast.error(`فشل إرسال إشعارات الفرع: ${errorMessage(err)}`);
    } finally {
      setSendingNotifs(false);
    }
  };

  const archiveMonth = async () => {
    if (!isPeriodClosed && !period?.legacy) {
      toast.error('أغلق المسير أولاً قبل الأرشفة 🔒');
      return;
    }
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

    const result = await run('archive_month', () => archivePayrollMonth(selectedMonth), 'خطأ أثناء الأرشفة');
    if (!result) return;
    if (result.success === false) {
      let msg = result.error ?? '';
      if (result.missing_employees?.length) {
        msg += `\n\nالموظفون الذين لم يتم اعتماد رواتبهم بعد:\n- ` + result.missing_employees.join('\n- ');
      }
      alert(msg);
      toast.error(result.error || 'فشلت عملية الأرشفة');
      return;
    }
    toast.success(result.message || 'تمت أرشفة الشهر بنجاح! 📦');
    confetti({ particleCount: 100, spread: 70, origin: { y: 0.6 } });
    await loadData();
  };

  return {
    loading, actionLoading, sendingNotifs,
    branches: data.branches,
    period, selectedMonth, startDate, endDate, changeMonth,
    searchTerm, setSearchTerm, selectedBranch, setSelectedBranch,
    rows, filteredRows, pendingRows, totals, pendingDecisions,
    isMonthArchived, isPeriodClosed, isLocked,
    payrollOverrides, saveOverride, clearOverride,
    addBonusDeduction, decideEvent, generateSlip, bulkGenerateSlips, revertSlip,
    closePeriod, reopenPeriod, sendBranchNotifications, archiveMonth,
  };
}

export type PayrollState = ReturnType<typeof usePayroll>;
