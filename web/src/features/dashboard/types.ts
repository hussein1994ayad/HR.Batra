// أنواع الصفحة الرئيسية للوحة التحكم.

import type { Branch, Department, Employee } from '@/lib/db-types';

export type EmployeeSummary = Pick<Employee, 'id' | 'full_name' | 'branch_id' | 'department_id'>;

export type SecurityLog = {
  id: string;
  type: 'mock_gps' | 'geofence';
  name: string;
  timestamp: Date | string;
  details: string;
  coords: string;
};

export interface DashboardStats {
  employees: number;
  presentToday: number;
  absentToday: number;
  pendingLeaves: number;
  pendingLoans: number;
  pendingDevices: number;
  securityIncidents: number;
  totalStorageBytes: number;
}

export interface DashboardData {
  stats: DashboardStats;
  securityLogs: SecurityLog[];
  absentList: EmployeeSummary[];
  branches: Pick<Branch, 'id' | 'name'>[];
  departments: Department[];
  employeesList: EmployeeSummary[];
}

export type AnnouncementTarget =
  | { type: 'all' }
  | { type: 'branch'; branchId: string }
  | { type: 'employee'; employeeIds: string[] };
