'use client';

import React, { useState, useEffect } from 'react';
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
  Loader2,
  Bell,
  Banknote
} from 'lucide-react';

interface SidebarItem {
  name: string;
  href: string;
  icon: React.ComponentType<any>;
}

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
        <div className="p-8 bg-slate-900 border border-rose-500/30 rounded-3xl text-right max-w-2xl mx-auto my-12 text-slate-100 animate-glass">
          <div className="flex items-center gap-3 mb-4">
            <span className="text-2xl">⚠️</span>
            <h2 className="text-xl font-bold text-rose-400">حدث خطأ غير متوقع في لوحة التحكم</h2>
          </div>
          <p className="text-sm text-slate-300 mb-6 leading-relaxed">
            لقد حدث خطأ أثناء معالجة أو عرض البيانات. يمكنك مسح البيانات المؤقتة وإعادة المحاولة بالضغط على الزر أدناه:
          </p>
          <pre className="p-4 bg-slate-950 rounded-2xl text-xs font-mono text-rose-300 overflow-x-auto whitespace-pre-wrap text-left dir-ltr mb-6 max-h-60 overflow-y-auto">
            {this.state.error?.toString()}
            {"\n\nStack Trace:\n"}
            {this.state.error?.stack}
          </pre>
          <div className="flex gap-4">
            <button 
              onClick={() => {
                localStorage.removeItem('batra_cache_dashboard');
                localStorage.removeItem('batra_cache_admin');
                window.location.reload();
              }}
              className="px-5 py-2.5 bg-rose-600 hover:bg-rose-500 text-white rounded-xl text-xs font-bold transition-all cursor-pointer active:scale-95"
            >
              مسح الذاكرة المؤقتة وإعادة التحميل 🔄
            </button>
            <button 
              onClick={() => window.location.reload()}
              className="px-5 py-2.5 bg-slate-800 hover:bg-slate-700 text-white rounded-xl text-xs font-bold transition-all cursor-pointer active:scale-95"
            >
              إعادة محاولة التحميل 🔄
            </button>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
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
  const [adminUser, setAdminUser] = useState<any>(null);
  const [adminName, setAdminName] = useState<string>('مدير النظام');
  const [pendingLeaves, setPendingLeaves] = useState(0);
  const [pendingLoans, setPendingLoans] = useState(0);
  const [showNotifications, setShowNotifications] = useState(false);

  const [systemNotifs, setSystemNotifs] = useState<any[]>([]);

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
          supabase.from('notifications').select('*').eq('employee_id', session.user.id).eq('is_read', false)
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
            // Optional: We can show a toast or alert, but toast() blocks the UI.
            // Using a simple notification state if needed.
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
    if (confirm('هل أنت متأكد من رغبتك في تسجيل الخروج؟')) {
      await supabase.auth.signOut();
      router.replace('/login');
    }
  };

  const menuItems: SidebarItem[] = [
    { name: 'لوحة المؤشرات العامة', href: '/dashboard', icon: LayoutDashboard },
    { name: 'دليل الموظفين والأجهزة', href: '/dashboard/employees', icon: Users },
    { name: 'الحضور، الانصراف والتتبع', href: '/dashboard/tracking', icon: MapPin },
    { name: 'إدارة وتخطيط السياج الجغرافي', href: '/dashboard/geofences', icon: ShieldAlert },
    { name: 'طلبات الإجازات والمعلقات', href: '/dashboard/leaves', icon: CalendarRange },
    { name: 'سلف الموظفين والأقساط', href: '/dashboard/loans', icon: Coins },
    { name: 'إدارة الرواتب والمكافآت', href: '/dashboard/payroll', icon: Banknote },
    { name: 'سلة المحذوفات للملفات', href: '/dashboard/trash', icon: Trash2 },
    { name: 'تحليلات التخزين والـ Buckets', href: '/dashboard/storage', icon: HardDrive },
    { name: 'إعدادات النظام والشركة', href: '/dashboard/settings', icon: Settings },
  ];

  return (
    <div className="flex h-screen bg-[#0A0E1A] overflow-hidden text-slate-100 font-sans" dir="rtl">
      <Toaster position="top-center" reverseOrder={false} toastOptions={{
        style: {
          background: '#1e293b',
          color: '#fff',
          fontFamily: 'Cairo, sans-serif',
          fontWeight: 'bold',
          borderRadius: '12px',
          border: '1px solid rgba(255,255,255,0.1)',
        }
      }} />
      {/* Dynamic Background Glows */}
      <div className="absolute top-0 right-0 w-[600px] h-[600px] bg-indigo-500/5 rounded-full blur-[150px] pointer-events-none"></div>
      <div className="absolute bottom-0 left-0 w-[500px] h-[500px] bg-violet-500/5 rounded-full blur-[150px] pointer-events-none"></div>

      {/* Sidebar - Desktop */}
      <aside className="hidden lg:flex lg:flex-col lg:w-72 bg-slate-950/40 backdrop-blur-xl border-l border-slate-800/40 z-20 transition-all duration-300">
        <div className="p-6 border-b border-slate-800/40 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-indigo-500/10 rounded-xl border border-indigo-500/20">
              <span className="text-xl font-bold text-indigo-400">✨</span>
            </div>
            <div>
              <h2 className="font-extrabold text-white text-base">HR Pro v6.0</h2>
              <p className="text-[10px] text-slate-400 font-medium">لوحة المدير والمسؤول</p>
            </div>
          </div>
        </div>

        <nav className="flex-1 px-4 py-6 space-y-1.5 overflow-y-auto scrollbar-thin">
          {menuItems.map((item) => {
            const isActive = pathname === item.href;
            const Icon = item.icon;
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`flex items-center gap-3.5 px-4 py-3.5 rounded-2xl text-sm font-semibold transition-all duration-200 cursor-pointer ${
                  isActive 
                    ? 'bg-gradient-to-l from-indigo-650 to-indigo-500 text-white shadow-lg shadow-indigo-500/15 scale-[1.02]' 
                    : 'text-slate-400 hover:text-white hover:bg-slate-800/40 hover:scale-[1.01]'
                }`}
              >
                <Icon className={`w-5 h-5 shrink-0 ${isActive ? 'text-white' : 'text-slate-400 group-hover:text-white'}`} />
                <span>{item.name}</span>
              </Link>
            );
          })}
        </nav>

        {/* User Card & Logout */}
        <div className="p-4 border-t border-slate-800/40 bg-slate-950/30">
          <div className="flex items-center gap-3 px-2 py-3 mb-2">
            <div className="w-10 h-10 rounded-xl bg-indigo-600 flex items-center justify-center font-bold text-white shadow-md shadow-indigo-500/20 text-sm border border-indigo-400/20">
              {(adminName || 'مدير').substring(0, 2)}
            </div>
            <div className="overflow-hidden">
              <h4 className="text-sm font-bold text-white truncate">{adminName}</h4>
              <span className="text-[10px] bg-indigo-500/15 text-indigo-300 font-bold px-1.5 py-0.5 rounded-md border border-indigo-500/20">
                {adminUser?.email === 'admin@hrpro.com' ? 'مسؤول النظام' : 'مدير الموارد'}
              </span>
            </div>
          </div>

          <button
            onClick={handleLogout}
            className="w-full flex items-center justify-center gap-2 py-3 px-4 bg-red-500/10 hover:bg-red-500/20 text-red-400 border border-red-500/20 hover:border-red-500/30 rounded-xl font-bold transition-all text-xs cursor-pointer"
          >
            <LogOut className="w-4 h-4" />
            <span>تسجيل الخروج</span>
          </button>
        </div>
      </aside>

      {/* Sidebar - Mobile / Tablet */}
      {sidebarOpen && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-30 lg:hidden" onClick={() => setSidebarOpen(false)} />
      )}

      <aside className={`fixed inset-y-0 right-0 w-72 bg-[#0E1324] border-l border-slate-800/60 z-40 flex flex-col transition-all duration-300 lg:hidden ${
        sidebarOpen ? 'translate-x-0' : 'translate-x-full'
      }`}>
        <div className="p-6 border-b border-slate-800/60 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="text-xl">✨</span>
            <span className="font-extrabold text-white text-base">HR Pro v6.0</span>
          </div>
          <button 
            onClick={() => setSidebarOpen(false)}
            className="p-1.5 bg-slate-800 hover:bg-slate-700 rounded-lg text-slate-400 hover:text-white"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <nav className="flex-1 px-4 py-6 space-y-1 overflow-y-auto">
          {menuItems.map((item) => {
            const isActive = pathname === item.href;
            const Icon = item.icon;
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={() => setSidebarOpen(false)}
                className={`flex items-center gap-3.5 px-4 py-3 rounded-2xl text-sm font-semibold transition-all ${
                  isActive 
                    ? 'bg-gradient-to-l from-indigo-600 to-indigo-500 text-white shadow-lg' 
                    : 'text-slate-400 hover:text-white hover:bg-slate-800/40'
                }`}
              >
                <Icon className="w-5 h-5 shrink-0" />
                <span>{item.name}</span>
              </Link>
            );
          })}
        </nav>

        <div className="p-4 border-t border-slate-800/60 bg-slate-950/20">
          <div className="flex items-center gap-3 px-2 py-3 mb-2">
            <div className="w-9 h-9 rounded-lg bg-indigo-600 flex items-center justify-center font-bold text-white">
              {(adminName || 'مدير').substring(0, 2)}
            </div>
            <div className="overflow-hidden">
              <h4 className="text-xs font-bold text-white truncate">{adminName}</h4>
              <span className="text-[9px] text-indigo-400 font-semibold">مسؤول الإدارة</span>
            </div>
          </div>
          <button
            onClick={handleLogout}
            className="w-full flex items-center justify-center gap-2 py-2 px-3 bg-red-500/10 hover:bg-red-500/20 text-red-400 rounded-lg font-bold transition-all text-[11px] cursor-pointer"
          >
            <LogOut className="w-3.5 h-3.5" />
            <span>تسجيل الخروج</span>
          </button>
        </div>
      </aside>

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col h-full overflow-hidden">
        
        {/* Top Navbar Header */}
        <header className="h-16 border-b border-slate-800/80 bg-slate-900/40 backdrop-blur-xl px-6 flex items-center justify-between z-10">
          <div className="flex items-center gap-4">
            <button
              onClick={() => setSidebarOpen(true)}
              className="p-2 bg-slate-800/60 hover:bg-slate-700/60 rounded-xl text-slate-400 hover:text-white lg:hidden transition-colors cursor-pointer"
            >
              <Menu className="w-6 h-6" />
            </button>
            
            <h1 className="text-lg font-extrabold text-white hidden md:block">
              {menuItems.find(item => item.href === pathname)?.name || 'لوحة الإدارة'}
            </h1>
          </div>

          <div className="flex items-center gap-4">
            {/* Live indicator badge */}
            <div className="flex items-center gap-2 px-3 py-1.5 bg-indigo-500/10 border border-indigo-500/20 rounded-full">
              <span className="w-2 h-2 rounded-full bg-indigo-400 animate-ping"></span>
              <span className="text-[10px] text-indigo-400 font-bold">مباشر ومزامن</span>
            </div>

            <div className="relative">
              <button 
                onClick={() => setShowNotifications(!showNotifications)}
                className="relative p-2 bg-slate-850/40 hover:bg-slate-800/40 border border-slate-800/60 text-slate-300 hover:text-white rounded-xl transition-all cursor-pointer"
              >
                <Bell className="w-5 h-5" />
                {(pendingLeaves + pendingLoans + systemNotifs.length) > 0 && (
                  <span className="absolute top-1 right-1 w-2 h-2 bg-indigo-400 rounded-full border border-slate-900 animate-pulse"></span>
                )}
              </button>
              
              {showNotifications && (
                <div className="absolute top-full left-0 mt-2 w-80 bg-slate-900 border border-slate-800 rounded-2xl shadow-2xl overflow-hidden z-50 text-right max-h-96 overflow-y-auto scrollbar-thin">
                  <div className="p-4 border-b border-slate-800 bg-slate-950/50">
                    <h3 className="text-sm font-bold text-white">الإشعارات والمهام</h3>
                  </div>
                  <div className="p-2">
                    {(pendingLeaves + pendingLoans + systemNotifs.length) === 0 ? (
                      <div className="p-4 text-center text-xs text-slate-500">لا توجد إشعارات أو مهام! كل شيء على ما يرام ✨</div>
                    ) : (
                      <>
                        {pendingLeaves > 0 && (
                          <Link href="/dashboard/leaves" onClick={() => setShowNotifications(false)} className="flex items-center gap-3 p-3 hover:bg-slate-800/50 rounded-xl transition-colors mb-1">
                            <div className="p-2 bg-amber-500/10 text-amber-400 rounded-lg"><CalendarRange className="w-4 h-4" /></div>
                            <div>
                              <p className="text-xs font-bold text-white">طلبات الإجازة ({pendingLeaves})</p>
                              <p className="text-[10px] text-slate-400">تحتاج إلى مراجعة واعتماد</p>
                            </div>
                          </Link>
                        )}
                        {pendingLoans > 0 && (
                          <Link href="/dashboard/loans" onClick={() => setShowNotifications(false)} className="flex items-center gap-3 p-3 hover:bg-slate-800/50 rounded-xl transition-colors mb-1">
                            <div className="p-2 bg-teal-500/10 text-teal-400 rounded-lg"><Coins className="w-4 h-4" /></div>
                            <div>
                              <p className="text-xs font-bold text-white">طلبات السلف ({pendingLoans})</p>
                              <p className="text-[10px] text-slate-400">بانتظار الاعتماد المالي</p>
                            </div>
                          </Link>
                        )}
                        
                        {systemNotifs.length > 0 && (
                          <div className="pt-2 mt-2 border-t border-slate-800/60">
                            <p className="text-[10px] text-slate-500 font-bold px-2 mb-2">إشعارات النظام ({systemNotifs.length})</p>
                            {systemNotifs.map((notif, idx) => (
                              <div key={idx} className="flex flex-col gap-1 p-3 hover:bg-slate-800/50 rounded-xl transition-colors mb-1 border border-slate-800/30">
                                <p className="text-xs font-bold text-white flex items-center gap-1.5">
                                  <span className="w-1.5 h-1.5 rounded-full bg-blue-500"></span>
                                  {notif.title}
                                </p>
                                <p className="text-[10px] text-slate-400 leading-relaxed pr-3">{notif.body}</p>
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
          </div>
        </header>

        {/* Page Content Viewport */}
        <main className="flex-1 overflow-y-auto p-6 md:p-8 scrollbar-thin relative">
          <div className="max-w-7xl mx-auto h-full flex flex-col">
            {loading ? (
              <div className="absolute inset-0 flex flex-col items-center justify-center z-10">
                <Loader2 className="w-10 h-10 text-teal-400 animate-spin mb-4" />
                <p className="text-sm text-slate-400 font-bold">جاري تحميل بيانات لوحة التحكم...</p>
              </div>
            ) : (
              <ErrorBoundary>
                {children}
              </ErrorBoundary>
            )}
          </div>
        </main>
      </div>
    </div>
  );
}
