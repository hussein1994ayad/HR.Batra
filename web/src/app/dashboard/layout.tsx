'use client';

// إطار لوحة الإدارة: الشريط الجانبي (سطح مكتب قابل للطي + موبايل منزلق)، الرأس (العنوان، البحث السريع،
// التاريخ، الإشعارات)، ومنطقة الصفحة. الجلسة والعدّادات في features/shell/useAdminSession،
// وعناصر القائمة في features/shell/nav.

import { arabicDate } from '@/lib/dates';
import { baghdadToday } from '@/features/payroll/period';
import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { Toaster } from 'react-hot-toast';
import { Menu, X, Search, ChevronsRight, ChevronsLeft } from 'lucide-react';
import { ConfirmProvider } from '@/components/confirm';
import { RoleContext, isAdminOnlyPath } from '@/lib/role';
import { useIsClient } from '@/lib/useIsClient';
import { findActiveItem, initialsOf } from '@/features/shell/nav';
import { useAdminSession } from '@/features/shell/useAdminSession';
import { ErrorBoundary } from '@/features/shell/components/ErrorBoundary';
import { SidebarBrand, SidebarNav, SidebarUserCard } from '@/features/shell/components/Sidebar';
import { NotificationsMenu } from '@/features/shell/components/NotificationsMenu';
import { LogoutConfirm } from '@/features/shell/components/LogoutConfirm';
import { CommandPalette } from '@/features/shell/components/CommandPalette';

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const { loading, adminName, role, pendingLeaves, pendingLoans, systemNotifs, logout, markAllNotifsRead } = useAdminSession();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [collapsed, setCollapsed] = useState(false);
  const [showNotifications, setShowNotifications] = useState(false);
  const [showLogoutConfirm, setShowLogoutConfirm] = useState(false);
  const [paletteOpen, setPaletteOpen] = useState(false);

  const closeNotifications = useCallback(() => setShowNotifications(false), []);

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

  const handleLogout = async () => {
    setShowLogoutConfirm(false);
    await logout();
  };

  // مدير الفرع ما يشوف صفحات الأدمن (الرابط المباشر يرجّعه للرئيسية)
  useEffect(() => {
    if (role === 'manager' && isAdminOnlyPath(pathname)) router.replace('/dashboard');
  }, [role, pathname, router]);

  const activeItem = useMemo(() => findActiveItem(pathname), [pathname]);

  const roleLabel = role === 'manager' ? 'مدير فرع' : 'مسؤول النظام';
  const closeSidebar = () => setSidebarOpen(false);
  const openLogoutConfirm = () => setShowLogoutConfirm(true);

  const isClient = useIsClient();
  const todayLabel = useMemo(() => {
    if (!isClient) return '';
    try {
      return arabicDate(baghdadToday(), true);
    } catch {
      return new Date().toDateString();
    }
  }, [isClient]);

  const nav = (isCollapsed: boolean) => (
    <SidebarNav
      collapsed={isCollapsed}
      role={role}
      activeHref={activeItem?.href}
      pendingLeaves={pendingLeaves}
      pendingLoans={pendingLoans}
      onNavigate={closeSidebar}
    />
  );

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
          <SidebarBrand collapsed={collapsed} />
        </div>

        {nav(collapsed)}

        <button
          onClick={toggleCollapsed}
          title={collapsed ? 'توسيع القائمة' : 'طي القائمة'}
          className="absolute top-20 -left-3 w-6 h-6 rounded-full bg-slate-900 border border-slate-700 text-slate-400 hover:text-white hover:border-indigo-500/60 flex items-center justify-center shadow-lg transition-colors cursor-pointer"
        >
          {collapsed ? <ChevronsLeft className="w-3.5 h-3.5" /> : <ChevronsRight className="w-3.5 h-3.5" />}
        </button>

        <SidebarUserCard collapsed={collapsed} adminName={adminName} roleLabel={roleLabel} onLogout={openLogoutConfirm} />
      </aside>

      {/* Sidebar - Mobile / Tablet */}
      <div
        className={`fixed inset-0 bg-black/60 backdrop-blur-sm z-30 lg:hidden transition-opacity duration-300 ${sidebarOpen ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
        onClick={closeSidebar}
      />
      <aside
        className={`fixed inset-y-0 right-0 w-72 max-w-[85vw] bg-slate-950 border-l border-slate-800/70 z-40 flex flex-col transition-transform duration-300 ease-out lg:hidden ${
          sidebarOpen ? 'translate-x-0' : 'translate-x-full'
        }`}
      >
        <div className="h-16 px-5 border-b border-slate-800/70 flex items-center justify-between">
          <SidebarBrand collapsed={false} />
          <button
            onClick={closeSidebar}
            className="p-2 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800/60 cursor-pointer"
          >
            <X className="w-5 h-5" />
          </button>
        </div>
        {nav(false)}
        <SidebarUserCard collapsed={false} adminName={adminName} roleLabel={roleLabel} onLogout={openLogoutConfirm} />
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

            <NotificationsMenu
              open={showNotifications}
              onToggle={() => setShowNotifications(!showNotifications)}
              onClose={closeNotifications}
              pendingLeaves={pendingLeaves}
              pendingLoans={pendingLoans}
              systemNotifs={systemNotifs}
              onMarkAllRead={markAllNotifsRead}
            />

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
                <ConfirmProvider>
                  <RoleContext.Provider value={role}>
                    <div key={pathname} className="animate-fade flex-1 flex flex-col">
                      {role === 'manager' && isAdminOnlyPath(pathname) ? null : children}
                    </div>
                  </RoleContext.Provider>
                </ConfirmProvider>
              </ErrorBoundary>
            )}
          </div>
        </main>
      </div>

      {paletteOpen && (
        <CommandPalette
          role={role}
          onClose={() => setPaletteOpen(false)}
          onNavigate={(href) => { setPaletteOpen(false); router.push(href); }}
          currentHref={activeItem?.href}
        />
      )}

      {showLogoutConfirm && <LogoutConfirm onConfirm={handleLogout} onCancel={() => setShowLogoutConfirm(false)} />}
    </div>
  );
}
