'use client';

// أجزاء الشريط الجانبي (تُستعمل بنسخة سطح المكتب القابلة للطي ونسخة الموبايل المنزلقة).

import Link from 'next/link';
import { LogOut, Sparkles } from 'lucide-react';
import { canSeePath, type DashboardRole } from '@/lib/role';
import { NAV_GROUPS, initialsOf, type SidebarItem } from '../nav';

export function SidebarNav({
  collapsed: isCollapsed,
  role,
  activeHref,
  pendingLeaves,
  pendingLoans,
  onNavigate,
}: {
  collapsed: boolean;
  role: DashboardRole;
  activeHref?: string;
  pendingLeaves: number;
  pendingLoans: number;
  onNavigate: () => void;
}) {
  const badgeFor = (item: SidebarItem) => {
    if (item.badgeKey === 'leaves') return pendingLeaves;
    if (item.badgeKey === 'loans') return pendingLoans;
    return 0;
  };

  return (
    <nav className="flex-1 px-3 py-4 overflow-y-auto no-scrollbar">
      {NAV_GROUPS.map((group) => (
        <div key={group.label} className="mb-5 last:mb-0">
          {isCollapsed ? (
            <div className="mx-auto mb-2 h-px w-6 bg-slate-800" />
          ) : (
            <p className="px-3 mb-2 text-[10px] font-bold tracking-wider text-slate-500">{group.label}</p>
          )}
          <div className="space-y-0.5">
            {group.items.filter((item) => canSeePath(role, item.href)).map((item) => {
              const isActive = activeHref === item.href;
              const Icon = item.icon;
              const badge = badgeFor(item);
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  title={isCollapsed ? item.name : undefined}
                  aria-current={isActive ? 'page' : undefined}
                  onClick={onNavigate}
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
}

export function SidebarBrand({ collapsed: isCollapsed }: { collapsed: boolean }) {
  return (
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
}

export function SidebarUserCard({
  collapsed: isCollapsed,
  adminName,
  roleLabel,
  onLogout,
}: {
  collapsed: boolean;
  adminName: string;
  roleLabel: string;
  onLogout: () => void;
}) {
  return (
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
            onClick={onLogout}
            title="تسجيل الخروج"
            className="p-2 rounded-lg text-slate-500 hover:text-rose-400 hover:bg-rose-500/10 transition-colors cursor-pointer"
          >
            <LogOut className="w-4 h-4" />
          </button>
        )}
      </div>
      {isCollapsed && (
        <button
          onClick={onLogout}
          title="تسجيل الخروج"
          className="p-2.5 rounded-lg text-slate-500 hover:text-rose-400 hover:bg-rose-500/10 transition-colors cursor-pointer"
        >
          <LogOut className="w-4 h-4" />
        </button>
      )}
    </div>
  );
}
