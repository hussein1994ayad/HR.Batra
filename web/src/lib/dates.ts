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

const pad2 = (n: number) => n.toString().padStart(2, '0');

/**
 * بداية ونهاية الدورة المالية لشهر معيّن (YYYY-MM).
 * إذا كان يوم البداية أكبر من يوم النهاية (مثل 25 → 24) تبدأ الدورة في الشهر السابق.
 */
export function getCycleDates(monthStr: string, startDay = 25, endDay = 24): { start: string; end: string } {
  if (!monthStr) return { start: '', end: '' };
  const [year, month] = monthStr.split('-').map(Number);
  const lastDaySelected = new Date(year, month, 0).getDate();

  if (startDay <= endDay) {
    return {
      start: `${year}-${pad2(month)}-${pad2(Math.min(startDay, lastDaySelected))}`,
      end: `${year}-${pad2(month)}-${pad2(Math.min(endDay, lastDaySelected))}`,
    };
  }

  const prevMonthDate = new Date(year, month - 2, 1);
  const prevYear = prevMonthDate.getFullYear();
  const prevMonthNum = prevMonthDate.getMonth() + 1;
  const lastDayPrev = new Date(prevYear, prevMonthNum, 0).getDate();
  return {
    start: `${prevYear}-${pad2(prevMonthNum)}-${pad2(Math.min(startDay, lastDayPrev))}`,
    end: `${year}-${pad2(month)}-${pad2(Math.min(endDay, lastDaySelected))}`,
  };
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

/** دقائق اليوم بتوقيت بغداد (UTC+3) لطابع زمني ISO. */
export function getBaghdadMinutesFromIso(isoStr: string): number {
  const d = new Date(isoStr);
  if (Number.isNaN(d.getTime())) return 0;
  const baghdadHours = (d.getUTCHours() + 3) % 24;
  return baghdadHours * 60 + d.getUTCMinutes();
}

/** "HH:MM[:SS]" → دقائق منذ منتصف الليل. */
export function parseScheduleMinutes(timeStr = '09:00:00'): number {
  const parts = timeStr.split(':').map(Number);
  return (parts[0] || 0) * 60 + (parts[1] || 0);
}

/** تاريخ اليوم المحلي بصيغة YYYY-MM-DD. */
export function getLocalDateStr(date: Date = new Date()): string {
  const d = new Date(date);
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset());
  return d.toISOString().split('T')[0];
}

/** YYYY-MM-DD لتاريخ محلي (بدون تحويل للـ UTC). */
export function toDateStr(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}
