-- =====================================================================
-- (1) مبلغ الخصم يتعدل عند القرار: الأدمن يشوف المبلغ المحسوب ويكدر يكتب غيره (بالتطبيق والموقع).
--     المبلغ المعدّل ينحفظ بـ amount_override ويبقى بعد أي إعادة حساب، وينمسح إذا القرار صار إعفاء.
-- (2) غياب اليوم قبل ما ينحسب (ماكو حركة بعد): باب واحد decide_absence_day يسجّل اليوم ويقرر عليه بنفس القواعد.
-- (3) payroll_day_rates: أجر اليوم لكل موظف (حتى يبين مبلغ غياب اليوم قبل القرار).
-- (4) «الغائبون اليوم» بلوحة التعاميم: اللي انخصم غيابهم اليوم (مثل «المتأخرون اليوم»).
-- =====================================================================

ALTER TABLE public.payroll_events ADD COLUMN IF NOT EXISTS amount_override numeric CHECK (amount_override IS NULL OR amount_override >= 0);
COMMENT ON COLUMN public.payroll_events.amount_override IS 'مبلغ كتبته الإدارة عند القرار بدل المحسوب (NULL = المحسوب). يبقى بعد إعادة الحساب';

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
            INSERT INTO _pd VALUES ('late', 'attendance', v_att.id, v_mins, 0, round(v_mins * v_minute, 2), -1, v_status,
                                    format('تأخير %s دقيقة', v_mins));
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

-- الدالة القديمة (3 مدخلات) تنحذف حتى ما يصير اسمين بنفس الاستدعاء؛ الجديدة تقبل نفس الاستدعاء القديم (المبلغ اختياري)
DROP FUNCTION IF EXISTS public.decide_payroll_event(uuid, boolean, text);

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

REVOKE EXECUTE ON FUNCTION public.decide_payroll_event(uuid, boolean, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_payroll_event(uuid, boolean, text, numeric) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- (2) قرار على غياب يوم ماله حركة بعد (غياب اليوم قبل الاحتساب): يسجّل اليوم غياب ثم يقرر بنفس باب القرارات
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.decide_absence_day(p_employee_id uuid, p_date date, p_approve boolean,
                                                     p_reason text DEFAULT NULL::text, p_amount numeric DEFAULT NULL::numeric)
 RETURNS payroll_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_event uuid;
  v_att attendance%ROWTYPE;
  v_branch uuid;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  PERFORM public.require_admin_or_manager();
  IF NOT public.is_admin() THEN
    IF p_employee_id = auth.uid() THEN
      RAISE EXCEPTION 'لا يمكنك اتخاذ قرار على حركاتك الخاصة.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.payroll_same_branch(p_employee_id) THEN
      RAISE EXCEPTION 'غير مصرح: الموظف من فرع آخر.' USING ERRCODE = '42501';
    END IF;
  END IF;
  IF p_date IS NULL OR p_date > v_today THEN
    RAISE EXCEPTION 'ما يصير قرار غياب ليوم بعده ما اجه.' USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_event FROM payroll_events
  WHERE employee_id = p_employee_id AND event_date = p_date AND event_type = 'absence' AND status <> 'void'
  ORDER BY updated_at DESC LIMIT 1;

  IF v_event IS NULL THEN
    SELECT * INTO v_att FROM attendance WHERE employee_id = p_employee_id AND work_date = p_date LIMIT 1;
    IF FOUND THEN
      IF v_att.check_in_time IS NOT NULL THEN
        RAISE EXCEPTION 'الموظف بصم بهذا اليوم، فما ينحسب غياب.' USING ERRCODE = '22023';
      END IF;
      UPDATE attendance SET status = 'absent' WHERE id = v_att.id;
    ELSE
      SELECT COALESCE(
        (SELECT branch_id FROM employees WHERE id = p_employee_id),
        (SELECT branch_id FROM employees WHERE id = auth.uid()),
        (SELECT id FROM branches ORDER BY created_at LIMIT 1)) INTO v_branch;
      IF v_branch IS NULL THEN
        RAISE EXCEPTION 'ماكو أي فرع بالنظام. أضف فرعاً أولاً.' USING ERRCODE = '22023';
      END IF;
      INSERT INTO attendance (employee_id, branch_id, work_date, status) VALUES (p_employee_id, v_branch, p_date, 'absent');
    END IF;
    -- trg_payroll_attendance حسب اليوم وطلّع حركة الغياب (إذا يوم دوام وماكو إجازة)
    SELECT id INTO v_event FROM payroll_events
    WHERE employee_id = p_employee_id AND event_date = p_date AND event_type = 'absence' AND status <> 'void'
    ORDER BY updated_at DESC LIMIT 1;
    IF v_event IS NULL THEN
      RAISE EXCEPTION 'هذا اليوم ما ينحسب بيه غياب (عطلة، إجازة معتمدة، أو خارج فترة الخدمة).' USING ERRCODE = '22023';
    END IF;
  END IF;

  RETURN public.decide_payroll_event(v_event, p_approve, p_reason, p_amount);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.decide_absence_day(uuid, date, boolean, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.decide_absence_day(uuid, date, boolean, text, numeric) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- (3) أجر اليوم لكل موظف نشط بتاريخ معيّن (الأدمن الكل، المدير فرعه) — مبلغ غياب يوم قبل القرار
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_day_rates(p_date date DEFAULT NULL::date)
 RETURNS TABLE(employee_id uuid, daily_rate numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_date date := COALESCE(p_date, (now() AT TIME ZONE public.company_timezone())::date);
  v_month text := COALESCE(public.payroll_natural_month(v_date), public.payroll_month_of(v_date));
BEGIN
  PERFORM public.require_admin_or_manager();
  RETURN QUERY
  SELECT e.id, round(public.payroll_daily_rate(e.id, v_month), 2)
  FROM employees e
  WHERE e.is_active AND (public.is_admin() OR public.payroll_same_branch(e.id));
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.payroll_day_rates(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.payroll_day_rates(date) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- (4) «الغائبون اليوم» بلوحة التعاميم: بس اللي الإدارة طبّقت خصم غيابهم اليوم (نفس قاعدة «المتأخرون اليوم»)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_absent_today()
 RETURNS TABLE(employee_id uuid, full_name text, avatar_url text, branch_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tz text := public.company_timezone();
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT e.id, e.full_name, e.avatar_url, b.name
  FROM attendance a
  JOIN employees e ON e.id = a.employee_id AND e.is_active
  LEFT JOIN branches b ON b.id = e.branch_id
  WHERE a.work_date = v_today
    AND a.status = 'absent'
    AND a.deduction_status = 'applied'   -- يظهر بس إذا الإدارة طبّقت خصم الغياب
    AND NOT EXISTS (                      -- إجازة يومية معتمدة تغطي اليوم = مو غياب
      SELECT 1 FROM leave_requests lr
      WHERE lr.employee_id = e.id AND lr.status = 'approved' AND NOT COALESCE(lr.is_hourly, false)
        AND v_today BETWEEN (lr.start_date AT TIME ZONE v_tz)::date AND (lr.end_date AT TIME ZONE v_tz)::date)
  ORDER BY e.full_name;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_absent_today() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_absent_today() TO authenticated, service_role;
