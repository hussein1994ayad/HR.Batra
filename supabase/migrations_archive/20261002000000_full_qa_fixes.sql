-- =========================================================================
-- تصليحات الفحص الشامل (2 تشرين الأول 2026)
-- =========================================================================
-- 1) تنظيف البيانات: قفل مالي حقيقي على حذف سجلات الحضور.
-- 2) غياب مسجّل بيوم عطلة لا يُخصم (حتى لو أُعلنت العطلة بعد تسجيله).
-- 3) طلب السلفة يُفحص بنفس شروط الاعتماد (القسط ≤ 50% من الراتب، لا سلفة نشطة)
--    — كان يقبل 900 مليار ويمنع بعدها أي طلب.
-- 4) الخصم اليدوي لا يتجاوز راتب الشهر؛ وأي مبلغ حده 100 مليون.
-- 5) الحضور: الانصراف بعد الحضور، ولا سجلات لأيام مستقبلية.
-- 6) الموظف: اسم غير فارغ، وتاريخ ترك العمل ليس قبل التعيين.
-- 7) تغيير الراتب يعيد حساب المسيرات المفتوحة (كان الأساسي بالجديد والغياب بالقديم).
-- 8) مدير الفرع يقرأ موظفين فرعه فقط (كان يقرأ كل الشركة).
-- =========================================================================

-- 1) تنظيف البيانات ----------------------------------------------------
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

  -- قفل مالي: سجلات الحضور تُحسب منها خصومات الرواتب؛ ما تنحذف إلا إذا كل مسير يغطي
  -- أيام هذا الشهر مغلق (رواتبه معتمدة). قبل: كانت تنحذف فوراً فيصير المتأخر "غائباً" يوماً كاملاً.
  IF p_absences AND EXISTS (
    SELECT 1 FROM payroll_periods pp
    WHERE pp.start_date <= v_end_date AND pp.cutoff_date >= v_start_date AND pp.status <> 'closed'
  ) THEN
    RAISE EXCEPTION 'لا يمكن حذف سجلات الحضور لهذا الشهر: مسير الرواتب الذي يغطيه ما زال مفتوحاً. اعتمد الرواتب وأغلق المسير أولاً.'
      USING ERRCODE = '42501';
  END IF;

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

