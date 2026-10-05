'use client';

// رأس الصفحة والبطاقات (PageHeader, Card, CardHeader).

import React from 'react';
import { type LucideIcon } from 'lucide-react';
import { cn, Tone, TONE_CHIP } from './classes';

export function PageHeader({
  icon: Icon,
  title,
  description,
  actions,
  tone = 'indigo',
}: {
  icon: LucideIcon;
  title: string;
  description?: React.ReactNode;
  actions?: React.ReactNode;
  tone?: Tone;
}) {
  return (
    <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4">
      <div className="flex items-start gap-3.5 min-w-0">
        <div className={cn('w-11 h-11 shrink-0 rounded-2xl border flex items-center justify-center', TONE_CHIP[tone])}>
          <Icon className="w-5 h-5" />
        </div>
        <div className="min-w-0">
          <h2 className="text-lg md:text-xl font-extrabold text-white tracking-tight">{title}</h2>
          {description && <p className="text-xs text-slate-400 mt-1 leading-relaxed">{description}</p>}
        </div>
      </div>
      {actions && <div className="flex flex-wrap items-center gap-2 lg:justify-end">{actions}</div>}
    </div>
  );
}

export function Card({
  children,
  className,
  padded = true,
  id,
}: {
  children: React.ReactNode;
  className?: string;
  padded?: boolean;
  id?: string;
}) {
  return (
    <section id={id} className={cn('surface rounded-3xl', padded && 'p-5 md:p-6', className)}>
      {children}
    </section>
  );
}

export function CardHeader({
  icon: Icon,
  tone = 'indigo',
  title,
  description,
  actions,
  className,
}: {
  icon?: LucideIcon;
  tone?: Tone;
  title: React.ReactNode;
  description?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-5', className)}>
      <div className="flex items-start gap-3 min-w-0">
        {Icon && (
          <div className={cn('w-9 h-9 shrink-0 rounded-xl border flex items-center justify-center', TONE_CHIP[tone])}>
            <Icon className="w-[18px] h-[18px]" />
          </div>
        )}
        <div className="min-w-0">
          <h3 className="text-[15px] font-extrabold text-white flex items-center gap-2">{title}</h3>
          {description && <p className="text-[11px] text-slate-500 mt-0.5 leading-relaxed">{description}</p>}
        </div>
      </div>
      {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
    </div>
  );
}
