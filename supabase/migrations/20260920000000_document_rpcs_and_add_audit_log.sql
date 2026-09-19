-- =========================================================================
-- HR Pro v6.0 - RPCs documentation + Audit log infrastructure
-- Date: 2026-09-20
-- Fixes audit points 27 (undocumented RPCs) and 30 (no audit trail).
-- =========================================================================
--
-- 1) COMMENT ON FUNCTION for every RPC — makes them discoverable in
--    Supabase dashboard and via psql \df+
-- 2) audit_log table + trigger helpers for change tracking on sensitive tables
-- =========================================================================


-- =====================================================================
-- SECTION 1 — RPC documentation
-- =====================================================================

COMMENT ON FUNCTION public.is_admin(uuid) IS
'يعيد TRUE إذا كان المستخدم المعطى دوره admin. يُستخدم في RLS policies.';

COMMENT ON FUNCTION public.is_manager(uuid) IS
'يعيد TRUE إذا كان المستخدم manager أو admin. يستخدم في RLS policies للصلاحيات الوسيطة.';

COMMENT ON FUNCTION public.perform_daily_cleanup() IS
'التنظيف اليومي المؤتمت: يفرغ سلة المحذوفات بعد 30 يوم ويؤرشف بيانات التتبع القديمة.
يُستدعى من Edge Function daily-cleanup أو من pg_cron. يعيد قائمة الملفات المطلوب حذفها من التخزين.';

COMMENT ON FUNCTION public.safe_delete_employee(uuid, text) IS
'حذف آمن لموظف: ينقله لجدول archived_employees مع سبب الأرشفة بدلاً من الحذف النهائي.
يحافظ على سجلات الحضور والرواتب لأغراض الامتثال والضرائب.';

COMMENT ON FUNCTION public.hard_delete_employee(uuid) IS
'حذف نهائي لموظف من قاعدة البيانات وجميع الجداول المرتبطة. لا يمكن التراجع عنه.
يستخدم فقط في حال طلب المستخدم حذف بياناته بموجب GDPR.';

COMMENT ON FUNCTION public.create_employee_secure(text, text, text, uuid, uuid, text) IS
'إنشاء موظف جديد مع حساب Supabase Auth مربوط. مقفل على الأدمن فقط.
البارامترات: full_name, employee_code, email, department_id, branch_id, role.
يعيد UUID الموظف الجديد.';

COMMENT ON FUNCTION public.update_employee_credentials(uuid, text, text) IS
'تحديث كلمة المرور و/أو البريد الإلكتروني لموظف. مقفل على الأدمن.
البارامترات: employee_id, new_email, new_password.';

COMMENT ON FUNCTION public.safe_archive_payroll_month(text) IS
'أرشفة كشوف رواتب شهر معيّن ومنع تعديلها لاحقاً. البارامتر: work_month بصيغة YYYY-MM.';

COMMENT ON FUNCTION public.manual_purge_month_data(text) IS
'حذف يدوي فوري لكل بيانات شهر معين من جدول location_tracking فقط.
يستخدم في حال الحاجة لتفريغ مساحة قاعدة البيانات. البارامتر: YYYY-MM.';

COMMENT ON FUNCTION public.send_idempotent_notification(uuid, text, text, text) IS
'إرسال إشعار دون تكرار: يفحص إذا كان إشعار بنفس المحتوى موجود لنفس الموظف اليوم قبل الإدراج.
البارامترات: employee_id, title, body, type. يعيد UUID الإشعار المنشأ أو الموجود.';

COMMENT ON FUNCTION public.get_database_size() IS
'يعيد حجم قاعدة البيانات الحالي بالبايت. يستخدم في شاشة storage_stats.';

COMMENT ON FUNCTION public.get_database_table_sizes() IS
'يعيد قائمة الجداول مع أحجامها للعرض في لوحة الإدارة.';

COMMENT ON FUNCTION public.get_storage_stats() IS
'إحصائيات تفصيلية لملفات التخزين (Supabase Storage): عدد وحجم لكل bucket.';

COMMENT ON FUNCTION public.get_orphan_storage_candidates() IS
'يعيد الملفات في التخزين التي لا يوجد لها سجل في قاعدة البيانات (ملفات يتيمة).
لا يحذف — فقط يعيد مرشحين للحذف اليدوي من قِبل الأدمن.';

COMMENT ON FUNCTION public.update_loan_and_installments_trigger() IS
'Trigger function: يحدّث تلقائياً remaining_amount في جدول loans بعد كل تحديث في loan_installments.
لا يستدعى مباشرة من التطبيق.';


-- =====================================================================
-- SECTION 2 — Audit Log Infrastructure
-- =====================================================================

