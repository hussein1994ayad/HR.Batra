// بيانات الصفحة الرئيسية: استعلامات متوازية + كاش محلي (batra_cache_dashboard) يظهر فوراً عند الفتح.

import { supabase } from '@/lib/supabase';
import { writeCache } from '@/lib/useQuery';
import { localDateStr } from '@/lib/format';
import type { Attendance, Branch, GeofenceViolation, LeaveRequest, MockGpsAttempt, StorageStat, WorkSchedule } from '@/lib/db-types';
import { buildSecurityLogs, computeTodayAttendance, type DirectoryEmployee, type SecurityLog } from './logic';

export interface DashboardData {
  stats: {
    employees: number;
    presentToday: number;
    absentToday: number;
    pendingLeaves: number;
    pendingLoans: number;
    pendingDevices: number;
    securityIncidents: number;
    totalStorageBytes: number;
  };
  securityLogs: SecurityLog[];
  branches: Pick<Branch, 'id' | 'name'>[];
  employeesList: DirectoryEmployee[];
  absentList: DirectoryEmployee[];
  syncedAt: string;
}

export const DASHBOARD_CACHE_KEY = 'batra_cache_dashboard';

export async function fetchDashboard(): Promise<DashboardData> {
  // Daily cleanup & scheduled salary activation run server-side; fire and forget.
  supabase.rpc('perform_daily_cleanup').then(({ error }) => {
    if (error) console.error('Error running daily cleanup:', error);
  });

  const todayStr = localDateStr();
  const [
    { count: empCount },
    { data: attToday },
    { count: leaveCount },
    { count: loanCount },
    { count: deviceCount },
    { count: mockCount },
    { count: geoCount },
    { data: delFiles },
    { data: statsData },
    { data: mockAttempts },
    { data: geoViolations },
    { data: branchList },
    { data: empList },
    { data: leavesData },
    { data: schedules },
  ] = await Promise.all([
    supabase.from('employees').select('*', { count: 'exact', head: true }),
    supabase.from('attendance').select('status, employee_id').eq('work_date', todayStr),
    supabase.from('leave_requests').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
    supabase.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
    supabase.from('employee_devices').select('*', { count: 'exact', head: true }).eq('is_approved', false),
    supabase.from('mock_gps_attempts').select('*', { count: 'exact', head: true }),
    supabase.from('geofence_violations').select('*', { count: 'exact', head: true }),
    supabase.from('deleted_files').select('file_size_bytes').is('restored_at', null),
    supabase.rpc('get_storage_stats'),
    supabase.from('mock_gps_attempts').select('*, employees(full_name)').order('timestamp', { ascending: false }).limit(5),
    supabase
      .from('geofence_violations')
      .select('*, employees(full_name), geofence_zones(name)')
      .order('timestamp', { ascending: false })
      .limit(5),
    supabase.from('branches').select('id, name'),
    supabase.from('employees').select('id, full_name, branch_id, department_id').eq('is_active', true).order('full_name'),
    supabase.from('leave_requests').select('*').eq('status', 'approved'),
    supabase.from('work_schedules').select('*'),
  ]);

  const employees = (empList ?? []) as DirectoryEmployee[];
  const { present, absentList } = computeTodayAttendance(
    todayStr,
    (attToday ?? []) as Pick<Attendance, 'status' | 'employee_id'>[],
    employees,
    (schedules ?? []) as WorkSchedule[],
    (leavesData ?? []) as LeaveRequest[],
  );

  const trashBytes = (delFiles ?? []).reduce((sum, f) => sum + (Number(f.file_size_bytes) || 0), 0);
  const bucketBytes = ((statsData ?? []) as StorageStat[]).reduce((sum, s) => sum + (Number(s.total_size) || 0), 0);

  const data: DashboardData = {
    stats: {
      employees: empCount || 0,
      presentToday: present,
      absentToday: absentList.length,
      pendingLeaves: leaveCount || 0,
      pendingLoans: loanCount || 0,
      pendingDevices: deviceCount || 0,
      securityIncidents: (mockCount || 0) + (geoCount || 0),
      totalStorageBytes: trashBytes + bucketBytes,
    },
    securityLogs: buildSecurityLogs((mockAttempts ?? []) as MockGpsAttempt[], (geoViolations ?? []) as GeofenceViolation[]),
    branches: (branchList ?? []) as DashboardData['branches'],
    employeesList: employees,
    absentList,
    syncedAt: new Date().toISOString(),
  };
  writeCache(DASHBOARD_CACHE_KEY, data);
  return data;
}

export function isDashboardData(value: unknown): value is DashboardData {
  return !!value && typeof value === 'object' && 'stats' in value && Array.isArray((value as DashboardData).absentList);
}

/** نشر تعميم بمدته وجمهوره وإشعار المستهدفين بخطوة وحدة (publish_announcement). يرجع عدد المُشعَرين. */
export async function publishAnnouncement(params: {
  p_title: string;
  p_content: string;
  p_starts_at: string | null;
  p_ends_at: string | null;
  p_target: 'all' | 'branch' | 'employees';
  p_branch_id: string | null;
  p_employee_ids: string[] | null;
}): Promise<number | null> {
  const { data: sent, error } = await supabase.rpc('publish_announcement', params);
  if (error) throw error;
  return sent;
}
