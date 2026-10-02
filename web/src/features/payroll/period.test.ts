import { describe, expect, it } from 'vitest';
import { baghdadToday, monthLabel } from './period';

describe('payroll dates', () => {
  it('today is the Baghdad date even right after midnight (UTC is still the day before)', () => {
    expect(baghdadToday(new Date('2026-10-26T22:30:00Z'))).toBe('2026-10-27');
    expect(baghdadToday(new Date('2026-10-27T20:59:00Z'))).toBe('2026-10-27');
  });

  it('labels a payroll month like the app', () => {
    expect(monthLabel('2026-10')).toBe('شهر 10 سنة 2026');
    expect(monthLabel('2027-01')).toBe('شهر 1 سنة 2027');
  });
});
