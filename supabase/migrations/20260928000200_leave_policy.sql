-- =====================================================================
-- سياسة الإجازات (تُعدَّل من إعدادات الموقع)
--
--   leave_policy في system_settings:
--     default_annual        أيام الإجازة السنوية لكل سنة
--     default_sick          أيام الإجازة المرضية لكل سنة
--     hourly_monthly_hours  ساعات الإجازات الزمنية المسموحة لكل شهر
--     active_types          أنواع الإجازات المتاحة
--
--   • السنوية والمرضية تتجدد كل سنة ميلادية؛ المستخدم = مجموع أيام العمل في
--     الإجازات المعتمدة من نفس السنة (الجمعة والعطل لا تُحسب).
--   • الزمنيات لها رصيد ساعات شهري منفصل يتجدد كل شهر، ولا تُخصم من الأيام.
--   • يمكن تخصيص رصيد موظف معيّن (leave_balances.*_entitlement، فارغ = السياسة).
--
-- قبل هذا: أرقام "سياسة الإجازات" في الإعدادات لم تكن مربوطة بشيء، والرصيد
-- المستخدم يتراكم مدى الحياة ولا يتجدد سنوياً، وإضافة نوع إجازة جديد من
-- الإعدادات كان يجعل كل طلب منه يفشل (قيد CHECK بخمسة أنواع ثابتة).
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) السياسة
-- ---------------------------------------------------------------------
INSERT INTO system_settings (key, value, description)
VALUES ('leave_policy',
        jsonb_build_object(
          'default_annual', 21, 'default_sick', 15, 'hourly_monthly_hours', 8,
          'active_types', jsonb_build_array(
            jsonb_build_object('id', 'annual', 'name', 'إجازة سنوية'),
            jsonb_build_object('id', 'sick', 'name', 'إجازة مرضية'),
            jsonb_build_object('id', 'emergency', 'name', 'إجازة طارئة'),
            jsonb_build_object('id', 'maternity', 'name', 'إجازة أمومة'),
            jsonb_build_object('id', 'other', 'name', 'إجازة أخرى'))),
        'سياسة الإجازات العامة وأنواعها المتاحة بالشركة')
ON CONFLICT (key) DO UPDATE
SET value = system_settings.value
  || jsonb_build_object('hourly_monthly_hours', COALESCE(system_settings.value -> 'hourly_monthly_hours', '8'::jsonb));

CREATE OR REPLACE FUNCTION public.leave_policy()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT value FROM system_settings WHERE key = 'leave_policy'), '{}'::jsonb);
$$;
REVOKE EXECUTE ON FUNCTION public.leave_policy() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leave_policy() TO authenticated, service_role;


-- ---------------------------------------------------------------------
-- 2) رصيد الموظف: فارغ = حسب السياسة
-- ---------------------------------------------------------------------
ALTER TABLE public.leave_balances
  ALTER COLUMN annual_entitlement DROP NOT NULL,
  ALTER COLUMN annual_entitlement DROP DEFAULT,
  ALTER COLUMN sick_entitlement DROP NOT NULL,
  ALTER COLUMN sick_entitlement DROP DEFAULT,
  ADD COLUMN IF NOT EXISTS hourly_monthly_hours numeric(6, 2);

-- الأرصدة الحالية كلها كانت القيمة الافتراضية للعمود (لم تكن هناك واجهة لتعديلها)
UPDATE public.leave_balances SET annual_entitlement = NULL WHERE annual_entitlement = 21;
UPDATE public.leave_balances SET sick_entitlement = NULL WHERE sick_entitlement = 15;

COMMENT ON COLUMN public.leave_balances.annual_entitlement IS 'أيام السنوية لهذا الموظف؛ فارغ = leave_policy.default_annual';
COMMENT ON COLUMN public.leave_balances.sick_entitlement IS 'أيام المرضية لهذا الموظف؛ فارغ = leave_policy.default_sick';
COMMENT ON COLUMN public.leave_balances.hourly_monthly_hours IS 'ساعات الزمنيات الشهرية لهذا الموظف؛ فارغ = leave_policy.hourly_monthly_hours';
COMMENT ON COLUMN public.leave_balances.annual_used IS 'مهجور: الرصيد المستخدم يُحسب من الطلبات المعتمدة (get_leave_balance)';
COMMENT ON COLUMN public.leave_balances.sick_used IS 'مهجور: الرصيد المستخدم يُحسب من الطلبات المعتمدة (get_leave_balance)';

-- العدّاد التراكمي لم يعد مستعملاً
DROP TRIGGER IF EXISTS trg_apply_leave_balance_change ON public.leave_requests;
DROP FUNCTION IF EXISTS public.apply_leave_balance_change();

-- الواجهة كانت تعرض العدّاد التراكمي؛ تُعاد بدون أعمدة الرصيد
DO $$
DECLARE
  v_grants text[];
  g text;
