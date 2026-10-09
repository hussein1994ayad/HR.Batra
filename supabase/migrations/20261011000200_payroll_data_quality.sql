-- =====================================================================
-- فحص الرواتب — المرحلة 3: جودة البيانات والغش.
--   5) بدون بصمة انصراف: خصم مقترح = دقائق الدوام بعد آخر تواجد مسجّل (تتبع أو بصمة الحضور). ما ينخصم تلقائياً:
--      الأدمن يقرر خصم أو إعفاء (نسيان)، ويطلع ضمن القرارات المعلّقة. اللي تقرر قبل يبقى مثل ما تقرر.
--  11) موظف بدون فرع: قرار غيابه كان يعلق ← فرع احتياطي، وموظف نشط لازم يكون إله فرع.
--  14) العطلة الرسمية داخل الإجازة ما تنحسب من رصيد الإجازة.
--  18) أرشفة شهر: الكشوف المطلوبة بس لمن جان بالخدمة خلال ذاك الشهر.
-- =====================================================================

-- ---------------------------------------------------------------------
-- حساب اليوم (آخر تعريف: 20260929000400_audit_fixes.sql)
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
      SET minutes = CASE WHEN e.event_type = 'missing_punch' AND e.decided_at IS NOT NULL THEN e.minutes ELSE d.minutes END,
          days = d.days,
          amount = CASE WHEN e.event_type = 'missing_punch' AND e.decided_at IS NOT NULL THEN e.amount ELSE d.amount END,
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
-- القرار على حركة (آخر تعريف: 20260929000400_audit_fixes.sql)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.decide_payroll_event(p_event_id uuid, p_approve boolean, p_reason text DEFAULT NULL::text)
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

  -- إشعار للموظف بالخصم أو باعتماد الإضافي فقط. الإعفاء (مثل: نسي البصمة وهو مداوم) بدون إشعار:
  -- الموظف ما تبلّغ بالتأخير أصلاً، والملاحظة تبقى محفوظة بالقرار (decision_reason)
  IF p_approve AND (e.event_type <> 'missing_punch' OR e.amount > 0) THEN
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
$function$;

-- ---------------------------------------------------------------------
-- ملخص راتب الموظف (آخر تعريف: 20261010000000_payroll_loans_clarity.sql)
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
  v_ev record;
  v_loans numeric;
  v_slip salary_slips%ROWTYPE;
  v_exit_balance numeric := 0;
  v_loan_items jsonb;
  v_attended int;
  v_scheduled int;
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

  SELECT count(*) INTO v_scheduled
  FROM generate_series(v_from, v_to, interval '1 day') g(d)
  WHERE EXTRACT(DOW FROM g.d)::int = ANY (COALESCE((public.payroll_schedule_at(p_employee_id, g.d::date)).work_days, ARRAY[0, 1, 2, 3, 4, 6]))
    AND NOT EXISTS (SELECT 1 FROM official_holidays h WHERE h.holiday_date = g.d::date);

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
-- أيام الإجازة اليومية (آخر تعريف: 20260928000200_leave_policy.sql)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leave_request_days(lr leave_requests)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN lr.is_hourly THEN 0::numeric
    ELSE (
      SELECT count(*)::numeric
      FROM generate_series(
        (lr.start_date AT TIME ZONE public.company_timezone())::date,
        (lr.end_date AT TIME ZONE public.company_timezone())::date,
        interval '1 day') AS d
      WHERE EXTRACT(DOW FROM d)::integer = ANY (public.employee_work_days(lr.employee_id))
        AND NOT EXISTS (SELECT 1 FROM official_holidays h WHERE h.holiday_date = d::date)
    )
  END;
$function$;

-- ---------------------------------------------------------------------
-- أرشفة شهر (آخر تعريف: 20260929000500_user_flow_fixes.sql)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.safe_archive_payroll_month(target_month text, cycle_start_day integer DEFAULT 25, cycle_end_day integer DEFAULT 24)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- بس اللي جانوا بالخدمة خلال ذاك الشهر (موظف باشر بعده ما يوقف الأرشفة)
  SELECT array_agg(e.full_name) INTO v_missing
  FROM employees e
  WHERE (e.join_date IS NULL OR e.join_date <= v_end)
    AND (e.termination_date IS NULL OR e.termination_date >= v_start)
    AND (e.is_active OR e.termination_date IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = e.id AND s.work_month = target_month);
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
$function$;

-- ---------------------------------------------------------------------
-- موظف نشط لازم يكون إله فرع (بدونه قرارات الحضور تعلق)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_employee_branch()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF COALESCE(NEW.is_active, true) AND NEW.branch_id IS NULL THEN
    RAISE EXCEPTION 'اختر فرع الموظف: كل موظف نشط لازم يكون إله فرع.' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_check_employee_branch ON public.employees;
CREATE TRIGGER trg_check_employee_branch BEFORE INSERT OR UPDATE OF branch_id, is_active ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.check_employee_branch();

-- حساب اليوم تغيّر للبصمة الناقصة: نعيد حساب المسيرات المفتوحة حتى تطلع الخصومات المقترحة
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT period_month FROM payroll_periods WHERE status = 'open' AND start_date <= (now() AT TIME ZONE public.company_timezone())::date LOOP
    PERFORM public.sync_payroll_period(r.period_month);
  END LOOP;
END $$;
