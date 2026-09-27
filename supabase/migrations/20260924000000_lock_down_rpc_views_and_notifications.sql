-- =========================================================================
-- HR Pro v6.0 — إغلاق الثغرات في الدوال (RPC) والـ Views والإشعارات
-- Date: 2026-09-24
-- =========================================================================
--
-- ما يعالجه هذا الملف:
--   1. دوال SECURITY DEFINER كانت قابلة للاستدعاء من أي مستخدم (وحتى بدون
--      تسجيل دخول) بدون أي فحص صلاحية:
--        update_employee_credentials  → كان يسمح بتغيير باسورد الأدمن
--        manual_purge_month_data / safe_archive_payroll_month → حذف بيانات
--        send_idempotent_notification، دوال إحصائيات التخزين، perform_daily_cleanup
--   2. نسخ قديمة من create_employee_secure (10 و 11 بارامتر) بدون فحص أدمن
--      بقيت موجودة بجانب النسخة المؤمّنة (CREATE OR REPLACE بتوقيع مختلف
--      يُنشئ نسخة جديدة ولا يستبدل القديمة).
--   3. صلاحية EXECUTE الافتراضية لـ anon على كل الدوال.
--   4. الـ Views كانت تتجاوز RLS (تُنفَّذ بصلاحيات مالكها)، و v_employee_directory
--      كان مقروءاً بدون تسجيل دخول.
--   5. أي موظف كان يقدر يرسل إشعار (push) لأي شخص بأي نص.
--   6. archived_months: أي موظف كان يقدر يقفل/يفتح شهر رواتب.
--   7. orphan_storage_candidates_cache: بدون RLS نهائياً.
--
-- كل الأوامر idempotent — آمن إعادة تشغيله.
-- =========================================================================


-- =====================================================================
-- 1) دوال مساعدة لفحص الصلاحيات
-- =====================================================================

CREATE OR REPLACE FUNCTION public.require_admin()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح: هذه العملية لمسؤول النظام (Admin) فقط.'
      USING ERRCODE = '42501';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.require_admin_or_manager()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT (public.is_admin() OR public.is_manager()) THEN
    RAISE EXCEPTION 'غير مصرح: هذه العملية للإدارة فقط.'
      USING ERRCODE = '42501';
  END IF;
END;
$$;

-- للدوال التي تُشغَّل من pg_cron أو الـ Edge Functions (service_role) أو من أدمن.
-- بدون JWT (pg_cron) → auth.uid() فارغ ومسموح. anon مرفوض صراحة.
CREATE OR REPLACE FUNCTION public.require_admin_or_system()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF COALESCE(auth.role(), '') = 'anon' THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح: هذه العملية لمسؤول النظام (Admin) فقط.'
      USING ERRCODE = '42501';
  END IF;
END;
$$;


-- =====================================================================
-- 2) create_employee_secure — حذف النسخ القديمة غير المؤمّنة
--    النسخة المعتمدة (12 بارامتر مع p_department_id) تفحص is_admin()
--    وتبقى كما هي. PostgREST يختار النسخة ذات الـ 12 بارامتر تلقائياً
--    حتى لو لم يُرسل p_join_date أو p_department_id (لها قيم افتراضية).
-- =====================================================================

DROP FUNCTION IF EXISTS public.create_employee_secure(
  text, text, text, text, text, uuid, numeric, text[], text, uuid);
DROP FUNCTION IF EXISTS public.create_employee_secure(
  text, text, text, text, text, uuid, numeric, text[], text, uuid, date);


