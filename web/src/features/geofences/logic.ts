// منطق صفحة الفروع والسياج الجغرافي — بدون React/Supabase.

import { distanceMeters } from '@/lib/geo';
import type { Attendance, Branch } from '@/lib/db-types';

/** نطاق البصمة الافتراضي (متر) لفرع بدون نطاق محفوظ. */
export const DEFAULT_RADIUS = 150;

/** مسودة إضافة/تعديل فرع (id فارغ = فرع جديد). */
export interface BranchDraft {
  id?: string;
  name: string;
  lat: number;
  lng: number;
  radius: number;
  address: string;
}

/** دوائر الفروع على الخريطة (الفروع بدون إحداثيات ما تظهر). */
export function branchCircles(branches: Branch[]) {
  return branches
    .filter((b) => b.latitude && b.longitude)
    .map((b) => ({ id: b.id, name: b.name, lat: Number(b.latitude), lng: Number(b.longitude), radius: Number(b.radius_meters) || DEFAULT_RADIUS }));
}

/**
 * حضور اليوم التابع لفرع: سجل الحضور على الفرع، أو الموظف تابع له، أو بصمته داخل نطاقه.
 * المسافة null إذا البصمة بدون إحداثيات.
 */
export function attendeesForBranch(selected: Branch, todayLogs: Attendance[]): { log: Attendance; distance: number | null }[] {
  const bLat = Number(selected.latitude);
  const bLng = Number(selected.longitude);
  const radius = Number(selected.radius_meters) || DEFAULT_RADIUS;
  return todayLogs
    .map((log) => {
      const hasCoords = !!log.check_in_lat && !!log.check_in_lng;
      const distance = hasCoords ? distanceMeters(Number(log.check_in_lat), Number(log.check_in_lng), bLat, bLng) : null;
      const belongs =
        log.branch_id === selected.id || log.employees?.branch_id === selected.id || (distance !== null && distance <= radius);
      return belongs ? { log, distance } : null;
    })
    .filter((x): x is { log: Attendance; distance: number | null } => x !== null);
}
