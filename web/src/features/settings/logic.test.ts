import { describe, expect, it } from 'vitest';
import { ARABIC_MONTH_NAMES, purgeSummary } from './logic';

describe('purgeSummary', () => {
  it('lists counts for the selected categories only', () => {
    const msg = purgeSummary(
      { year: 2026, month: 1, notifications: true, tracking: false, absences: true },
      { notifications_deleted: 4, absences_deleted: 10, tracking_deleted: 99 },
    );
    expect(msg).toBe('تم التنظيف بنجاح! 🧹 تم حذف: 4 إشعار، 10 سجل حضور وغياب');
  });

  it('has twelve Iraqi month names', () => {
    expect(ARABIC_MONTH_NAMES).toHaveLength(12);
    expect(ARABIC_MONTH_NAMES[8]).toBe('أيلول');
  });
});