-- =====================================================================
-- 3) update_employee_credentials — كان بدون أي فحص (استيلاء على أي حساب)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.update_employee_credentials(
  p_employee_id uuid,
  p_email text,
  p_password text DEFAULT NULL,
  p_phone text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_hashed_password text;
BEGIN
  PERFORM public.require_admin();

  IF p_password IS NOT NULL AND p_password != '' THEN
    v_hashed_password := extensions.crypt(p_password, extensions.gen_salt('bf'));
    UPDATE auth.users
    SET email = p_email,
        encrypted_password = v_hashed_password,
        phone = NULLIF(p_phone, ''),
        updated_at = now()
    WHERE id = p_employee_id;
  ELSE
    UPDATE auth.users
    SET email = p_email,
        phone = NULLIF(p_phone, ''),
        updated_at = now()
    WHERE id = p_employee_id;
  END IF;

  UPDATE auth.identities
  SET identity_data = jsonb_set(identity_data, '{email}', to_jsonb(p_email)),
      updated_at = now()
  WHERE user_id = p_employee_id;

  UPDATE public.employees
  SET email = p_email,
      phone = NULLIF(p_phone, ''),
      plain_password = CASE WHEN p_password IS NOT NULL AND p_password != '' THEN p_password ELSE plain_password END
  WHERE id = p_employee_id;
END;
$function$;


-- =====================================================================
-- 4) manual_purge_month_data — حذف بيانات شهر كامل، للأدمن فقط
-- =====================================================================

CREATE OR REPLACE FUNCTION public.manual_purge_month_data(
  p_year integer,
  p_month integer,
  p_notifications boolean DEFAULT false,
  p_tracking boolean DEFAULT false,
  p_absences boolean DEFAULT false
)
RETURNS TABLE (
  notifications_deleted integer,
  tracking_deleted integer,
  stops_deleted integer,
  violations_deleted integer,
  absences_deleted integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_start_date date;
  v_end_date date;
  v_notif_count integer := 0;
  v_track_count integer := 0;
  v_stops_count integer := 0;
  v_viol_count integer := 0;
  v_absent_count integer := 0;
BEGIN
  PERFORM public.require_admin();

  v_start_date := make_date(p_year, p_month, 1);
  v_end_date := (v_start_date + INTERVAL '1 month' - INTERVAL '1 day')::date;

  IF p_notifications THEN
    WITH del AS (
      DELETE FROM public.notifications
      WHERE created_at::date >= v_start_date AND created_at::date <= v_end_date
      RETURNING id
    )
    SELECT count(*)::integer INTO v_notif_count FROM del;
  END IF;

  IF p_tracking THEN
    WITH del_stops AS (
      DELETE FROM public.tracked_stops
      WHERE start_time::date >= v_start_date AND start_time::date <= v_end_date
      RETURNING id
    ),
    del_viol AS (
      DELETE FROM public.geofence_violations
      WHERE timestamp::date >= v_start_date AND timestamp::date <= v_end_date
      RETURNING id
    ),
    del_track AS (
      DELETE FROM public.location_tracking
      WHERE timestamp::date >= v_start_date AND timestamp::date <= v_end_date
      RETURNING id
    )
    SELECT
      (SELECT count(*)::integer FROM del_track),
      (SELECT count(*)::integer FROM del_stops),
      (SELECT count(*)::integer FROM del_viol)
    INTO v_track_count, v_stops_count, v_viol_count;
  END IF;

  IF p_absences THEN
    WITH del_att AS (
      DELETE FROM public.attendance
      WHERE work_date >= v_start_date AND work_date <= v_end_date
      RETURNING id
    )
    SELECT count(*)::integer INTO v_absent_count FROM del_att;
  END IF;

  RETURN QUERY SELECT v_notif_count, v_track_count, v_stops_count, v_viol_count, v_absent_count;
END;
$function$;


-- =====================================================================
-- 5) send_idempotent_notification — الموظف يرسل لنفسه فقط
-- =====================================================================

CREATE OR REPLACE FUNCTION public.send_idempotent_notification(
  p_employee_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_type TEXT,
  p_dedup_window_minutes INT DEFAULT 60
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND p_employee_id IS DISTINCT FROM auth.uid()
     AND NOT (public.is_admin() OR public.is_manager()) THEN
    RAISE EXCEPTION 'غير مصرح بإرسال إشعار لموظف آخر.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.notifications
    WHERE employee_id = p_employee_id
      AND title = p_title
      AND body = p_body
      AND created_at > (NOW() - (p_dedup_window_minutes || ' minutes')::INTERVAL)
  ) THEN
    RETURN false;
  END IF;

  INSERT INTO public.notifications (employee_id, title, body, type, is_read, created_at)
  VALUES (p_employee_id, p_title, p_body, p_type, false, NOW());

  RETURN true;