-- 2) الغياب بأيام العطل ---------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_payroll_day(p_employee_id uuid, p_date date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
BEGIN
  IF current_setting('payroll.skip_sync', true) = 'on' THEN RETURN; END IF;

  v_natural := public.payroll_natural_month(p_date);
  IF v_natural IS NULL THEN RETURN; END IF;         -- قبل أول مسير: كشوف قديمة

  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  IF NOT FOUND THEN RETURN; END IF;

  v_sched := public.payroll_schedule(p_employee_id);
  v_has_sched := v_sched.id IS NOT NULL;
  v_daily := public.payroll_daily_rate(p_employee_id, v_natural);
  v_minute := v_daily / public.payroll_shift_minutes(p_employee_id);
  v_grace := COALESCE(v_sched.grace_period_minutes, 15);
  v_workday := EXTRACT(DOW FROM p_date)::int = ANY (COALESCE(v_sched.work_days, ARRAY[0, 1, 2, 3, 4, 6]))
               AND NOT EXISTS (SELECT 1 FROM official_holidays WHERE holiday_date = p_date); -- العطلة الرسمية ليست يوم دوام

  -- الحركات المطلوبة لهذا اليوم (جدول مؤقت داخل الاستدعاء)
  CREATE TEMP TABLE IF NOT EXISTS _pd (
    event_type text, source text, source_id uuid, minutes numeric, days numeric,
    amount numeric, direction smallint, status_hint text, notes text
  ) ON COMMIT DROP;
  DELETE FROM _pd WHERE true; -- Supabase (pg_safeupdate) يرفض DELETE بدون WHERE

  -- الموظف لم يباشر بعد أو انتهت خدمته: لا حركات لهذا اليوم
  IF (v_emp.join_date IS NOT NULL AND p_date < v_emp.join_date)
     OR (v_emp.termination_date IS NOT NULL AND p_date > v_emp.termination_date) THEN
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
          INSERT INTO _pd VALUES ('missing_punch', 'attendance', v_att.id, 0, 0, 0, 0, NULL, 'حضور بدون بصمة انصراف');
        END IF;

        -- التأخير: من بداية الدوام، إذا تجاوز فترة السماح
        IF v_att.check_in_time IS NOT NULL AND v_has_sched AND v_sched.check_in_time IS NOT NULL THEN
          v_mins := floor(public.payroll_local_minutes(v_att.check_in_time) - public.payroll_time_minutes(v_sched.check_in_time))
                    - public.payroll_hourly_leave_overlap(p_employee_id, p_date, public.payroll_time_minutes(v_sched.check_in_time),
                                                         public.payroll_local_minutes(v_att.check_in_time));
          IF v_mins > v_grace OR (v_att.status = 'late' AND v_mins > 0) THEN
            INSERT INTO _pd VALUES ('late', 'attendance', v_att.id, v_mins, 0, round(v_mins * v_minute, 2), -1, v_status,
                                    format('تأخير %s دقيقة', v_mins));
          END IF;
        END IF;

        IF v_att.check_out_time IS NOT NULL AND v_has_sched AND v_sched.check_out_time IS NOT NULL THEN
          -- الخروج المبكر بالدقائق (ينتظر قرار الإدارة)
          v_mins := floor(public.payroll_time_minutes(v_sched.check_out_time) - public.payroll_local_minutes(v_att.check_out_time))
                    - public.payroll_hourly_leave_overlap(p_employee_id, p_date, public.payroll_local_minutes(v_att.check_out_time),
                                                         public.payroll_time_minutes(v_sched.check_out_time));
          IF v_mins > v_grace THEN
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

    -- الإجازات الزمنية المعتمدة في هذا اليوم
    FOR v_leave IN
      SELECT * FROM leave_requests
      WHERE employee_id = p_employee_id AND status = 'approved' AND COALESCE(is_hourly, false)
        AND (start_date AT TIME ZONE public.company_timezone())::date = p_date
    LOOP
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
      v_desired_signed := CASE WHEN v_status = 'approved' THEN d.direction * d.amount ELSE 0 END;
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
      SET minutes = d.minutes, days = d.days, amount = d.amount, direction = d.direction, notes = d.notes,
          status = v_status, payroll_month = v_target, carried_from = NULLIF(v_natural, v_target),
          daily_rate = v_daily, minute_rate = v_minute, updated_at = now()
      WHERE id = e.id;
    END IF;
  END LOOP;
END;
$$;

-- أيام العطل التي عليها غياب غير مصروف: إعادة حساب
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT pe.employee_id, pe.event_date FROM payroll_events pe
           JOIN official_holidays h ON h.holiday_date = pe.event_date
           WHERE pe.event_type = 'absence' AND pe.status <> 'void' AND pe.salary_slip_id IS NULL
  LOOP
    PERFORM public.sync_payroll_day(r.employee_id, r.event_date);
  END LOOP;
END $$;

-- 3) طلب السلفة -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.one_pending_loan_request()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_salary numeric;
BEGIN
  IF NEW.status = 'pending' AND EXISTS (
    SELECT 1 FROM loans WHERE employee_id = NEW.employee_id AND status = 'pending' AND id <> NEW.id
  ) THEN
    RAISE EXCEPTION 'لديك طلب سلفة قيد المراجعة. انتظر قرار الإدارة قبل تقديم طلب جديد.' USING ERRCODE = '23505';
  END IF;

  -- طلبات المستخدمين عبر التطبيق/الموقع فقط (العمليات الداخلية والإعداد تمر)
  IF NEW.status = 'pending' AND current_user IN ('authenticated', 'anon') THEN
    IF EXISTS (SELECT 1 FROM loans WHERE employee_id = NEW.employee_id AND status = 'approved' AND remaining_amount > 0) THEN
      RAISE EXCEPTION 'لديك سلفة جارية لم تُسدَّد بعد. تقدر تطلب سلفة جديدة بعد إكمال سدادها.' USING ERRCODE = '55000';
    END IF;
    SELECT monthly_salary_iqd INTO v_salary FROM employees WHERE id = NEW.employee_id;
    IF COALESCE(v_salary, 0) > 0 AND NEW.installment_amount > v_salary * 0.5 THEN
      RAISE EXCEPTION 'القسط الشهري يتجاوز 50%% من راتبك (الحد % د.ع). زد مدة السداد أو قلّل المبلغ.',
        to_char(v_salary * 0.5, 'FM999,999,999') USING ERRCODE = '22023';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- 4) حدود الخصومات والمكافآت ------------------------------------------
CREATE OR REPLACE FUNCTION public.check_bonus_deduction_amount()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
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
$$;
DROP TRIGGER IF EXISTS trg_check_bonus_deduction_amount ON public.bonuses_deductions;
CREATE TRIGGER trg_check_bonus_deduction_amount
BEFORE INSERT OR UPDATE OF amount, type, employee_id ON public.bonuses_deductions
FOR EACH ROW EXECUTE FUNCTION public.check_bonus_deduction_amount();

