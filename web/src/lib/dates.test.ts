import { describe, expect, it } from 'vitest';
import { addDaysStr } from './dates';

describe('addDaysStr', () => {
  it('adds calendar days across months and years', () => {
    expect(addDaysStr('2026-09-27', 6)).toBe('2026-10-03');
    expect(addDaysStr('2026-12-30', 3)).toBe('2027-01-02');
    expect(addDaysStr('2028-02-28', 1)).toBe('2028-02-29');
    expect(addDaysStr('2026-09-27', 0)).toBe('2026-09-27');
  });
});
