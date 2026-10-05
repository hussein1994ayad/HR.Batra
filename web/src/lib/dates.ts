// أدوات التواريخ والأوقات المشتركة بين صفحات لوحة التحكم.

/** أسماء الأشهر بالعربية كما تُعرض في كشوف الرواتب. */
export const ARABIC_MONTHS: Record<string, string> = {
  '01': 'كانون الثاني (يناير)',
  '02': 'شباط (فبراير)',
  '03': 'آذار (مارس)',
  '04': 'نيسان (أبريل)',
  '05': 'أيار (مايو)',
  '06': 'حزيران (يونيو)',
  '07': 'تموز (يوليو)',
  '08': 'آب (أغسطس)',
  '09': 'أيلول (سبتمبر)',
  '10': 'تشرين الأول (أكتوبر)',
  '11': 'تشرين الثاني (نوفمبر)',
  '12': 'كانون الأول (ديسمبر)',
};

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
