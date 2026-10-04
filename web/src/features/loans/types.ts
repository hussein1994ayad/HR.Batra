// أنواع صفحة السلف.

import type { Loan, LoanInstallment } from '@/lib/db-types';

export type LoansTab = 'active' | 'completed';

/** مسودة الاعتماد: يمكن للإدارة تعديل المبلغ والمدة وتاريخ أول قسط قبل التوليد. */
export interface ApprovalDraft {
  loan: Loan;
  amount: number;
  months: number;
  startDate: string;
}

/** مسودة تعديل سلفة جارية وإعادة جدولة أقساطها غير المدفوعة. */
export interface EditLoanDraft {
  loan: Loan;
  amount: number;
  installmentAmount: number;
  installmentCount: number;
  remainingAmount: number;
}

export type InstallmentPrompt = { installmentId: string; amount: number };

/** قسط جديد قبل إدخاله (بدون loan_id). */
export interface ScheduledInstallment {
  due_date: string;
  amount: number;
}

export type PaymentMethod = 'cash' | 'salary_deduction';

/** مسودة تسجيل دفعة بأي مبلغ على قسط (الزيادة تُخصم من آخر الأقساط والنقص يُضاف لآخر قسط). */
export interface PayDraft {
  installment: LoanInstallment;
  amount: number;
  method: PaymentMethod;
  note: string;
}
