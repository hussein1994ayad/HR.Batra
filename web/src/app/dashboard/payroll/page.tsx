'use client';

import React, { useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import {
  Banknote,
  Building,
  Plus,
  TrendingUp,
  TrendingDown,
  CheckCircle2,
  Printer,
  CalendarRange,
  Info,
  Clock,
  Undo2,
  Wallet,
  Users,
  AlertTriangle,
  RotateCcw,
  Check,
} from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { confetti } from '@/lib/lazy';
import { useQuery } from '@/lib/useQuery';
import { formatLateDurationArabic } from '@/lib/attendance';
import { computePayrollRow, getCycleDates, type DayTone, type PayrollField, type PayrollOverrides, type PayrollRow } from '@/lib/payroll';
import { MONTHS_AR, errorMessage, formatIQD } from '@/lib/format';
import type { Attendance, BonusDeduction, Branch, Employee, LeaveRequest, LoanInstallment, SalarySlip, WorkSchedule } from '@/lib/types';
import { useConfirm } from '@/components/confirm';
import {
  AmountInput,
  Avatar,
  Badge,
  Button,
  Card,
  DataTable,
  EmptyState,
  Field,
  FilterSelect,
  IconButton,
  InfoNote,
  Input,
  Modal,
  ModalFooter,
  PageHeader,
  PageSkeleton,
  SearchInput,
  SegmentedTabs,
  StatTile,
  TableEmpty,
  cn,
  type Tone,
} from '@/components/ui';

interface PayrollData {
  month: string;
  startDate: string;
  endDate: string;
  branches: Pick<Branch, 'id' | 'name'>[];
  employees: Employee[];
  bonuses: BonusDeduction[];
  installments: LoanInstallment[];
  attendance: Attendance[];
  leaves: LeaveRequest[];
  schedules: WorkSchedule[];
  slips: SalarySlip[];
}

async function fetchPayroll(month: string): Promise<PayrollData> {
  const { data: policy } = await supabase.from('system_settings').select('*').eq('key', 'payroll_policy').maybeSingle();
  const { start, end } = getCycleDates(month, policy?.value?.cycle_start_day || 25, policy?.value?.cycle_end_day || 24);

  const [brs, emps, bds, loans, att, lvs, scheds, slips] = await Promise.all([
    supabase.from('branches').select('id, name'),
    supabase
      .from('employees')
      .select('id, full_name, monthly_salary_iqd, future_salary_iqd, future_salary_month, branch_id, department_id, branches(name)')
      .eq('is_active', true)
      .order('full_name'),
    supabase.from('bonuses_deductions').select('*').gte('issue_date', start).lte('issue_date', end),
    supabase.from('loan_installments').select('*, loans!inner(employee_id)').gte('due_date', start).lte('due_date', end).eq('is_paid', false),
    supabase.from('attendance').select('*').gte('work_date', start).lte('work_date', end),
    supabase.from('leave_requests').select('*').in('status', ['approved', 'pending']).lte('start_date', end).gte('end_date', start),
    supabase.from('work_schedules').select('*'),
    supabase.from('salary_slips').select('*').eq('work_month', month),
  ]);
  if (emps.error) throw emps.error;

  return {
    month,
    startDate: start,
    endDate: end,
    branches: (brs.data ?? []) as PayrollData['branches'],
    employees: (emps.data ?? []) as unknown as Employee[],
    bonuses: (bds.data ?? []) as BonusDeduction[],
    installments: (loans.data ?? []) as LoanInstallment[],
    attendance: (att.data ?? []) as Attendance[],
    leaves: (lvs.data ?? []) as LeaveRequest[],
    schedules: (scheds.data ?? []) as WorkSchedule[],
    slips: (slips.data ?? []) as SalarySlip[],
  };
}

/**
 * Publishes a salary slip for one employee and records the audit trail:
 * paid loan installments, manual adjustments and automatic attendance deductions.
 */
async function issueSlip(row: PayrollRow, month: string, start: string, end: string): Promise<void> {
  const { error } = await supabase.from('salary_slips').insert({
    employee_id: row.id,
    work_month: month,
    basic_salary: row.basic,
    allowances: row.totalBonuses,
    deductions: row.totalDeductions,
    loans_deduction: row.loanDeduction,
    net_salary: row.netSalary,
    status: 'published',
  });
  if (error) throw error;

  if (row.loanInstallmentIds.length > 0) {
    await supabase.from('loan_installments').update({ is_paid: true, paid_at: new Date().toISOString() }).in('id', row.loanInstallmentIds);
  }

  const insertAdjustment = (type: 'bonus' | 'deduction', amount: number, reason: string) =>
    supabase.from('bonuses_deductions').insert({ employee_id: row.id, type, amount, reason, issue_date: end });

  if (row.isBonusesOverridden) {
    const diff = row.totalBonuses - row.computedBonuses;
    if (diff > 0) await insertAdjustment('bonus', diff, `تسوية زيادة مكافآت يدوياً لشهر ${month}`);
    else if (diff < 0) await insertAdjustment('deduction', -diff, `تسوية تخفيض مكافآت يدوياً لشهر ${month}`);
  }

  if (row.isOtherDeductionsOverridden) {
    const diff = row.totalDeductions - row.totalAttendanceDeductions - row.computedOtherDeductions;
    if (diff > 0) await insertAdjustment('deduction', diff, `تسوية زيادة خصومات يدوياً لشهر ${month}`);
    else if (diff < 0) await insertAdjustment('bonus', -diff, `تسوية تخفيض خصومات يدوياً لشهر ${month}`);
  }

  const period = `للفترة من ${start} إلى ${end}`;
  if (row.isAttendanceDeductionsOverridden) {
    if (row.totalAttendanceDeductions > 0) {
      await insertAdjustment('deduction', row.totalAttendanceDeductions, `خصم غياب وحضور معدل يدوياً ${period}`);
    }
  } else if (row.totalAttendanceDeductions > 0) {
    const addOnce = async (amount: number, reason: string) => {
      if (amount <= 0) return;
      const { data: existing } = await supabase
        .from('bonuses_deductions')
        .select('id')
        .eq('employee_id', row.id)
        .eq('type', 'deduction')
        .eq('reason', reason)
        .maybeSingle();
      if (!existing) await insertAdjustment('deduction', amount, reason);
    };
    await addOnce(row.absenceDeduction, `خصم غياب غير مبرر (${row.absencesCount} يوم) ${period}`);
    await addOnce(row.halfDayDeduction, `خصم نصف يوم (${row.halfDaysCount} يوم) ${period}`);
    await addOnce(row.latenessDeduction, `خصم تأخير الحضور (${formatLateDurationArabic(row.totalLateMinutes)}) ${period}`);
    await addOnce(row.earlyExitDeduction, `خصم خروج مبكر (${formatLateDurationArabic(row.totalEarlyExitMinutes)}) ${period}`);
  }

  await supabase.from('notifications').insert({
    employee_id: row.id,
    title: 'اعتماد كشف الراتب 💸',
    body: `تم اعتماد وصرف كشف راتبك لشهر (${month}) بصافي مستلم قدره (${row.netSalary.toLocaleString()} د.ع).`,
    type: 'salary',
  });
}

const DAY_TONE: Record<DayTone, Tone> = {
  present: 'emerald',
  excused: 'teal',
  absent: 'rose',
  leave: 'sky',
  warning: 'amber',
  late: 'orange',
  future: 'slate',
};

function currentMonth(): string {
  const d = new Date();
  return `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}`;
}

export default function PayrollPage() {
  const confirm = useConfirm();
  const [month, setMonth] = useState(currentMonth);
  const query = useQuery(`payroll:${month}`, () => fetchPayroll(month));
  const [search, setSearch] = useState('');
  const [branchId, setBranchId] = useState('all');
  const [statusFilter, setStatusFilter] = useState<'all' | 'pending' | 'issued'>('all');
  const [overrides, setOverrides] = useState<Record<string, PayrollOverrides>>({});
  const [excused, setExcused] = useState<Record<string, string[]>>({});
  const [editing, setEditing] = useState<{ id: string; field: PayrollField } | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [adjustFor, setAdjustFor] = useState<PayrollRow | null>(null);
  const [breakdownId, setBreakdownId] = useState<string | null>(null);
  const [bulkOpen, setBulkOpen] = useState(false);

  const data = query.data && query.data.month === month ? query.data : undefined;

  const rows = useMemo(() => {
    if (!data) return [];
    return data.employees.map((emp) =>
      computePayrollRow(emp, {
        selectedMonth: data.month,
        startDate: data.startDate,
        endDate: data.endDate,
        schedules: data.schedules,
        attendance: data.attendance,
        leaves: data.leaves,
        bonusesAndDeductions: data.bonuses,
        installments: data.installments,
        slips: data.slips,
        overrides: overrides[emp.id] ?? {},
        excusedDays: excused[emp.id] ?? [],
      }),
    );
  }, [data, overrides, excused]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    return rows.filter(
      (r) =>
        (branchId === 'all' || r.branch_id === branchId) &&
        (statusFilter === 'all' || (statusFilter === 'issued') === r.isIssued) &&
        (!q || (r.full_name || '').toLowerCase().includes(q)),
    );
  }, [rows, search, branchId, statusFilter]);

  if (!data) {
    if (query.error) {
      return <EmptyState icon={AlertTriangle} tone="rose" title="تعذر تحميل بيانات الرواتب" description={errorMessage(query.error)} action={<Button size="sm" variant="secondary" onClick={query.reload}>إعادة المحاولة</Button>} />;
    }
    return <PageSkeleton rows={8} />;
  }

  const totalNet = filtered.reduce((s, r) => s + r.netSalary, 0);
  const totalBase = filtered.reduce((s, r) => s + r.basic, 0);
  const totalDeductions = filtered.reduce((s, r) => s + r.totalDeductions + r.loanDeduction, 0);
  const issuedCount = filtered.filter((r) => r.isIssued).length;
  const pendingRows = filtered.filter((r) => !r.isIssued);
  const breakdown = rows.find((r) => r.id === breakdownId) ?? null;
  const branchName = data.branches.find((b) => b.id === branchId)?.name ?? 'جميع الفروع';
  const [year, monthNum] = month.split('-');

  const setOverride = (id: string, field: PayrollField, value: number | undefined) => {
    setOverrides((prev) => {
      const next = { ...(prev[id] ?? {}) };
      if (value === undefined) delete next[field];
      else next[field] = value;
      return { ...prev, [id]: next };
    });
    setEditing(null);
  };

  const approveOne = async (row: PayrollRow) => {
    if (row.isNetNegative) {
      const ok = await confirm({ title: 'الراتب الصافي سالب', message: 'هل تريد اعتماد الراتب رغم أن صافيه سالب؟', confirmLabel: 'اعتماد', tone: 'warning' });
      if (!ok) return;
    }
    setBusy(`slip_${row.id}`);
    try {
      await issueSlip(row, data.month, data.startDate, data.endDate);
      confetti({ particleCount: 90, spread: 60, colors: ['#10B981', '#059669'] });
      toast.success(`تم اعتماد راتب ${row.full_name}`);
      query.reload();
    } catch (err) {
      toast.error(`فشل اعتماد الراتب: ${errorMessage(err)}`);
    } finally {
      setBusy(null);
    }
  };

  const approveBulk = async () => {
    setBusy('bulk');
    let ok = 0;
    for (const row of pendingRows) {
      try {
        await issueSlip(row, data.month, data.startDate, data.endDate);
        ok++;
      } catch (err) {
        console.error(`Error generating slip for ${row.full_name}:`, err);
      }
    }
    setBusy(null);
    setBulkOpen(false);
    confetti({ particleCount: 150, spread: 80, colors: ['#10B981', '#818CF8'] });
    if (ok === pendingRows.length) toast.success(`تم اعتماد رواتب ${ok} موظف`);
    else toast.error(`تم اعتماد ${ok} من ${pendingRows.length}، راجع السجلات المتبقية`);
    query.reload();
  };

  const revert = async (row: PayrollRow) => {
    const ok = await confirm({
      title: 'إلغاء اعتماد الراتب؟',
      message: 'سيتم حذف كشف الراتب وقيود الخصم التلقائية لهذه الدورة وإرجاع أقساط السلف إلى غير مدفوعة.',
      confirmLabel: 'إلغاء الاعتماد',
      tone: 'warning',
    });
    if (!ok) return;
    const slip = data.slips.find((s) => s.employee_id === row.id);
    if (!slip) return;
    setBusy(`revert_${row.id}`);
    try {
      const { error } = await supabase.from('salary_slips').delete().eq('id', slip.id);
      if (error) throw error;
      await supabase
        .from('bonuses_deductions')
        .delete()
        .eq('employee_id', row.id)
        .eq('issue_date', data.endDate)
        .or(`reason.like.%للفترة من ${data.startDate} إلى ${data.endDate}%,reason.like.%لشهر ${data.month}%`);
      const { data: loans } = await supabase.from('loans').select('id').eq('employee_id', row.id);
      if (loans && loans.length > 0) {
        await supabase
          .from('loan_installments')
          .update({ is_paid: false, paid_at: null })
          .in('loan_id', loans.map((l) => l.id))
          .gte('due_date', data.startDate)
          .lte('due_date', data.endDate)
          .eq('is_paid', true);
      }
      toast.success('تم التراجع عن اعتماد الراتب');
      query.reload();
    } catch (err) {
      toast.error(`فشل التراجع عن الاعتماد: ${errorMessage(err)}`);
    } finally {
      setBusy(null);
    }
  };

  const toggleExcuse = (employeeId: string, date: string) =>
    setExcused((prev) => {
      const list = prev[employeeId] ?? [];
      return { ...prev, [employeeId]: list.includes(date) ? list.filter((d) => d !== date) : [...list, date] };
    });

  const editableCell = (row: PayrollRow, field: PayrollField, value: number, tone: string, sign: string) => {
    const isOpen = editing?.id === row.id && editing.field === field;
    const overridden = overrides[row.id]?.[field] !== undefined;
    return (
      <div className="relative inline-block">
        <button
          type="button"
          onClick={() => (row.isIssued ? toast.error('الراتب معتمد ولا يمكن تعديله') : setEditing({ id: row.id, field }))}
          className={cn(
            'font-bold whitespace-nowrap border-b border-dashed transition-colors cursor-pointer',
            tone,
            overridden ? 'border-amber-400/70 bg-amber-400/10 px-1.5 rounded-md' : 'border-slate-700 hover:border-indigo-400',
            row.isIssued && 'cursor-default border-transparent',
          )}
          title={row.isIssued ? undefined : 'اضغط للتعديل يدوياً'}
        >
          {value > 0 ? `${sign}${value.toLocaleString('en-US')}` : '—'}
          {overridden && <span className="text-amber-300 mr-0.5">*</span>}
        </button>
        {isOpen && (
          <InlineAmountEditor
            initial={value}
            overridden={overridden}
            onSave={(v) => setOverride(row.id, field, v)}
            onReset={() => setOverride(row.id, field, undefined)}
            onCancel={() => setEditing(null)}
          />
        )}
      </div>
    );
  };

  return (
    <div className="space-y-6 pb-12">
      <PageHeader
        icon={Banknote}
        tone="emerald"
        title="الرواتب والمكافآت"
        description={
          <span className="inline-flex flex-wrap items-center gap-1.5">
            الدورة المالية
            <span className="font-mono font-bold text-slate-200" dir="ltr">{data.startDate}</span>←
            <span className="font-mono font-bold text-slate-200" dir="ltr">{data.endDate}</span>
            {query.refreshing && <span className="text-indigo-300">· جاري التحديث...</span>}
          </span>
        }
        actions={
          <>
            <div className="flex items-center gap-1 h-9 rounded-xl bg-slate-950/70 border border-slate-800 px-1">
              <select
                aria-label="الشهر"
                value={monthNum}
                onChange={(e) => setMonth(`${year}-${e.target.value}`)}
                className="h-7 bg-transparent text-xs font-bold text-white outline-none cursor-pointer px-1"
              >
                {MONTHS_AR.map((name, i) => (
                  <option key={name} value={(i + 1).toString().padStart(2, '0')}>
                    {name}
                  </option>
                ))}
              </select>
              <select
                aria-label="السنة"
                value={year}
                onChange={(e) => setMonth(`${e.target.value}-${monthNum}`)}
                className="h-7 bg-transparent text-xs font-bold text-white outline-none cursor-pointer px-1 font-mono"
              >
                {Array.from({ length: 9 }, (_, i) => 2024 + i).map((y) => (
                  <option key={y} value={y}>
                    {y}
                  </option>
                ))}
              </select>
            </div>
            <Button size="sm" variant="secondary" icon={Printer} onClick={() => window.print()} className="print:hidden">
              طباعة
            </Button>
          </>
        }
      />

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatTile label="صافي الرواتب" value={formatIQD(totalNet)} icon={Wallet} tone="emerald" hint={branchName} />
        <StatTile label="الرواتب الأساسية" value={formatIQD(totalBase)} icon={Banknote} tone="indigo" />
        <StatTile label="الخصومات والسلف" value={formatIQD(totalDeductions)} icon={TrendingDown} tone="rose" />
        <StatTile label="الرواتب المعتمدة" value={`${issuedCount} / ${filtered.length}`} icon={CheckCircle2} tone={issuedCount === filtered.length && filtered.length > 0 ? 'emerald' : 'amber'} />
      </div>

      <Card>
        <div className="flex flex-col xl:flex-row xl:items-center justify-between gap-3 mb-5 print:hidden">
          <div className="flex flex-col sm:flex-row gap-2">
            <SearchInput value={search} onChange={setSearch} placeholder="ابحث باسم الموظف..." className="w-full sm:w-60" />
            <FilterSelect icon={Building} value={branchId} onChange={setBranchId} className="sm:w-44">
              <option value="all">جميع الفروع</option>
              {data.branches.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </FilterSelect>
            <SegmentedTabs
              value={statusFilter}
              onChange={setStatusFilter}
              options={[
                { value: 'all', label: 'الكل' },
                { value: 'pending', label: 'غير معتمد' },
                { value: 'issued', label: 'معتمد' },
              ]}
            />
          </div>
          <Button variant="success" icon={CheckCircle2} disabled={pendingRows.length === 0} onClick={() => setBulkOpen(true)}>
            اعتماد رواتب {branchId === 'all' ? 'الكل' : 'الفرع'} ({pendingRows.length})
          </Button>
        </div>

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
            {filtered.length === 0 ? (
              <TableEmpty colSpan={8}>لا توجد بيانات مطابقة</TableEmpty>
            ) : (
              filtered.map((row) => (
                <tr key={row.id} className={cn(row.isIssued && 'bg-emerald-500/[0.03]')}>
                  <td>
                    <div className="flex items-start gap-2.5 min-w-[200px]">
                      <Avatar name={row.full_name} size="sm" />
                      <div className="min-w-0">
                        <p className="font-bold text-white truncate">{row.full_name}</p>
                        <p className="text-[10px] text-slate-500">{row.branches?.name || 'بدون فرع'}</p>
                        <div className="flex flex-wrap gap-1 mt-1">
                          {row.isNetNegative && <Badge tone="rose">صافي سالب</Badge>}
                          {row.isAttendanceMissing && <Badge tone="amber">لا بصمات</Badge>}
                          {row.hasPendingLeave && <Badge tone="sky">إجازة معلقة</Badge>}
                          {row.unconfirmedAbsencesCount > 0 && <Badge tone="orange">غياب غير مثبت ({row.unconfirmedAbsencesCount})</Badge>}
                        </div>
                        <button
                          type="button"
                          onClick={() => setBreakdownId(row.id)}
                          className="mt-1 inline-flex items-center gap-1 text-[10px] font-bold text-indigo-300 hover:text-indigo-200 cursor-pointer print:hidden"
                        >
                          <Info className="w-3 h-3" /> تفاصيل الحضور والخصم
                        </button>
                      </div>
                    </div>
                  </td>
                  <td className="font-bold text-slate-200 whitespace-nowrap">{row.basic.toLocaleString('en-US')}</td>
                  <td>{editableCell(row, 'bonuses', row.totalBonuses, 'text-emerald-300', '+')}</td>
                  <td>
                    {editableCell(row, 'attendanceDeductions', row.totalAttendanceDeductions, 'text-amber-300', '−')}
                    {!row.isAttendanceDeductionsOverridden && row.totalAttendanceDeductions > 0 && (
                      <span className="block text-[10px] text-slate-500 mt-0.5">
                        {row.absencesCount} غياب · {row.halfDaysCount} نصف يوم
                      </span>
                    )}
                  </td>
                  <td>{editableCell(row, 'otherDeductions', row.totalDeductions - row.totalAttendanceDeductions, 'text-rose-300', '−')}</td>
                  <td className="font-bold text-orange-300 whitespace-nowrap">{row.loanDeduction > 0 ? `−${row.loanDeduction.toLocaleString('en-US')}` : '—'}</td>
                  <td className="whitespace-nowrap">
                    <span className={cn('text-sm font-extrabold', row.netSalary < 0 ? 'text-rose-300' : 'text-white')}>{formatIQD(row.netSalary)}</span>
                  </td>
                  <td className="!text-left print:hidden">
                    <div className="flex items-center justify-end gap-1.5">
                      <IconButton icon={Plus} label="إضافة مكافأة أو خصم" tone="slate" onClick={() => setAdjustFor(row)} />
                      {row.isIssued ? (
                        <>
                          <Badge tone="emerald" dot>معتمد</Badge>
                          <IconButton icon={Undo2} label="إلغاء الاعتماد" tone="amber" loading={busy === `revert_${row.id}`} onClick={() => revert(row)} />
                        </>
                      ) : (
                        <Button size="xs" variant="soft-success" icon={Check} loading={busy === `slip_${row.id}`} disabled={busy === 'bulk'} onClick={() => approveOne(row)}>
                          اعتماد
                        </Button>
                      )}
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </DataTable>
      </Card>

      {adjustFor && (
        <AdjustmentModal
          row={adjustFor}
          onClose={() => setAdjustFor(null)}
          onSaved={() => {
            setAdjustFor(null);
            query.reload();
          }}
        />
      )}

      {breakdown && (
        <Modal title="تفاصيل الحضور والخصومات" subtitle={`${breakdown.full_name} · ${data.startDate} ← ${data.endDate}`} icon={CalendarRange} tone="indigo" size="lg" onClose={() => setBreakdownId(null)}>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
            <StatTile label="أيام العمل" value={breakdown.scheduledWorkDays} tone="slate" className="!p-3" />
            <StatTile
              label="الحضور"
              value={breakdown.presentsCount}
              tone="emerald"
              className="!p-3"
              hint={[breakdown.latesCount > 0 && `${breakdown.latesCount} تأخير`, breakdown.earlyExitsCount > 0 && `${breakdown.earlyExitsCount} خروج مبكر`].filter(Boolean).join(' · ') || undefined}
            />
            <StatTile label="غيابات بخصم" value={breakdown.absencesCount} tone="rose" className="!p-3" />
            <StatTile label="إجازات مدفوعة" value={breakdown.paidLeavesCount} tone="sky" className="!p-3" />
          </div>

          <InfoNote tone="indigo" icon={Info} className="mb-5">
            <p>أجرة اليوم = {formatIQD(breakdown.basic)} ÷ 30 = <b>{formatIQD(breakdown.basic / 30)}</b></p>
            {breakdown.absencesCount > 0 && <p>خصم الغياب = {breakdown.absencesCount} يوم × أجرة اليوم = <b>{formatIQD(breakdown.absenceDeduction)}</b></p>}
            {breakdown.halfDaysCount > 0 && <p>خصم أنصاف الأيام = {breakdown.halfDaysCount} × نصف أجرة يوم = <b>{formatIQD(breakdown.halfDayDeduction)}</b></p>}
            {breakdown.totalLateMinutes > 0 && (
              <p>خصم التأخير = {breakdown.totalLateMinutes} دقيقة × (أجرة اليوم ÷ {breakdown.workdayMinutes} دقيقة) = <b>{formatIQD(breakdown.latenessDeduction)}</b></p>
            )}
            {breakdown.totalEarlyExitMinutes > 0 && (
              <p>خصم الخروج المبكر = {breakdown.totalEarlyExitMinutes} دقيقة = <b>{formatIQD(breakdown.earlyExitDeduction)}</b></p>
            )}
            <p className="mt-1 pt-1 border-t border-indigo-500/20">إجمالي خصومات الدوام = <b className="text-white">{formatIQD(breakdown.totalAttendanceDeductions)}</b></p>
          </InfoNote>

          <p className="text-[11px] text-slate-400 mb-2 flex items-center gap-1.5">
            <Clock className="w-3.5 h-3.5" /> يوميات الدورة — يمكنك إعفاء أيام الغياب المعفاة إدارياً
          </p>
          <div className="max-h-[300px] overflow-y-auto rounded-2xl border border-slate-800/80 divide-y divide-slate-800/70">
            {breakdown.detailLogs.map((log) => (
              <div key={log.date} className="p-3 flex flex-col sm:flex-row sm:items-center justify-between gap-2 text-xs">
                <div className="flex items-center gap-2.5">
                  <span className="font-mono text-slate-400" dir="ltr">{log.date}</span>
                  <Badge tone={DAY_TONE[log.tone]}>{log.status}</Badge>
                  {log.time !== '-' && <span className="text-slate-500 font-mono" dir="ltr">{log.time}</span>}
                </div>
                {log.isAbsenceDay ? (
                  <Button size="xs" variant={log.isExcused ? 'soft-danger' : 'soft-success'} icon={RotateCcw} disabled={breakdown.isIssued} onClick={() => toggleExcuse(breakdown.id, log.date)}>
                    {log.isExcused ? 'إلغاء الإعفاء' : 'إعفاء'}
                  </Button>
                ) : (
                  <span className="text-[11px] text-slate-500 sm:text-left">{log.note}</span>
                )}
              </div>
            ))}
          </div>
        </Modal>
      )}

      {bulkOpen && (
        <Modal title="اعتماد الرواتب دفعة واحدة" subtitle={`${branchName} · ${MONTHS_AR[Number(monthNum) - 1]} ${year}`} icon={Users} tone="emerald" onClose={() => setBulkOpen(false)}>
          <div className="grid grid-cols-2 gap-3 mb-4">
            <StatTile label="عدد الموظفين" value={pendingRows.length} tone="slate" className="!p-3" />
            <StatTile label="الرواتب الأساسية" value={formatIQD(pendingRows.reduce((s, r) => s + r.basic, 0))} tone="indigo" className="!p-3" />
            <StatTile label="المكافآت" value={formatIQD(pendingRows.reduce((s, r) => s + r.totalBonuses, 0))} tone="emerald" className="!p-3" />
            <StatTile label="الخصومات والسلف" value={formatIQD(pendingRows.reduce((s, r) => s + r.totalDeductions + r.loanDeduction, 0))} tone="rose" className="!p-3" />
          </div>
          <div className="rounded-2xl bg-emerald-500/5 border border-emerald-500/20 p-4 text-center mb-4">
            <p className="text-[11px] text-slate-400 mb-1">إجمالي الصافي المستحق</p>
            <p className="text-2xl font-extrabold text-emerald-300">{formatIQD(pendingRows.reduce((s, r) => s + r.netSalary, 0))}</p>
          </div>
          {pendingRows.some((r) => r.isNetNegative || r.unconfirmedAbsencesCount > 0) && (
            <InfoNote tone="amber" icon={AlertTriangle} className="mb-2">
              بعض الموظفين لديهم تنبيهات (صافي سالب أو غياب غير مثبت). راجعهم قبل الاعتماد.
            </InfoNote>
          )}
          <InfoNote tone="slate" icon={Info}>
            سيُرسل إشعار لكل موظف بكشف راتبه وتُحدَّث أقساط السلف والخصومات تلقائياً.
          </InfoNote>
          <ModalFooter onCancel={() => setBulkOpen(false)} onSubmit={approveBulk} loading={busy === 'bulk'} loadingLabel="جاري الاعتماد..." submitLabel={`اعتماد ${pendingRows.length} راتب`} variant="success" submitIcon={CheckCircle2} />
        </Modal>
      )}
    </div>
  );
}

function InlineAmountEditor({
  initial,
  overridden,
  onSave,
  onReset,
  onCancel,
}: {
  initial: number;
  overridden: boolean;
  onSave: (value: number) => void;
  onReset: () => void;
  onCancel: () => void;
}) {
  const [value, setValue] = useState(initial);
  return (
    <div
      className="absolute z-30 top-full mt-2 right-1/2 translate-x-1/2 w-52 surface-solid rounded-2xl p-3 space-y-2.5 animate-glass text-right"
      onKeyDown={(e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          onSave(value);
        } else if (e.key === 'Escape') {
          e.stopPropagation();
          onCancel();
        }
      }}
    >
      <p className="text-[10px] font-bold text-slate-400">تعديل القيمة يدوياً (د.ع)</p>
      <AmountInput autoFocus value={value} onValueChange={setValue} className="h-9" />
      <div className="flex items-center gap-1.5">
        {overridden && (
          <Button size="xs" variant="ghost" icon={RotateCcw} onClick={onReset} className="ml-auto">
            تلقائي
          </Button>
        )}
        <Button size="xs" variant="ghost" onClick={onCancel} className={overridden ? '' : 'mr-auto'}>
          إلغاء
        </Button>
        <Button size="xs" onClick={() => onSave(value)}>
          حفظ
        </Button>
      </div>
    </div>
  );
}

function AdjustmentModal({ row, onClose, onSaved }: { row: PayrollRow; onClose: () => void; onSaved: () => void }) {
  const [type, setType] = useState<'bonus' | 'deduction'>('bonus');
  const [amount, setAmount] = useState(0);
  const [reason, setReason] = useState('');
  const [saving, setSaving] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (amount <= 0) {
      toast.error('أدخل مبلغاً أكبر من صفر');
      return;
    }
    setSaving(true);
    try {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      const now = new Date();
      const issueDate = `${now.getFullYear()}-${(now.getMonth() + 1).toString().padStart(2, '0')}-${now.getDate().toString().padStart(2, '0')}`;
      const { error } = await supabase.from('bonuses_deductions').insert({
        employee_id: row.id,
        type,
        amount,
        reason,
        issue_date: issueDate,
        created_by: user?.id,
      });
      if (error) throw error;
      toast.success(type === 'bonus' ? 'تمت إضافة المكافأة' : 'تمت إضافة الخصم');
      onSaved();
    } catch (err) {
      toast.error(`حدث خطأ أثناء الإضافة: ${errorMessage(err)}`);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal title="تسوية مالية يدوية" subtitle={row.full_name} icon={type === 'bonus' ? TrendingUp : TrendingDown} tone={type === 'bonus' ? 'emerald' : 'rose'} size="sm" onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <div className="grid grid-cols-2 gap-2">
          {(['bonus', 'deduction'] as const).map((t) => {
            const active = type === t;
            const Icon = t === 'bonus' ? TrendingUp : TrendingDown;
            return (
              <button
                key={t}
                type="button"
                onClick={() => setType(t)}
                className={cn(
                  'flex flex-col items-center gap-1.5 py-3 rounded-2xl border text-xs font-bold transition-colors cursor-pointer',
                  active
                    ? t === 'bonus'
                      ? 'border-emerald-400/50 bg-emerald-500/10 text-emerald-300'
                      : 'border-rose-400/50 bg-rose-500/10 text-rose-300'
                    : 'border-slate-800 bg-slate-950/50 text-slate-400 hover:text-slate-200',
                )}
              >
                <Icon className="w-5 h-5" />
                {t === 'bonus' ? 'مكافأة (+)' : 'خصم (−)'}
              </button>
            );
          })}
        </div>
        <Field label="المبلغ (د.ع)">
          <AmountInput required autoFocus value={amount} onValueChange={setAmount} placeholder="25,000" />
        </Field>
        <Field label="السبب">
          <Input required value={reason} onChange={(e) => setReason(e.target.value)} placeholder="مثال: ساعات إضافية، عقوبة إدارية..." />
        </Field>
        <ModalFooter onCancel={onClose} loading={saving} submitLabel="حفظ" variant={type === 'bonus' ? 'success' : 'danger'} />
      </form>
    </Modal>
  );
}
