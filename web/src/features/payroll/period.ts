// حساب مسير الرواتب الحالي في المتصفح (للاختيار الافتراضي والمعاينة فقط).
// التواريخ الحقيقية لكل مسير محفوظة في السيرفر (payroll_periods).

const pad2 = (n: number) => n.toString().padStart(2, '0');

/** توقيت بغداد (UTC+3 بدون توقيت صيفي) لتاريخ معيّن. */
function baghdadParts(now: Date) {
  const d = new Date(now.getTime() + 3 * 3600 * 1000);
  return { y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, day: d.getUTCDate() };
}

/** مسير اليوم: حتى يوم القطع = مسير نفس الشهر، بعده = مسير الشهر التالي. */
export function currentPayrollMonth(cutoffDay = 26, now = new Date()): string {
  const { y, m, day } = baghdadParts(now);
  if (day <= cutoffDay) return `${y}-${pad2(m)}`;
  return m === 12 ? `${y + 1}-01` : `${y}-${pad2(m + 1)}`;
}

/** معاينة فترة مسير شهر: من اليوم التالي لقطع الشهر السابق حتى يوم القطع. */
export function previewPayrollPeriod(month: string, cutoffDay: number, paymentDay: number) {
  const [y, m] = month.split('-').map(Number);
  const lastDay = (yy: number, mm: number) => new Date(Date.UTC(yy, mm, 0)).getUTCDate();
  const prevY = m === 1 ? y - 1 : y;
  const prevM = m === 1 ? 12 : m - 1;
  const prevCutoff = Math.min(cutoffDay, lastDay(prevY, prevM));
  const cutoff = Math.min(cutoffDay, lastDay(y, m));
  const start = prevCutoff === lastDay(prevY, prevM)
    ? `${y}-${pad2(m)}-01`
    : `${prevY}-${pad2(prevM)}-${pad2(prevCutoff + 1)}`;
  return {
    start,
    end: `${y}-${pad2(m)}-${pad2(cutoff)}`,
    payment: `${y}-${pad2(m)}-${pad2(Math.min(paymentDay, lastDay(y, m)))}`,
  };
}
