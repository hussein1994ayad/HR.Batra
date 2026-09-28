-- =====================================================================
-- محرّك الرواتب (Payroll Engine)
--
-- القواعد المعتمدة:
--   • أجر اليوم = الراتب الشهري ÷ 30 دائماً (مهما كان عدد أيام الشهر).
--   • أجر الدقيقة = أجر اليوم ÷ دقائق دوام الموظف (من جدول دوامه، 8 ساعات افتراضياً).
--   • مسير الشهر يُقطع يوم 26: أي حركة من 1 إلى 26 تدخل مسير نفس الشهر، ومن 27
--     إلى نهاية الشهر تُرحَّل لمسير الشهر التالي. تاريخ الحركة الحقيقي لا يتغيّر.
--     (مسير تشرين الأول = 27 أيلول → 26 تشرين الأول.)
--   • التأخير يُحسب من بداية الدوام (بعد تجاوز فترة السماح).
--   • الخروج المبكر بالدقائق، والبصمة الناقصة (نسيان حضور/انصراف) لا تُخصم تلقائياً:
--     كلها تنتظر قرار الإدارة (اعتماد أو إعفاء). لا يوجد "نصف يوم" ثابت.
--   • الغياب بدون بصمة ولا إجازة ينتظر قرار الإدارة أيضاً.
--   • الساعات الإضافية معطّلة افتراضياً وتُفعَّل من الإعدادات، وتحتاج موافقة.
--   • المسير المغلق لا يتغيّر؛ أي تعديل لاحق على أيامه يصير تسوية في أول مسير مفتوح.
--
-- كل حركة تُسجَّل في payroll_events بتاريخها الحقيقي (event_date) والمسير الذي
-- تُحتسب فيه (payroll_month)، مع أجر اليوم والدقيقة وقتها للتدقيق.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 0) إعدادات سياسة الرواتب
-- ---------------------------------------------------------------------
INSERT INTO system_settings (key, value, description)
VALUES ('payroll_policy', '{}'::jsonb, 'إعدادات دورة الرواتب')
ON CONFLICT (key) DO NOTHING;

-- cycle_start_day/cycle_end_day تبقى للنسخ القديمة من الموقع (27 → 26 = نفس القاعدة)
UPDATE system_settings
SET value = value
  || jsonb_build_object(
       'cutoff_day', COALESCE((value ->> 'cutoff_day')::int, 26),
       'payment_day', COALESCE((value ->> 'payment_day')::int, 30),
       'overtime_enabled', COALESCE((value ->> 'overtime_enabled')::boolean, false),
       'overtime_multiplier', COALESCE((value ->> 'overtime_multiplier')::numeric, 1),
       'overtime_min_minutes', COALESCE((value ->> 'overtime_min_minutes')::int, 30),
       -- أيام العمل بلا بصمة قبل تشغيل المحرّك لا تُعتبر غياباً (النظام كان جديداً ولم يُستعمل للبصمة)
       'no_record_from', COALESCE(value ->> 'no_record_from', to_char((now() AT TIME ZONE 'Asia/Baghdad')::date, 'YYYY-MM-DD')),
       'cycle_start_day', COALESCE((value ->> 'cutoff_day')::int, 26) + 1,
       'cycle_end_day', COALESCE((value ->> 'cutoff_day')::int, 26)
     )
WHERE key = 'payroll_policy';

CREATE OR REPLACE FUNCTION public.payroll_policy()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT value FROM system_settings WHERE key = 'payroll_policy'), '{}'::jsonb);
$$;


-- ---------------------------------------------------------------------
-- 1) تاريخ انتهاء الخدمة (للكشف الأخير)
-- ---------------------------------------------------------------------
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS termination_date date;
COMMENT ON COLUMN public.employees.termination_date IS 'آخر يوم خدمة؛ يُضبط تلقائياً عند تعطيل الحساب. يدخل الموظف في مسير الفترة التي فيها هذا اليوم.';

CREATE OR REPLACE FUNCTION public.set_termination_date()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF COALESCE(OLD.is_active, true) AND NOT COALESCE(NEW.is_active, true) AND NEW.termination_date IS NULL THEN
    NEW.termination_date := (now() AT TIME ZONE public.company_timezone())::date;
  ELSIF NOT COALESCE(OLD.is_active, true) AND COALESCE(NEW.is_active, true) THEN
    NEW.termination_date := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_termination_date ON public.employees;
CREATE TRIGGER trg_set_termination_date
BEFORE UPDATE OF is_active ON public.employees
FOR EACH ROW EXECUTE FUNCTION public.set_termination_date();


-- ---------------------------------------------------------------------
-- 2) المسيرات
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payroll_periods (
  period_month   text PRIMARY KEY CHECK (period_month ~ '^\d{4}-\d{2}$'),
  start_date     date NOT NULL,
  cutoff_date    date NOT NULL,
  payment_date   date NOT NULL,
  status         text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  closed_at      timestamptz,
  closed_by      uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  reopened_at    timestamptz,
  reopened_by    uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  reopen_reason  text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CHECK (cutoff_date >= start_date)
);
ALTER TABLE public.payroll_periods ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated read payroll periods" ON public.payroll_periods;
CREATE POLICY "Authenticated read payroll periods" ON public.payroll_periods FOR SELECT TO authenticated USING (true);
COMMENT ON TABLE public.payroll_periods IS 'مسيرات الرواتب: من اليوم التالي لقطع الشهر السابق حتى يوم القطع (26) من الشهر.';

CREATE OR REPLACE FUNCTION public.payroll_month_add(p_month text, p_n integer)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT to_char((p_month || '-01')::date + make_interval(months => p_n), 'YYYY-MM');
$$;

