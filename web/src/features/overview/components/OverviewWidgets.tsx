'use client';

// عناصر عرض صغيرة بالرئيسية: بطاقات المؤشرات، حلقة نسبة الحضور، صف المفتاح، وهيكل التحميل.

import Link from 'next/link';
import { ChevronLeft, type LucideIcon } from 'lucide-react';
import { TONE_CHIP, cn, type Tone } from '@/components/ui';

export interface StatCardProps {
  title: string;
  value: number;
  subtitle: string;
  icon: LucideIcon;
  tone: Tone;
  href: string;
  /** شارة "يتطلب إجراء" بدل السهم */
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

export function StatCard({ title, value, subtitle, icon: Icon, tone, href, attention }: StatCardProps) {
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

export function AttendanceRing({ percent }: { percent: number }) {
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

export function LegendRow({ color, label, value }: { color: string; label: string; value: number }) {
  return (
    <div className="flex items-center gap-3">
      <span className={cn('w-2.5 h-2.5 rounded-full', color)} />
      <span className="flex-1 text-xs text-slate-300">{label}</span>
      <span className="text-sm font-extrabold text-white">{value.toLocaleString('en-US')}</span>
    </div>
  );
}

export function DashboardSkeleton() {
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