BEGIN
  IF to_regclass('public.v_leaves_with_employee') IS NOT NULL THEN
    SELECT array_agg(format('GRANT %s ON public.v_leaves_with_employee TO %I', privilege_type, grantee))
    INTO v_grants
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public' AND table_name = 'v_leaves_with_employee'
      AND grantee IN ('anon', 'authenticated', 'service_role');
    DROP VIEW public.v_leaves_with_employee;
  END IF;

  CREATE VIEW public.v_leaves_with_employee WITH (security_invoker = true) AS
  SELECT lr.id, lr.employee_id, e.full_name AS employee_name, e.employee_code,
         d.name AS department_name, lr.start_date, lr.end_date, lr.leave_type,
         lr.is_hourly, lr.start_hour, lr.end_hour, lr.is_paid, lr.reason, lr.status,
         lr.attachment_url, lr.approved_by, lr.approved_at, lr.created_at
  FROM leave_requests lr
  LEFT JOIN employees e ON e.id = lr.employee_id
  LEFT JOIN departments d ON d.id = e.department_id;

  REVOKE ALL ON public.v_leaves_with_employee FROM anon, authenticated;
  FOREACH g IN ARRAY COALESCE(v_grants, ARRAY['GRANT SELECT ON public.v_leaves_with_employee TO authenticated']) LOOP
    EXECUTE g;
  END LOOP;
END $$;


-- ---------------------------------------------------------------------
-- 3) أنواع الإجازات من السياسة بدل قيد ثابت
-- ---------------------------------------------------------------------
ALTER TABLE public.leave_requests DROP CONSTRAINT IF EXISTS leave_requests_leave_type_check;


-- ---------------------------------------------------------------------
-- 4) أيام وساعات الطلب
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.leave_request_days(leave_requests);
CREATE FUNCTION public.leave_request_days(lr leave_requests)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN lr.is_hourly THEN 0::numeric
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

CREATE OR REPLACE FUNCTION public.leave_request_hours(lr leave_requests)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT CASE WHEN lr.is_hourly
    THEN round(GREATEST(EXTRACT(EPOCH FROM COALESCE(lr.end_hour - lr.start_hour, lr.end_date - lr.start_date)) / 3600, 0)::numeric, 2)
    ELSE 0::numeric END;
$$;
REVOKE EXECUTE ON FUNCTION public.leave_request_hours(leave_requests) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leave_request_hours(leave_requests) TO authenticated, service_role;