-- يُنشئ مسير الشهر (والمسيرات قبله حتى أول مسير) إن لم يكن موجوداً
CREATE OR REPLACE FUNCTION public.ensure_payroll_period(p_month text)
RETURNS payroll_periods
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row payroll_periods%ROWTYPE;
  v_prev payroll_periods%ROWTYPE;
  v_first text;
  v_first_day date := (p_month || '-01')::date;
  v_last int := EXTRACT(DAY FROM (v_first_day + interval '1 month - 1 day'))::int;
  v_policy jsonb := public.payroll_policy();
  v_cutoff int := LEAST(COALESCE((v_policy ->> 'cutoff_day')::int, 26), v_last);
  v_pay int := LEAST(COALESCE((v_policy ->> 'payment_day')::int, 30), v_last);
  v_start date;
BEGIN
  SELECT * INTO v_row FROM payroll_periods WHERE period_month = p_month;
  IF FOUND THEN RETURN v_row; END IF;

  SELECT min(period_month) INTO v_first FROM payroll_periods;
  IF v_first IS NULL THEN
    v_start := v_first_day;                       -- أول مسير في النظام يبدأ من أول الشهر
  ELSIF p_month < v_first THEN
    RAISE EXCEPTION 'هذا الشهر قبل بداية نظام المسيرات (%).', v_first USING ERRCODE = '22023';
  ELSE
    v_prev := public.ensure_payroll_period(public.payroll_month_add(p_month, -1));
    v_start := v_prev.cutoff_date + 1;
  END IF;

  INSERT INTO payroll_periods (period_month, start_date, cutoff_date, payment_date)
  VALUES (p_month, v_start, make_date(EXTRACT(YEAR FROM v_first_day)::int, EXTRACT(MONTH FROM v_first_day)::int, v_cutoff),
          make_date(EXTRACT(YEAR FROM v_first_day)::int, EXTRACT(MONTH FROM v_first_day)::int, v_pay))
  ON CONFLICT (period_month) DO NOTHING
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    SELECT * INTO v_row FROM payroll_periods WHERE period_month = p_month;
  END IF;
  RETURN v_row;
END;
$$;

-- أول مسير: أيلول 2026 (1 → 26 أيلول). ما قبله كُشوف قديمة محسوبة بالطريقة السابقة.
INSERT INTO public.payroll_periods (period_month, start_date, cutoff_date, payment_date)
VALUES ('2026-09', '2026-09-01', '2026-09-26', '2026-09-30')
ON CONFLICT (period_month) DO NOTHING;

-- مسير الحركة حسب تاريخها الحقيقي (NULL إن كانت قبل أول مسير)
CREATE OR REPLACE FUNCTION public.payroll_natural_month(p_date date)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_first payroll_periods%ROWTYPE;
  v_month text := to_char(p_date, 'YYYY-MM');
  v_p payroll_periods%ROWTYPE;
BEGIN
  SELECT * INTO v_first FROM payroll_periods ORDER BY period_month LIMIT 1;
  IF NOT FOUND OR p_date < v_first.start_date THEN
    RETURN NULL;
  END IF;
  v_p := public.ensure_payroll_period(v_month);
  IF p_date <= v_p.cutoff_date THEN
    RETURN v_month;                               -- 1 → 26: مسير نفس الشهر
  END IF;
  RETURN public.payroll_month_add(v_month, 1);    -- 27 → نهاية الشهر: مسير الشهر التالي
END;
$$;

-- أول مسير متاح للموظف ابتداءً من شهر الحركة: مفتوح وليس للموظف فيه كشف معتمد
CREATE OR REPLACE FUNCTION public.payroll_target_month(p_employee_id uuid, p_natural text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_month text := p_natural;
  v_p payroll_periods%ROWTYPE;
BEGIN
  FOR i IN 1..36 LOOP
    v_p := public.ensure_payroll_period(v_month);
    IF v_p.status = 'open'
       AND NOT EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = p_employee_id AND work_month = v_month)
       AND NOT EXISTS (SELECT 1 FROM archived_months WHERE work_month = v_month) THEN
      RETURN v_month;
    END IF;
    v_month := public.payroll_month_add(v_month, 1);
  END LOOP;
  RETURN v_month;
END;
$$;

-- كشوف اعتُمدت بالطريقة القديمة (أرقام من المتصفح) داخل مسير المحرّك:
-- حركات أيامها تُعتبر محتسبة فيها (حتى لا تُخصم مرتين)، وأي تغيير لاحق يصير تسوية.
ALTER TABLE public.salary_slips ADD COLUMN IF NOT EXISTS computed_by_engine boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.payroll_legacy_slip(p_employee_id uuid, p_month text)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM salary_slips
  WHERE employee_id = p_employee_id AND work_month = p_month AND NOT computed_by_engine;
$$;


-- ---------------------------------------------------------------------
-- 3) سجل الحركات
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payroll_events (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       uuid NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  event_date        date NOT NULL,
  event_type        text NOT NULL CHECK (event_type IN (
                      'absence', 'late', 'early_leave', 'missing_punch', 'unpaid_leave', 'paid_leave',
                      'overtime', 'manual_deduction', 'bonus', 'allowance', 'advance', 'adjustment', 'other')),
  minutes           numeric(10, 2) NOT NULL DEFAULT 0,
  days              numeric(6, 2) NOT NULL DEFAULT 0,
  amount            numeric(14, 2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  direction         smallint NOT NULL CHECK (direction IN (-1, 0, 1)),
  payroll_month     text NOT NULL REFERENCES public.payroll_periods(period_month),
  carried_from      text,
  status            text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'ignored', 'void')),
  source            text NOT NULL CHECK (source IN ('attendance', 'no_record', 'leave', 'manual', 'approval', 'carry_over', 'legacy')),
  source_id         uuid,
  adjusts_event_id  uuid REFERENCES public.payroll_events(id) ON DELETE SET NULL,
  daily_rate        numeric(14, 4),
  minute_rate       numeric(14, 6),
  notes             text,
  decision_reason   text,
  decided_by        uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  decided_at        timestamptz,
  salary_slip_id    uuid REFERENCES public.salary_slips(id) ON DELETE SET NULL,
  created_by        uuid,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payroll_events_month ON public.payroll_events (payroll_month, employee_id);
