'use client';

import React, { useEffect, useMemo, useState } from 'react';
import dynamic from 'next/dynamic';
import toast from 'react-hot-toast';
import {
  MapPin,
  Users,
  ShieldAlert,
  CheckCircle2,
  RefreshCw,
  Clock,
  Pencil,
  Save,
  LogOut,
  Building2,
  Map as MapIcon,
  Download,
  UserPlus,
  Gavel,
  AlertTriangle,
  Radio,
  Timer,
  XCircle,
} from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { useQuery } from '@/lib/useQuery';
import {
  DEFAULT_CHECK_IN,
  findSchedule,
  formatLateDurationArabic,
  isDateInRange,
  minutesLate,
  weekdayOf,
  workDaysFor,
} from '@/lib/attendance';
import { escapeHtml, errorMessage, formatClock, formatDuration, localDateStr } from '@/lib/format';
import { BAGHDAD_CENTER } from '@/lib/geo';
import type { Attendance, Branch, DeductionStatus, Employee, GeofenceZone, LeaveRequest, MockGpsAttempt, WorkSchedule } from '@/lib/types';
import type { MapMarker, MapPolygon } from '@/components/MapComponent';
import { useConfirm } from '@/components/confirm';
import {
  AmountInput,
  Avatar,
  Badge,
  Button,
  Card,
  CardHeader,
  DataTable,
  EmptyState,
  Field,
  FilterSelect,
  IconButton,
  Input,
  Modal,
  ModalFooter,
  PageHeader,
  PageSkeleton,
  SegmentedTabs,
  Select,
  StatTile,
  TableEmpty,
  Toggle,
  cn,
} from '@/components/ui';

const MapComponent = dynamic(() => import('@/components/MapComponent'), {
  ssr: false,
  loading: () => <div className="skeleton w-full h-full min-h-[420px] rounded-2xl" />,
});

type TrackedEmployee = Pick<Employee, 'id' | 'full_name' | 'branch_id' | 'department_id' | 'role' | 'departments'>;

interface TrackingData {
  zones: GeofenceZone[];
  branches: Branch[];
  employees: TrackedEmployee[];
  schedules: WorkSchedule[];
  leaves: LeaveRequest[];
  attendance: Attendance[];
  mockAttempts: MockGpsAttempt[];
}

function dayBounds(dateStr: string): { start: string; end: string } {
  const [y, m, d] = dateStr.split('-').map(Number);
  return { start: new Date(y, m - 1, d).toISOString(), end: new Date(y, m - 1, d + 1).toISOString() };
}

async function fetchTracking(dateStr: string): Promise<TrackingData> {
  const { start, end } = dayBounds(dateStr);
  const [zones, branches, employees, schedules, leaves, attendance, mock] = await Promise.all([
    supabase.from('geofence_zones').select('*').eq('is_active', true),
    supabase.from('branches').select('*'),
    supabase
      .from('employees')
      .select('id, full_name, branch_id, department_id, role, departments:departments!employees_department_id_fkey(name)')
      .eq('is_active', true)
      .order('full_name'),
    supabase.from('work_schedules').select('*'),
    supabase.from('leave_requests').select('*').eq('status', 'approved'),
    supabase.from('attendance').select('*, employees!employee_id(full_name, branch_id)').eq('work_date', dateStr),
    supabase
      .from('mock_gps_attempts')
      .select('*, employees(full_name)')
      .gte('timestamp', start)
      .lt('timestamp', end)
      .order('timestamp', { ascending: false }),
  ]);
  if (attendance.error) throw attendance.error;
  return {
    zones: (zones.data ?? []) as GeofenceZone[],
    branches: (branches.data ?? []) as Branch[],
    employees: (employees.data ?? []) as unknown as TrackedEmployee[],
    schedules: (schedules.data ?? []) as WorkSchedule[],
    leaves: (leaves.data ?? []) as LeaveRequest[],
    attendance: (attendance.data ?? []) as Attendance[],
    mockAttempts: (mock.data ?? []) as MockGpsAttempt[],
  };
}

