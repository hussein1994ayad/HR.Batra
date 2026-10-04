'use client';

// عناصر العرض: Badge, Avatar, StatTile, SegmentedTabs, EmptyState, InfoNote.

import React from 'react';
import { type LucideIcon } from 'lucide-react';
import { initials } from '@/lib/format';
import { cn, Tone, TONE_CHIP, TONE_TEXT, TONE_DOT } from './classes';

export function Badge({
  tone = 'slate',
  children,
  dot,
  className,
}: {
  tone?: Tone;
  children: React.ReactNode;
  dot?: boolean;
  className?: string;
}) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full border text-[10px] font-bold whitespace-nowrap',
        TONE_CHIP[tone],
        className,
      )}
    >
      {dot && <span className={cn('w-1.5 h-1.5 rounded-full', TONE_DOT[tone])} />}
      {children}
    </span>
  );
}

const AVATAR_TONES: Tone[] = ['indigo', 'violet', 'sky', 'emerald', 'amber', 'rose', 'teal'];

export function Avatar({ name, size = 'md' }: { name: string | null | undefined; size?: 'sm' | 'md' | 'lg' }) {
  let h = 0;
  const n = name || '';
  for (let i = 0; i < n.length; i++) h = (h * 31 + n.charCodeAt(i)) >>> 0;
  const tone = AVATAR_TONES[h % AVATAR_TONES.length];
  const sizes = { sm: 'w-7 h-7 text-[10px]', md: 'w-9 h-9 text-[11px]', lg: 'w-11 h-11 text-sm' };
  return (
    <div className={cn('shrink-0 rounded-full border flex items-center justify-center font-bold', TONE_CHIP[tone], sizes[size])}>
      {initials(name)}
    </div>
  );
}

export function StatTile({
  label,
  value,
  hint,
  icon: Icon,
  tone = 'indigo',
  className,
}: {
  label: React.ReactNode;
  value: React.ReactNode;
  hint?: React.ReactNode;
  icon?: LucideIcon;
  tone?: Tone;
  className?: string;
}) {
  return (
    <div className={cn('rounded-2xl bg-slate-900/50 border border-slate-800/80 p-4', className)}>
      <div className="flex items-center justify-between gap-2 mb-2">
        <span className="text-[11px] font-semibold text-slate-400">{label}</span>
        {Icon && (
          <div className={cn('w-7 h-7 rounded-lg border flex items-center justify-center', TONE_CHIP[tone])}>
            <Icon className="w-3.5 h-3.5" />
          </div>
        )}
      </div>
      <div className={cn('text-xl font-extrabold tracking-tight', tone === 'slate' ? 'text-white' : TONE_TEXT[tone])}>{value}</div>
      {hint && <div className="text-[10px] text-slate-500 mt-1">{hint}</div>}
    </div>
  );
}

export interface TabOption<T extends string> {
  value: T;
  label: string;
  count?: number;
  icon?: LucideIcon;
}

export function SegmentedTabs<T extends string>({
  value,
  onChange,
  options,
  className,
}: {
  value: T;
  onChange: (value: T) => void;
  options: TabOption<T>[];
  className?: string;
}) {
  return (
    <div
      role="tablist"
      className={cn('inline-flex max-w-full overflow-x-auto no-scrollbar p-1 gap-1 rounded-xl bg-slate-950/60 border border-slate-800/80', className)}
    >
      {options.map((opt) => {
        const active = opt.value === value;
        const Icon = opt.icon;
        return (
          <button
            key={opt.value}
            role="tab"
            type="button"
            aria-selected={active}
            onClick={() => onChange(opt.value)}
            className={cn(
              'inline-flex items-center gap-1.5 h-8 px-3 rounded-lg text-xs font-bold whitespace-nowrap transition-colors cursor-pointer',
              active ? 'bg-slate-800 text-white shadow-sm' : 'text-slate-400 hover:text-slate-200',
            )}
          >
            {Icon && <Icon className={cn('w-3.5 h-3.5', active ? 'text-indigo-300' : '')} />}
            {opt.label}
            {opt.count !== undefined && (
              <span
                className={cn(
                  'min-w-5 h-5 px-1.5 rounded-full text-[10px] flex items-center justify-center',
                  active ? 'bg-indigo-500/20 text-indigo-200' : 'bg-slate-800 text-slate-400',
                )}
              >
                {opt.count}
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}

export function EmptyState({
  icon: Icon,
  title,
  description,
  action,
  tone = 'slate',
  className,
}: {
  icon: LucideIcon;
  title: string;
  description?: React.ReactNode;
  action?: React.ReactNode;
  tone?: Tone;
  className?: string;
}) {
  return (
    <div className={cn('flex flex-col items-center justify-center text-center py-12 px-6 rounded-2xl border border-dashed border-slate-800', className)}>
      <div className={cn('w-12 h-12 rounded-2xl border flex items-center justify-center mb-3', TONE_CHIP[tone])}>
        <Icon className="w-6 h-6" />
      </div>
      <p className="text-sm font-bold text-slate-200">{title}</p>
      {description && <p className="text-xs text-slate-500 mt-1 max-w-sm leading-relaxed">{description}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}

export function InfoNote({
  tone = 'indigo',
  icon: Icon,
  children,
  className,
}: {
  tone?: Tone;
  icon?: LucideIcon;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('flex items-start gap-2.5 p-3.5 rounded-xl border text-xs leading-relaxed', TONE_CHIP[tone], className)}>
      {Icon && <Icon className="w-4 h-4 shrink-0 mt-0.5" />}
      <div className="text-slate-300">{children}</div>
    </div>
  );
}
