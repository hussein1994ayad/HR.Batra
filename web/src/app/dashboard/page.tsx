'use client';

// الصفحة الرئيسية (نظرة عامة): ملخص اليوم، مؤشرات الطلبات، مركز المراقبة، إجراءات سريعة، وغيابات اليوم.
// البيانات في features/overview/api (كاش يظهر فوراً ثم تحديث)، والحسابات في features/overview/logic.

import { useEffect, useState } from 'react';
import Link from 'next/link';
import {
  Users,
  CalendarRange,
  Coins,
  Smartphone,
  HardDrive,
  UserPlus,
  Send,
  AlertTriangle,
  CheckCircle,
  FileSpreadsheet,
  RefreshCw,
  Banknote,
  ChevronLeft,
  Sparkles,
  type LucideIcon,
} from 'lucide-react';
import { readCache, useQuery } from '@/lib/useQuery';
import { errorMessage, formatBytes, timeAgo } from '@/lib/format';
import { Card, CardHeader, EmptyState, TONE_CHIP, cn, type Tone } from '@/components/ui';
import { DASHBOARD_CACHE_KEY, fetchDashboard, isDashboardData, type DashboardData } from '@/features/overview/api';
import { AnnouncementModal } from '@/features/overview/components/AnnouncementModal';
import { clearAnnouncementDraft, peekAnnouncementDraft } from '@/features/assistant/draft';
import { AbsentTodayCard } from '@/features/overview/components/AbsentTodayCard';
import { SecurityCenter } from '@/features/overview/components/SecurityCenter';
import {
  AttendanceRing,
  DashboardSkeleton,
  LegendRow,
  StatCard,
  type StatCardProps,
} from '@/features/overview/components/OverviewWidgets';

export default function DashboardPage() {
  const [cached] = useState(() => {
    const c = readCache<DashboardData>(DASHBOARD_CACHE_KEY);
    return isDashboardData(c) ? c : undefined;
  });
  const [adminName] = useState(() => readCache<{ name?: string }>('batra_cache_admin')?.name ?? '');
  const query = useQuery('dashboard', fetchDashboard, cached);
  // مسودة من المساعد الذكي («فتح كتعميم»): النافذة تنفتح والنص جاهز، والنشر بيد الأدمن
  const [draft, setDraft] = useState(() => (typeof window === 'undefined' ? null : peekAnnouncementDraft()));
  const [showAnnounceModal, setShowAnnounceModal] = useState(() => typeof window !== 'undefined' && peekAnnouncementDraft() !== null);
  const [now, setNow] = useState(() => Date.now());

  // Keep the "last synced" label fresh.
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 30000);
    return () => clearInterval(t);
  }, []);

  const data = query.data;

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
    // ماكو أحد عنده دوام اليوم (جمعة/عطلة) = عطلة، مو "الجميع حضروا"
    tracked === 0 ? 'واليوم عطلة، ماكو دوام.' : stats.absentToday > 0 ? `و${stats.absentToday} موظف لم يسجلوا حضورهم بعد.` : 'والجميع سجلوا حضورهم اليوم.',
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
        <SecurityCenter securityLogs={securityLogs} incidents={stats.securityIncidents} />

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

      <AbsentTodayCard data={data} tracked={tracked} />

      {showAnnounceModal && (
        <AnnouncementModal
          branches={data.branches}
          employees={data.employeesList}
          initialTitle={draft?.title}
          initialText={draft?.body}
          onClose={() => {
            setShowAnnounceModal(false);
            setDraft(null);
            clearAnnouncementDraft();
          }}
        />
      )}
    </div>
  );
}