CREATE INDEX IF NOT EXISTS idx_payroll_events_day ON public.payroll_events (employee_id, event_date);
CREATE INDEX IF NOT EXISTS idx_payroll_events_slip ON public.payroll_events (salary_slip_id);

ALTER TABLE public.payroll_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins and managers read payroll events" ON public.payroll_events;
CREATE POLICY "Admins and managers read payroll events" ON public.payroll_events FOR SELECT TO authenticated
  USING (public.is_admin() OR public.is_manager() OR employee_id = auth.uid());
COMMENT ON TABLE public.payroll_events IS
'كل حركة تؤثر على الراتب بتاريخها الحقيقي والمسير الذي تُحتسب فيه. تُكتب فقط عبر دوال المحرّك.';

-- تفاصيل الكشف المعتمد (نسخة ثابتة من الحركات وقت الاعتماد)
CREATE TABLE IF NOT EXISTS public.salary_slip_lines (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  salary_slip_id uuid NOT NULL REFERENCES public.salary_slips(id) ON DELETE CASCADE,
  event_id       uuid REFERENCES public.payroll_events(id) ON DELETE SET NULL,
  line_type      text NOT NULL,
  event_date     date,
  minutes        numeric(10, 2) NOT NULL DEFAULT 0,
  days           numeric(6, 2) NOT NULL DEFAULT 0,
  amount         numeric(14, 2) NOT NULL DEFAULT 0,
  direction      smallint NOT NULL,
  notes          text,
  carried_from   text
);
CREATE INDEX IF NOT EXISTS idx_salary_slip_lines_slip ON public.salary_slip_lines (salary_slip_id);
ALTER TABLE public.salary_slip_lines ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Slip lines readable by owner and admins" ON public.salary_slip_lines;
CREATE POLICY "Slip lines readable by owner and admins" ON public.salary_slip_lines FOR SELECT TO authenticated
  USING (public.is_admin() OR EXISTS (SELECT 1 FROM salary_slips s WHERE s.id = salary_slip_id AND s.employee_id = auth.uid()));

-- قيود "خصم مقابل قرار حضور" القديمة: كانت تُضاف فوق خصم الحضور نفسه (خصم مزدوج)
ALTER TABLE public.bonuses_deductions ADD COLUMN IF NOT EXISTS superseded_by_attendance boolean NOT NULL DEFAULT false;
UPDATE public.bonuses_deductions bd
SET superseded_by_attendance = true
WHERE bd.salary_slip_id IS NULL
  AND bd.type = 'deduction'
  AND NOT bd.superseded_by_attendance
  AND EXISTS (
    SELECT 1 FROM attendance a
    WHERE a.employee_id = bd.employee_id AND a.work_date = bd.issue_date
      AND a.deduction_status = 'applied' AND a.status IN ('late', 'absent')
  );


-- ---------------------------------------------------------------------
-- 4) أدوات الحساب
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_schedule(p_employee_id uuid)
RETURNS work_schedules
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT ws.*
  FROM work_schedules ws
  JOIN employees e ON e.id = p_employee_id
  WHERE ws.employee_id = e.id
     OR (ws.employee_id IS NULL AND ws.department_id IS NOT NULL AND ws.department_id = e.department_id)
     OR (ws.employee_id IS NULL AND ws.department_id IS NULL AND ws.branch_id IS NOT NULL AND ws.branch_id = e.branch_id)
  ORDER BY CASE WHEN ws.employee_id IS NOT NULL THEN 0 WHEN ws.department_id IS NOT NULL THEN 1 ELSE 2 END,
           ws.created_at DESC
  LIMIT 1;
$$;

-- الراتب الأساسي للمسير (مع الراتب المستقبلي إن حلّ موعده)
CREATE OR REPLACE FUNCTION public.payroll_basic_salary(p_employee_id uuid, p_month text)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN e.future_salary_iqd IS NOT NULL AND e.future_salary_month IS NOT NULL
         AND p_month >= substr(e.future_salary_month, 1, 7)
      THEN e.future_salary_iqd
    ELSE COALESCE(e.monthly_salary_iqd, 0)
  END
  FROM employees e WHERE e.id = p_employee_id;
$$;

CREATE OR REPLACE FUNCTION public.payroll_daily_rate(p_employee_id uuid, p_month text)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(public.payroll_basic_salary(p_employee_id, p_month), 0) / 30;
$$;

