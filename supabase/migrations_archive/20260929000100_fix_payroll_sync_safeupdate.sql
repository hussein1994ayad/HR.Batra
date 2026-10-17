-- =====================================================================
-- إصلاح: محرّك الرواتب فشل على Supabase برسالة "DELETE requires a WHERE clause"
--
-- Supabase يفعّل pg_safeupdate لطلبات الـ API: أي DELETE بدون WHERE يُرفض، حتى داخل
-- الدوال. sync_payroll_day كانت تفرّغ جدولها المؤقت بـ DELETE بدون شرط، فتفشل صفحة
-- الرواتب، وأي بصمة أو تعديل حضور (التريجر يستدعيها).
-- =====================================================================

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
  DELETE FROM _pd WHERE true; -- Supabase (pg_safeupdate) يرفض DELETE بدون WHERE

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
