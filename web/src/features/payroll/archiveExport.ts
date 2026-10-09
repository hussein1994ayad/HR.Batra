// ملف Excel للشهر قبل الأرشفة: الأرشفة تحذف سجلات الحضور التفصيلية، فننزّلها مع الرواتب أولاً
// (مرجع بالنزاعات أو التدقيق).

import * as XLSX from 'xlsx';
import { supabase } from '@/lib/supabase';
import type { PayrollRow } from './calc';

const STATUS: Record<string, string> = {
  present: 'حاضر', late: 'متأخر', absent: 'غائب', half_day: 'نصف يوم', early_leave: 'خروج مبكر', on_leave: 'إجازة',
};
const time = (iso: string | null) =>
  iso ? new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Baghdad' }) : '';

export async function downloadMonthBeforeArchive(month: string, startDate: string, endDate: string, rows: PayrollRow[]): Promise<void> {
  const { data, error } = await supabase
    .from('attendance')
    .select('work_date, status, check_in_time, check_out_time, deduction_status, deduction_reason, employees(full_name, employee_code)')
    .gte('work_date', startDate)
    .lte('work_date', endDate)
    .order('work_date');
  if (error) throw error;

  const wb = XLSX.utils.book_new();
  const payroll = rows.map((r) => ({
    'الموظف': r.full_name,
    'الفرع': r.branches?.name ?? '',
    'الأساسي': r.basic,
    'المكافآت': r.totalBonuses,
    'خصم الدوام': r.totalAttendanceDeductions,
    'خصومات أخرى': r.totalDeductions - r.totalAttendanceDeductions,
    'السلف': r.loanDeduction,
    'الصافي': r.netSalary,
    'معتمد': r.isIssued ? 'نعم' : 'لا',
  }));
  XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(payroll), 'الرواتب');

  type Att = {
    work_date: string; status: string; check_in_time: string | null; check_out_time: string | null;
    deduction_status: string | null; deduction_reason: string | null;
    employees: { full_name: string | null; employee_code: string | null } | { full_name: string | null; employee_code: string | null }[] | null;
  };
  const attendance = ((data ?? []) as Att[]).map((a) => {
    const emp = Array.isArray(a.employees) ? a.employees[0] : a.employees;
    return {
      'التاريخ': a.work_date,
      'الموظف': emp?.full_name ?? '',
      'الكود': emp?.employee_code ?? '',
      'الحالة': STATUS[a.status] ?? a.status,
      'الحضور': time(a.check_in_time),
      'الانصراف': time(a.check_out_time),
      'القرار': a.deduction_status === 'applied' ? 'خصم' : a.deduction_status === 'ignored' ? 'إعفاء' : '',
      'السبب': a.deduction_reason ?? '',
    };
  });
  XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(attendance), 'الحضور');
  XLSX.writeFile(wb, `أرشيف_رواتب_وحضور_${month}.xlsx`);
}
