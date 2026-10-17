-- =====================================================================
-- المرحلة 1 من إصلاحات تدقيق 14/10/2026: صلاحيات مدير الفرع وحدود المبالغ.
-- (BUG-002) المدير يشوف حضور وإجازات ورصيد ومواقع GPS ووقفات ومخالفات موظفي فرعه بس (كان كل الفروع).
-- (BUG-003) المدير يكتب إشعار لموظفي فرعه بس.
-- (BUG-004) حذف المستمسكات للأدمن بس (المدير كان يحذف ملف أي فرع والرابط يبقى مكسور).
-- (BUG-005) الراتب ما ينقرا من جدول الموظفين مباشرة لأي مستخدم: الأدمن (والموظف لراتبه) عن طريق get_employee_pay.
-- (BUG-012) السلفة المعتمدة ما ترجع مرفوضة أو ملغاة (أقساطها كانت توكف).
-- (BUG-014) الموظف يشوف حركاته بعد القرار بس (التأخير ما يظهر قبل الخصم)، بالقراءة المباشرة وبمعاينة «راتبي».
-- (BUG-016) الصورة الشخصية بمجلد صاحبها، والمستمسكات 10MB صور وPDF.
-- (PAY-003) مبلغ القرار: الغياب/التأخير/الخروج المبكر/البصمة الناقصة ≤ أجر يوم، الإضافي ≤ المحسوب، والمدير يقلل بس.
-- (PAY-004) «آخر يوم عمل» محمي: الموظف ما يغيّره.
-- (PAY-005) بعد قرار الإجازة التعديل للأدمن بس؛ المدير يقرر لفرعه ومو لنفسه؛ تعديل إجازة معتمدة يرجع يفحص الرصيد والتداخل.
-- =====================================================================

-- ---------------------------------------------------------------------
-- موظفي فرع المدير (قائمة وحدة تنحسب مرة لكل طلب داخل الصلاحيات). غير المدير = قائمة فارغة.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.managed_employee_ids()
 RETURNS uuid[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(array_agg(t.id), '{}'::uuid[])
  FROM employees me
  JOIN employees t ON t.branch_id = me.branch_id
  WHERE me.id = auth.uid() AND me.role = 'manager' AND me.is_active AND me.branch_id IS NOT NULL;
$function$;
REVOKE ALL ON FUNCTION public.managed_employee_ids() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.managed_employee_ids() TO authenticated;

-- ---------------------------------------------------------------------
-- (BUG-002) قراءة المدير لفرعه بس
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "Employees can view own attendance and managers view all" ON public.attendance;
DROP POLICY IF EXISTS "Attendance readable by owner, admins and branch managers" ON public.attendance;
CREATE POLICY "Attendance readable by owner, admins and branch managers" ON public.attendance
  FOR SELECT TO authenticated
  USING (employee_id = auth.uid() OR (SELECT public.is_admin())
         OR employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[]));

DROP POLICY IF EXISTS "Only admins and managers can update attendance" ON public.attendance;
DROP POLICY IF EXISTS "Admins and branch managers update attendance" ON public.attendance;
CREATE POLICY "Admins and branch managers update attendance" ON public.attendance
  FOR UPDATE TO authenticated
  USING ((SELECT public.is_admin())
         OR (employee_id <> auth.uid() AND employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[])))
  WITH CHECK ((SELECT public.is_admin())
         OR (employee_id <> auth.uid() AND employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[])));

DROP POLICY IF EXISTS "Employees can view own leaves and managers view all" ON public.leave_requests;
DROP POLICY IF EXISTS "Leaves readable by owner, admins and branch managers" ON public.leave_requests;
CREATE POLICY "Leaves readable by owner, admins and branch managers" ON public.leave_requests
  FOR SELECT TO authenticated
  USING (employee_id = auth.uid() OR (SELECT public.is_admin())
         OR employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[]));

DROP POLICY IF EXISTS "Admins and managers can approve or reject leave requests" ON public.leave_requests;
DROP POLICY IF EXISTS "Admins and branch managers decide leave requests" ON public.leave_requests;
CREATE POLICY "Admins and branch managers decide leave requests" ON public.leave_requests
  FOR UPDATE TO authenticated
  USING ((SELECT public.is_admin())
         OR (employee_id <> auth.uid() AND employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[])))
  WITH CHECK ((SELECT public.is_admin())
         OR (employee_id <> auth.uid() AND employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[])));

