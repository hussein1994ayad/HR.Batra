import { afterEach, describe, expect, it, vi } from 'vitest';
import { clearLocalCaches } from './local-cache';

function fakeStorage(initial: Record<string, string>) {
  const data = { ...initial };
  return new Proxy(data, {
    get(target, prop) {
      if (prop === 'removeItem') return (k: string) => { delete target[k]; };
      if (prop === 'getItem') return (k: string) => target[k] ?? null;
      return target[prop as string];
    },
  });
}

describe('clearLocalCaches', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('removes every batra_cache_* key and keeps the rest', () => {
    const store = fakeStorage({
      batra_cache_admin: '{}',
      batra_cache_employees: '{"salary":1}',
      batra_cache_geofences_v2: '{}',
      batra_sidebar_collapsed: '1',
      'sb-x-auth-token': 't',
    });
    vi.stubGlobal('localStorage', store);
    clearLocalCaches();
    expect(Object.keys(store).sort()).toEqual(['batra_sidebar_collapsed', 'sb-x-auth-token']);
  });

  it('ignores blocked storage', () => {
    vi.stubGlobal('localStorage', undefined);
    expect(() => clearLocalCaches()).not.toThrow();
  });
});
