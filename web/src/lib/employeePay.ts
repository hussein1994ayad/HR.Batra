// الراتب ما ينقرا من جدول الموظفين مباشرة (تدقيق 14/10/2026، BUG-005): القاعدة تمنع أعمدة الراتب عن أي مستخدم،
// والأدمن يقراها من get_employee_pay (والموظف راتبه هو بس، والمدير ما يوصله شي).
import { supabase } from './supabase';

/** أعمدة الموظف المسموح قراءتها مباشرة (كل شي غير الراتب). نفس القائمة بملف القاعدة 20261018000000. */
export const EMPLOYEE_COLUMNS =
  'id, employee_code, full_name, phone, email, avatar_url, is_active, role, department_id, branch_id, created_at, ' +
  'must_change_password, device_id_lock, fcm_token, document_urls, join_date, termination_date';

export interface EmployeePay {
  monthly_salary_iqd: number | null;
  future_salary_iqd: number | null;
  future_salary_month: string | null;
}

type PayRow = { employee_id: string } & EmployeePay;

/** رواتب الموظفين (employee_id → الراتب). بدون ids = كل اللي يحق للمستخدم يشوفهم. */
export async function fetchEmployeePay(ids?: string[]): Promise<Record<string, EmployeePay>> {
  const { data, error } = await supabase.rpc('get_employee_pay', ids ? { p_employee_ids: ids } : {});
  if (error) {
    // سيرفر قبل تحديث 20261018000000 (الدالة بعدها ما موجودة): الراتب ينقرا مباشرة مثل قبل
    if (error.code === 'PGRST202') return toMap(await readPayDirectly(ids));
    throw error;
  }
  return toMap((data ?? []) as PayRow[]);
}

async function readPayDirectly(ids?: string[]): Promise<PayRow[]> {
  let query = supabase.from('employees').select('id, monthly_salary_iqd, future_salary_iqd, future_salary_month');
  if (ids) query = query.in('id', ids);
  const { data, error } = await query;
  if (error) throw error;
  return ((data ?? []) as ({ id: string } & EmployeePay)[]).map(({ id, ...pay }) => ({ employee_id: id, ...pay }));
}

function toMap(rows: PayRow[]): Record<string, EmployeePay> {
  const out: Record<string, EmployeePay> = {};
  for (const r of rows) {
    out[r.employee_id] = {
      monthly_salary_iqd: r.monthly_salary_iqd,
      future_salary_iqd: r.future_salary_iqd,
      future_salary_month: r.future_salary_month,
    };
  }
  return out;
}
