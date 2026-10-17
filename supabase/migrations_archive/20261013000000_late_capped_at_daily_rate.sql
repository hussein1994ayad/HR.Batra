-- =====================================================================
-- خصم التأخير ما يتجاوز أجر يوم واحد.
-- التأخير ينحسب بالدقيقة من بداية الدوام، وإذا الموظف بصم بعد نهاية الدوام (مثلاً 10 بالليل ودوامه 9–2) كان يطلع
-- «تأخير 13 ساعة» بخصم مقترح أكثر من أجر يومين ونص. هسه الخصم = الأقل بين (الدقائق × أجر الدقيقة) وأجر اليوم،
-- والدقائق تبقى مثل ما هي للعرض. المبلغ المعدّل من الإدارة (amount_override) ما يتأثر.
-- =====================================================================

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

-- الحساب تغيّر: نعيد حساب المسيرات المفتوحة (الكشوف المعتمدة ما تتغير؛ الفرق إن وجد يصير تسوية)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT period_month FROM payroll_periods WHERE status = 'open' AND start_date <= (now() AT TIME ZONE public.company_timezone())::date LOOP
    PERFORM public.sync_payroll_period(r.period_month);
  END LOOP;
END $$;
