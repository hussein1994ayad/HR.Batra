// =========================================================================
// منطق صفحة الإعدادات — دوال نقية بدون React أو Supabase
// =========================================================================

import type { WorkSchedule } from '@/lib/db-types';
import type {
  CompanyInfo, LeaveType, PurgeOptions, PurgeResult, ScheduleForm, ScheduleTargets, SystemPolicies,
} from './types';

export const DEFAULT_COMPANY: CompanyInfo = {
  name: 'مكتب بغداد الرئيسي للخرسانة',
  address: 'العراق، بغداد، شارع الكرادة',
  phone: '+9647700000000',
  email: 'info@batra-concrete.com',
  website: 'www.batra-concrete.com',
  tax_number: '100-244-555',
  logo_url: '',
};

export const DEFAULT_LEAVE_TYPES: LeaveType[] = [
  { id: 'annual', name: 'إجازة سنوية' },
  { id: 'sick', name: 'إجازة مرضية' },
  { id: 'emergency', name: 'إجازة طارئة' },
  { id: 'maternity', name: 'إجازة أمومة' },
  { id: 'other', name: 'إجازة أخرى' },
];

/** أنواع مرتبطة بالرواتب والأرصدة ولا يمكن حذفها. */
export const PROTECTED_LEAVE_TYPES = ['annual', 'sick'];

type JsonRow = { value?: Record<string, unknown> | null } | null;
const num = (v: unknown, fallback: number) => Number(v) || fallback;

/** يحوّل صفوف system_settings إلى قيم النموذج مع القيم الافتراضية لكل حقل ناقص. */
export function parsePolicies(rows: { archive: JsonRow; payroll: JsonRow; leave: JsonRow }): SystemPolicies {
  const archive = rows.archive?.value ?? {};
  const payroll = rows.payroll?.value ?? {};
  const leave = rows.leave?.value;
  return {
    trackingDays: num(archive.tracking_archive_days, 180),
    cycleStartDay: num(payroll.cycle_start_day, 25),
    cycleEndDay: num(payroll.cycle_end_day, 24),
    defaultAnnual: num(leave?.default_annual, 21),
    defaultSick: num(leave?.default_sick, 15),
    leaveTypes: leave ? ((leave.active_types as LeaveType[] | undefined) ?? []) : DEFAULT_LEAVE_TYPES,
  };
}

export function parseCompany(row: Partial<Record<keyof CompanyInfo, string | null>> | null): CompanyInfo {
  if (!row) return DEFAULT_COMPANY;
  return {
    name: row.name || '',
    address: row.address || '',
    phone: row.phone || '',
    email: row.email || '',
    website: row.website || '',
    tax_number: row.tax_number || '',
    logo_url: row.logo_url || '',
  };
}

/** يضيف نوع إجازة برمز موحّد (أحرف صغيرة و _ بدل المسافات) أو يرجع سبب الرفض. */
export function addLeaveType(types: LeaveType[], rawId: string, rawName: string):
  { types: LeaveType[] } | { error: string; duplicate?: boolean } {
  if (!rawId.trim() || !rawName.trim()) return { error: 'يرجى كتابة رمز ونوع الإجازة' };
  const id = rawId.trim().toLowerCase().replace(/\s+/g, '_');
  if (types.some(t => t.id === id)) return { error: 'رمز الإجازة هذا موجود بالفعل', duplicate: true };
  return { types: [...types, { id, name: rawName.trim() }] };
}

export const DEFAULT_SCHEDULE_FORM: ScheduleForm = {
  name: '',
  scope: 'branch',
  targetId: '',
  checkIn: '09:00',
  checkOut: '17:00',
  grace: 15,
  workDays: [6, 0, 1, 2, 3, 4], // السبت إلى الخميس
};

export function toggleWorkDay(days: number[], day: number): number[] {
  return days.includes(day) ? days.filter(d => d !== day) : [...days, day].sort((a, b) => a - b);
}

/** صف work_schedules من النموذج؛ الجهة المستهدفة تُكتب في عمود النطاق المختار فقط. */
export function buildScheduleRow(form: ScheduleForm): Omit<WorkSchedule, 'id'> {
  const row: Omit<WorkSchedule, 'id'> = {
    name: form.name.trim(),
    check_in_time: form.checkIn + ':00',
    check_out_time: form.checkOut + ':00',
    grace_period_minutes: Number(form.grace),
    work_days: form.workDays,
  };
  if (form.scope === 'branch') row.branch_id = form.targetId;
  else if (form.scope === 'department') row.department_id = form.targetId;
  else row.employee_id = form.targetId;
  return row;
}

const DAY_NAMES = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
export const getDayNameAr = (day: number) => DAY_NAMES[day] ?? '';

/** اسم الجهة التي يطبق عليها الجدول (الموظف أولاً ثم القسم ثم الفرع). */
export function scheduleTargetName(sched: WorkSchedule, targets: ScheduleTargets): string {
  if (sched.employee_id) {
    const emp = targets.employees.find(e => e.id === sched.employee_id);
    return `👤 موظف: ${emp ? emp.full_name : 'غير معروف'}`;
  }
  if (sched.department_id) {
    const dept = targets.departments.find(d => d.id === sched.department_id);
    return `🏢 قسم: ${dept ? dept.name : 'غير معروف'}`;
  }
  if (sched.branch_id) {
    const branch = targets.branches.find(b => b.id === sched.branch_id);
    return `📍 فرع: ${branch ? branch.name : 'غير معروف'}`;
  }
  return 'عام';
}

/** "HH:MM[:SS]" → "h:MM AM/PM". */
export function formatTime12h(timeStr: string | null | undefined): string {
  if (!timeStr) return '--:--';
  const [h, m] = timeStr.split(':');
  const hour = parseInt(h, 10);
  const minute = parseInt(m, 10);
  if (Number.isNaN(hour) || Number.isNaN(minute)) return timeStr;
  return `${hour % 12 || 12}:${String(minute).padStart(2, '0')} ${hour >= 12 ? 'PM' : 'AM'}`;
}

export const ARABIC_MONTH_NAMES = [
  'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
  'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
];

/** رسالة نجاح التنظيف بعدد السجلات المحذوفة لكل فئة مختارة. */
export function purgeSummary(options: PurgeOptions, result: PurgeResult | null | undefined): string {
  const r = result ?? {};
  const parts: string[] = [];
  if (options.notifications) parts.push(`${r.notifications_deleted || 0} إشعار`);
  if (options.tracking) {
    parts.push(`${r.tracking_deleted || 0} إحداثي تتبع، ${r.stops_deleted || 0} وقفات، ${r.violations_deleted || 0} مخالفات`);
  }
  if (options.absences) parts.push(`${r.absences_deleted || 0} سجل حضور وغياب`);
  return `تم التنظيف بنجاح! 🧹 تم حذف: ${parts.join('، ')}`;
}
