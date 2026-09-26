-- =====================================================================
-- جولة أمان ثانية (نتائج الفحص الشامل 2026-09-26)
--
-- 1) الموظف كان يقدر يعدّل راتبه وكوده وتاريخ تعيينه وقفل جهازه من صفه
--    (سياسة التحديث تقفل الدور والفرع والقسم والتفعيل فقط).
-- 2) كلمات السر كانت محفوظة نصاً مقروءاً (plain_password) لمعظم الحسابات.
-- 3) مستندات الموظفين وتعهدات السلف في حاويات عامة: أي أحد عنده الرابط يفتحها.
-- 4) قواعد الإجازات (التداخل، الرصيد، التواريخ) كانت في التطبيق فقط،
--    والأيام تُحسب مع أيام العطلة.
-- 5) المدير كان يقدر يغيّر أوقات بصمة أي موظف.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) أعمدة الموظف التي لا يغيّرها إلا الأدمن
--    الدوال SECURITY DEFINER (مثل register_device_login) تعمل بصلاحية
--    مالكها فلا يشملها هذا القيد.
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
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_employee_columns ON public.employees;
CREATE TRIGGER trg_protect_employee_columns
BEFORE UPDATE ON public.employees
FOR EACH ROW EXECUTE FUNCTION public.protect_employee_columns();


-- ---------------------------------------------------------------------
-- 2) لا كلمات سر مقروءة بعد اليوم
--    العمود يبقى (دوال قديمة تكتب فيه) لكنه يُفرَّغ دائماً.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.strip_plain_password()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.plain_password := NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_strip_plain_password ON public.employees;
CREATE TRIGGER trg_strip_plain_password
BEFORE INSERT OR UPDATE ON public.employees
FOR EACH ROW EXECUTE FUNCTION public.strip_plain_password();

UPDATE public.employees SET plain_password = NULL WHERE plain_password IS NOT NULL;
COMMENT ON COLUMN public.employees.plain_password IS
'مهجور: يُفرَّغ دائماً بالتريجر trg_strip_plain_password. لا تخزّن كلمات سر مقروءة.';


-- ---------------------------------------------------------------------
-- 3) المستندات والتعهدات خاصة — تُفتح بروابط موقّعة مؤقتة فقط
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NOT NULL THEN
    UPDATE storage.buckets SET public = false WHERE id IN ('employee-documents', 'loan-pledges');
  END IF;
END $$;

-- مرفقات الإجازات (leaves/<employee>/...): صاحبها + المدير (يعتمد الإجازات)
DO $$
BEGIN
  IF to_regclass('storage.objects') IS NOT NULL THEN
    DROP POLICY IF EXISTS "Leave attachments visible to owner and managers" ON storage.objects;
    CREATE POLICY "Leave attachments visible to owner and managers"
      ON storage.objects FOR SELECT TO authenticated
      USING (
        bucket_id = 'employee-documents'
        AND (storage.foldername(name))[1] = 'leaves'
        AND ((storage.foldername(name))[2] = auth.uid()::text OR public.is_manager())
      );
  END IF;
END $$;


-- ---------------------------------------------------------------------
-- 4) الإجازات: أيام العمل فقط + تحقق السيرفر
-- ---------------------------------------------------------------------

-- أيام العمل الأسبوعية للموظف (0=الأحد…6=السبت). بدون جدول: كل الأيام عدا الجمعة.
CREATE OR REPLACE FUNCTION public.employee_work_days(p_employee_id uuid)
RETURNS integer[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT ws.work_days
     FROM work_schedules ws
     JOIN employees e ON e.id = p_employee_id
     WHERE ws.employee_id = e.id
        OR (ws.employee_id IS NULL AND ws.department_id IS NOT NULL AND ws.department_id = e.department_id)
        OR (ws.employee_id IS NULL AND ws.department_id IS NULL AND ws.branch_id IS NOT NULL AND ws.branch_id = e.branch_id)
     ORDER BY CASE WHEN ws.employee_id IS NOT NULL THEN 0
                   WHEN ws.department_id IS NOT NULL THEN 1 ELSE 2 END,
              ws.created_at DESC
     LIMIT 1),
    ARRAY[0, 1, 2, 3, 4, 6]
  );
