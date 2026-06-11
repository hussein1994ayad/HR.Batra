-- ==========================================
-- نظام HR Pro v6.0 - تهيئة قاعدة البيانات
-- ==========================================

-- تفعيل إضافة UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. جدول إعدادات الشركة (company_settings)
CREATE TABLE IF NOT EXISTS company_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    logo_url TEXT,
    address TEXT,
    phone TEXT,
    email TEXT,
    website TEXT,
    tax_number TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE company_settings IS 'إعدادات وبيانات الشركة العامة المظهرة في التقارير وكشوف الرواتب';

-- 2. جدول الفروع (branches)
CREATE TABLE IF NOT EXISTS branches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius_meters DOUBLE PRECISION DEFAULT 100 NOT NULL,
    address TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE branches IS 'فروع الشركة ونطاقات الجغرافي الخاصة بالبصمة';

-- 3. جدول الأقسام (departments)
CREATE TABLE IF NOT EXISTS departments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    manager_id UUID, -- سيتم ربطه لاحقاً بجدول الموظفين لمنع العلاقات الدائرية في التأسيس
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE departments IS 'الأقسام الإدارية للشركة';

-- 4. جدول الموظفين (employees)
CREATE TABLE IF NOT EXISTS employees (
    id UUID PRIMARY KEY, -- يطابق معرّف المستخدم في auth.users الخاص بـ Supabase Auth
    employee_code TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    avatar_url TEXT,
    is_active BOOLEAN DEFAULT true NOT NULL,
    role TEXT DEFAULT 'employee' NOT NULL CHECK (role IN ('employee', 'manager', 'admin')),
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE employees IS 'بيانات الموظفين الأساسية وربطهم بالأقسام والفروع والمهام الإدارية';

-- الآن نقوم بإضافة قيد مفتاح خارجي لمدير القسم بعد إنشاء جدول الموظفين
ALTER TABLE departments ADD CONSTRAINT fk_departments_manager FOREIGN KEY (manager_id) REFERENCES employees(id) ON DELETE SET NULL;

-- 5. جدول الموظفين المؤرشفين (archived_employees)
CREATE TABLE IF NOT EXISTS archived_employees (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL,
    employee_code TEXT,
    full_name TEXT NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    archive_reason TEXT,
    archive_type TEXT NOT NULL CHECK (archive_type IN ('permanent', 'scheduled_deletion', 'archived')),
    scheduled_deletion_date TIMESTAMP WITH TIME ZONE,
    archived_by UUID REFERENCES employees(id) ON DELETE SET NULL,
    notes TEXT
);

COMMENT ON TABLE archived_employees IS 'سجلات الموظفين المستقيلين أو المفصولين مع طريقة وخيارات الأرشفة والحذف المجدول';

-- 6. جدول أجهزة الموظفين (employee_devices)
CREATE TABLE IF NOT EXISTS employee_devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    device_id TEXT NOT NULL, -- معرف فريد للجهاز UUID
    model TEXT,
    os_version TEXT,
    is_approved BOOLEAN DEFAULT false NOT NULL,
    approved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE (employee_id, device_id)
);

COMMENT ON TABLE employee_devices IS 'الأجهزة المعتمدة للموظفين لضمان تسجيل الدخول من جهاز واحد معتمد فقط';

-- 7. جدول جداول الدوام (work_schedules)
CREATE TABLE IF NOT EXISTS work_schedules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE, -- مخصص لموظف معين (اختياري)
    department_id UUID REFERENCES departments(id) ON DELETE CASCADE, -- أو قسم معين (اختياري)
    name TEXT NOT NULL,
    check_in_time TIME NOT NULL,
    check_out_time TIME NOT NULL,
    grace_period_minutes INTEGER DEFAULT 15 NOT NULL,
    work_days INTEGER[] NOT NULL, -- مصفوفة أيام الدوام (مثلاً: [0,1,2,3,4] لتمثيل الأحد إلى الخميس)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE work_schedules IS 'توقيتات وأيام العمل المحددة للموظفين والأقسام';

