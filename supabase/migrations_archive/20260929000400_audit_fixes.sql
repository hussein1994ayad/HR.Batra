-- =====================================================================
-- تصليحات الفحص الشامل (QA) — الموافَق عليها
--
--  1) الحذف المجدول للموظف كان يحذف صفّه فتُمسح كشوفه وسلفه وحضوره (CASCADE):
--     الآن يُخفي هويته ويحذف حسابه فقط، وتبقى السجلات المالية.
--  2) المكافآت والخصومات اليدوية للأدمن فقط (كان المدير يضيف مكافأة لنفسه).
--     المدير يرى ويقرّر حركات موظفي فرعه فقط، ولا يقرّر على نفسه.
--  3) الإجازة الزمنية المعتمدة لا يُحسب وقتها تأخيراً ولا خروجاً مبكراً.
--  4) إجازة يومية معتمدة ليوم مسجّل غياب: تُحتسب الإجازة لا الغياب.
--  5) الكشف القديم (قبل المحرّك) يغطي الأيام حتى تاريخ إنشائه فقط.
--  6) المبالغ بدقة فلسين والتقريب لأقرب دينار على مجموع الكشف (كان يوماً بيوم).
--  7) السلفة النقدية (payment_method = cash) لا تُخصم من الراتب.
--  8) تنبيه: موظف ترك العمل وما زال عليه رصيد سلفة.
--  9) العطل الرسمية: جدول official_holidays — لا غياب ولا تذكير بصمة في يومها.
-- 10) قيود: مكافأة/خصم > 0، راتب ≥ 0، قسط السلفة ≤ مبلغها.
-- =====================================================================

