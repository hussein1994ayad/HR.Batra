-- =====================================================================
-- المرحلة 4 من إصلاحات تدقيق 14/10/2026: تاريخ الموظف (قرارات صاحب الشركة 15/10/2026).
-- (PAY-002) نقل الموظف لفرع/قسم ثاني كان يعيد حساب أيامه القديمة على دوام الفرع الجديد (تأخير وخروج مبكر غلط).
--   هسه كل تغيير فرع/قسم ينحفظ بتاريخه ويسري من يوم التغيير، وكل يوم ينحسب على دوام فرعه وقسمه بذاك اليوم.
-- (PAY-009) التفعيل بعد الترك كان يمسح آخر يوم عمل بدون تاريخ رجوع، فأيام الانقطاع تطلع غياب والراتب كامل.
--   هسه ينحفظ «تاريخ الرجوع» (reactivate_employee؛ التفعيل العادي = اليوم)، وأيام الانقطاع ما تطلع غياب،
--   والراتب ناقص أجرها مثل الأيام قبل المباشرة.
-- (FEATURE-001) سجل الموظف: باشر، انتقل، ترك، رجع (get_employee_history).
-- الكشوف المعتمدة ما تتغير.
-- =====================================================================

-- ---------------------------------------------------------------------
-- تاريخ الفرع والقسم
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.employee_assignment_history (
  id bigserial PRIMARY KEY,
  employee_id uuid NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  -- بدون مفتاح أجنبي: السجل يبقى حتى لو انحذف الفرع أو القسم
  branch_id uuid,
  department_id uuid,
  effective_from date NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  recorded_by uuid
);
CREATE INDEX IF NOT EXISTS idx_employee_assignment_history_lookup
  ON public.employee_assignment_history (employee_id, effective_from DESC, recorded_at DESC, id DESC);
ALTER TABLE public.employee_assignment_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS employee_assignment_history_admin_read ON public.employee_assignment_history;
CREATE POLICY employee_assignment_history_admin_read ON public.employee_assignment_history
  FOR SELECT TO authenticated USING ((SELECT public.is_admin()));
REVOKE INSERT, UPDATE, DELETE ON public.employee_assignment_history FROM anon, authenticated;

-- الموجودين: فرعهم وقسمهم الحالي من البداية (ماكو تاريخ قبل هذا التحديث، فحساب الأيام ما يتغير)
INSERT INTO public.employee_assignment_history (employee_id, branch_id, department_id, effective_from)
SELECT e.id, e.branch_id, e.department_id, DATE '1900-01-01'
FROM public.employees e
WHERE NOT EXISTS (SELECT 1 FROM public.employee_assignment_history h WHERE h.employee_id = e.id);

-- ---------------------------------------------------------------------
-- فترات الانقطاع (ترك ورجع): الأيام بين آخر يوم عمل ويوم الرجوع
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.employee_service_breaks (
  id bigserial PRIMARY KEY,
  employee_id uuid NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  last_day date NOT NULL,
  return_date date NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  recorded_by uuid,
  CONSTRAINT employee_service_breaks_dates CHECK (return_date > last_day + 1)
);
CREATE INDEX IF NOT EXISTS idx_employee_service_breaks_emp ON public.employee_service_breaks (employee_id, last_day);
ALTER TABLE public.employee_service_breaks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS employee_service_breaks_admin_read ON public.employee_service_breaks;
CREATE POLICY employee_service_breaks_admin_read ON public.employee_service_breaks
  FOR SELECT TO authenticated USING ((SELECT public.is_admin()));
REVOKE INSERT, UPDATE, DELETE ON public.employee_service_breaks FROM anon, authenticated;

