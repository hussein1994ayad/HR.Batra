-- =====================================================================
-- 1) المستمسكات: الموظف يضيف فقط، والأدمن وحده يعدّل أو يحذف
--    الموظف يقدر يضيف مستمسكات جديدة لملفه (في مجلده <id>/...) ويرفع مرفقات
--    إجازاته (leaves/<id>/...)، لكن لا يحذف ولا يستبدل أي ملف موجود.
--    سياسة الرفع القديمة كانت تمنع مرفقات الإجازات بالغلط.
--
-- 2) الإجازة الزمنية تُخصم من الرصيد
--    الرصيد صار بكسور اليوم: ساعات الإجازة ÷ ساعات دوام الموظف
--    (مثال: 3 ساعات من دوام 8 ساعات = 0.38 يوم).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) المستمسكات
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_employee_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.role IS DISTINCT FROM OLD.role
     OR NEW.is_active IS DISTINCT FROM OLD.is_active
     OR NEW.branch_id IS DISTINCT FROM OLD.branch_id
     OR NEW.department_id IS DISTINCT FROM OLD.department_id
     OR NEW.employee_code IS DISTINCT FROM OLD.employee_code
     OR NEW.full_name IS DISTINCT FROM OLD.full_name
     OR NEW.email IS DISTINCT FROM OLD.email
     OR NEW.join_date IS DISTINCT FROM OLD.join_date
     OR NEW.monthly_salary_iqd IS DISTINCT FROM OLD.monthly_salary_iqd
     OR NEW.future_salary_iqd IS DISTINCT FROM OLD.future_salary_iqd
     OR NEW.future_salary_month IS DISTINCT FROM OLD.future_salary_month
     OR NEW.device_id_lock IS DISTINCT FROM OLD.device_id_lock
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR (NEW.must_change_password AND NOT COALESCE(OLD.must_change_password, false))
  THEN
    RAISE EXCEPTION 'غير مصرح: هذه البيانات يعدّلها قسم الموارد البشرية فقط.' USING ERRCODE = '42501';
  END IF;

  -- المستمسكات: إضافة فقط. كل القديمة تبقى، والجديدة من مجلد الموظف نفسه.
  IF NEW.document_urls IS DISTINCT FROM OLD.document_urls THEN
    IF NOT (COALESCE(NEW.document_urls, '[]'::jsonb) @> COALESCE(OLD.document_urls, '[]'::jsonb))
       OR EXISTS (
         SELECT 1
         FROM jsonb_array_elements_text(COALESCE(NEW.document_urls, '[]'::jsonb)) AS u(url)
         WHERE NOT (COALESCE(OLD.document_urls, '[]'::jsonb) ? u.url)
           AND position('/employee-documents/' || OLD.id::text || '/' IN u.url) = 0
       )
    THEN
      RAISE EXCEPTION 'غير مصرح: تقدر تضيف مستمسكات فقط، والحذف أو التعديل من قسم الموارد البشرية.' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DO $$
BEGIN
  IF to_regclass('storage.objects') IS NULL THEN
    RETURN;
  END IF;

  DROP POLICY IF EXISTS "Employees can upload own employee-documents" ON storage.objects;
  DROP POLICY IF EXISTS "Employees can update own employee-documents" ON storage.objects;
  DROP POLICY IF EXISTS "Employees can delete own employee-documents" ON storage.objects;
  DROP POLICY IF EXISTS "Employees can upload own leave attachments" ON storage.objects;

  DROP POLICY IF EXISTS "Employees can add own documents" ON storage.objects;

  -- الأدمن يدير الحاوية كاملة عبر "Admins can manage employee-documents".
  -- الموظف: رفع فقط (بدون تعديل أو حذف) في مجلده أو مجلد مرفقات إجازاته.
  CREATE POLICY "Employees can add own documents"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
      bucket_id = 'employee-documents'
      AND (storage.foldername(name))[1] = auth.uid()::text
    );

  CREATE POLICY "Employees can upload own leave attachments"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
      bucket_id = 'employee-documents'
      AND (storage.foldername(name))[1] = 'leaves'
      AND (storage.foldername(name))[2] = auth.uid()::text
    );
