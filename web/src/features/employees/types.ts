// أنواع صفحة إدارة الموظفين.

import type { Branch } from '@/lib/db-types';

export type BranchOption = Pick<Branch, 'id' | 'name'>;

/** طريقة إنهاء خدمة الموظف: أرشفة، حذف مجدول بعد 30 يوماً، أو حذف فوري. */
export type DeleteType = 'immediate' | 'archive' | 'scheduled';

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
}