CREATE TABLE IF NOT EXISTS audit_log (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_name        TEXT NOT NULL,
    row_id            UUID,
    action            TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    actor_id          UUID REFERENCES employees(id) ON DELETE SET NULL,
    actor_email       TEXT,
    old_data          JSONB,
    new_data          JSONB,
    changed_columns   TEXT[],
    created_at        TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    ip_address        INET
);

COMMENT ON TABLE audit_log IS
'سجل تدقيق شامل للتغييرات على الجداول الحساسة (salary_slips, loans, employees, ...).
كل تحديث/إدراج/حذف يترك أثراً مع من فعل ومتى وأي أعمدة تغيّرت.';

CREATE INDEX IF NOT EXISTS idx_audit_log_table_row
    ON audit_log(table_name, row_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor
    ON audit_log(actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at
    ON audit_log(created_at DESC);


-- =====================================================================
-- SECTION 3 — Generic audit trigger function
-- =====================================================================

CREATE OR REPLACE FUNCTION public.record_audit_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_actor_id     UUID;
    v_actor_email  TEXT;
    v_changed_cols TEXT[];
    v_row_id       UUID;
BEGIN
    -- من هو الفاعل؟
    v_actor_id := auth.uid();
    IF v_actor_id IS NOT NULL THEN
        SELECT email INTO v_actor_email FROM auth.users WHERE id = v_actor_id;
    END IF;

    -- التقاط row_id بحسب نوع الجدول
    IF TG_OP = 'DELETE' THEN
        v_row_id := (OLD.id)::UUID;
    ELSE
        v_row_id := (NEW.id)::UUID;
    END IF;

    -- الأعمدة التي تغيّرت (فقط للـ UPDATE)
    IF TG_OP = 'UPDATE' THEN
        SELECT array_agg(key) INTO v_changed_cols
        FROM jsonb_each(to_jsonb(OLD)) o
        WHERE o.value IS DISTINCT FROM (to_jsonb(NEW) -> o.key);
    END IF;

    -- إدراج السطر في audit_log
    INSERT INTO audit_log (
        table_name, row_id, action, actor_id, actor_email,
        old_data, new_data, changed_columns
    ) VALUES (
        TG_TABLE_NAME,
        v_row_id,
        TG_OP,
        v_actor_id,
        v_actor_email,
        CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) ELSE NULL END,
        v_changed_cols
    );

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

COMMENT ON FUNCTION public.record_audit_log() IS
'Trigger function عامة لتسجيل التغييرات في audit_log. تلتقط: من فعل، متى، أي أعمدة تغيّرت.';


-- =====================================================================
-- SECTION 4 — Enable audit on sensitive tables
-- =====================================================================

-- salary_slips (كشوف الرواتب — الأخطر مالياً)
DROP TRIGGER IF EXISTS trg_audit_salary_slips ON salary_slips;
CREATE TRIGGER trg_audit_salary_slips
    AFTER INSERT OR UPDATE OR DELETE ON salary_slips
    FOR EACH ROW EXECUTE FUNCTION record_audit_log();

-- loans (السلف)
DROP TRIGGER IF EXISTS trg_audit_loans ON loans;
CREATE TRIGGER trg_audit_loans
    AFTER INSERT OR UPDATE OR DELETE ON loans
    FOR EACH ROW EXECUTE FUNCTION record_audit_log();

-- employees (بيانات الموظفين وأدوارهم)
DROP TRIGGER IF EXISTS trg_audit_employees ON employees;
CREATE TRIGGER trg_audit_employees
    AFTER INSERT OR UPDATE OR DELETE ON employees
    FOR EACH ROW EXECUTE FUNCTION record_audit_log();

-- bonuses_deductions (المكافآت والخصومات)
DROP TRIGGER IF EXISTS trg_audit_bonuses ON bonuses_deductions;
CREATE TRIGGER trg_audit_bonuses
    AFTER INSERT OR UPDATE OR DELETE ON bonuses_deductions
    FOR EACH ROW EXECUTE FUNCTION record_audit_log();

-- leave_requests (طلبات الإجازات وحالات الاعتماد)
DROP TRIGGER IF EXISTS trg_audit_leave_requests ON leave_requests;
CREATE TRIGGER trg_audit_leave_requests
    AFTER UPDATE OR DELETE ON leave_requests
    FOR EACH ROW EXECUTE FUNCTION record_audit_log();


-- =====================================================================
-- SECTION 5 — RLS on audit_log (only admins can read)
-- =====================================================================

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "audit_log admin read" ON audit_log;
CREATE POLICY "audit_log admin read"
    ON audit_log FOR SELECT
    USING (is_admin(auth.uid()));

-- لا نسمح لأحد بالكتابة المباشرة — Trigger فقط
DROP POLICY IF EXISTS "audit_log no direct writes" ON audit_log;
CREATE POLICY "audit_log no direct writes"
    ON audit_log FOR ALL
    USING (false)
    WITH CHECK (false);
