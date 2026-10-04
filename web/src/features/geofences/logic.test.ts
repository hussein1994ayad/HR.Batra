import { describe, expect, it } from 'vitest';
import type { Attendance, Branch } from '@/lib/db-types';
import { DEFAULT_RADIUS, attendeesForBranch, branchCircles } from './logic';

const branch = { id: 'b1', name: 'المنصور', latitude: 33.3, longitude: 44.4, radius_meters: null } as unknown as Branch;
const log = (over: Partial<Attendance>) => ({ id: Math.random().toString(), employee_id: 'e', work_date: '2026-10-04', status: 'present', ...over }) as Attendance;

describe('geofences logic', () => {
  it('draws only branches with coordinates, with the default radius', () => {
    const noCoords = { id: 'b2', name: 'x', latitude: null, longitude: null } as unknown as Branch;
    expect(branchCircles([branch, noCoords])).toEqual([{ id: 'b1', name: 'المنصور', lat: 33.3, lng: 44.4, radius: DEFAULT_RADIUS }]);
  });

  it('an attendee belongs by branch, by employee branch, or by punching inside the radius', () => {
    const logs = [
      log({ branch_id: 'b1' }),
      log({ branch_id: 'other', employees: { full_name: 'a', branch_id: 'b1' } as Attendance['employees'] }),
      log({ branch_id: 'other', check_in_lat: 33.3005, check_in_lng: 44.4 }), // ~55 م
      log({ branch_id: 'other', check_in_lat: 33.31, check_in_lng: 44.4 }), // ~1.1 كم
    ];
    const res = attendeesForBranch(branch, logs);
    expect(res).toHaveLength(3);
    expect(res[0].distance).toBeNull();
    expect(res[2].distance).toBeGreaterThan(40);
    expect(res[2].distance).toBeLessThan(70);
  });
});
