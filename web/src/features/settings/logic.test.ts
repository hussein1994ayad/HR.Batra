import { describe, expect, it } from 'vitest';
import { ARABIC_MONTH_NAMES, attendanceBlockers, cleanupSummary } from './logic';
import type { CleanupPreview } from './types';

describe('payroll cleanup', () => {
  const preview = (over: Partial<CleanupPreview> = {}): CleanupPreview => ({
    month: '2026-09', start_date: '2026-09-01', end_date: '2026-09-26', status: 'closed', next_month: '2026-10', next_status: 'closed',
    checks: { closed: true, next_closed: true, pending_decisions: 0 },
    counts: { attendance: 10, tracking: 500, stops: 3, violations: 1, notifications: 40 },
    done: { attendance: false, tracking: false, notifications: false },
    can: { attendance: true, tracking: true, notifications: true },
    history: [],
    ...over,
  });

  it('lists counts for the requested categories only', () => {
    expect(cleanupSummary({ attendance_deleted: 10, tracking_deleted: null, notifications_deleted: 4 }))
      .toBe('تم التنظيف 🧹 انحذف: 10 سجل حضور، 4 إشعار');
    expect(cleanupSummary({ tracking_deleted: 500, stops_deleted: 3, violations_deleted: 1 }))
      .toBe('تم التنظيف 🧹 انحذف: 500 نقطة تتبع، 3 وقفة، 1 مخالفة');
  });

  it('explains why the attendance of a period cannot be deleted yet', () => {
    expect(attendanceBlockers(preview())).toEqual([]);
    expect(attendanceBlockers(preview({ checks: { closed: true, next_closed: false, pending_decisions: 2 } }))).toEqual([
      'لازم تعتمد وتغلق رواتب المسير اللي بعده (الشهر العاشر 2026) أولاً، حتى نتأكد ماكو شي يخص هذا المسير بعده معلّق.',
      'اكو 2 حركة (غياب/تأخير) لأيام هذا المسير تنتظر قرارك. احسمها أولاً.',
    ]);
    expect(attendanceBlockers(preview({ done: { attendance: true, tracking: false, notifications: false } }))).toEqual(['حضور هذا المسير منظّف مسبقاً.']);
  });

  it('has twelve Iraqi month names', () => {
    expect(ARABIC_MONTH_NAMES).toHaveLength(12);
    expect(ARABIC_MONTH_NAMES[8]).toBe('الشهر التاسع');
  });
});
