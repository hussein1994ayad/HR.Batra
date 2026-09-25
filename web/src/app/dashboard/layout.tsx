'use client';

import React, { useState, useEffect, useMemo, useRef, useCallback } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { Toaster } from 'react-hot-toast';
import Link from 'next/link';
import {
  LayoutDashboard,
  Users,
  MapPin,
  Settings,
  LogOut,
  Menu,
  X,
  ShieldAlert,
  Trash2,
  HardDrive,
  CalendarRange,
  Coins,
  Bell,
  Banknote,
  Search,
  ChevronsRight,
  ChevronsLeft,
  CornerDownLeft,
  CheckCheck,
  Sparkles,
  Inbox,
} from 'lucide-react';

interface SidebarItem {
  name: string;
  description: string;
  href: string;
  icon: React.ComponentType<any>;
  badgeKey?: 'leaves' | 'loans';
}

interface SidebarGroup {
  label: string;
  items: SidebarItem[];
}

const NAV_GROUPS: SidebarGroup[] = [
  {
    label: 'الرئيسية',
    items: [
      { name: 'نظرة عامة', description: 'ملخص فوري لحالة الكادر والحضور والتنبيهات', href: '/dashboard', icon: LayoutDashboard },
    ],
  },
  {
    label: 'الموارد البشرية',
    items: [
      { name: 'الموظفون والأجهزة', description: 'دليل الموظفين، البيانات الشخصية واعتماد الأجهزة', href: '/dashboard/employees', icon: Users },
      { name: 'الحضور والتتبع', description: 'سجلات الحضور والانصراف والتتبع المباشر على الخريطة', href: '/dashboard/tracking', icon: MapPin },
      { name: 'السياج الجغرافي', description: 'تخطيط وإدارة مناطق العمل المسموح بها', href: '/dashboard/geofences', icon: ShieldAlert },
      { name: 'الإجازات', description: 'مراجعة واعتماد طلبات الإجازات الزمنية واليومية', href: '/dashboard/leaves', icon: CalendarRange, badgeKey: 'leaves' },
    ],
  },
  {
    label: 'المالية',
    items: [
      { name: 'السلف والأقساط', description: 'طلبات السلف وجدولة الأقساط الشهرية', href: '/dashboard/loans', icon: Coins, badgeKey: 'loans' },
      { name: 'الرواتب والمكافآت', description: 'احتساب الرواتب والاستقطاعات والمكافآت', href: '/dashboard/payroll', icon: Banknote },
    ],
  },
  {
    label: 'النظام',
    items: [
      { name: 'سلة المحذوفات', description: 'استعادة أو حذف الملفات نهائياً', href: '/dashboard/trash', icon: Trash2 },
      { name: 'التخزين', description: 'تحليلات المساحة المستخدمة في الـ Buckets', href: '/dashboard/storage', icon: HardDrive },
      { name: 'الإعدادات', description: 'إعدادات الشركة، الفروع، الأقسام وجداول الدوام', href: '/dashboard/settings', icon: Settings },
    ],
  },
];

const ALL_ITEMS = NAV_GROUPS.flatMap((g) => g.items);

class ErrorBoundary extends React.Component<
  { children: React.ReactNode },
  { hasError: boolean; error: Error | null }
