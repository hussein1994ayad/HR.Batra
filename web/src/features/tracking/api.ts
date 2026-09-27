// استعلامات Supabase الخاصة بصفحة المراقبة والانضباط.

import { supabase } from '@/lib/supabase';
import type { AttendanceRecord, Branch, LeaveRequest, LocationPoint, WorkSchedule } from '@/lib/db-types';
import type { MockGpsAttempt, RawZone, TrackedEmployee } from './types';

export interface TrackingDataset {
  geofenceZones: RawZone[];
  branches: Branch[];
  employees: TrackedEmployee[];
  workSchedules: WorkSchedule[];
  leaveRequests: LeaveRequest[];
  attendanceLogs: AttendanceRecord[];
  securityLogs: MockGpsAttempt[];
}

export async function fetchTrackingDataset(filters: {
  startDate: string;
  endDate: string;
  selectedBranch: string;
  selectedEmployee: string;
}): Promise<TrackingDataset> {
  const { startDate, endDate, selectedBranch, selectedEmployee } = filters;
  const [resZones, resBranches, resEmps, resScheds, resLeaves] = await Promise.all([
    supabase.from('geofence_zones').select('*').eq('is_active', true),
    supabase.from('branches').select('*'),
    supabase.from('employees')
      .select('id, full_name, branch_id, department_id, role, departments:departments!employees_department_id_fkey(name)')
      .eq('is_active', true)
      .order('full_name'),
    supabase.from('work_schedules').select('*'),
    supabase.from('leave_requests').select('*').eq('status', 'approved'),
  ]);
  const firstError = [resZones, resBranches, resEmps, resScheds, resLeaves].find(r => r.error)?.error;
  if (firstError) throw firstError;

  let attendanceLogs: AttendanceRecord[] = [];
  let securityLogs: MockGpsAttempt[] = [];
  if (startDate && endDate) {
    let attQuery = supabase.from('attendance')
      .select('*, employees!employee_id(full_name, branch_id)')
      .gte('work_date', startDate)
      .lte('work_date', endDate);
    if (selectedEmployee !== 'all') attQuery = attQuery.eq('employee_id', selectedEmployee);

    const [resAtt, resMock] = await Promise.all([
      attQuery,
      supabase.from('mock_gps_attempts').select('*, employees(full_name)').order('timestamp', { ascending: false }),
    ]);
    if (resAtt.error) throw resAtt.error;
    if (resMock.error) throw resMock.error;

    attendanceLogs = resAtt.data ?? [];
    if (selectedBranch !== 'all') {
      attendanceLogs = attendanceLogs.filter(log => log.employees?.branch_id === selectedBranch);
    }
    securityLogs = resMock.data ?? [];
  }

  return {
    geofenceZones: resZones.data ?? [],
    branches: resBranches.data ?? [],
    // supabase-js بدون أنواع مولّدة يستنتج العلاقة departments كمصفوفة، وهي فعلياً كائن واحد
    employees: (resEmps.data ?? []) as unknown as TrackedEmployee[],
    workSchedules: resScheds.data ?? [],
    leaveRequests: resLeaves.data ?? [],
    attendanceLogs,
    securityLogs,
  };
}

/** نقاط موقع موظف خلال يوم (بتوقيت الجهاز المحلي). */
export async function fetchTrailPoints(employeeId: string, dateStr: string) {
  const { data, error } = await supabase
    .from('location_tracking')
    .select('latitude, longitude, timestamp')
    .eq('employee_id', employeeId)
    .gte('timestamp', new Date(`${dateStr}T00:00:00`).toISOString())
    .lte('timestamp', new Date(`${dateStr}T23:59:59.999`).toISOString())
    .order('timestamp', { ascending: true });
  if (error) throw error;
  return data ?? [];
}

/** اشتراك مباشر بنقاط موقع موظف جديدة؛ يرجع دالة إلغاء الاشتراك. */
export function subscribeToEmployeeLocations(employeeId: string, onPoint: (point: LocationPoint) => void): () => void {
  const channel = supabase
    .channel(`location_tracking:live:${employeeId}`)
    .on(
      'postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'location_tracking', filter: `employee_id=eq.${employeeId}` },
      (payload: { new: LocationPoint }) => onPoint(payload.new),
    )
    .subscribe();
  return () => {
    void supabase.removeChannel(channel);
  };
}

const toIso = (date: string, time: string) => (time ? new Date(`${date}T${time}:00`).toISOString() : null);