-- ---------------------------------------------------------------------
-- العطل الرسمية
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.official_holidays (
  holiday_date date PRIMARY KEY,
  name         text NOT NULL CHECK (btrim(name) <> ''),
  created_by   uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.official_holidays ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Everyone reads official holidays" ON public.official_holidays;
CREATE POLICY "Everyone reads official holidays" ON public.official_holidays FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Admins manage official holidays" ON public.official_holidays;
CREATE POLICY "Admins manage official holidays" ON public.official_holidays FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
COMMENT ON TABLE public.official_holidays IS 'العطل الرسمية: لا يُحتسب فيها غياب ولا تُرسل تذكيرات بصمة.';

-- ---------------------------------------------------------------------
-- أدوات
-- ---------------------------------------------------------------------
-- دقائق الإجازات الزمنية المعتمدة التي تقع داخل [p_from, p_to] (بالدقائق من منتصف الليل)
CREATE OR REPLACE FUNCTION public.payroll_hourly_leave_overlap(p_employee_id uuid, p_date date, p_from numeric, p_to numeric)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(sum(GREATEST(LEAST(p_to, l_end) - GREATEST(p_from, l_start), 0)), 0)
  FROM (
    SELECT COALESCE(public.payroll_time_minutes(lr.start_hour), public.payroll_local_minutes(lr.start_date)) AS l_start,
           COALESCE(public.payroll_time_minutes(lr.end_hour), public.payroll_local_minutes(lr.end_date)) AS l_end
    FROM leave_requests lr
    WHERE lr.employee_id = p_employee_id AND lr.status = 'approved' AND COALESCE(lr.is_hourly, false)
      AND (lr.start_date AT TIME ZONE public.company_timezone())::date = p_date
  ) x
  WHERE p_to > p_from;
$$;

-- هل الموظف من نفس فرع المستخدم الحالي؟
CREATE OR REPLACE FUNCTION public.payroll_same_branch(p_employee_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM employees me JOIN employees t ON t.id = p_employee_id
    WHERE me.id = auth.uid() AND me.branch_id IS NOT NULL AND t.branch_id = me.branch_id
  );
$$;

-- الكشف القديم لموظف في شهر، إن كان تاريخ الحركة لا يتجاوز يوم إنشائه
CREATE OR REPLACE FUNCTION public.payroll_legacy_slip(p_employee_id uuid, p_month text, p_date date)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM salary_slips
  WHERE employee_id = p_employee_id AND work_month = p_month AND NOT computed_by_engine
    AND p_date <= (created_at AT TIME ZONE public.company_timezone())::date;
$$;

-- إخفاء هوية موظف وحذف حسابه دون حذف سجلاته (مشترك: الحذف الآمن والحذف المجدول)
CREATE OR REPLACE FUNCTION public._anonymize_employee(p_employee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- إخفاء هوية الموظف في جدول الموظفين وتصفير مستنداته بأمان
  UPDATE public.employees
  SET 
    full_name = 'مستخدم محذوف',
    phone = NULL,
    email = 'deleted_' || substring(p_employee_id::text from 1 for 8) || '@deleted.com',
    avatar_url = NULL,
    is_active = false,
    plain_password = NULL,
    document_urls = '[]'::jsonb
  WHERE id = p_employee_id;

  -- إزالة الأجهزة المقترنة والتوكنات
  DELETE FROM public.employee_devices WHERE employee_id = p_employee_id;
  DELETE FROM public.fcm_tokens WHERE employee_id = p_employee_id;
  DELETE FROM public.device_tokens WHERE employee_id = p_employee_id;

  -- حذف الحساب من المصادقة
  DELETE FROM auth.users WHERE id = p_employee_id;
END;
$$;

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
        INSERT INTO _pd VALUES ('absence', 'attendance', v_att.id, 0, 1, round(v_daily, 2), -1, v_status,
                                COALESCE(v_att.deduction_reason, 'غياب'));
      ELSE
        -- بصمة ناقصة: لا خصم تلقائي، تنتظر قرار الإدارة (قد يكون نسياناً)
        IF v_att.check_in_time IS NULL AND v_att.check_out_time IS NOT NULL THEN
          INSERT INTO _pd VALUES ('missing_punch', 'attendance', v_att.id, 0, 0, 0, 0, NULL, 'انصراف بدون بصمة حضور');
        ELSIF v_att.check_in_time IS NOT NULL AND v_att.check_out_time IS NULL AND p_date < v_today THEN
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

CREATE OR REPLACE FUNCTION public._payroll_settle(p_event payroll_events, p_desired_signed numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_posted numeric;
  v_delta numeric;
  v_open payroll_events%ROWTYPE;
  v_target text;
  v_labels jsonb := '{"absence":"غياب","late":"تأخير","early_leave":"خروج مبكر","unpaid_leave":"إجازة بدون راتب","overtime":"ساعات إضافية","manual_deduction":"خصم","bonus":"مكافأة","paid_leave":"إجازة مدفوعة","missing_punch":"بصمة ناقصة"}';
BEGIN
  IF p_event.salary_slip_id IS NULL THEN RETURN; END IF;

  -- الأثر المُحتسب حتى الآن: الحركة الأصلية + تسوياتها المعتمدة داخل كشوف
  SELECT (CASE WHEN p_event.status = 'approved' THEN p_event.direction * p_event.amount ELSE 0 END)
       + COALESCE(sum(a.direction * a.amount) FILTER (WHERE a.salary_slip_id IS NOT NULL AND a.status = 'approved'), 0)
  INTO v_posted
  FROM payroll_events a
  WHERE a.adjusts_event_id = p_event.id;
  v_posted := COALESCE(v_posted, CASE WHEN p_event.status = 'approved' THEN p_event.direction * p_event.amount ELSE 0 END);

  v_delta := round(p_desired_signed - v_posted, 2);

  SELECT * INTO v_open FROM payroll_events
  WHERE adjusts_event_id = p_event.id AND salary_slip_id IS NULL AND status <> 'void'
  LIMIT 1;

  IF v_delta = 0 THEN
    IF v_open.id IS NOT NULL THEN
      UPDATE payroll_events SET status = 'void', updated_at = now() WHERE id = v_open.id;
    END IF;
    RETURN;
  END IF;

  IF v_open.id IS NOT NULL THEN
    UPDATE payroll_events
    SET amount = abs(v_delta), direction = sign(v_delta)::smallint, updated_at = now()
    WHERE id = v_open.id;
  ELSE
    v_target := public.payroll_target_month(p_event.employee_id, p_event.payroll_month);
    INSERT INTO payroll_events (employee_id, event_date, event_type, minutes, days, amount, direction, payroll_month,
                                carried_from, status, source, adjusts_event_id, daily_rate, minute_rate, notes)
    VALUES (p_event.employee_id, p_event.event_date, 'adjustment', p_event.minutes, p_event.days, abs(v_delta),
            sign(v_delta)::smallint, v_target, p_event.payroll_month, 'approved', 'carry_over', p_event.id,
            p_event.daily_rate, p_event.minute_rate,
            format('تسوية %s بتاريخ %s بعد اعتماد مسير %s',
                   COALESCE(v_labels ->> p_event.event_type, p_event.event_type), p_event.event_date, p_event.payroll_month));
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.payroll_employee_summary(p_employee_id uuid, p_month text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
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
  v_ev record;
  v_loans numeric;
  v_slip salary_slips%ROWTYPE;
  v_exit_balance numeric := 0;
BEGIN
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  v_month_basic := public.payroll_basic_salary(p_employee_id, p_month);
  v_daily := v_month_basic / 30;

  v_from := GREATEST(v_p.start_date, COALESCE(v_emp.join_date, v_p.start_date));
  v_to := LEAST(v_p.cutoff_date, COALESCE(v_emp.termination_date, v_p.cutoff_date));
  v_period_days := v_p.cutoff_date - v_p.start_date + 1;
  v_employed_days := GREATEST(v_to - v_from + 1, 0);
  -- فترة كاملة = الراتب كاملاً؛ جزئية (مباشرة/انتهاء خدمة) = أجر اليوم × الأيام (بحد 30)
  v_basic := CASE WHEN v_employed_days >= v_period_days THEN v_month_basic
                  ELSE round(v_daily * LEAST(v_employed_days, 30)) END;

  SELECT
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = 1), 0) AS earnings,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = -1), 0) AS deductions,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = -1 AND event_type IN ('absence', 'late', 'early_leave', 'unpaid_leave')), 0) AS attendance_deductions,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND event_type = 'overtime'), 0) AS overtime,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND event_type = 'bonus'), 0) AS bonuses,
    count(*) FILTER (WHERE status = 'pending' AND event_type <> 'missing_punch') AS pending,
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

  SELECT * INTO v_slip FROM salary_slips WHERE employee_id = p_employee_id AND work_month = p_month;

  RETURN jsonb_build_object(
    'employee_id', p_employee_id,
    'period_days', v_period_days,
    'employed_days', v_employed_days,
    'monthly_salary', v_month_basic,
    'daily_rate', round(v_daily, 4),
    'minute_rate', round(v_daily / public.payroll_shift_minutes(p_employee_id), 6),
    'shift_minutes', public.payroll_shift_minutes(p_employee_id),
    'basic', v_basic,
    'earnings', round(v_ev.earnings),
    'bonuses', round(v_ev.bonuses),
    'overtime', round(v_ev.overtime),
    'deductions', round(v_ev.deductions),
    'attendance_deductions', round(v_ev.attendance_deductions),
    'loans', v_loans,
    -- التقريب لأقرب دينار على المجموع (لا يوم بيوم)
    'net', v_basic + round(v_ev.earnings) - round(v_ev.deductions) - v_loans,
    'loan_balance_after_exit', v_exit_balance,
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
$$;

CREATE OR REPLACE FUNCTION public.approve_payroll_slip(
  p_employee_id uuid,
  p_month text,
  p_adjustments jsonb DEFAULT '[]'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_sum jsonb;
  v_slip uuid;
  v_adj jsonb;
BEGIN
  PERFORM public.require_admin();
  v_p := public.ensure_payroll_period(p_month);
  IF v_p.status <> 'open' OR EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month) THEN
    RAISE EXCEPTION 'مسير % مغلق. أعد فتحه أولاً.', p_month USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = p_employee_id AND work_month = p_month) THEN
    RAISE EXCEPTION 'تم صرف الراتب مسبقاً لهذا الموظف في هذا الشهر.' USING ERRCODE = '23505';
  END IF;

  PERFORM public.sync_payroll_period(p_month, p_employee_id);

  -- تعديلات يدوية وقت الاعتماد (مكافأة/خصم إضافي بسبب)
  FOR v_adj IN SELECT * FROM jsonb_array_elements(COALESCE(p_adjustments, '[]'::jsonb)) LOOP
    CONTINUE WHEN COALESCE((v_adj ->> 'amount')::numeric, 0) <= 0;
    INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, status, source, notes, created_by)
    VALUES (p_employee_id, v_p.cutoff_date,
            CASE WHEN v_adj ->> 'type' = 'bonus' THEN 'bonus' ELSE 'manual_deduction' END,
            round((v_adj ->> 'amount')::numeric),
            CASE WHEN v_adj ->> 'type' = 'bonus' THEN 1 ELSE -1 END,
            p_month, 'approved', 'approval', v_adj ->> 'reason', auth.uid());
  END LOOP;

  v_sum := public.payroll_employee_summary(p_employee_id, p_month);

  INSERT INTO salary_slips (employee_id, work_month, basic_salary, allowances, deductions, loans_deduction, net_salary, status, computed_by_engine)
  VALUES (p_employee_id, p_month, (v_sum ->> 'basic')::numeric, (v_sum ->> 'earnings')::numeric,
          (v_sum ->> 'deductions')::numeric, (v_sum ->> 'loans')::numeric, (v_sum ->> 'net')::numeric, 'published', true)
  RETURNING id INTO v_slip;

  INSERT INTO salary_slip_lines (salary_slip_id, event_id, line_type, event_date, minutes, days, amount, direction, notes, carried_from)
  SELECT v_slip, pe.id, pe.event_type, pe.event_date, pe.minutes, pe.days, pe.amount, pe.direction, pe.notes, pe.carried_from
  FROM payroll_events pe
  WHERE pe.employee_id = p_employee_id AND pe.payroll_month = p_month AND pe.status = 'approved'
    AND (pe.amount > 0 OR pe.event_type = 'paid_leave');

  INSERT INTO salary_slip_lines (salary_slip_id, line_type, event_date, amount, direction, notes)
  SELECT v_slip, 'loan', li.due_date, li.amount, -1, 'قسط سلفة'
  FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  UPDATE payroll_events SET salary_slip_id = v_slip, updated_at = now()
  WHERE employee_id = p_employee_id AND payroll_month = p_month AND status = 'approved';

  UPDATE loan_installments li
  SET is_paid = true, paid_at = now(), paid_by_slip_id = v_slip
  FROM loans l
  WHERE li.loan_id = l.id AND l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  RETURN v_slip;
