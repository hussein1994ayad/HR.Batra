import { describe, expect, it, vi } from 'vitest';

vi.mock('@/lib/supabase', () => ({ supabase: {} }));

import { isDashboardRole } from './api';

describe('isDashboardRole', () => {
  it('only admin and manager may open the dashboard', () => {
    expect(isDashboardRole('admin')).toBe(true);
    expect(isDashboardRole('manager')).toBe(true);
    expect(isDashboardRole('employee')).toBe(false);
    expect(isDashboardRole(undefined)).toBe(false);
  });
});
