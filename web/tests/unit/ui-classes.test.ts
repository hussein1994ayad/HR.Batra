import { describe, expect, it } from 'vitest';
import { mergeClasses } from '@/components/ui';

describe('mergeClasses', () => {
  const base = 'w-full h-10 px-3.5 text-[13px] text-white rounded-xl';
  it('lets callers override width, height and font size', () => {
    const out = mergeClasses(base, 'w-40 h-9 text-xs');
    expect(out.split(' ')).not.toContain('w-full');
    expect(out.split(' ')).not.toContain('h-10');
    expect(out.split(' ')).not.toContain('text-[13px]');
    expect(out).toContain('w-40');
    expect(out).toContain('text-white');
  });
  it('keeps unrelated classes and variants', () => {
    expect(mergeClasses(base, 'sm:w-40 text-left')).toContain('w-full');
    expect(mergeClasses(base, 'text-left')).toContain('text-[13px]');
    expect(mergeClasses(base)).toBe(base);
  });
});
