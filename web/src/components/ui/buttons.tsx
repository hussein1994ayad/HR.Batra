'use client';

// الأزرار (Button, IconButton) وأنماطها.

import React from 'react';
import { Loader2, type LucideIcon } from 'lucide-react';
import { cn, Tone, TONE_CHIP } from './classes';

export type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'success' | 'warning' | 'soft-danger' | 'soft-success' | 'soft';

const BUTTON_VARIANTS: Record<ButtonVariant, string> = {
  primary:
    'bg-gradient-to-l from-indigo-500 to-violet-600 hover:from-indigo-400 hover:to-violet-500 text-white shadow-lg shadow-indigo-500/20',
  secondary: 'bg-slate-800/80 hover:bg-slate-700/80 border border-slate-700/80 text-slate-100',
  ghost: 'text-slate-400 hover:text-white hover:bg-slate-800/70',
  danger: 'bg-rose-600 hover:bg-rose-500 text-white shadow-lg shadow-rose-600/20',
  success: 'bg-emerald-600 hover:bg-emerald-500 text-white shadow-lg shadow-emerald-600/20',
  warning: 'bg-amber-500 hover:bg-amber-400 text-slate-950 shadow-lg shadow-amber-500/20',
  'soft-danger': 'bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/20 text-rose-300',
  'soft-success': 'bg-emerald-500/10 hover:bg-emerald-500/20 border border-emerald-500/20 text-emerald-300',
  soft: 'bg-indigo-500/10 hover:bg-indigo-500/20 border border-indigo-500/20 text-indigo-200',
};

const BUTTON_SIZES = {
  xs: 'h-7 px-2.5 text-[11px] gap-1 rounded-lg',
  sm: 'h-9 px-3 text-xs gap-1.5 rounded-xl',
  md: 'h-10 px-4 text-xs gap-2 rounded-xl',
  lg: 'h-12 px-5 text-sm gap-2 rounded-xl',
};

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: keyof typeof BUTTON_SIZES;
  icon?: LucideIcon;
  loading?: boolean;
  block?: boolean;
}

export function Button({
  variant = 'primary',
  size = 'md',
  icon: Icon,
  loading,
  block,
  className,
  children,
  disabled,
  type = 'button',
  ...rest
}: ButtonProps) {
  return (
    <button
      type={type}
      disabled={disabled || loading}
      className={cn(
        'inline-flex items-center justify-center font-bold whitespace-nowrap transition-all duration-150 cursor-pointer active:scale-[0.98] disabled:opacity-50 disabled:pointer-events-none',
        BUTTON_VARIANTS[variant],
        BUTTON_SIZES[size],
        block && 'w-full',
        className,
      )}
      {...rest}
    >
      {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : Icon ? <Icon className="w-4 h-4 shrink-0" /> : null}
      {children}
    </button>
  );
}

export function IconButton({
  icon: Icon,
  label,
  tone = 'slate',
  loading,
  className,
  ...rest
}: Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'children'> & {
  icon: LucideIcon;
  label: string;
  tone?: Tone;
  loading?: boolean;
}) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      disabled={rest.disabled || loading}
      className={cn(
        'inline-flex items-center justify-center w-8 h-8 rounded-lg border transition-colors cursor-pointer disabled:opacity-50 disabled:pointer-events-none hover:brightness-125',
        TONE_CHIP[tone],
        className,
      )}
      {...rest}
    >
      {loading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Icon className="w-3.5 h-3.5" />}
    </button>
  );
}