-- دقائق الدوام اليومي حسب جدول الموظف (8 ساعات إن لم يوجد جدول)
CREATE OR REPLACE FUNCTION public.payroll_shift_minutes(p_employee_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(NULLIF(public.employee_shift_hours(p_employee_id), 0), 8) * 60;
$$;

CREATE OR REPLACE FUNCTION public.payroll_local_minutes(p_ts timestamptz)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT EXTRACT(HOUR FROM (p_ts AT TIME ZONE public.company_timezone())) * 60
       + EXTRACT(MINUTE FROM (p_ts AT TIME ZONE public.company_timezone()));
$$;

CREATE OR REPLACE FUNCTION public.payroll_time_minutes(p_t time)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT EXTRACT(HOUR FROM p_t) * 60 + EXTRACT(MINUTE FROM p_t);
$$;


-- ---------------------------------------------------------------------
-- 5) مزامنة حركات يوم واحد من مصادرها (الحضور، الإجازات، غياب بلا سجل)
--    idempotent: تُستدعى من التريجرات ومن صفحة الرواتب.
-- ---------------------------------------------------------------------
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
  v_workday := EXTRACT(DOW FROM p_date)::int = ANY (COALESCE(v_sched.work_days, ARRAY[0, 1, 2, 3, 4, 6]));

  -- الحركات المطلوبة لهذا اليوم (جدول مؤقت داخل الاستدعاء)
  CREATE TEMP TABLE IF NOT EXISTS _pd (
    event_type text, source text, source_id uuid, minutes numeric, days numeric,
    amount numeric, direction smallint, status_hint text, notes text
  ) ON COMMIT DROP;
  DELETE FROM _pd;

  -- الموظف لم يباشر بعد أو انتهت خدمته: لا حركات لهذا اليوم
  IF (v_emp.join_date IS NOT NULL AND p_date < v_emp.join_date)
     OR (v_emp.termination_date IS NOT NULL AND p_date > v_emp.termination_date) THEN
    NULL;
  ELSE
    SELECT * INTO v_att FROM attendance WHERE employee_id = p_employee_id AND work_date = p_date LIMIT 1;
    v_has_att := FOUND;

    IF v_has_att THEN
      v_status := CASE v_att.deduction_status WHEN 'applied' THEN 'approved' WHEN 'ignored' THEN 'ignored' ELSE 'pending' END;

      IF v_att.status = 'absent' THEN
        INSERT INTO _pd VALUES ('absence', 'attendance', v_att.id, 0, 1, round(v_daily), -1, v_status,
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
          v_mins := floor(public.payroll_local_minutes(v_att.check_in_time) - public.payroll_time_minutes(v_sched.check_in_time));
          IF v_mins > v_grace OR (v_att.status = 'late' AND v_mins > 0) THEN
            INSERT INTO _pd VALUES ('late', 'attendance', v_att.id, v_mins, 0, round(v_mins * v_minute), -1, v_status,
                                    format('تأخير %s دقيقة', v_mins));
          END IF;
        END IF;

        IF v_att.check_out_time IS NOT NULL AND v_has_sched AND v_sched.check_out_time IS NOT NULL THEN
          -- الخروج المبكر بالدقائق (ينتظر قرار الإدارة)
          v_mins := floor(public.payroll_time_minutes(v_sched.check_out_time) - public.payroll_local_minutes(v_att.check_out_time));
          IF v_mins > v_grace THEN
            INSERT INTO _pd VALUES ('early_leave', 'attendance', v_att.id, v_mins, 0, round(v_mins * v_minute), -1, NULL,
                                    format('خروج مبكر %s دقيقة', v_mins));
          END IF;

          -- الساعات الإضافية (إن فُعّلت من الإعدادات) وتحتاج موافقة
          IF COALESCE((v_policy ->> 'overtime_enabled')::boolean, false) THEN
            v_mins := floor(public.payroll_local_minutes(v_att.check_out_time) - public.payroll_time_minutes(v_sched.check_out_time));
            IF v_mins >= COALESCE((v_policy ->> 'overtime_min_minutes')::int, 30) THEN
              INSERT INTO _pd VALUES ('overtime', 'attendance', v_att.id, v_mins, 0,
                                      round(v_mins * v_minute * COALESCE((v_policy ->> 'overtime_multiplier')::numeric, 1)), 1, NULL,
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
          INSERT INTO _pd VALUES ('unpaid_leave', 'leave', v_leave.id, 0, 1, round(v_daily), -1, 'approved', 'إجازة بدون راتب');
        END IF;
      ELSIF NOT FOUND AND v_workday AND p_date < v_today
            AND p_date >= COALESCE((v_policy ->> 'no_record_from')::date, '-infinity'::date) THEN
        -- يوم عمل بلا بصمة ولا إجازة: غياب ينتظر قرار الإدارة (لا يُخصم تلقائياً)
        INSERT INTO _pd VALUES ('absence', 'no_record', NULL, 0, 1, round(v_daily), -1, 'pending', 'يوم عمل بدون بصمة ولا إجازة');
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
        INSERT INTO _pd VALUES ('unpaid_leave', 'leave', v_leave.id, v_mins, 0, round(v_mins * v_minute), -1, 'approved', 'إجازة زمنية بدون راتب');
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
      v_legacy := public.payroll_legacy_slip(p_employee_id, v_natural);
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

-- يجعل الأثر النهائي لحركة داخل كشف معتمد = p_desired_signed، بإضافة/تعديل تسوية
-- في أول مسير مفتوح للموظف (الكشف المعتمد نفسه لا يتغيّر).
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

  v_delta := round(p_desired_signed - v_posted);

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

-- قيد مكافأة/خصم يدوي ← حركة
CREATE OR REPLACE FUNCTION public.sync_payroll_manual(p_bd_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  bd bonuses_deductions%ROWTYPE;
  e payroll_events%ROWTYPE;
  v_natural text;
  v_target text;
  v_type text;
  v_dir smallint;
  v_legacy uuid;
BEGIN
  IF current_setting('payroll.skip_sync', true) = 'on' THEN RETURN; END IF;
  SELECT * INTO e FROM payroll_events WHERE source = 'manual' AND source_id = p_bd_id AND status <> 'void' LIMIT 1;
  SELECT * INTO bd FROM bonuses_deductions WHERE id = p_bd_id;

  IF NOT FOUND OR bd.salary_slip_id IS NOT NULL OR bd.superseded_by_attendance THEN
    IF e.id IS NOT NULL THEN
      PERFORM public._payroll_settle(e, 0);
      UPDATE payroll_events SET status = 'void', updated_at = now() WHERE id = e.id AND salary_slip_id IS NULL;
    END IF;
    RETURN;
  END IF;

  v_natural := public.payroll_natural_month(bd.issue_date);
  IF v_natural IS NULL THEN RETURN; END IF;
  v_type := CASE WHEN bd.type = 'bonus' THEN 'bonus' ELSE 'manual_deduction' END;
  v_dir := CASE WHEN bd.type = 'bonus' THEN 1 ELSE -1 END;

  IF e.id IS NULL THEN
    -- قيد أُدخل قبل كشف قديم لنفس المسير = محتسب فيه؛ بعده = يُرحَّل لأول مسير مفتوح
    SELECT s.id INTO v_legacy FROM salary_slips s
    WHERE s.id = public.payroll_legacy_slip(bd.employee_id, v_natural) AND s.created_at >= bd.created_at;
    v_target := CASE WHEN v_legacy IS NOT NULL THEN v_natural ELSE public.payroll_target_month(bd.employee_id, v_natural) END;
    INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, carried_from,
                                status, source, source_id, notes, created_by, salary_slip_id)
    VALUES (bd.employee_id, bd.issue_date, v_type, abs(bd.amount), v_dir, v_target, NULLIF(v_natural, v_target),
            'approved', 'manual', bd.id, bd.reason, bd.created_by, v_legacy);
  ELSIF e.salary_slip_id IS NOT NULL THEN
    PERFORM public._payroll_settle(e, v_dir * abs(bd.amount));
  ELSE
    UPDATE payroll_events SET amount = abs(bd.amount), direction = v_dir, event_type = v_type, event_date = bd.issue_date,
                              notes = bd.reason, updated_at = now()
    WHERE id = e.id;
  END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- 6) التريجرات: أي تغيير في المصادر يحدّث الحركات تلقائياً
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_payroll_attendance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- النسخ القديمة من الموقع/التطبيق تسجّل قرار الخصم كقيد خصم منفصل + تعتمد الحضور = خصم مرتين.
  -- المحرّك يحسب الخصم من الحضور نفسه، فالقيد المكرر (نفس اليوم والسبب، أُضيف للتو) يُعلَّم.
  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.deduction_status = 'applied' AND NEW.status IN ('late', 'absent')
     AND (TG_OP = 'INSERT' OR OLD.deduction_status IS DISTINCT FROM 'applied') THEN
    UPDATE bonuses_deductions
    SET superseded_by_attendance = true
    WHERE employee_id = NEW.employee_id AND issue_date = NEW.work_date AND type = 'deduction'
      AND salary_slip_id IS NULL AND NOT superseded_by_attendance
      AND reason IS NOT DISTINCT FROM NEW.deduction_reason
      AND created_at > now() - interval '10 minutes';
  END IF;

  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM public.sync_payroll_day(OLD.employee_id, OLD.work_date);
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE')
     AND (TG_OP = 'INSERT' OR NEW.employee_id IS DISTINCT FROM OLD.employee_id OR NEW.work_date IS DISTINCT FROM OLD.work_date) THEN
    PERFORM public.sync_payroll_day(NEW.employee_id, NEW.work_date);
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_payroll_attendance ON public.attendance;
CREATE TRIGGER trg_payroll_attendance
AFTER INSERT OR UPDATE OR DELETE ON public.attendance
FOR EACH ROW EXECUTE FUNCTION public.trg_payroll_attendance();

CREATE OR REPLACE FUNCTION public.trg_payroll_leave()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r leave_requests%ROWTYPE;
  d date;
  v_from date;
  v_to date;
BEGIN
  FOREACH r IN ARRAY (CASE TG_OP WHEN 'INSERT' THEN ARRAY[NEW] WHEN 'DELETE' THEN ARRAY[OLD] ELSE ARRAY[OLD, NEW] END) LOOP
    CONTINUE WHEN r.start_date IS NULL OR r.end_date IS NULL;
    v_from := (r.start_date AT TIME ZONE public.company_timezone())::date;
    v_to := LEAST((r.end_date AT TIME ZONE public.company_timezone())::date, v_from + 92);
    d := v_from;
    WHILE d <= v_to LOOP
      PERFORM public.sync_payroll_day(r.employee_id, d);
      d := d + 1;
    END LOOP;
  END LOOP;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_payroll_leave ON public.leave_requests;
CREATE TRIGGER trg_payroll_leave
AFTER INSERT OR UPDATE OF status, start_date, end_date, is_paid, is_hourly, start_hour, end_hour OR DELETE ON public.leave_requests
FOR EACH ROW EXECUTE FUNCTION public.trg_payroll_leave();

CREATE OR REPLACE FUNCTION public.trg_payroll_manual()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.sync_payroll_manual(COALESCE(NEW.id, OLD.id));
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_payroll_manual ON public.bonuses_deductions;
CREATE TRIGGER trg_payroll_manual
AFTER INSERT OR UPDATE OR DELETE ON public.bonuses_deductions
FOR EACH ROW EXECUTE FUNCTION public.trg_payroll_manual();

-- "نصف يوم" لم يعد يُفرض عند الخروج المبكر: الحالة تبقى، والدقائق تُحسب في المحرّك
CREATE OR REPLACE FUNCTION public.keep_status_on_early_checkout()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'half_day' AND OLD.status IN ('present', 'late')
     AND OLD.check_out_time IS NULL AND NEW.check_out_time IS NOT NULL THEN
    NEW.status := OLD.status;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_keep_status_on_early_checkout ON public.attendance;
CREATE TRIGGER trg_keep_status_on_early_checkout
BEFORE UPDATE ON public.attendance
FOR EACH ROW EXECUTE FUNCTION public.keep_status_on_early_checkout();


-- ---------------------------------------------------------------------
-- 7) مزامنة مسير كامل + ملخص الموظف
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_payroll_period(p_month text, p_employee_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_p payroll_periods%ROWTYPE := public.ensure_payroll_period(p_month);
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_emp record;
  d date;
  bd record;
BEGIN
  IF v_p.status <> 'open' THEN RETURN; END IF;
  FOR v_emp IN
    SELECT id FROM employees
    WHERE (p_employee_id IS NULL OR id = p_employee_id)
      AND (join_date IS NULL OR join_date <= v_p.cutoff_date)
      AND (termination_date IS NULL OR termination_date >= v_p.start_date)
      AND (is_active OR termination_date IS NOT NULL)
  LOOP
    d := v_p.start_date;
    WHILE d <= LEAST(v_p.cutoff_date, v_today) LOOP
      PERFORM public.sync_payroll_day(v_emp.id, d);
      d := d + 1;
    END LOOP;
  END LOOP;

  FOR bd IN
    SELECT b.id FROM bonuses_deductions b
    WHERE b.issue_date BETWEEN v_p.start_date AND v_p.cutoff_date
      AND (p_employee_id IS NULL OR b.employee_id = p_employee_id)
  LOOP
    PERFORM public.sync_payroll_manual(bd.id);
  END LOOP;
END;
$$;

-- ملخص موظف في مسير: الأساسي (مع التناسب)، الحركات، الأقساط، والصافي
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
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

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
    'earnings', v_ev.earnings,
    'bonuses', v_ev.bonuses,
    'overtime', v_ev.overtime,
    'deductions', v_ev.deductions,
    'attendance_deductions', v_ev.attendance_deductions,
    'loans', v_loans,
    'net', v_basic + v_ev.earnings - v_ev.deductions - v_loans,
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


-- ---------------------------------------------------------------------
-- 8) واجهات الموقع والتطبيق (RPC)
-- ---------------------------------------------------------------------