DROP POLICY IF EXISTS "Employees can view their own leave balance" ON public.leave_balances;
DROP POLICY IF EXISTS "Leave balance readable by owner, admins and branch managers" ON public.leave_balances;
CREATE POLICY "Leave balance readable by owner, admins and branch managers" ON public.leave_balances
  FOR SELECT TO authenticated
  USING (employee_id = auth.uid() OR (SELECT public.is_admin())
         OR employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[]));

DROP POLICY IF EXISTS "Admins and managers can view location tracking" ON public.location_tracking;
DROP POLICY IF EXISTS "Tracking readable by admins and branch managers" ON public.location_tracking;
CREATE POLICY "Tracking readable by admins and branch managers" ON public.location_tracking
  FOR SELECT TO authenticated
  USING ((SELECT public.is_admin()) OR employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[]));

DROP POLICY IF EXISTS "Admins can view stops" ON public.tracked_stops;
DROP POLICY IF EXISTS "Stops readable by admins and branch managers" ON public.tracked_stops;
CREATE POLICY "Stops readable by admins and branch managers" ON public.tracked_stops
  FOR SELECT TO authenticated
  USING ((SELECT public.is_admin()) OR employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[]));

DROP POLICY IF EXISTS "Admins can view violations" ON public.geofence_violations;
DROP POLICY IF EXISTS "Violations readable by admins and branch managers" ON public.geofence_violations;
CREATE POLICY "Violations readable by admins and branch managers" ON public.geofence_violations
  FOR SELECT TO authenticated
  USING ((SELECT public.is_admin()) OR employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[]));

DROP POLICY IF EXISTS "Admins can view mock gps attempts" ON public.mock_gps_attempts;
DROP POLICY IF EXISTS "Mock GPS readable by admins and branch managers" ON public.mock_gps_attempts;
CREATE POLICY "Mock GPS readable by admins and branch managers" ON public.mock_gps_attempts
  FOR SELECT TO authenticated
  USING ((SELECT public.is_admin()) OR employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[]));

DROP POLICY IF EXISTS "Employees view own geofence assignments" ON public.employee_geofence_assignments;
DROP POLICY IF EXISTS "Geofence assignments readable by owner, admins and branch managers" ON public.employee_geofence_assignments;
CREATE POLICY "Geofence assignments readable by owner, admins and branch managers" ON public.employee_geofence_assignments
  FOR SELECT TO authenticated
  USING (employee_id = auth.uid() OR (SELECT public.is_admin())
         OR employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[]));

DROP POLICY IF EXISTS "Employees view own tracking schedule" ON public.tracking_schedules;
DROP POLICY IF EXISTS "Tracking schedule readable by owner, admins and branch managers" ON public.tracking_schedules;
CREATE POLICY "Tracking schedule readable by owner, admins and branch managers" ON public.tracking_schedules
  FOR SELECT TO authenticated
  USING (employee_id = auth.uid() OR (SELECT public.is_admin())
         OR employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[]));

