import { describe, expect, it } from 'vitest';
import { filterLeavesByName, LEAVE_TYPES, leaveDays } from './logic';

describe('leaveDays', () => {
  it('counts both ends inclusively', () => {
    expect(leaveDays({ start_date: '2026-10-01T00:00:00Z', end_date: '2026-10-03T00:00:00Z' })).toBe(3);
  });

  it('a single-day leave is 1', () => {
    expect(leaveDays({ start_date: '2026-10-05T08:00:00Z', end_date: '2026-10-05T12:00:00Z' })).toBe(1);
  });
});

describe('filterLeavesByName', () => {
  const list = [
    { id: '1', employees: { full_name: 'Ahmed Ali' } },
    { id: '2', employees: { full_name: 'سارة حسن' } },
    { id: '3', employees: null },
  ];

  it('empty search keeps everything', () => {
    expect(filterLeavesByName(list, '  ')).toHaveLength(3);
  });

  it('matches case-insensitively and skips rows without a name', () => {
    expect(filterLeavesByName(list, 'ahmed').map((r) => r.id)).toEqual(['1']);
    expect(filterLeavesByName(list, 'سارة').map((r) => r.id)).toEqual(['2']);
  });
});

it('LEAVE_TYPES has the four known types', () => {
  expect(Object.keys(LEAVE_TYPES)).toEqual(['annual', 'sick', 'emergency', 'maternity']);
});