END;
$$;


-- =====================================================================
-- 6) دوال الإحصائيات — للإدارة فقط (كانت تكشف مسارات ملفات المستندات)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_storage_stats()
RETURNS TABLE (
    bucket_name  TEXT,
    total_size   BIGINT,
    file_count   BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
BEGIN
    PERFORM public.require_admin_or_manager();

    RETURN QUERY
    SELECT
        b.id::TEXT AS bucket_name,
        COALESCE(SUM(
            COALESCE(
                (o.metadata->>'size')::BIGINT,
                (o.metadata->>'contentLength')::BIGINT,
                (o.user_metadata->>'size')::BIGINT,
                0
            )
        ), 0)::BIGINT AS total_size,
        COUNT(o.id)::BIGINT AS file_count
    FROM storage.buckets b
    LEFT JOIN storage.objects o ON o.bucket_id = b.id
    GROUP BY b.id
    ORDER BY b.id;
END;
$$;

-- كانت LANGUAGE sql — تحويلها لـ plpgsql لإضافة فحص الصلاحية
CREATE OR REPLACE FUNCTION public.get_database_size()
RETURNS TABLE (db_size bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  PERFORM public.require_admin_or_manager();
  RETURN QUERY SELECT pg_database_size(current_database())::bigint AS db_size;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_database_table_sizes()
RETURNS TABLE (
  table_name text,
  row_count bigint,
  total_bytes bigint,
  pretty_size text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  PERFORM public.require_admin_or_manager();

  RETURN QUERY
  SELECT
    c.relname::text AS table_name,
    c.reltuples::bigint AS row_count,
    pg_total_relation_size(c.oid)::bigint AS total_bytes,
    pg_size_pretty(pg_total_relation_size(c.oid))::text AS pretty_size
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
  ORDER BY pg_total_relation_size(c.oid) DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_orphan_storage_candidates()
RETURNS TABLE (
  bucket_id TEXT,
  file_path TEXT,
  file_size BIGINT,
  created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin();

  RETURN QUERY
  SELECT
    CASE
      WHEN df.file_type = 'avatar' THEN 'avatars'::TEXT
      WHEN df.file_type = 'document' THEN 'employee-documents'::TEXT
      WHEN df.file_type = 'pledge' THEN 'loan-pledges'::TEXT
      WHEN df.file_type = 'logo' THEN 'company-logos'::TEXT
      ELSE 'employee-documents'::TEXT
    END as bucket_id,
    df.file_path,
    COALESCE(df.file_size_bytes, 0) as file_size,
    df.deleted_at as created_at
  FROM public.deleted_files df
  WHERE df.restored_at IS NULL;
END;
$$;



-- =====================================================================
-- 7) safe_archive_payroll_month — يحذف حضور وخصومات دورة كاملة، للأدمن فقط
--    (الجسم منسوخ كما هو من 20260623000001 مع إضافة فحص الصلاحية)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.safe_archive_payroll_month(
    target_month TEXT,
    cycle_start_day INT DEFAULT 25,
    cycle_end_day INT DEFAULT 24
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_year INT;
    v_month INT;
    v_active_emp_count INT;
    v_slips_count INT;
    v_unpaid_installments INT;
    v_latest_slip_date TIMESTAMP;
    v_days_since_latest INT;
    v_att_deleted INT;
    v_bd_deleted INT;
    v_notif_deleted INT;
    v_already_archived BOOLEAN;
    v_missing_employees TEXT[];
BEGIN
    PERFORM public.require_admin();

    -- فحص 0: هل الشهر مؤرشف مسبقاً؟
    SELECT EXISTS(SELECT 1 FROM archived_months WHERE work_month = target_month) INTO v_already_archived;
    IF v_already_archived THEN
        RETURN json_build_object(
            'success', false,
            'error', 'هذا الشهر مؤرشف مسبقاً ولا يمكن أرشفته مرة أخرى.'
        );
    END IF;

    -- حساب فترة الدورة المالية (مثل 25 من الشهر السابق إلى 24 من الشهر الحالي)
    v_year := SPLIT_PART(target_month, '-', 1)::INT;
    v_month := SPLIT_PART(target_month, '-', 2)::INT;

    -- تاريخ البداية: cycle_start_day من الشهر السابق
    IF v_month = 1 THEN
        v_start_date := MAKE_DATE(v_year - 1, 12, cycle_start_day);
    ELSE
        v_start_date := MAKE_DATE(v_year, v_month - 1, cycle_start_day);
    END IF;

    -- تاريخ النهاية: cycle_end_day من الشهر الحالي
    v_end_date := MAKE_DATE(v_year, v_month, cycle_end_day);

    -- فحص 1: هل كل الموظفين النشطين عندهم كشف راتب معتمد؟
    SELECT COUNT(*) INTO v_active_emp_count
    FROM employees WHERE is_active = true;

    SELECT COUNT(*) INTO v_slips_count
    FROM salary_slips WHERE work_month = target_month;

    IF v_slips_count < v_active_emp_count THEN
        -- جمع أسماء الموظفين الذين بدون راتب معتمد
        SELECT ARRAY_AGG(e.full_name) INTO v_missing_employees
        FROM employees e
        WHERE e.is_active = true
            AND NOT EXISTS (
                SELECT 1 FROM salary_slips ss
                WHERE ss.employee_id = e.id AND ss.work_month = target_month
            );

        RETURN json_build_object(
            'success', false,
            'error', 'لا يمكن الأرشفة: يوجد ' || (v_active_emp_count - v_slips_count) || ' موظف بدون راتب معتمد لهذا الشهر.',
            'missing_employees', v_missing_employees
        );
    END IF;

    -- فحص 2: هل مرّت 60 يوم على الأقل من آخر اعتماد؟
    SELECT MAX(created_at) INTO v_latest_slip_date
    FROM salary_slips WHERE work_month = target_month;

    v_days_since_latest := EXTRACT(DAY FROM (NOW() - v_latest_slip_date));

    IF v_days_since_latest < 60 THEN
        RETURN json_build_object(
            'success', false,
            'error', 'لا يمكن الأرشفة بعد: لم تمر 60 يوماً من آخر اعتماد راتب لهذا الشهر (مرّ ' || v_days_since_latest || ' يوم فقط). يمكن الأرشفة بعد ' || (60 - v_days_since_latest) || ' يوم.'
        );
    END IF;

    -- فحص 3: لا توجد أقساط سلف غير مدفوعة ضمن الفترة
    SELECT COUNT(*) INTO v_unpaid_installments
    FROM loan_installments li
    JOIN loans l ON li.loan_id = l.id
    WHERE li.due_date >= v_start_date
        AND li.due_date <= v_end_date
        AND li.is_paid = false
        AND l.status = 'approved';

    IF v_unpaid_installments > 0 THEN
        RETURN json_build_object(
            'success', false,
            'error', 'لا يمكن الأرشفة: يوجد ' || v_unpaid_installments || ' قسط سلفة غير مدفوع ضمن هذه الفترة. يرجى اعتماد الرواتب أو سداد الأقساط أولاً.'
        );
    END IF;

    -- ✅ كل الفحوصات نجحت — بدء الأرشفة الآمنة

    -- حذف سجلات الحضور التفصيلية للفترة
    DELETE FROM attendance
    WHERE work_date >= v_start_date AND work_date <= v_end_date;
    GET DIAGNOSTICS v_att_deleted = ROW_COUNT;

    -- حذف سجلات المكافآت والخصومات للفترة (الأرقام النهائية محفوظة بـ salary_slips)
    DELETE FROM bonuses_deductions
    WHERE issue_date >= v_start_date AND issue_date <= v_end_date;
    GET DIAGNOSTICS v_bd_deleted = ROW_COUNT;

    -- حذف الإشعارات القديمة (أكثر من 90 يوم)
    DELETE FROM notifications
    WHERE created_at < NOW() - INTERVAL '90 days';
    GET DIAGNOSTICS v_notif_deleted = ROW_COUNT;

    -- تسجيل الشهر كمؤرشف
    INSERT INTO archived_months (work_month, attendance_deleted, bd_deleted, notifications_deleted)
    VALUES (target_month, v_att_deleted, v_bd_deleted, v_notif_deleted);

    RETURN json_build_object(
        'success', true,
        'message', 'تم أرشفة شهر ' || target_month || ' بنجاح! 📦',
        'attendance_deleted', v_att_deleted,
        'bd_deleted', v_bd_deleted,
        'notifications_deleted', v_notif_deleted
    );
END;
$$;


-- =====================================================================
-- 8) perform_daily_cleanup — للأدمن أو pg_cron/service_role فقط
--    (الجسم منسوخ كما هو من 20260702000000 مع إضافة فحص الصلاحية)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.perform_daily_cleanup()
RETURNS TABLE (expired_file_path TEXT, expired_bucket_id TEXT, file_record_id UUID) AS $$
DECLARE
  archive_record RECORD;
  tracking_archive_days INT;
BEGIN
  PERFORM public.require_admin_or_system();

  -- 0. ترقية وتفعيل الراتب المستقبلي للموظفين المستحقين
  UPDATE public.employees 
  SET 
    monthly_salary_iqd = future_salary_iqd,
    future_salary_iqd = NULL,
    future_salary_month = NULL
  WHERE future_salary_month IS NOT NULL 
    AND future_salary_iqd IS NOT NULL 
    AND future_salary_month <= TO_CHAR(NOW(), 'YYYY-MM-DD');

  -- 1. الحصول على مدة أرشفة التتبع من إعدادات النظام (الافتراضي 180 يوماً / 6 أشهر)
  SELECT COALESCE((value->>'tracking_archive_days')::INT, 180) INTO tracking_archive_days
  FROM public.system_settings WHERE key = 'archive_policy';

  -- 2. حذف بيانات التتبع والموقع القديمة
  DELETE FROM public.location_tracking WHERE timestamp < (NOW() - (tracking_archive_days || ' days')::INTERVAL);
  DELETE FROM public.tracked_stops WHERE start_time < (NOW() - (tracking_archive_days || ' days')::INTERVAL);
  DELETE FROM public.geofence_violations WHERE timestamp < (NOW() - (tracking_archive_days || ' days')::INTERVAL);

  -- 3. تنظيف الإشعارات القديمة تلقائياً
  DELETE FROM public.notifications WHERE is_read = true AND created_at < (NOW() - INTERVAL '30 days');
  DELETE FROM public.notifications WHERE created_at < (NOW() - INTERVAL '90 days');

  -- 4. إرسال إشعارات التنبيه للأدمن عن موظف مجدول للحذف قبل الحذف بأسبوع
  INSERT INTO public.notifications (employee_id, title, body, type, is_read, created_at)
  SELECT 
    COALESCE(archived_by, (SELECT id FROM public.employees WHERE role = 'admin' LIMIT 1)),
    'تنبيه: حذف مجدول لموظف خلال أسبوع',
    'تنبيه: سيتم حذف بيانات الموظف (' || full_name || ') نهائياً وبشكل كامل في تاريخ ' || TO_CHAR(scheduled_deletion_date, 'YYYY-MM-DD') || '.',
    'system',
    false,
    NOW()
  FROM public.archived_employees
  WHERE archive_type = 'scheduled_deletion' 
    AND scheduled_deletion_date BETWEEN NOW() AND NOW() + INTERVAL '7 days'
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications 
      WHERE notifications.employee_id = COALESCE(archived_employees.archived_by, (SELECT id FROM employees WHERE role = 'admin' LIMIT 1))
        AND notifications.title = 'تنبيه: حذف مجدول لموظف خلال أسبوع'
        AND notifications.created_at > NOW() - INTERVAL '1 day'
    );

  -- 5. معالجة الحذف المجدول للموظفين المؤرشفين
  FOR archive_record IN 
    SELECT employee_id, full_name FROM public.archived_employees 
    WHERE archive_type = 'scheduled_deletion' AND scheduled_deletion_date <= NOW()
  LOOP
    DELETE FROM public.employees WHERE id = archive_record.employee_id;
    UPDATE public.archived_employees 
    SET 
      archive_type = 'permanent', 
      notes = COALESCE(notes, '') || ' - تم التنفيذ التلقائي للحذف المجدول بتاريخ ' || TO_CHAR(NOW(), 'YYYY-MM-DD') || '.'
    WHERE employee_id = archive_record.employee_id;
  END LOOP;

  -- 6. إرجاع قائمة الملفات المنتهية في سلة المحذوفات بالمجلدات الصحيحة
  RETURN QUERY 
  SELECT 
    df.file_path as expired_file_path, 
    CASE 
      WHEN df.file_type = 'avatar' THEN 'avatars'::TEXT
      WHEN df.file_type = 'document' THEN 'employee-documents'::TEXT
      WHEN df.file_type = 'pledge' THEN 'loan-pledges'::TEXT
      WHEN df.file_type = 'logo' THEN 'company-logos'::TEXT
      ELSE 'employee-documents'::TEXT
    END as expired_bucket_id,
    df.id as file_record_id
  FROM public.deleted_files df
  WHERE df.scheduled_deletion_date <= NOW() AND df.restored_at IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- =====================================================================
-- 9) صلاحيات EXECUTE — لا شيء لـ anon، ودوال الجدولة للنظام فقط
-- =====================================================================

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;
GRANT  EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, service_role;

-- is_admin/is_manager تُقيَّم داخل سياسات RLS؛ تبقى متاحة (ترجع false لغير المسجل)
GRANT EXECUTE ON FUNCTION public.is_admin(), public.is_manager() TO anon;

-- الدوال الجديدة مستقبلاً لا تُمنح لـ anon تلقائياً
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;

-- دوال تُشغَّل من pg_cron فقط (بعضها قد لا يكون موجوداً في كل البيئات)
DO $$
DECLARE
  fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.purge_old_location_tracking()',
    'public.refresh_orphan_candidates_cache()',
    'public.check_and_send_attendance_reminders()'
  ] LOOP
    IF to_regprocedure(fn) IS NOT NULL THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', fn);
    END IF;
  END LOOP;
