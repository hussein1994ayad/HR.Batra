// استعلامات Supabase الخاصة بصفحة السلف. كل دالة ترمي عند الخطأ.
// إشعار الموظف بقرار الاعتماد/الرفض يُرسل من قاعدة البيانات: trg_notify_employee_loan_decision
// والمبلغ المتبقي يُعاد حسابه تلقائياً بعد تعديل/حذف الأقساط: trg_update_loan_and_installments

import { supabase } from '@/lib/supabase';
import type { Loan, LoanInstallment } from '@/lib/db-types';
import { addMonths } from './logic';
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

/**
 * يعدّل السلفة ويعيد جدولة الأقساط غير المدفوعة من الشهر القادم (reschedule_loan).
 * كله على السيرفر في معاملة واحدة: كان الحذف يولّد أقساطاً تلقائياً ثم يُضاف الجدول
 * الجديد فوقها فتتضاعف الأقساط. المتبقي = المبلغ − المسدَّد، والسيرفر يُشعر الموظف.
 */
export async function rescheduleLoan(draft: EditLoanDraft) {
  const { error } = await supabase.rpc('reschedule_loan', {
    p_loan_id: draft.loan.id,
    p_amount: Math.round(draft.amount),
    p_installment_amount: Math.round(draft.installmentAmount),
    p_count: Number(draft.installmentCount),
  });
  if (error) throw error;
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

/** الموظفون النشطون لاختيار صاحب السلفة (مع الراتب لفحص شرط 50%). */
export async function fetchLoanEmployees(): Promise<{ id: string; full_name: string; monthly_salary_iqd: number | null }[]> {
  const { data, error } = await supabase
    .from('employees')
    .select('id, full_name, monthly_salary_iqd')
    .eq('is_active', true)
    .order('full_name');
  if (error) throw error;
  return data ?? [];
}

/**
 * سلفة معتمدة مباشرة لموظف (مثل زر "سلفة لموظف" بالتطبيق): يرفع صورة التعهد ثم
 * create_direct_loan يولّد الأقساط ويبلغ الموظف بمعاملة وحدة.
 */
export async function createDirectLoan(entry: {
  employeeId: string;
  amount: number;
  months: number;
  firstDue: string;
  pledge: File;
  notes: string;
}): Promise<void> {
  const ext = (entry.pledge.name.split('.').pop() || 'jpg').toLowerCase();
  const path = `pledges/${entry.employeeId}/${crypto.randomUUID()}.${ext}`;
  const { error: upErr } = await supabase.storage.from('loan-pledges').upload(path, entry.pledge);
  if (upErr) throw upErr;
  const pledgeUrl = supabase.storage.from('loan-pledges').getPublicUrl(path).data.publicUrl;
  const { error } = await supabase.rpc('create_direct_loan', {
    p_employee_id: entry.employeeId,
    p_amount: entry.amount,
    p_months: entry.months,
    p_first_due: entry.firstDue,
    p_pledge_url: pledgeUrl,
    p_notes: entry.notes.trim() || null,
  });
  if (error) {
    // السلفة ما انعملت: نشيل الصورة الي انرفعت حتى ما تبقى يتيمة
    await supabase.storage.from('loan-pledges').remove([path]);
    throw error;
  }
}