-- 8. جدول جداول التتبع (tracking_schedules)
CREATE TABLE IF NOT EXISTS tracking_schedules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    tracking_days INTEGER[] NOT NULL,
    interval_minutes INTEGER DEFAULT 5 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE tracking_schedules IS 'مواعيد التتبع الجغرافي التلقائي المحددة للموظفين ميدانياً';

-- 9. سجل الحضور والانصراف (attendance)
CREATE TABLE IF NOT EXISTS attendance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL NOT NULL,
    check_in_time TIMESTAMP WITH TIME ZONE,
    check_out_time TIMESTAMP WITH TIME ZONE,
    check_in_lat DOUBLE PRECISION,
    check_in_lng DOUBLE PRECISION,
    check_out_lat DOUBLE PRECISION,
    check_out_lng DOUBLE PRECISION,
    is_mock_detected BOOLEAN DEFAULT false NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('present', 'late', 'absent', 'half_day')),
    work_date DATE DEFAULT current_date NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE (employee_id, work_date)
);

COMMENT ON TABLE attendance IS 'سجلات الدوام اليومي وحضور الموظفين مع حقول الفحص الجغرافي وكشف التزييف';

-- 10. طلبات الإجازات (leave_requests)
CREATE TABLE IF NOT EXISTS leave_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    start_date TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date TIMESTAMP WITH TIME ZONE NOT NULL,
    leave_type TEXT NOT NULL CHECK (leave_type IN ('annual', 'sick', 'emergency', 'maternity', 'other')),
    is_hourly BOOLEAN DEFAULT false NOT NULL,
    start_hour TIME,
    end_hour TIME,
    is_paid BOOLEAN DEFAULT true NOT NULL,
    reason TEXT,
    status TEXT DEFAULT 'pending' NOT NULL CHECK (status IN ('pending', 'approved', 'rejected')),
    attachment_url TEXT,
    approved_by UUID REFERENCES employees(id) ON DELETE SET NULL,
    approved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE leave_requests IS 'طلبات الإجازات اليومية والساعية مع المرفقات وحالة الاعتماد';

-- 11. رصيد الإجازات (leave_balances)
CREATE TABLE IF NOT EXISTS leave_balances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE UNIQUE NOT NULL,
    annual_entitlement INTEGER DEFAULT 21 NOT NULL,
    annual_used INTEGER DEFAULT 0 NOT NULL,
    sick_entitlement INTEGER DEFAULT 15 NOT NULL,
    sick_used INTEGER DEFAULT 0 NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE leave_balances IS 'أرصدة إجازات الموظفين السنوية والمرضية والمنقضية';

-- 12. كشوف الرواتب (salary_slips)
CREATE TABLE IF NOT EXISTS salary_slips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    work_month TEXT NOT NULL, -- بصيغة 'YYYY-MM'
    basic_salary NUMERIC NOT NULL, -- بالدينار العراقي
    allowances NUMERIC DEFAULT 0 NOT NULL,
    deductions NUMERIC DEFAULT 0 NOT NULL,
    loans_deduction NUMERIC DEFAULT 0 NOT NULL,
    net_salary NUMERIC NOT NULL,
    pdf_url TEXT,
    status TEXT DEFAULT 'draft' NOT NULL CHECK (status IN ('draft', 'published')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    UNIQUE (employee_id, work_month)
);

COMMENT ON TABLE salary_slips IS 'كشوف الرواتب الشهرية المفصلة للموظفين مصحوبة بملف PDF ومفصلة بالدينار العراقي';

