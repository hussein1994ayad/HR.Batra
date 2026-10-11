import { describe, expect, it } from 'vitest';
import type { Loan } from '@/lib/db-types';
import { loanStatementFileName, loanStatementRows } from './statementExport';

const loan = {
  id: 'l1', employee_id: 'e1', amount: 300000, installment_amount: 100000, installment_count: 3, remaining_amount: 0,
  pledge_url: 'x', status: 'approved', approved_at: '2026-09-05T10:00:00Z', employees: { full_name: 'زينب علي' },
  loan_installments: [
    { id: 'i2', loan_id: 'l1', due_date: '2026-10-10', amount: 100000, is_paid: true, paid_at: '2026-10-28T09:00:00Z', payment_type: 'cash', payment_note: 'دفع بالمكتب' },
    { id: 'i1', loan_id: 'l1', due_date: '2026-09-10', amount: 100000, is_paid: true, paid_at: '2026-09-27T09:00:00Z', paid_by_slip_id: 's1' },
    { id: 'i3', loan_id: 'l1', due_date: '2026-11-10', amount: 100000, is_paid: true, paid_at: '2026-11-27T09:00:00Z', paid_by_slip_id: 's3', origin_kind: 'postponed', origin_month: '2026-10-01' },
  ],
} as unknown as Loan;

describe('loan statement kept before deleting a repaid loan', () => {
  it('summarises the loan and lists every installment in order with how it was paid', () => {
    const { summary, installments } = loanStatementRows(loan);
    expect(summary.find((r) => r['البند'] === 'المسدد (د.ع)')?.['القيمة']).toBe(300000);
    expect(summary.find((r) => r['البند'] === 'الباقي (د.ع)')?.['القيمة']).toBe(0);
    expect(installments.map((r) => r['تاريخ الاستحقاق'])).toEqual(['2026-09-10', '2026-10-10', '2026-11-10']);
    expect(installments.map((r) => r['طريقة السداد'])).toEqual(['خصم من الراتب', 'نقداً', 'خصم من الراتب']);
    expect(installments[0]['يستقطع من']).toBe('رواتب الشهر التاسع 2026');
    expect(installments[1]['ملاحظة']).toBe('دفع بالمكتب');
    expect(installments[2]['ملاحظة']).toBe('مؤجّل من الشهر العاشر 2026');
  });

  it('names the file after the employee and the approval date', () => {
    expect(loanStatementFileName(loan)).toBe('كشف_سلفة_زينب_علي_2026-09-05.xlsx');
  });
});
