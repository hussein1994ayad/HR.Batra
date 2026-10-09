import { describe, expect, it } from 'vitest';
import type { Employee } from '@/lib/db-types';
import { daysUntil, documentPathFromUrl, employeeToFormValues, salaryChangeMonth, salaryUpdateFields, filterEmployees, normalizeArabic } from './logic';

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