-- ---------------------------------------------------------------------
-- فرع وقسم الموظف بيوم معيّن، وهل جان بالخدمة ذاك اليوم
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.employee_assignment_at(p_employee_id uuid, p_date date)
 RETURNS TABLE(branch_id uuid, department_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT x.branch_id, x.department_id FROM (
    (SELECT h.branch_id, h.department_id, 0 AS pri
     FROM employee_assignment_history h
     WHERE h.employee_id = p_employee_id AND h.effective_from <= p_date
     ORDER BY h.effective_from DESC, h.recorded_at DESC, h.id DESC
     LIMIT 1)
    UNION ALL
    (SELECT e.branch_id, e.department_id, 1 FROM employees e WHERE e.id = p_employee_id)
  ) x
  ORDER BY x.pri
  LIMIT 1;
$function$;
REVOKE ALL ON FUNCTION public.employee_assignment_at(uuid, date) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.employee_in_service(p_employee_id uuid, p_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((
    SELECT (e.join_date IS NULL OR p_date >= e.join_date)
       AND (e.termination_date IS NULL OR p_date <= e.termination_date)
       AND NOT EXISTS (SELECT 1 FROM employee_service_breaks b
                       WHERE b.employee_id = e.id AND p_date > b.last_day AND p_date < b.return_date)
    FROM employees e WHERE e.id = p_employee_id), false);
$function$;
REVOKE ALL ON FUNCTION public.employee_in_service(uuid, date) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- (PAY-002) جدول دوام اليوم من فرع وقسم الموظف بذاك اليوم (مو الحاليين)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_schedule_at(p_employee_id uuid, p_date date)
 RETURNS work_schedules
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  h record;
  r work_schedules%ROWTYPE;
  v_branch uuid;
  v_dept uuid;
BEGIN
  SELECT a.branch_id, a.department_id INTO v_branch, v_dept FROM public.employee_assignment_at(p_employee_id, p_date) a;
  SELECT x.* INTO h
  FROM (
    SELECT DISTINCT ON (wh.schedule_id) wh.*
    FROM work_schedule_history wh
    WHERE wh.effective_from <= p_date
    ORDER BY wh.schedule_id, wh.effective_from DESC, wh.recorded_at DESC
  ) x
  WHERE NOT x.removed
    AND (x.employee_id = p_employee_id
     OR (x.employee_id IS NULL AND x.department_id IS NOT NULL AND x.department_id = v_dept)
     OR (x.employee_id IS NULL AND x.department_id IS NULL AND x.branch_id IS NOT NULL AND x.branch_id = v_branch))
  ORDER BY CASE WHEN x.employee_id IS NOT NULL THEN 0 WHEN x.department_id IS NOT NULL THEN 1 ELSE 2 END,
           x.schedule_created_at DESC
  LIMIT 1;
  IF FOUND THEN
    r.id := h.schedule_id;
    r.employee_id := h.employee_id;
    r.department_id := h.department_id;
    r.branch_id := h.branch_id;
    r.check_in_time := h.check_in_time;
    r.check_out_time := h.check_out_time;
    r.grace_period_minutes := h.grace_period_minutes;
    r.work_days := h.work_days;
    r.created_at := h.schedule_created_at;
  END IF;
  RETURN r;
END;
$function$;

-- ---------------------------------------------------------------------
-- كل تغيير فرع/قسم ينحفظ ويسري من يوم التغيير (قرار 15/10/2026)، وحساب اليوم يتحدث
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_employee_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO employee_assignment_history (employee_id, branch_id, department_id, effective_from, recorded_by)
    VALUES (NEW.id, NEW.branch_id, NEW.department_id, DATE '1900-01-01', auth.uid());
    RETURN NULL;
  END IF;
  IF NEW.branch_id IS NOT DISTINCT FROM OLD.branch_id AND NEW.department_id IS NOT DISTINCT FROM OLD.department_id THEN
    RETURN NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM employee_assignment_history WHERE employee_id = NEW.id) THEN
    INSERT INTO employee_assignment_history (employee_id, branch_id, department_id, effective_from)
    VALUES (NEW.id, OLD.branch_id, OLD.department_id, DATE '1900-01-01');
  END IF;
  INSERT INTO employee_assignment_history (employee_id, branch_id, department_id, effective_from, recorded_by)
  VALUES (NEW.id, NEW.branch_id, NEW.department_id, v_today, auth.uid());
  PERFORM public.sync_payroll_day(NEW.id, v_today);
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_record_employee_assignment ON public.employees;
CREATE TRIGGER trg_record_employee_assignment AFTER INSERT OR UPDATE OF branch_id, department_id ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.record_employee_assignment();

-- ---------------------------------------------------------------------
-- حساب اليوم: بس أيام الخدمة (بدون فترات الانقطاع)، والجدول من فرع/قسم ذاك اليوم (payroll_schedule_at فوق)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_payroll_day(p_employee_id uuid, p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_natural text;
  v_emp employees%ROWTYPE;
  v_sched work_schedules%ROWTYPE;
  v_has_sched boolean;
  v_att attendance%ROWTYPE;
  v_has_att boolean;
  v_leave leave_requests%ROWTYPE;
  v_policy jsonb := public.payroll_policy();
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_daily numeric;
  v_minute numeric;
  v_workday boolean;
  v_grace int;
  v_mins numeric;
  v_status text;
  d record;
  e payroll_events%ROWTYPE;
  v_target text;
  v_desired_signed numeric;
  v_current_signed numeric;
  v_legacy uuid;
  v_full_leave leave_requests%ROWTYPE;
  v_has_full_leave boolean;
  v_whole_day boolean := false;
  v_last timestamptz;
BEGIN
  IF current_setting('payroll.skip_sync', true) = 'on' THEN RETURN; END IF;
  -- يوم انحذف حضوره بعد إغلاق مسيره (أرشفة/تنظيف): حركاته المعتمدة هي التاريخ، ما ينعاد حسابه
  -- (كان يعتبر الخصم «ماله أصل» ويرجّعه للموظف كتسوية بالمسير المفتوح)
  IF public.payroll_day_frozen(p_date) THEN RETURN; END IF;

  v_natural := public.payroll_natural_month(p_date);
  IF v_natural IS NULL THEN RETURN; END IF;         -- قبل أول مسير: كشوف قديمة

  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  IF NOT FOUND THEN RETURN; END IF;

  v_sched := public.payroll_schedule_at(p_employee_id, p_date);  -- الجدول الساري بذلك اليوم
  v_has_sched := v_sched.id IS NOT NULL;
  v_daily := public.payroll_daily_rate(p_employee_id, v_natural);
  v_minute := v_daily / public.payroll_shift_minutes_at(p_employee_id, p_date);
  v_grace := COALESCE(v_sched.grace_period_minutes, 15);
  v_workday := EXTRACT(DOW FROM p_date)::int = ANY (COALESCE(v_sched.work_days, ARRAY[0, 1, 2, 3, 4, 6]))
               AND NOT EXISTS (SELECT 1 FROM official_holidays WHERE holiday_date = p_date); -- العطلة الرسمية ليست يوم دوام

  -- الحركات المطلوبة لهذا اليوم (جدول مؤقت داخل الاستدعاء)
  CREATE TEMP TABLE IF NOT EXISTS _pd (
    event_type text, source text, source_id uuid, minutes numeric, days numeric,
    amount numeric, direction smallint, status_hint text, notes text
  ) ON COMMIT DROP;
  DELETE FROM _pd WHERE true; -- Supabase (pg_safeupdate) يرفض DELETE بدون WHERE

  -- الموظف لم يباشر بعد أو انتهت خدمته أو بفترة انقطاع (ترك ورجع): لا حركات لهذا اليوم
  IF NOT public.employee_in_service(p_employee_id, p_date) THEN
    NULL;
  ELSE
    SELECT * INTO v_att FROM attendance WHERE employee_id = p_employee_id AND work_date = p_date LIMIT 1;
    v_has_att := FOUND;

    SELECT * INTO v_full_leave FROM leave_requests
    WHERE employee_id = p_employee_id AND status = 'approved' AND NOT COALESCE(is_hourly, false)
      AND p_date BETWEEN (start_date AT TIME ZONE public.company_timezone())::date
                     AND (end_date AT TIME ZONE public.company_timezone())::date
    LIMIT 1;
    v_has_full_leave := FOUND;

    -- يوم مسجّل غياب ثم اعتُمدت له إجازة يومية: الإجازة هي التي تُحتسب (لا خصم غياب)
    IF v_has_att AND NOT (v_att.status = 'absent' AND v_has_full_leave) THEN
      v_status := CASE v_att.deduction_status WHEN 'applied' THEN 'approved' WHEN 'ignored' THEN 'ignored' ELSE 'pending' END;

      IF v_att.status = 'absent' THEN
        -- يوم عطلة (رسمية أو أسبوعية) ما بيه غياب، حتى لو كان مسجّلاً قبل إعلان العطلة
        IF v_workday THEN
          INSERT INTO _pd VALUES ('absence', 'attendance', v_att.id, 0, 1, round(v_daily, 2), -1, v_status,
                                  COALESCE(v_att.deduction_reason, 'غياب'));
        END IF;
      ELSE
        -- بصمة ناقصة: لا خصم تلقائي، تنتظر قرار الإدارة (قد يكون نسياناً)
        IF v_att.check_in_time IS NULL AND v_att.check_out_time IS NOT NULL THEN
          INSERT INTO _pd VALUES ('missing_punch', 'attendance', v_att.id, 0, 0, 0, 0, NULL, 'انصراف بدون بصمة حضور');
        ELSIF v_att.check_in_time IS NOT NULL AND v_att.check_out_time IS NULL AND p_date < v_today
              -- إجازة زمنية معتمدة تشمل آخر دقيقة من الدوام = ما يحتاج بصمة انصراف
              AND NOT (v_has_sched AND v_sched.check_out_time IS NOT NULL
                       AND public.payroll_hourly_leave_overlap(p_employee_id, p_date,
                             public.payroll_time_minutes(v_sched.check_out_time) - 1,
                             public.payroll_time_minutes(v_sched.check_out_time)) > 0) THEN
          -- آخر تواجد مسجّل (آخر نقطة تتبع بنفس اليوم بعد البصمة، وإلا وقت بصمة الحضور) ← دقائق الدوام الباقية خصم مقترح.
          -- ما ينخصم تلقائياً: الأدمن يقرر (خصم، أو إعفاء إذا نسي البصمة وهو مداوم)
          v_last := GREATEST(v_att.check_in_time, COALESCE((
            SELECT max(lt."timestamp") FROM location_tracking lt
            WHERE lt.employee_id = p_employee_id AND lt."timestamp" >= v_att.check_in_time
              AND (lt."timestamp" AT TIME ZONE public.company_timezone())::date = p_date), v_att.check_in_time));
          v_mins := 0;
          IF v_workday AND v_has_sched AND v_sched.check_out_time IS NOT NULL THEN
            v_mins := floor(public.payroll_time_minutes(v_sched.check_out_time) - public.payroll_local_minutes(v_last))
                      - public.payroll_hourly_leave_overlap(p_employee_id, p_date, public.payroll_local_minutes(v_last),
                                                           public.payroll_time_minutes(v_sched.check_out_time));
          END IF;
          IF v_mins > v_grace THEN
            INSERT INTO _pd VALUES ('missing_punch', 'attendance', v_att.id, v_mins, 0, round(v_mins * v_minute, 2), -1, NULL,
                                    format('بدون بصمة انصراف — آخر تواجد مسجّل %s%s (خصم مقترح %s دقيقة)',
                                           to_char(v_last AT TIME ZONE public.company_timezone(), 'HH24:MI'),
                                           CASE WHEN v_last = v_att.check_in_time THEN ' وقت بصمة الحضور' ELSE '' END, v_mins));
          ELSE
            INSERT INTO _pd VALUES ('missing_punch', 'attendance', v_att.id, 0, 0, 0, 0, NULL, 'حضور بدون بصمة انصراف');
          END IF;
        END IF;

        -- التأخير: من بداية الدوام، إذا تجاوز فترة السماح (بأيام الدوام فقط — الجمعة والعطلة ما بيها تأخير)
        IF v_workday AND v_att.check_in_time IS NOT NULL AND v_has_sched AND v_sched.check_in_time IS NOT NULL THEN
          v_mins := floor(public.payroll_local_minutes(v_att.check_in_time) - public.payroll_time_minutes(v_sched.check_in_time))
                    - public.payroll_hourly_leave_overlap(p_employee_id, p_date, public.payroll_time_minutes(v_sched.check_in_time),
                                                         public.payroll_local_minutes(v_att.check_in_time));
          IF v_mins > v_grace OR (v_att.status = 'late' AND v_mins > 0) THEN
            -- خصم التأخير ما يتجاوز أجر يوم واحد (مثل الغياب): بصمة بعد نهاية الدوام كانت تطلع «تأخير 13 ساعة» بأجر أكثر من يومين
            INSERT INTO _pd VALUES ('late', 'attendance', v_att.id, v_mins, 0, LEAST(round(v_mins * v_minute, 2), round(v_daily, 2)), -1, v_status,
                                    format('تأخير %s دقيقة', v_mins)
                                    || CASE WHEN round(v_mins * v_minute, 2) > round(v_daily, 2) THEN ' (الخصم محدد بأجر يوم واحد)' ELSE '' END);
          END IF;
        END IF;

        IF v_att.check_out_time IS NOT NULL AND v_has_sched AND v_sched.check_out_time IS NOT NULL THEN
          -- الخروج المبكر بالدقائق (ينتظر قرار الإدارة)
          v_mins := floor(public.payroll_time_minutes(v_sched.check_out_time) - public.payroll_local_minutes(v_att.check_out_time))
                    - public.payroll_hourly_leave_overlap(p_employee_id, p_date, public.payroll_local_minutes(v_att.check_out_time),
                                                         public.payroll_time_minutes(v_sched.check_out_time));
          IF v_workday AND v_mins > v_grace THEN  -- الخروج المبكر بأيام الدوام فقط
            INSERT INTO _pd VALUES ('early_leave', 'attendance', v_att.id, v_mins, 0, round(v_mins * v_minute, 2), -1, NULL,
                                    format('خروج مبكر %s دقيقة', v_mins));
          END IF;

          -- الساعات الإضافية (إن فُعّلت من الإعدادات) وتحتاج موافقة
          IF COALESCE((v_policy ->> 'overtime_enabled')::boolean, false) THEN
            v_mins := floor(public.payroll_local_minutes(v_att.check_out_time) - public.payroll_time_minutes(v_sched.check_out_time));
            IF v_mins >= COALESCE((v_policy ->> 'overtime_min_minutes')::int, 30) THEN
              INSERT INTO _pd VALUES ('overtime', 'attendance', v_att.id, v_mins, 0,
                                      round(v_mins * v_minute * COALESCE((v_policy ->> 'overtime_multiplier')::numeric, 1), 2), 1, NULL,
                                      format('ساعات إضافية %s دقيقة', v_mins));
            END IF;
          END IF;
        END IF;
      END IF;
    ELSE
      -- إجازة يومية معتمدة تغطي اليوم
      SELECT * INTO v_leave FROM leave_requests
      WHERE employee_id = p_employee_id AND status = 'approved' AND NOT COALESCE(is_hourly, false)
        AND p_date BETWEEN (start_date AT TIME ZONE public.company_timezone())::date
                       AND (end_date AT TIME ZONE public.company_timezone())::date
      ORDER BY created_at LIMIT 1;

      IF FOUND AND v_workday THEN
        IF v_leave.is_paid THEN
          INSERT INTO _pd VALUES ('paid_leave', 'leave', v_leave.id, 0, 1, 0, 0, 'approved', 'إجازة مدفوعة');
        ELSE
          INSERT INTO _pd VALUES ('unpaid_leave', 'leave', v_leave.id, 0, 1, round(v_daily, 2), -1, 'approved', 'إجازة بدون راتب');
        END IF;
      ELSIF NOT FOUND AND v_workday AND p_date < v_today
            AND p_date >= COALESCE((v_policy ->> 'no_record_from')::date, '-infinity'::date) THEN
        -- يوم عمل بلا بصمة ولا إجازة: غياب ينتظر قرار الإدارة (لا يُخصم تلقائياً)
        INSERT INTO _pd VALUES ('absence', 'no_record', NULL, 0, 1, round(v_daily, 2), -1, 'pending', 'يوم عمل بدون بصمة ولا إجازة');
      END IF;
    END IF;

    -- الإجازات الزمنية المعتمدة في هذا اليوم.
    -- يوم غياب كامل معتمد (انخصم) أو إجازة يومية = اليوم كله محسوب، فالإذن الزمني ما يُحسب فوقه (كان يُخصم مرتين).
    -- الغياب المعلّق أو المعفى: الإذن يبقى محسوباً لحد ما تقرر الإدارة
    v_whole_day := EXISTS (SELECT 1 FROM _pd WHERE event_type IN ('absence', 'paid_leave', 'unpaid_leave') AND days >= 1
                             AND status_hint = 'approved');
    FOR v_leave IN
      SELECT * FROM leave_requests
      WHERE employee_id = p_employee_id AND status = 'approved' AND COALESCE(is_hourly, false)
        AND (start_date AT TIME ZONE public.company_timezone())::date = p_date
    LOOP
      CONTINUE WHEN v_whole_day;
      v_mins := GREATEST(round(EXTRACT(EPOCH FROM COALESCE(v_leave.end_hour - v_leave.start_hour, v_leave.end_date - v_leave.start_date)) / 60), 0);
      IF v_leave.is_paid THEN
        INSERT INTO _pd VALUES ('paid_leave', 'leave', v_leave.id, v_mins, 0, 0, 0, 'approved', 'إجازة زمنية مدفوعة');
      ELSE
        INSERT INTO _pd VALUES ('unpaid_leave', 'leave', v_leave.id, v_mins, 0, round(v_mins * v_minute, 2), -1, 'approved', 'إجازة زمنية بدون راتب');
      END IF;
    END LOOP;
  END IF;

  -- (أ) حركات سابقة لم تعد مطلوبة: تُلغى (أو تُعكس إن كانت داخل كشف معتمد)
  FOR e IN
    SELECT pe.* FROM payroll_events pe
    WHERE pe.employee_id = p_employee_id AND pe.event_date = p_date
      AND pe.source IN ('attendance', 'no_record', 'leave') AND pe.status <> 'void'
      AND NOT EXISTS (SELECT 1 FROM _pd WHERE _pd.event_type = pe.event_type AND _pd.source = pe.source
                        AND _pd.source_id IS NOT DISTINCT FROM pe.source_id)
      -- إيقاف الإضافي من الإعدادات لا يلغي إضافياً اعتمدته الإدارة سابقاً
      AND NOT (pe.event_type = 'overtime' AND pe.decided_at IS NOT NULL
               AND NOT COALESCE((v_policy ->> 'overtime_enabled')::boolean, false))
  LOOP
    PERFORM public._payroll_settle(e, 0);
    UPDATE payroll_events SET status = 'void', updated_at = now() WHERE id = e.id AND salary_slip_id IS NULL;
  END LOOP;

  -- (ب) الحركات المطلوبة: إنشاء أو تحديث
  FOR d IN SELECT * FROM _pd LOOP
    SELECT * INTO e FROM payroll_events pe
    WHERE pe.employee_id = p_employee_id AND pe.event_date = p_date AND pe.event_type = d.event_type
      AND pe.source = d.source AND pe.source_id IS NOT DISTINCT FROM d.source_id AND pe.status <> 'void'
    ORDER BY pe.created_at DESC LIMIT 1;

    IF NOT FOUND THEN
      v_legacy := public.payroll_legacy_slip(p_employee_id, v_natural, p_date);
      v_target := CASE WHEN v_legacy IS NOT NULL THEN v_natural ELSE public.payroll_target_month(p_employee_id, v_natural) END;
      INSERT INTO payroll_events (employee_id, event_date, event_type, minutes, days, amount, direction,
                                  payroll_month, carried_from, status, source, source_id, daily_rate, minute_rate, notes,
                                  salary_slip_id)
      VALUES (p_employee_id, p_date, d.event_type, d.minutes, d.days, d.amount, d.direction,
              v_target, NULLIF(v_natural, v_target), COALESCE(d.status_hint, 'pending'), d.source, d.source_id,
              v_daily, v_minute, d.notes, v_legacy);
    ELSIF e.salary_slip_id IS NOT NULL THEN
      -- داخل كشف معتمد: لا نغيّره، الفرق يصير تسوية في أول مسير مفتوح
      v_status := CASE WHEN d.status_hint IN ('approved', 'ignored') AND d.event_type IN ('absence', 'late')
                       THEN d.status_hint ELSE e.status END;
      -- مبلغ معدّل من الإدارة يبقى هو المطلوب
      v_desired_signed := CASE WHEN v_status = 'approved' THEN d.direction * COALESCE(e.amount_override, d.amount) ELSE 0 END;
      PERFORM public._payroll_settle(e, v_desired_signed);
    ELSE
      v_status := CASE
        WHEN d.status_hint IN ('approved', 'ignored') AND (d.event_type IN ('absence', 'late') OR d.source = 'leave') THEN d.status_hint
        WHEN d.status_hint = 'pending' AND d.event_type IN ('absence', 'late') AND e.decided_at IS NULL THEN 'pending'
        ELSE e.status
      END;
      v_target := CASE
        WHEN EXISTS (SELECT 1 FROM payroll_periods WHERE period_month = e.payroll_month AND status = 'open')
             AND NOT EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = p_employee_id AND work_month = e.payroll_month)
          THEN e.payroll_month
        ELSE public.payroll_target_month(p_employee_id, v_natural)
      END;
      UPDATE payroll_events
      SET minutes = CASE WHEN e.event_type = 'missing_punch' AND e.decided_at IS NOT NULL THEN e.minutes ELSE d.minutes END,
          days = d.days,
          -- مبلغ عدّلته الإدارة عند الخصم يبقى (ما يرجع للمحسوب)، وينمسح إذا القرار ما عاد خصم
          amount = CASE WHEN v_status = 'approved' AND e.amount_override IS NOT NULL THEN e.amount_override
                        WHEN e.event_type = 'missing_punch' AND e.decided_at IS NOT NULL THEN e.amount ELSE d.amount END,
          amount_override = CASE WHEN v_status = 'approved' THEN e.amount_override END,
          direction = CASE WHEN e.event_type = 'missing_punch' AND e.decided_at IS NOT NULL THEN e.direction ELSE d.direction END,
          notes = d.notes,
          status = v_status, payroll_month = v_target, carried_from = NULLIF(v_natural, v_target),
          daily_rate = v_daily, minute_rate = v_minute, updated_at = now()
      WHERE id = e.id;
    END IF;
  END LOOP;
END;
$function$;

-- ---------------------------------------------------------------------
-- (PAY-009) أساسي المسير: أيام الانقطاع مثل الأيام قبل المباشرة (قرار 15/10/2026)، ويا سطر الشرح
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_employee_summary(p_employee_id uuid, p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_emp employees%ROWTYPE;
  v_month_basic numeric;
  v_daily numeric;
  v_from date;
  v_to date;
  v_period_days int;
  v_employed_days int;
  v_basic numeric;
  v_basis text;
  v_note text;
  v_missing int;
  v_ev record;
  v_loans numeric;
  v_slip salary_slips%ROWTYPE;
  v_exit_balance numeric := 0;
  v_loan_items jsonb;
  v_attended int;
  v_scheduled int;
  v_gap int;
  v_gap_note text;
BEGIN
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  v_month_basic := public.payroll_basic_salary(p_employee_id, p_month);
  v_daily := v_month_basic / 30;

  v_from := GREATEST(v_p.start_date, COALESCE(v_emp.join_date, v_p.start_date));
  v_to := LEAST(v_p.cutoff_date, COALESCE(v_emp.termination_date, v_p.cutoff_date));
  v_period_days := v_p.cutoff_date - v_p.start_date + 1;
  -- أيام الانقطاع (ترك ورجع) داخل المسير ما تنحسب خدمة (تدقيق 14/10 PAY-009)
  SELECT string_agg(format('ترك بعد %s ورجع %s', to_char(b.last_day, 'DD/MM'), to_char(b.return_date, 'DD/MM')), '، ' ORDER BY b.last_day)
  INTO v_gap_note
  FROM (SELECT DISTINCT b.id, b.last_day, b.return_date
        FROM employee_service_breaks b
        WHERE b.employee_id = p_employee_id AND b.last_day < v_to AND b.return_date > v_from) b;
  SELECT count(*) INTO v_gap
  FROM generate_series(v_from, v_to, interval '1 day') g(d)
  WHERE EXISTS (SELECT 1 FROM employee_service_breaks b WHERE b.employee_id = p_employee_id AND g.d::date > b.last_day AND g.d::date < b.return_date);
  v_employed_days := GREATEST(v_to - v_from + 1 - v_gap, 0);

  -- أيام الدوام ضمن الخدمة (حسب جدول الموظف بكل يوم، بدون الجمع/العطل الأسبوعية والرسمية)
  SELECT count(*) INTO v_scheduled
  FROM generate_series(v_from, v_to, interval '1 day') g(d)
  WHERE EXTRACT(DOW FROM g.d)::int = ANY (COALESCE((public.payroll_schedule_at(p_employee_id, g.d::date)).work_days, ARRAY[0, 1, 2, 3, 4, 6]))
    AND NOT EXISTS (SELECT 1 FROM official_holidays h WHERE h.holiday_date = g.d::date)
    AND NOT EXISTS (SELECT 1 FROM employee_service_breaks b WHERE b.employee_id = p_employee_id AND g.d::date > b.last_day AND g.d::date < b.return_date);

  IF v_employed_days <= 0 THEN
    v_basic := 0;
    v_basis := 'none';
    v_note := 'ما اشتغل بهالمسير';
  ELSIF v_emp.termination_date IS NOT NULL AND v_emp.termination_date < v_p.cutoff_date THEN
    -- نهاية خدمة داخل المسير: أيام الدوام اللي خدمها بس (قرار 15/10/2026)
    v_basic := round(v_daily * v_scheduled);
    v_basis := 'end_of_service';
    v_note := format('نهاية خدمة: %s يوم دوام من %s لحد %s (الجمع والعطل الرسمية%s ما تنحسب) × أجر اليوم %s = %s د.ع',
                     v_scheduled, to_char(v_from, 'DD/MM'), to_char(v_to, 'DD/MM'),
                     CASE WHEN v_gap > 0 THEN ' وأيام الانقطاع' ELSE '' END,
                     to_char(round(v_daily), 'FM999,999,999'), to_char(v_basic, 'FM999,999,999'));
  ELSIF v_employed_days < v_period_days AND v_gap > 0 THEN
    -- رجع للعمل بعد انقطاع (قرار 15/10/2026: مثل المباشر): الراتب ناقص أجر أيام الانقطاع (وأيام قبل المباشرة إن وجدت)
    v_missing := v_period_days - v_employed_days;
    v_basic := GREATEST(v_month_basic - round(v_daily * v_missing), 0);
    v_basis := 'returned';
    v_note := format('%s: الراتب %s ناقص %s × أجر اليوم %s = %s د.ع',
                     v_gap_note, to_char(v_month_basic, 'FM999,999,999'),
                     CASE WHEN v_missing > v_gap THEN format('%s يوم (%s انقطاع + %s قبل المباشرة)', v_missing, v_gap, v_missing - v_gap)
                          ELSE format('%s يوم انقطاع', v_gap) END,
                     to_char(round(v_daily), 'FM999,999,999'), to_char(v_basic, 'FM999,999,999'));
  ELSIF v_employed_days < v_period_days THEN
    -- مباشرة بنص المسير: الراتب ناقص أجر الأيام قبل المباشرة (مثل خصم الغياب، مهما كان طول المسير)
    v_missing := v_period_days - v_employed_days;
    v_basic := GREATEST(v_month_basic - round(v_daily * v_missing), 0);
    v_basis := 'joined';
    v_note := format('باشر %s: الراتب %s ناقص %s يوم قبل المباشرة × أجر اليوم %s = %s د.ع',
                     to_char(v_from, 'DD/MM/YYYY'), to_char(v_month_basic, 'FM999,999,999'), v_missing,
                     to_char(round(v_daily), 'FM999,999,999'), to_char(v_basic, 'FM999,999,999'));
  ELSE
    v_basic := v_month_basic;
    v_basis := 'full';
    v_note := format('راتب المسير كامل: %s د.ع', to_char(v_month_basic, 'FM999,999,999'));
  END IF;

  SELECT
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = 1), 0) AS earnings,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = -1), 0) AS deductions,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = -1 AND event_type IN ('absence', 'late', 'early_leave', 'unpaid_leave')), 0) AS attendance_deductions,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND event_type = 'overtime'), 0) AS overtime,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND event_type = 'bonus'), 0) AS bonuses,
    count(*) FILTER (WHERE status = 'pending') AS pending,
    count(*) FILTER (WHERE status = 'pending' AND event_type = 'missing_punch') AS missing_punches,
    COALESCE(sum(days) FILTER (WHERE status = 'approved' AND event_type = 'absence'), 0) AS absence_days,
    COALESCE(sum(minutes) FILTER (WHERE status = 'approved' AND event_type = 'late'), 0) AS late_minutes,
    COALESCE(sum(minutes) FILTER (WHERE status = 'approved' AND event_type = 'early_leave'), 0) AS early_minutes,
    COALESCE(sum(minutes) FILTER (WHERE status = 'approved' AND event_type = 'overtime'), 0) AS overtime_minutes,
    COALESCE(sum(days) FILTER (WHERE event_type = 'paid_leave'), 0) AS paid_leave_days,
    COALESCE(sum(days) FILTER (WHERE status = 'approved' AND event_type = 'unpaid_leave'), 0) AS unpaid_leave_days
  INTO v_ev
  FROM payroll_events
  WHERE employee_id = p_employee_id AND payroll_month = p_month AND status <> 'void';

  SELECT COALESCE(sum(li.amount), 0) INTO v_loans
  FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'           -- السلفة النقدية تُسدَّد نقداً لا من الراتب
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  -- ترك العمل خلال المسير: ما يبقى من السلف بعد أقساط هذا المسير (تنبيه للإدارة)
  IF v_emp.termination_date IS NOT NULL AND v_emp.termination_date <= v_p.cutoff_date THEN
    SELECT COALESCE(sum(li.amount), 0) INTO v_exit_balance
    FROM loan_installments li JOIN loans l ON l.id = li.loan_id
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid AND li.due_date > v_p.cutoff_date;
  END IF;

  -- للعرض فقط: أقساط هالمسير وأسبابها، وأيام الدوام الفعلي مقابل المجدول (الحساب ما يتغير)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'installment_id', li.id, 'loan_id', l.id, 'loan_amount', l.amount, 'due_date', li.due_date, 'amount', li.amount,
           'origin_kind', li.origin_kind, 'origin_month', li.origin_month, 'amount_locked', li.amount_locked,
           'note', li.payment_note) ORDER BY li.due_date), '[]'::jsonb)
  INTO v_loan_items
  FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  SELECT count(DISTINCT a.work_date) INTO v_attended
  FROM attendance a
  WHERE a.employee_id = p_employee_id AND a.work_date BETWEEN v_from AND v_to AND a.status <> 'absent';

  SELECT * INTO v_slip FROM salary_slips WHERE employee_id = p_employee_id AND work_month = p_month;

  RETURN jsonb_build_object(
    'employee_id', p_employee_id,
    'period_days', v_period_days,
    'employed_days', v_employed_days,
    'gap_days', v_gap,
    'monthly_salary', v_month_basic,
    'daily_rate', round(v_daily, 4),
    'minute_rate', round(v_daily / public.payroll_shift_minutes(p_employee_id), 6),
    'shift_minutes', public.payroll_shift_minutes(p_employee_id),
    'basic', v_basic,
    'basic_basis', v_basis,
    'basic_note', v_note,
    'earnings', round(v_ev.earnings),
    'bonuses', round(v_ev.bonuses),
    'overtime', round(v_ev.overtime),
    'deductions', round(v_ev.deductions),
    'attendance_deductions', round(v_ev.attendance_deductions),
    'loans', v_loans,
    -- التقريب لأقرب دينار على المجموع (لا يوم بيوم)
    'net', v_basic + round(v_ev.earnings) - round(v_ev.deductions) - v_loans,
    'loan_balance_after_exit', v_exit_balance,
    'loan_items', v_loan_items,
    'attended_days', COALESCE(v_attended, 0),
    'scheduled_days', COALESCE(v_scheduled, 0),
    'has_schedule', (public.payroll_schedule_at(p_employee_id, LEAST(v_p.cutoff_date, (now() AT TIME ZONE public.company_timezone())::date))).id IS NOT NULL,
    'pending_count', v_ev.pending,
    'missing_punches', v_ev.missing_punches,
    'absence_days', v_ev.absence_days,
    'late_minutes', v_ev.late_minutes,
    'early_minutes', v_ev.early_minutes,
    'overtime_minutes', v_ev.overtime_minutes,
    'paid_leave_days', v_ev.paid_leave_days,
    'unpaid_leave_days', v_ev.unpaid_leave_days,
    'slip', CASE WHEN v_slip.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_slip.id, 'basic_salary', v_slip.basic_salary, 'allowances', v_slip.allowances,
      'deductions', v_slip.deductions, 'loans_deduction', v_slip.loans_deduction,
      'net_salary', v_slip.net_salary, 'created_at', v_slip.created_at,
      'legacy', NOT v_slip.computed_by_engine) END
  );
