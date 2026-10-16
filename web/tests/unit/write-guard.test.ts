// تدقيق 14/10/2026 — المرحلة 9 (CODE-009): تعديل ما أثّر على ولا سطر = خطأ واضح، مو نجاح صامت.
import { describe, expect, it } from 'vitest';
import { NothingChangedError, ensureChanged } from '@/lib/write-guard';

describe('ensureChanged', () => {
  it('passes the changed rows through', async () => {
    await expect(ensureChanged(Promise.resolve({ data: [{ id: 'b1' }], error: null }))).resolves.toEqual([{ id: 'b1' }]);
  });
  it('a write blocked by a rule (zero rows) is an error the admin sees', async () => {
    await expect(ensureChanged(Promise.resolve({ data: [], error: null }))).rejects.toBeInstanceOf(NothingChangedError);
    await expect(ensureChanged(Promise.resolve({ data: null, error: null }))).rejects.toThrow('ما تغيّر شي');
  });
  it('a server error is passed on as it is', async () => {
    const error = { code: '42501', message: 'permission denied' };
    await expect(ensureChanged(Promise.resolve({ data: null, error }))).rejects.toBe(error);
  });
});