> {
  constructor(props: any) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: any) {
    console.error("Dashboard Boundary caught an error:", error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="p-8 surface rounded-3xl text-right max-w-2xl mx-auto my-12 text-slate-100 animate-glass border-rose-500/30">
          <div className="flex items-center gap-3 mb-4">
            <div className="p-2.5 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400">
              <ShieldAlert className="w-5 h-5" />
            </div>
            <h2 className="text-lg font-bold text-rose-300">حدث خطأ غير متوقع في لوحة التحكم</h2>
          </div>
          <p className="text-sm text-slate-300 mb-6 leading-relaxed">
            لقد حدث خطأ أثناء معالجة أو عرض البيانات. يمكنك مسح البيانات المؤقتة وإعادة المحاولة بالضغط على الزر أدناه:
          </p>
          <pre className="p-4 bg-slate-950 rounded-2xl text-xs font-mono text-rose-300 overflow-x-auto whitespace-pre-wrap text-left mb-6 max-h-60 overflow-y-auto" dir="ltr">
            {this.state.error?.toString()}
            {"\n\nStack Trace:\n"}
            {this.state.error?.stack}
          </pre>
          <div className="flex flex-wrap gap-3">
            <button
              onClick={() => {
                localStorage.removeItem('batra_cache_dashboard');
                localStorage.removeItem('batra_cache_admin');
                window.location.reload();
              }}
              className="px-5 py-2.5 bg-rose-600 hover:bg-rose-500 text-white rounded-xl text-xs font-bold transition-all cursor-pointer active:scale-95"
            >
              مسح الذاكرة المؤقتة وإعادة التحميل
            </button>
            <button
              onClick={() => window.location.reload()}
              className="px-5 py-2.5 bg-slate-800 hover:bg-slate-700 text-white rounded-xl text-xs font-bold transition-all cursor-pointer active:scale-95"
            >
              إعادة المحاولة
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}

function useClickOutside(ref: React.RefObject<HTMLElement | null>, onOutside: () => void, active: boolean) {
  useEffect(() => {
    if (!active) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) onOutside();
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [ref, onOutside, active]);
}

function initialsOf(name: string) {
  const parts = (name || 'مدير').trim().split(/\s+/);
  if (parts.length >= 2) return parts[0][0] + parts[1][0];
  return (parts[0] || 'م').substring(0, 2);
}

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [loading, setLoading] = useState(true);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(false);
  const [adminUser, setAdminUser] = useState<any>(null);
  const [adminName, setAdminName] = useState<string>('مدير النظام');
  const [pendingLeaves, setPendingLeaves] = useState(0);
  const [pendingLoans, setPendingLoans] = useState(0);
  const [showNotifications, setShowNotifications] = useState(false);
  const [showLogoutConfirm, setShowLogoutConfirm] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(false);

  const [systemNotifs, setSystemNotifs] = useState<any[]>([]);

  const notifRef = useRef<HTMLDivElement>(null);
  const closeNotifications = useCallback(() => setShowNotifications(false), []);
  useClickOutside(notifRef, closeNotifications, showNotifications);

  // Restore collapsed sidebar preference
  useEffect(() => {
    try {
      // Read after mount so the statically exported markup hydrates without mismatch
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setCollapsed(localStorage.getItem('batra_sidebar_collapsed') === '1');
    } catch {}
  }, []);

  const toggleCollapsed = () => {
    setCollapsed((prev) => {
      try { localStorage.setItem('batra_sidebar_collapsed', prev ? '0' : '1'); } catch {}
      return !prev;
    });
  };

  // Global keyboard shortcuts: Ctrl/⌘+K opens the quick navigator, Esc closes overlays
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setPaletteOpen((v) => !v);
      } else if (e.key === 'Escape') {
        setShowNotifications(false);
        setSidebarOpen(false);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  useEffect(() => {
    const checkAuth = async () => {
      try {
        // 1. Try to load cached admin session instantly to avoid blocking UI
        const cachedAdmin = localStorage.getItem('batra_cache_admin');
        if (cachedAdmin) {
          try {
            const parsed = JSON.parse(cachedAdmin);
            if (parsed) {
              if (parsed.user) setAdminUser(parsed.user);
              if (parsed.name) setAdminName(parsed.name);
              setPendingLeaves(parsed.pendingLeaves || 0);
              setPendingLoans(parsed.pendingLoans || 0);
              setLoading(false); // Render layout instantly!
            }
          } catch (e) {
            console.error('Error parsing admin cache:', e);
          }
        }

        const { data: { session } } = await supabase.auth.getSession();
        if (!session) {
          localStorage.removeItem('batra_cache_admin');
          router.replace('/login');
          return;
        }

        // Verify role in employee table
        const { data: emp, error } = await supabase
          .from('employees')
          .select('full_name, role')
          .eq('id', session.user.id)
          .single();

        if (error || !emp || (emp.role !== 'admin' && emp.role !== 'manager')) {
          localStorage.removeItem('batra_cache_admin');
          await supabase.auth.signOut();
          router.replace('/login');
          return;
        }

        setAdminUser(session.user);
        setAdminName(emp.full_name);

        // Fetch notification counts and unread notifications concurrently
        const [
          { count: leavesCount },
          { count: loansCount },
          { data: unreadNotifs }
        ] = await Promise.all([
          supabase.from('leave_requests').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
          supabase.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
          supabase.from('notifications').select('*').eq('employee_id', session.user.id).eq('is_read', false).order('created_at', { ascending: false })
        ]);

        setPendingLeaves(leavesCount || 0);
        setPendingLoans(loansCount || 0);
        if (unreadNotifs) setSystemNotifs(unreadNotifs);

        // Save session cache for next instant rendering
        localStorage.setItem('batra_cache_admin', JSON.stringify({
          user: session.user,
          name: emp.full_name,
          pendingLeaves: leavesCount || 0,
          pendingLoans: loansCount || 0
        }));

        setLoading(false);
      } catch (err) {
        localStorage.removeItem('batra_cache_admin');
        router.replace('/login');
      }
    };

    checkAuth();
  }, [router]);

  const playBeep = () => {
    try {
      const AudioContextClass = window.AudioContext || (window as any).webkitAudioContext;
      if (!AudioContextClass) return;
      const ctx = new AudioContextClass();
      const osc = ctx.createOscillator();
      const gainNode = ctx.createGain();
      osc.connect(gainNode);
      gainNode.connect(ctx.destination);
      osc.type = 'sine';
      osc.frequency.setValueAtTime(880, ctx.currentTime);
      gainNode.gain.setValueAtTime(0.1, ctx.currentTime);
      osc.start();
      gainNode.gain.exponentialRampToValueAtTime(0.00001, ctx.currentTime + 0.5);
      osc.stop(ctx.currentTime + 0.5);
    } catch (e) {
      console.log('Audio playback failed:', e);
    }
  };

  useEffect(() => {
    if (!adminUser) return;

    const channelLeaves = supabase
      .channel('schema-db-changes-leaves')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'leave_requests'
        },
        async (payload) => {
          const { count } = await supabase
            .from('leave_requests')
            .select('*', { count: 'exact', head: true })
            .eq('status', 'pending');
          setPendingLeaves(count || 0);

          if (payload.eventType === 'INSERT') {
            playBeep();
          }
        }
      )
      .subscribe();

    const channelLoans = supabase
      .channel('schema-db-changes-loans')
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'loans'
        },
        async (payload) => {
          const { count } = await supabase
            .from('loans')
            .select('*', { count: 'exact', head: true })
            .eq('status', 'pending');
          setPendingLoans(count || 0);

          if (payload.eventType === 'INSERT') {
            playBeep();
          }
        }
      )
      .subscribe();

    const channelNotifs = supabase
      .channel('schema-db-changes-notifications')
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'notifications',
          filter: `employee_id=eq.${adminUser.id}`
        },
        async (payload) => {
          if (payload.new) {
            setSystemNotifs(prev => [payload.new, ...prev]);
            playBeep();
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channelLeaves);
      supabase.removeChannel(channelLoans);
      supabase.removeChannel(channelNotifs);
    };
  }, [adminUser]);

  const handleLogout = async () => {
    setShowLogoutConfirm(false);
    localStorage.removeItem('batra_cache_admin');
    localStorage.removeItem('batra_cache_dashboard');
    await supabase.auth.signOut();
    router.replace('/login');
  };

  const markAllNotifsRead = async () => {
    if (!adminUser || systemNotifs.length === 0) return;
    const ids = systemNotifs.map((n) => n.id).filter(Boolean);
    setSystemNotifs([]);
    if (ids.length > 0) {
      const { error } = await supabase.from('notifications').update({ is_read: true }).in('id', ids);
      if (error) console.error('Failed to mark notifications as read:', error);
    }
  };

  const badgeFor = (item: SidebarItem) => {
    if (item.badgeKey === 'leaves') return pendingLeaves;
    if (item.badgeKey === 'loans') return pendingLoans;
    return 0;
  };

  const activeItem = useMemo(() => {
    // Longest matching prefix wins so nested routes keep their parent highlighted
    return [...ALL_ITEMS]
      .sort((a, b) => b.href.length - a.href.length)
      .find((item) => pathname === item.href || (item.href !== '/dashboard' && pathname?.startsWith(item.href + '/')));
  }, [pathname]);

  const totalNotifs = pendingLeaves + pendingLoans + systemNotifs.length;
  const roleLabel = adminUser?.email === 'admin@hrpro.com' ? 'مسؤول النظام' : 'مدير الموارد';

  const renderNav = (isCollapsed: boolean) => (
    <nav className="flex-1 px-3 py-4 overflow-y-auto no-scrollbar">
      {NAV_GROUPS.map((group) => (
        <div key={group.label} className="mb-5 last:mb-0">
          {isCollapsed ? (
            <div className="mx-auto mb-2 h-px w-6 bg-slate-800" />
          ) : (
            <p className="px-3 mb-2 text-[10px] font-bold tracking-wider text-slate-500">{group.label}</p>
          )}
          <div className="space-y-0.5">
            {group.items.map((item) => {
              const isActive = activeItem?.href === item.href;
              const Icon = item.icon;
              const badge = badgeFor(item);
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  prefetch
                  title={isCollapsed ? item.name : undefined}
                  aria-current={isActive ? 'page' : undefined}
                  onClick={() => setSidebarOpen(false)}
                  className={`group relative flex items-center gap-3 rounded-xl text-[13px] font-semibold transition-colors duration-150 ${
                    isCollapsed ? 'justify-center h-11 w-11 mx-auto' : 'px-3 py-2.5'
                  } ${
                    isActive
                      ? 'bg-indigo-500/12 text-white'
                      : 'text-slate-400 hover:text-slate-100 hover:bg-slate-800/50'
                  }`}
                >
                  {isActive && (
                    <span className="absolute right-0 top-1/2 -translate-y-1/2 h-6 w-[3px] rounded-l-full bg-gradient-to-b from-indigo-400 to-violet-500 shadow-[0_0_12px_rgba(129,140,248,0.8)]" />
                  )}
                  <Icon className={`w-[18px] h-[18px] shrink-0 transition-colors ${isActive ? 'text-indigo-300' : 'text-slate-500 group-hover:text-slate-300'}`} />
                  {!isCollapsed && <span className="flex-1 truncate">{item.name}</span>}
                  {badge > 0 && (
                    isCollapsed ? (
                      <span className="absolute top-1.5 left-1.5 w-2 h-2 rounded-full bg-amber-400 ring-2 ring-slate-950" />
                    ) : (
                      <span className="min-w-5 h-5 px-1.5 rounded-full bg-amber-400/15 text-amber-300 border border-amber-400/25 text-[10px] font-bold flex items-center justify-center" dir="ltr">
                        {badge > 99 ? '99+' : badge}
                      </span>
                    )
                  )}
                </Link>
              );
            })}
          </div>
        </div>
      ))}
    </nav>
  );

  const renderBrand = (isCollapsed: boolean) => (
    <Link href="/dashboard" className={`flex items-center gap-3 ${isCollapsed ? 'justify-center' : ''}`}>
      <div className="relative w-9 h-9 shrink-0 rounded-xl bg-gradient-to-br from-indigo-500 via-violet-500 to-fuchsia-500 flex items-center justify-center shadow-lg shadow-indigo-500/30">
        <Sparkles className="w-[18px] h-[18px] text-white" />
        <span className="absolute inset-0 rounded-xl ring-1 ring-inset ring-white/20" />
      </div>
      {!isCollapsed && (
        <div className="min-w-0">
          <h2 className="font-extrabold text-white text-[15px] leading-tight">HR Pro</h2>
          <p className="text-[10px] text-slate-500 font-medium">لوحة تحكم الإدارة</p>
        </div>
      )}
    </Link>
  );

  const renderUserCard = (isCollapsed: boolean) => (
    <div className={`p-3 border-t border-slate-800/70 ${isCollapsed ? 'flex flex-col items-center gap-2' : ''}`}>
      <div className={`flex items-center gap-3 ${isCollapsed ? '' : 'p-2 rounded-xl bg-slate-900/60 border border-slate-800/70'}`}>
        <div
          title={isCollapsed ? adminName : undefined}
          className="w-9 h-9 shrink-0 rounded-lg bg-gradient-to-br from-slate-700 to-slate-800 border border-slate-700 flex items-center justify-center font-bold text-slate-100 text-xs"
        >
          {initialsOf(adminName)}
        </div>
        {!isCollapsed && (
          <div className="flex-1 min-w-0">
            <h4 className="text-xs font-bold text-white truncate">{adminName}</h4>
            <span className="text-[10px] text-indigo-300/90 font-semibold">{roleLabel}</span>
          </div>
        )}
        {!isCollapsed && (
          <button
            onClick={() => setShowLogoutConfirm(true)}
            title="تسجيل الخروج"
            className="p-2 rounded-lg text-slate-500 hover:text-rose-400 hover:bg-rose-500/10 transition-colors cursor-pointer"
          >
            <LogOut className="w-4 h-4" />
          </button>
        )}
      </div>
      {isCollapsed && (
        <button
          onClick={() => setShowLogoutConfirm(true)}
          title="تسجيل الخروج"
          className="p-2.5 rounded-lg text-slate-500 hover:text-rose-400 hover:bg-rose-500/10 transition-colors cursor-pointer"
        >
          <LogOut className="w-4 h-4" />
        </button>
      )}
    </div>
  );

  const todayLabel = useMemo(() => {
    try {
      return new Date().toLocaleDateString('ar-IQ-u-nu-latn', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
    } catch {
      return new Date().toDateString();
    }
  }, []);

  return (
    <div className="flex h-dvh bg-dark-bg overflow-hidden text-slate-100 font-sans" dir="rtl">
      <Toaster position="top-center" reverseOrder={false} toastOptions={{
        style: {
          background: '#111729',
          color: '#EEF2F8',
          fontFamily: 'var(--font-cairo), sans-serif',
          fontWeight: 600,
          fontSize: '13px',
          borderRadius: '14px',
          border: '1px solid rgba(139,152,174,0.18)',
          boxShadow: '0 16px 40px -12px rgba(0,0,0,0.6)',
        }
      }} />

      {/* Ambient background */}
      <div className="pointer-events-none fixed inset-0 overflow-hidden">
        <div className="absolute -top-40 right-1/4 w-[640px] h-[640px] bg-indigo-600/[0.07] rounded-full blur-[140px]" />
        <div className="absolute -bottom-48 left-0 w-[520px] h-[520px] bg-violet-600/[0.06] rounded-full blur-[140px]" />
      </div>

      {/* Sidebar - Desktop */}
      <aside
        className={`hidden lg:flex lg:flex-col relative z-20 shrink-0 bg-slate-950/70 backdrop-blur-xl border-l border-slate-800/70 transition-[width] duration-300 ease-out ${
          collapsed ? 'w-[76px]' : 'w-64'
        }`}
      >
        <div className={`h-16 flex items-center border-b border-slate-800/70 ${collapsed ? 'justify-center px-2' : 'px-5'}`}>
          {renderBrand(collapsed)}
        </div>

        {renderNav(collapsed)}

        <button
          onClick={toggleCollapsed}
          title={collapsed ? 'توسيع القائمة' : 'طي القائمة'}
          className="absolute top-20 -left-3 w-6 h-6 rounded-full bg-slate-900 border border-slate-700 text-slate-400 hover:text-white hover:border-indigo-500/60 flex items-center justify-center shadow-lg transition-colors cursor-pointer"
        >
          {collapsed ? <ChevronsLeft className="w-3.5 h-3.5" /> : <ChevronsRight className="w-3.5 h-3.5" />}
        </button>

        {renderUserCard(collapsed)}
      </aside>

      {/* Sidebar - Mobile / Tablet */}
      <div
        className={`fixed inset-0 bg-black/60 backdrop-blur-sm z-30 lg:hidden transition-opacity duration-300 ${sidebarOpen ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
        onClick={() => setSidebarOpen(false)}
      />
      <aside
        className={`fixed inset-y-0 right-0 w-72 max-w-[85vw] bg-slate-950 border-l border-slate-800/70 z-40 flex flex-col transition-transform duration-300 ease-out lg:hidden ${
          sidebarOpen ? 'translate-x-0' : 'translate-x-full'
        }`}
      >
        <div className="h-16 px-5 border-b border-slate-800/70 flex items-center justify-between">
          {renderBrand(false)}
          <button
            onClick={() => setSidebarOpen(false)}
            className="p-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800/60 cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
        {renderNav(false)}
        {renderUserCard(false)}
      </aside>

      {/* Main Content Area */}
      <div className="relative flex-1 flex flex-col h-full min-w-0 overflow-hidden">

        {/* Top Header */}
        <header className="h-16 shrink-0 border-b border-slate-800/70 bg-slate-950/50 backdrop-blur-xl px-4 md:px-6 flex items-center justify-between gap-3 z-10">
          <div className="flex items-center gap-3 min-w-0">
            <button
              onClick={() => setSidebarOpen(true)}
              className="p-2 rounded-xl text-slate-400 hover:text-white hover:bg-slate-800/60 lg:hidden transition-colors cursor-pointer"
              aria-label="فتح القائمة"
            >
              <Menu className="w-5 h-5" />
            </button>

            <div className="min-w-0">
              <h1 className="text-[15px] md:text-base font-extrabold text-white truncate">
                {activeItem?.name || 'لوحة الإدارة'}
              </h1>
              <p className="hidden md:block text-[11px] text-slate-500 truncate">
                {activeItem?.description}
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            {/* Quick navigator */}
            <button
              onClick={() => setPaletteOpen(true)}
              className="hidden sm:flex items-center gap-2 h-9 pl-2 pr-3 w-56 xl:w-64 rounded-xl bg-slate-900/70 border border-slate-800 hover:border-slate-700 text-slate-500 hover:text-slate-300 text-xs transition-colors cursor-pointer"
            >
              <Search className="w-4 h-4 shrink-0" />
              <span className="flex-1 text-right">بحث سريع وانتقال...</span>
              <kbd className="font-mono text-[10px] px-1.5 py-0.5 rounded-md bg-slate-800 border border-slate-700 text-slate-400" dir="ltr">Ctrl K</kbd>
            </button>
            <button
              onClick={() => setPaletteOpen(true)}
              className="sm:hidden p-2 rounded-xl text-slate-400 hover:text-white hover:bg-slate-800/60 cursor-pointer"
              aria-label="بحث"
            >
              <Search className="w-5 h-5" />
            </button>

            <div className="hidden xl:flex items-center gap-2 h-9 px-3 rounded-xl text-[11px] text-slate-400 border border-slate-800/80 bg-slate-900/40">
              <span className="relative flex w-2 h-2">
                <span className="absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-60 animate-ping" />
                <span className="relative inline-flex w-2 h-2 rounded-full bg-emerald-400" />
              </span>
              <span className="font-semibold">{todayLabel}</span>
            </div>

            {/* Notifications */}
            <div className="relative" ref={notifRef}>
              <button
                onClick={() => setShowNotifications(!showNotifications)}
                className={`relative h-9 w-9 flex items-center justify-center rounded-xl border transition-colors cursor-pointer ${
                  showNotifications
                    ? 'bg-slate-800 border-slate-700 text-white'
                    : 'bg-slate-900/60 border-slate-800 text-slate-400 hover:text-white hover:border-slate-700'
                }`}
                aria-label="الإشعارات"
              >
                <Bell className="w-[18px] h-[18px]" />
                {totalNotifs > 0 && (
                  <span className="absolute -top-1.5 -left-1.5 min-w-[18px] h-[18px] px-1 rounded-full bg-rose-500 text-white text-[10px] font-bold flex items-center justify-center ring-2 ring-slate-950" dir="ltr">
                    {totalNotifs > 9 ? '9+' : totalNotifs}
                  </span>
                )}
              </button>

              {showNotifications && (
                <div className="absolute top-full left-0 mt-2 w-[min(22rem,calc(100vw-2rem))] surface-solid rounded-2xl shadow-2xl overflow-hidden z-50 text-right animate-glass">
                  <div className="px-4 py-3 border-b border-slate-800/80 flex items-center justify-between">
                    <h3 className="text-sm font-bold text-white">الإشعارات والمهام</h3>
                    {systemNotifs.length > 0 && (
                      <button
                        onClick={markAllNotifsRead}
                        className="flex items-center gap-1 text-[11px] font-semibold text-indigo-300 hover:text-indigo-200 cursor-pointer"
                      >
                        <CheckCheck className="w-3.5 h-3.5" />
                        تحديد الكل كمقروء
                      </button>
                    )}
                  </div>
                  <div className="p-2 max-h-96 overflow-y-auto">
                    {totalNotifs === 0 ? (
                      <div className="py-10 flex flex-col items-center text-center">
                        <div className="p-3 rounded-2xl bg-slate-800/60 text-slate-500 mb-3"><Inbox className="w-6 h-6" /></div>
                        <p className="text-xs font-semibold text-slate-300">لا توجد إشعارات جديدة</p>
                        <p className="text-[11px] text-slate-500 mt-1">كل شيء على ما يرام</p>
                      </div>
                    ) : (
                      <>
                        {pendingLeaves > 0 && (
                          <Link href="/dashboard/leaves" onClick={closeNotifications} className="flex items-center gap-3 p-3 hover:bg-slate-800/60 rounded-xl transition-colors">
                            <div className="p-2 bg-amber-500/10 border border-amber-500/20 text-amber-400 rounded-lg"><CalendarRange className="w-4 h-4" /></div>
                            <div className="flex-1">
                              <p className="text-xs font-bold text-white">طلبات إجازة معلقة</p>
                              <p className="text-[11px] text-slate-400">تحتاج إلى مراجعة واعتماد</p>
                            </div>
                            <span className="text-[11px] font-bold text-amber-300">{pendingLeaves}</span>
                          </Link>
                        )}
                        {pendingLoans > 0 && (
                          <Link href="/dashboard/loans" onClick={closeNotifications} className="flex items-center gap-3 p-3 hover:bg-slate-800/60 rounded-xl transition-colors">
                            <div className="p-2 bg-teal-500/10 border border-teal-500/20 text-teal-400 rounded-lg"><Coins className="w-4 h-4" /></div>
                            <div className="flex-1">
                              <p className="text-xs font-bold text-white">طلبات سلف معلقة</p>
                              <p className="text-[11px] text-slate-400">بانتظار الاعتماد المالي</p>
                            </div>
                            <span className="text-[11px] font-bold text-teal-300">{pendingLoans}</span>
                          </Link>
                        )}

                        {systemNotifs.length > 0 && (
                          <div className="pt-2 mt-1 border-t border-slate-800/60">
                            <p className="text-[10px] text-slate-500 font-bold px-2 py-1.5">إشعارات النظام ({systemNotifs.length})</p>
                            {systemNotifs.map((notif, idx) => (
                              <div key={notif.id ?? idx} className="flex gap-2.5 p-3 hover:bg-slate-800/50 rounded-xl transition-colors">
                                <span className="mt-1.5 w-1.5 h-1.5 shrink-0 rounded-full bg-indigo-400" />
                                <div className="min-w-0">
                                  <p className="text-xs font-bold text-white">{notif.title}</p>
                                  <p className="text-[11px] text-slate-400 leading-relaxed mt-0.5">{notif.body}</p>
                                </div>
                              </div>
                            ))}
                          </div>
                        )}
                      </>
                    )}
                  </div>
                </div>
              )}
            </div>

            <div
              title={`${adminName} — ${roleLabel}`}
              className="hidden md:flex w-9 h-9 rounded-xl bg-gradient-to-br from-indigo-500 to-violet-600 items-center justify-center text-xs font-bold text-white shadow-md shadow-indigo-500/20"
            >
              {initialsOf(adminName)}
            </div>
          </div>
        </header>

        {/* Page Content Viewport */}
        <main className="flex-1 overflow-y-auto relative">
          <div className="max-w-[1400px] mx-auto px-4 py-6 md:px-8 md:py-8 min-h-full flex flex-col">
            {loading ? (
              <div className="space-y-6">
                <div className="skeleton h-36 rounded-3xl" />
                <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
                  {Array.from({ length: 4 }).map((_, i) => <div key={i} className="skeleton h-28 rounded-2xl" />)}
                </div>
                <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                  <div className="skeleton h-72 rounded-3xl lg:col-span-2" />
                  <div className="skeleton h-72 rounded-3xl" />
                </div>
              </div>
            ) : (
              <ErrorBoundary>
                <div key={pathname} className="animate-fade flex-1 flex flex-col">
                  {children}
                </div>
              </ErrorBoundary>
            )}
          </div>
        </main>
      </div>

      {paletteOpen && (
        <CommandPalette
          onClose={() => setPaletteOpen(false)}
          onNavigate={(href) => { setPaletteOpen(false); router.push(href); }}
          currentHref={activeItem?.href}
        />
      )}

      {showLogoutConfirm && (
        <div className="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm" onClick={() => setShowLogoutConfirm(false)}>
          <div className="w-full max-w-sm surface-solid rounded-2xl p-6 text-right animate-glass" onClick={(e) => e.stopPropagation()}>
            <div className="w-11 h-11 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 flex items-center justify-center mb-4">
              <LogOut className="w-5 h-5" />
            </div>
            <h3 className="text-base font-bold text-white mb-1">تسجيل الخروج</h3>
            <p className="text-xs text-slate-400 leading-relaxed mb-6">هل أنت متأكد من رغبتك في تسجيل الخروج من لوحة التحكم؟</p>
            <div className="flex gap-2">
              <button
                onClick={handleLogout}
                className="flex-1 py-2.5 rounded-xl bg-rose-600 hover:bg-rose-500 text-white text-xs font-bold transition-colors cursor-pointer"
              >
                تسجيل الخروج
              </button>
              <button
                autoFocus
                onClick={() => setShowLogoutConfirm(false)}
                className="flex-1 py-2.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-bold transition-colors cursor-pointer"
              >
                إلغاء
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function CommandPalette({
  onClose,
  onNavigate,
  currentHref,
}: {
  onClose: () => void;
  onNavigate: (href: string) => void;
  currentHref?: string;
}) {
  const [query, setQuery] = useState('');
  const [index, setIndex] = useState(0);
  const listRef = useRef<HTMLDivElement>(null);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return ALL_ITEMS;
    return ALL_ITEMS.filter((i) => i.name.toLowerCase().includes(q) || i.description.toLowerCase().includes(q));
  }, [query]);

  useEffect(() => {
    const el = listRef.current?.querySelector<HTMLElement>(`[data-idx="${index}"]`);
    el?.scrollIntoView({ block: 'nearest' });
  }, [index]);

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setIndex((i) => Math.min(i + 1, results.length - 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setIndex((i) => Math.max(i - 1, 0));
    } else if (e.key === 'Enter' && results[index]) {
      e.preventDefault();
      onNavigate(results[index].href);
    } else if (e.key === 'Escape') {
      onClose();
    }
  };

  return (
    <div className="fixed inset-0 z-[70] flex items-start justify-center p-4 pt-[12vh] bg-black/60 backdrop-blur-sm" onClick={onClose}>
      <div className="w-full max-w-lg surface-solid rounded-2xl overflow-hidden animate-glass" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center gap-3 px-4 border-b border-slate-800">
          <Search className="w-4 h-4 text-slate-500 shrink-0" />
          <input
            autoFocus
            value={query}
            onChange={(e) => { setQuery(e.target.value); setIndex(0); }}
            onKeyDown={onKeyDown}
            placeholder="ابحث عن صفحة أو قسم..."
            className="flex-1 h-14 bg-transparent text-sm text-white placeholder-slate-500 outline-none focus-visible:shadow-none"
          />
          <kbd className="font-mono text-[10px] px-1.5 py-0.5 rounded-md bg-slate-800 border border-slate-700 text-slate-400">Esc</kbd>
        </div>
        <div ref={listRef} className="max-h-80 overflow-y-auto p-2">
          {results.length === 0 ? (
            <p className="py-10 text-center text-xs text-slate-500">لا توجد نتائج مطابقة</p>
          ) : (
            results.map((item, i) => {
              const Icon = item.icon;
              const selected = i === index;
              return (
                <button
                  key={item.href}
                  data-idx={i}
                  onMouseEnter={() => setIndex(i)}
                  onClick={() => onNavigate(item.href)}
                  className={`w-full flex items-center gap-3 p-2.5 rounded-xl text-right transition-colors cursor-pointer ${selected ? 'bg-indigo-500/15' : ''}`}
                >
                  <div className={`p-2 rounded-lg border ${selected ? 'bg-indigo-500/20 border-indigo-400/30 text-indigo-200' : 'bg-slate-800/70 border-slate-700/70 text-slate-400'}`}>
                    <Icon className="w-4 h-4" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className={`text-[13px] font-bold ${selected ? 'text-white' : 'text-slate-200'}`}>
                      {item.name}
                      {currentHref === item.href && <span className="mr-2 text-[10px] font-semibold text-slate-500">(الصفحة الحالية)</span>}
                    </p>
                    <p className="text-[11px] text-slate-500 truncate">{item.description}</p>
                  </div>
                  {selected && <CornerDownLeft className="w-4 h-4 text-slate-500" />}
                </button>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}