END;
$function$;

-- ---------------------------------------------------------------------
-- تقرير الحضور بالمساعد: أيام الانقطاع «خارج فترة الخدمة» (مو غياب)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_attendance_log(p_employee_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tz text := public.company_timezone();
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_emp record;
  v_days jsonb := '[]'::jsonb;
  d date;
  s work_schedules%ROWTYPE;
  v_holiday text;
  v_workday boolean;
  a attendance%ROWTYPE;
  v_has_att boolean;
  v_leave text;
  v_hourly text;
  v_events jsonb;
  v_status text;
  v_decision text;
  v_deducted numeric;
BEGIN
  PERFORM public.require_admin();
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
    RAISE EXCEPTION 'حدد فترة صحيحة (من … إلى).' USING ERRCODE = '22023';
  END IF;
  IF p_to - p_from > 92 THEN
    RAISE EXCEPTION 'الفترة طويلة: أقصاها 3 أشهر بالطلب الواحد.' USING ERRCODE = '22023';
  END IF;

  SELECT e.id, e.full_name, e.employee_code, b.name AS branch, e.join_date, e.termination_date INTO v_emp
  FROM employees e LEFT JOIN branches b ON b.id = e.branch_id WHERE e.id = p_employee_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;

  d := p_from;
  WHILE d <= p_to LOOP
    s := public.payroll_schedule_at(p_employee_id, d);
    SELECT name INTO v_holiday FROM official_holidays WHERE holiday_date = d LIMIT 1;
    v_workday := EXTRACT(DOW FROM d)::int = ANY (COALESCE(s.work_days, ARRAY[0, 1, 2, 3, 4, 6])) AND v_holiday IS NULL;

    SELECT * INTO a FROM attendance WHERE employee_id = p_employee_id AND work_date = d LIMIT 1;
    v_has_att := FOUND;

    SELECT public.assistant_leave_type_name(l.leave_type) || CASE WHEN l.is_paid THEN '' ELSE ' (بدون راتب)' END INTO v_leave
    FROM leave_requests l
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT COALESCE(l.is_hourly, false)
      AND d BETWEEN (l.start_date AT TIME ZONE v_tz)::date AND (l.end_date AT TIME ZONE v_tz)::date
    LIMIT 1;

    SELECT string_agg(format('إذن %s→%s', to_char(l.start_hour, 'HH24:MI'), to_char(l.end_hour, 'HH24:MI')), '، ') INTO v_hourly
    FROM leave_requests l
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND COALESCE(l.is_hourly, false)
      AND (l.start_date AT TIME ZONE v_tz)::date = d;

    SELECT jsonb_agg(jsonb_build_object(
             'type', pe.event_type, 'minutes', pe.minutes, 'amount', round(pe.amount),
             'decision', CASE pe.status WHEN 'approved' THEN 'مخصوم' WHEN 'ignored' THEN 'معفى' ELSE 'بانتظار القرار' END,
             'reason', COALESCE(pe.decision_reason, pe.notes), 'payroll_month', pe.payroll_month) ORDER BY pe.event_type)
    INTO v_events
    FROM payroll_events pe
    WHERE pe.employee_id = p_employee_id AND pe.event_date = d AND pe.status <> 'void'
      AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch', 'unpaid_leave');

    v_status := CASE
      WHEN NOT public.employee_in_service(p_employee_id, d) THEN 'خارج فترة الخدمة'
      WHEN v_holiday IS NOT NULL AND NOT v_has_att THEN 'عطلة رسمية'
      WHEN v_leave IS NOT NULL THEN 'إجازة'
      WHEN v_has_att AND a.status = 'absent' THEN 'غياب'
      WHEN v_has_att AND a.check_in_time IS NULL THEN 'بصمة ناقصة'
      WHEN v_has_att AND v_events @> '[{"type":"late"}]' THEN 'متأخر'
      WHEN v_has_att AND v_events @> '[{"type":"early_leave"}]' THEN 'خروج مبكر'
      WHEN v_has_att THEN 'حاضر'
      WHEN NOT v_workday THEN 'عطلة أسبوعية'
      WHEN d >= v_today THEN 'لم يحن بعد'
      ELSE 'غياب'
    END;

    SELECT CASE
             WHEN count(*) FILTER (WHERE e ->> 'type' <> 'missing_punch') = 0 THEN NULL
             WHEN bool_or(e ->> 'decision' = 'بانتظار القرار') THEN 'بانتظار القرار'
             WHEN bool_or(e ->> 'decision' = 'مخصوم') THEN 'مخصوم'
             ELSE 'معفى' END,
           COALESCE(sum((e ->> 'amount')::numeric) FILTER (WHERE e ->> 'decision' = 'مخصوم'), 0)
    INTO v_decision, v_deducted
    FROM jsonb_array_elements(COALESCE(v_events, '[]'::jsonb)) e;

    v_days := v_days || jsonb_build_object(
      'date', d, 'weekday', EXTRACT(DOW FROM d)::int, 'workday', v_workday, 'status', v_status,
      'holiday', v_holiday, 'leave', COALESCE(v_leave, v_hourly),
      'check_in', CASE WHEN v_has_att THEN to_char(a.check_in_time AT TIME ZONE v_tz, 'HH24:MI') END,
      'check_out', CASE WHEN v_has_att THEN to_char(a.check_out_time AT TIME ZONE v_tz, 'HH24:MI') END,
      'late_minutes', COALESCE((SELECT sum((e ->> 'minutes')::numeric) FROM jsonb_array_elements(COALESCE(v_events, '[]')) e WHERE e ->> 'type' = 'late'), 0),
      'early_minutes', COALESCE((SELECT sum((e ->> 'minutes')::numeric) FROM jsonb_array_elements(COALESCE(v_events, '[]')) e WHERE e ->> 'type' = 'early_leave'), 0),
      'decision', v_decision, 'deducted', v_deducted, 'events', COALESCE(v_events, '[]'::jsonb));
    d := d + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'employee', jsonb_build_object('id', v_emp.id, 'name', v_emp.full_name, 'code', v_emp.employee_code, 'branch', v_emp.branch),
    'from', p_from, 'to', p_to,
    'summary', (SELECT jsonb_build_object(
        'present', count(*) FILTER (WHERE x ->> 'status' IN ('حاضر', 'متأخر', 'خروج مبكر')),
        'late', count(*) FILTER (WHERE x ->> 'status' = 'متأخر'),
        'early_leave', count(*) FILTER (WHERE x ->> 'status' = 'خروج مبكر'),
        'absent', count(*) FILTER (WHERE x ->> 'status' = 'غياب'),
        'leave', count(*) FILTER (WHERE x ->> 'status' = 'إجازة'),
        'missing_punch', count(*) FILTER (WHERE x ->> 'status' = 'بصمة ناقصة'),
        'late_minutes', sum((x ->> 'late_minutes')::numeric),
        'deducted_days', count(*) FILTER (WHERE x ->> 'decision' = 'مخصوم'),
        'excused_days', count(*) FILTER (WHERE x ->> 'decision' = 'معفى'),
        'pending_days', count(*) FILTER (WHERE x ->> 'decision' = 'بانتظار القرار'),
        'deducted_total', sum((x ->> 'deducted')::numeric))
      FROM jsonb_array_elements(v_days) x),
    'days', v_days);
