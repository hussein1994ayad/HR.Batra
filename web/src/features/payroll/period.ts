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

/** أول مسير في محرّك الرواتب (قبله كشوف قديمة بالأشهر الكاملة). */
export const FIRST_ENGINE_MONTH = '2026-09';

const addMonths = (month: string, n: number) => {
  const [y, m] = month.split('-').map(Number);
  const d = new Date(Date.UTC(y, m - 1 + n, 1));
  return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}`;
};

/**
 * قائمة المسيرات بالتسلسل (الأقدم ← الأحدث) حول المسير الحالي، مع رقم الشهر وفترته:
 * "10 / 2026 · 27-09 ← 26-10".
 */
export function payrollMonthOptions(current: string, cutoffDay = 26, before = 12, after = 3) {
  const out: { value: string; label: string }[] = [];
  for (let i = -before; i <= after; i++) {
    const month = addMonths(current, i);
    const [y, m] = month.split('-');
    const short = (iso: string) => iso.slice(5).split('-').reverse().join('-');
    let range: string;
    if (month < FIRST_ENGINE_MONTH) range = 'كشوف قديمة';
    else if (month === FIRST_ENGINE_MONTH) range = `01-${m} ← ${pad2(cutoffDay)}-${m}`;
    else {
      const p = previewPayrollPeriod(month, cutoffDay, 30);
      range = `${short(p.start)} ← ${short(p.end)}`;
    }
    out.push({ value: month, label: `${m} / ${y} · ${range}` });
  }
  return out;
}
