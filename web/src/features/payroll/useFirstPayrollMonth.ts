'use client';

import { useQuery } from '@/lib/useQuery';
import { fetchFirstPayrollMonth } from './api';

/** أول مسير بالقاعدة: قوائم الأشهر تبدي منه (تدقيق 14/10 BUG-017). null لحد ما يوصل أو إذا ماكو مسيرات. */
export function useFirstPayrollMonth(): string | null {
  const q = useQuery('payroll:first-month', () => fetchFirstPayrollMonth().catch(() => null));
  return q.data ?? null;
}
