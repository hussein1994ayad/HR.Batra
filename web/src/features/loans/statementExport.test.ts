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

import type { SettledLoan } from '@/lib/db-types';
import { settledLoanRows } from './statementExport';
import { cleanupReportSheets } from '@/features/settings/cleanupReport';
import { loanRef } from './logic';

describe('settled loan record', () => {
  const settled: SettledLoan = {
    id: 's1', loan_id: 'l1', loan_no: 7, employee_id: 'e1', employee_name: 'زينب علي', employee_code: 'E-002',
    amount: 300000, total_deducted: 300000, final_balance: 0, approved_at: '2026-09-05T10:00:00Z',
    settled_at: '2026-11-27T09:00:00Z', archived_at: '2026-12-01T09:00:00Z',
    installments: [
      { due_date: '2026-09-10', amount: 100000, paid_at: '2026-09-27T09:00:00Z', method: 'salary', payroll_month: '2026-09', slip_id: 's1' },
      { due_date: '2026-10-10', amount: 100000, paid_at: '2026-10-28T09:00:00Z', method: 'cash', payroll_month: '2026-10', slip_id: null, note: 'دفع بالمكتب' },
      { due_date: '2026-11-10', amount: 100000, paid_at: '2026-11-27T09:00:00Z', method: 'salary', payroll_month: '2026-11', slip_id: 's3' },
    ],
  };

  it('formats the reference number', () => {
    expect(loanRef(7)).toBe('L-0007');
    expect(loanRef(12345)).toBe('L-12345');
    expect(loanRef(undefined)).toBe('');
  });

  it('exports the permanent record: reference, totals, zero balance, and each deduction with its payroll month', () => {
    const { summary, installments } = settledLoanRows(settled);
    const value = (k: string) => summary.find((r) => r['البند'] === k)?.['القيمة'];
    expect(value('رقم السلفة')).toBe('L-0007');
    expect(value('مجموع المستقطع (د.ع)')).toBe(300000);
    expect(value('الرصيد النهائي (د.ع)')).toBe(0);
    expect(value('تاريخ التسوية')).toBe('2026-11-27');
    expect(installments.map((r) => r['رواتب'])).toEqual(['الشهر التاسع 2026', 'الشهر العاشر 2026', 'الشهر الحادي عشر 2026']);
    expect(installments.map((r) => r['طريقة السداد'])).toEqual(['خصم من الراتب', 'نقداً', 'خصم من الراتب']);
  });

  it('the cleanup preview report lists candidates and the excluded with their reasons', () => {
    const sheets = cleanupReportSheets(null, {
      settled: [{ id: 'l1', loan_no: 7, employee: 'زينب علي', amount: 300000, settled_at: '2026-11-27T09:00:00Z' }],
      excluded: [{ loan_no: 8, employee: 'مصطفى حسن', amount: 500000, remaining: 200000, reason: 'عليها باقي 200,000 د.ع.' }],
      requests: [], requests_recent: 0, bytes: { settled_rows: 1, settled_files: 1, requests_rows: 0, requests_files: 0 }, archived_total: 0,
    });
    expect(sheets.map((s) => s.name)).toEqual(['سلف تتأرشف', 'سلف مستثناة', 'طلبات مرفوضة قديمة']);
    expect(sheets[0].rows[0]).toMatchObject({ 'رقم السلفة': 'L-0007', 'الموظف': 'زينب علي' });
    expect(sheets[1].rows[0]).toMatchObject({ 'رقم السلفة': 'L-0008', 'السبب': 'عليها باقي 200,000 د.ع.' });
  });
});