END;
$$;

CREATE OR REPLACE FUNCTION public.decide_payroll_event(p_event_id uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS payroll_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  e payroll_events%ROWTYPE;
  v_att_id uuid;
  v_branch uuid;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'ignored' END;
  v_labels jsonb := '{"absence":"غياب","late":"تأخير","early_leave":"خروج مبكر","missing_punch":"بصمة ناقصة","overtime":"ساعات إضافية"}';
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

  -- الغياب والتأخير قرارهما محفوظ في سجل الحضور أيضاً (للتوافق مع الشاشات)
  IF e.event_type IN ('absence', 'late') THEN
    IF e.source = 'no_record' THEN
      SELECT branch_id INTO v_branch FROM employees WHERE id = e.employee_id;
      IF v_branch IS NULL THEN
        RAISE EXCEPTION 'الموظف غير مرتبط بفرع، يرجى ربطه بفرع أولاً.' USING ERRCODE = '22023';
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

  IF e.salary_slip_id IS NULL THEN
    UPDATE payroll_events
    SET status = v_status, decision_reason = NULLIF(btrim(p_reason), ''), decided_by = auth.uid(), decided_at = now(),
        payroll_month = CASE
          WHEN EXISTS (SELECT 1 FROM payroll_periods WHERE period_month = e.payroll_month AND status = 'open')
               AND NOT EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = e.employee_id AND work_month = e.payroll_month)
            THEN e.payroll_month
          ELSE public.payroll_target_month(e.employee_id, e.payroll_month) END,
        updated_at = now()
    WHERE id = e.id
    RETURNING * INTO e;
  ELSE
    UPDATE payroll_events SET decision_reason = NULLIF(btrim(p_reason), ''), decided_by = auth.uid(), decided_at = now()
    WHERE id = e.id;
    PERFORM public._payroll_settle(e, CASE WHEN p_approve THEN e.direction * e.amount ELSE 0 END);
  END IF;

  IF e.event_type <> 'missing_punch' THEN
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
                   CASE WHEN p_approve AND e.amount > 0 THEN format(' بمبلغ %s د.ع', to_char(e.amount, 'FM999,999,999')) ELSE '' END,
                   CASE WHEN NULLIF(btrim(p_reason), '') IS NOT NULL THEN '. السبب: ' || btrim(p_reason) ELSE '' END),
            'attendance');
  END IF;
  RETURN e;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_pending_payroll_decisions()
