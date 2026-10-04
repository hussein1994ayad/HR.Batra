// منطق الصفحة الرئيسية (نظرة عامة) — بدون React/Supabase حتى يُفحص لوحده.

import { findSchedule, isDateInRange, weekdayOf, workDaysFor } from '@/lib/attendance';
import type { Attendance, Employee, GeofenceViolation, LeaveRequest, MockGpsAttempt, WorkSchedule } from '@/lib/db-types';

export type DirectoryEmployee = Pick<Employee, 'id' | 'full_name' | 'branch_id' | 'department_id'>;

export interface SecurityLog {
  id: string;
  type: 'mock_gps' | 'geofence';
  name: string;
  timestamp: string;
  details: string;
  coords: string;
}

/**
 * حضور وغياب اليوم:
 * - حاضر = سجل بحالة present / late / half_day.
 * - غائب = سجل absent **أو** بدون سجل، بشرط أن اليوم يوم دوام للموظف حسب جدوله، وأنه غير مجاز.
 *   (يوم بدون دوام لأحد = عطلة، فيكون الحاضر + الغائب = 0.)
 */
export function computeTodayAttendance(
  todayStr: string,
  attToday: Pick<Attendance, 'status' | 'employee_id'>[],
  employees: DirectoryEmployee[],
  scheduleList: WorkSchedule[],
  leaves: LeaveRequest[],
): { present: number; absentList: DirectoryEmployee[] } {
  const weekday = weekdayOf(todayStr);
  const isWorkingDay = (emp: DirectoryEmployee) => workDaysFor(findSchedule(emp, scheduleList)).includes(weekday);

  let present = 0;
  const accounted = new Set<string>();
  const absentList: DirectoryEmployee[] = [];

  attToday.forEach((r) => {
    if (['present', 'late', 'half_day'].includes(r.status)) {
      present++;
      accounted.add(r.employee_id);
    } else if (r.status === 'absent') {
      const emp = employees.find((e) => e.id === r.employee_id);
      if (emp && isWorkingDay(emp)) {
        accounted.add(r.employee_id);
        absentList.push(emp);
      }
    }
  });

  // Employees with no record who are not on leave and were due to work today.
  employees.forEach((emp) => {
    if (accounted.has(emp.id)) return;
    const onLeave = leaves.some((l) => l.employee_id === emp.id && isDateInRange(todayStr, l.start_date, l.end_date));
    if (!onLeave && isWorkingDay(emp)) absentList.push(emp);
  });

  return { present, absentList };
}

/** آخر 5 حوادث أمنية (موقع وهمي + خروقات سياج) مرتبة من الأحدث. */
export function buildSecurityLogs(mockAttempts: MockGpsAttempt[], geoViolations: GeofenceViolation[]): SecurityLog[] {
  return [
    ...mockAttempts.map((log) => ({
      id: log.id,
      type: 'mock_gps' as const,
      name: log.employees?.full_name || 'موظف غير معروف',
      timestamp: log.timestamp,
      details: `محاولة تزييف موقع باستخدام: ${log.app_used || 'تطبيق غير معروف'}`,
      coords: log.latitude && log.longitude ? `${log.latitude}, ${log.longitude}` : '',
    })),
    ...geoViolations.map((log) => ({
      id: log.id,
      type: 'geofence' as const,
      name: log.employees?.full_name || 'موظف غير معروف',
      timestamp: log.timestamp,
      details: `${log.violation_type === 'entry' ? 'دخول' : 'خروج'} غير مصرح به في منطقة: ${log.geofence_zones?.name || 'مجهولة'}`,
      coords: '',
    })),
  ]
    .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
    .slice(0, 5);
}

/** وقت الحادثة: الساعة فقط لو اليوم، وإلا اليوم/الشهر · الساعة. */
export function formatLogTime(ts: string) {
  const d = new Date(ts);
  if (isNaN(d.getTime())) return 'غير محدد';
  const time = d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
  return d.toDateString() === new Date().toDateString()
    ? time
    : `${d.toLocaleDateString('en-GB', { day: '2-digit', month: '2-digit' })} · ${time}`;
}