END $$;


-- =====================================================================
-- 10) الـ Views — تحترم RLS، ولا وصول لـ anon
-- =====================================================================

DO $$
DECLARE
  v record;
BEGIN
  FOR v IN
    SELECT schemaname, viewname FROM pg_views WHERE schemaname = 'public'
  LOOP
    EXECUTE format('ALTER VIEW %I.%I SET (security_invoker = true)', v.schemaname, v.viewname);
    EXECUTE format('REVOKE ALL ON %I.%I FROM anon', v.schemaname, v.viewname);
  END LOOP;
END $$;

-- دليل الموظفين: بعد security_invoker يرى الموظف صفّه فقط عبر الـ View
-- (تستعمله شاشتا الرئيسية والإعدادات لبيانات الموظف نفسه).
-- قائمة الزملاء تُجلب من هذه الدالة: أعمدة غير حساسة فقط، للمسجلين فقط.
CREATE OR REPLACE FUNCTION public.get_employee_directory()
RETURNS TABLE (
  id uuid,
  employee_code text,
  full_name text,
  phone text,
  email text,
  avatar_url text,
  role text,
  department_id uuid,
  department_name text,
  branch_id uuid,
  branch_name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT e.id, e.employee_code, e.full_name, e.phone, e.email, e.avatar_url,
         e.role, e.department_id, d.name, e.branch_id, b.name
  FROM employees e
  LEFT JOIN departments d ON d.id = e.department_id
  LEFT JOIN branches b ON b.id = e.branch_id
  WHERE e.is_active = true
  ORDER BY e.full_name;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_employee_directory() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_employee_directory() TO authenticated;


-- =====================================================================
-- 11) الإشعارات — الموظف يكتب لنفسه فقط، الإدارة لأي موظف
--     إشعارات "طلب جديد" للمدراء تُنشأ من Triggers (SECURITY DEFINER).
-- =====================================================================