-- رصيد الإجازة وجدول الدوام بالدوال: نفس القاعدة
CREATE OR REPLACE FUNCTION public.get_leave_balance(p_employee_id uuid DEFAULT NULL::uuid, p_on date DEFAULT NULL::date, p_exclude uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  IF auth.uid() IS NOT NULL AND v_emp <> auth.uid()
     AND NOT (public.is_admin() OR v_emp = ANY (public.managed_employee_ids())) THEN
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
$function$;

CREATE OR REPLACE FUNCTION public.get_effective_work_schedule(p_employee_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF work_schedules
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp_id uuid := COALESCE(p_employee_id, auth.uid());
BEGIN
  IF auth.uid() IS NOT NULL AND v_emp_id <> auth.uid()
     AND NOT (public.is_admin() OR v_emp_id = ANY (public.managed_employee_ids())) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT ws.*
  FROM work_schedules ws
  JOIN employees e ON e.id = v_emp_id
  WHERE ws.employee_id = e.id
     OR (ws.employee_id IS NULL AND ws.department_id IS NOT NULL
         AND ws.department_id = e.department_id)
     OR (ws.employee_id IS NULL AND ws.department_id IS NULL
         AND ws.branch_id IS NOT NULL AND ws.branch_id = e.branch_id)
  ORDER BY
    CASE
      WHEN ws.employee_id IS NOT NULL THEN 0
      WHEN ws.department_id IS NOT NULL THEN 1
      ELSE 2
    END,
    ws.created_at DESC
  LIMIT 1;
END;
$function$;

-- ---------------------------------------------------------------------
-- (BUG-003) الإشعارات: المدير لموظفي فرعه بس
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "Insert own notifications or as management" ON public.notifications;
DROP POLICY IF EXISTS "Insert own notifications, admins any, branch managers their branch" ON public.notifications;
CREATE POLICY "Insert own notifications, admins any, branch managers their branch" ON public.notifications
  FOR INSERT TO authenticated
  WITH CHECK (employee_id = auth.uid() OR (SELECT public.is_admin())
              OR employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[]));

CREATE OR REPLACE FUNCTION public.send_idempotent_notification(p_employee_id uuid, p_title text, p_body text, p_type text, p_dedup_window_minutes integer DEFAULT 60)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL
     AND p_employee_id IS DISTINCT FROM auth.uid()
     AND NOT (public.is_admin() OR p_employee_id = ANY (public.managed_employee_ids())) THEN
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
$function$;

-- ---------------------------------------------------------------------
-- (BUG-004 + BUG-016) التخزين
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "Only admins and managers can delete employee-documents" ON storage.objects;
DROP POLICY IF EXISTS "Only admins can delete employee-documents" ON storage.objects;
CREATE POLICY "Only admins can delete employee-documents" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'employee-documents' AND public.is_admin());

DROP POLICY IF EXISTS "Leave attachments visible to owner and managers" ON storage.objects;
DROP POLICY IF EXISTS "Leave attachments visible to owner and branch managers" ON storage.objects;
CREATE POLICY "Leave attachments visible to owner and branch managers" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'employee-documents' AND (storage.foldername(name))[1] = 'leaves'
         AND ((storage.foldername(name))[2] = auth.uid()::text
              OR (storage.foldername(name))[2] = ANY ((SELECT public.managed_employee_ids())::text[])));

DROP POLICY IF EXISTS "Authenticated users can upload avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users upload avatars into their own folder" ON storage.objects;
CREATE POLICY "Users upload avatars into their own folder" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'avatars' AND ((storage.foldername(name))[1] = auth.uid()::text OR public.is_admin()));

UPDATE storage.buckets
SET file_size_limit = 10485760, allowed_mime_types = ARRAY['image/*', 'application/pdf']
WHERE id = 'employee-documents';

-- ---------------------------------------------------------------------
-- (BUG-005) الراتب ما ينقرا مباشرة: صلاحية القراءة لأعمدة الموظف غير أعمدة الراتب (وكلمة السر القديمة).
-- ملاحظة للمطور: أي عمود جديد بجدول الموظفين لازم ينضاف لهذي القائمة حتى ينقرا.
-- ---------------------------------------------------------------------
REVOKE SELECT ON public.employees FROM anon, authenticated;
GRANT SELECT (id, employee_code, full_name, phone, email, avatar_url, is_active, role, department_id, branch_id,
              created_at, must_change_password, device_id_lock, fcm_token, document_urls, join_date, termination_date)
  ON public.employees TO authenticated;

-- صلاحية «الموظف يعدّل سطره» كانت تقرا الراتب حتى تمنع تغييره، فتفشل بعد منع القراءة.
-- الحماية الفعلية للأعمدة (الدور، الفرع، القسم، التفعيل، الراتب، الرمز، المباشرة، آخر يوم عمل، قفل الجهاز)
-- بالفحص protect_employee_columns اللي يرفض برسالة واضحة.
DROP POLICY IF EXISTS "Employees can update their own details (limited)" ON public.employees;
DROP POLICY IF EXISTS "Employees update their own row (columns guarded by trigger)" ON public.employees;
CREATE POLICY "Employees update their own row (columns guarded by trigger)" ON public.employees
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