END;
$function$;

-- ---------------------------------------------------------------------
-- (PAY-009) التفعيل بعد الترك: فترة الانقطاع تنحفظ (تاريخ الرجوع من reactivate_employee، وإلا اليوم)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_termination_date()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_return date;
BEGIN
  IF COALESCE(OLD.is_active, true) AND NOT COALESCE(NEW.is_active, true) AND NEW.termination_date IS NULL THEN
    NEW.termination_date := v_today;
  ELSIF NOT COALESCE(OLD.is_active, true) AND COALESCE(NEW.is_active, true) THEN
    -- الأيام بين آخر يوم عمل ويوم الرجوع ما تطلع غياب، وتنقص من راتب ذاك المسير مثل الأيام قبل المباشرة
    v_return := COALESCE(NULLIF(current_setting('employees.return_date', true), '')::date, v_today);
    IF OLD.termination_date IS NOT NULL AND v_return > OLD.termination_date + 1 THEN
      INSERT INTO employee_service_breaks (employee_id, last_day, return_date, recorded_by)
      VALUES (NEW.id, OLD.termination_date, v_return, auth.uid());
    END IF;
    NEW.termination_date := NULL;
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- (PAY-009) «تفعيل الحساب» بتاريخ رجوع: يحفظ الانقطاع، ويعيد حساب المسيرات المفتوحة، وينبّه إذا راتب شهر الرجوع معتمد
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reactivate_employee(p_employee_id uuid, p_return_date date DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp employees%ROWTYPE;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_return date := COALESCE(p_return_date, (now() AT TIME ZONE public.company_timezone())::date);
  v_month text;
  v_gap int := 0;
  v_warnings jsonb := '[]'::jsonb;
  r record;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF v_emp.is_active THEN
    RAISE EXCEPTION 'حساب % مفعّل أصلاً.', v_emp.full_name USING ERRCODE = '22023';
  END IF;
  IF v_return > v_today THEN
    RAISE EXCEPTION 'تاريخ الرجوع ما يكون بالمستقبل: فعّل الحساب يوم يرجع.' USING ERRCODE = '22023';
  END IF;
  IF v_emp.join_date IS NOT NULL AND v_return < v_emp.join_date THEN
    RAISE EXCEPTION 'تاريخ الرجوع قبل تاريخ المباشرة (%).', to_char(v_emp.join_date, 'DD/MM/YYYY') USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('employees.return_date', v_return::text, true);
  UPDATE employees SET is_active = true WHERE id = p_employee_id;
  PERFORM set_config('employees.return_date', '', true);
  IF v_emp.termination_date IS NOT NULL AND v_return > v_emp.termination_date + 1 THEN
    v_gap := v_return - v_emp.termination_date - 1;
  END IF;

  -- المسيرات المفتوحة من آخر يوم عمل لحد اليوم تنعاد (أيام الانقطاع ما تطلع غياب)
  FOR r IN
    SELECT pp.period_month FROM payroll_periods pp
    WHERE pp.status = 'open' AND pp.cutoff_date >= COALESCE(v_emp.termination_date, v_return) AND pp.start_date <= v_today
      AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = p_employee_id AND s.work_month = pp.period_month)
    ORDER BY 1
  LOOP
    PERFORM public.sync_payroll_period(r.period_month, p_employee_id);
  END LOOP;

  -- راتب شهر الرجوع معتمد (مثلاً آخر راتب قبل الترك): أيام رجوعه ما تنحسب إلا بإلغاء الاعتماد وإعادته
  v_month := public.payroll_month_of(v_return);
  IF EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = p_employee_id AND s.work_month = v_month) THEN
    v_warnings := v_warnings || to_jsonb(format(
      'راتب الشهر %s %s معتمد من قبل الرجوع: ألغِ اعتماده من صفحة الرواتب وأعد اعتماده حتى تنحسب أيام رجوعه.',
      (ARRAY['الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس', 'السابع', 'الثامن', 'التاسع', 'العاشر', 'الحادي عشر', 'الثاني عشر'])[split_part(v_month, '-', 2)::int],
      split_part(v_month, '-', 1)));
  END IF;

  RETURN jsonb_build_object('employee_id', p_employee_id, 'last_day', v_emp.termination_date, 'return_date', v_return,
                            'gap_days', v_gap, 'warnings', v_warnings);
