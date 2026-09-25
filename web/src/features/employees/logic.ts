// =========================================================================
// منطق صفحة الموظفين — دوال نقية بدون React أو Supabase
// =========================================================================

import type { Department, Employee } from '@/lib/db-types';
import { getLocalDateStr } from '@/lib/dates';
import type { BranchOption, EmployeeFormValues } from './types';

/** توحيد الهمزات والتاء المربوطة والياء وحذف التشكيل حتى يطابق البحث كل الكتابات. */
export function normalizeArabic(text: string = ''): string {
  return text
    .replace(/[أإآٱ]/g, 'ا')
    .replace(/ة/g, 'ه')
    .replace(/ى/g, 'ي')
    .replace(/ئ/g, 'ي')
    .replace(/ؤ/g, 'و')
    .replace(/[ً-ٟ]/g, '')
    .trim()
    .toLowerCase();
}

/** بحث الدليل: الاسم، البريد، الهاتف، الكود، القسم، أو الفرع — مع فلتر الفرع. */
export function filterEmployees(input: {
  employees: Employee[];
  departments: Department[];
  branches: BranchOption[];
  searchTerm: string;
  branchId: string;
}): Employee[] {
  const { employees, departments, branches, searchTerm, branchId } = input;
  const normSearch = normalizeArabic(searchTerm);

  return employees.filter(emp => {
    const matchesBranch = branchId === 'all' || emp.branch_id === branchId;
    if (!normSearch) return matchesBranch;

    const deptName = departments.find(d => d.id === emp.department_id)?.name;
    const branchName = branches.find(b => b.id === emp.branch_id)?.name || emp.branches?.name || '';
    const fields = [
      normalizeArabic(emp.full_name || ''),
      (emp.email || '').toLowerCase(),
      (emp.phone_number || emp.phone || '').toLowerCase(),
      (emp.employee_code || '').toLowerCase(),
      normalizeArabic(deptName || ''),
      normalizeArabic(branchName),
    ];
    return matchesBranch && fields.some(f => f.includes(normSearch));
  });
}

export const emptyEmployeeForm = (): EmployeeFormValues => ({
  fullName: '',
  email: '',
  phone: '',
  password: '',
  role: 'employee',
  branchId: '',
  monthlySalary: 0,
  futureSalary: 0,
  futureSalaryMonth: '',
  joinDate: getLocalDateStr(),
});

/** قيم نموذج التعديل من سجل الموظف (تاريخ المباشرة يرجع لتاريخ الإنشاء ثم اليوم). */
export function employeeToFormValues(emp: Employee): EmployeeFormValues {
  return {
    fullName: emp.full_name,
    email: emp.email ?? '',
    phone: emp.phone || '',
    password: emp.plain_password || '',
    role: emp.role,
    branchId: emp.branch_id || '',
    monthlySalary: emp.monthly_salary_iqd || 0,
    futureSalary: emp.future_salary_iqd || 0,
    futureSalaryMonth: emp.future_salary_month || '',
    joinDate: emp.join_date || getLocalDateStr(emp.created_at ? new Date(emp.created_at) : new Date()),
  };
}

/** مسار الملف داخل bucket الوثائق من رابطه العام، أو null إن لم يكن منه. */
export function documentPathFromUrl(url: string): string | null {
  return url.match(/\/employee-documents\/(.+)$/)?.[1] ?? null;
}

/** الأيام المتبقية حتى الحذف المجدول (تقريب للأعلى). */
export function daysUntil(dateIso: string, now: Date = new Date()): number {
  return Math.ceil((new Date(dateIso).getTime() - now.getTime()) / (1000 * 3600 * 24));
}