export async function updateAttendanceTimes(record: AttendanceRecord, checkIn: string, checkOut: string, fallbackDate: string) {
  const workDate = record.work_date || fallbackDate;
  const checkOutISO = toIso(workDate, checkOut);
  const { error } = await supabase
    .from('attendance')
    .update({
      check_in_time: toIso(workDate, checkIn),
      check_out_time: checkOutISO,
      status: checkOutISO ? 'present' : record.status,
    })
    .eq('id', record.id);
  if (error) throw error;
}

/** حضور يدوي: يحدّث سجل اليوم إن وُجد أو ينشئ سجلاً جديداً. */
export async function saveManualAttendance(entry: {
  employeeId: string;
  branchId: string;
  date: string;
  checkIn: string;
  checkOut: string;
}) {
  const values = {
    check_in_time: toIso(entry.date, entry.checkIn),
    check_out_time: toIso(entry.date, entry.checkOut),
    status: 'present',
    branch_id: entry.branchId,
  };
  const { data: existing, error: findErr } = await supabase
    .from('attendance')
    .select('id')
    .eq('employee_id', entry.employeeId)
    .eq('work_date', entry.date)
    .maybeSingle();
  if (findErr) throw findErr;

  const { error } = existing
    ? await supabase.from('attendance').update(values).eq('id', existing.id)
    : await supabase.from('attendance').insert({ ...values, employee_id: entry.employeeId, work_date: entry.date });
  if (error) throw error;
}

/** تسجيل خروج الآن. الحالة تبقى كما هي (كانت تُضبط على 'completed' وهي قيمة يرفضها القيد). */
export async function forceCheckout(recordId: string) {
  const { error } = await supabase
    .from('attendance')
    .update({ check_out_time: new Date().toISOString() })
    .eq('id', recordId);
  if (error) throw error;
}

/** قرار خصم/إعفاء لمخالفة غياب أو تأخير، مع إشعار الموظف حسب القواعد. */
export async function saveDecision(decision: {
  employee: TrackedEmployee;
  type: string;
  date: string;
  status: 'applied' | 'ignored';
  recordId: string | null;
  reason: string;
  amount: number;
  fallbackBranchId: string | null;
}) {
  const { employee, type, date, status, recordId, reason, amount } = decision;

  // يُفحص قبل إضافة الخصم حتى لا يبقى خصم بدون تسجيل الغياب
  const branchId = employee.branch_id || decision.fallbackBranchId;
  if (type === 'virtual_absent' && !branchId) {
    throw new Error('الموظف غير مرتبط بفرع، يرجى ربطه بفرع أولاً.');
  }

  if (status === 'applied' && amount > 0) {
    const { error } = await supabase.from('bonuses_deductions').insert({
      employee_id: employee.id,
      type: 'deduction',
      amount,
      reason,
      issue_date: date,
    });
    if (error) throw error;
  }

  if (type === 'virtual_absent') {
    const { data: existing, error: findErr } = await supabase
      .from('attendance')
      .select('id')
      .eq('employee_id', employee.id)
      .eq('work_date', date)
      .maybeSingle();
    if (findErr) throw findErr;

    const values = { status: 'absent', deduction_status: status, deduction_reason: reason, branch_id: branchId };
    const { error } = existing
      ? await supabase.from('attendance').update(values).eq('id', existing.id)
      : await supabase.from('attendance').insert({ ...values, employee_id: employee.id, work_date: date });
    if (error) throw error;
  } else {
    const { error } = await supabase
      .from('attendance')
      .update({ deduction_status: status, deduction_reason: reason })
      .eq('id', recordId);
    if (error) throw error;
  }

  // الإشعار: الغياب المسجّل والإعفاء فقط (لا إشعار عند تطبيق خصم تأخير)
  if (type === 'virtual_absent') {
    await supabase.from('notifications').insert({
      employee_id: employee.id,
      title: 'تسجيل غياب يومي ⚠️',
      body: `تم تسجيل غيابك عن العمل ليوم ${date} من قبل الإدارة. السبب: ${reason || 'غير محدد'}`,
      type: 'attendance',
    });
  } else if (status === 'ignored') {
    await supabase.from('notifications').insert({
      employee_id: employee.id,
      title: 'إعفاء من الخصم المالي ✅',
      body: `تم إعفاؤك من الخصم المالي المترتب على ${type === 'late' ? 'التأخير الصباحي' : 'الغياب'} ليوم ${date}.`,
      type: 'attendance',
    });
  }
}
