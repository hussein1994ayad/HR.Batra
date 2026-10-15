import { describe, expect, it } from 'vitest';
import type { Employee } from '@/lib/db-types';
import { daysUntil, documentPathFromUrl, endOfServiceBlocks, employeeToFormValues, salaryChangeMonth, salaryUpdateFields, filterEmployees, normalizeArabic, documentList } from './logic';

const emp = (over: Partial<Employee>): Employee => ({
  id: 'e', employee_code: 'EMP-100', full_name: '', is_active: true, role: 'employee', ...over,
});

describe('normalizeArabic', () => {
  it('unifies hamza, taa marbuta, alef maqsura and strips diacritics', () => {
    expect(normalizeArabic('  أحمد إبراهيم ')).toBe('احمد ابراهيم');
    expect(normalizeArabic('فاطمة')).toBe('فاطمه');
    expect(normalizeArabic('مُصْطَفى')).toBe('مصطفي');
  });
});

describe('filterEmployees', () => {
  const employees = [
    emp({ id: '1', full_name: 'أحمد علي', branch_id: 'b1', department_id: 'd1', email: 'Ahmed@X.com' }),
    emp({ id: '2', full_name: 'فاطمة حسن', branch_id: 'b2', phone: '07701234567', employee_code: 'EMP-777' }),
  ];
  const base = {
    employees,
    departments: [{ id: 'd1', name: 'المحاسبة' }],
    branches: [{ id: 'b1', name: 'الكرادة' }, { id: 'b2', name: 'المنصور' }],
    branchId: 'all',
  };
  const ids = (searchTerm: string, branchId = 'all') =>
    filterEmployees({ ...base, searchTerm, branchId }).map(e => e.id);

  it('matches name regardless of hamza/taa spelling', () => {
    expect(ids('احمد')).toEqual(['1']);
    expect(ids('فاطمه')).toEqual(['2']);
  });

  it('matches email, phone, code, department and branch', () => {
    expect(ids('ahmed@')).toEqual(['1']);
    expect(ids('0770')).toEqual(['2']);
    expect(ids('emp-777')).toEqual(['2']);
    expect(ids('محاسبه')).toEqual(['1']);
    expect(ids('المنصور')).toEqual(['2']);
  });

  it('applies the branch filter with and without a search term', () => {
    expect(ids('', 'b2')).toEqual(['2']);
    expect(ids('احمد', 'b2')).toEqual([]);
  });
});

describe('employeeToFormValues', () => {
  it('leaves a missing join date empty (not the date the employee was added)', () => {
    const values = employeeToFormValues(emp({ full_name: 'x', created_at: '2026-03-10T08:00:00Z', monthly_salary_iqd: null }));
    expect(values.joinDate).toBe('');
    expect(employeeToFormValues(emp({ full_name: 'y', join_date: '2025-01-05' })).joinDate).toBe('2025-01-05');
    expect(values.monthlySalary).toBe(0);
    expect(values.email).toBe('');
  });
});

describe('salary change month', () => {
  it('reads the scheduled month from any saved format', () => {
    expect(salaryChangeMonth('2026/06/01')).toBe('2026-06');
    expect(salaryChangeMonth('2026-10-27')).toBe('2026-11');
    expect(salaryChangeMonth('2026-11')).toBe('2026-11');
    expect(salaryChangeMonth('2026-1')).toBe('2026-01');
    expect(salaryChangeMonth(null)).toBe('');
    expect(employeeToFormValues(emp({ full_name: 'z', future_salary_month: '2026/06/01', future_salary_iqd: 800000 })).futureSalaryMonth).toBe('2026-06');
  });

  it('changes the salary now for this month and schedules it for a later month', () => {
    const base = { monthlySalary: 600000, futureSalary: 800000 };
    expect(salaryUpdateFields({ ...base, futureSalaryMonth: '2026-10' }, '2026-10'))
      .toEqual({ monthly_salary_iqd: 800000, future_salary_iqd: null, future_salary_month: null });
    expect(salaryUpdateFields({ ...base, futureSalaryMonth: '2026-11' }, '2026-10'))
      .toEqual({ monthly_salary_iqd: 600000, future_salary_iqd: 800000, future_salary_month: '2026-11' });
    expect(salaryUpdateFields({ ...base, futureSalary: 0, futureSalaryMonth: '2026-11' }, '2026-10'))
      .toEqual({ monthly_salary_iqd: 600000, future_salary_iqd: null, future_salary_month: null });
  });
});

describe('documentPathFromUrl', () => {
  it('extracts the storage path from a public URL', () => {
    expect(documentPathFromUrl('https://x.supabase.co/storage/v1/object/public/employee-documents/e1/a.jpg')).toBe('e1/a.jpg');
    expect(documentPathFromUrl('https://example.com/a.jpg')).toBeNull();
  });
});

describe('daysUntil', () => {
  it('rounds up partial days', () => {
    expect(daysUntil('2026-10-01T12:00:00Z', new Date('2026-09-25T00:00:00Z'))).toBe(7);
  });
});

describe('documentList', () => {
  it('always gives a list, whatever the database stored', () => {
    expect(documentList(['a', 'b'])).toEqual(['a', 'b']);
    expect(documentList({})).toEqual([]);
    expect(documentList(null)).toEqual([]);
    expect(documentList(undefined)).toEqual([]);
    expect(documentList(['a', 3, null])).toEqual(['a']);
  });
});

describe('end of service preview (stage 3)', () => {
  const preview = {
    last_day: '2026-10-28',
    total_net: 853333,
    loans_left_after: 0,
    periods: [
      { month: '2026-10', start_date: '2026-10-01', cutoff_date: '2026-10-26', can_approve_now: false, expected_net: 800000, loan_cut: 0, excess_deductions: 0,
        summary: { basic: 800000, basic_note: 'راتب المسير كامل: 800,000 د.ع', earnings: 0, deductions: 0, loans: 0, net: 800000 } },
      { month: '2026-11', start_date: '2026-10-27', cutoff_date: '2026-11-26', can_approve_now: false, expected_net: 0, loan_cut: 50000, excess_deductions: 20000,
        summary: { basic: 53333, basic_note: 'نهاية خدمة: 2 يوم دوام', earnings: 0, deductions: 73333, loans: 50000, net: -70000, pending_count: 1 } },
    ],
  };
  it('explains every period in plain words', () => {
    const [oct, nov] = endOfServiceBlocks(preview);
    expect(oct.title).toContain('الشهر العاشر 2026');
    expect(oct.lines[0]).toBe('راتب المسير كامل: 800,000 د.ع');
    expect(oct.net).toBe('800,000 د.ع');
    expect(nov.lines).toContain('نهاية خدمة: 2 يوم دوام');
    expect(nov.lines.some((l) => l.includes('ينخصم منه 0 د.ع بس'))).toBe(true);
    expect(nov.lines.some((l) => l.includes('خارج النظام'))).toBe(true);
    expect(nov.lines.some((l) => l.includes('تنتظر قرارك'))).toBe(true);
    // آخر يوم 28 بعد يوم القطع 26: المسير الأول ينعتمد بعد نهايته، والثاني بعد آخر يوم
    expect(oct.when).toContain('26/10');
    expect(nov.when).toContain('28/10');
  });
});
