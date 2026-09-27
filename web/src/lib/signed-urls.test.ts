import { describe, expect, it, vi } from 'vitest';

vi.mock('@/lib/supabase', () => ({ supabase: {} }));
const { parseStorageUrl } = await import('./signed-urls');

const base = 'https://x.supabase.co/storage/v1/object';

describe('parseStorageUrl', () => {
  it('recognises private buckets', () => {
    expect(parseStorageUrl(`${base}/public/employee-documents/e1/a.jpg`)).toEqual({ bucket: 'employee-documents', path: 'e1/a.jpg' });
    expect(parseStorageUrl(`${base}/sign/loan-pledges/p/u1/b.png?token=t`)).toEqual({ bucket: 'loan-pledges', path: 'p/u1/b.png' });
  });

  it('leaves public buckets and other links alone', () => {
    expect(parseStorageUrl(`${base}/public/avatars/u1.jpg`)).toBeNull();
    expect(parseStorageUrl('https://example.com/x.pdf')).toBeNull();
  });
});
