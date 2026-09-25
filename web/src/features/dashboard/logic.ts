// =========================================================================
// منطق الصفحة الرئيسية — دوال نقية بدون React أو Supabase
// =========================================================================

import type { Branch, LeaveRequest, WorkSchedule } from '@/lib/db-types';
import { resolveWorkSchedule } from '@/lib/schedules';
import type { EmployeeSummary, SecurityLog } from './types';

const DEFAULT_WORK_DAYS = [6, 0, 1, 2, 3, 4]; // السبت إلى الخميس
const PRESENT_STATUSES = ['present', 'late', 'half_day'];

/**
 * حضور وغياب اليوم:
 * - حاضر: سجل بحالة حضور/تأخير/نصف يوم.
 * - غائب: سجل غياب في يوم عمل، أو موظف نشط بلا سجل وبلا إجازة معتمدة واليوم من أيام دوامه.
 */
export function computeTodayAttendance(input: {
  todayStr: string;
  attendance: { status: string; employee_id: string }[];
  employees: EmployeeSummary[];
  leaves: Pick<LeaveRequest, 'employee_id' | 'start_date' | 'end_date'>[];
  schedules: WorkSchedule[];
}): { present: number; absent: number; absentList: EmployeeSummary[] } {
  const { todayStr, attendance, employees, leaves, schedules } = input;
  const [y, m, d] = todayStr.split('-').map(Number);
  const weekday = new Date(y, m - 1, d).getDay();
  const isWorkingDay = (emp: EmployeeSummary | { id: string }) =>
    (resolveWorkSchedule(emp, schedules)?.work_days ?? DEFAULT_WORK_DAYS).includes(weekday);

  let present = 0;
  const absentList: EmployeeSummary[] = [];
  let absent = 0;
  const hasRecord = new Set<string>();

  for (const r of attendance) {
    if (PRESENT_STATUSES.includes(r.status)) {
      present++;
      hasRecord.add(r.employee_id);
    } else if (r.status === 'absent') {
      const emp = employees.find(e => e.id === r.employee_id);
      if (isWorkingDay(emp ?? { id: r.employee_id })) {
        absent++;
        hasRecord.add(r.employee_id);
        if (emp) absentList.push(emp);
      }
    }
  }

  for (const emp of employees) {
    if (hasRecord.has(emp.id)) continue;
    const onLeave = leaves.some(l =>
      l.employee_id === emp.id && todayStr >= l.start_date.slice(0, 10) && todayStr <= l.end_date.slice(0, 10));
    if (!onLeave && isWorkingDay(emp)) {
      absent++;
      absentList.push(emp);
    }
  }

  return { present, absent, absentList };
}

type MockAttemptRow = {
  id: string; timestamp: string; app_used?: string | null; latitude: number | string; longitude: number | string;
  employees?: { full_name?: string | null } | null;
};
type GeofenceViolationRow = {
  id: string; timestamp: string; violation_type?: string | null;
  employees?: { full_name?: string | null } | null; geofence_zones?: { name?: string | null } | null;
};

/** آخر الخروقات (تزييف الموقع ومخالفات السياج) مدمجة ومرتبة من الأحدث. */
export function buildSecurityLogs(mock: MockAttemptRow[], geo: GeofenceViolationRow[], limit = 5): SecurityLog[] {
  const logs: SecurityLog[] = [
    ...mock.map((log): SecurityLog => ({
      id: log.id,
      type: 'mock_gps',
      name: log.employees?.full_name || 'موظف غير معروف',
      timestamp: new Date(log.timestamp),
      details: `محاولة تزييف موقع باستخدام: ${log.app_used || 'تطبيق غير معروف'}`,
      coords: `${log.latitude}, ${log.longitude}`,
    })),
    ...geo.map((log): SecurityLog => ({
      id: log.id,
      type: 'geofence',
      name: log.employees?.full_name || 'موظف غير معروف',
      timestamp: new Date(log.timestamp),
      details: `${log.violation_type === 'entry' ? 'دخول' : 'خروج'} غير مصرح به في منطقة: ${log.geofence_zones?.name || 'مجهولة'}`,
      coords: '',
    })),
  ];
  return logs
    .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
    .slice(0, limit);
}

export const sumBy = <T,>(rows: T[] | null | undefined, pick: (row: T) => number | string | null | undefined) =>
  (rows ?? []).reduce((total, row) => total + (Number(pick(row)) || 0), 0);

/** الغائبون مجمّعون حسب الفرع بترتيب الفروع، ثم مجموعة "بدون فرع" إن وُجدت. */
export function groupAbsenteesByBranch(absentList: EmployeeSummary[], branches: Pick<Branch, 'id' | 'name'>[]) {
  const groups = branches
    .map(branch => ({ key: branch.id, name: branch.name, assigned: true, employees: absentList.filter(e => e.branch_id === branch.id) }))
    .filter(g => g.employees.length > 0);
  const unassigned = absentList.filter(e => !e.branch_id);
  if (unassigned.length > 0) groups.push({ key: 'none', name: 'غير محدد (بدون فرع)', assigned: false, employees: unassigned });
  return groups;
}