END $$;


-- ---------------------------------------------------------------------
-- 2) رصيد الإجازات بكسور اليوم
-- ---------------------------------------------------------------------
-- v_leaves_with_employee يعرض الرصيد، فيُعاد إنشاؤه بنفس تعريفه وصلاحياته
DO $$
DECLARE
  v_def text;
  v_grants text[];
  g text;
BEGIN
  IF to_regclass('public.v_leaves_with_employee') IS NOT NULL THEN
    v_def := pg_get_viewdef('public.v_leaves_with_employee'::regclass);
    SELECT array_agg(format('GRANT %s ON public.v_leaves_with_employee TO %I', privilege_type, grantee))
    INTO v_grants
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public' AND table_name = 'v_leaves_with_employee'
      AND grantee IN ('anon', 'authenticated', 'service_role');
    DROP VIEW public.v_leaves_with_employee;
  END IF;

  ALTER TABLE public.leave_balances
    ALTER COLUMN annual_used TYPE numeric(7, 2),
    ALTER COLUMN sick_used TYPE numeric(7, 2);

  IF v_def IS NOT NULL THEN
    EXECUTE 'CREATE VIEW public.v_leaves_with_employee WITH (security_invoker = true) AS ' || v_def;
    REVOKE ALL ON public.v_leaves_with_employee FROM anon, authenticated;
    FOREACH g IN ARRAY COALESCE(v_grants, '{}') LOOP
      EXECUTE g;
    END LOOP;
  END IF;
END $$;

-- ساعات دوام الموظف اليومية حسب جدوله (بدون جدول: 8 ساعات)
CREATE OR REPLACE FUNCTION public.employee_shift_hours(p_employee_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT NULLIF(
              EXTRACT(EPOCH FROM (
                CASE WHEN ws.check_out_time > ws.check_in_time
                     THEN ws.check_out_time - ws.check_in_time
                     ELSE ws.check_out_time - ws.check_in_time + interval '24 hours' END
              )) / 3600, 0)
     FROM work_schedules ws
     JOIN employees e ON e.id = p_employee_id
     WHERE ws.check_in_time IS NOT NULL AND ws.check_out_time IS NOT NULL
       AND (ws.employee_id = e.id
        OR (ws.employee_id IS NULL AND ws.department_id IS NOT NULL AND ws.department_id = e.department_id)
        OR (ws.employee_id IS NULL AND ws.department_id IS NULL AND ws.branch_id IS NOT NULL AND ws.branch_id = e.branch_id))
     ORDER BY CASE WHEN ws.employee_id IS NOT NULL THEN 0
                   WHEN ws.department_id IS NOT NULL THEN 1 ELSE 2 END,
              ws.created_at DESC
     LIMIT 1),
    8
  )::numeric;
