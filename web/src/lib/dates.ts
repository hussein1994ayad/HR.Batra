// أدوات التواريخ والأوقات المشتركة بين صفحات لوحة التحكم.

/** ترتيب الأشهر: نكتب «الشهر العاشر» بدل «تشرين الأول» (أوضح للكل، نفس التطبيق). */
export const MONTH_ORDINALS = [
  'الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس',
  'السابع', 'الثامن', 'التاسع', 'العاشر', 'الحادي عشر', 'الثاني عشر',
];

/** 10 → "الشهر العاشر". */
export function monthOrdinal(m: number): string {
  return `الشهر ${MONTH_ORDINALS[m - 1] ?? m}`;
}

const DAY_NAMES = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

/** "2026-09-27" → "الأحد 27/9" (بالأرقام، والسنة إذا طلبت: "الأحد 27/9/2026"). */
export function arabicDate(iso: string | null | undefined, withYear = false): string {
  if (!iso) return '';
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number);
  const day = DAY_NAMES[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
  return `${day} ${d}/${m}${withYear ? `/${y}` : ''}`;
}

/** مدة بالدقائق بصيغة عربية مقروءة: "ساعتين و 5 دقائق". */
export function formatLateDurationArabic(minutes: number): string {
  if (minutes <= 0) return '0 دقيقة';
  const hrs = Math.floor(minutes / 60);
  const mins = minutes % 60;

  let hrsStr = '';
  if (hrs > 0) {
    if (hrs === 1) hrsStr = 'ساعة';
    else if (hrs === 2) hrsStr = 'ساعتين';
    else if (hrs >= 3 && hrs <= 10) hrsStr = `${hrs} ساعات`;
    else hrsStr = `${hrs} ساعة`;
  }

  let minsStr = '';
  if (mins > 0) {
    if (mins === 1) minsStr = 'دقيقة واحدة';
    else if (mins === 2) minsStr = 'دقيقتين';
    else if (mins >= 3 && mins <= 10) minsStr = `${mins} دقائق`;
    else minsStr = `${mins} دقيقة`;
  }

  if (hrsStr && minsStr) return `${hrsStr} و ${minsStr}`;
  return hrsStr || minsStr;
}

/** تاريخ اليوم المحلي بصيغة YYYY-MM-DD. */
export function getLocalDateStr(date: Date = new Date()): string {
  const d = new Date(date);
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
  return d.toISOString().split('T')[0];
}

/** يضيف أياماً لتاريخ YYYY-MM-DD ويرجع YYYY-MM-DD (حساب تقويمي بدون منطقة زمنية). */
export function addDaysStr(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + days));
  return t.toISOString().slice(0, 10);
}
