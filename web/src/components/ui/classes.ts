// أدوات أسماء الكلاسات والألوان (Tones) المشتركة لمكوّنات الواجهة.

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

export const TONE_DOT: Record<Tone, string> = {
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
