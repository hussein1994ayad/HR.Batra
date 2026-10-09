'use client';

// حالة وإجراءات صفحة السلف: تحميل الطلبات والسلف المعتمدة، الاعتماد/الرفض، التعديل وإعادة الجدولة،
// تسجيل/التراجع عن دفعة، تأجيل الأقساط، والحذف. كل إجراء يمر بـ run (مؤشر تحميل + رسالة خطأ موحّدة).

import React, { useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import { confetti } from '@/lib/lazy';
import { useQuery } from '@/lib/useQuery';
import { errorMessage } from '@/lib/format';
import { useConfirm, useConfirmNote } from '@/components/confirm';
import type { Loan, LoanInstallment } from '@/lib/db-types';
import {
  approveLoan, deleteCompletedLoan, fetchLoans, payInstallment,
  postponeInstallment, rejectLoan as rejectLoanRequest, rescheduleLoan, revertInstallmentPayment, setMonthInstallment,
} from './api';
import {
  monthLabel, overHalfSalaryWarning, postponeTarget, previewMonthAmount, previewPayment, sameDayNextMonth, splitLoansByCompletion,
  validateApproval,
} from './logic';
import type { ApprovalDraft, EditLoanDraft, LoansTab, MonthAmountDraft, PayDraft } from './types';
import { cutoffDateOf, payrollMonthOfDate } from '@/features/payroll/period';

export function useLoans() {
  const confirm = useConfirm();
  const askNote = useConfirmNote();
  const query = useQuery('loans', fetchLoans);
  const [tab, setTab] = useState<LoansTab>('active');
  const [search, setSearch] = useState('');
  const [busy, setBusy] = useState<string | null>(null);

  const [approval, setApproval] = useState<ApprovalDraft | null>(null);
  const [rejecting, setRejecting] = useState<Loan | null>(null);
  const [editDraft, setEditDraft] = useState<EditLoanDraft | null>(null);
  const [scheduleLoanId, setScheduleLoanId] = useState<string | null>(null);
  const [payPrompt, setPayPrompt] = useState<PayDraft | null>(null);
  const [monthPrompt, setMonthPrompt] = useState<MonthAmountDraft | null>(null);
  const [creating, setCreating] = useState(false);

  const approved = useMemo(() => query.data?.approved ?? [], [query.data]);
  const { incomplete: active, completed } = splitLoansByCompletion(approved);
  const outstanding = active.reduce((sum, l) => sum + Number(l.remaining_amount), 0);
  const scheduleLoan = approved.find((l) => l.id === scheduleLoanId) ?? null;
  const paymentPreview = useMemo(
    () => (payPrompt && scheduleLoan ? previewPayment(scheduleLoan, payPrompt.installment.id, payPrompt.amount) : null),
    [payPrompt, scheduleLoan],
  );
  const monthPreview = useMemo(
    () => (monthPrompt && scheduleLoan ? previewMonthAmount(scheduleLoan, monthPrompt.installment.id, monthPrompt.amount) : null),
    [monthPrompt, scheduleLoan],
  );
  const pending = query.data?.pending ?? [];

  const displayed = (tab === 'active' ? active : completed).filter((l) =>
    (l.employees?.full_name || '').toLowerCase().includes(search.trim().toLowerCase()),
  );

  const run = async (key: string, action: () => Promise<void>, failMsg: string) => {
    setBusy(key);
    try {
      await action();
    } catch (err) {
      toast.error(`${failMsg}: ${errorMessage(err)}`);
    } finally {
      setBusy(null);
    }
  };

  const startApproval = (loan: Loan) =>
    setApproval({
      loan,
      amount: Number(loan.amount),
      months: Number(loan.installment_count),
      startDate: cutoffDateOf(payrollMonthOfDate(sameDayNextMonth())),
    });

  // سبب الرفض يصل للموظف في إشعار قاعدة البيانات (trg_notify_employee_loan_decision)
  const rejectLoan = async (loan: Loan, reason: string) => {
    setRejecting(null);
    await run(
      loan.id,
      async () => {
        await rejectLoanRequest(loan.id, reason);
        query.mutate((d) => ({ ...d, pending: d.pending.filter((l) => l.id !== loan.id) }));
        toast.success('تم رفض طلب السلفة');
      },
      'فشل معالجة الطلب',
    );
  };

  const submitApproval = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!approval) return;
    const salary = Number((approval.loan as { employees?: { monthly_salary_iqd?: number | null } | null }).employees?.monthly_salary_iqd) || 0;
    const invalid = validateApproval(approval.amount, approval.months);
    if (invalid) {
      toast.error(invalid);
      return;
    }
    // قسط فوق نص الراتب مسموح (الباقي يتسدد نقداً) — تنبيه وتأكيد فقط
    const warning = overHalfSalaryWarning(approval.amount, approval.months, salary);
    if (warning && !(await confirm({ title: 'القسط أكثر من نص الراتب', message: warning, confirmLabel: 'اعتماد رغم ذلك', tone: 'warning' }))) return;
    await run(
      'approve',
      async () => {
        // اعتماد وتوليد الأقساط في معاملة واحدة على السيرفر (approve_loan)
        await approveLoan(approval);
        setApproval(null);
        query.reload();
        confetti({ particleCount: 100, spread: 70, colors: ['#818CF8', '#34D399', '#6EE7B7'] });
        toast.success('تم اعتماد السلفة وتوليد الأقساط');
      },
      'فشل الاعتماد',
    );
  };

  const submitEdit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editDraft) return;
    const d = editDraft;
    await run(
      'edit',
      async () => {
        await rescheduleLoan(d);
        setEditDraft(null);
        query.reload();
        toast.success('تم تعديل السلفة وإعادة جدولة الأقساط المتبقية');
      },
      'فشل التعديل',
    );
  };

  const recordPayment = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!payPrompt || !paymentPreview || paymentPreview.error) return;
    await run(
      'pay',
      async () => {
        await payInstallment(payPrompt.installment.id, payPrompt.amount, payPrompt.method, payPrompt.note);
        setPayPrompt(null);
        query.reload();
        toast.success('تم تسجيل الدفعة وإعادة توزيع الأقساط المتبقية');
      },
      'فشل تسجيل الدفعة',
    );
  };

  const recordMonthAmount = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!monthPrompt || !monthPreview || monthPreview.error) return;
    await run(
      'month',
      async () => {
        await setMonthInstallment(monthPrompt.installment.id, monthPrompt.amount, monthPrompt.note);
        setMonthPrompt(null);
        query.reload();
        toast.success('تم: هالشهر يتخصم المبلغ الجديد، والباقي صار شهر بالأخير');
      },
      'فشل تعديل قسط الشهر',
    );
  };

  const revertPayment = async (inst: LoanInstallment) => {
    const ok = await confirm({
      title: 'التراجع عن السداد؟',
      message: 'سيعود القسط غير مدفوع ويُضاف للمبلغ المتبقي ليُستقطع مع الراتب القادم.',
      confirmLabel: 'تراجع عن السداد',
      tone: 'warning',
    });
    if (!ok) return;
    await run(
      `revert_${inst.id}`,
      async () => {
        await revertInstallmentPayment(inst.id);
        query.reload();
        toast.success('تم التراجع عن السداد');
      },
      'فشل التراجع عن السداد',
    );
  };

  /** تأجيل قسط شهر واحد لآخر السلفة (بملاحظة تنحفظ وتوصل للموظف). */
  const postponeFrom = async (inst: LoanInstallment) => {
    const to = scheduleLoan ? postponeTarget(scheduleLoan, inst.id) : null;
    const note = await askNote({
      title: `تأجيل قسط شهر ${monthLabel(inst.due_date)}؟`,
      message: `القسط (${Number(inst.amount).toLocaleString('en-US')} د.ع) ينتقل لآخر السلفة${to ? ` (شهر ${monthLabel(to)})` : ''}، وباقي الأشهر ما تتغير. الموظف يوصله إشعار.`,
      confirmLabel: 'تأجيل',
      tone: 'warning',
      note: { presets: ['طلب الموظف تأجيل', 'ظرف طارئ'], placeholder: 'سبب التأجيل (اختياري)' },
    });
    if (note === null) return;
    await run(
      `postpone_${inst.id}`,
      async () => {
        await postponeInstallment(inst.id, note);
        query.reload();
        toast.success(`تم تأجيل قسط شهر ${monthLabel(inst.due_date)} لآخر السلفة`);
      },
      'فشل تأجيل القسط',
    );
  };

  /** حذف سلفة مسددة بالكامل مع ملف تعهدها لتوفير المساحة. */
  const deleteLoan = async (loan: Loan) => {
    const ok = await confirm({
      title: 'حذف سجل السلفة المكتملة؟',
      message: 'ستُحذف السلفة وأقساطها وصورة التعهد نهائياً لتوفير المساحة. لا يمكن التراجع.',
      confirmLabel: 'حذف نهائي',
    });
    if (!ok) return;
    await run(
      `delete_loan_${loan.id}`,
      async () => {
        await deleteCompletedLoan(loan);
        query.mutate((d) => ({ ...d, approved: d.approved.filter((l) => l.id !== loan.id) }));
        toast.success('تم حذف السلفة وتوفير المساحة');
      },
      'فشل الحذف',
    );
  };

  return {
    query, pending, active, completed, outstanding, displayed,
    tab, setTab, search, setSearch, busy,
    approval, setApproval, rejecting, setRejecting, editDraft, setEditDraft,
    scheduleLoan, setScheduleLoanId, payPrompt, setPayPrompt, paymentPreview, creating, setCreating,
    monthPrompt, setMonthPrompt, monthPreview, recordMonthAmount,
    startApproval, rejectLoan, submitApproval, submitEdit, recordPayment, revertPayment, postponeFrom, deleteLoan,
  };
}

export type LoansState = ReturnType<typeof useLoans>;
