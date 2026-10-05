'use client';

// البحث السريع (Ctrl/⌘+K): انتقال لأي صفحة يقدر يشوفها المستخدم، بالأسهم وEnter.

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { CornerDownLeft, Search } from 'lucide-react';
import { canSeePath, type DashboardRole } from '@/lib/role';
import { ALL_ITEMS } from '../nav';

export function CommandPalette({
  role,
  onClose,
  onNavigate,
  currentHref,
}: {
  role: DashboardRole;
  onClose: () => void;
  onNavigate: (href: string) => void;
  currentHref?: string;
}) {
  const [query, setQuery] = useState('');
  const [index, setIndex] = useState(0);
  const listRef = useRef<HTMLDivElement>(null);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    const visible = ALL_ITEMS.filter((i) => canSeePath(role, i.href));
    if (!q) return visible;
    return visible.filter((i) => i.name.toLowerCase().includes(q) || i.description.toLowerCase().includes(q));
  }, [query, role]);

  useEffect(() => {
    const el = listRef.current?.querySelector<HTMLElement>(`[data-idx="${index}"]`);
    el?.scrollIntoView({ block: 'nearest' });
  }, [index]);

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setIndex((i) => Math.min(i + 1, results.length - 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setIndex((i) => Math.max(i - 1, 0));
    } else if (e.key === 'Enter' && results[index]) {
      e.preventDefault();
      onNavigate(results[index].href);
    } else if (e.key === 'Escape') {
      onClose();
    }
  };

  return (
    <div className="fixed inset-0 z-[70] flex items-start justify-center p-4 pt-[12vh] bg-black/60 backdrop-blur-sm" onClick={onClose}>
      <div className="w-full max-w-lg surface-solid rounded-2xl overflow-hidden animate-glass" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center gap-3 px-4 border-b border-slate-800">
          <Search className="w-4 h-4 text-slate-500 shrink-0" />
          <input
            autoFocus
            value={query}
            onChange={(e) => { setQuery(e.target.value); setIndex(0); }}
            onKeyDown={onKeyDown}
            placeholder="ابحث عن صفحة أو قسم..."
            className="flex-1 h-14 bg-transparent text-sm text-white placeholder-slate-500 outline-none focus-visible:shadow-none"
          />
          <kbd className="font-mono text-[10px] px-1.5 py-0.5 rounded-md bg-slate-800 border border-slate-700 text-slate-400">Esc</kbd>
        </div>
        <div ref={listRef} className="max-h-80 overflow-y-auto p-2">
          {results.length === 0 ? (
            <p className="py-10 text-center text-xs text-slate-500">لا توجد نتائج مطابقة</p>
          ) : (
            results.map((item, i) => {
              const Icon = item.icon;
              const selected = i === index;
              return (
                <button
                  key={item.href}
                  data-idx={i}
                  onMouseEnter={() => setIndex(i)}
                  onClick={() => onNavigate(item.href)}
                  className={`w-full flex items-center gap-3 p-2.5 rounded-xl text-right transition-colors cursor-pointer ${selected ? 'bg-indigo-500/15' : ''}`}
                >
                  <div className={`p-2 rounded-lg border ${selected ? 'bg-indigo-500/20 border-indigo-400/30 text-indigo-200' : 'bg-slate-800/70 border-slate-700/70 text-slate-400'}`}>
                    <Icon className="w-4 h-4" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className={`text-[13px] font-bold ${selected ? 'text-white' : 'text-slate-200'}`}>
                      {item.name}
                      {currentHref === item.href && <span className="mr-2 text-[10px] font-semibold text-slate-500">(الصفحة الحالية)</span>}
                    </p>
                    <p className="text-[11px] text-slate-500 truncate">{item.description}</p>
                  </div>
                  {selected && <CornerDownLeft className="w-4 h-4 text-slate-500" />}
                </button>
              );
            })
          )}
        </div>
      </div>
    </div>
  );
}
