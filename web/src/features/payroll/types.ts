// أنواع خاصة بصفحة الرواتب.

/** مكافأة/خصم يُضاف مع كشف الراتب داخل approve_payroll_slip (تعديل يدوي قبل الاعتماد). */
export type SlipAdjustment = {
  type: 'bonus' | 'deduction';
  amount: number;
  reason: string;
};

/** الخانات التي يمكن للأدمن تعديلها يدوياً في جدول الرواتب. */
export type OverrideField = 'bonuses' | 'attendanceDeductions' | 'otherDeductions';

/** تعديلات يدوية لكل موظف: employeeId → قيم الخانات المعدلة. */
export type PayrollOverrides = Record<string, Partial<Record<OverrideField, number>>>;
