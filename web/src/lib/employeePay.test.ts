import { beforeEach, describe, expect, it, vi } from 'vitest';

// سيرفر وهمي: الدالة الجديدة، أو سيرفر قديم بدونها (PGRST202) فالراتب ينقرا مباشرة
let oldServer = false;
const tableReads: { table: string; select: string; ids?: unknown }[] = [];

vi.mock('@/lib/supabase', () => ({
  supabase: {
    rpc: () =>
      Promise.resolve(
        oldServer
          ? { data: null, error: { code: 'PGRST202', message: 'function not found' } }
          : { data: [{ employee_id: 'e1', monthly_salary_iqd: 900000, future_salary_iqd: null, future_salary_month: null }], error: null },
      ),
    from: (table: string) => {
      const read = { table, select: '' } as { table: string; select: string; ids?: unknown };
      const q = {
        select: (cols: string) => ((read.select = cols), tableReads.push(read), q),
        in: (_col: string, ids: unknown) => ((read.ids = ids), q),
        then: (resolve: (v: unknown) => void) =>
          resolve({ data: [{ id: 'e2', monthly_salary_iqd: 750000, future_salary_iqd: 800000, future_salary_month: '2026-12' }], error: null }),
      };
      return q;
    },
  },
}));

import { EMPLOYEE_COLUMNS, fetchEmployeePay } from './employeePay';

describe('fetchEmployeePay', () => {
  beforeEach(() => {
    oldServer = false;
    tableReads.length = 0;
  });

  it('reads salaries from the server function', async () => {
    const pay = await fetchEmployeePay();
    expect(pay.e1.monthly_salary_iqd).toBe(900000);
    expect(tableReads).toHaveLength(0);
  });

  it('falls back to the old direct read before the database update', async () => {
    oldServer = true;
    const pay = await fetchEmployeePay(['e2']);
    expect(pay.e2).toEqual({ monthly_salary_iqd: 750000, future_salary_iqd: 800000, future_salary_month: '2026-12' });
    expect(tableReads[0]).toMatchObject({ table: 'employees', ids: ['e2'] });
  });

  it('the readable employee columns never include the salary', () => {
    for (const c of ['monthly_salary_iqd', 'future_salary_iqd', 'future_salary_month', 'plain_password']) {
      expect(EMPLOYEE_COLUMNS).not.toContain(c);
    }
  });
});
