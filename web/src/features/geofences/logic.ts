// =========================================================================
// منطق صفحة الفروع الجغرافية — دوال نقية بدون React أو Supabase
// =========================================================================

import type { AttendanceRecord, Branch } from '@/lib/db-types';

export type LatLng = { lat: number; lng: number };

export const BAGHDAD: LatLng = { lat: 33.3152, lng: 44.3661 };
export const DEFAULT_RADIUS = 150;

/** مسافة هافرساين بالأمتار (نفس distance_meters في قاعدة البيانات). */
export function distanceMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371e3;
  const phi1 = (lat1 * Math.PI) / 180;
  const phi2 = (lat2 * Math.PI) / 180;
  const dPhi = ((lat2 - lat1) * Math.PI) / 180;
  const dLambda = ((lon2 - lon1) * Math.PI) / 180;
  const a = Math.sin(dPhi / 2) ** 2 + Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * يستخرج إحداثيات من رابط خرائط جوجل أو نص "lat, lng".
 * الترتيب: ‎@lat,lng ← q/ll/query=lat,lng ← /place/lat,lng ← أي زوج أرقام ضمن حدود العراق.
 */
export function extractCoordsFromText(text: string): LatLng | null {
  if (!text) return null;
  let decoded = text;
  try {
    decoded = decodeURIComponent(text);
  } catch {
    // نص غير مشفّر بشكل صحيح؛ يُفحص كما هو
  }

  const at = decoded.match(/@(-?\d+\.\d+),(-?\d+\.\d+)/);
  if (at) return { lat: parseFloat(at[1]), lng: parseFloat(at[2]) };

  const query = decoded.match(/[?&](q|ll|query|saddr|daddr)=(-?\d+\.\d+),(-?\d+\.\d+)/);
  if (query) return { lat: parseFloat(query[2]), lng: parseFloat(query[3]) };

  const place = decoded.match(/\/place\/(-?\d+\.\d+)(?:\+|,)(-?\d+\.\d+)/);
  if (place) return { lat: parseFloat(place[1]), lng: parseFloat(place[2]) };

  const generic = /(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)/g;
  let m: RegExpExecArray | null;
  while ((m = generic.exec(decoded)) !== null) {
    const lat = parseFloat(m[1]);
    const lng = parseFloat(m[2]);
    if (lat >= 29 && lat <= 38 && lng >= 38 && lng <= 49) return { lat, lng };
  }
  return null;
}

/** إحداثيات من صفحة خرائط جوجل (og:url، canonical، APP_INITIALIZATION_STATE، ثم أي نص). */
export function extractCoordsFromHtml(body: string): LatLng | null {
  const og = body.match(/property="og:url"\s+content="([^"]+)"/) || body.match(/content="([^"]+)"\s+property="og:url"/);
  const fromOg = og && extractCoordsFromText(og[1]);
  if (fromOg) return fromOg;

  const canonical = body.match(/rel="canonical"\s+href="([^"]+)"/) || body.match(/href="([^"]+)"\s+rel="canonical"/);
  const fromCanonical = canonical && extractCoordsFromText(canonical[1]);
  if (fromCanonical) return fromCanonical;

  // الترتيب هنا [lng, lat]
  const init = body.match(/APP_INITIALIZATION_STATE=\[\[\[(-?\d+\.\d+),(-?\d+\.\d+)/);
  if (init) return { lat: parseFloat(init[2]), lng: parseFloat(init[1]) };

  return extractCoordsFromText(body);
}

export interface BranchAttendee {
  id: string;
  name: string;
  phone: string;
  checkInTime: string;
  distanceText: string;
}

/** بصمات اليوم التابعة للفرع: مرتبطة به مباشرة، أو لموظف من الفرع، أو داخل نطاقه جغرافياً. */
export function branchAttendees(branch: Branch, logs: AttendanceRecord[]): BranchAttendee[] {
  const radius = branch.radius_meters || DEFAULT_RADIUS;
  const distanceOf = (log: AttendanceRecord) =>
    log.check_in_lat && log.check_in_lng
      ? distanceMeters(Number(log.check_in_lat), Number(log.check_in_lng), Number(branch.latitude), Number(branch.longitude))
      : null;

  return logs
    .filter(log => {
      if (log.branch_id === branch.id || log.employees?.branch_id === branch.id) return true;
      const d = distanceOf(log);
      return d !== null && d <= radius;
    })
    .map(log => {
      const d = distanceOf(log);
      return {
        id: log.id,
        name: log.employees?.full_name || 'موظف غير معروف',
        phone: log.employees?.phone || 'بلا هاتف',
        checkInTime: log.check_in_time
          ? new Date(log.check_in_time).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })
          : '-',
        distanceText: d !== null ? `على بُعد ${Math.round(d)} متر` : 'بصمة موجهة يدوياً للفرع',
      };
    });
}

export function mapCircles(branches: Branch[]) {
  return branches
    .filter(b => b.latitude && b.longitude)
    .map(b => ({ id: b.id, name: b.name, lat: b.latitude, lng: b.longitude, radius: b.radius_meters || DEFAULT_RADIUS }));
}

export type MapCircle = ReturnType<typeof mapCircles>[number];