-- مسير كامل للعرض: يزامن الحركات ثم يرجع صفاً لكل موظف
CREATE OR REPLACE FUNCTION public.get_payroll_run(p_month text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_rows jsonb;
BEGIN
  PERFORM public.require_admin();
  v_p := public.ensure_payroll_period(p_month);
  PERFORM public.sync_payroll_period(p_month);

  SELECT COALESCE(jsonb_agg(
           public.payroll_employee_summary(e.id, p_month)
             || jsonb_build_object('full_name', e.full_name, 'branch_id', e.branch_id, 'branch_name', b.name,
                                   'join_date', e.join_date, 'termination_date', e.termination_date,
                                   'is_active', e.is_active)
           ORDER BY e.full_name), '[]'::jsonb)
  INTO v_rows
  FROM employees e
  LEFT JOIN branches b ON b.id = e.branch_id
  WHERE (e.join_date IS NULL OR e.join_date <= v_p.cutoff_date)
    AND (e.termination_date IS NULL OR e.termination_date >= v_p.start_date)
    AND (e.is_active OR e.termination_date IS NOT NULL
         OR EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = e.id AND s.work_month = p_month));

  RETURN jsonb_build_object(
    'period', to_jsonb(v_p) || jsonb_build_object('archived', EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month)),
    'rows', v_rows
  );