RETURNS TABLE (
  id uuid, employee_id uuid, full_name text, branch_id uuid, branch_name text, event_date date, event_type text,
  minutes numeric, days numeric, amount numeric, direction smallint, payroll_month text, carried_from text,
  status text, source text, source_id uuid, notes text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  v_month text;
BEGIN
  PERFORM public.require_admin_or_manager();
  FOR v_month IN SELECT period_month FROM payroll_periods WHERE status = 'open' LOOP
    PERFORM public.sync_payroll_period(v_month);
  END LOOP;
  PERFORM public.sync_payroll_period(public.payroll_natural_month((now() AT TIME ZONE public.company_timezone())::date));

  RETURN QUERY
  SELECT pe.id, pe.employee_id, e.full_name, e.branch_id, b.name, pe.event_date, pe.event_type, pe.minutes, pe.days,
         pe.amount, pe.direction, pe.payroll_month, pe.carried_from, pe.status, pe.source, pe.source_id, pe.notes
  FROM payroll_events pe
  JOIN employees e ON e.id = pe.employee_id
  LEFT JOIN branches b ON b.id = e.branch_id
  JOIN payroll_periods p ON p.period_month = pe.payroll_month AND p.status = 'open'
  WHERE pe.status = 'pending'
    AND (public.is_admin() OR (pe.employee_id <> auth.uid() AND public.payroll_same_branch(pe.employee_id)))
    AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch', 'overtime')
  ORDER BY pe.event_date DESC, e.full_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_and_send_attendance_reminders(p_now timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_local    timestamp := p_now AT TIME ZONE public.company_timezone();
  v_today    date := v_local::date;
  v_dow      integer := EXTRACT(DOW FROM v_local)::integer;
  v_emp      record;
  v_sched    work_schedules%ROWTYPE;
  v_att      attendance%ROWTYPE;
  v_has_att  boolean;
  v_start    timestamp;
  v_end      timestamp;
  v_after    interval;
  v_kind     text;
  v_title    text;
  v_body     text;
  v_sent     integer := 0;
BEGIN
  IF EXISTS (SELECT 1 FROM official_holidays WHERE holiday_date = v_today) THEN
    RETURN 0; -- عطلة رسمية
  END IF;

  FOR v_emp IN SELECT id, full_name FROM employees WHERE is_active LOOP
    SELECT * INTO v_sched FROM public.get_effective_work_schedule(v_emp.id) LIMIT 1;
    CONTINUE WHEN NOT FOUND;
    CONTINUE WHEN v_sched.check_in_time IS NULL OR v_sched.check_out_time IS NULL;
    CONTINUE WHEN v_sched.work_days IS NOT NULL AND NOT (v_dow = ANY (v_sched.work_days));

    -- لا تذكير لمن عنده إجازة يومية معتمدة تشمل اليوم
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM leave_requests lr
      WHERE lr.employee_id = v_emp.id AND lr.status = 'approved'
        AND NOT COALESCE(lr.is_hourly, false)
        AND v_today BETWEEN (lr.start_date AT TIME ZONE public.company_timezone())::date
                        AND (lr.end_date AT TIME ZONE public.company_timezone())::date
    );

    SELECT * INTO v_att FROM attendance WHERE employee_id = v_emp.id AND work_date = v_today;
    v_has_att := FOUND;

    v_start := v_today + v_sched.check_in_time;
    v_end   := v_today + v_sched.check_out_time;
    IF v_end <= v_start THEN v_end := v_end + interval '1 day'; END IF;  -- دوام يعبر منتصف الليل
    v_after := make_interval(mins => COALESCE(v_sched.reminder_minutes_after, 5));

    v_kind := NULL;
    IF NOT v_has_att OR v_att.check_in_time IS NULL THEN
      IF v_local >= v_start - interval '15 minutes' AND v_local < v_start - interval '13 minutes' THEN
        v_kind := 'checkin_soon';
        v_title := '⏰ الدوام يبدأ خلال 15 دقيقة';
        v_body := format('مرحباً %s، دوامك يبدأ الساعة %s. لا تنسَ تسجيل الحضور.',
                         v_emp.full_name, to_char(v_sched.check_in_time, 'HH12:MI AM'));
      ELSIF v_local >= v_start + v_after AND v_local < v_start + v_after + interval '2 minutes' THEN
        v_kind := 'checkin_late';
        v_title := '⚠️ لم تسجّل الحضور بعد';
        v_body := format('بدأ الدوام الساعة %s ولم يُسجَّل حضورك. سجّل بصمة الحضور الآن.',
                         to_char(v_sched.check_in_time, 'HH12:MI AM'));
      END IF;
    ELSIF v_att.check_out_time IS NULL THEN
      IF v_local >= v_end - interval '15 minutes' AND v_local < v_end - interval '13 minutes' THEN
        v_kind := 'checkout_soon';
        v_title := '🔔 الدوام ينتهي خلال 15 دقيقة';
        v_body := format('ينتهي دوامك الساعة %s. لا تنسَ تسجيل الانصراف قبل المغادرة.',
                         to_char(v_sched.check_out_time, 'HH12:MI AM'));
      ELSIF v_local >= v_end + v_after AND v_local < v_end + v_after + interval '2 minutes' THEN
        v_kind := 'checkout_late';
        v_title := '⚠️ لم تسجّل الانصراف';
        v_body := format('انتهى دوامك الساعة %s ولم يُسجَّل انصرافك. سجّل بصمة الانصراف الآن.',
                         to_char(v_sched.check_out_time, 'HH12:MI AM'));
      END IF;
    END IF;

    CONTINUE WHEN v_kind IS NULL;

    INSERT INTO attendance_reminder_log (employee_id, work_date, kind)
    VALUES (v_emp.id, v_today, v_kind)
    ON CONFLICT DO NOTHING;
    CONTINUE WHEN NOT FOUND;

    INSERT INTO notifications (employee_id, title, body, type)
    VALUES (v_emp.id, v_title, v_body, 'attendance');
    v_sent := v_sent + 1;
  END LOOP;

  -- تنظيف السجل القديم
  DELETE FROM attendance_reminder_log WHERE work_date < v_today - 7;

  RETURN v_sent;
END;
$$;

CREATE OR REPLACE FUNCTION public.safe_delete_employee(p_employee_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_role TEXT;
  v_target_role TEXT;
BEGIN
  -- التحقق من هوية المستدعي (يجب ألا يكون فارغاً ويجب أن يكون أدمن أو مدير)
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح: يجب تسجيل الدخول لتنفيذ هذا الإجراء.';
  END IF;

  SELECT role INTO v_caller_role FROM public.employees WHERE id = v_caller_id;
  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'manager') THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية. يجب أن تكون مديراً أو مشرفاً عاماً.';
  END IF;

  -- التحقق من وجود الموظف ومعرفة دوره
  SELECT role INTO v_target_role FROM public.employees WHERE id = p_employee_id;
  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'الموظف المطلوب غير موجود في النظام.';
  END IF;

  -- حماية حسابات الأدمن: لا يمكن لغير الأدمن حذف حساب أدمن
  IF v_target_role = 'admin' AND v_caller_role != 'admin' THEN
    RAISE EXCEPTION 'غير مصرح: لا يمكن لمدير عادي حذف حساب مسؤول نظام (Admin).';
  END IF;

  PERFORM public._anonymize_employee(p_employee_id);

END;
$$;

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
    'تنبيه: سيتم حذف حساب الموظف (' || full_name || ') وإخفاء بياناته الشخصية (تبقى سجلاته المالية) في تاريخ ' || TO_CHAR(scheduled_deletion_date, 'YYYY-MM-DD') || '.',
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
    -- لا يُحذف صف الموظف: الحذف كان يمسح كشوف رواتبه وسلفه وحضوره (ON DELETE CASCADE)
    PERFORM public._anonymize_employee(archive_record.employee_id);
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

-- ---------------------------------------------------------------------
-- تحديث حركات يوم العطلة عند إضافتها أو حذفها
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_payroll_holiday()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp record;
  v_day date := COALESCE(NEW.holiday_date, OLD.holiday_date);
BEGIN
  FOR v_emp IN SELECT id FROM employees WHERE is_active OR termination_date IS NOT NULL LOOP
    PERFORM public.sync_payroll_day(v_emp.id, v_day);
  END LOOP;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_payroll_holiday ON public.official_holidays;
CREATE TRIGGER trg_payroll_holiday
AFTER INSERT OR DELETE ON public.official_holidays
FOR EACH ROW EXECUTE FUNCTION public.trg_payroll_holiday();

-- ---------------------------------------------------------------------
-- الصلاحيات: المكافآت والخصومات للأدمن، والمدير يقرأ حركات فرعه فقط
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "Admins and managers can manage bonuses/deductions" ON public.bonuses_deductions;
DROP POLICY IF EXISTS "Admins manage bonuses/deductions" ON public.bonuses_deductions;
CREATE POLICY "Admins manage bonuses/deductions" ON public.bonuses_deductions TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Managers read branch bonuses/deductions" ON public.bonuses_deductions;
CREATE POLICY "Managers read branch bonuses/deductions" ON public.bonuses_deductions FOR SELECT TO authenticated
  USING (public.is_manager() AND public.payroll_same_branch(employee_id));

DROP POLICY IF EXISTS "Admins and managers read payroll events" ON public.payroll_events;
CREATE POLICY "Admins and managers read payroll events" ON public.payroll_events FOR SELECT TO authenticated
  USING (public.is_admin() OR employee_id = auth.uid() OR (public.is_manager() AND public.payroll_same_branch(employee_id)));

REVOKE EXECUTE ON FUNCTION public._anonymize_employee(uuid), public.payroll_hourly_leave_overlap(uuid, date, numeric, numeric),
  public.payroll_legacy_slip(uuid, text, date), public.trg_payroll_holiday()
FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.payroll_same_branch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.payroll_same_branch(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- قيود القيم (NOT VALID ثم التحقق إن كانت البيانات الحالية سليمة)
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_bd_amount_positive') THEN
    ALTER TABLE public.bonuses_deductions ADD CONSTRAINT chk_bd_amount_positive CHECK (amount > 0) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_employees_salary_non_negative') THEN
    ALTER TABLE public.employees ADD CONSTRAINT chk_employees_salary_non_negative
      CHECK (monthly_salary_iqd >= 0 AND (future_salary_iqd IS NULL OR future_salary_iqd >= 0)) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_loans_installment_le_amount') THEN
    ALTER TABLE public.loans ADD CONSTRAINT chk_loans_installment_le_amount CHECK (installment_amount <= amount) NOT VALID;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.bonuses_deductions WHERE amount <= 0) THEN
    ALTER TABLE public.bonuses_deductions VALIDATE CONSTRAINT chk_bd_amount_positive;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.employees WHERE monthly_salary_iqd < 0 OR future_salary_iqd < 0) THEN
    ALTER TABLE public.employees VALIDATE CONSTRAINT chk_employees_salary_non_negative;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.loans WHERE installment_amount > amount) THEN
    ALTER TABLE public.loans VALIDATE CONSTRAINT chk_loans_installment_le_amount;
  END IF;
END $$;
