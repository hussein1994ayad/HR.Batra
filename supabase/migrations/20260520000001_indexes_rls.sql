-- ==========================================
-- نظام HR Pro v6.0 - الفهارس وقواعد أمن الصفوف (RLS)
-- ==========================================

-- تفعيل RLS لجميع الجداول
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE archived_employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracking_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE salary_slips ENABLE ROW LEVEL SECURITY;
ALTER TABLE bonuses_deductions ENABLE ROW LEVEL SECURITY;
ALTER TABLE loans ENABLE ROW LEVEL SECURITY;
ALTER TABLE loan_installments ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE location_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE tracked_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE geofence_zones ENABLE ROW LEVEL SECURITY;
ALTER TABLE geofence_violations ENABLE ROW LEVEL SECURITY;
ALTER TABLE mock_gps_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE deleted_files ENABLE ROW LEVEL SECURITY;

-- 1. الفهارس لتحسين الأداء وتسريع الاستعلامات (Indexes)
CREATE INDEX IF NOT EXISTS idx_employees_department ON employees(department_id);
CREATE INDEX IF NOT EXISTS idx_employees_branch ON employees(branch_id);
CREATE INDEX IF NOT EXISTS idx_attendance_employee_date ON attendance(employee_id, work_date);
CREATE INDEX IF NOT EXISTS idx_leave_requests_employee ON leave_requests(employee_id);
CREATE INDEX IF NOT EXISTS idx_leave_requests_dates ON leave_requests(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_salary_slips_employee_month ON salary_slips(employee_id, work_month);
CREATE INDEX IF NOT EXISTS idx_loans_employee ON loans(employee_id);
CREATE INDEX IF NOT EXISTS idx_documents_employee ON documents(employee_id);
CREATE INDEX IF NOT EXISTS idx_location_tracking_employee_time ON location_tracking(employee_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_tracked_stops_employee_time ON tracked_stops(employee_id, start_time);
CREATE INDEX IF NOT EXISTS idx_deleted_files_deletion_date ON deleted_files(scheduled_deletion_date);
CREATE INDEX IF NOT EXISTS idx_archived_employees_deletion_date ON archived_employees(scheduled_deletion_date);
CREATE INDEX IF NOT EXISTS idx_notifications_employee_read ON notifications(employee_id, is_read);

-- 2. سياسات الوصول (RLS Policies)

-- دالة مساعدة لمعرفة هل المستخدم الحالي أدمن
CREATE OR REPLACE FUNCTION is_admin() 
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM employees 
    WHERE id = auth.uid() AND role = 'admin' AND is_active = true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- دالة مساعدة لمعرفة هل المستخدم الحالي مدير
CREATE OR REPLACE FUNCTION is_manager() 
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM employees 
    WHERE id = auth.uid() AND role = 'manager' AND is_active = true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- سياسات جدول الموظفين (employees)
CREATE POLICY "Admins have full access on employees" 
ON employees TO authenticated
USING (is_admin()) 
WITH CHECK (is_admin());

CREATE POLICY "Employees can view their own details" 
ON employees FOR SELECT TO authenticated
USING (id = auth.uid() OR is_admin() OR is_manager());

CREATE POLICY "Employees can update their own details (limited)" 
ON employees FOR UPDATE TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid() AND (
  -- منع الموظف العادي من تغيير حقل الصلاحية (role) أو القسم أو الفرع أو النشاط
  (role = (SELECT role FROM employees WHERE id = auth.uid())) AND
  (department_id = (SELECT department_id FROM employees WHERE id = auth.uid())) AND
  (branch_id = (SELECT branch_id FROM employees WHERE id = auth.uid())) AND
  (is_active = (SELECT is_active FROM employees WHERE id = auth.uid()))
));

-- سياسات إعدادات الشركة (company_settings)
CREATE POLICY "Anyone authenticated can view company settings"
ON company_settings FOR SELECT TO authenticated
USING (true);

CREATE POLICY "Only admins can modify company settings"
ON company_settings TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- سياسات الفروع (branches)
CREATE POLICY "Anyone authenticated can view branches"
ON branches FOR SELECT TO authenticated
USING (true);

CREATE POLICY "Only admins can modify branches"
ON branches TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- سياسات الأقسام (departments)
CREATE POLICY "Anyone authenticated can view departments"
ON departments FOR SELECT TO authenticated
USING (true);

CREATE POLICY "Only admins can modify departments"
ON departments TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- سياسات الأجهزة (employee_devices)
CREATE POLICY "Employees can view and insert their own devices"
ON employee_devices TO authenticated
USING (employee_id = auth.uid() OR is_admin())
WITH CHECK (employee_id = auth.uid() OR is_admin());

CREATE POLICY "Admins can manage all devices"
ON employee_devices TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- سياسات الحضور (attendance)
CREATE POLICY "Employees can manage their own attendance"
ON attendance TO authenticated
USING (employee_id = auth.uid() OR is_admin() OR is_manager())
WITH CHECK (employee_id = auth.uid() OR is_admin());

CREATE POLICY "Admins and managers can view all attendance records"
ON attendance FOR SELECT TO authenticated
USING (is_admin() OR is_manager());

-- سياسات طلبات الإجازات (leave_requests)
CREATE POLICY "Employees can view and create their own leave requests"
ON leave_requests TO authenticated
USING (employee_id = auth.uid() OR is_admin() OR is_manager())
WITH CHECK (employee_id = auth.uid() OR is_admin());

CREATE POLICY "Admins and managers can view and process leave requests"
ON leave_requests TO authenticated
USING (is_admin() OR is_manager())
WITH CHECK (is_admin() OR is_manager());

-- سياسات رصيد الإجازات (leave_balances)
CREATE POLICY "Employees can view their own leave balance"
ON leave_balances FOR SELECT TO authenticated
USING (employee_id = auth.uid() OR is_admin() OR is_manager());

CREATE POLICY "Admins can manage leave balances"
ON leave_balances TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- سياسات كشوف الرواتب (salary_slips)
CREATE POLICY "Employees can view their own salary slips"
ON salary_slips FOR SELECT TO authenticated
USING (employee_id = auth.uid() AND status = 'published');

CREATE POLICY "Admins can manage salary slips"
ON salary_slips TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- سياسات المكافآت والخصومات (bonuses_deductions)
CREATE POLICY "Employees can view their own bonuses/deductions"
ON bonuses_deductions FOR SELECT TO authenticated
USING (employee_id = auth.uid());

CREATE POLICY "Admins and managers can manage bonuses/deductions"
ON bonuses_deductions TO authenticated
USING (is_admin() OR is_manager())
WITH CHECK (is_admin() OR is_manager());

-- سياسات السلف (loans)
CREATE POLICY "Employees can view and request loans"
ON loans TO authenticated
USING (employee_id = auth.uid() OR is_admin())
WITH CHECK (employee_id = auth.uid() OR is_admin());

CREATE POLICY "Admins can manage loans"
ON loans TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- سياسات أقساط السلف (loan_installments)
CREATE POLICY "Employees can view their own loan installments"
ON loan_installments FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM loans WHERE loans.id = loan_installments.loan_id AND loans.employee_id = auth.uid()
) OR is_admin());

