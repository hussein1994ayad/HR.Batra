import { describe, expect, it } from 'vitest';
import type { AttendanceRecord, Branch } from '@/lib/db-types';
import { branchAttendees, distanceMeters, extractCoordsFromHtml, extractCoordsFromText, mapCircles } from './logic';

describe('extractCoordsFromText', () => {
  it('reads every Google Maps URL shape and plain pairs', () => {
    expect(extractCoordsFromText('https://www.google.com/maps/@33.3152,44.3661,15z')).toEqual({ lat: 33.3152, lng: 44.3661 });
    expect(extractCoordsFromText('https://maps.google.com/?q=33.1,44.2')).toEqual({ lat: 33.1, lng: 44.2 });
    expect(extractCoordsFromText('https://www.google.com/maps/place/33.5+44.6/data')).toEqual({ lat: 33.5, lng: 44.6 });
    expect(extractCoordsFromText('33.3152, 44.3661')).toEqual({ lat: 33.3152, lng: 44.3661 });
  });

  it('ignores generic pairs outside Iraq and malformed escapes', () => {
    expect(extractCoordsFromText('10.5, 20.5')).toBeNull();
    expect(extractCoordsFromText('%E0%A4%A 33.2, 44.1')).toEqual({ lat: 33.2, lng: 44.1 });
  });
});

describe('extractCoordsFromHtml', () => {
  it('prefers og:url, then reads APP_INITIALIZATION_STATE as [lng, lat]', () => {
    expect(extractCoordsFromHtml('<meta property="og:url" content="https://maps/@33.9,44.9">')).toEqual({ lat: 33.9, lng: 44.9 });
    expect(extractCoordsFromHtml('window.APP_INITIALIZATION_STATE=[[[44.36,33.31')).toEqual({ lat: 33.31, lng: 44.36 });
  });
});

describe('distanceMeters', () => {
  it('matches a known distance within 1%', () => {
    // ~111.2 كم لكل درجة عرض
    expect(distanceMeters(33, 44, 34, 44)).toBeGreaterThan(110_000);
    expect(distanceMeters(33, 44, 34, 44)).toBeLessThan(112_300);
  });
});

describe('branchAttendees', () => {
  const branch: Branch = { id: 'b1', name: 'الكرادة', latitude: 33.3, longitude: 44.4, radius_meters: 150 };
  const log = (over: Partial<AttendanceRecord>): AttendanceRecord =>
    ({ id: 'x', employee_id: 'e', branch_id: null, work_date: '2026-09-25', status: 'present', ...over }) as AttendanceRecord;

  it('includes direct branch links and nearby check-ins only', () => {
    const rows = branchAttendees(branch, [
      log({ id: 'direct', branch_id: 'b1' }),
      log({ id: 'near', check_in_lat: 33.3005, check_in_lng: 44.4 }),
      log({ id: 'far', check_in_lat: 33.31, check_in_lng: 44.4 }),
      log({ id: 'none' }),
    ]);
    expect(rows.map(r => r.id)).toEqual(['direct', 'near']);
    expect(rows[0].distanceText).toBe('بصمة موجهة يدوياً للفرع');
    expect(rows[1].distanceText).toBe('على بُعد 56 متر');
  });
});

describe('mapCircles', () => {
  it('skips branches without coordinates and defaults the radius', () => {
    const circles = mapCircles([
      { id: 'a', name: 'a', latitude: 33, longitude: 44, radius_meters: 0 },
      { id: 'b', name: 'b', latitude: 0, longitude: 0, radius_meters: 100 },
    ]);
    expect(circles).toEqual([{ id: 'a', name: 'a', lat: 33, lng: 44, radius: 150 }]);
  });
});
