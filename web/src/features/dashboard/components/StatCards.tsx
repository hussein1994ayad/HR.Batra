'use client';

import Link from 'next/link';
import type { DashboardStats } from '../types';
import { Users, CalendarRange, Coins, Smartphone, AlertTriangle, CheckCircle } from 'lucide-react';

interface StatCardsProps {
  stats: DashboardStats;
}

/** بطاقات الإحصاءات السريعة، كل بطاقة رابط للصفحة المختصة. */
export function StatCards({ stats }: StatCardsProps) {
  const statCards = [
    { title: 'إجمالي الكادر', value: stats.employees, subtitle: 'الموظفين النشطين', icon: Users, color: 'text-indigo-400 bg-indigo-500/10 border-indigo-500/20', href: '/dashboard/employees' },
    { title: 'حاضر اليوم', value: stats.presentToday, subtitle: 'سجلوا الحضور اليوم', icon: CheckCircle, color: 'text-violet-400 bg-violet-500/10 border-violet-500/20', href: '/dashboard/tracking' },
    { title: 'غياب اليوم', value: stats.absentToday, subtitle: 'لم يسجلوا بصمة دخول', icon: AlertTriangle, color: 'text-rose-400 bg-rose-500/10 border-rose-500/20', href: '#absent-section' },
    { title: 'طلبات الإجازة المعلقة', value: stats.pendingLeaves, subtitle: 'تحت التدقيق الإداري', icon: CalendarRange, color: 'text-amber-400 bg-amber-500/10 border-amber-500/20', href: '/dashboard/leaves' },
    { title: 'السلف المطلوبة', value: stats.pendingLoans, subtitle: 'بانتظار الاعتماد المالي', icon: Coins, color: 'text-sky-400 bg-sky-500/10 border-sky-500/20', href: '/dashboard/loans' },
    { title: 'طلبات اعتماد الأجهزة', value: stats.pendingDevices, subtitle: 'تغيير أو قفل هواتف الموظفين', icon: Smartphone, color: 'text-purple-400 bg-purple-500/10 border-purple-500/20', href: '/dashboard/employees' },
  ];

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
      {statCards.map((card, i) => (
        <Link 
          key={i} 
          href={card.href}
          className="group relative bg-slate-900/40 backdrop-blur-xl border border-slate-800/80 rounded-3xl p-6 shadow-xl hover:border-slate-700/60 hover:-translate-y-0.5 transition-all duration-300 block cursor-pointer"
        >
          <div className="flex items-center justify-between">
            <div>
              <span className="text-xs text-slate-400 font-bold block mb-1.5">{card.title}</span>
              <span className="text-3xl font-extrabold text-white tracking-tight">{card.value}</span>
              <span className="text-[10px] text-slate-500 font-medium block mt-1.5">{card.subtitle}</span>
            </div>
            <div className={`p-4 rounded-2xl border ${card.color} group-hover:scale-110 transition-transform duration-300`}>
              <card.icon className="w-6 h-6 shrink-0" />
            </div>
          </div>
        </Link>
      ))}
    </div>
  );
}