CREATE OR REPLACE FUNCTION public.get_employee_pay(p_employee_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS TABLE(employee_id uuid, monthly_salary_iqd numeric, future_salary_iqd numeric, future_salary_month text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- الأدمن: رواتب الكل (أو المطلوبين). أي مستخدم ثاني: راتبه هو بس
  SELECT e.id, e.monthly_salary_iqd, e.future_salary_iqd, e.future_salary_month
  FROM employees e
  WHERE (p_employee_ids IS NULL OR e.id = ANY (p_employee_ids))
    AND (public.is_admin() OR e.id = auth.uid());
$function$;
REVOKE ALL ON FUNCTION public.get_employee_pay(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_pay(uuid[]) TO authenticated;

-- ---------------------------------------------------------------------
-- (BUG-014) الموظف يشوف حركاته المقررة (المعتمدة) بس
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "Admins and managers read payroll events" ON public.payroll_events;
DROP POLICY IF EXISTS "Payroll events: admins, own decided, branch managers" ON public.payroll_events;
CREATE POLICY "Payroll events: admins, own decided, branch managers" ON public.payroll_events
  FOR SELECT TO authenticated
  USING ((SELECT public.is_admin())
         OR (employee_id = auth.uid() AND status = 'approved')
         OR (employee_id <> auth.uid() AND employee_id = ANY ((SELECT public.managed_employee_ids())::uuid[])));

CREATE OR REPLACE FUNCTION public.get_my_payroll_preview()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_month text;
  v_p payroll_periods%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;
  v_month := public.payroll_natural_month((now() AT TIME ZONE public.company_timezone())::date);
  IF v_month IS NULL THEN
    RETURN NULL;
  END IF;
  v_p := public.ensure_payroll_period(v_month);
  PERFORM public.sync_payroll_period(v_month, v_me);

  RETURN jsonb_build_object(
    'period', to_jsonb(v_p),
    -- اللي ينتظر قرار الإدارة ما يبين للموظف (قاعدة: التأخير ما يظهر قبل الخصم)
    'summary', public.payroll_employee_summary(v_me, v_month) || jsonb_build_object('pending_count', 0, 'missing_punches', 0),
    'events', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'event_date', pe.event_date, 'event_type', pe.event_type, 'minutes', pe.minutes, 'days', pe.days,
               'amount', pe.amount, 'direction', pe.direction, 'status', pe.status, 'notes', pe.notes,
               'carried_from', pe.carried_from)
             ORDER BY pe.event_date, pe.event_type)
      FROM payroll_events pe
      WHERE pe.employee_id = v_me AND pe.payroll_month = v_month AND pe.status = 'approved'
        AND (pe.amount > 0 OR pe.event_type = 'paid_leave')), '[]'::jsonb)
  );
END;
$function$;

-- ---------------------------------------------------------------------
-- (PAY-004) «آخر يوم عمل» محمي من تعديل الموظف
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_employee_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
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
     OR NEW.termination_date IS DISTINCT FROM OLD.termination_date
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
$function$;

-- ---------------------------------------------------------------------
-- (PAY-005) الإجازات: بعد القرار التعديل للأدمن بس، والمدير لفرعه ومو لنفسه
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_leave_decisions()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.employee_id = auth.uid()
       AND (NEW.start_date AT TIME ZONE public.company_timezone())::date < v_today - 30 THEN
      RAISE EXCEPTION 'لا يمكن طلب إجازة لتاريخ مضى عليه أكثر من 30 يوماً. راجع الإدارة.' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
  END IF;

  -- صاحب الطلب (موظف أو مدير): يلغي طلبه المعلّق بس
  IF OLD.employee_id = auth.uid() OR NEW.employee_id = auth.uid() THEN
    IF OLD.status = 'pending' AND NEW.status = 'cancelled' AND NEW.employee_id = OLD.employee_id THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'لا يمكنك اعتماد أو رفض أو تعديل طلب إجازتك.' USING ERRCODE = '42501';
  END IF;

  -- مدير الفرع: يقرر على طلبات فرعه المعلّقة بس
  IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
     OR NOT (OLD.employee_id = ANY (public.managed_employee_ids())) THEN
    RAISE EXCEPTION 'غير مصرح: الموظف من فرع آخر.' USING ERRCODE = '42501';
  END IF;
  IF OLD.status <> 'pending' THEN
    RAISE EXCEPTION 'الإجازة انقررت. تعديلها بعد القرار من مسؤول النظام (الأدمن) فقط.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.validate_leave_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tz text := public.company_timezone();
  v_types jsonb := public.leave_policy() -> 'active_types';
  v_days numeric;
  v_hours numeric;
  v_bal jsonb;
  v_left numeric;
