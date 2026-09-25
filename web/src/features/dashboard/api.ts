// استعلامات Supabase الخاصة بالصفحة الرئيسية. كل دالة ترمي عند الخطأ.

import { supabase } from '@/lib/supabase';
import { getLocalDateStr } from '@/lib/dates';
import { buildSecurityLogs, computeTodayAttendance, sumBy } from './logic';
import type { AnnouncementTarget, DashboardData } from './types';

const count = (table: string) => supabase.from(table).select('*', { count: 'exact', head: true });

/** تنظيف يومي وتفعيل الرواتب المستقبلية — يعمل بالخلفية ولا يؤخر الصفحة. */
export function runDailyCleanup() {
  void supabase.rpc('perform_daily_cleanup').then(({ error }) => {
    if (error) console.error('Error running daily cleanup:', error);
  });
}

export async function fetchDashboardData(): Promise<DashboardData> {
  const todayStr = getLocalDateStr();
  const results = await Promise.all([
    count('employees'),
    supabase.from('attendance').select('status, employee_id').eq('work_date', todayStr),
    count('leave_requests').eq('status', 'pending'),
    count('loans').eq('status', 'pending'),
    count('employee_devices').eq('is_approved', false),
    count('mock_gps_attempts'),
    count('geofence_violations'),
    supabase.from('deleted_files').select('file_size_bytes').is('restored_at', null),
    supabase.rpc('get_storage_stats'),
    supabase.from('mock_gps_attempts').select('*, employees(full_name)').order('timestamp', { ascending: false }).limit(5),
    supabase.from('geofence_violations').select('*, employees(full_name), geofence_zones(name)').order('timestamp', { ascending: false }).limit(5),
    supabase.from('branches').select('id, name'),
    supabase.from('departments').select('id, name'),
    supabase.from('employees').select('id, full_name, branch_id, department_id').eq('is_active', true).order('full_name'),
    supabase.from('leave_requests').select('employee_id, start_date, end_date').eq('status', 'approved'),
    supabase.from('work_schedules').select('*'),
  ]);
  const [
    empCount, attToday, leaveCount, loanCount, deviceCount, mockCount, geoCount, delFiles, storageStats,
    mockAttempts, geoViolations, branches, departments, employees, leaves, schedules,
  ] = results;

  // بدون الموظفين والحضور والإجازات والجداول تكون أرقام الغياب خاطئة، فهذه تُفشل التحميل.
  // الباقي (عدادات، مساحة التخزين، سجل الأمان) يُسجَّل فقط حتى لا تتعطل الصفحة كلها بسببه.
  const critical = [attToday, employees, leaves, schedules].find(r => r.error)?.error;
  if (critical) throw critical;
  results.filter(r => r.error).forEach(r => console.error('Dashboard query failed:', r.error));

  const employeesList = employees.data ?? [];
  const { present, absent, absentList } = computeTodayAttendance({
    todayStr,
    attendance: attToday.data ?? [],
    employees: employeesList,
    leaves: leaves.data ?? [],
    schedules: schedules.data ?? [],
  });

  return {
    stats: {
      employees: empCount.count || 0,
      presentToday: present,
      absentToday: absent,
      pendingLeaves: leaveCount.count || 0,
      pendingLoans: loanCount.count || 0,
      pendingDevices: deviceCount.count || 0,
      securityIncidents: (mockCount.count || 0) + (geoCount.count || 0),
      totalStorageBytes:
        sumBy(delFiles.data as { file_size_bytes: number | null }[] | null, f => f.file_size_bytes) +
        sumBy(storageStats.data as { total_size: number | null }[] | null, s => s.total_size),
    },
    securityLogs: buildSecurityLogs(mockAttempts.data ?? [], geoViolations.data ?? []),
    absentList,
    branches: branches.data ?? [],
    departments: departments.data ?? [],
    employeesList,
  };
}

/** يرسل التعميم كإشعار لكل مستلم ويحفظه في أرشيف التعاميم. يرجع عدد المستلمين. */
export async function broadcastAnnouncement(target: AnnouncementTarget, text: string): Promise<number> {
  let recipients: string[];
  if (target.type === 'employee') {
    recipients = target.employeeIds;
  } else {
    let query = supabase.from('employees').select('id').eq('is_active', true);
    if (target.type === 'branch') query = query.eq('branch_id', target.branchId);
    const { data, error } = await query;
    if (error) throw error;
    recipients = (data ?? []).map(e => e.id);
  }
  if (recipients.length === 0) return 0;

  const title = 'تعميم إداري هام 📢';
  const { error: notifErr } = await supabase.from('notifications').insert(
    recipients.map(employee_id => ({ employee_id, title, body: text, type: 'memo', is_read: false })),
  );
  if (notifErr) throw notifErr;

  const { data: { session } } = await supabase.auth.getSession();
  const { error } = await supabase.from('announcements').insert({
    title, content: text, is_pinned: false, created_by: session?.user?.id || null,
  });
  if (error) console.error('Failed to archive announcement:', error); // الإشعارات وصلت بالفعل
  return recipients.length;
}
