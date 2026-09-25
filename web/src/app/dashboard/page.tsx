'use client';

import React, { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import toast from 'react-hot-toast';
import {
  Users,
  MapPin,
  ShieldAlert,
  CalendarRange,
  Coins,
  Smartphone,
  HardDrive,
  UserPlus,
  Send,
  AlertTriangle,
  Clock,
  CheckCircle,
  FileSpreadsheet,
  RefreshCw,
  Banknote,
  ChevronLeft,
  Building2,
  ShieldCheck,
  Sparkles,
  type LucideIcon,
} from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { confetti } from '@/lib/lazy';
import { readCache, useQuery, writeCache } from '@/lib/useQuery';
import { findSchedule, isDateInRange, weekdayOf, workDaysFor } from '@/lib/attendance';
import { errorMessage, formatBytes, localDateStr, timeAgo } from '@/lib/format';
import type {
  Attendance,
  Branch,
  Employee,
  GeofenceViolation,
  LeaveRequest,
  MockGpsAttempt,
  StorageStat,
  WorkSchedule,
} from '@/lib/types';
import {
  Avatar,
  Badge,
  Card,
  CardHeader,
  EmptyState,
  Field,
  Modal,
  ModalFooter,
  SearchInput,
  Select,
  SegmentedTabs,
  TONE_CHIP,
  Textarea,
  cn,
  type Tone,
} from '@/components/ui';

interface SecurityLog {
  id: string;
  type: 'mock_gps' | 'geofence';
  name: string;
  timestamp: string;
  details: string;
  coords: string;
}

type DirectoryEmployee = Pick<Employee, 'id' | 'full_name' | 'branch_id' | 'department_id'>;

interface DashboardData {
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

const CACHE_KEY = 'batra_cache_dashboard';

async function fetchDashboard(): Promise<DashboardData> {
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
  const scheduleList = (schedules ?? []) as WorkSchedule[];
  const leaves = (leavesData ?? []) as LeaveRequest[];
  const weekday = weekdayOf(todayStr);
  const isWorkingDay = (emp: DirectoryEmployee) => workDaysFor(findSchedule(emp, scheduleList)).includes(weekday);

  let present = 0;
  const accounted = new Set<string>();
  const absentList: DirectoryEmployee[] = [];

  ((attToday ?? []) as Pick<Attendance, 'status' | 'employee_id'>[]).forEach((r) => {
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

  const trashBytes = (delFiles ?? []).reduce((sum, f) => sum + (Number(f.file_size_bytes) || 0), 0);
  const bucketBytes = ((statsData ?? []) as StorageStat[]).reduce((sum, s) => sum + (Number(s.total_size) || 0), 0);

  const logs: SecurityLog[] = [
    ...((mockAttempts ?? []) as MockGpsAttempt[]).map((log) => ({
      id: log.id,
      type: 'mock_gps' as const,
      name: log.employees?.full_name || 'موظف غير معروف',
      timestamp: log.timestamp,
      details: `محاولة تزييف موقع باستخدام: ${log.app_used || 'تطبيق غير معروف'}`,
      coords: log.latitude && log.longitude ? `${log.latitude}, ${log.longitude}` : '',
    })),
    ...((geoViolations ?? []) as GeofenceViolation[]).map((log) => ({
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
    securityLogs: logs,
    branches: (branchList ?? []) as DashboardData['branches'],
    employeesList: employees,
    absentList,
    syncedAt: new Date().toISOString(),
  };
  writeCache(CACHE_KEY, data);
  return data;
}

function isDashboardData(value: unknown): value is DashboardData {
  return !!value && typeof value === 'object' && 'stats' in value && Array.isArray((value as DashboardData).absentList);
}

export default function DashboardPage() {
  const [cached] = useState(() => {
    const c = readCache<DashboardData>(CACHE_KEY);
    return isDashboardData(c) ? c : undefined;
  });
  const [adminName] = useState(() => readCache<{ name?: string }>('batra_cache_admin')?.name ?? '');
  const query = useQuery('dashboard', fetchDashboard, cached);
  const [showAnnounceModal, setShowAnnounceModal] = useState(false);
  const [absentSearch, setAbsentSearch] = useState('');
  const [now, setNow] = useState(() => Date.now());

  // Keep the "last synced" label fresh.
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 30000);
    return () => clearInterval(t);
  }, []);

  const data = query.data;

  const absentGroups = useMemo(() => {
    if (!data) return [];
    const q = absentSearch.trim().toLowerCase();
    const list = q ? data.absentList.filter((e) => (e.full_name || '').toLowerCase().includes(q)) : data.absentList;
    return [
      ...data.branches.map((b) => ({ id: b.id, name: b.name, members: list.filter((e) => e.branch_id === b.id) })),
      { id: '__none', name: 'بدون فرع', members: list.filter((e) => !e.branch_id) },
    ].filter((g) => g.members.length > 0);
  }, [data, absentSearch]);

  if (!data) {
    if (query.error) {
      return (
        <EmptyState
          icon={AlertTriangle}
          tone="rose"
          title="تعذر تحميل بيانات لوحة التحكم"
          description={errorMessage(query.error)}
          action={
            <button onClick={query.reload} className="text-xs font-bold text-indigo-300 hover:text-indigo-200 cursor-pointer">
              إعادة المحاولة
            </button>
          }
        />
      );
    }
    return <DashboardSkeleton />;
  }

  const { stats, securityLogs } = data;
  const tracked = stats.presentToday + stats.absentToday;
  const attendanceRate = tracked > 0 ? Math.round((stats.presentToday / tracked) * 100) : 0;
  const firstName = adminName.trim().split(/\s+/)[0];
  const greeting = new Date(now).getHours() < 12 ? 'صباح الخير' : 'مساء الخير';
  const pendingTotal = stats.pendingLeaves + stats.pendingLoans + stats.pendingDevices;
  const heroSummary = [
    pendingTotal > 0 ? `لديك ${pendingTotal} طلب بانتظار قرارك` : 'لا توجد طلبات معلقة حالياً',
    stats.absentToday > 0 ? `و${stats.absentToday} موظف لم يسجلوا حضورهم بعد.` : 'والجميع سجلوا حضورهم اليوم.',
  ].join(pendingTotal > 0 ? '، ' : ' ');

  const statCards: StatCardProps[] = [
    { title: 'إجمالي الكادر', value: stats.employees, subtitle: 'الموظفون المسجلون', icon: Users, tone: 'indigo', href: '/dashboard/employees' },
    { title: 'حاضر اليوم', value: stats.presentToday, subtitle: 'سجلوا بصمة الحضور', icon: CheckCircle, tone: 'emerald', href: '/dashboard/tracking' },
    { title: 'غياب اليوم', value: stats.absentToday, subtitle: 'لم يسجلوا بصمة دخول', icon: AlertTriangle, tone: 'rose', href: '#absent-section', attention: stats.absentToday > 0 },
    { title: 'إجازات معلقة', value: stats.pendingLeaves, subtitle: 'بانتظار المراجعة', icon: CalendarRange, tone: 'amber', href: '/dashboard/leaves', attention: stats.pendingLeaves > 0 },
    { title: 'سلف مطلوبة', value: stats.pendingLoans, subtitle: 'بانتظار الاعتماد المالي', icon: Coins, tone: 'sky', href: '/dashboard/loans', attention: stats.pendingLoans > 0 },
    { title: 'اعتماد الأجهزة', value: stats.pendingDevices, subtitle: 'هواتف بانتظار الموافقة', icon: Smartphone, tone: 'violet', href: '/dashboard/employees', attention: stats.pendingDevices > 0 },
  ];

  const quickActions: { label: string; hint: string; icon: LucideIcon; tone: Tone; href?: string; onClick?: () => void }[] = [
    { label: 'إضافة موظف', hint: 'حساب وهوية جديدة', icon: UserPlus, tone: 'indigo', href: '/dashboard/employees#new' },
    { label: 'بث تعميم', hint: 'إشعار فوري للموبايل', icon: Send, tone: 'violet', onClick: () => setShowAnnounceModal(true) },
    { label: 'الرواتب', hint: 'احتساب وصرف', icon: Banknote, tone: 'emerald', href: '/dashboard/payroll' },
    { label: 'تقرير الحضور', hint: 'تصدير Excel', icon: FileSpreadsheet, tone: 'sky', href: '/dashboard/tracking' },
  ];

  return (
    <div className="space-y-6 pb-12">
      {/* Hero */}
      <section className="relative overflow-hidden rounded-3xl border border-slate-800/70 bg-gradient-to-bl from-indigo-600/25 via-slate-900/70 to-slate-950 p-6 md:p-8">
        <div className="absolute inset-0 bg-grid opacity-60 pointer-events-none" />
        <div className="absolute -top-24 -right-16 w-72 h-72 rounded-full bg-violet-500/20 blur-3xl pointer-events-none" />
        <div className="relative flex flex-col lg:flex-row lg:items-center gap-8">
          <div className="flex-1 min-w-0">
            <div className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-white/5 border border-white/10 text-[11px] font-semibold text-indigo-200 mb-4">
              <Sparkles className="w-3.5 h-3.5" />
              ملخص اليوم
            </div>
            <h2 className="text-2xl md:text-3xl font-extrabold text-white tracking-tight">
              {greeting}
              {firstName ? `، ${firstName}` : ''} 👋
            </h2>
            <p className="text-sm text-slate-300/80 mt-2 max-w-xl leading-relaxed">{heroSummary}</p>

            <div className="flex flex-wrap items-center gap-2.5 mt-6">
              <Link
                href="/dashboard/employees#new"
                className="inline-flex items-center gap-2 h-10 px-4 rounded-xl bg-white text-slate-900 text-xs font-bold hover:bg-indigo-50 active:scale-[0.98] transition-all shadow-lg shadow-black/20"
              >
                <UserPlus className="w-4 h-4" />
                إضافة موظف
              </Link>
              <button
                onClick={() => setShowAnnounceModal(true)}
                className="inline-flex items-center gap-2 h-10 px-4 rounded-xl bg-white/10 border border-white/10 text-white text-xs font-bold hover:bg-white/15 active:scale-[0.98] transition-all cursor-pointer"
              >
                <Send className="w-4 h-4" />
                بث تعميم
              </button>
              <button
                onClick={query.reload}
                disabled={query.refreshing}
                className="inline-flex items-center gap-2 h-10 px-3 rounded-xl text-slate-300 text-[11px] font-semibold hover:text-white hover:bg-white/5 transition-colors cursor-pointer disabled:opacity-60"
                title="تحديث البيانات"
              >
                <RefreshCw className={cn('w-3.5 h-3.5', query.refreshing && 'animate-spin')} />
                <span>{query.refreshing ? 'جاري التحديث...' : `آخر تحديث ${timeAgo(new Date(data.syncedAt), now)}`}</span>
              </button>
            </div>
          </div>

          <div className="flex items-center gap-6 lg:pl-2">
            <AttendanceRing percent={attendanceRate} />
            <div className="space-y-3 min-w-[150px]">
              <LegendRow color="bg-emerald-400" label="حاضرون" value={stats.presentToday} />
              <LegendRow color="bg-rose-400" label="غائبون" value={stats.absentToday} />
              <LegendRow color="bg-slate-500" label="إجمالي الكادر" value={stats.employees} />
            </div>
          </div>
        </div>
      </section>

      {/* KPI cards */}
      <section className="grid grid-cols-2 lg:grid-cols-3 gap-3 md:gap-4">
        {statCards.map((card) => (
          <StatCard key={card.title} {...card} />
        ))}
      </section>

      <section className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Security center */}
        <Card className="lg:col-span-2 flex flex-col">
          <CardHeader
            icon={ShieldAlert}
            tone="rose"
            title="مركز المراقبة الأمنية"
            description="أحدث محاولات تزييف المواقع وخروقات السياج الجغرافي"
            actions={
              <Badge tone={stats.securityIncidents > 0 ? 'rose' : 'emerald'}>{stats.securityIncidents} خرق مرصود</Badge>
            }
          />
          {securityLogs.length === 0 ? (
            <EmptyState icon={ShieldCheck} tone="emerald" title="كل شيء آمن" description="لا توجد خروقات مسجلة حالياً" className="flex-grow" />
          ) : (
            <ol className="relative space-y-3 before:absolute before:top-2 before:bottom-2 before:right-[19px] before:w-px before:bg-slate-800">
              {securityLogs.map((log) => {
                const isMock = log.type === 'mock_gps';
                return (
                  <li key={log.id} className="relative flex items-start gap-4">
                    <div
                      className={cn(
                        'relative z-10 w-10 h-10 shrink-0 rounded-xl border flex items-center justify-center',
                        isMock ? 'bg-rose-950 border-rose-500/30 text-rose-400' : 'bg-amber-950 border-amber-500/30 text-amber-400',
                      )}
                    >
                      {isMock ? <MapPin className="w-[18px] h-[18px]" /> : <AlertTriangle className="w-[18px] h-[18px]" />}
                    </div>
                    <div className="flex-1 min-w-0 p-3.5 rounded-2xl bg-slate-900/50 border border-slate-800/70 hover:border-slate-700/70 transition-colors">
                      <div className="flex items-center justify-between gap-2 mb-1">
                        <h4 className="text-[13px] font-bold text-white truncate">{log.name}</h4>
                        <span className="shrink-0 text-[10px] text-slate-500 flex items-center gap-1" dir="ltr">
                          <Clock className="w-3 h-3" />
                          {formatLogTime(log.timestamp)}
                        </span>
                      </div>
                      <p className="text-xs text-slate-400 leading-relaxed">{log.details}</p>
                      {log.coords && (
                        <span className="inline-block mt-2 text-[10px] bg-slate-950 border border-slate-800 px-2 py-0.5 rounded-md font-mono text-slate-400" dir="ltr">
                          {log.coords}
                        </span>
                      )}
                    </div>
                  </li>
                );
              })}
            </ol>
          )}
        </Card>

        <div className="flex flex-col gap-6">
          <Card>
            <CardHeader title="إجراءات سريعة" description="الوصول المباشر لأكثر المهام استخداماً" className="mb-4" />
            <div className="grid grid-cols-2 gap-3">
              {quickActions.map((a) => {
                const inner = (
                  <>
                    <div className={cn('w-9 h-9 rounded-xl border flex items-center justify-center mb-3 group-hover:scale-105 transition-transform', TONE_CHIP[a.tone])}>
                      <a.icon className="w-[18px] h-[18px]" />
                    </div>
                    <p className="text-xs font-bold text-slate-100">{a.label}</p>
                    <p className="text-[10px] text-slate-500 mt-0.5">{a.hint}</p>
                  </>
                );
                const cls = 'group text-right p-3.5 rounded-2xl bg-slate-900/60 border border-slate-800/80 hover:border-slate-700 hover:bg-slate-800/40 transition-colors cursor-pointer';
                return a.href ? (
                  <Link key={a.label} href={a.href} className={cls}>
                    {inner}
                  </Link>
                ) : (
                  <button key={a.label} onClick={a.onClick} className={cls}>
                    {inner}
                  </button>
                );
              })}
            </div>
          </Card>

          <Link href="/dashboard/storage" className="group surface rounded-3xl p-5 md:p-6 flex items-center gap-4 hover:border-slate-700 transition-colors">
            <div className={cn('w-11 h-11 rounded-xl border flex items-center justify-center', TONE_CHIP.sky)}>
              <HardDrive className="w-5 h-5" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-[11px] text-slate-500 font-semibold">المساحة التخزينية المستخدمة</p>
              <p className="text-lg font-extrabold text-white mt-0.5" dir="ltr">
                {formatBytes(stats.totalStorageBytes)}
              </p>
            </div>
            <ChevronLeft className="w-5 h-5 text-slate-600 group-hover:text-slate-300 group-hover:-translate-x-0.5 transition-all" />
          </Link>
        </div>
      </section>

      {/* Absentees */}
      <Card id="absent-section" className="scroll-mt-24">
        <CardHeader
          icon={AlertTriangle}
          tone="rose"
          title={
            <>
              غيابات اليوم <Badge tone="rose">{stats.absentToday}</Badge>
            </>
          }
          description="موظفون لم يسجلوا دخولهم اليوم وغير مجازين، مقسمون حسب الفروع"
          actions={
            data.absentList.length > 0 && (
              <SearchInput value={absentSearch} onChange={setAbsentSearch} placeholder="ابحث عن موظف..." className="w-full sm:w-64" />
            )
          }
        />

        {data.absentList.length === 0 ? (
          <EmptyState icon={CheckCircle} tone="emerald" title="الجميع حاضرون!" description="لا توجد غيابات مسجلة لهذا اليوم." />
        ) : absentGroups.length === 0 ? (
          <p className="py-10 text-center text-xs text-slate-500">لا توجد نتائج مطابقة للبحث</p>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {absentGroups.map((group) => (
              <div key={group.id} className="rounded-2xl bg-slate-950/40 border border-slate-800/70 overflow-hidden flex flex-col">
                <div className="px-4 py-3 border-b border-slate-800/70 flex justify-between items-center">
                  <span className="font-bold text-[13px] text-white flex items-center gap-2 min-w-0">
                    <Building2 className="w-4 h-4 text-indigo-400 shrink-0" />
                    <span className="truncate">{group.name}</span>
                  </span>
                  <Badge tone="rose">{group.members.length} غائب</Badge>
                </div>
                <ul className="p-2 space-y-0.5 overflow-y-auto max-h-[240px]">
                  {group.members.map((emp) => (
                    <li key={emp.id} className="px-2.5 py-2 rounded-xl flex items-center gap-3 hover:bg-slate-800/40 transition-colors">
                      <Avatar name={emp.full_name} size="sm" />
                      <p className="text-xs font-semibold text-slate-200 truncate">{emp.full_name}</p>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        )}
      </Card>

      {showAnnounceModal && (
        <AnnouncementModal
          branches={data.branches}
          employees={data.employeesList}
          onClose={() => setShowAnnounceModal(false)}
        />
      )}
    </div>
  );
}

/* ----------------------------- Announcement ----------------------------- */

function AnnouncementModal({
  branches,
  employees,
  onClose,
}: {
  branches: DashboardData['branches'];
  employees: DirectoryEmployee[];
  onClose: () => void;
}) {
  const [text, setText] = useState('');
  const [targetType, setTargetType] = useState<'all' | 'branch' | 'employee'>('all');
  const [branchId, setBranchId] = useState('');
  const [employeeIds, setEmployeeIds] = useState<string[]>([]);
  const [search, setSearch] = useState('');
  const [sending, setSending] = useState(false);

  const visibleEmployees = employees.filter((e) => (e.full_name || '').toLowerCase().includes(search.toLowerCase()));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!text.trim()) return;
    setSending(true);
    try {
      let targets: string[] = [];
      if (targetType === 'all') {
        const { data: emps } = await supabase.from('employees').select('id').eq('is_active', true);
        targets = (emps ?? []).map((emp) => emp.id);
      } else if (targetType === 'branch') {
        if (!branchId) {
          toast.error('يرجى اختيار الفرع المستهدف أولاً');
          return;
        }
        const { data: emps } = await supabase.from('employees').select('id').eq('branch_id', branchId).eq('is_active', true);
        targets = (emps ?? []).map((emp) => emp.id);
      } else {
        if (employeeIds.length === 0) {
          toast.error('يرجى اختيار موظف واحد على الأقل');
          return;
        }
        targets = employeeIds;
      }

      if (targets.length === 0) {
        toast('لم يتم العثور على موظفين مستهدفين لإرسال هذا التعميم');
        return;
      }

      const title = 'تعميم إداري هام 📢';
      const { error: notifErr } = await supabase.from('notifications').insert(
        targets.map((employee_id) => ({ employee_id, title, body: text, type: 'memo', is_read: false })),
      );
      if (notifErr) throw notifErr;

      const {
        data: { session },
      } = await supabase.auth.getSession();
      await supabase.from('announcements').insert({ title, content: text, is_pinned: false, created_by: session?.user?.id || null });

      confetti({ particleCount: 80, spread: 60, origin: { y: 0.8 } });
      toast.success(`تم إرسال التعميم إلى ${targets.length} موظف`);
      onClose();
    } catch (err) {
      toast.error(`فشل إرسال التعميم: ${errorMessage(err)}`);
    } finally {
      setSending(false);
    }
  };

  return (
    <Modal title="بث تعميم إداري" subtitle="يصل التعميم فوراً كإشعار على هواتف الموظفين المستهدفين" icon={Send} tone="brand" onClose={onClose}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="المستلمون">
          <SegmentedTabs
            value={targetType}
            onChange={setTargetType}
            className="w-full"
            options={[
              { value: 'all', label: 'الكل' },
              { value: 'branch', label: 'فرع معين' },
              { value: 'employee', label: 'موظفون محددون', count: employeeIds.length || undefined },
            ]}
          />
        </Field>

        {targetType === 'branch' && (
          <Field label="الفرع المستهدف">
            <Select value={branchId} onChange={(e) => setBranchId(e.target.value)} required>
              <option value="">اختر الفرع...</option>
              {branches.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name}
                </option>
              ))}
            </Select>
          </Field>
        )}

        {targetType === 'employee' && (
          <Field label={`الموظفون المستهدفون (${employeeIds.length} محدد)`}>
            <SearchInput value={search} onChange={setSearch} placeholder="ابحث باسم الموظف..." className="mb-2" />
            <div className="max-h-[180px] overflow-y-auto border border-slate-800 rounded-xl p-1.5 bg-slate-950/50">
              {visibleEmployees.map((emp) => {
                const checked = employeeIds.includes(emp.id);
                return (
                  <label
                    key={emp.id}
                    className={cn(
                      'flex items-center gap-2.5 px-2.5 py-2 rounded-lg text-xs cursor-pointer transition-colors',
                      checked ? 'bg-indigo-500/10 text-white' : 'text-slate-300 hover:bg-slate-800/50',
                    )}
                  >
                    <input
                      type="checkbox"
                      checked={checked}
                      onChange={() =>
                        setEmployeeIds((prev) => (checked ? prev.filter((id) => id !== emp.id) : [...prev, emp.id]))
                      }
                      className="w-4 h-4 rounded"
                    />
                    {emp.full_name}
                  </label>
                );
              })}
            </div>
          </Field>
        )}

        <Field label="نص التعميم">
          <Textarea value={text} onChange={(e) => setText(e.target.value)} required rows={4} placeholder="اكتب نص التعميم هنا..." />
        </Field>

        <ModalFooter onCancel={onClose} loading={sending} submitLabel="إرسال التعميم" loadingLabel="جاري الإرسال..." submitIcon={Send} />
      </form>
    </Modal>
  );
}

/* ----------------------------- UI helpers ----------------------------- */

interface StatCardProps {
  title: string;
  value: number;
  subtitle: string;
  icon: LucideIcon;
  tone: Tone;
  href: string;
  attention?: boolean;
}

const GLOW: Partial<Record<Tone, string>> = {
  indigo: 'from-indigo-500/15',
  emerald: 'from-emerald-500/15',
  rose: 'from-rose-500/15',
  amber: 'from-amber-500/15',
  sky: 'from-sky-500/15',
  violet: 'from-violet-500/15',
};

function StatCard({ title, value, subtitle, icon: Icon, tone, href, attention }: StatCardProps) {
  return (
    <Link href={href} className="group relative overflow-hidden surface rounded-2xl p-4 md:p-5 hover:border-slate-700 hover:-translate-y-0.5 transition-all duration-200">
      <div className={cn('absolute inset-0 bg-gradient-to-bl to-transparent to-60% opacity-0 group-hover:opacity-100 transition-opacity duration-300 pointer-events-none', GLOW[tone])} />
      <div className="relative flex items-start justify-between gap-2">
        <div className={cn('w-10 h-10 rounded-xl border flex items-center justify-center', TONE_CHIP[tone])}>
          <Icon className="w-5 h-5" />
        </div>
        {attention ? (
          <span className="flex items-center gap-1 text-[10px] font-bold text-amber-300 bg-amber-400/10 border border-amber-400/20 px-2 py-0.5 rounded-full">
            <span className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" />
            <span className="hidden sm:inline">يتطلب إجراء</span>
          </span>
        ) : (
          <ChevronLeft className="w-4 h-4 text-slate-600 group-hover:text-slate-300 group-hover:-translate-x-0.5 transition-all" />
        )}
      </div>
      <div className="relative mt-4">
        <p className="text-2xl md:text-3xl font-extrabold tracking-tight text-white">{value.toLocaleString('en-US')}</p>
        <p className="text-xs font-bold text-slate-300 mt-1">{title}</p>
        <p className="text-[10px] md:text-[11px] text-slate-500 mt-0.5 truncate">{subtitle}</p>
      </div>
    </Link>
  );
}

function AttendanceRing({ percent }: { percent: number }) {
  const r = 52;
  const c = 2 * Math.PI * r;
  const offset = c - (Math.min(Math.max(percent, 0), 100) / 100) * c;
  return (
    <div className="relative w-36 h-36 shrink-0">
      <svg viewBox="0 0 128 128" className="w-full h-full -rotate-90">
        <defs>
          <linearGradient id="ringGrad" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stopColor="#34D399" />
            <stop offset="100%" stopColor="#22D3EE" />
          </linearGradient>
        </defs>
        <circle cx="64" cy="64" r={r} fill="none" stroke="rgb(255 255 255 / 0.08)" strokeWidth="10" />
        <circle
          cx="64"
          cy="64"
          r={r}
          fill="none"
          stroke="url(#ringGrad)"
          strokeWidth="10"
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={offset}
          style={{ transition: 'stroke-dashoffset 0.9s cubic-bezier(0.16, 1, 0.3, 1)' }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="text-3xl font-extrabold text-white" dir="ltr">
          {percent}%
        </span>
        <span className="text-[10px] font-semibold text-slate-400">نسبة الحضور</span>
      </div>
    </div>
  );
}

function LegendRow({ color, label, value }: { color: string; label: string; value: number }) {
  return (
    <div className="flex items-center gap-3">
      <span className={cn('w-2.5 h-2.5 rounded-full', color)} />
      <span className="flex-1 text-xs text-slate-300">{label}</span>
      <span className="text-sm font-extrabold text-white">{value.toLocaleString('en-US')}</span>
    </div>
  );
}

function DashboardSkeleton() {
  return (
    <div className="space-y-6" aria-busy="true">
      <div className="skeleton h-44 rounded-3xl" />
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-4">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="skeleton h-32 rounded-2xl" />
        ))}
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="skeleton h-80 rounded-3xl lg:col-span-2" />
        <div className="skeleton h-80 rounded-3xl" />
      </div>
    </div>
  );
}

function formatLogTime(ts: string) {
  const d = new Date(ts);
  if (isNaN(d.getTime())) return 'غير محدد';
  const time = d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
  return d.toDateString() === new Date().toDateString()
    ? time
    : `${d.toLocaleDateString('en-GB', { day: '2-digit', month: '2-digit' })} · ${time}`;
}
