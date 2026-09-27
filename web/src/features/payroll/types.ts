// أنواع خاصة بصفحة الرواتب.

/** سطر في تفصيل الحضور اليومي لموظف ضمن كشف الراتب. */
export type DetailLog = {
  date: string;
  status: string;
  time: string;
  note: string;
  isAbsenceDay: boolean;
  isExcused?: boolean;
};

/** قيد يُنشأ مع كشف الراتب داخل approve_salary_slip. */
export type SlipAdjustment = {
  type: 'bonus' | 'deduction';
  amount: number;
  reason: string;
  issue_date: string;
  skip_if_exists: boolean;
};

/** الخانات التي يمكن للأدمن تعديلها يدوياً في جدول الرواتب. */
export type OverrideField = 'bonuses' | 'attendanceDeductions' | 'otherDeductions';

/** تعديلات يدوية لكل موظف: employeeId → قيم الخانات المعدلة. */
export type PayrollOverrides = Record<string, Partial<Record<OverrideField, number>>>;

/** أيام الغياب المعفاة يدوياً لكل موظف: employeeId → تواريخ YYYY-MM-DD. */
export type ExcusedDays = Record<string, string[]>;