async function fetchTrail(employeeId: string | null, dateStr: string): Promise<[number, number][]> {
  if (!employeeId) return [];
  const { start, end } = dayBounds(dateStr);
  const { data, error } = await supabase
    .from('location_tracking')
    .select('latitude, longitude, timestamp')
    .eq('employee_id', employeeId)
    .gte('timestamp', start)
    .lt('timestamp', end)
    .order('timestamp', { ascending: true });
  if (error) throw error;
  return (data ?? []).map((p) => [Number(p.latitude), Number(p.longitude)] as [number, number]);
}

interface Decision {
  key: string;
  recordId: string | null;
  type: 'late' | 'absent' | 'virtual_absent';
  employee: TrackedEmployee;
  date: string;
  time: string;
  duration: string;
  status: DeductionStatus;
  reason: string;
  suggestedAmount: number;
}

function buildDecisions(data: TrackingData, dateStr: string, branchId: string): Decision[] {
  const weekday = weekdayOf(dateStr);
  const list: Decision[] = [];
  data.employees.forEach((emp) => {
    if (branchId !== 'all' && emp.branch_id !== branchId) return;
    const schedule = findSchedule(emp, data.schedules);
    if (!workDaysFor(schedule).includes(weekday)) return;

    const att = data.attendance.find((a) => a.employee_id === emp.id);
    const base = { employee: emp, date: dateStr };
    if (att?.status === 'late') {
      const mins = minutesLate(att.check_in_time, schedule?.check_in_time ?? DEFAULT_CHECK_IN);
      list.push({
        ...base,
        key: `${emp.id}_late`,
        recordId: att.id,
        type: 'late',
        time: formatClock(att.check_in_time),
        duration: formatLateDurationArabic(mins),
        status: att.deduction_status || 'pending',
        reason: att.deduction_reason || `التأخير: ${formatLateDurationArabic(mins)}`,
        suggestedAmount: mins * 50,
      });
    } else if (att?.status === 'absent') {
      list.push({
        ...base,
        key: `${emp.id}_absent`,
        recordId: att.id,
        type: 'absent',
        time: '-',
        duration: 'يوم واحد',
        status: att.deduction_status || 'pending',
        reason: att.deduction_reason || 'الغياب بدون إجازة',
        suggestedAmount: 25000,
      });
    } else if (!att) {
      const onLeave = data.leaves.some((l) => l.employee_id === emp.id && isDateInRange(dateStr, l.start_date, l.end_date));
      if (!onLeave) {
        list.push({
          ...base,
          key: `${emp.id}_virtual`,
          recordId: null,
          type: 'virtual_absent',
          time: '-',
          duration: 'يوم واحد',
          status: 'pending',
          reason: 'الغياب بدون إجازة',
          suggestedAmount: 25000,
        });
      }
    }
  });
  return list;
}

function zonePolygon(zone: GeofenceZone): MapPolygon {
  let coords: [number, number][] = [];
  if (zone.polygon_coordinates) {
    try {
      coords = Array.isArray(zone.polygon_coordinates) ? zone.polygon_coordinates : JSON.parse(zone.polygon_coordinates);
    } catch {
      coords = [];
    }
  }
  if (coords.length < 3 && zone.latitude && zone.longitude) {
    const o = 0.003;
    coords = [
      [zone.latitude + o, zone.longitude - o],
      [zone.latitude + o, zone.longitude + o],
      [zone.latitude - o, zone.longitude + o],
      [zone.latitude - o, zone.longitude - o],
    ];
  }
  return { name: zone.name, coords };
}

function timeInputValue(iso: string | null | undefined): string {
  if (!iso) return '';
  const d = new Date(iso);
  return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
}