$$;
REVOKE EXECUTE ON FUNCTION public.employee_shift_hours(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.employee_shift_hours(uuid) TO authenticated, service_role;

-- تغيير نوع الإرجاع يحتاج حذف الدالة (الدوال التي تستدعيها تُحلّ وقت التشغيل)
DROP FUNCTION IF EXISTS public.leave_request_days(leave_requests);

CREATE FUNCTION public.leave_request_days(lr leave_requests)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN lr.is_hourly THEN round(
      GREATEST(
        EXTRACT(EPOCH FROM COALESCE(lr.end_hour - lr.start_hour, lr.end_date - lr.start_date)) / 3600,
        0
      ) / public.employee_shift_hours(lr.employee_id),
      2)
    ELSE (
      SELECT count(*)::numeric
      FROM generate_series(
        (lr.start_date AT TIME ZONE public.company_timezone())::date,
        (lr.end_date AT TIME ZONE public.company_timezone())::date,
        interval '1 day') AS d
      WHERE EXTRACT(DOW FROM d)::integer = ANY (public.employee_work_days(lr.employee_id))
    )
  END;
$$;
REVOKE EXECUTE ON FUNCTION public.leave_request_days(leave_requests) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leave_request_days(leave_requests) TO authenticated, service_role;

-- الأرقام بالرسائل بدون أصفار زائدة (0.38 وليس 0.3800)
CREATE OR REPLACE FUNCTION public.fmt_days(v numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN v = trunc(v) THEN trunc(v)::text ELSE rtrim(rtrim(round(v, 2)::text, '0'), '.') END;
$$;

CREATE OR REPLACE FUNCTION public.validate_leave_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tz text := public.company_timezone();
  v_days numeric;
  v_left numeric;
BEGIN
  IF TG_OP = 'UPDATE' AND NOT (NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' AND NEW.status NOT IN ('pending', 'approved') THEN
    RETURN NEW;
  END IF;

  IF NEW.start_date IS NULL OR NEW.end_date IS NULL OR NEW.end_date < NEW.start_date THEN
    RAISE EXCEPTION 'تاريخ نهاية الإجازة يجب أن يكون بعد تاريخ بدايتها.' USING ERRCODE = '22023';
  END IF;
  IF NEW.is_hourly AND NEW.start_hour IS NOT NULL AND NEW.end_hour IS NOT NULL
     AND NEW.end_hour <= NEW.start_hour THEN
    RAISE EXCEPTION 'وقت نهاية الإجازة الزمنية يجب أن يكون بعد وقت بدايتها.' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM leave_requests o
    WHERE o.employee_id = NEW.employee_id
      AND o.id IS DISTINCT FROM NEW.id
      AND o.status IN ('pending', 'approved')
      AND (o.start_date AT TIME ZONE v_tz)::date <= (NEW.end_date AT TIME ZONE v_tz)::date
      AND (o.end_date AT TIME ZONE v_tz)::date >= (NEW.start_date AT TIME ZONE v_tz)::date
      AND (
        NOT (COALESCE(o.is_hourly, false) AND COALESCE(NEW.is_hourly, false))
        OR o.start_hour IS NULL OR NEW.start_hour IS NULL
        OR (o.start_hour < NEW.end_hour AND NEW.start_hour < o.end_hour)
      )
  ) THEN
    RAISE EXCEPTION 'توجد إجازة أخرى (قيد الانتظار أو معتمدة) تتداخل مع هذه التواريخ.' USING ERRCODE = '23P01';
  END IF;

  v_days := public.leave_request_days(NEW);
  IF NOT COALESCE(NEW.is_hourly, false) AND v_days = 0 THEN
    RAISE EXCEPTION 'الأيام المختارة كلها عطلة رسمية، لا حاجة لإجازة.' USING ERRCODE = '22023';
  END IF;

  IF NEW.leave_type IN ('annual', 'sick') AND v_days > 0 THEN
    INSERT INTO leave_balances (employee_id) VALUES (NEW.employee_id) ON CONFLICT (employee_id) DO NOTHING;
    SELECT CASE WHEN NEW.leave_type = 'annual'
                THEN annual_entitlement - annual_used
                ELSE sick_entitlement - sick_used END
    INTO v_left
    FROM leave_balances WHERE employee_id = NEW.employee_id;

    IF v_days > COALESCE(v_left, 0) THEN
      RAISE EXCEPTION 'رصيد الإجازة غير كافٍ: المطلوب % يوم والمتبقي % يوم.',
        public.fmt_days(v_days), public.fmt_days(GREATEST(COALESCE(v_left, 0), 0))
        USING ERRCODE = '22023';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- الإجازات الزمنية المعتمدة سابقاً لم تُخصم؛ نعيد حساب الرصيد المستخدم من الطلبات المعتمدة
UPDATE leave_balances lb
SET annual_used = s.annual_days,
    sick_used = s.sick_days,
    updated_at = now()
FROM (
  SELECT e.id AS employee_id,
         COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'annual'), 0) AS annual_days,
         COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'sick'), 0) AS sick_days
  FROM employees e
  LEFT JOIN leave_requests lr ON lr.employee_id = e.id AND lr.status = 'approved'
  GROUP BY e.id
) s
WHERE lb.employee_id = s.employee_id
  AND (lb.annual_used IS DISTINCT FROM s.annual_days OR lb.sick_used IS DISTINCT FROM s.sick_days);
