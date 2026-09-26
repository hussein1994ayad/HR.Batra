// استعلامات Supabase الخاصة بصفحة السلف. كل دالة ترمي عند الخطأ.
// إشعار الموظف بقرار الاعتماد/الرفض يُرسل من قاعدة البيانات: trg_notify_employee_loan_decision
// والمبلغ المتبقي يُعاد حسابه تلقائياً بعد تعديل/حذف الأقساط: trg_update_loan_and_installments

import { supabase } from '@/lib/supabase';
import type { Loan, LoanInstallment } from '@/lib/db-types';
import { addMonths, buildInstallmentSchedule, firstOfNextMonth } from './logic';
import type { ApprovalDraft, EditLoanDraft, PaymentMethod } from './types';

const EMPLOYEE_JOIN = 'employees!loans_employee_id_fkey(full_name, monthly_salary_iqd)';

export async function fetchLoans(): Promise<{ pending: Loan[]; approved: Loan[] }> {
  const [pending, approved] = await Promise.all([
    supabase.from('loans').select(`*, ${EMPLOYEE_JOIN}`).eq('status', 'pending').order('created_at', { ascending: false }),
    supabase.from('loans').select(`*, ${EMPLOYEE_JOIN}, loan_installments(*)`).eq('status', 'approved').order('created_at', { ascending: false }),
  ]);
  if (pending.error) throw pending.error;
  if (approved.error) throw approved.error;
  return { pending: pending.data ?? [], approved: approved.data ?? [] };
}

async function currentAdminId(): Promise<string> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) throw new Error('انتهت الجلسة، يرجى تسجيل الدخول مجدداً.');
  return session.user.id;
}

export async function rejectLoan(loanId: string, reason: string) {
  const { error } = await supabase
    .from('loans')
    .update({
      status: 'rejected',
      approved_by: await currentAdminId(),
      approved_at: new Date().toISOString(),
      rejection_reason: reason.trim() || null,
    })
    .eq('id', loanId);
  if (error) throw error;
}

/**
 * يعتمد السلفة بالمبلغ والمدة المعدّلة ويولّد أقساطها في معاملة واحدة (approve_loan).
 * نفس قواعد buildInstallmentSchedule، ويتحقق السيرفر من السلفة الجارية وحد 50% من الراتب.
 */
export async function approveLoan(draft: ApprovalDraft) {
  const { error } = await supabase.rpc('approve_loan', {
    p_loan_id: draft.loan.id,
    p_amount: draft.amount,
    p_months: draft.months,
    p_first_due: draft.startDate,
  });
  if (error) throw error;
}

/** يعدّل السلفة ويعيد توليد الأقساط غير المدفوعة ابتداءً من الشهر القادم، ثم يُشعر الموظف. */
export async function rescheduleLoan(draft: EditLoanDraft) {
  const loanId = draft.loan.id;
  const amount = Math.round(draft.amount);
  const installmentAmount = Math.round(draft.installmentAmount);
  const remaining = Math.round(draft.remainingAmount);
  const count = Number(draft.installmentCount);

  const { error: updErr } = await supabase
    .from('loans')
    .update({ amount, installment_amount: installmentAmount, installment_count: count, remaining_amount: remaining })
    .eq('id', loanId);
  if (updErr) throw updErr;

  const { count: paidCount, error: paidErr } = await supabase
    .from('loan_installments')
    .select('id', { count: 'exact', head: true })
    .eq('loan_id', loanId)
    .eq('is_paid', true);
  if (paidErr) throw paidErr;

  const { error: delErr } = await supabase.from('loan_installments').delete().eq('loan_id', loanId).eq('is_paid', false);
  if (delErr) throw delErr;

  const remainingCount = count - (paidCount ?? 0);
  if (remainingCount > 0) {
    const schedule = buildInstallmentSchedule(remaining, remainingCount, firstOfNextMonth());
    const { error } = await supabase
      .from('loan_installments')
      .insert(schedule.map(s => ({ ...s, loan_id: loanId, is_paid: false })));
    if (error) throw error;
  }

  await supabase.from('notifications').insert({
    employee_id: draft.loan.employee_id,
    title: 'تعديل تفاصيل السلفة 💸',
    body: `قامت الإدارة بتعديل تفاصيل سلفة العمل الخاصة بك (المبلغ الكلي الجديد: ${amount.toLocaleString()} د.ع، القسط الشهري الجديد: ${installmentAmount.toLocaleString()} د.ع).`,
    type: 'loan',
  });
}

// ------------------------------------------------------------------
// الأقساط
// ------------------------------------------------------------------

/**
 * يسجّل سداد قسط بأي مبلغ (pay_loan_installment): الزيادة تُخصم من آخر الأقساط،
 * والنقص يُضاف لآخر قسط (أو لشهر جديد إن كان هذا آخرها)، ويُشعَر الموظف.
 */
export async function payInstallment(installmentId: string, amount: number, method: PaymentMethod, note: string) {
  const { error } = await supabase.rpc('pay_loan_installment', {
    p_installment_id: installmentId,
    p_amount: Math.round(amount),
    p_method: method,
    p_note: note.trim() || null,
  });
  if (error) throw error;
}

export async function revertInstallmentPayment(installmentId: string) {
  const { error } = await supabase
    .from('loan_installments')
    .update({ is_paid: false, paid_at: null, payment_type: 'salary_deduction', payment_note: null })
    .eq('id', installmentId);
  if (error) throw error;
}

export async function deleteInstallment(installmentId: string) {
  const { error } = await supabase.from('loan_installments').delete().eq('id', installmentId);
  if (error) throw error;
}

/** يؤجل هذا القسط وكل الأقساط غير المدفوعة بعده شهراً واحداً. */
export async function postponeInstallments(installment: LoanInstallment) {
  const { data, error } = await supabase
    .from('loan_installments')
    .select('id, due_date')
    .eq('loan_id', installment.loan_id)
    .eq('is_paid', false)
    .gte('due_date', installment.due_date)
    .order('due_date', { ascending: false }); // من الأبعد للأقرب حتى لا يتصادم تاريخان مؤقتاً
  if (error) throw error;

  for (const inst of data ?? []) {
    const { error: updErr } = await supabase
      .from('loan_installments')
      .update({ due_date: addMonths(inst.due_date, 1) })
      .eq('id', inst.id);
    if (updErr) throw updErr;
  }
}

/** حذف سلفة مكتملة مع ملف التعهد المرفق بها. */
export async function deleteCompletedLoan(loan: Loan) {
  const pledgePath = loan.pledge_url?.match(/\/loan-pledges\/(.+)$/)?.[1];
  if (pledgePath) {
    const { error } = await supabase.storage.from('loan-pledges').remove([pledgePath]);
    if (error) console.error('Failed to delete pledge file', error);
  }
  const { error } = await supabase.from('loans').delete().eq('id', loan.id);
  if (error) throw error;
}