CREATE POLICY "Admins can manage installments"
ON loan_installments TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- سياسات المستندات (documents)
CREATE POLICY "Employees can view and add their own documents"
ON documents TO authenticated
USING (employee_id = auth.uid() OR is_admin())
WITH CHECK (employee_id = auth.uid() OR is_admin());

-- الأدمن فقط يملك صلاحية حذف المستندات
CREATE POLICY "Only admins can delete documents"
ON documents FOR DELETE TO authenticated
USING (is_admin());

-- سياسات تتبع الموقع (location_tracking)
CREATE POLICY "Employees can insert their own location tracking"
ON location_tracking FOR INSERT TO authenticated
WITH CHECK (employee_id = auth.uid());

CREATE POLICY "Admins and managers can view location tracking"
ON location_tracking FOR SELECT TO authenticated
USING (is_admin() OR is_manager());

-- سياسات الوقفات وسجلات الجيوفينس ومحاولات التزييف
CREATE POLICY "Employees can report tracking metrics"
ON tracked_stops FOR INSERT TO authenticated WITH CHECK (employee_id = auth.uid());

CREATE POLICY "Admins can view stops"
ON tracked_stops FOR SELECT TO authenticated USING (is_admin() OR is_manager());

CREATE POLICY "Anyone authenticated can view geofence zones"
ON geofence_zones FOR SELECT TO authenticated USING (true);

CREATE POLICY "Only admins can manage geofence zones"
ON geofence_zones TO authenticated USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Employees can insert violations"
ON geofence_violations FOR INSERT TO authenticated WITH CHECK (employee_id = auth.uid());

CREATE POLICY "Admins can view violations"
ON geofence_violations FOR SELECT TO authenticated USING (is_admin() OR is_manager());

CREATE POLICY "Employees can report mock gps attempts"
ON mock_gps_attempts FOR INSERT TO authenticated WITH CHECK (employee_id = auth.uid());

CREATE POLICY "Admins can view mock gps attempts"
ON mock_gps_attempts FOR SELECT TO authenticated USING (is_admin() OR is_manager());

-- سياسات الإعلانات (announcements)
CREATE POLICY "Anyone authenticated can view announcements"
ON announcements FOR SELECT TO authenticated
USING (true);

CREATE POLICY "Only admins can manage announcements"
ON announcements TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- سياسات إصدارات التطبيق (app_versions)
CREATE POLICY "Anyone authenticated can view app versions"
ON app_versions FOR SELECT TO authenticated
USING (true);

CREATE POLICY "Only admins can manage app versions"
ON app_versions TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- سياسات الإشعارات (notifications)
CREATE POLICY "Employees can view and update their own notifications"
ON notifications TO authenticated
USING (employee_id = auth.uid())
WITH CHECK (employee_id = auth.uid());

-- سياسات سلة المحذوفات (deleted_files)
CREATE POLICY "Admins can view and manage deleted files"
ON deleted_files TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- سياسات الموظفين المؤرشفين (archived_employees)
CREATE POLICY "Admins can view and manage archived employees"
ON archived_employees TO authenticated
USING (is_admin())
WITH CHECK (is_admin());
