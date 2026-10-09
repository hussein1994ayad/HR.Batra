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
 * قائمة المسيرات بالتسلسل (الأقدم ← الأحدث) حول المسير الحالي بأسماء الأشهر: "رواتب تشرين الأول 2026"
 * (فترة الدوام تنكتب تحت العنوان بجملة واضحة).
 */
export function payrollMonthOptions(current: string, before = 12, after = 3) {
  const out: { value: string; label: string }[] = [];
  for (let i = -before; i <= after; i++) {
    const month = addMonths(current, i);
    out.push({ value: month, label: `رواتب ${payrollMonthName(month)}${month < FIRST_ENGINE_MONTH ? ' (كشوف قديمة)' : ''}` });
  }
  return out;
}

/** تاريخ اليوم بتوقيت بغداد (YYYY-MM-DD) — مو UTC، حتى ما يرجع يوم بعد منتصف الليل. */
export function baghdadToday(now = new Date()): string {
  const { y, m, day } = baghdadParts(now);
  return `${y}-${pad2(m)}-${pad2(day)}`;
}

/** "2026-10" → "شهر 10 سنة 2026" (نفس صيغة الكشوف بالتطبيق) */
export function monthLabel(month: string): string {
  const [y, m] = month.split('-').map(Number);
  return `شهر ${m} سنة ${y}`;
}

const MONTH_NAMES = ['كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول'];
const DAY_NAMES = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

/** "2026-10" → "تشرين الأول 2026". */
export function payrollMonthName(month: string): string {
  const [y, m] = month.split('-').map(Number);
  return `${MONTH_NAMES[m - 1] ?? m} ${y}`;
}

/** "2026-09-27" → "الأحد 27 أيلول" (بدون السنة إلا إذا طلبت). */
export function arabicDate(iso: string | null | undefined, withYear = false): string {
  if (!iso) return '';
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number);
  const day = DAY_NAMES[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
  return `${day} ${d} ${MONTH_NAMES[m - 1]}${withYear ? ` ${y}` : ''}`;
}

/** شهر الرواتب اللي يتبعه تاريخ (نفس payroll_month_of بالسيرفر): بعد يوم القطع = الشهر الجاي. */
export function payrollMonthOfDate(iso: string, cutoffDay = 26): string {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number);
  if (d <= cutoffDay) return `${y}-${pad2(m)}`;
  return m === 12 ? `${y + 1}-01` : `${y}-${pad2(m + 1)}`;
}

/** المسير السابق/التالي. */
export function shiftPayrollMonth(month: string, n: number): string {
  return addMonths(month, n);
}

/** يوم القطع داخل شهر رواتب (تاريخ أول قسط افتراضي حتى ينخصم بنفس الشهر). */
export function cutoffDateOf(month: string, cutoffDay = 26): string {
  const [y, m] = month.split('-').map(Number);
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return `${y}-${pad2(m)}-${pad2(Math.min(cutoffDay, last))}`;
}
