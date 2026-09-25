'use client';

// Shared UI kit for the dashboard: consistent cards, buttons, form controls,
// badges, tabs, tables, modals and empty/loading states.

import React, { useEffect, useId, useRef, useState } from 'react';
import { Loader2, Search, X, type LucideIcon } from 'lucide-react';
import { initials } from '@/lib/format';

export function cn(...classes: Array<string | false | null | undefined>): string {
  return classes.filter(Boolean).join(' ');
}

// Utility groups where a class passed by the caller should replace the default.
const CLASS_GROUPS: Array<[string, RegExp]> = [
  ['w', /^w-/],
  ['h', /^h-/],
  ['px', /^px-/],
  ['pl', /^pl-/],
  ['pr', /^pr-/],
  ['text-size', /^text-(xs|sm|base|lg|xl|\[\d+px\])$/],
];

function groupOf(token: string): string | null {
  const bare = token.replace(/^[a-z]+:/, '');
  if (bare !== token) return null; // keep responsive/state variants as-is
  return CLASS_GROUPS.find(([, re]) => re.test(bare))?.[0] ?? null;
}

/** Joins a default class list with overrides, dropping defaults the overrides replace. */
export function mergeClasses(base: string, extra?: string): string {
  if (!extra) return base;
  const overridden = new Set(extra.split(/\s+/).map(groupOf).filter(Boolean));
  const kept = base.split(/\s+/).filter((t) => {
    const g = groupOf(t);
    return !g || !overridden.has(g);
  });
  return `${kept.join(' ')} ${extra}`;
}

/* ------------------------------------------------------------------ */
/* Tones                                                                */
/* ------------------------------------------------------------------ */

export type Tone = 'indigo' | 'violet' | 'emerald' | 'rose' | 'amber' | 'sky' | 'teal' | 'orange' | 'slate';

export const TONE_CHIP: Record<Tone, string> = {
  indigo: 'bg-indigo-500/10 border-indigo-500/20 text-indigo-300',
  violet: 'bg-violet-500/10 border-violet-500/20 text-violet-300',
  emerald: 'bg-emerald-500/10 border-emerald-500/20 text-emerald-300',
  rose: 'bg-rose-500/10 border-rose-500/20 text-rose-300',
  amber: 'bg-amber-500/10 border-amber-500/20 text-amber-300',
  sky: 'bg-sky-500/10 border-sky-500/20 text-sky-300',
  teal: 'bg-teal-500/10 border-teal-500/20 text-teal-300',
  orange: 'bg-orange-500/10 border-orange-500/20 text-orange-300',
  slate: 'bg-slate-800/70 border-slate-700/70 text-slate-300',
};

export const TONE_TEXT: Record<Tone, string> = {
  indigo: 'text-indigo-300',
  violet: 'text-violet-300',
  emerald: 'text-emerald-300',
  rose: 'text-rose-300',
  amber: 'text-amber-300',
  sky: 'text-sky-300',
  teal: 'text-teal-300',
  orange: 'text-orange-300',
  slate: 'text-slate-300',
};

const TONE_DOT: Record<Tone, string> = {
  indigo: 'bg-indigo-400',
  violet: 'bg-violet-400',
  emerald: 'bg-emerald-400',
  rose: 'bg-rose-400',
  amber: 'bg-amber-400',
  sky: 'bg-sky-400',
  teal: 'bg-teal-400',
  orange: 'bg-orange-400',
  slate: 'bg-slate-400',
};

/* ------------------------------------------------------------------ */
/* Layout                                                               */
/* ------------------------------------------------------------------ */

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

/* ------------------------------------------------------------------ */
/* Buttons                                                              */
/* ------------------------------------------------------------------ */

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

/* ------------------------------------------------------------------ */
/* Form controls                                                        */
/* ------------------------------------------------------------------ */

export const inputCls =
  'w-full h-10 bg-slate-950/70 border border-slate-800 hover:border-slate-700 focus:border-indigo-500 rounded-xl px-3.5 text-[13px] text-white placeholder-slate-600 outline-none disabled:opacity-60';

const LABELABLE = new Set<unknown>(['input', 'select', 'textarea']);