export default function TrackingPage() {
  const confirm = useConfirm();
  const [date, setDate] = useState(() => localDateStr());
  const [branchId, setBranchId] = useState('all');
  const [tab, setTab] = useState<'monitoring' | 'decisions'>('monitoring');
  const query = useQuery(`tracking:${date}`, () => fetchTracking(date || localDateStr()));
  const [busy, setBusy] = useState<string | null>(null);

  const [editing, setEditing] = useState<{ record: Attendance; checkIn: string; checkOut: string } | null>(null);
  const [manual, setManual] = useState<{ employeeId: string; date: string; checkIn: string; checkOut: string } | null>(null);
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [amounts, setAmounts] = useState<Record<string, number>>({});

  const [trailEmployee, setTrailEmployee] = useState<string | null>(null);
  const [live, setLive] = useState(false);
  const trail = useQuery(`trail:${trailEmployee}:${date}`, () => fetchTrail(trailEmployee, date));
  const trailMutate = trail.mutate;

  // Stream new points for the selected employee while live mode is on.
  useEffect(() => {
    if (!trailEmployee || !live) return;
    const channel = supabase
      .channel(`location_tracking:live:${trailEmployee}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'location_tracking', filter: `employee_id=eq.${trailEmployee}` },
        (payload) => {
          const row = payload.new as { latitude?: number; longitude?: number };
          const lat = Number(row.latitude);
          const lng = Number(row.longitude);
          if (lat && lng) {
            trailMutate((prev) => [...prev, [lat, lng]]);
            toast.success('تم استلام موقع جديد مباشرةً');
          }
        },
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [trailEmployee, live, trailMutate]);

  const data = query.data;
  const stale = query.refreshing && !!data;

  const attendance = useMemo(
    () => (data?.attendance ?? []).filter((a) => branchId === 'all' || (a.employees?.branch_id ?? a.branch_id) === branchId),
    [data, branchId],
  );
  const decisions = useMemo(() => (data && date ? buildDecisions(data, date, branchId) : []), [data, date, branchId]);
  const virtualAbsents = decisions.filter((d) => d.type === 'virtual_absent');
  const pendingDecisions = decisions.filter((d) => d.status === 'pending').length;
  const trailPoints = useMemo(() => trail.data ?? [], [trail.data]);

  const markers = useMemo<MapMarker[]>(() => {
    const list: MapMarker[] = [];
    attendance.forEach((log) => {
      if (!log.check_in_lat || !log.check_in_lng) return;
      list.push({
        lat: Number(log.check_in_lat),
        lng: Number(log.check_in_lng),
        popupText: `<strong>${escapeHtml(log.employees?.full_name || 'موظف')}</strong><br/>الحضور: ${formatClock(log.check_in_time)}<br/>الحالة: ${log.status === 'late' ? 'متأخر' : 'في الوقت'}`,
      });
    });
    (data?.mockAttempts ?? []).forEach((m) => {
      if (!m.latitude || !m.longitude) return;
      list.push({
        lat: Number(m.latitude),
        lng: Number(m.longitude),
        isViolation: true,
        popupText: `<strong style="color:#FB7185">محاولة موقع وهمي</strong><br/>${escapeHtml(m.employees?.full_name || 'غير معروف')}<br/>${formatClock(m.timestamp)} · ${escapeHtml(m.app_used || 'تطبيق غير مصنف')}`,
      });
    });
    if (trailEmployee && trailPoints.length > 0) {
      const [lat, lng] = trailPoints[trailPoints.length - 1];
      const name = data?.employees.find((e) => e.id === trailEmployee)?.full_name;
      list.push({ lat, lng, color: '#60A5FA', popupText: `<strong>الموقع الحالي</strong><br/>${escapeHtml(name || 'الموظف المختار')}` });
    }
    return list;
  }, [attendance, data, trailEmployee, trailPoints]);

  const polygons = useMemo(() => (data?.zones ?? []).map(zonePolygon), [data]);
  const polylines = useMemo(
    () => (trailPoints.length >= 2 ? [{ coords: trailPoints, color: '#60A5FA', weight: 4.5 }] : []),
    [trailPoints],
  );
  const mapCenter: [number, number] = trailPoints.length > 0 ? trailPoints[trailPoints.length - 1] : BAGHDAD_CENTER;
  const mapZoom = trailPoints.length > 0 ? 15 : 12;

  if (!data) {
    if (query.error) {
      return <EmptyState icon={AlertTriangle} tone="rose" title="تعذر تحميل بيانات الحضور" description={errorMessage(query.error)} action={<Button size="sm" variant="secondary" onClick={query.reload}>إعادة المحاولة</Button>} />;
    }
    return <PageSkeleton rows={8} />;
  }

  const lateCount = attendance.filter((a) => a.status === 'late').length;

  const run = async (key: string, action: () => Promise<void>, failMsg: string) => {
    setBusy(key);
    try {
      await action();
    } catch (err) {
      toast.error(`${failMsg}: ${errorMessage(err)}`);
    } finally {
      setBusy(null);
    }
  };

  const saveTimes = (e: React.FormEvent) => {
    e.preventDefault();
    if (!editing) return;
    return run(
      'edit',
      async () => {
        const checkIn = editing.checkIn ? new Date(`${date}T${editing.checkIn}:00`).toISOString() : null;
        const checkOut = editing.checkOut ? new Date(`${date}T${editing.checkOut}:00`).toISOString() : null;
        const { error } = await supabase
          .from('attendance')
          .update({ check_in_time: checkIn, check_out_time: checkOut, status: checkOut ? 'present' : editing.record.status })
          .eq('id', editing.record.id);
        if (error) throw error;
        setEditing(null);
        query.reload();
        toast.success('تم تحديث أوقات الدوام');
      },
      'فشل التحديث',
    );
  };

  const saveManual = (e: React.FormEvent) => {
    e.preventDefault();
    if (!manual) return;
    if (!manual.employeeId) {
      toast.error('الرجاء اختيار الموظف أولاً');
      return;
    }
    return run(
      'manual',
      async () => {
        const emp = data.employees.find((x) => x.id === manual.employeeId);
        const branch = emp?.branch_id || data.branches[0]?.id;
        if (!branch) throw new Error('الموظف غير مربوط بفرع ولا يوجد فرع افتراضي');
        const checkIn = manual.checkIn ? new Date(`${manual.date}T${manual.checkIn}:00`).toISOString() : null;
        const checkOut = manual.checkOut ? new Date(`${manual.date}T${manual.checkOut}:00`).toISOString() : null;
        const record = { check_in_time: checkIn, check_out_time: checkOut, status: 'present', branch_id: branch };

        const { data: existing } = await supabase
          .from('attendance')
          .select('id')
          .eq('employee_id', manual.employeeId)
          .eq('work_date', manual.date)
          .maybeSingle();
        const { error } = existing
          ? await supabase.from('attendance').update(record).eq('id', existing.id)
          : await supabase.from('attendance').insert({ ...record, employee_id: manual.employeeId, work_date: manual.date });
        if (error) throw error;

        setManual(null);
        query.reload();
        toast.success('تم تسجيل الحضور اليدوي');
      },
      'حدث خطأ',
    );
  };

  const forceCheckout = async (record: Attendance) => {
    const ok = await confirm({
      title: 'تسجيل خروج الموظف الآن؟',
      message: `سيُسجَّل وقت الخروج لـ ${record.employees?.full_name || 'الموظف'} بتوقيت اللحظة الحالية.`,
      confirmLabel: 'تسجيل الخروج',
      tone: 'warning',
      icon: LogOut,
    });
    if (!ok) return;
    await run(
      `checkout_${record.id}`,
      async () => {
        // Only the checkout time changes; the attendance status (present/late) is kept.
        const { error } = await supabase.from('attendance').update({ check_out_time: new Date().toISOString() }).eq('id', record.id);
        if (error) throw error;
        query.reload();
        toast.success('تم تسجيل خروج الموظف');
      },
      'فشل تسجيل الخروج',
    );
  };

  const decide = (item: Decision, status: 'applied' | 'ignored') =>
    run(
      `${item.key}_${status}`,
      async () => {
        const reason = reasons[item.key] ?? item.reason;
        const amount = status === 'applied' ? amounts[item.key] ?? item.suggestedAmount : 0;
        if (status === 'applied' && amount > 0) {
          await supabase.from('bonuses_deductions').insert({
            employee_id: item.employee.id,
            type: 'deduction',
            amount,
            reason,
            issue_date: item.date,
          });
        }

        if (item.type === 'virtual_absent') {
          const branch = item.employee.branch_id || data.branches[0]?.id;
          if (!branch) throw new Error('الموظف غير مرتبط بفرع، يرجى ربطه بفرع أولاً');
          const { error } = await supabase.from('attendance').insert({
            employee_id: item.employee.id,
            work_date: item.date,
            status: 'absent',
            deduction_status: status,
            deduction_reason: reason,
            branch_id: branch,
          });
          if (error) throw error;
        } else {
          const { error } = await supabase
            .from('attendance')
            .update({ deduction_status: status, deduction_reason: reason })
            .eq('id', item.recordId);
          if (error) throw error;
        }

        const what = item.type === 'late' ? 'التأخير الصباحي' : 'الغياب';
        await supabase.from('notifications').insert({
          employee_id: item.employee.id,
          title: status === 'applied' ? 'تطبيق خصم مالي ⚠️' : 'إعفاء من الخصم المالي ✅',
          body:
            status === 'applied'
              ? `تقرر تطبيق الخصم المالي المترتب على ${what} ليوم ${item.date}. السبب: ${reason}`
              : `تم إعفاؤك من الخصم المالي المترتب على ${what} ليوم ${item.date}.`,
          type: 'attendance',
        });

        query.reload();
        toast.success('تم حفظ القرار وإشعار الموظف');
      },
      'فشل حفظ القرار',
    );

  const exportExcel = async () => {
    try {
      const rows = [
        ...attendance.map((log) => ({
          'اسم الموظف': log.employees?.full_name || 'غير محدد',
          'التاريخ': log.work_date,
          'وقت الدخول': formatClock(log.check_in_time),
          'وقت الخروج': formatClock(log.check_out_time),
          'ساعات العمل': formatDuration(log.check_in_time, log.check_out_time),
          'الحالة': log.status === 'late' ? 'تأخير' : log.status === 'absent' ? 'غياب' : 'حضور',
        })),
        ...virtualAbsents.map((d) => ({
          'اسم الموظف': d.employee.full_name,
          'التاريخ': date,
          'وقت الدخول': '-',
          'وقت الخروج': '-',
          'ساعات العمل': '-',
          'الحالة': 'غياب',
        })),
      ];
      const XLSX = await import('xlsx');
      const sheet = XLSX.utils.json_to_sheet(rows);
      const book = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(book, sheet, 'تقرير الحضور');
      XLSX.writeFile(book, `تقرير_الحضور_${date}.xlsx`);
    } catch (err) {
      toast.error(`حدث خطأ أثناء تصدير التقرير: ${errorMessage(err)}`);
    }
  };

  return (
    <div className="space-y-6 pb-12">
      <PageHeader
        icon={MapPin}
        tone="emerald"
        title="الحضور والتتبع"
        description="سجل الحضور والانصراف اليومي، التتبع على الخريطة، وقرارات خصم الغياب والتأخير"
        actions={
          <>
            <FilterSelect icon={Building2} value={branchId} onChange={setBranchId} className="w-40">
              <option value="all">جميع الفروع</option>
              {data.branches.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </FilterSelect>
            <Input type="date" value={date} max={localDateStr()} onChange={(e) => e.target.value && setDate(e.target.value)} className="h-9 w-40 text-xs" dir="ltr" />
            <IconButton icon={RefreshCw} label="تحديث" loading={query.refreshing} onClick={query.reload} className="w-9 h-9" />
            <Button size="sm" icon={UserPlus} onClick={() => setManual({ employeeId: '', date, checkIn: '09:00', checkOut: '17:00' })}>
              حضور يدوي
            </Button>
          </>
        }
      />

      <div className={cn('grid grid-cols-2 lg:grid-cols-4 gap-4 transition-opacity', stale && 'opacity-60')}>
        <StatTile label="سجلوا الحضور" value={attendance.filter((a) => a.status !== 'absent').length} icon={CheckCircle2} tone="emerald" />
        <StatTile label="متأخرون" value={lateCount} icon={Timer} tone={lateCount > 0 ? 'amber' : 'slate'} />
        <StatTile label="لم يسجلوا حضوراً" value={virtualAbsents.length} icon={XCircle} tone={virtualAbsents.length > 0 ? 'rose' : 'slate'} />
        <StatTile label="محاولات موقع وهمي" value={data.mockAttempts.length} icon={ShieldAlert} tone={data.mockAttempts.length > 0 ? 'rose' : 'emerald'} />
      </div>

      <SegmentedTabs
        value={tab}
        onChange={setTab}
        options={[
          { value: 'monitoring', label: 'السجل والخريطة', icon: MapIcon },
          { value: 'decisions', label: 'قرارات الغياب والتأخير', icon: Gavel, count: pendingDecisions || undefined },
        ]}
      />

      {tab === 'monitoring' ? (
        <>
          <Card className={cn('transition-opacity', stale && 'opacity-60')}>
            <CardHeader
              icon={Clock}
              tone="emerald"
              title="سجل الحضور والانصراف"
              description={`يوم ${date}`}
              actions={
                <Button size="sm" variant="soft-success" icon={Download} onClick={exportExcel}>
                  تصدير Excel
                </Button>
              }
            />
            <DataTable>
              <thead>
                <tr>
                  <th>الموظف</th>
                  <th>الحالة</th>
                  <th>الدخول</th>
                  <th>الخروج</th>
                  <th>ساعات العمل</th>
                  <th className="!text-left">الإجراءات</th>
                </tr>
              </thead>
              <tbody>
                {attendance.length === 0 && virtualAbsents.length === 0 ? (
                  <TableEmpty colSpan={6}>لا توجد سجلات حضور لهذا اليوم</TableEmpty>
                ) : (
                  <>
                    {attendance.map((log) => (
                      <tr key={log.id}>
                        <td>
                          <div className="flex items-center gap-2.5">
                            <Avatar name={log.employees?.full_name} size="sm" />
                            <span className="font-bold text-white">{log.employees?.full_name || 'موظف'}</span>
                          </div>
                        </td>
                        <td>
                          {log.status === 'late' ? (
                            <Badge tone="amber" dot>متأخر</Badge>
                          ) : log.status === 'absent' ? (
                            <Badge tone="rose" dot>غائب</Badge>
                          ) : log.status === 'half_day' ? (
                            <Badge tone="violet" dot>نصف يوم</Badge>
                          ) : (
                            <Badge tone="emerald" dot>حاضر</Badge>
                          )}
                        </td>
                        <td className="font-mono text-emerald-300" dir="ltr">{formatClock(log.check_in_time)}</td>
                        <td className="font-mono text-slate-300" dir="ltr">
                          {log.check_out_time ? formatClock(log.check_out_time) : log.check_in_time ? <Badge tone="sky">داخل الدوام</Badge> : '-'}
                        </td>
                        <td className="font-bold text-slate-200">{formatDuration(log.check_in_time, log.check_out_time)}</td>
                        <td className="!text-left">
                          <div className="flex justify-end gap-1.5">
                            <IconButton
                              icon={Pencil}
                              label="تعديل أوقات الدخول والخروج"
                              tone="indigo"
                              onClick={() => setEditing({ record: log, checkIn: timeInputValue(log.check_in_time), checkOut: timeInputValue(log.check_out_time) })}
                            />
                            {log.check_in_time && !log.check_out_time && (
                              <IconButton icon={LogOut} label="تسجيل خروج الآن" tone="rose" loading={busy === `checkout_${log.id}`} onClick={() => forceCheckout(log)} />
                            )}
                          </div>
                        </td>
                      </tr>
                    ))}
                    {virtualAbsents.map((d) => (
                      <tr key={d.key} className="bg-rose-500/[0.03]">
                        <td>
                          <div className="flex items-center gap-2.5">
                            <Avatar name={d.employee.full_name} size="sm" />
                            <span className="font-bold text-white">{d.employee.full_name}</span>
                          </div>
                        </td>
                        <td>
                          <Badge tone="rose">لم يبصم</Badge>
                        </td>
                        <td className="text-slate-600">-</td>
                        <td className="text-slate-600">-</td>
                        <td className="text-slate-600">-</td>
                        <td className="!text-left">
                          <Button size="xs" variant="ghost" icon={Gavel} onClick={() => setTab('decisions')}>
                            اتخاذ قرار
                          </Button>
                        </td>
                      </tr>
                    ))}
                  </>
                )}
              </tbody>
            </DataTable>
          </Card>

          <Card>
            <CardHeader
              icon={MapIcon}
              tone="sky"
              title="خريطة التتبع المباشر"
              description="مواقع بصمات الحضور، محاولات المواقع الوهمية، ومسار حركة الموظف المختار"
              actions={
                <>
                  <Select
                    value={trailEmployee ?? ''}
                    onChange={(e) => setTrailEmployee(e.target.value || null)}
                    className="h-9 w-56 text-xs"
                  >
                    <option value="">اختر موظفاً لعرض مساره...</option>
                    {attendance.map((log) => (
                      <option key={log.employee_id} value={log.employee_id}>
                        {log.employees?.full_name}
                      </option>
                    ))}
                  </Select>
                  {trailEmployee && <Toggle checked={live} onChange={setLive} label="بث مباشر" />}
                </>
              }
            />
            {trailEmployee && (
              <div className="flex flex-wrap items-center justify-between gap-2 mb-4 px-3.5 py-2.5 rounded-xl bg-sky-500/5 border border-sky-500/15 text-xs">
                <span className="text-slate-300">
                  {trail.loading || trail.refreshing ? 'جاري تحميل المسار...' : `${trailPoints.length} نقطة تتبع مسجلة لهذا اليوم`}
                </span>
                {live && (
                  <span className="flex items-center gap-1.5 font-bold text-emerald-300">
                    <Radio className="w-3.5 h-3.5 animate-pulse" /> تحديث مباشر
                  </span>
                )}
              </div>
            )}
            <div className="h-[520px]">
              <MapComponent markers={markers} polygons={polygons} polylines={polylines} center={mapCenter} zoom={mapZoom} />
            </div>
          </Card>
        </>
      ) : (
        <Card className={cn('transition-opacity', stale && 'opacity-60')}>
          <CardHeader
            icon={Gavel}
            tone="amber"
            title="قرارات الغياب والتأخير"
            description="«تطبيق» يخصم المبلغ من صافي الراتب، و«تجاهل» يعفي الموظف دون التأثير على راتبه"
          />
          <DataTable>
            <thead>
              <tr>
                <th>الموظف</th>
                <th>المخالفة</th>
                <th>المدة</th>
                <th>الخصم (د.ع)</th>
                <th>السبب</th>
                <th className="!text-left">القرار</th>
              </tr>
            </thead>
            <tbody>
              {decisions.length === 0 ? (
                <TableEmpty colSpan={6}>لا توجد غيابات أو تأخيرات لهذا اليوم</TableEmpty>
              ) : (
                decisions.map((item) => (
                  <tr key={item.key}>
                    <td>
                      <div className="flex items-center gap-2.5 min-w-[180px]">
                        <Avatar name={item.employee.full_name} size="sm" />
                        <div>
                          <p className="font-bold text-white">{item.employee.full_name}</p>
                          <p className="text-[10px] text-slate-500">
                            {item.employee.departments?.name || 'بدون قسم'} · {item.time !== '-' ? `البصمة ${item.time}` : 'غياب كامل'}
                          </p>
                        </div>
                      </div>
                    </td>
                    <td>
                      <Badge tone={item.type === 'late' ? 'amber' : 'rose'}>{item.type === 'late' ? 'تأخير' : 'غياب'}</Badge>
                    </td>
                    <td className="whitespace-nowrap">{item.duration}</td>
                    <td>
                      <AmountInput
                        value={amounts[item.key] ?? item.suggestedAmount}
                        onValueChange={(v) => setAmounts((prev) => ({ ...prev, [item.key]: v }))}
                        className="h-8 w-28 text-xs"
                      />
                    </td>
                    <td>
                      <Input
                        value={reasons[item.key] ?? item.reason}
                        onChange={(e) => setReasons((prev) => ({ ...prev, [item.key]: e.target.value }))}
                        className="h-8 min-w-[200px] text-xs"
                      />
                    </td>
                    <td className="!text-left">
                      <div className="flex justify-end gap-1.5">
                        <Button
                          size="xs"
                          variant={item.status === 'applied' ? 'success' : 'soft-success'}
                          loading={busy === `${item.key}_applied`}
                          disabled={!!busy}
                          onClick={() => decide(item, 'applied')}
                        >
                          تطبيق
                        </Button>
                        <Button
                          size="xs"
                          variant={item.status === 'ignored' ? 'secondary' : 'ghost'}
                          loading={busy === `${item.key}_ignored`}
                          disabled={!!busy}
                          onClick={() => decide(item, 'ignored')}
                        >
                          تجاهل
                        </Button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </DataTable>
        </Card>
      )}

      {editing && (
        <Modal title="تعديل سجل الحضور" subtitle={`${editing.record.employees?.full_name ?? ''} · ${date}`} icon={Pencil} tone="indigo" size="sm" onClose={() => setEditing(null)}>
          <form onSubmit={saveTimes} className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <Field label="وقت الدخول">
                <Input type="time" value={editing.checkIn} onChange={(e) => setEditing({ ...editing, checkIn: e.target.value })} dir="ltr" />
              </Field>
              <Field label="وقت الخروج">
                <Input type="time" value={editing.checkOut} onChange={(e) => setEditing({ ...editing, checkOut: e.target.value })} dir="ltr" />
              </Field>
            </div>
            <ModalFooter onCancel={() => setEditing(null)} loading={busy === 'edit'} submitLabel="حفظ التعديلات" submitIcon={Save} />
          </form>
        </Modal>
      )}

      {manual && (
        <Modal title="تسجيل حضور يدوي" subtitle="يُحدَّث السجل إن كان للموظف بصمة في نفس اليوم" icon={UserPlus} tone="brand" size="sm" onClose={() => setManual(null)}>
          <form onSubmit={saveManual} className="space-y-4">
            <Field label="الموظف">
              <Select required value={manual.employeeId} onChange={(e) => setManual({ ...manual, employeeId: e.target.value })}>
                <option value="">اختر الموظف...</option>
                {data.employees.map((emp) => (
                  <option key={emp.id} value={emp.id}>
                    {emp.full_name}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="تاريخ الدوام">
              <Input type="date" required value={manual.date} max={localDateStr()} onChange={(e) => setManual({ ...manual, date: e.target.value })} dir="ltr" />
            </Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="وقت الدخول">
                <Input type="time" value={manual.checkIn} onChange={(e) => setManual({ ...manual, checkIn: e.target.value })} dir="ltr" />
              </Field>
              <Field label="وقت الخروج">
                <Input type="time" value={manual.checkOut} onChange={(e) => setManual({ ...manual, checkOut: e.target.value })} dir="ltr" />
              </Field>
            </div>
            <ModalFooter onCancel={() => setManual(null)} loading={busy === 'manual'} submitLabel="تسجيل الحضور" submitIcon={Users} />
          </form>
        </Modal>
      )}
    </div>
  );
}
