-- =====================================================================
-- المرحلة 5 من إصلاحات تدقيق 14/10/2026: التزامن والسرعة.
-- (PAY-007) نفس اليوم ينحسب من طلبين بنفس اللحظة (المهمة الليلية + زر الاحتساب + تعديل بصمة) = احتمال حركة خصم مكررة.
--   هسه: قفل لكل موظف ويوم (وكل قيد يدوي)، وقيود فريدة بالقاعدة تمنع الحركة الفعالة المكررة حتى لو صار شي غير متوقع.
-- (BUG-018) «احتساب الرواتب» كان يحسب الكل بطلب واحد، والقاعدة توقف طلب المستخدم بعد 8 ثواني
--   (قياس على السيرفر الحي: ~1.5 ملي ثانية لكل موظف بكل يوم = ~150 موظف بمسير كامل يوصلون الحد).
--   هسه: calculate_payroll_batch يحسب 10 موظفين بكل طلب، والموقع يكرر ويبين التقدم.
-- (BUG-013) اعتماد إجازة أطول من 92 يوم كان يحسب أول 92 يوم بس.
-- ما يتغير أي مبلغ ولا كشف.
-- =====================================================================

-- ---------------------------------------------------------------------
-- (PAY-007) القيود الفريدة: قبلها نتأكد ماكو تكرار (إذا اكو، التحديث يوقف بدون ما يحذف شي)
-- ---------------------------------------------------------------------
DO $$
DECLARE
  v_dups int;
BEGIN
  SELECT count(*) INTO v_dups FROM (
    SELECT 1 FROM public.payroll_events
    WHERE status <> 'void' AND source IN ('attendance', 'no_record', 'leave')
    GROUP BY employee_id, event_date, event_type, source, source_id HAVING count(*) > 1
    UNION ALL
    SELECT 1 FROM public.payroll_events
    WHERE status <> 'void' AND source = 'manual' AND source_id IS NOT NULL
    GROUP BY source_id HAVING count(*) > 1
    UNION ALL
    SELECT 1 FROM public.payroll_events
    WHERE status <> 'void' AND source = 'carry_over' AND salary_slip_id IS NULL AND adjusts_event_id IS NOT NULL
    GROUP BY adjusts_event_id HAVING count(*) > 1
  ) x;
  IF v_dups > 0 THEN
    RAISE EXCEPTION 'لكيت % حركة رواتب مكررة. التحديث توقف حتى تنراجع يدوياً (ما ينحذف شي تلقائياً).', v_dups;
  END IF;
END $$;

-- حركة فعالة وحدة لكل موظف ويوم ونوع ومصدر (حركات الحضور والغياب والإجازات)
CREATE UNIQUE INDEX IF NOT EXISTS uq_payroll_events_engine_day ON public.payroll_events
  (employee_id, event_date, event_type, source, COALESCE(source_id, '00000000-0000-0000-0000-000000000000'::uuid))
  WHERE status <> 'void' AND source IN ('attendance', 'no_record', 'leave');
-- حركة فعالة وحدة لكل خصم/مكافأة يدوية
CREATE UNIQUE INDEX IF NOT EXISTS uq_payroll_events_manual ON public.payroll_events (source_id)
  WHERE status <> 'void' AND source = 'manual';
-- تسوية مفتوحة وحدة لكل حركة داخل كشف معتمد
CREATE UNIQUE INDEX IF NOT EXISTS uq_payroll_events_open_adjustment ON public.payroll_events (adjusts_event_id)
  WHERE status <> 'void' AND source = 'carry_over' AND salary_slip_id IS NULL;

