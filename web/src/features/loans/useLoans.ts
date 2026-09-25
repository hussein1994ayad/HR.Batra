'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import confetti from 'canvas-confetti';
import toast from 'react-hot-toast';
import type { Loan, LoanInstallment } from '@/lib/db-types';
import { errorMessage } from '@/lib/error-utils';
import {
  approveLoan, deleteCompletedLoan, deleteInstallment, fetchLoans, payInstallmentCash, postponeInstallments,
  rejectLoan, rescheduleLoan, revertInstallmentPayment, updateInstallmentAmount,
} from './api';
import { splitLoansByCompletion, validateApproval } from './logic';
import type { ApprovalDraft, EditLoanDraft } from './types';

/** حالة صفحة السلف: الطلبات المعلقة، السلف المعتمدة، وكل إجراءات الأقساط. */
export function useLoans() {
  const [loading, setLoading] = useState(true);
  const [loanRequests, setLoanRequests] = useState<Loan[]>([]);
  const [activeLoans, setActiveLoans] = useState<Loan[]>([]);
  // مفتاح الإجراء الجاري (معرّف السلفة أو اسم الإجراء) لتعطيل الأزرار
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const loadLoans = useCallback(async () => {
    try {
      const { pending, approved } = await fetchLoans();
      setLoanRequests(pending);
      setActiveLoans(approved);
    } catch (err) {
      console.error(err);
      toast.error(`تعذر تحميل السلف: ${errorMessage(err)}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- التحميل الأول للصفحة
    void loadLoans();
  }, [loadLoans]);

  const { incomplete: incompleteLoans, completed: completedLoans } = useMemo(
    () => splitLoansByCompletion(activeLoans), [activeLoans]);

  /** ينفذ إجراءً مع تعطيل الأزرار ثم يعيد التحميل. يرجع true عند النجاح. */
  const run = async (key: string, action: () => Promise<void>, success: string, failure: string) => {
    setActionLoading(key);
    try {
      await action();
      toast.success(success);
      await loadLoans();
      return true;
    } catch (err: unknown) {
      toast.error(`${failure}: ${errorMessage(err)}`);
      return false;
    } finally {
      setActionLoading(null);
    }
  };

  /** لا تُعتمد سلفة ثانية لموظف لديه سلفة جارية. */
  const canApprove = (loan: Loan) => {
    const hasActive = incompleteLoans.some(l => l.employee_id === loan.employee_id);
    if (hasActive) toast.error('لا يمكن الموافقة: الموظف لديه سلفة نشطة حالياً. يرجى إغلاقها أولاً.');
    return !hasActive;
  };

  const approve = (draft: ApprovalDraft) => {
    const invalid = validateApproval(draft.amount, draft.months, draft.loan.employees?.monthly_salary_iqd || 0);
    if (invalid) {
      toast.error(invalid);
      return Promise.resolve(false);
    }
    return run(draft.loan.id, async () => {
      await approveLoan(draft);
      void confetti({ particleCount: 100, spread: 70, colors: ['#0D9488', '#34D399', '#6EE7B7'] });
    }, 'تم اعتماد السلفة وتوليد الأقساط بذكاء! ✅', 'فشل الاعتماد');
  };

  const reject = (loan: Loan) => {
    const reason = prompt('يرجى إدخال سبب الرفض (اختياري):');
    if (reason === null) return;
    return run(loan.id, () => rejectLoan(loan.id, reason), 'تم رفض طلب السلفة بنجاح. ❌', 'فشل إتمام معالجة الطلب');
  };

  const reschedule = (draft: EditLoanDraft) =>
    run('edit_' + draft.loan.id, () => rescheduleLoan(draft),
      'تم تعديل السلفة وإعادة جدولة الأقساط المتبقية بنجاح! ✅', 'فشل التعديل');

  const payCash = (installmentId: string, note: string) =>
    run('cash_' + installmentId, () => payInstallmentCash(installmentId, note),
      'تم تسجيل السداد النقدي وتحديث الرصيد المتبقي بنجاح! 💵', 'فشل تسجيل السداد');

  const revertPayment = (installmentId: string) => {
    if (!confirm('هل تريد إلغاء حالة السداد لهذا القسط وإعادته لغير مدفوع؟ سيتم إعادة إضافة القسط للمبلغ المتبقي ويستقطع مع الراتب القادم.')) return;
    return run('revert_' + installmentId, () => revertInstallmentPayment(installmentId),
      'تم التراجع عن السداد بنجاح! 🔄', 'فشل التراجع عن السداد');
  };

  const deletePaidInstallment = (installmentId: string) => {
    if (!confirm('هل أنت متأكد من حذف هذا القسط المسدد نهائياً من قاعدة البيانات لتوفير المساحة؟ هذا الإجراء غير قابل للتراجع ولن يؤثر على رصيد السلفة المتبقي.')) return;
    return run('delete_inst_' + installmentId, () => deleteInstallment(installmentId),
      'تم حذف القسط المسدد نهائياً من قاعدة البيانات! 🗑️', 'فشل حذف القسط');
  };

  const changeInstallmentAmount = (installmentId: string, amount: number) => {
    if (amount <= 0) return Promise.resolve(false);
    return run('update_amt_' + installmentId, () => updateInstallmentAmount(installmentId, amount),
      'تم تعديل قيمة القسط وتحديث الرصيد المتبقي بنجاح! ✏️', 'فشل تعديل القسط');
  };

  const postpone = (installment: LoanInstallment) =>
    run('postpone_' + installment.id, () => postponeInstallments(installment),
      'تم تأجيل القسط والأقساط اللاحقة شهراً إضافياً بنجاح! 🔄', 'فشل تأجيل القسط');

  const deleteLoan = (loan: Loan) => {
    if (Number(loan.remaining_amount) > 0) {
      toast.error('لا يمكن حذف سلفة غير مكتملة السداد.');
      return;
    }
    if (!confirm('تحذير: هل أنت متأكد من مسح هذه السلفة المكتملة بشكل نهائي من قاعدة البيانات لتوفير المساحة؟ سيتم حذف جميع تفاصيلها وأقساطها. هذا الإجراء لا يمكن التراجع عنه.')) return;
    return run('delete_loan_' + loan.id, () => deleteCompletedLoan(loan),
      'تم حذف السلفة وتوفير مساحة التخزين بنجاح! 🗑️', 'فشل الحذف');
  };

  return {
    loading, loanRequests, activeLoans, incompleteLoans, completedLoans, actionLoading,
    canApprove, approve, reject, reschedule,
    payCash, revertPayment, deletePaidInstallment, changeInstallmentAmount, postpone, deleteLoan,
  };
}
