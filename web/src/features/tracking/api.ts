// استعلامات Supabase الخاصة بصفحة المراقبة والانضباط.

import { supabase } from '@/lib/supabase';
import type { AttendanceRecord, Branch, LeaveRequest, LocationPoint, WorkSchedule } from '@/lib/db-types';
import type { MockGpsAttempt, RawZone, TrackedEmployee } from './types';
import { fetchAllRows } from '@/lib/fetch-all';

export interface TrackingDataset {
  geofenceZones: RawZone[];
  branches: Branch[];
  employees: TrackedEmployee[];
  workSchedules: WorkSchedule[];
  leaveRequests: LeaveRequest[];
  attendanceLogs: AttendanceRecord[];
  securityLogs: MockGpsAttempt[];
  /** مبلغ الخصم كما يحسبه محرّك الرواتب: `${employeeId}_${date}_${late|absent}` → د.ع */
  payrollAmounts: Record<string, number>;
  /** العطل الرسمية YYYY-MM-DD (لا غياب فيها) */
  holidays: string[];
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
      .select('id, full_name, branch_id, department_id, role, join_date, termination_date, departments:departments!employees_department_id_fkey(name)')
      .eq('is_active', true)
      .order('full_name'),
    supabase.from('work_schedules').select('*'),
    // الإجازات المعتمدة تتراكم مع السنين: كل الصفحات
    fetchAllRows<LeaveRequest>((from, to) =>
      supabase.from('leave_requests').select('*').eq('status', 'approved').order('id').range(from, to)),
  ]);
  const firstError = [resZones, resBranches, resEmps, resScheds].find(r => r.error)?.error;
  if (firstError) throw firstError;

  let attendanceLogs: AttendanceRecord[] = [];
  let securityLogs: MockGpsAttempt[] = [];
  const payrollAmounts: Record<string, number> = {};
  let holidays: string[] = [];
  if (startDate && endDate) {
    // فترة طويلة × كل الموظفين تتجاوز حد الـ 1000 صف: كل الصفحات حتى لا ينقص التقرير
    const attendancePage = (from: number, to: number) => {
      let q = supabase.from('attendance')
        .select('*, employees!employee_id(full_name, branch_id)')
        .gte('work_date', startDate)
        .lte('work_date', endDate);
      if (selectedEmployee !== 'all') q = q.eq('employee_id', selectedEmployee);
      return q.order('id').range(from, to);
    };
    type EventRow = { employee_id: string; event_date: string; event_type: string; amount: number };

    const [attendanceRows, resMock, events, resHolidays] = await Promise.all([
      fetchAllRows<AttendanceRecord>(attendancePage),
      // محاولات الموقع الوهمي للفترة المختارة فقط (كانت تُجلب كلها منذ أول يوم)
      supabase.from('mock_gps_attempts').select('*, employees(full_name)')
        .gte('timestamp', new Date(`${startDate}T00:00:00`).toISOString())
        .lte('timestamp', new Date(`${endDate}T23:59:59.999`).toISOString())
        .order('timestamp', { ascending: false }),
      // الأيام قبل نظام المسيرات ليس لها حركات؛ خطأ هنا لا يمنع عرض الصفحة
      fetchAllRows<EventRow>((from, to) => supabase.from('payroll_events')
        .select('employee_id, event_date, event_type, amount')
        .in('event_type', ['absence', 'late'])
        .neq('status', 'void')
        .gte('event_date', startDate)
        .lte('event_date', endDate)
        .order('id')
        .range(from, to)).catch(() => [] as EventRow[]),
      supabase.from('official_holidays').select('holiday_date').gte('holiday_date', startDate).lte('holiday_date', endDate),
    ]);
    holidays = (resHolidays.data ?? []).map((h: { holiday_date: string }) => h.holiday_date);
    if (resMock.error) throw resMock.error;
    for (const e of events) {
      payrollAmounts[`${e.employee_id}_${e.event_date}_${e.event_type === 'late' ? 'late' : 'absent'}`] = Number(e.amount) || 0;
    }

    attendanceLogs = attendanceRows;
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
    leaveRequests: resLeaves,
    attendanceLogs,
    securityLogs,
    payrollAmounts,
    holidays,
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

export async function updateAttendanceTimes(record: AttendanceRecord, checkIn: string, checkOut: string, fallbackDate: string, status?: 'present' | 'late') {
  const workDate = record.work_date || fallbackDate;
  const checkOutISO = toIso(workDate, checkOut);
  const { error } = await supabase
    .from('attendance')
    .update({
      check_in_time: toIso(workDate, checkIn),
      check_out_time: checkOutISO,
      // الحالة من وقت الدخول والجدول (كان يصير "حاضر" بمجرد وجود انصراف حتى لو متأخر)
      status: status ?? (checkOutISO ? 'present' : record.status),
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
  status: 'present' | 'late';
}) {
  const values = {
    check_in_time: toIso(entry.date, entry.checkIn),
    check_out_time: toIso(entry.date, entry.checkOut),
    status: entry.status,
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

/**
 * قرار خصم/إعفاء لمخالفة غياب أو تأخير، مع إشعار الموظف حسب القواعد.
 * المبلغ لا يُكتب هنا: محرّك الرواتب يحسبه من سجل الحضور (أجر اليوم ÷ 30، والتأخير بالدقيقة)
 * — كان يُضاف قيد خصم منفصل فوق خصم الحضور فيُخصم الموظف مرتين.
 */
export async function saveDecision(decision: {
  employee: TrackedEmployee;
  type: string;
  date: string;
  status: 'applied' | 'ignored';
  recordId: string | null;
  reason: string;
  fallbackBranchId: string | null;
}) {
  const { employee, type, date, status, recordId, reason } = decision;

  // يُفحص قبل إضافة الخصم حتى لا يبقى خصم بدون تسجيل الغياب
  const branchId = employee.branch_id || decision.fallbackBranchId;
  if (type === 'virtual_absent' && !branchId) {
    throw new Error('الموظف غير مرتبط بفرع، يرجى ربطه بفرع أولاً.');
  }

  // القرار ينكتب بسجل الحضور (deduction_status)، والـ trigger trg_payroll_attendance بالسيرفر ينقله لحركة
  // الرواتب (payroll_events). الباب الثاني لنفس القرار هو decide_payroll_event (صفحة الرواتب) — أي تغيير
  // بمسار القرار لازم يراعي البابين. التفاصيل: BUSINESS_RULES.md «دورة حياة المسير» البند 3.
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