-- ---------------------------------------------------------------------
-- (PAY-007) حساب اليوم: قفل لكل موظف ويوم
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

  -- (PAY-007) نفس الموظف ونفس اليوم من طلبين بنفس اللحظة (المهمة الليلية + زر الاحتساب + تعديل بصمة):
  -- الثاني ينتظر الأول لحد ما يخلص، فيشوف حركته وما يضيفها مرة ثانية
  PERFORM pg_advisory_xact_lock(hashtextextended('payroll_day:' || p_employee_id::text || ':' || p_date::text, 0));

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
-- (PAY-007) الخصومات والمكافآت اليدوية: قفل لكل قيد
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_payroll_manual(p_bd_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- (PAY-007) نفس القيد من طلبين بنفس اللحظة: الثاني ينتظر
  PERFORM pg_advisory_xact_lock(hashtextextended('payroll_manual:' || p_bd_id::text, 0));
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
$function$;

-- ---------------------------------------------------------------------
-- نفس ترتيب الموظفين بكل الحلقات (حتى الأقفال ما تتعاكس بين طلبين)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_payroll_period(p_month text, p_employee_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    ORDER BY id  -- نفس الترتيب بكل مكان (الأقفال ما تتعاكس)
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
$function$;

CREATE OR REPLACE FUNCTION public.payroll_nightly()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_emp record;
  d date;
  v_n int := 0;
BEGIN
  PERFORM public.require_admin_or_system();
  PERFORM public.apply_due_salary_changes();
  IF public.payroll_natural_month(v_today) IS NULL THEN
    RETURN 0;
  END IF;
  FOR v_emp IN
    SELECT id FROM employees
    WHERE (is_active OR termination_date >= v_today - 3)
      AND (join_date IS NULL OR join_date <= v_today)
    ORDER BY id
  LOOP
    FOR d IN SELECT generate_series(v_today - 3, v_today - 1, interval '1 day')::date LOOP
      PERFORM public.sync_payroll_day(v_emp.id, d);
    END LOOP;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_payroll_holiday()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp record;
  v_day date := COALESCE(NEW.holiday_date, OLD.holiday_date);
BEGIN
  FOR v_emp IN SELECT id FROM employees WHERE is_active OR termination_date IS NOT NULL ORDER BY id LOOP
    PERFORM public.sync_payroll_day(v_emp.id, v_day);
  END LOOP;
  RETURN NULL;
END;
$function$;

-- ---------------------------------------------------------------------
-- (BUG-013) اعتماد إجازة طويلة يحسب كل أيامها اللي فاتت
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_payroll_leave()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  r leave_requests%ROWTYPE;
  d date;
  v_from date;
  v_to date;
BEGIN
  FOREACH r IN ARRAY (CASE TG_OP WHEN 'INSERT' THEN ARRAY[NEW] WHEN 'DELETE' THEN ARRAY[OLD] ELSE ARRAY[OLD, NEW] END) LOOP
    CONTINUE WHEN r.start_date IS NULL OR r.end_date IS NULL;
    v_from := (r.start_date AT TIME ZONE public.company_timezone())::date;
    -- (BUG-013) كل الأيام اللي فاتت مهما طالت الإجازة (كان أول 92 يوم بس)، والقادمة لحد 92 يوم من اليوم
    -- (الباقي ينحسب بالمهمة الليلية وقت ما يفوت، وبالاعتماد)
    v_to := LEAST((r.end_date AT TIME ZONE public.company_timezone())::date, GREATEST(v_from + 92, v_today + 92));
    d := v_from;
    WHILE d <= v_to LOOP
      PERFORM public.sync_payroll_day(r.employee_id, d);
      d := d + 1;
    END LOOP;
  END LOOP;
  RETURN NULL;
END;
$function$;

-- ---------------------------------------------------------------------
-- (BUG-018) «احتساب الرواتب» على دفعات: كل طلب يحسب p_limit موظف (بالترتيب بعد p_after)،
-- والموقع يكرر لحد finished ويبين التقدم. آخر دفعة تسجّل وقت الاحتساب.
-- نفس الموظفين ونفس الحساب اللي يسويه calculate_payroll (يبقى شغال للنسخ القديمة).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_payroll_batch(p_month text, p_after uuid DEFAULT NULL, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_limit int := CASE WHEN p_limit BETWEEN 1 AND 50 THEN p_limit ELSE 10 END;
  v_ids uuid[];
  v_id uuid;
  v_last uuid;
  v_total int;
  v_before int;
  v_finished boolean;
  bd record;
BEGIN
  PERFORM public.require_admin();
  IF p_month !~ '^\d{4}-\d{2}$' THEN
    RAISE EXCEPTION 'صيغة الشهر غير صحيحة.' USING ERRCODE = '22023';
  END IF;
  IF p_month < (SELECT min(period_month) FROM payroll_periods) THEN
    RETURN jsonb_build_object('total', 0, 'done', 0, 'last_id', NULL, 'finished', true);
  END IF;
  v_p := public.ensure_payroll_period(p_month);
  IF v_p.status <> 'open' OR EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month) THEN
    RETURN jsonb_build_object('total', 0, 'done', 0, 'last_id', NULL, 'finished', true);
  END IF;

  -- نفس شرط sync_payroll_period
  SELECT count(*), count(*) FILTER (WHERE p_after IS NOT NULL AND e.id <= p_after)
  INTO v_total, v_before
  FROM employees e
  WHERE (e.join_date IS NULL OR e.join_date <= v_p.cutoff_date)
    AND (e.termination_date IS NULL OR e.termination_date >= v_p.start_date)
    AND (e.is_active OR e.termination_date IS NOT NULL);

  SELECT array_agg(x.id ORDER BY x.id) INTO v_ids
  FROM (
    SELECT e.id FROM employees e
    WHERE (e.join_date IS NULL OR e.join_date <= v_p.cutoff_date)
      AND (e.termination_date IS NULL OR e.termination_date >= v_p.start_date)
      AND (e.is_active OR e.termination_date IS NOT NULL)
      AND (p_after IS NULL OR e.id > p_after)
    ORDER BY e.id
    LIMIT v_limit
  ) x;

  FOREACH v_id IN ARRAY COALESCE(v_ids, '{}'::uuid[]) LOOP
    PERFORM public.sync_payroll_period(p_month, v_id);
    v_last := v_id;
  END LOOP;

  v_finished := v_last IS NULL OR NOT EXISTS (
    SELECT 1 FROM employees e
    WHERE (e.join_date IS NULL OR e.join_date <= v_p.cutoff_date)
      AND (e.termination_date IS NULL OR e.termination_date >= v_p.start_date)
      AND (e.is_active OR e.termination_date IS NOT NULL)
      AND e.id > v_last);

  IF v_finished THEN
    -- مثل sync_payroll_period للكل: الخصومات والمكافآت اليدوية لموظفين برا القائمة (مثلاً معطّل بدون آخر يوم)
    FOR bd IN
      SELECT b.id FROM bonuses_deductions b JOIN employees e ON e.id = b.employee_id
      WHERE b.issue_date BETWEEN v_p.start_date AND v_p.cutoff_date
        AND NOT ((e.join_date IS NULL OR e.join_date <= v_p.cutoff_date)
                 AND (e.termination_date IS NULL OR e.termination_date >= v_p.start_date)
                 AND (e.is_active OR e.termination_date IS NOT NULL))
      ORDER BY b.id
    LOOP
      PERFORM public.sync_payroll_manual(bd.id);
    END LOOP;
    UPDATE payroll_periods SET calculated_at = now(), calculated_by = auth.uid() WHERE period_month = p_month;
  END IF;

  RETURN jsonb_build_object('total', v_total, 'done', v_before + COALESCE(array_length(v_ids, 1), 0),
                            'last_id', v_last, 'finished', v_finished);
END;
$function$;
REVOKE ALL ON FUNCTION public.calculate_payroll_batch(text, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.calculate_payroll_batch(text, uuid, integer) TO authenticated;