export function Field({
  label,
  hint,
  children,
  className,
  htmlFor,
}: {
  label: React.ReactNode;
  hint?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
  htmlFor?: string;
}) {
  const autoId = useId();
  // Link the label to a single form control child so it is announced and clickable.
  let control = children;
  let targetId = htmlFor;
  if (!targetId && React.isValidElement<{ id?: string }>(children)) {
    const type = children.type;
    if (LABELABLE.has(type) || type === Input || type === Select || type === Textarea || type === AmountInput) {
      targetId = children.props.id ?? autoId;
      control = React.cloneElement(children, { id: targetId });
    }
  }
  return (
    <div className={className}>
      <label htmlFor={targetId} className="block text-[11px] font-bold text-slate-400 mb-1.5">
        {label}
      </label>
      {control}
      {hint && <p className="text-[10px] text-slate-500 mt-1.5 leading-relaxed">{hint}</p>}
    </div>
  );
}

export function Input({ className, ...rest }: React.InputHTMLAttributes<HTMLInputElement>) {
  return <input className={mergeClasses(inputCls, className)} {...rest} />;
}

export function Select({ className, children, ...rest }: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select className={mergeClasses(`${inputCls} cursor-pointer`, className)} {...rest}>
      {children}
    </select>
  );
}

export function Textarea({ className, ...rest }: React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea className={mergeClasses(inputCls, cn('h-auto py-2.5 resize-none leading-relaxed', className))} {...rest} />;
}

/** Numeric amount input that accepts pasted text and keeps only digits. */
export function AmountInput({
  value,
  onValueChange,
  className,
  ...rest
}: Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange'> & {
  value: number;
  onValueChange: (value: number) => void;
}) {
  return (
    <input
      inputMode="numeric"
      dir="ltr"
      value={value ? value.toLocaleString('en-US') : ''}
      onChange={(e) => onValueChange(Number(e.target.value.replace(/\D/g, '')) || 0)}
      className={mergeClasses(`${inputCls} text-left font-mono`, className)}
      {...rest}
    />
  );
}

export function SearchInput({
  value,
  onChange,
  placeholder = 'بحث...',
  className,
}: {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  className?: string;
}) {
  return (
    <div className={cn('relative', className)}>
      <Search className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className={mergeClasses(inputCls, 'h-9 pr-9 text-xs')}
      />
      {value && (
        <button
          type="button"
          onClick={() => onChange('')}
          aria-label="مسح البحث"
          className="absolute left-2 top-1/2 -translate-y-1/2 p-1 rounded-md text-slate-500 hover:text-white cursor-pointer"
        >
          <X className="w-3.5 h-3.5" />
        </button>
      )}
    </div>
  );
}

export function FilterSelect({
  icon: Icon,
  value,
  onChange,
  children,
  className,
}: {
  icon?: LucideIcon;
  value: string;
  onChange: (value: string) => void;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('relative', className)}>
      {Icon && <Icon className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />}
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className={mergeClasses(inputCls, cn('h-9 text-xs cursor-pointer', Icon && 'pr-9'))}
      >
        {children}
      </select>
    </div>
  );
}

export function Toggle({
  checked,
  onChange,
  label,
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  label?: React.ReactNode;
}) {
  return (
    <label className="inline-flex items-center gap-2.5 cursor-pointer select-none">
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={cn(
          'relative w-9 h-5 rounded-full transition-colors cursor-pointer',
          checked ? 'bg-emerald-500' : 'bg-slate-700',
        )}
      >
        <span
          className={cn(
            'absolute top-0.5 w-4 h-4 rounded-full bg-white shadow transition-all',
            checked ? 'right-0.5' : 'right-[18px]',
          )}
        />
      </button>
      {label && <span className="text-xs font-semibold text-slate-300">{label}</span>}
    </label>
  );
}

/* ------------------------------------------------------------------ */
/* Display                                                              */
/* ------------------------------------------------------------------ */

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

/** Scrollable wrapper that applies the shared `.data-table` styles. */
export function DataTable({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className={cn('overflow-x-auto rounded-2xl border border-slate-800/80 bg-slate-950/30', className)}>
      <table className="data-table">{children}</table>
    </div>
  );
}

export function TableEmpty({ colSpan, children }: { colSpan: number; children: React.ReactNode }) {
  return (
    <tr>
      <td colSpan={colSpan} className="!py-12 text-center text-slate-500 text-xs">
        {children}
      </td>
    </tr>
  );
}