END;
$$;

-- حركات موظف في مسير (للتفاصيل)
CREATE OR REPLACE FUNCTION public.get_payroll_events(p_month text, p_employee_id uuid DEFAULT NULL)
RETURNS SETOF payroll_events
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT pe.* FROM payroll_events pe
  WHERE (public.is_admin() OR public.is_manager() OR pe.employee_id = auth.uid())
    AND pe.payroll_month = p_month
    AND (p_employee_id IS NULL OR pe.employee_id = p_employee_id)
    AND pe.status <> 'void'
  ORDER BY pe.event_date, pe.event_type;
$$;

-- قرارات الإدارة المعلّقة (غياب، تأخير، خروج مبكر، بصمة ناقصة، إضافي) في المسيرات المفتوحة
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
    AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch', 'overtime')
  ORDER BY pe.event_date DESC, e.full_name;
END;
$$;

-- قرار: اعتماد الخصم/الإضافي أو الإعفاء منه
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
  IF e.event_type NOT IN ('absence', 'late', 'early_leave', 'missing_punch', 'overtime') THEN
    RAISE EXCEPTION 'هذه الحركة لا تحتاج قراراً.' USING ERRCODE = '22023';
  END IF;

  -- الغياب والتأخير قرارهما محفوظ في سجل الحضور أيضاً (للتوافق مع الشاشات)
  IF e.event_type IN ('absence', 'late') THEN
    IF e.source = 'no_record' THEN
      SELECT branch_id INTO v_branch FROM employees WHERE id = e.employee_id;
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

-- اعتماد كشف موظف: يحسب السيرفر كل شيء، ويحفظ التفاصيل سطراً سطراً
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
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  UPDATE payroll_events SET salary_slip_id = v_slip, updated_at = now()
  WHERE employee_id = p_employee_id AND payroll_month = p_month AND status = 'approved';

  UPDATE loan_installments li
  SET is_paid = true, paid_at = now(), paid_by_slip_id = v_slip
  FROM loans l
  WHERE li.loan_id = l.id AND l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  RETURN v_slip;
END;
$$;

