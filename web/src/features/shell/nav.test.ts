import { describe, expect, it } from 'vitest';
import { findActiveItem, initialsOf } from './nav';

describe('dashboard navigation', () => {
  it('highlights the longest matching section, including nested routes', () => {
    expect(findActiveItem('/dashboard')?.href).toBe('/dashboard');
    expect(findActiveItem('/dashboard/loans')?.href).toBe('/dashboard/loans');
    expect(findActiveItem('/dashboard/loans/123')?.href).toBe('/dashboard/loans');
    expect(findActiveItem('/dashboard/unknown')).toBeUndefined();
  });

  it('builds two-letter initials with Arabic fallbacks', () => {
    expect(initialsOf('حسين أياد')).toBe('حأ');
    expect(initialsOf('علي')).toBe('عل');
    expect(initialsOf('')).toBe('مد');
  });
});
