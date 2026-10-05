'use client';

// النوافذ المنبثقة (Modal, ModalFooter) — Escape يغلق الأعلى فقط.

import React, { useEffect, useRef, useState } from 'react';
import { X, type LucideIcon } from 'lucide-react';
import { cn, Tone, TONE_CHIP } from './classes';
import { ButtonVariant, Button } from './buttons';

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
