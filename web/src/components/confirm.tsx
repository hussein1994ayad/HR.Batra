'use client';

// Promise-based confirmation dialog that replaces the browser's confirm().
// Usage: const confirm = useConfirm(); if (await confirm({ title, message })) { ... }

import React, { createContext, useCallback, useContext, useRef, useState } from 'react';
import { AlertTriangle, type LucideIcon } from 'lucide-react';
import { Button, Modal, type ButtonVariant, type Tone } from './ui';

export interface ConfirmOptions {
  title: string;
  message?: React.ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  tone?: 'danger' | 'warning' | 'primary';
  icon?: LucideIcon;
}

type ConfirmFn = (options: ConfirmOptions) => Promise<boolean>;

const ConfirmContext = createContext<ConfirmFn | null>(null);

const TONES: Record<NonNullable<ConfirmOptions['tone']>, { tone: Tone; button: ButtonVariant }> = {
  danger: { tone: 'rose', button: 'danger' },
  warning: { tone: 'amber', button: 'warning' },
  primary: { tone: 'indigo', button: 'primary' },
};

export function ConfirmProvider({ children }: { children: React.ReactNode }) {
  const [options, setOptions] = useState<ConfirmOptions | null>(null);
  const resolver = useRef<((value: boolean) => void) | null>(null);

  const confirm = useCallback<ConfirmFn>((opts) => {
    resolver.current?.(false);
    setOptions(opts);
    return new Promise<boolean>((resolve) => {
      resolver.current = resolve;
    });
  }, []);

  const settle = (value: boolean) => {
    resolver.current?.(value);
    resolver.current = null;
    setOptions(null);
  };

  const t = TONES[options?.tone ?? 'danger'];

  return (
    <ConfirmContext.Provider value={confirm}>
      {children}
      {options && (
        <Modal
          title={options.title}
          icon={options.icon ?? AlertTriangle}
          tone={t.tone}
          size="sm"
          onClose={() => settle(false)}
        >
          {options.message && <div className="text-xs text-slate-300 leading-relaxed">{options.message}</div>}
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
  return ctx;
}
