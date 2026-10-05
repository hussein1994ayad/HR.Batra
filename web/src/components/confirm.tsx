'use client';

// Promise-based confirmation dialog that replaces the browser's confirm().
// Usage: const confirm = useConfirm(); if (await confirm({ title, message })) { ... }
// With a note: const ask = useConfirmNote(); const note = await ask({ title, note: { presets } }); // null = cancelled

import React, { createContext, useCallback, useContext, useRef, useState } from 'react';
import { AlertTriangle, type LucideIcon } from 'lucide-react';
import { Button, Input, Modal, type ButtonVariant, type Tone } from './ui';

export interface ConfirmOptions {
  title: string;
  message?: React.ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  tone?: 'danger' | 'warning' | 'primary';
  icon?: LucideIcon;
  /** حقل ملاحظة (اختياري) مع ملاحظات جاهزة تنضغط. */
  note?: { presets?: readonly string[]; placeholder?: string; initial?: string };
}

type ConfirmFn = (options: ConfirmOptions) => Promise<boolean>;
type ConfirmNoteFn = (options: ConfirmOptions) => Promise<string | null>;
type Answer = { ok: boolean; note: string };

const ConfirmContext = createContext<((options: ConfirmOptions) => Promise<Answer>) | null>(null);

const TONES: Record<NonNullable<ConfirmOptions['tone']>, { tone: Tone; button: ButtonVariant }> = {
  danger: { tone: 'rose', button: 'danger' },
  warning: { tone: 'amber', button: 'warning' },
  primary: { tone: 'indigo', button: 'primary' },
};

export function ConfirmProvider({ children }: { children: React.ReactNode }) {
  const [options, setOptions] = useState<ConfirmOptions | null>(null);
  const [note, setNote] = useState('');
  const resolver = useRef<((value: Answer) => void) | null>(null);

  const ask = useCallback((opts: ConfirmOptions) => {
    resolver.current?.({ ok: false, note: '' });
    setOptions(opts);
    setNote(opts.note?.initial ?? '');
    return new Promise<Answer>((resolve) => {
      resolver.current = resolve;
    });
  }, []);

  const settle = (ok: boolean) => {
    resolver.current?.({ ok, note: note.trim() });
    resolver.current = null;
    setOptions(null);
  };

  const t = TONES[options?.tone ?? 'danger'];

  return (
    <ConfirmContext.Provider value={ask}>
      {children}
      {options && (
        <Modal
          title={options.title}
          icon={options.icon ?? AlertTriangle}
          tone={t.tone}
          size="sm"
          onClose={() => settle(false)}
        >
          {options.message && <div className="text-xs text-slate-300 leading-relaxed whitespace-pre-line">{options.message}</div>}
          {options.note && (
            <div className="mt-4 space-y-2">
              <Input value={note} onChange={(e) => setNote(e.target.value)} placeholder={options.note.placeholder ?? 'ملاحظة (اختياري)'}
                aria-label="ملاحظة" className="h-9 text-xs" />
              {options.note.presets && options.note.presets.length > 0 && (
                <div className="flex flex-wrap gap-1.5">
                  {options.note.presets.map((p) => (
                    <button key={p} type="button" onClick={() => setNote(p)}
                      className={`px-2.5 py-1 rounded-full border text-[11px] transition-colors ${note === p
                        ? 'bg-indigo-500/20 border-indigo-400/40 text-indigo-100'
                        : 'border-slate-700 text-slate-300 hover:bg-slate-800'}`}>
                      {p}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
          <div className="flex items-center gap-2 mt-6">
            <Button variant={t.button} block onClick={() => settle(true)}>
              {options.confirmLabel ?? 'تأكيد'}
            </Button>
            <Button variant="secondary" block autoFocus onClick={() => settle(false)}>
              {options.cancelLabel ?? 'إلغاء'}
            </Button>
          </div>
        </Modal>
      )}
    </ConfirmContext.Provider>
  );
}

export function useConfirm(): ConfirmFn {
  const ctx = useContext(ConfirmContext);
  if (!ctx) {
    // Outside the provider (should not happen in the dashboard) fall back to the native dialog.
    return async (opts) => window.confirm(opts.title);
  }
  return async (opts) => (await ctx(opts)).ok;
}

/** تأكيد مع ملاحظة: يرجّع نص الملاحظة (قد يكون فارغاً) عند التأكيد، و null عند الإلغاء. */
export function useConfirmNote(): ConfirmNoteFn {
  const ctx = useContext(ConfirmContext);
  if (!ctx) {
    return async (opts) => (window.confirm(opts.title) ? '' : null);
  }
  return async (opts) => {
    const a = await ctx(opts);
    return a.ok ? a.note : null;
  };
}
