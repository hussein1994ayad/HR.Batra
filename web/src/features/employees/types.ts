// أنواع صفحة إدارة الموظفين.

import type { Branch } from '@/lib/db-types';

export type BranchOption = Pick<Branch, 'id' | 'name'>;

/** طريقة إنهاء خدمة الموظف: أرشفة، حذف مجدول بعد 30 يوماً، أو حذف فوري. */
export type DeleteType = 'immediate' | 'archive' | 'scheduled';

/** مسير واحد بمعاينة «إنهاء خدمات» (end_of_service_preview). */
export interface EndOfServicePeriod {
  month: string;
  start_date: string;
  cutoff_date: string;
  /** يكدر الأدمن يعتمده هسه (آخر يوم فات، أو المسير خلص) */
  can_approve_now: boolean;
  /** الصافي اللي ينعتمد (ما ينزل تحت الصفر) */
  expected_net: number;
  /** كم ينقص من قسط السلفة لأن الراتب ما يكفي */
  loan_cut: number;
  /** خصومات أكثر من الراتب: ما تنخصم وتتسوى خارج النظام */
  excess_deductions: number;
  summary: {
    basic: number;
    basic_basis?: string;
    basic_note?: string;
    earnings: number;
    deductions: number;
    loans: number;
    net: number;
    scheduled_days?: number;
    attended_days?: number;
    pending_count?: number;
  };
}

/** معاينة «إنهاء خدمات»: شلون ينحسب آخر راتب لو آخر يوم = last_day (ما ينحفظ شي). */
export interface EndOfServicePreview {
  last_day: string;
  periods: EndOfServicePeriod[];
  total_net: number;
  /** باقي السلف بعد آخر راتب: الشركة تسويه ويا الموظف خارج النظام */
  loans_left_after: number;
}

/** حقول نموذج الإضافة/التعديل. */
export interface EmployeeFormValues {
  fullName: string;
  email: string;
  phone: string;
  password: string;
  role: string;
  branchId: string;
  monthlySalary: number;
  futureSalary: number;
  futureSalaryMonth: string;
  joinDate: string;
  /** فارغ = القسم العام (بدون قسم). */
  departmentId?: string;
}
