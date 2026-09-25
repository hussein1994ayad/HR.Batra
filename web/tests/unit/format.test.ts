import { describe, expect, it } from 'vitest';
import {
  daysUntil,
  digitsOnly,
  errorMessage,
  escapeHtml,
  formatBytes,
  formatDuration,
  formatIQD,
  formatTime12h,
  initials,
  localDateStr,
  timeAgo,
} from '@/lib/format';

describe('formatIQD', () => {
  it('rounds and groups thousands', () => {
    expect(formatIQD(1250000)).toBe('1,250,000 د.ع');
    expect(formatIQD('999.6')).toBe('1,000 د.ع');
  });
  it('treats missing values as zero', () => {
    expect(formatIQD(null)).toBe('0 د.ع');
    expect(formatIQD(undefined)).toBe('0 د.ع');
  });
});

describe('formatBytes', () => {
  it('picks a sensible unit', () => {
    expect(formatBytes(0)).toBe('0 B');
    expect(formatBytes(512)).toBe('512 B');
    expect(formatBytes(1536)).toBe('1.5 KB');
    expect(formatBytes(734003200)).toBe('700.0 MB');
    expect(formatBytes(3 * 1024 ** 3)).toBe('3.00 GB');
  });
});

describe('formatTime12h', () => {
  it('converts database time columns', () => {
    expect(formatTime12h('09:00:00')).toBe('9:00 AM');
    expect(formatTime12h('17:30')).toBe('5:30 PM');
    expect(formatTime12h('00:05:00')).toBe('12:05 AM');
    expect(formatTime12h(null)).toBe('--:--');
  });
});

describe('formatDuration', () => {
  it('formats worked hours', () => {
    expect(formatDuration('2026-09-01T06:00:00Z', '2026-09-01T14:15:00Z')).toBe('8 س و 15 د');
  });
  it('returns a dash for incomplete or inverted ranges', () => {
    expect(formatDuration('2026-09-01T06:00:00Z', null)).toBe('-');
    expect(formatDuration('2026-09-01T14:00:00Z', '2026-09-01T06:00:00Z')).toBe('-');
  });
});

describe('timeAgo / daysUntil', () => {
  const now = new Date('2026-09-25T12:00:00Z').getTime();
  it('describes elapsed time in Arabic', () => {
    expect(timeAgo(null, now)).toBe('الآن');
    expect(timeAgo(new Date(now - 30_000), now)).toBe('الآن');
    expect(timeAgo(new Date(now - 5 * 60_000), now)).toBe('منذ 5 دقيقة');
    expect(timeAgo(new Date(now - 3 * 3_600_000), now)).toBe('منذ 3 ساعة');
    expect(timeAgo(new Date(now - 2 * 86_400_000), now)).toBe('منذ 2 يوم');
  });
  it('counts whole days remaining', () => {
    expect(daysUntil('2026-10-05T12:00:00Z', now)).toBe(10);
    expect(daysUntil('2026-09-24T12:00:00Z', now)).toBe(-1);
  });
});

describe('misc helpers', () => {
  it('uses the local calendar date', () => {
    // 22:30 UTC is already the next day in Baghdad (UTC+3).
    expect(localDateStr(new Date('2026-09-24T22:30:00Z'))).toBe('2026-09-25');
  });
  it('builds initials from Arabic names', () => {
    expect(initials('حسين أياد')).toBe('حأ');
    expect(initials('زينب')).toBe('زي');
    expect(initials('')).toBe('?');
  });
  it('keeps only digits from pasted amounts', () => {
    expect(digitsOnly('1,500,000 د.ع')).toBe(1500000);
    expect(digitsOnly('abc')).toBe(0);
  });
  it('extracts messages from any thrown value', () => {
    expect(errorMessage(new Error('boom'))).toBe('boom');
    expect(errorMessage({ message: 'row violates policy' })).toBe('row violates policy');
    expect(errorMessage('plain')).toBe('plain');
    expect(errorMessage(42)).toBe('حدث خطأ غير متوقع');
  });
  it('escapes HTML for map popups', () => {
    expect(escapeHtml('<img src=x onerror="alert(1)">')).toBe('&lt;img src=x onerror=&quot;alert(1)&quot;&gt;');
  });
});