-- التراجع عن كشف (المسير يجب أن يكون مفتوحاً)
CREATE OR REPLACE FUNCTION public.revert_payroll_slip(p_slip_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slip salary_slips%ROWTYPE;
  v_p payroll_periods%ROWTYPE;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_slip FROM salary_slips WHERE id = p_slip_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'كشف الراتب غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = v_slip.work_month;
  IF (FOUND AND v_p.status <> 'open') OR EXISTS (SELECT 1 FROM archived_months WHERE work_month = v_slip.work_month) THEN
    RAISE EXCEPTION 'مسير % مغلق. أعد فتحه أولاً.', v_slip.work_month USING ERRCODE = '42501';
  END IF;

  IF NOT v_slip.computed_by_engine THEN
    -- كشف قديم (أرقام من المتصفح): نفس التراجع السابق، وحركات أيامه تعود لتُحتسب
    UPDATE payroll_events SET salary_slip_id = NULL, updated_at = now() WHERE salary_slip_id = p_slip_id;
    PERFORM public.revert_salary_slip(
      p_slip_id,
      COALESCE(v_p.start_date, (v_slip.work_month || '-01')::date),
      COALESCE(v_p.cutoff_date, ((v_slip.work_month || '-01')::date + interval '1 month - 1 day')::date));
    RETURN;
  END IF;

  DELETE FROM payroll_events WHERE salary_slip_id = p_slip_id AND source = 'approval';
  UPDATE payroll_events SET salary_slip_id = NULL, updated_at = now() WHERE salary_slip_id = p_slip_id;
  UPDATE loan_installments SET is_paid = false, paid_at = NULL, paid_by_slip_id = NULL WHERE paid_by_slip_id = p_slip_id;
  DELETE FROM bonuses_deductions WHERE salary_slip_id = p_slip_id;
  DELETE FROM salary_slips WHERE id = p_slip_id;
END;
$$;

-- إغلاق المسير: كل الموظفين المستحقين لهم كشف معتمد
CREATE OR REPLACE FUNCTION public.close_payroll_period(p_month text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_missing text[];
BEGIN
  PERFORM public.require_admin();
  v_p := public.ensure_payroll_period(p_month);
  IF v_p.status = 'closed' THEN
    RETURN jsonb_build_object('success', true, 'message', 'المسير مغلق مسبقاً.');
  END IF;

  SELECT array_agg(e.full_name ORDER BY e.full_name) INTO v_missing
  FROM employees e
  WHERE (e.join_date IS NULL OR e.join_date <= v_p.cutoff_date)
    AND (e.termination_date IS NULL OR e.termination_date >= v_p.start_date)
    AND (e.is_active OR e.termination_date IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = e.id AND s.work_month = p_month);
  IF v_missing IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'لا يمكن إغلاق المسير: يوجد موظفون بدون كشف معتمد.',
                              'missing_employees', to_jsonb(v_missing));
  END IF;

  -- قرارات معلّقة لم تُحسم: تُرحَّل للمسير التالي
  UPDATE payroll_events pe
  SET payroll_month = public.payroll_month_add(p_month, 1), carried_from = COALESCE(pe.carried_from, p_month), updated_at = now()
  FROM (SELECT public.ensure_payroll_period(public.payroll_month_add(p_month, 1))) AS ensure_next
  WHERE pe.payroll_month = p_month AND pe.salary_slip_id IS NULL AND pe.status IN ('pending', 'approved');

  UPDATE payroll_periods SET status = 'closed', closed_at = now(), closed_by = auth.uid() WHERE period_month = p_month;
  RETURN jsonb_build_object('success', true, 'message', format('تم إغلاق مسير %s.', p_month));
END;
$$;

-- إعادة فتح المسير (للأدمن، مع سبب يُسجَّل للتدقيق)
CREATE OR REPLACE FUNCTION public.reopen_payroll_period(p_month text, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin();
  IF COALESCE(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'اكتب سبب إعادة فتح المسير.' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month) THEN
    RAISE EXCEPTION 'هذا الشهر مؤرشف ولا يمكن فتحه.' USING ERRCODE = '42501';
  END IF;
  UPDATE payroll_periods
  SET status = 'open', reopened_at = now(), reopened_by = auth.uid(), reopen_reason = btrim(p_reason)
  WHERE period_month = p_month AND status = 'closed';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'المسير غير موجود أو مفتوح مسبقاً.' USING ERRCODE = 'P0002';
  END IF;
  INSERT INTO audit_log (table_name, action, actor_id, new_data)
  VALUES ('payroll_periods', 'UPDATE', auth.uid(), jsonb_build_object('period_month', p_month, 'reopened', true, 'reason', btrim(p_reason)));
END;
$$;

-- ضبط سياسة الرواتب (يوم القطع، يوم الدفع، الساعات الإضافية)
CREATE OR REPLACE FUNCTION public.set_payroll_policy(
  p_cutoff_day int,
  p_payment_day int,
  p_overtime_enabled boolean,
  p_overtime_multiplier numeric DEFAULT 1,
  p_overtime_min_minutes int DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin();
  IF p_cutoff_day NOT BETWEEN 1 AND 28 THEN
    RAISE EXCEPTION 'يوم القطع يجب أن يكون بين 1 و 28.' USING ERRCODE = '22023';
  END IF;
  IF p_payment_day NOT BETWEEN 1 AND 31 THEN
    RAISE EXCEPTION 'يوم الدفع يجب أن يكون بين 1 و 31.' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_overtime_multiplier, 1) <= 0 OR COALESCE(p_overtime_min_minutes, 0) < 0 THEN
    RAISE EXCEPTION 'قيم الساعات الإضافية غير صحيحة.' USING ERRCODE = '22023';
  END IF;
  UPDATE system_settings
  SET value = value || jsonb_build_object(
    'cutoff_day', p_cutoff_day, 'payment_day', p_payment_day,
    'overtime_enabled', p_overtime_enabled, 'overtime_multiplier', COALESCE(p_overtime_multiplier, 1),
    'overtime_min_minutes', COALESCE(p_overtime_min_minutes, 30),
    'cycle_start_day', p_cutoff_day + 1, 'cycle_end_day', p_cutoff_day)
  WHERE key = 'payroll_policy';
  RETURN public.payroll_policy();
END;
$$;

-- الطريقة القديمة للاعتماد (أرقام محسوبة في المتصفح) تبقى فقط للأشهر التي قبل المحرّك.
-- أشهر المحرّك تُعتمد عبر approve_payroll_slip (السيرفر يحسب كل شيء).
ALTER FUNCTION public.approve_salary_slip(uuid, text, numeric, numeric, numeric, numeric, numeric, uuid[], jsonb)
  RENAME TO approve_salary_slip_legacy;
REVOKE EXECUTE ON FUNCTION public.approve_salary_slip_legacy(uuid, text, numeric, numeric, numeric, numeric, numeric, uuid[], jsonb)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.approve_salary_slip(
  p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric,
  p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[] DEFAULT '{}', p_adjustments jsonb DEFAULT '[]'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin();
  IF EXISTS (SELECT 1 FROM payroll_periods WHERE period_month = p_work_month) THEN
    RAISE EXCEPTION 'تم تحديث نظام الرواتب. حدّث صفحة الرواتب (Ctrl+Shift+R) ثم أعد الاعتماد.' USING ERRCODE = '42501';
  END IF;
  RETURN public.approve_salary_slip_legacy(p_employee_id, p_work_month, p_basic_salary, p_allowances, p_deductions,
                                           p_loans_deduction, p_net_salary, p_installment_ids, p_adjustments);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.approve_salary_slip(uuid, text, numeric, numeric, numeric, numeric, numeric, uuid[], jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_salary_slip(uuid, text, numeric, numeric, numeric, numeric, numeric, uuid[], jsonb) TO authenticated, service_role;


-- ---------------------------------------------------------------------
-- 9) الأرشفة تستعمل تواريخ المسير ولا تُطلق مزامنة (البند 4 مؤجل)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.safe_archive_payroll_month(
  target_month text,
  cycle_start_day int DEFAULT 25,
  cycle_end_day int DEFAULT 24
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_start date;
  v_end date;
  v_missing text[];
  v_latest timestamptz;
  v_unpaid int;
  v_att int;
  v_bd int;
  v_notif int;
BEGIN
  PERFORM public.require_admin();
  IF EXISTS (SELECT 1 FROM archived_months WHERE work_month = target_month) THEN
    RETURN json_build_object('success', false, 'error', 'هذا الشهر مؤرشف مسبقاً ولا يمكن أرشفته مرة أخرى.');
  END IF;

  SELECT * INTO v_p FROM payroll_periods WHERE period_month = target_month;
  IF FOUND THEN
    IF v_p.status <> 'closed' THEN
      RETURN json_build_object('success', false, 'error', 'أغلق المسير أولاً قبل الأرشفة.');
    END IF;
    v_start := v_p.start_date;
    v_end := v_p.cutoff_date;
  ELSE
    -- أشهر قبل المحرّك: دورة الإعدادات القديمة (البداية من الشهر السابق إن كانت بعد النهاية)،
    -- مع ضبط الأيام على طول الشهر (كان 1 → 31 يفشل في الأشهر القصيرة).
    v_end := (target_month || '-01')::date
             + (LEAST(cycle_end_day, EXTRACT(DAY FROM (target_month || '-01')::date + interval '1 month - 1 day')::int) - 1);
    IF cycle_start_day > cycle_end_day THEN
      v_start := ((target_month || '-01')::date - interval '1 month')::date
                 + (LEAST(cycle_start_day, EXTRACT(DAY FROM (target_month || '-01')::date - interval '1 day')::int) - 1);
    ELSE
      v_start := (target_month || '-01')::date + (cycle_start_day - 1);
    END IF;
  END IF;

  SELECT array_agg(e.full_name) INTO v_missing
  FROM employees e
  WHERE e.is_active AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = e.id AND s.work_month = target_month);
  IF v_missing IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن الأرشفة: يوجد موظفون بدون راتب معتمد لهذا الشهر.',
                             'missing_employees', v_missing);
  END IF;

  SELECT max(created_at) INTO v_latest FROM salary_slips WHERE work_month = target_month;
  IF v_latest IS NOT NULL AND now() - v_latest < interval '60 days' THEN
    RETURN json_build_object('success', false, 'error',
      format('لا يمكن الأرشفة بعد: يجب أن تمر 60 يوماً على آخر اعتماد (مرّ %s يوم).', EXTRACT(DAY FROM now() - v_latest)::int));
  END IF;

  SELECT count(*) INTO v_unpaid FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE li.due_date BETWEEN v_start AND v_end AND NOT li.is_paid AND l.status = 'approved';
  IF v_unpaid > 0 THEN
    RETURN json_build_object('success', false, 'error', format('لا يمكن الأرشفة: يوجد %s قسط غير مدفوع ضمن الفترة.', v_unpaid));
  END IF;

  PERFORM set_config('payroll.skip_sync', 'on', true);
  DELETE FROM attendance WHERE work_date BETWEEN v_start AND v_end;
  GET DIAGNOSTICS v_att = ROW_COUNT;
  DELETE FROM bonuses_deductions WHERE issue_date BETWEEN v_start AND v_end;
  GET DIAGNOSTICS v_bd = ROW_COUNT;
  DELETE FROM notifications WHERE created_at < now() - interval '90 days';
  GET DIAGNOSTICS v_notif = ROW_COUNT;
  PERFORM set_config('payroll.skip_sync', 'off', true);

  INSERT INTO archived_months (work_month, attendance_deleted, bd_deleted, notifications_deleted)
  VALUES (target_month, v_att, v_bd, v_notif);
  RETURN json_build_object('success', true, 'message', 'تم أرشفة شهر ' || target_month || ' بنجاح! 📦',
                           'attendance_deleted', v_att, 'bd_deleted', v_bd, 'notifications_deleted', v_notif);
END;
$$;


-- ---------------------------------------------------------------------
-- 10) الصلاحيات
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION
  public.ensure_payroll_period(text), public.payroll_natural_month(date), public.payroll_target_month(uuid, text),
  public.sync_payroll_day(uuid, date), public._payroll_settle(payroll_events, numeric), public.sync_payroll_manual(uuid),
  public.sync_payroll_period(text, uuid), public.payroll_employee_summary(uuid, text), public.payroll_schedule(uuid),
  public.payroll_basic_salary(uuid, text), public.payroll_daily_rate(uuid, text), public.payroll_shift_minutes(uuid),
  public.payroll_policy()
FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION
  public.get_payroll_run(text), public.get_payroll_events(text, uuid), public.get_pending_payroll_decisions(),
  public.decide_payroll_event(uuid, boolean, text), public.approve_payroll_slip(uuid, text, jsonb),
  public.revert_payroll_slip(uuid), public.close_payroll_period(text), public.reopen_payroll_period(text, text),
  public.set_payroll_policy(int, int, boolean, numeric, int)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.get_payroll_run(text), public.get_payroll_events(text, uuid), public.get_pending_payroll_decisions(),
  public.decide_payroll_event(uuid, boolean, text), public.approve_payroll_slip(uuid, text, jsonb),
  public.revert_payroll_slip(uuid), public.close_payroll_period(text), public.reopen_payroll_period(text, text),
  public.set_payroll_policy(int, int, boolean, numeric, int)
TO authenticated, service_role;
