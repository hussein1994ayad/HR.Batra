// =========================================================================
// منطق صفحة الموظفين — دوال نقية بدون React أو Supabase
// =========================================================================

import type { Department, Employee } from '@/lib/db-types';
import { getLocalDateStr } from '@/lib/dates';
import { payrollMonthOfDate } from '@/features/payroll/period';
import { formatIQD } from '@/lib/format';
import { arabicDate } from '@/lib/dates';
import { payrollMonthName } from '@/features/payroll/period';
import type { BranchOption, EmployeeFormValues, EndOfServicePreview } from './types';

/** مسير بمعاينة «إنهاء خدمات» بأسطر بسيطة: شلون انحسب، الخصومات، السلفة، والصافي. */
export interface EndOfServiceBlock {
  title: string;
  lines: string[];
  net: string;
  when: string;
}

export function endOfServiceBlocks(preview: EndOfServicePreview): EndOfServiceBlock[] {
  return preview.periods.map((p) => {
    const s = p.summary;
    const lines: string[] = [];
    lines.push(s.basic_note || `الأساسي ${formatIQD(s.basic)}`);
    if (Number(s.earnings) > 0) lines.push(`مكافآت وإضافي: +${formatIQD(s.earnings)}`);
    if (Number(s.deductions) > 0) lines.push(`خصومات قررتها الإدارة (غياب/تأخير/إجازة بدون راتب): -${formatIQD(s.deductions)}`);
    if (Number(s.loans) > 0) {
      lines.push(Number(p.loan_cut) > 0
        ? `قسط سلفة ${formatIQD(s.loans)}: ينخصم منه ${formatIQD(Number(s.loans) - Number(p.loan_cut))} بس (الراتب ما يكفي)`
        : `قسط سلفة: -${formatIQD(s.loans)}`);
    }
    if (Number(p.excess_deductions) > 0) {
      lines.push(`خصومات أكثر من الراتب بـ ${formatIQD(p.excess_deductions)}: ما تنخصم وتتسوى ويا الموظف خارج النظام`);
    }
    if (Number(s.pending_count) > 0) {
      lines.push(`${s.pending_count} حركة تنتظر قرارك (غياب/تأخير): الأرقام تتغير بعد القرار`);
    }
    return {
      title: `مسير ${payrollMonthName(p.month)} (${arabicDate(p.start_date)} - ${arabicDate(p.cutoff_date)})`,
      lines,
      net: formatIQD(p.expected_net),
      when: p.can_approve_now
        ? 'تكدر تعتمده هسه من صفحة الرواتب'
        : `تعتمده من صفحة الرواتب بعد ${arabicDate(p.cutoff_date < preview.last_day ? p.cutoff_date : preview.last_day)}`,
    };
  });
}

/** روابط مستمسكات الموظف كقائمة دائماً: أي شكل ثاني (كائن `{}`، null) = قائمة فارغة بدل ما توكف الصفحة. */
export function documentList(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((u): u is string => typeof u === 'string') : [];
}

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