DROP POLICY IF EXISTS "Anyone can insert notifications" ON notifications;
DROP POLICY IF EXISTS "Insert own notifications or as management" ON notifications;
CREATE POLICY "Insert own notifications or as management"
ON notifications FOR INSERT TO authenticated
WITH CHECK (employee_id = auth.uid() OR is_admin() OR is_manager());

DROP POLICY IF EXISTS "Employees can update their own notifications" ON notifications;
CREATE POLICY "Employees can update their own notifications"
ON notifications FOR UPDATE TO authenticated
USING (employee_id = auth.uid())
WITH CHECK (employee_id = auth.uid());


-- =====================================================================
-- 12) archived_months — القراءة للجميع، القفل/الفتح للأدمن فقط
-- =====================================================================

DROP POLICY IF EXISTS "authenticated_users_archived_months" ON archived_months;
DROP POLICY IF EXISTS "Authenticated can view archived months" ON archived_months;
DROP POLICY IF EXISTS "Only admins can manage archived months" ON archived_months;

CREATE POLICY "Authenticated can view archived months"
ON archived_months FOR SELECT TO authenticated
USING (true);

CREATE POLICY "Only admins can manage archived months"
ON archived_months TO authenticated
USING (is_admin())
WITH CHECK (is_admin());


-- =====================================================================
-- 13) orphan_storage_candidates_cache — كان بدون RLS
-- =====================================================================

