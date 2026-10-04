'use client';

// عناصر النماذج: Field وحقول الإدخال والبحث والفلاتر وToggle.

import React, { useId } from 'react';
import { Search, X, type LucideIcon } from 'lucide-react';
import { cn, mergeClasses } from './classes';

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
