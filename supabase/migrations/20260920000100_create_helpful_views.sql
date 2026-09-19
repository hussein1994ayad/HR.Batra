-- =========================================================================
-- HR Pro v6.0 - Helpful views to reduce client-side N+1 queries
-- Date: 2026-09-20
-- Related: audit point 26
-- =========================================================================
--
-- What this migration does:
--   • Adds views that join sensitive tables so mobile/web don't do
--     N+1 queries or client-side joins.
--
-- Rollback: DROP VIEW ... CASCADE for each view below.
-- =========================================================================


-- =====================================================================
-- v_attendance_with_employee
-- الحضور + اسم الموظف + قسم + فرع في استعلام واحد
-- =====================================================================
CREATE OR REPLACE VIEW v_attendance_with_employee AS
SELECT
    a.id,
    a.employee_id,
    e.full_name       AS employee_name,
    e.employee_code,
    e.avatar_url,
    d.name            AS department_name,
    b.name            AS branch_name,
    a.branch_id,
    a.check_in_time,
    a.check_out_time,
    a.check_in_lat,
    a.check_in_lng,
    a.check_out_lat,
    a.check_out_lng,
    a.is_mock_detected,
    a.status,
    a.work_date,
    a.created_at
FROM attendance a
LEFT JOIN employees   e ON e.id = a.employee_id
LEFT JOIN departments d ON d.id = e.department_id
LEFT JOIN branches    b ON b.id = a.branch_id;

COMMENT ON VIEW v_attendance_with_employee IS
'كل سجل حضور مع اسم الموظف، القسم، والفرع. يقلل N+1 في شاشات تقارير الحضور.';


-- =====================================================================
-- v_loans_summary
-- السلف + عدد الأقساط المدفوعة + المتبقي المحسوب
-- =====================================================================
CREATE OR REPLACE VIEW v_loans_summary AS
SELECT
    l.id,
    l.employee_id,
    e.full_name        AS employee_name,
    e.employee_code,
    l.amount,
    l.installments,
    l.installment_amount,
    l.pledge_url,
    l.status,
    l.approved_by,
    l.approved_at,
    l.rejection_reason,
    l.created_at,
    COALESCE(paid.paid_count, 0)      AS paid_installments,
    COALESCE(paid.paid_amount, 0)     AS total_paid_amount,
    l.amount - COALESCE(paid.paid_amount, 0) AS remaining_amount
FROM loans l
LEFT JOIN employees e ON e.id = l.employee_id
LEFT JOIN LATERAL (
    SELECT
        COUNT(*) FILTER (WHERE is_paid) AS paid_count,
        COALESCE(SUM(amount) FILTER (WHERE is_paid), 0) AS paid_amount
    FROM loan_installments
    WHERE loan_id = l.id
) paid ON true;

COMMENT ON VIEW v_loans_summary IS
'السلف مع اسم الموظف وعدد ومبلغ الأقساط المدفوعة والمتبقي المحسوب. تجنّب N+1 في شاشة إدارة السلف.';


-- =====================================================================
-- v_leaves_with_employee
-- طلبات الإجازات + اسم الموظف + رصيد الإجازات الحالي
-- =====================================================================
CREATE OR REPLACE VIEW v_leaves_with_employee AS
SELECT
    lr.id,
    lr.employee_id,
    e.full_name        AS employee_name,
    e.employee_code,
    d.name             AS department_name,
    lr.start_date,
    lr.end_date,
    lr.leave_type,
    lr.is_hourly,
    lr.start_hour,
    lr.end_hour,
    lr.is_paid,
    lr.reason,
    lr.status,
    lr.attachment_url,
    lr.approved_by,
    lr.approved_at,
    lr.created_at,
    lb.annual_entitlement,
    lb.annual_used,
    lb.sick_entitlement,
    lb.sick_used
FROM leave_requests lr
LEFT JOIN employees        e  ON e.id  = lr.employee_id
LEFT JOIN departments      d  ON d.id  = e.department_id
LEFT JOIN leave_balances   lb ON lb.employee_id = lr.employee_id;

COMMENT ON VIEW v_leaves_with_employee IS
'طلبات الإجازات مع بيانات الموظف ورصيد إجازاته الحالي. يستخدم في لوحة اعتماد الإجازات.';


-- =====================================================================
-- v_payroll_with_employee
-- كشوف رواتب + اسم الموظف والقسم للتقارير
-- =====================================================================
CREATE OR REPLACE VIEW v_payroll_with_employee AS
SELECT
    s.id,
    s.employee_id,
    e.full_name        AS employee_name,
    e.employee_code,
    d.name             AS department_name,
    b.name             AS branch_name,
    s.work_month,
    s.basic_salary,
    s.allowances,
    s.deductions,
    s.loans_deduction,
    s.net_salary,
    s.pdf_url,
    s.status,
    s.created_at
FROM salary_slips s
LEFT JOIN employees    e ON e.id = s.employee_id
LEFT JOIN departments  d ON d.id = e.department_id
LEFT JOIN branches     b ON b.id = e.branch_id;

COMMENT ON VIEW v_payroll_with_employee IS
'كشوف الرواتب الشهرية مع بيانات الموظف الكاملة. يستخدم في شاشة payroll وتصدير Excel/PDF.';


-- =====================================================================
-- v_device_requests
-- طلبات الأجهزة الجديدة المعلقة (لموافقة الأدمن)
-- =====================================================================
CREATE OR REPLACE VIEW v_device_requests AS
SELECT
    ed.id,
    ed.employee_id,
    e.full_name        AS employee_name,
    e.employee_code,
    ed.device_id,
    ed.model,
    ed.os_version,
    ed.is_approved,
    ed.approved_at,
    ed.created_at,
    e.device_id_lock   AS currently_locked_device
FROM employee_devices ed
LEFT JOIN employees e ON e.id = ed.employee_id
WHERE ed.is_approved = false;

COMMENT ON VIEW v_device_requests IS
'طلبات الأجهزة الجديدة المعلقة (is_approved=false) مع اسم الموظف. يستخدم في شاشة إدارة الأجهزة.';


-- =====================================================================
-- v_security_incidents
-- محاولات الاختراق والتزييف الأخيرة للمراقبة
-- =====================================================================
CREATE OR REPLACE VIEW v_security_incidents AS
SELECT
    'mock_gps'::TEXT   AS incident_type,
    m.id,
    m.employee_id,
    e.full_name        AS employee_name,
    m.latitude,
    m.longitude,
    m.app_used         AS details,
    m.timestamp        AS occurred_at
FROM mock_gps_attempts m
LEFT JOIN employees e ON e.id = m.employee_id
UNION ALL
SELECT
    'geofence_violation'::TEXT,
    v.id,
    v.employee_id,
    e.full_name,
    NULL::DOUBLE PRECISION,
    NULL::DOUBLE PRECISION,
    v.violation_type,
    v.timestamp
FROM geofence_violations v
LEFT JOIN employees e ON e.id = v.employee_id
ORDER BY occurred_at DESC;

COMMENT ON VIEW v_security_incidents IS
'الحوادث الأمنية الموحدة: محاولات تزييف GPS ومخالفات السياج الجغرافي في تدفق واحد مرتب زمنياً.';