DO $$
BEGIN
  IF to_regclass('public.orphan_storage_candidates_cache') IS NOT NULL THEN
    ALTER TABLE public.orphan_storage_candidates_cache ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "Only admins can use orphan cache" ON public.orphan_storage_candidates_cache;
    CREATE POLICY "Only admins can use orphan cache"
      ON public.orphan_storage_candidates_cache TO authenticated
      USING (is_admin()) WITH CHECK (is_admin());
  END IF;
END $$;


-- =====================================================================
-- 14) جداول الدوام والتتبع — لم تكن لها سياسات موثّقة في المستودع
--     (RLS مفعّل بدون سياسة = لا أحد يقرأ). السياسات أدناه تضمن
--     أن الموظف يقرأ جدوله، والأدمن يدير الكل.
-- =====================================================================

DROP POLICY IF EXISTS "Authenticated can view work schedules" ON work_schedules;
CREATE POLICY "Authenticated can view work schedules"
ON work_schedules FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS "Only admins can manage work schedules" ON work_schedules;
CREATE POLICY "Only admins can manage work schedules"
ON work_schedules TO authenticated
USING (is_admin()) WITH CHECK (is_admin());

DROP POLICY IF EXISTS "Employees view own tracking schedule" ON tracking_schedules;
CREATE POLICY "Employees view own tracking schedule"
ON tracking_schedules FOR SELECT TO authenticated
USING (employee_id = auth.uid() OR is_admin() OR is_manager());

DROP POLICY IF EXISTS "Only admins can manage tracking schedules" ON tracking_schedules;
CREATE POLICY "Only admins can manage tracking schedules"
ON tracking_schedules TO authenticated
USING (is_admin()) WITH CHECK (is_admin());

-- هذا الجدول لم يكن عليه RLS أصلاً (مفتوح للقراءة والكتابة من أي أحد)
ALTER TABLE employee_geofence_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Employees view own geofence assignments" ON employee_geofence_assignments;
CREATE POLICY "Employees view own geofence assignments"
ON employee_geofence_assignments FOR SELECT TO authenticated
USING (employee_id = auth.uid() OR is_admin() OR is_manager());

DROP POLICY IF EXISTS "Only admins can manage geofence assignments" ON employee_geofence_assignments;
CREATE POLICY "Only admins can manage geofence assignments"
ON employee_geofence_assignments TO authenticated
USING (is_admin()) WITH CHECK (is_admin());
