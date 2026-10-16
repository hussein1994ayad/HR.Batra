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

// ---------------------------------------------------------------------
// توقيت بغداد (تدقيق 14/10 BUG-007): كل وقت ينكتب وينعرض بتوقيت بغداد، مهما كان توقيت كمبيوتر الأدمن.
// العراق ما بيه توقيت صيفي، فالفرق ثابت +3.
// ---------------------------------------------------------------------
export const BAGHDAD_OFFSET = '+03:00';
const BAGHDAD_MS = 3 * 3600 * 1000;

/** تاريخ (YYYY-MM-DD) + ساعة (HH:MM) بتوقيت بغداد ← ISO. */
export function baghdadIso(date: string, time: string): string {
  return new Date(`${date}T${time.length === 5 ? `${time}:00` : time}${BAGHDAD_OFFSET}`).toISOString();
}

/** بداية ونهاية يوم بغداد (لفلترة الأوقات بيوم معيّن). */
export const baghdadDayStartIso = (date: string) => baghdadIso(date, '00:00:00');
export const baghdadDayEndIso = (date: string) => baghdadIso(date, '23:59:59.999');

/** الساعة والدقيقة بتوقيت بغداد لوقت معيّن. */
export function baghdadHM(value: string | number | Date): { h: number; m: number } {
  const d = new Date(new Date(value).getTime() + BAGHDAD_MS);
  return { h: d.getUTCHours(), m: d.getUTCMinutes() };
}

/** تاريخ يوم بغداد (YYYY-MM-DD) لوقت معيّن، والافتراضي اليوم (كان تاريخ كمبيوتر الأدمن). */
export function getLocalDateStr(date: Date = new Date()): string {
  return new Date(new Date(date).getTime() + BAGHDAD_MS).toISOString().slice(0, 10);
}

/** يضيف أياماً لتاريخ YYYY-MM-DD ويرجع YYYY-MM-DD (حساب تقويمي بدون منطقة زمنية). */
export function addDaysStr(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + days));
  return t.toISOString().slice(0, 10);
}
