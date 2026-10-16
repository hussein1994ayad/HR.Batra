// تدقيق 14/10/2026 — المرحلة 6 (BUG-007): الأوقات تنكتب وتنعرض بتوقيت بغداد حتى لو كمبيوتر الأدمن على توقيت ثاني.
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { baghdadDayEndIso, baghdadDayStartIso, baghdadHM, baghdadIso, getLocalDateStr } from '@/lib/dates';
import { formatClock, formatDate, localDateStr } from '@/lib/format';
import { formatTimeInputValue } from '@/features/tracking/logic';

let savedTz: string | undefined;
beforeAll(() => {
  savedTz = process.env.TZ;
  process.env.TZ = 'America/Los_Angeles'; // أدمن مسافر (أو كمبيوتر بتوقيت ثاني)
});
afterAll(() => {
  if (savedTz === undefined) delete process.env.TZ;
  else process.env.TZ = savedTz;
});

describe('Baghdad time on a computer set to another time zone', () => {
  it('the computer really is on another time zone in this test', () => {
    expect(new Date('2026-10-15T06:00:00Z').getHours()).toBe(23);
  });

  it('a manual punch typed as 09:00 is saved as 09:00 Baghdad', () => {
    expect(baghdadIso('2026-10-15', '09:00')).toBe('2026-10-15T06:00:00.000Z');
  });

  it('punch times are shown and edited in Baghdad time', () => {
    expect(formatClock('2026-10-15T06:00:00Z')).toBe('9:00 ص');
    expect(formatClock('2026-10-15T11:30:00Z')).toBe('2:30 م');
    expect(formatTimeInputValue('2026-10-15T06:05:00Z')).toBe('09:05');
    expect(baghdadHM('2026-10-15T21:10:00Z')).toEqual({ h: 0, m: 10 });
  });

  it('dates and "today" follow Baghdad', () => {
    expect(getLocalDateStr(new Date('2026-10-15T22:30:00Z'))).toBe('2026-10-16');
    expect(localDateStr(new Date('2026-10-15T20:30:00Z'))).toBe('2026-10-15');
    expect(formatDate('2026-10-15T22:30:00Z')).toBe('16/10/2026');
  });

  it('a day range covers the Baghdad day', () => {
    expect(baghdadDayStartIso('2026-10-15')).toBe('2026-10-14T21:00:00.000Z');
    expect(baghdadDayEndIso('2026-10-15')).toBe('2026-10-15T20:59:59.999Z');
  });
});