END;
$function$;
REVOKE ALL ON FUNCTION public.reactivate_employee(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reactivate_employee(uuid, date) TO authenticated;

-- ---------------------------------------------------------------------
-- (FEATURE-001) سجل الموظف: باشر، انتقل (فرع/قسم)، ترك، رجع — بالتاريخ
-- الأدمن، ومدير فرعه، والموظف لنفسه (ماكو مبالغ)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_employee_history(p_employee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp employees%ROWTYPE;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_events jsonb;
BEGIN
  IF NOT (public.is_admin() OR p_employee_id = auth.uid() OR p_employee_id = ANY (public.managed_employee_ids())) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  IF NOT FOUND THEN
    RETURN '[]'::jsonb;
  END IF;

  WITH h AS (
    SELECT hh.effective_from, hh.branch_id, hh.department_id,
           lag(hh.branch_id) OVER w AS prev_branch, lag(hh.department_id) OVER w AS prev_dept,
           row_number() OVER w AS rn
    FROM employee_assignment_history hh
    WHERE hh.employee_id = p_employee_id
    WINDOW w AS (ORDER BY hh.effective_from, hh.recorded_at, hh.id)
  ), ev AS (
    SELECT v_emp.join_date AS d, 1 AS ord, 'join' AS kind,
           'باشر بالعمل' || COALESCE(' بفرع ' || (SELECT b.name FROM h JOIN branches b ON b.id = h.branch_id WHERE h.rn = 1), '') AS txt
    WHERE v_emp.join_date IS NOT NULL
    UNION ALL
    SELECT h.effective_from, 2, 'transfer',
           concat_ws('، ',
             CASE WHEN h.branch_id IS DISTINCT FROM h.prev_branch THEN
               format('انتقل من %s إلى %s',
                      COALESCE(bp.name, CASE WHEN h.prev_branch IS NULL THEN 'بدون فرع' ELSE 'فرع محذوف' END),
                      COALESCE(bn.name, CASE WHEN h.branch_id IS NULL THEN 'بدون فرع' ELSE 'فرع محذوف' END)) END,
             CASE WHEN h.department_id IS DISTINCT FROM h.prev_dept THEN
               format('صار بقسم %s', COALESCE(dn.name, CASE WHEN h.department_id IS NULL THEN 'عام (بدون قسم)' ELSE 'قسم محذوف' END)) END)
    FROM h
    LEFT JOIN branches bp ON bp.id = h.prev_branch
    LEFT JOIN branches bn ON bn.id = h.branch_id
    LEFT JOIN departments dn ON dn.id = h.department_id
    WHERE h.rn > 1 AND (h.branch_id IS DISTINCT FROM h.prev_branch OR h.department_id IS DISTINCT FROM h.prev_dept)
    UNION ALL
    SELECT b.last_day, 3, 'exit', 'ترك العمل (آخر يوم عمل)' FROM employee_service_breaks b WHERE b.employee_id = p_employee_id
    UNION ALL
    SELECT b.return_date, 4, 'return', format('رجع للعمل بعد انقطاع %s يوم', b.return_date - b.last_day - 1)
    FROM employee_service_breaks b WHERE b.employee_id = p_employee_id
    UNION ALL
    SELECT v_emp.termination_date, 5, 'exit',
           CASE WHEN v_emp.termination_date >= v_today THEN 'آخر يوم عمل (انتهاء الخدمات)' ELSE 'انتهت خدماته (آخر يوم عمل)' END
    WHERE v_emp.termination_date IS NOT NULL
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('date', ev.d, 'kind', ev.kind, 'text', ev.txt) ORDER BY ev.d, ev.ord), '[]'::jsonb)
  INTO v_events
  FROM ev;
  RETURN v_events;
END;
$function$;
REVOKE ALL ON FUNCTION public.get_employee_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_history(uuid) TO authenticated;