export function PageSkeleton({ rows = 6 }: { rows?: number }) {
  return (
    <div className="space-y-6" aria-busy="true" aria-live="polite">
      <div className="flex items-center gap-3.5">
        <div className="skeleton w-11 h-11 rounded-2xl" />
        <div className="space-y-2">
          <div className="skeleton h-4 w-48" />
          <div className="skeleton h-3 w-72" />
        </div>
      </div>
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="skeleton h-24 rounded-2xl" />
        ))}
      </div>
      <div className="surface rounded-3xl p-5 space-y-3">
        {Array.from({ length: rows }).map((_, i) => (
          <div key={i} className="skeleton h-11 rounded-xl" />
        ))}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Modal                                                                */
/* ------------------------------------------------------------------ */

// Only the top-most open modal reacts to Escape.
const modalStack: number[] = [];
let modalSeq = 0;

const MODAL_SIZES = { sm: 'max-w-sm', md: 'max-w-lg', lg: 'max-w-2xl', xl: 'max-w-4xl' };

export function Modal({
  title,
  subtitle,
  icon: Icon,
  tone = 'indigo',
  onClose,
  children,
  footer,
  size = 'md',
}: {
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  icon?: LucideIcon;
  tone?: Tone | 'brand';
  onClose: () => void;
  children: React.ReactNode;
  footer?: React.ReactNode;
  size?: keyof typeof MODAL_SIZES;
}) {
  const [id] = useState(() => ++modalSeq);
  const [depth] = useState(() => modalStack.length);
  const onCloseRef = useRef(onClose);

  useEffect(() => {
    onCloseRef.current = onClose;
  });

  useEffect(() => {
    modalStack.push(id);
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && modalStack[modalStack.length - 1] === id) {
        e.stopPropagation();
        onCloseRef.current();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('keydown', onKey);
      const idx = modalStack.indexOf(id);
      if (idx >= 0) modalStack.splice(idx, 1);
    };
  }, [id]);

  const iconCls =
    tone === 'brand'
      ? 'bg-gradient-to-br from-indigo-500 to-violet-600 text-white border-transparent shadow-lg shadow-indigo-500/25'
      : TONE_CHIP[tone];

  return (
    <div
      className="fixed inset-0 flex items-start sm:items-center justify-center p-4 bg-black/70 backdrop-blur-sm overflow-y-auto"
      style={{ zIndex: 50 + depth * 2 }}
      onMouseDown={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        className={cn('relative w-full surface-solid rounded-3xl my-8 animate-glass text-right', MODAL_SIZES[size])}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="flex items-start gap-3 p-5 md:p-6 border-b border-slate-800/80">
          {Icon && (
            <div className={cn('w-10 h-10 shrink-0 rounded-xl border flex items-center justify-center', iconCls)}>
              <Icon className="w-5 h-5" />
            </div>
          )}
          <div className="flex-1 min-w-0">
            <h3 className="text-base font-extrabold text-white">{title}</h3>
            {subtitle && <p className="text-[11px] text-slate-500 mt-0.5 leading-relaxed">{subtitle}</p>}
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-2 -m-1 rounded-lg text-slate-500 hover:text-white hover:bg-slate-800 transition-colors cursor-pointer"
            aria-label="إغلاق"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="p-5 md:p-6">{children}</div>
        {footer && <div className="px-5 md:px-6 pb-5 md:pb-6 -mt-1">{footer}</div>}
      </div>
    </div>
  );
}

export function ModalFooter({
  onCancel,
  loading,
  submitLabel,
  loadingLabel,
  variant = 'primary',
  submitIcon,
  cancelLabel = 'إلغاء',
  onSubmit,
  disabled,
}: {
  onCancel: () => void;
  loading?: boolean;
  submitLabel?: string;
  loadingLabel?: string;
  variant?: ButtonVariant;
  submitIcon?: LucideIcon;
  cancelLabel?: string;
  /** When given, the submit button is a plain button calling this handler. */
  onSubmit?: () => void;
  disabled?: boolean;
}) {
  return (
    <div className="flex items-center justify-end gap-2 pt-4 mt-5 border-t border-slate-800/80">
      <Button variant="ghost" onClick={onCancel}>
        {cancelLabel}
      </Button>
      {submitLabel && (
        <Button
          type={onSubmit ? 'button' : 'submit'}
          onClick={onSubmit}
          variant={variant}
          icon={submitIcon}
          loading={loading}
          disabled={disabled}
        >
          {loading && loadingLabel ? loadingLabel : submitLabel}
        </Button>
      )}
    </div>
  );
}
