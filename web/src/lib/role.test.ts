import { describe, expect, it } from 'vitest';
import { canSeePath, isAdminOnlyPath } from './role';

describe('dashboard role', () => {
  it('hides payroll, loans, settings and system pages from branch managers', () => {
    for (const p of ['/dashboard/payroll', '/dashboard/loans', '/dashboard/settings', '/dashboard/storage', '/dashboard/trash']) {
      expect(canSeePath('manager', p)).toBe(false);
      expect(canSeePath('admin', p)).toBe(true);
    }
    expect(isAdminOnlyPath('/dashboard/settings/x')).toBe(true);
  });
  it('keeps the branch pages for managers', () => {
    for (const p of ['/dashboard', '/dashboard/employees', '/dashboard/tracking', '/dashboard/leaves', '/dashboard/geofences']) {
      expect(canSeePath('manager', p)).toBe(true);
    }
    expect(isAdminOnlyPath(null)).toBe(false);
  });
});
