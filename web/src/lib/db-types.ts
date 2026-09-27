// =========================================================================
// أنواع صفوف قاعدة البيانات كما تستعملها لوحة التحكم.
// مبنية على supabase/migrations — الأعمدة المشتقة من joins (مثل employees
// داخل loans) اختيارية لأنها لا تُجلب في كل استعلام.
// =========================================================================

export type Role = 'employee' | 'manager' | 'admin';

export interface Branch {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  radius_meters: number;
  address?: string | null;
  created_at?: string;
}

export interface Department {
  id: string;
  name: string;
  manager_id?: string | null;
  created_at?: string;
}

export interface Employee {
  id: string;
  employee_code: string;
  full_name: string;
  phone?: string | null;
  phone_number?: string | null;
  email?: string | null;
  avatar_url?: string | null;
  is_active: boolean;
  role: Role;
  department_id?: string | null;
  branch_id?: string | null;
  monthly_salary_iqd?: number | null;
  future_salary_iqd?: number | null;
  future_salary_month?: string | null;
  join_date?: string | null;
  device_id_lock?: string | null;
  plain_password?: string | null;
  must_change_password?: boolean;
  document_urls?: string[] | null;
  created_at?: string;
  branches?: { id?: string; name: string } | null;
  departments?: { id?: string; name: string } | null;
}

/** أعمدة الموظف كما تأتي داخل join (employees!fk(...)). */
export type EmployeeRef = Partial<Employee> & { full_name?: string };

export interface EmployeeDevice {
  id: string;
  employee_id: string;
  device_id: string;
  model?: string | null;
  os_version?: string | null;
  is_approved: boolean;
  approved_at?: string | null;
  created_at?: string;
  employees?: EmployeeRef | null;
}

export interface ArchivedEmployee {
  id: string;
  employee_id: string;
  employee_code?: string | null;
  full_name: string;
  archived_at: string;
  archive_reason?: string | null;
  archive_type: 'permanent' | 'scheduled_deletion' | 'archived';
  scheduled_deletion_date?: string | null;
  archived_by?: string | null;
  notes?: string | null;
}

export interface WorkSchedule {
  id: string;
  employee_id?: string | null;
  department_id?: string | null;
  branch_id?: string | null;
  name: string;
  check_in_time: string;
  check_out_time: string;
  grace_period_minutes: number;
  work_days: number[];
  created_at?: string;
}

export interface AttendanceRecord {
  id: string;
  employee_id: string;
  branch_id: string;
  check_in_time?: string | null;
  check_out_time?: string | null;
  check_in_lat?: number | null;
  check_in_lng?: number | null;
  check_out_lat?: number | null;
  check_out_lng?: number | null;
  check_in_offline?: boolean;
  check_out_offline?: boolean;
  is_mock_detected?: boolean;
  status: 'present' | 'late' | 'absent' | 'half_day' | string;
  work_date: string;
  deduction_status?: 'pending' | 'applied' | 'ignored' | null;
  deduction_reason?: string | null;
  deduction_applied?: boolean | null;
  created_at?: string;
  employees?: EmployeeRef | null;
  branches?: Pick<Branch, 'id' | 'name'> | null;
}

export interface LeaveRequest {
  id: string;
  employee_id: string;
  start_date: string;
  end_date: string;
  leave_type: string;
  is_hourly: boolean;
  start_hour?: string | null;
  end_hour?: string | null;
  is_paid: boolean;
  reason?: string | null;
  status: 'pending' | 'approved' | 'rejected' | string;
  rejection_reason?: string | null;
  attachment_url?: string | null;
  approved_by?: string | null;
  approved_at?: string | null;
  created_at?: string;
  employees?: EmployeeRef | null;
  approver?: EmployeeRef | null;
}

export interface LoanInstallment {
  id: string;
  loan_id: string;
  due_date: string;
  amount: number;
  is_paid: boolean;
  paid_at?: string | null;
  paid_by_slip_id?: string | null;
  payment_type?: 'cash' | 'salary_deduction' | string | null;
  payment_note?: string | null;
  created_at?: string;
  loans?: Partial<Loan> | null;
}

export interface Loan {
  id: string;
  employee_id: string;
  amount: number;
  installment_amount: number;
  installment_count: number;
  remaining_amount: number;
  pledge_url: string;
  status: 'pending' | 'approved' | 'rejected' | string;
  payment_method?: string | null;
  rejection_reason?: string | null;
  approved_by?: string | null;
  approved_at?: string | null;
  created_at?: string;
  employees?: EmployeeRef | null;
  loan_installments?: LoanInstallment[];
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
  pdf_url?: string | null;
  status: 'draft' | 'published';
  created_at?: string;
}

export interface BonusDeduction {
  id: string;
  employee_id: string;
  type: 'bonus' | 'deduction';
  amount: number;
  reason: string;
  issue_date: string;
  created_by?: string | null;
  salary_slip_id?: string | null;
  created_at?: string;
}

export interface AppNotification {
  id: string;
  employee_id: string;
  title: string;
  body: string;
  type: string;
  is_read: boolean;
  created_at: string;
}

export interface Announcement {
  id: string;
  title: string;
  content: string;
  is_pinned: boolean;
  target_department_id?: string | null;
  created_by?: string | null;
  created_at: string;
}

export interface GeofenceZone {
  id: string;
  name: string;
  coordinates: { lat: number; lng: number }[];
  is_active?: boolean;
  created_at?: string;
}

export interface DeletedFile {
  id: string;
  file_path: string;
  file_type: 'avatar' | 'document' | 'pledge' | 'logo' | 'other';
  related_table?: string | null;
  related_id?: string | null;
  deleted_by?: string | null;
  deleted_at: string;
  scheduled_deletion_date: string;
  file_size_bytes?: number | null;
  restored_at?: string | null;
  employees?: EmployeeRef | null;
}

export interface LocationPoint {
  id?: string;
  employee_id: string;
  latitude: number;
  longitude: number;
  battery_level?: number | null;
  is_moving?: boolean | null;
  timestamp: string;
}
