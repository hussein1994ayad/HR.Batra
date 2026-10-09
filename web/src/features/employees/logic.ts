// =========================================================================
// منطق صفحة الموظفين — دوال نقية بدون React أو Supabase
// =========================================================================

import type { Department, Employee } from '@/lib/db-types';
import { getLocalDateStr } from '@/lib/dates';
import { payrollMonthOfDate } from '@/features/payroll/period';
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
  departmentId: '',
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
    password: '', // فارغة = بدون تغيير (كلمات السر لا تُحفظ مقروءة)
    role: emp.role,
    branchId: emp.branch_id || '',
    departmentId: emp.department_id || '',
    monthlySalary: emp.monthly_salary_iqd || 0,
    futureSalary: emp.future_salary_iqd || 0,
    futureSalaryMonth: salaryChangeMonth(emp.future_salary_month),
    // بدون تاريخ مباشرة: يبقى فارغاً حتى يُدخله الأدمن (كان يُحفظ تاريخ إضافته للنظام فيُنقص راتبه)
    joinDate: emp.join_date || '',
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

/** شهر الرواتب لتغيير الراتب المجدول من القيمة المحفوظة بأي صيغة قديمة: 2026-06 / 2026-06-15 / 2026/06/01 → "2026-06". */
export function salaryChangeMonth(value: string | null | undefined): string {
  const v = (value ?? '').trim().replace(/\//g, '-');
  const p2 = (x: string) => x.padStart(2, '0');
  const full = v.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (full) return payrollMonthOfDate(`${full[1]}-${p2(full[2])}-${p2(full[3])}`);
  const month = v.match(/^(\d{4})-(\d{1,2})$/);
  if (month) return `${month[1]}-${p2(month[2])}`;
  return '';
}

/**
 * حقول الراتب عند الحفظ: الراتب الجديد من رواتب هذا الشهر (أو شهر فات) = يتغير الراتب نفسه هسه؛
 * من شهر جاي = يبقى مجدول بشهره ويتطبق وحده لما يجي شهره. بدون راتب جديد = يلغي التغيير المجدول.
 */
export function salaryUpdateFields(values: Pick<EmployeeFormValues, 'monthlySalary' | 'futureSalary' | 'futureSalaryMonth'>, currentMonth: string) {
  const month = values.futureSalaryMonth;
  if (values.futureSalary > 0 && month && month <= currentMonth) {
    return { monthly_salary_iqd: values.futureSalary, future_salary_iqd: null, future_salary_month: null };
  }
  const scheduled = values.futureSalary > 0 && !!month;
  return {
    monthly_salary_iqd: values.monthlySalary || 0,
    future_salary_iqd: scheduled ? values.futureSalary : null,
    future_salary_month: scheduled ? month : null,
  };
}
