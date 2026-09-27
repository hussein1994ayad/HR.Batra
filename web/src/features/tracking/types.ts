// أنواع صفحة المراقبة والانضباط.

import type { AttendanceRecord, Employee, EmployeeRef } from '@/lib/db-types';

// الإحداثيات مخزنة بأكثر من شكل عبر إصدارات التطبيق: [lat, lng] أو {lat, lng} أو {latitude, longitude}
export type RawPoint =
  | [number | string, number | string]
  | { lat?: number | string; lng?: number | string; latitude?: number | string; longitude?: number | string };

export type RawZone = { id: string; name: string; coordinates?: unknown; polygon_coordinates?: unknown };

export type MockGpsAttempt = {
  id: string;
  employee_id: string;
  latitude: number | null;
  longitude: number | null;
  app_used: string | null;
  timestamp: string;
  employees?: EmployeeRef | null;
};

export type TrackedEmployee = Pick<Employee, 'id' | 'full_name' | 'branch_id' | 'department_id' | 'role'> & {
  departments?: { name: string } | null;
};

export type AttendanceRow = AttendanceRecord & { is_virtual: boolean };

export type DetectedStop = { lat: number; lng: number; startTime: Date; endTime: Date; duration: number };

export type MapMarker = { lat: number; lng: number; popupText: string; isViolation?: boolean; color?: string };

export type Decision = {
  id: string | null;
  type: 'late' | 'absent' | 'virtual_absent';
  employee: TrackedEmployee;
  date: string;
  time: string;
  duration: string;
  typeName: string;
  deductionStatus: string;
  reason: string;
  suggestedAmount: number;
};
