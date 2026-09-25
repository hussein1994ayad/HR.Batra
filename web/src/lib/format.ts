// Small, dependency-free formatting helpers shared by dashboard pages.

/** Formats an amount in Iraqi dinars, e.g. `1,250,000 د.ع`. */
export function formatIQD(value: number | string | null | undefined): string {
  const n = Math.round(Number(value) || 0);
  return `${n.toLocaleString('en-US')} د.ع`;
}

export function formatNumber(value: number | string | null | undefined): string {
  return (Number(value) || 0).toLocaleString('en-US');
}

export function formatBytes(bytes: number | null | undefined): string {
  const b = Number(bytes) || 0;
  if (b <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.min(Math.floor(Math.log(b) / Math.log(1024)), units.length - 1);
  const value = b / Math.pow(1024, i);
  return `${value.toFixed(i === 0 ? 0 : i >= 3 ? 2 : 1)} ${units[i]}`;
}

/** `9:05 AM` style clock for an ISO timestamp, or `-` when missing/invalid. */
export function formatClock(iso: string | null | undefined): string {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '-';
  return d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true });
}

/** Converts a `HH:MM[:SS]` time column into `9:00 AM`. */
export function formatTime12h(timeStr: string | null | undefined): string {
  if (!timeStr) return '--:--';
  const parts = timeStr.split(':');
  if (parts.length < 2) return timeStr;
  let hour = parseInt(parts[0], 10);
  const minute = parseInt(parts[1], 10);
  if (isNaN(hour) || isNaN(minute)) return timeStr;
  const period = hour >= 12 ? 'PM' : 'AM';
  hour = hour % 12;
  if (hour === 0) hour = 12;
  return `${hour}:${minute.toString().padStart(2, '0')} ${period}`;
}

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '-';
  return d.toLocaleDateString('en-GB', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '-';
  return `${formatDate(iso)} · ${formatClock(iso)}`;
}

/** Working-hours duration between two timestamps, e.g. `8 س و 15 د`. */
export function formatDuration(checkIn: string | null | undefined, checkOut: string | null | undefined): string {
  if (!checkIn || !checkOut) return '-';
  const diffMs = new Date(checkOut).getTime() - new Date(checkIn).getTime();
  if (!(diffMs > 0)) return '-';
  const hours = Math.floor(diffMs / 3_600_000);
  const mins = Math.floor((diffMs % 3_600_000) / 60_000);
  return `${hours} س و ${mins} د`;
}

export function timeAgo(date: Date | null, now: number = Date.now()): string {
  if (!date) return 'الآن';
  const mins = Math.floor((now - date.getTime()) / 60000);
  if (mins < 1) return 'الآن';
  if (mins < 60) return `منذ ${mins} دقيقة`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `منذ ${hours} ساعة`;
  return `منذ ${Math.floor(hours / 24)} يوم`;
}

/** Whole days from now until `iso` (negative when in the past). */
export function daysUntil(iso: string, now: number = Date.now()): number {
  return Math.ceil((new Date(iso).getTime() - now) / 86_400_000);
}

/** Today's date as `YYYY-MM-DD` in the browser's local timezone. */
export function localDateStr(d: Date = new Date()): string {
  const y = d.getFullYear();
  const m = (d.getMonth() + 1).toString().padStart(2, '0');
  const day = d.getDate().toString().padStart(2, '0');
  return `${y}-${m}-${day}`;
}

export function initials(name: string | null | undefined): string {
  const parts = (name || '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].substring(0, 2);
  return parts[0][0] + parts[1][0];
}

/** Strips everything but digits, for amount inputs that accept pasted text. */
export function digitsOnly(value: string): number {
  return Number(value.replace(/\D/g, '')) || 0;
}

export function errorMessage(err: unknown, fallback = 'حدث خطأ غير متوقع'): string {
  if (err instanceof Error) return err.message || fallback;
  if (err && typeof err === 'object' && 'message' in err) {
    const msg = (err as { message?: unknown }).message;
    if (typeof msg === 'string' && msg) return msg;
  }
  if (typeof err === 'string' && err) return err;
  return fallback;
}

/** Escapes text before it is interpolated into HTML strings (e.g. map popups). */
export function escapeHtml(value: string | null | undefined): string {
  return (value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export const MONTHS_AR = [
  'كانون الثاني',
  'شباط',
  'آذار',
  'نيسان',
  'أيار',
  'حزيران',
  'تموز',
  'آب',
  'أيلول',
  'تشرين الأول',
  'تشرين الثاني',
  'كانون الأول',
];

export const WEEKDAYS_AR = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