-- 13. المكافآت والخصومات (bonuses_deductions)
CREATE TABLE IF NOT EXISTS bonuses_deductions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('bonus', 'deduction')),
    amount NUMERIC NOT NULL, -- بالدينار العراقي
    reason TEXT NOT NULL,
    issue_date DATE DEFAULT current_date NOT NULL,
    created_by UUID REFERENCES employees(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE bonuses_deductions IS 'سجل المكافآت والخصومات الفورية الصادرة بحق الموظف بالدينار العراقي';

-- 14. السلف (loans)
CREATE TABLE IF NOT EXISTS loans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    amount NUMERIC NOT NULL, -- المبلغ الإجمالي للسلفة
    installment_amount NUMERIC NOT NULL, -- قيمة القسط الشهري
    installment_count INTEGER NOT NULL, -- عدد الأقساط
    remaining_amount NUMERIC NOT NULL, -- المبلغ المتبقي للسداد
    pledge_url TEXT NOT NULL, -- رابط صورة التعهد الإلزامية الموقعة والمضغوطة تلقائياً
    status TEXT DEFAULT 'pending' NOT NULL CHECK (status IN ('pending', 'approved', 'rejected')),
    payment_method TEXT CHECK (payment_method IN ('cash', 'bank', 'salary_deduction')),
    approved_by UUID REFERENCES employees(id) ON DELETE SET NULL,
    approved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE loans IS 'طلبات القروض والسلف المالية للموظفين وصورة تعهد السلفة الإلزامية';

-- 15. أقساط السلف (loan_installments)
CREATE TABLE IF NOT EXISTS loan_installments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    loan_id UUID REFERENCES loans(id) ON DELETE CASCADE NOT NULL,
    due_date DATE NOT NULL,
    amount NUMERIC NOT NULL,
    is_paid BOOLEAN DEFAULT false NOT NULL,
    paid_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE loan_installments IS 'الأقساط الشهرية وجدول سداد السلف';

-- 16. المستندات والوثائق (documents)
CREATE TABLE IF NOT EXISTS documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    doc_type TEXT NOT NULL CHECK (doc_type IN ('national_id', 'residency', 'passport', 'driving_license', 'contract', 'certificate', 'visa', 'loan_pledge', 'other')),
    doc_url TEXT NOT NULL,
    doc_number TEXT,
    issue_date DATE,
    expiry_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE documents IS 'المستندات والملفات المرفوعة الخاصة بكل موظف وتواريخ انتهاء صلاحيتها للتنبيه';

-- 17. تتبع الموقع الجغرافي (location_tracking)
CREATE TABLE IF NOT EXISTS location_tracking (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    battery_level INTEGER,
    is_moving BOOLEAN,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE location_tracking IS 'بيانات تتبع الموقع الجغرافي المستمر للموظفين الميدانيين أثناء العمل';

-- 18. سجل الوقفات (tracked_stops)
CREATE TABLE IF NOT EXISTS tracked_stops (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    start_time TIMESTAMP WITH TIME ZONE NOT NULL,
    end_time TIMESTAMP WITH TIME ZONE,
    duration_minutes INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE tracked_stops IS 'سجل الوقفات المكتشفة التي تتجاوز الـ 5 دقائق للموظف أثناء تتبعه';

-- 19. مناطق السياج الجغرافي (geofence_zones)
CREATE TABLE IF NOT EXISTS geofence_zones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    coordinates JSONB NOT NULL, -- مصفوفة من الإحداثيات تمثل مضلع السياج الجغرافي [{"lat": 0.0, "lng": 0.0}]
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE geofence_zones IS 'مناطق ومساحات السياج الجغرافي المرسومة لمتابعة الموظفين';

-- 20. تعيين السياج الجغرافي للموظفين (employee_geofence_assignments)
CREATE TABLE IF NOT EXISTS employee_geofence_assignments (
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    zone_id UUID REFERENCES geofence_zones(id) ON DELETE CASCADE NOT NULL,
    PRIMARY KEY (employee_id, zone_id)
);

COMMENT ON TABLE employee_geofence_assignments IS 'تعيين وتخصيص مناطق السياج الجغرافي للموظفين ميدانياً';

-- 21. مخالفات السياج الجغرافي (geofence_violations)
CREATE TABLE IF NOT EXISTS geofence_violations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    zone_id UUID REFERENCES geofence_zones(id) ON DELETE CASCADE NOT NULL,
    violation_type TEXT NOT NULL CHECK (violation_type IN ('entry', 'exit')),
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE geofence_violations IS 'مخالفات الدخول والخروج المسجلة من وإلى مناطق السياج الجغرافي للموظفين المكلفين';

-- 22. محاولات التزييف الجغرافي (mock_gps_attempts)
CREATE TABLE IF NOT EXISTS mock_gps_attempts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    app_used TEXT,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE mock_gps_attempts IS 'سجل محاولات تزييف وتعديل الموقع الجغرافي باستخدام تطبيقات Mock GPS';

-- 23. لوحة الإعلانات (announcements)
CREATE TABLE IF NOT EXISTS announcements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    is_pinned BOOLEAN DEFAULT false NOT NULL,
    target_department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    created_by UUID REFERENCES employees(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE announcements IS 'لوحة الإعلانات الإدارية والتعاميم الموجهة للموظفين';

-- 24. إصدارات التطبيق (app_versions)
CREATE TABLE IF NOT EXISTS app_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    version_code INTEGER NOT NULL,
    version_name TEXT NOT NULL,
    apk_url TEXT NOT NULL,
    ipa_url TEXT,
    is_mandatory BOOLEAN DEFAULT false NOT NULL,
    release_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE app_versions IS 'سجل إصدارات التطبيق وملفات التحميل لغرض تحديثات OTA';

-- 25. الإشعارات (notifications)
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('leave', 'loan', 'bonus_deduction', 'attendance', 'salary', 'document', 'device', 'ota', 'system')),
    is_read BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE notifications IS 'سجل وتاريخ الإشعارات الواردة للموظفين والأدمن وتصنيفاتها';

-- 26. رموز أجهزة الإشعارات (device_tokens)
CREATE TABLE IF NOT EXISTS device_tokens (
    employee_id UUID REFERENCES employees(id) ON DELETE CASCADE NOT NULL,
    token TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('android', 'ios')),
    PRIMARY KEY (employee_id, token)
);

COMMENT ON TABLE device_tokens IS 'رموز أجهزة الهواتف المخصصة لإرسال إشعارات Push عبر FCM';

-- 27. إعدادات النظام (system_settings)
CREATE TABLE IF NOT EXISTS system_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT
);

COMMENT ON TABLE system_settings IS 'إعدادات النظام العامة مثل فترات أرشفة بيانات التتبع وغيرها';

-- 28. سلة المحذوفات للملفات (deleted_files)
CREATE TABLE IF NOT EXISTS deleted_files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_path TEXT NOT NULL, -- المسار الكامل للملف في Supabase Storage
    file_type TEXT NOT NULL CHECK (file_type IN ('avatar', 'document', 'pledge', 'logo', 'other')),
    related_table TEXT,
    related_id TEXT,
    deleted_by UUID REFERENCES employees(id) ON DELETE SET NULL,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    scheduled_deletion_date TIMESTAMP WITH TIME ZONE NOT NULL, -- deleted_at + 30 days
    file_size_bytes BIGINT,
    restored_at TIMESTAMP WITH TIME ZONE
);

COMMENT ON TABLE deleted_files IS 'سلة المحذوفات للاحتفاظ بالملفات المحذوفة مؤقتاً لمدة 30 يوماً قبل الحذف التام';

-- ==========================================
-- 29. الـ View الخاص بدليل الموظفين الآمن
-- ==========================================
CREATE OR REPLACE VIEW v_employee_directory AS
SELECT 
    e.id,
    e.employee_code,
    e.full_name,
    e.phone,
    e.email,
    e.avatar_url,
    e.is_active,
    e.role,
    e.department_id,
    d.name as department_name,
    e.branch_id,
    b.name as branch_name,
    e.created_at
FROM employees e
LEFT JOIN departments d ON e.department_id = d.id
LEFT JOIN branches b ON e.branch_id = b.id
WHERE e.is_active = true;

COMMENT ON VIEW v_employee_directory IS 'واجهة دليل الموظفين المحمية التي تستبعد البيانات الحساسة وتعرض الموظفين النشطين فقط';