-- ---------------------------------------------------------------------
-- 5) الرصيد: get_leave_balance
-- ---------------------------------------------------------------------
-- p_on: أي يوم داخل السنة/الشهر المطلوب (افتراضياً اليوم). p_exclude: طلب لا يُحسب
-- (يُستعمل عند اعتماد طلب قيد الانتظار حتى لا يُحسب مرتين).
CREATE OR REPLACE FUNCTION public.get_leave_balance(
  p_employee_id uuid DEFAULT NULL,
  p_on date DEFAULT NULL,
  p_exclude uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp uuid := COALESCE(p_employee_id, auth.uid());
  v_tz text := public.company_timezone();
  v_on date := COALESCE(p_on, (now() AT TIME ZONE public.company_timezone())::date);
  v_year_start date := date_trunc('year', v_on)::date;
  v_month_start date := date_trunc('month', v_on)::date;
  v_policy jsonb := public.leave_policy();
  v_lb leave_balances%ROWTYPE;
  v_annual numeric; v_sick numeric; v_hours numeric;
  r record;
BEGIN
  IF auth.uid() IS NOT NULL AND v_emp <> auth.uid() AND NOT (public.is_admin() OR public.is_manager()) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_lb FROM leave_balances WHERE employee_id = v_emp;
  v_annual := COALESCE(v_lb.annual_entitlement, (v_policy ->> 'default_annual')::numeric, 21);
  v_sick   := COALESCE(v_lb.sick_entitlement, (v_policy ->> 'default_sick')::numeric, 15);
  v_hours  := COALESCE(v_lb.hourly_monthly_hours, (v_policy ->> 'hourly_monthly_hours')::numeric, 8);

  SELECT
    COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'annual' AND lr.status = 'approved'), 0) AS annual_used,
    COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'annual' AND lr.status = 'pending'), 0) AS annual_pending,
    COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'sick' AND lr.status = 'approved'), 0) AS sick_used,
    COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'sick' AND lr.status = 'pending'), 0) AS sick_pending
  INTO r
  FROM leave_requests lr
  WHERE lr.employee_id = v_emp
    AND lr.id IS DISTINCT FROM p_exclude
    AND NOT COALESCE(lr.is_hourly, false)
    AND (lr.start_date AT TIME ZONE v_tz)::date >= v_year_start
    AND (lr.start_date AT TIME ZONE v_tz)::date < (v_year_start + interval '1 year')::date;

  RETURN jsonb_build_object(
    'year', EXTRACT(YEAR FROM v_on)::int,
    'month', to_char(v_on, 'YYYY-MM'),
    'annual', jsonb_build_object('entitlement', v_annual, 'used', r.annual_used, 'pending', r.annual_pending,
                                 'left', v_annual - r.annual_used - r.annual_pending),
    'sick', jsonb_build_object('entitlement', v_sick, 'used', r.sick_used, 'pending', r.sick_pending,
                               'left', v_sick - r.sick_used - r.sick_pending),
    'hourly', (
      SELECT jsonb_build_object(
        'allowance_hours', v_hours,
        'used_hours', COALESCE(SUM(public.leave_request_hours(lr)) FILTER (WHERE lr.status = 'approved'), 0),
        'pending_hours', COALESCE(SUM(public.leave_request_hours(lr)) FILTER (WHERE lr.status = 'pending'), 0),
        'left_hours', v_hours - COALESCE(SUM(public.leave_request_hours(lr)) FILTER (WHERE lr.status IN ('approved', 'pending')), 0))
      FROM leave_requests lr
      WHERE lr.employee_id = v_emp
        AND lr.id IS DISTINCT FROM p_exclude
        AND lr.is_hourly
        AND (lr.start_date AT TIME ZONE v_tz)::date >= v_month_start
        AND (lr.start_date AT TIME ZONE v_tz)::date < (v_month_start + interval '1 month')::date
    )
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_leave_balance(uuid, date, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_leave_balance(uuid, date, uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.get_leave_balance(uuid, date, uuid) IS
'رصيد الإجازات: السنوية والمرضية للسنة، والزمنيات للشهر. الموظف يرى رصيده فقط؛ الأدمن والمدير أي موظف.';

-- الأدمن يخصّص رصيد موظف (فارغ = يرجع للسياسة)
CREATE OR REPLACE FUNCTION public.set_employee_leave_entitlement(
  p_employee_id uuid,
  p_annual numeric,
  p_sick numeric,
  p_hourly_monthly_hours numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin();
  IF COALESCE(p_annual, 0) < 0 OR COALESCE(p_sick, 0) < 0 OR COALESCE(p_hourly_monthly_hours, 0) < 0 THEN
    RAISE EXCEPTION 'الرصيد لا يمكن أن يكون بالسالب.' USING ERRCODE = '22023';
  END IF;
  INSERT INTO leave_balances (employee_id, annual_entitlement, sick_entitlement, hourly_monthly_hours)
  VALUES (p_employee_id, p_annual, p_sick, p_hourly_monthly_hours)
  ON CONFLICT (employee_id) DO UPDATE
  SET annual_entitlement = EXCLUDED.annual_entitlement,
      sick_entitlement = EXCLUDED.sick_entitlement,
      hourly_monthly_hours = EXCLUDED.hourly_monthly_hours,
      updated_at = now();
END;
$$;
REVOKE EXECUTE ON FUNCTION public.set_employee_leave_entitlement(uuid, numeric, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_employee_leave_entitlement(uuid, numeric, numeric, numeric) TO authenticated, service_role;


-- ---------------------------------------------------------------------
-- 6) التحقق عند الطلب والاعتماد
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_leave_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tz text := public.company_timezone();
  v_types jsonb := public.leave_policy() -> 'active_types';
  v_days numeric;
  v_hours numeric;
  v_bal jsonb;
  v_left numeric;
BEGIN
  IF TG_OP = 'UPDATE' AND NOT (NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' AND NEW.status NOT IN ('pending', 'approved') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' AND jsonb_typeof(v_types) = 'array' AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_types) t WHERE t ->> 'id' = NEW.leave_type
  ) THEN
    RAISE EXCEPTION 'نوع الإجازة غير متاح حالياً.' USING ERRCODE = '22023';
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

  v_bal := public.get_leave_balance(NEW.employee_id, (NEW.start_date AT TIME ZONE v_tz)::date, NEW.id);

  IF COALESCE(NEW.is_hourly, false) THEN
    v_hours := public.leave_request_hours(NEW);
    v_left := (v_bal -> 'hourly' ->> 'left_hours')::numeric;
    IF v_hours > v_left THEN
      RAISE EXCEPTION 'رصيد الإجازات الزمنية لهذا الشهر غير كافٍ: المطلوب % ساعة والمتبقي % ساعة.',
        public.fmt_days(v_hours), public.fmt_days(GREATEST(v_left, 0)) USING ERRCODE = '22023';
    END IF;
  ELSE
    v_days := public.leave_request_days(NEW);
    IF v_days = 0 THEN
      RAISE EXCEPTION 'الأيام المختارة كلها عطلة رسمية، لا حاجة لإجازة.' USING ERRCODE = '22023';
    END IF;
    IF NEW.leave_type IN ('annual', 'sick') THEN
      v_left := (v_bal -> NEW.leave_type ->> 'left')::numeric;
      IF v_days > v_left THEN
        RAISE EXCEPTION 'رصيد الإجازة غير كافٍ: المطلوب % يوم والمتبقي % يوم.',
          public.fmt_days(v_days), public.fmt_days(GREATEST(v_left, 0)) USING ERRCODE = '22023';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;
