// Row shapes returned by Supabase for the tables the dashboard reads.
// Several columns live only in the hosted database (they are not in the
// migrations), so optional fields are typed loosely on purpose.

export type Role = 'employee' | 'manager' | 'admin';

export interface Branch {
  id: string;
  name: string;
  latitude?: number | null;
  longitude?: number | null;
  radius_meters?: number | null;
  address?: string | null;
  created_at?: string;
}

export interface Department {
  id: string;
  name: string;
}

export interface Employee {
  id: string;
  full_name: string;
  email?: string | null;
  phone?: string | null;
  role?: Role | string;
  branch_id?: string | null;
  department_id?: string | null;
  employee_code?: string | null;
  is_active?: boolean;
  monthly_salary_iqd?: number | null;
  future_salary_iqd?: number | null;
  future_salary_month?: string | null;
  plain_password?: string | null;
  document_urls?: string[] | null;
  device_id_lock?: string | null;
  branches?: { name: string } | null;
  departments?: { name: string } | null;
}

export interface WorkSchedule {
  id: string;
  name: string;
  employee_id?: string | null;
  department_id?: string | null;
  branch_id?: string | null;
  check_in_time: string;
  check_out_time: string;
  grace_period_minutes: number;
  work_days: number[];
}

export type DeductionStatus = 'pending' | 'applied' | 'ignored';

export interface Attendance {
  id: string;
  employee_id: string;
  branch_id?: string | null;
  work_date: string;
  check_in_time?: string | null;
  check_out_time?: string | null;
  check_in_lat?: number | null;
  check_in_lng?: number | null;
  status: string;
  deduction_status?: DeductionStatus | null;
  deduction_reason?: string | null;
  employees?: {
    full_name: string;
    branch_id?: string | null;
    phone?: string | null;
    email?: string | null;
  } | null;
}

export type RequestStatus = 'pending' | 'approved' | 'rejected';

export interface LeaveRequest {
  id: string;
  employee_id: string;
  start_date: string;
  end_date: string;
  leave_type: string;
  is_hourly?: boolean;
  start_hour?: string | null;
  end_hour?: string | null;
  is_paid: boolean;
  reason?: string | null;
  status: RequestStatus;
  attachment_url?: string | null;
  approved_at?: string | null;
  created_at?: string;
  employees?: { full_name: string } | null;
  approver?: { full_name: string } | null;
}

export interface LoanInstallment {
  id: string;
  loan_id: string;
  due_date: string;
  amount: number;
  is_paid: boolean;
  paid_at?: string | null;
  payment_type?: string | null;
  payment_note?: string | null;
  loans?: { employee_id: string } | null;
}

export interface Loan {
  id: string;
  employee_id: string;
  amount: number;
  installment_amount: number;
  installment_count: number;
  remaining_amount: number;
  pledge_url?: string | null;
  status: RequestStatus;
  created_at?: string;
  employees?: { full_name: string } | null;
  loan_installments?: LoanInstallment[];
}

export interface BonusDeduction {
  id: string;
  employee_id: string;
  type: 'bonus' | 'deduction';
  amount: number;
  reason: string;
  issue_date: string;
}

export interface SalarySlip {
  id: string;
  employee_id: string;
  work_month: string;
  basic_salary: number;
  allowances: number;
  deductions: number;
  loans_deduction: number;
  net_salary: number;
  status: string;
}

export interface AppNotification {
  id: string;
  employee_id: string;
  title: string;
  body: string;
  type: string;
  is_read: boolean;
  created_at?: string;
}

export interface DeviceRequest {
  id: string;
  employee_id: string;
  device_id: string;
  device_model?: string | null;
  model?: string | null;
  os_version?: string | null;
  employees?: { full_name: string } | null;
}

export interface ArchivedEmployee {
  id: string;
  employee_id: string;
  employee_code?: string | null;
  full_name: string;
  archived_at: string;
  archive_reason?: string | null;
  archive_type: string;
  scheduled_deletion_date?: string | null;
}

export interface DeletedFile {
  id: string;
  file_path: string;
  file_type: string;
  deleted_at: string;
  scheduled_deletion_date: string;
  file_size_bytes?: number | null;
  employees?: { full_name: string } | null;
}

export interface Announcement {
  id: string;
  title: string;
  content: string;
  is_pinned: boolean;
  created_at: string;
}

export interface MockGpsAttempt {
  id: string;
  employee_id?: string;
  latitude?: number | null;
  longitude?: number | null;
  app_used?: string | null;
  timestamp: string;
  employees?: { full_name: string } | null;
}

export interface GeofenceViolation {
  id: string;
  violation_type: 'entry' | 'exit';
  timestamp: string;
  employees?: { full_name: string } | null;
  geofence_zones?: { name: string } | null;
}

export interface GeofenceZone {
  id: string;
  name: string;
  polygon_coordinates?: [number, number][] | string | null;
  latitude?: number | null;
  longitude?: number | null;
}

export interface LeaveTypeOption {
  id: string;
  name: string;
}

export interface StorageStat {
  bucket_name: string;
  total_size: number | string | null;
}