BEGIN
  -- يتفحص: طلب جديد، أو اعتماد، أو تعديل تواريخ/نوع إجازة معتمدة (كان التعديل بعد الاعتماد يتخطى الرصيد والتداخل)
  IF TG_OP = 'UPDATE' AND NOT (
       (NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved')
       OR (NEW.status = 'approved' AND (
             NEW.start_date IS DISTINCT FROM OLD.start_date OR NEW.end_date IS DISTINCT FROM OLD.end_date
             OR NEW.leave_type IS DISTINCT FROM OLD.leave_type OR NEW.is_hourly IS DISTINCT FROM OLD.is_hourly
             OR NEW.start_hour IS DISTINCT FROM OLD.start_hour OR NEW.end_hour IS DISTINCT FROM OLD.end_hour))) THEN
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
$function$;

-- ---------------------------------------------------------------------
-- (BUG-012) السلفة المعتمدة ما ترجع مرفوضة أو ملغاة
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_loan_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.status = 'approved' AND NEW.status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'السلفة معتمدة: ما ترجع طلب ولا تنرفض ولا تنلغي. إذا بيها غلط عدّلها، وإذا انسددت تتأرشف.'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_guard_loan_status ON public.loans;
CREATE TRIGGER trg_guard_loan_status BEFORE UPDATE OF status ON public.loans
  FOR EACH ROW EXECUTE FUNCTION public.guard_loan_status();

-- ---------------------------------------------------------------------
-- (PAY-003) حدود المبلغ اللي ينكتب بالقرار
-- ---------------------------------------------------------------------
-- المبلغ اللي يحسبه المحرّك للحركة من دقائقها وأجورها (بدون أي تعديل من الإدارة)
CREATE OR REPLACE FUNCTION public._payroll_event_computed_amount(e payroll_events)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT round(CASE e.event_type
    WHEN 'absence' THEN d.daily * GREATEST(e.days, 1)
    WHEN 'late' THEN LEAST(e.minutes * COALESCE(e.minute_rate, 0), d.daily)
    WHEN 'overtime' THEN e.minutes * COALESCE(e.minute_rate, 0)
                         * COALESCE((public.payroll_policy() ->> 'overtime_multiplier')::numeric, 1)
    ELSE e.minutes * COALESCE(e.minute_rate, 0)
  END, 2)
  FROM (SELECT COALESCE(e.daily_rate, public.payroll_daily_rate(e.employee_id, e.payroll_month)) AS daily) d;
$function$;
REVOKE ALL ON FUNCTION public._payroll_event_computed_amount(payroll_events) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.decide_payroll_event(p_event_id uuid, p_approve boolean, p_reason text DEFAULT NULL::text, p_amount numeric DEFAULT NULL::numeric)
 RETURNS payroll_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  e payroll_events%ROWTYPE;
  v_att_id uuid;
  v_branch uuid;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'ignored' END;
  v_labels jsonb := '{"absence":"غياب","late":"تأخير","early_leave":"خروج مبكر","missing_punch":"بدون بصمة انصراف","overtime":"ساعات إضافية"}';
  -- المبلغ اللي كتبه الأدمن (بس عند الخصم/الاعتماد). NULL = المبلغ المحسوب
  v_amount numeric := CASE WHEN p_approve AND p_amount IS NOT NULL THEN round(p_amount, 2) END;
  v_salary numeric;
  v_final numeric;
  v_had_override boolean;
  v_computed numeric;
  v_daily numeric;
  v_cap numeric;
BEGIN
  PERFORM public.require_admin_or_manager();
  SELECT * INTO e FROM payroll_events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND OR e.status = 'void' THEN
    RAISE EXCEPTION 'الحركة غير موجودة.' USING ERRCODE = 'P0002';
  END IF;
  IF NOT public.is_admin() THEN
    IF e.employee_id = auth.uid() THEN
      RAISE EXCEPTION 'لا يمكنك اتخاذ قرار على حركاتك الخاصة.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.payroll_same_branch(e.employee_id) THEN
      RAISE EXCEPTION 'غير مصرح: الموظف من فرع آخر.' USING ERRCODE = '42501';
    END IF;
  END IF;
  IF e.event_type NOT IN ('absence', 'late', 'early_leave', 'missing_punch', 'overtime') THEN
    RAISE EXCEPTION 'هذه الحركة لا تحتاج قراراً.' USING ERRCODE = '22023';
  END IF;
  IF v_amount IS NOT NULL THEN
    IF v_amount < 0 THEN
      RAISE EXCEPTION 'المبلغ لازم يكون صفر أو أكثر.' USING ERRCODE = '22023';
    END IF;
    -- حماية من غلطة كتابة (صفر زايد): مبلغ حركة وحدة ما يتجاوز الراتب الشهري
    v_salary := public.payroll_basic_salary(e.employee_id, e.payroll_month);
    IF v_salary > 0 AND v_amount > v_salary THEN
      RAISE EXCEPTION 'المبلغ (%) أكبر من راتب الموظف الشهري (%).', to_char(v_amount, 'FM999,999,999'), to_char(v_salary, 'FM999,999,999')
        USING ERRCODE = '22023';
    END IF;
    -- الحد حسب النوع: الخصم ≤ أجر يوم (العقوبة الأكبر = «خصم يدوي» بسبب)، الإضافي ≤ المحسوب (الأكثر = «مكافأة»).
    -- المدير يقلل المبلغ المحسوب بس، ما يزيده.
    v_computed := public._payroll_event_computed_amount(e);
    v_daily := round(COALESCE(e.daily_rate, public.payroll_daily_rate(e.employee_id, e.payroll_month)) * GREATEST(e.days, 1), 2);
    v_cap := CASE WHEN e.event_type = 'overtime' THEN v_computed ELSE v_daily END;
    IF NOT public.is_admin() THEN
      IF v_amount > v_computed THEN
        RAISE EXCEPTION 'مدير الفرع يكدر يقلل المبلغ بس: المحسوب % د.ع.', to_char(v_computed, 'FM999,999,990')
          USING ERRCODE = '42501';
      END IF;
    ELSIF v_amount > v_cap THEN
      IF e.event_type = 'overtime' THEN
        RAISE EXCEPTION 'مبلغ الإضافي ما يتجاوز المحسوب (% د.ع). للمبلغ الأكبر سجّل «مكافأة» بسبب واضح.',
          to_char(v_cap, 'FM999,999,990') USING ERRCODE = '22023';
      END IF;
      RAISE EXCEPTION 'خصم % ما يتجاوز أجر يوم واحد (% د.ع). للعقوبة الأكبر سجّل «خصم يدوي» بسبب واضح.',
        COALESCE(v_labels ->> e.event_type, ''), to_char(v_cap, 'FM999,999,990') USING ERRCODE = '22023';
    END IF;
  END IF;

  -- الغياب والتأخير قرارهما محفوظ في سجل الحضور أيضاً (للتوافق مع الشاشات)
  IF e.event_type IN ('absence', 'late') THEN
    IF e.source = 'no_record' THEN
      -- موظف بدون فرع: نسجل اليوم بفرع اللي قرر (أو أول فرع) بدل ما يعلق القرار
      SELECT COALESCE(
        (SELECT branch_id FROM employees WHERE id = e.employee_id),
        (SELECT branch_id FROM employees WHERE id = auth.uid()),
        (SELECT id FROM branches ORDER BY created_at LIMIT 1)) INTO v_branch;
      IF v_branch IS NULL THEN
        RAISE EXCEPTION 'ماكو أي فرع بالنظام. أضف فرعاً أولاً.' USING ERRCODE = '22023';
      END IF;
      INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status, deduction_reason)
      VALUES (e.employee_id, v_branch, e.event_date, 'absent', CASE WHEN p_approve THEN 'applied' ELSE 'ignored' END, p_reason)
      RETURNING id INTO v_att_id;
    ELSE
      UPDATE attendance
      SET deduction_status = CASE WHEN p_approve THEN 'applied' ELSE 'ignored' END,
          deduction_applied = p_approve,
          deduction_reason = COALESCE(NULLIF(btrim(p_reason), ''), deduction_reason)
      WHERE id = e.source_id;
    END IF;
    SELECT * INTO e FROM payroll_events
    WHERE employee_id = e.employee_id AND event_date = e.event_date AND event_type = e.event_type
      AND status <> 'void' ORDER BY updated_at DESC LIMIT 1;
  END IF;

  v_had_override := e.amount_override IS NOT NULL;
  IF e.salary_slip_id IS NULL THEN
    UPDATE payroll_events
    SET status = v_status, decision_reason = NULLIF(btrim(p_reason), ''), decided_by = auth.uid(), decided_at = now(),
        amount_override = v_amount,
        amount = COALESCE(v_amount,
                          -- رجوع للمحسوب بعد مبلغ معدّل على بصمة ناقصة (الباقي يرجّعه إعادة الحساب تحت)
                          CASE WHEN e.amount_override IS NOT NULL AND e.event_type = 'missing_punch'
                               THEN round(e.minutes * COALESCE(e.minute_rate, 0), 2) ELSE amount END),
        -- بصمة ناقصة كانت «تأكيد بدون مبلغ» وانكتب إلها مبلغ = خصم
        direction = CASE WHEN v_amount > 0 AND direction = 0 THEN -1 ELSE direction END,
        payroll_month = CASE
          WHEN EXISTS (SELECT 1 FROM payroll_periods WHERE period_month = e.payroll_month AND status = 'open')
               AND NOT EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = e.employee_id AND work_month = e.payroll_month)
            THEN e.payroll_month
          ELSE public.payroll_target_month(e.employee_id, e.payroll_month) END,
        updated_at = now()
    WHERE id = e.id
    RETURNING * INTO e;
    -- انمسح مبلغ معدّل سابق: نرجع للمبلغ المحسوب من الدوام
    IF v_had_override AND v_amount IS NULL AND p_approve AND e.event_type <> 'missing_punch' THEN
      PERFORM public.sync_payroll_day(e.employee_id, e.event_date);
      SELECT * INTO e FROM payroll_events WHERE id = e.id;
    END IF;
    v_final := e.amount;
  ELSE
    -- داخل كشف معتمد: الحركة ما تتغير، والفرق يصير تسوية بأول مسير مفتوح
    UPDATE payroll_events SET decision_reason = NULLIF(btrim(p_reason), ''), decided_by = auth.uid(), decided_at = now(),
                              amount_override = v_amount
    WHERE id = e.id;
    v_final := COALESCE(v_amount, e.amount);
    PERFORM public._payroll_settle(e, CASE WHEN p_approve THEN e.direction * v_final ELSE 0 END);
  END IF;

  -- إشعار للموظف بالخصم أو باعتماد الإضافي فقط. الإعفاء (مثل: نسي البصمة وهو مداوم) بدون إشعار:
  -- الموظف ما تبلّغ بالتأخير أصلاً، والملاحظة تبقى محفوظة بالقرار (decision_reason)
  IF p_approve AND (e.event_type <> 'missing_punch' OR v_final > 0) THEN
    INSERT INTO notifications (employee_id, title, body, type)
    VALUES (e.employee_id,
            CASE WHEN p_approve AND e.direction < 0 THEN 'إشعار بخصم ⚠️'
                 WHEN p_approve THEN 'اعتماد ساعات إضافية ✅'
                 ELSE 'إعفاء من الخصم 🎉' END,
            format('%s ليوم %s%s%s',
                   CASE WHEN p_approve AND e.direction < 0 THEN 'تم تطبيق خصم ' || COALESCE(v_labels ->> e.event_type, '')
                        WHEN p_approve THEN 'تم اعتماد ساعات إضافية'
                        ELSE 'تم إعفاؤك من خصم ' || COALESCE(v_labels ->> e.event_type, '') END,
                   e.event_date,
                   CASE WHEN p_approve AND v_final > 0 THEN format(' بمبلغ %s د.ع', to_char(v_final, 'FM999,999,999')) ELSE '' END,
                   CASE WHEN NULLIF(btrim(p_reason), '') IS NOT NULL THEN '. السبب: ' || btrim(p_reason) ELSE '' END),
            'attendance');
  END IF;
  RETURN e;
END;
$function$;

-- ---------------------------------------------------------------------
-- (BUG-005) فحص مبلغ الخصم اليدوي يقرا الراتب: يشتغل بصلاحية المالك بعد ما انمنعت قراءة الراتب المباشرة
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_bonus_deduction_amount()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_salary numeric;
BEGIN
  SELECT monthly_salary_iqd INTO v_salary FROM employees WHERE id = NEW.employee_id;
  IF NEW.type = 'deduction' AND COALESCE(v_salary, 0) > 0 AND NEW.amount > v_salary THEN
    RAISE EXCEPTION 'مبلغ الخصم (% د.ع) أكبر من راتب الموظف الشهري (% د.ع). تأكد من المبلغ.',
      to_char(NEW.amount, 'FM999,999,999,999'), to_char(v_salary, 'FM999,999,999') USING ERRCODE = '22023';
  END IF;
  IF NEW.amount > 100000000 THEN
    RAISE EXCEPTION 'المبلغ كبير جداً (أكثر من 100,000,000 د.ع). تأكد من المبلغ.' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$function$;
