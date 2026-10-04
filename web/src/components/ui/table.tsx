'use client';

// الجداول وحالة التحميل (DataTable, TableEmpty, PageSkeleton).

import React from 'react';
import { cn } from './classes';

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