$$;
REVOKE EXECUTE ON FUNCTION public.employee_work_days(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.employee_work_days(uuid) TO authenticated, service_role;

-- عدد أيام الإجازة = أيام العمل فقط ضمن الفترة (العطل لا تُخصم من الرصيد)
CREATE OR REPLACE FUNCTION public.leave_request_days(lr leave_requests)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN lr.is_hourly THEN 0
    ELSE (
      SELECT count(*)::integer
      FROM generate_series(
        (lr.start_date AT TIME ZONE public.company_timezone())::date,
        (lr.end_date AT TIME ZONE public.company_timezone())::date,
        interval '1 day') AS d
      WHERE EXTRACT(DOW FROM d)::integer = ANY (public.employee_work_days(lr.employee_id))
    )
  END;
$$;

CREATE OR REPLACE FUNCTION public.validate_leave_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tz text := public.company_timezone();
  v_days integer;
  v_left integer;
BEGIN
  -- التحقق عند الإنشاء، وعند الاعتماد (قد يتغير الرصيد بين الطلب والاعتماد)
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

  -- لا تداخل مع إجازة أخرى قيد الانتظار أو معتمدة
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

  IF NOT COALESCE(NEW.is_hourly, false) THEN
    v_days := public.leave_request_days(NEW);
    IF v_days = 0 THEN
      RAISE EXCEPTION 'الأيام المختارة كلها عطلة رسمية، لا حاجة لإجازة.' USING ERRCODE = '22023';
    END IF;

    IF NEW.leave_type IN ('annual', 'sick') THEN
      INSERT INTO leave_balances (employee_id) VALUES (NEW.employee_id) ON CONFLICT (employee_id) DO NOTHING;
      SELECT CASE WHEN NEW.leave_type = 'annual'
                  THEN annual_entitlement - annual_used
                  ELSE sick_entitlement - sick_used END
      INTO v_left
      FROM leave_balances WHERE employee_id = NEW.employee_id;

      IF v_days > COALESCE(v_left, 0) THEN
        RAISE EXCEPTION 'رصيد الإجازة غير كافٍ: المطلوب % يوم والمتبقي % يوم.', v_days, GREATEST(COALESCE(v_left, 0), 0)
          USING ERRCODE = '22023';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_leave_request ON public.leave_requests;
CREATE TRIGGER trg_validate_leave_request
BEFORE INSERT OR UPDATE ON public.leave_requests
FOR EACH ROW EXECUTE FUNCTION public.validate_leave_request();


-- ---------------------------------------------------------------------
-- 5) المدير يقرّر الخصم فقط؛ أوقات البصمة وموقعها يعدّلها الأدمن فقط
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_attendance_times()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
     OR NEW.work_date IS DISTINCT FROM OLD.work_date
     OR NEW.check_in_time IS DISTINCT FROM OLD.check_in_time
     OR NEW.check_out_time IS DISTINCT FROM OLD.check_out_time
     OR NEW.check_in_lat IS DISTINCT FROM OLD.check_in_lat
     OR NEW.check_in_lng IS DISTINCT FROM OLD.check_in_lng
     OR NEW.check_out_lat IS DISTINCT FROM OLD.check_out_lat
     OR NEW.check_out_lng IS DISTINCT FROM OLD.check_out_lng
     OR NEW.is_mock_detected IS DISTINCT FROM OLD.is_mock_detected
     OR NEW.branch_id IS DISTINCT FROM OLD.branch_id
  THEN
    RAISE EXCEPTION 'غير مصرح: تعديل أوقات البصمة وموقعها للأدمن فقط.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_attendance_times ON public.attendance;
CREATE TRIGGER trg_protect_attendance_times
BEFORE UPDATE ON public.attendance
FOR EACH ROW EXECUTE FUNCTION public.protect_attendance_times();