-- 5) الحضور ------------------------------------------------------------
ALTER TABLE public.attendance DROP CONSTRAINT IF EXISTS chk_attendance_out_after_in;
ALTER TABLE public.attendance ADD CONSTRAINT chk_attendance_out_after_in
  CHECK (check_out_time IS NULL OR check_in_time IS NULL OR check_out_time >= check_in_time);

CREATE OR REPLACE FUNCTION public.reject_future_attendance()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- إدخالات المستخدمين فقط (البصمة من السيرفر تستعمل وقت السيرفر أصلاً)
  -- رسالة عربية قبل قيد chk_attendance_out_after_in
  IF NEW.check_out_time IS NOT NULL AND NEW.check_in_time IS NOT NULL AND NEW.check_out_time < NEW.check_in_time THEN
    RAISE EXCEPTION 'وقت الانصراف لازم يكون بعد وقت الحضور.' USING ERRCODE = '23514';
  END IF;
  IF current_user IN ('authenticated', 'anon')
     AND (TG_OP = 'INSERT' OR NEW.work_date IS DISTINCT FROM OLD.work_date)
     AND NEW.work_date > (now() AT TIME ZONE public.company_timezone())::date THEN
    RAISE EXCEPTION 'لا يمكن تسجيل حضور أو غياب ليوم لم يأتِ بعد (%).', NEW.work_date USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_reject_future_attendance ON public.attendance;
CREATE TRIGGER trg_reject_future_attendance
BEFORE INSERT OR UPDATE OF work_date, check_in_time, check_out_time ON public.attendance
FOR EACH ROW EXECUTE FUNCTION public.reject_future_attendance();

-- 6) بيانات الموظف ------------------------------------------------------
ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS chk_employees_name_not_blank;
ALTER TABLE public.employees ADD CONSTRAINT chk_employees_name_not_blank CHECK (btrim(full_name) <> '');
ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS chk_employees_termination_after_join;
ALTER TABLE public.employees ADD CONSTRAINT chk_employees_termination_after_join
  CHECK (termination_date IS NULL OR join_date IS NULL OR termination_date >= join_date);

-- رسائل عربية قبل قيود بيانات الموظف
CREATE OR REPLACE FUNCTION public.check_employee_basics()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF btrim(COALESCE(NEW.full_name, '')) = '' THEN
    RAISE EXCEPTION 'اسم الموظف مطلوب.' USING ERRCODE = '23514';
  END IF;
  IF NEW.termination_date IS NOT NULL AND NEW.join_date IS NOT NULL AND NEW.termination_date < NEW.join_date THEN
    RAISE EXCEPTION 'تاريخ آخر يوم عمل (%) قبل تاريخ المباشرة (%).', NEW.termination_date, NEW.join_date USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_check_employee_basics ON public.employees;
CREATE TRIGGER trg_check_employee_basics
BEFORE INSERT OR UPDATE OF full_name, join_date, termination_date ON public.employees
FOR EACH ROW EXECUTE FUNCTION public.check_employee_basics();

-- 7) تغيير الراتب → إعادة حساب المسيرات المفتوحة بدون كشف ----------------
CREATE OR REPLACE FUNCTION public.resync_payroll_on_salary_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
BEGIN
  IF NEW.monthly_salary_iqd IS NOT DISTINCT FROM OLD.monthly_salary_iqd THEN
    RETURN NEW;
  END IF;
  FOR r IN
    SELECT pp.period_month FROM payroll_periods pp
    WHERE pp.status = 'open'
      AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = NEW.id AND s.work_month = pp.period_month)
  LOOP
    PERFORM public.sync_payroll_period(r.period_month, NEW.id);
  END LOOP;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_resync_payroll_on_salary_change ON public.employees;
CREATE TRIGGER trg_resync_payroll_on_salary_change
AFTER UPDATE OF monthly_salary_iqd ON public.employees
FOR EACH ROW EXECUTE FUNCTION public.resync_payroll_on_salary_change();

-- 8) مدير الفرع: موظفين فرعه فقط ----------------------------------------
DROP POLICY IF EXISTS "Employees can view their own details" ON public.employees;
CREATE POLICY "Employees can view their own details" ON public.employees
  FOR SELECT USING (id = auth.uid() OR public.is_admin() OR (public.is_manager() AND public.payroll_same_branch(id)));
