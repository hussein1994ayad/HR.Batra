-- =====================================================================
-- تنظيف آمن للبيانات القديمة (نتيجة فحص التكلفة والتنظيف):
-- (1) «تنظيف بيانات شهر» كان يرجّع خصومات الشهر المعتمدة للموظفين: حذف الحضور يشغّل إعادة حساب اليوم،
--     فالمحرّك يعتبر الخصم «ماله أصل» ويسويله تسوية بالمسير المفتوح. هسه الحذف بدون إعادة حساب.
-- (2) يوم انحذف حضوره بعد إغلاق مسيره (أرشفة أو تنظيف) ما ينعاد حسابه أبداً (payroll_day_frozen).
-- (3) سجلات النظام (سجل المهام المجدولة وردود الإشعارات) تنظف تلقائياً — كانت 90% من حجم القاعدة.
-- (4) السلفة ما تنحذف إلا إذا مسددة بالكامل (كان القفل بالشاشة بس).
-- (7) «تنظيف مسير»: معاينة بالأعداد، شروط واضحة، تنفيذ بمعاملة وحدة، وسجل (منو، متى، كم سطر).
-- الكشوف (salary_slips / salary_slip_lines) وحركات الرواتب (payroll_events) ما تنلمس بأي تنظيف.
-- =====================================================================

-- ---------------------------------------------------------------------
-- سجل عمليات التنظيف
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payroll_cleanups (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_month          text,                       -- المسير (YYYY-MM)، أو NULL لتنظيف شهر ميلادي من الإعدادات القديمة
  start_date            date NOT NULL,
  end_date              date NOT NULL,
  attendance_deleted    integer,                    -- NULL = هاي الفئة ما انطلبت بهالعملية
  tracking_deleted      integer,
  stops_deleted         integer,
  violations_deleted    integer,
  notifications_deleted integer,
  performed_by          uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  performed_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS payroll_cleanups_range_idx ON public.payroll_cleanups (start_date, end_date) WHERE attendance_deleted IS NOT NULL;
COMMENT ON TABLE public.payroll_cleanups IS 'سجل تنظيف البيانات القديمة: منو، متى، أي فترة، وكم سطر انحذف من كل فئة';

ALTER TABLE public.payroll_cleanups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS payroll_cleanups_admin_read ON public.payroll_cleanups;
CREATE POLICY payroll_cleanups_admin_read ON public.payroll_cleanups FOR SELECT TO authenticated USING (public.is_admin());
REVOKE ALL ON public.payroll_cleanups FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.payroll_cleanups FROM authenticated;
GRANT SELECT ON public.payroll_cleanups TO authenticated;

-- ---------------------------------------------------------------------
-- (2) يوم مجمّد = حضوره انحذف بعد إغلاق مسيره (تنظيف أو أرشفة)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_day_frozen(p_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM payroll_cleanups c
                 WHERE c.attendance_deleted IS NOT NULL AND p_date BETWEEN c.start_date AND c.end_date)
      OR EXISTS (SELECT 1 FROM archived_months am JOIN payroll_periods pp ON pp.period_month = am.work_month
                 WHERE p_date BETWEEN pp.start_date AND pp.cutoff_date);
$function$;
REVOKE EXECUTE ON FUNCTION public.payroll_day_frozen(date) FROM PUBLIC, anon, authenticated;

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

-- ---------------------------------------------------------------------
-- (1) تنظيف بيانات شهر ميلادي (شاشة الإعدادات القديمة): الحضور ينحذف بدون إعادة حساب
-- ---------------------------------------------------------------------
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

  -- حركة بعدها تنتظر قرار (خصم/إعفاء) لأيام هذا الشهر: تنحسم أول، حتى ما يضيع دليلها
  IF p_absences AND EXISTS (
    SELECT 1 FROM payroll_events WHERE status = 'pending' AND event_date BETWEEN v_start_date AND v_end_date
  ) THEN
    RAISE EXCEPTION 'لا يمكن حذف سجلات الحضور لهذا الشهر: اكو حركات (غياب/تأخير) بعدها تنتظر قرارك لأيام هذا الشهر. احسمها أولاً.'
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
    -- بدون إعادة حساب: حذف السطر كان يخلي المحرّك يرجّع خصومات الشهر المعتمدة للموظفين كتسوية
    PERFORM set_config('payroll.skip_sync', 'on', true);
    WITH del_att AS (
      DELETE FROM public.attendance
      WHERE work_date >= v_start_date AND work_date <= v_end_date
      RETURNING id
    )
    SELECT count(*)::integer INTO v_absent_count FROM del_att;
    PERFORM set_config('payroll.skip_sync', 'off', true);
  END IF;

  -- سجل العملية (ومنه تتجمّد أيام الحضور المحذوف)
  INSERT INTO payroll_cleanups (period_month, start_date, end_date, attendance_deleted, tracking_deleted, stops_deleted,
                                violations_deleted, notifications_deleted, performed_by)
  VALUES (NULL, v_start_date, v_end_date,
          CASE WHEN p_absences THEN v_absent_count END,
          CASE WHEN p_tracking THEN v_track_count END, CASE WHEN p_tracking THEN v_stops_count END,
          CASE WHEN p_tracking THEN v_viol_count END,
          CASE WHEN p_notifications THEN v_notif_count END, auth.uid());

  RETURN QUERY SELECT v_notif_count, v_track_count, v_stops_count, v_viol_count, v_absent_count;
END;
$function$;

-- ---------------------------------------------------------------------
-- (7) تنظيف مسير: المعاينة
--   الحضور: المسير مغلق + المسير اللي بعده مغلق (رواتبه تسلّمت) + ماكو حركة تنتظر قرار لأيامه.
--   التتبع والإشعارات: يكفي المسير مغلق (الرواتب ما تعتمد عليها بعد الإغلاق).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_cleanup_preview(p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_next payroll_periods%ROWTYPE;
  v_tz text := public.company_timezone();
  v_pending int;
  v_att_done boolean;
  v_trk_done boolean;
  v_ntf_done boolean;
  v_closed boolean;
  v_next_closed boolean;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'هذا الشهر ما إله مسير رواتب.' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_next FROM payroll_periods WHERE start_date > v_p.cutoff_date ORDER BY start_date LIMIT 1;

  v_closed := v_p.status = 'closed';
  v_next_closed := COALESCE(v_next.status = 'closed', false);
  SELECT count(*) INTO v_pending FROM payroll_events
  WHERE status = 'pending' AND event_date BETWEEN v_p.start_date AND v_p.cutoff_date;
  v_att_done := public.payroll_day_frozen(v_p.start_date) AND public.payroll_day_frozen(v_p.cutoff_date);
  v_trk_done := EXISTS (SELECT 1 FROM payroll_cleanups WHERE period_month = p_month AND tracking_deleted IS NOT NULL);
  v_ntf_done := EXISTS (SELECT 1 FROM payroll_cleanups WHERE period_month = p_month AND notifications_deleted IS NOT NULL);

  RETURN jsonb_build_object(
    'month', p_month, 'start_date', v_p.start_date, 'end_date', v_p.cutoff_date, 'status', v_p.status,
    'next_month', v_next.period_month, 'next_status', v_next.status,
    'checks', jsonb_build_object('closed', v_closed, 'next_closed', v_next_closed, 'pending_decisions', v_pending),
    'counts', jsonb_build_object(
      'attendance', (SELECT count(*) FROM attendance WHERE work_date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'tracking', (SELECT count(*) FROM location_tracking WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'stops', (SELECT count(*) FROM tracked_stops WHERE (start_time AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'violations', (SELECT count(*) FROM geofence_violations WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'notifications', (SELECT count(*) FROM notifications WHERE (created_at AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date)),
    'done', jsonb_build_object('attendance', v_att_done, 'tracking', v_trk_done, 'notifications', v_ntf_done),
    'can', jsonb_build_object(
      'attendance', v_closed AND v_next_closed AND v_pending = 0 AND NOT v_att_done,
      'tracking', v_closed,
      'notifications', v_closed),
    'history', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'at', c.performed_at, 'by', (SELECT full_name FROM employees WHERE id = c.performed_by),
               'attendance', c.attendance_deleted, 'tracking', c.tracking_deleted, 'stops', c.stops_deleted,
               'violations', c.violations_deleted, 'notifications', c.notifications_deleted) ORDER BY c.performed_at DESC)
      FROM payroll_cleanups c WHERE c.period_month = p_month), '[]'::jsonb));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.payroll_cleanup_preview(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.payroll_cleanup_preview(text) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- (7) تنظيف مسير: التنفيذ (معاملة وحدة: إذا فشل شي بالنص يتراجع كله)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_cleanup_run(p_month text, p_attendance boolean DEFAULT false,
                                                      p_tracking boolean DEFAULT false, p_notifications boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v jsonb;
  v_start date;
  v_end date;
  v_tz text := public.company_timezone();
  v_att int;
  v_trk int;
  v_stops int;
  v_viol int;
  v_ntf int;
BEGIN
  PERFORM public.require_admin();
  IF NOT (COALESCE(p_attendance, false) OR COALESCE(p_tracking, false) OR COALESCE(p_notifications, false)) THEN
    RAISE EXCEPTION 'اختار شنو ينحذف: الحضور، التتبع، أو الإشعارات.' USING ERRCODE = '22023';
  END IF;
  -- عمليتين على نفس المسير بنفس اللحظة: الثانية تنتظر الأولى وتشوف نتيجتها
  PERFORM pg_advisory_xact_lock(hashtext('payroll_cleanup_' || p_month));

  v := public.payroll_cleanup_preview(p_month);
  v_start := (v ->> 'start_date')::date;
  v_end := (v ->> 'end_date')::date;

  IF NOT (v -> 'checks' ->> 'closed')::boolean THEN
    RAISE EXCEPTION 'المسير بعده مفتوح. اعتمد الرواتب وأغلق المسير أولاً.' USING ERRCODE = '42501';
  END IF;
  IF p_attendance THEN
    IF (v -> 'done' ->> 'attendance')::boolean THEN
      RAISE EXCEPTION 'حضور هذا المسير منظّف مسبقاً.' USING ERRCODE = '42501';
    END IF;
    IF NOT (v -> 'checks' ->> 'next_closed')::boolean THEN
      RAISE EXCEPTION 'حضور هذا المسير ينحذف بعد ما تعتمد وتغلق رواتب المسير اللي بعده (%).', COALESCE(v ->> 'next_month', 'الجاي')
        USING ERRCODE = '42501';
    END IF;
    IF (v -> 'checks' ->> 'pending_decisions')::int > 0 THEN
      RAISE EXCEPTION 'اكو % حركة (غياب/تأخير) لأيام هذا المسير بعدها تنتظر قرارك. احسمها أولاً.', (v -> 'checks' ->> 'pending_decisions')
        USING ERRCODE = '42501';
    END IF;
    PERFORM set_config('payroll.skip_sync', 'on', true);
    DELETE FROM attendance WHERE work_date BETWEEN v_start AND v_end;
    GET DIAGNOSTICS v_att = ROW_COUNT;
    PERFORM set_config('payroll.skip_sync', 'off', true);
  END IF;

  IF p_tracking THEN
    DELETE FROM location_tracking WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_start AND v_end;
    GET DIAGNOSTICS v_trk = ROW_COUNT;
    DELETE FROM tracked_stops WHERE (start_time AT TIME ZONE v_tz)::date BETWEEN v_start AND v_end;
    GET DIAGNOSTICS v_stops = ROW_COUNT;
    DELETE FROM geofence_violations WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_start AND v_end;
    GET DIAGNOSTICS v_viol = ROW_COUNT;
  END IF;

  IF p_notifications THEN
    DELETE FROM notifications WHERE (created_at AT TIME ZONE v_tz)::date BETWEEN v_start AND v_end;
    GET DIAGNOSTICS v_ntf = ROW_COUNT;
  END IF;

  INSERT INTO payroll_cleanups (period_month, start_date, end_date, attendance_deleted, tracking_deleted, stops_deleted,
                                violations_deleted, notifications_deleted, performed_by)
  VALUES (p_month, v_start, v_end, v_att, v_trk, v_stops, v_viol, v_ntf, auth.uid());

  RETURN jsonb_build_object('success', true, 'month', p_month, 'attendance_deleted', v_att, 'tracking_deleted', v_trk,
                            'stops_deleted', v_stops, 'violations_deleted', v_viol, 'notifications_deleted', v_ntf);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.payroll_cleanup_run(text, boolean, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.payroll_cleanup_run(text, boolean, boolean, boolean) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- (4) السلفة ما تنحذف وعليها باقي (حذف الموظف نفسه يبقى يمسح سلفه مثل قبل)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_loan_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.status = 'approved'
     AND (COALESCE(OLD.remaining_amount, 0) > 0
          OR EXISTS (SELECT 1 FROM loan_installments li WHERE li.loan_id = OLD.id AND NOT li.is_paid))
     -- حذف الموظف نهائياً يمسح سلفه بالتسلسل: وقتها سطر الموظف ما موجود بعد
     AND EXISTS (SELECT 1 FROM employees e WHERE e.id = OLD.employee_id) THEN
    RAISE EXCEPTION 'السلفة بعدها عليها باقي (% د.ع). ما تنحذف إلا بعد تسديدها بالكامل.', to_char(COALESCE(OLD.remaining_amount, 0), 'FM999,999,999')
      USING ERRCODE = '42501';
  END IF;
  RETURN OLD;
END;
$function$;
DROP TRIGGER IF EXISTS trg_guard_loan_delete ON public.loans;
CREATE TRIGGER trg_guard_loan_delete BEFORE DELETE ON public.loans
  FOR EACH ROW EXECUTE FUNCTION public.guard_loan_delete();

-- ---------------------------------------------------------------------
-- (3) سجلات النظام: سجل المهام المجدولة (يكتب سطر كل دقيقة) وردود طلبات الإشعارات
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_system_logs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cron bigint := 0;
  v_net_truncated boolean := false;
  v_net regclass;
BEGIN
  PERFORM public.require_admin_or_system();
  IF to_regclass('cron.job_run_details') IS NOT NULL THEN
    EXECUTE $q$DELETE FROM cron.job_run_details WHERE start_time < now() - interval '7 days'$q$;
    GET DIAGNOSTICS v_cron = ROW_COUNT;
  END IF;
  -- pg_net يمسح الردود القديمة وحده (بعد 6 ساعات) بس مساحتها تبقى محجوزة: إذا كبر الجدول نفرّغه
  v_net := to_regclass('net._http_response');
  IF v_net IS NOT NULL THEN
    IF pg_total_relation_size(v_net) > 20 * 1024 * 1024 THEN
      EXECUTE 'TRUNCATE net._http_response';
      v_net_truncated := true;
    END IF;
  END IF;
  RETURN jsonb_build_object('cron_rows_deleted', v_cron, 'net_responses_truncated', v_net_truncated);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.purge_system_logs() FROM PUBLIC, anon, authenticated;

-- تفريغ أول مرة (الحذف العادي ما يرجّع المساحة للقاعدة، التفريغ يرجّعها): سجل تشغيل المهام تشخيصي بس
DO $$
BEGIN
  IF to_regclass('cron.job_run_details') IS NOT NULL THEN EXECUTE 'TRUNCATE cron.job_run_details'; END IF;
  IF to_regclass('net._http_response') IS NOT NULL THEN EXECUTE 'TRUNCATE net._http_response'; END IF;
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'ما كدرنا نفرّغ سجلات النظام (صلاحية): %', SQLERRM;
END $$;

DO $$ BEGIN PERFORM cron.unschedule('system_logs_cleanup'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule('system_logs_cleanup', '45 3 * * *', $cron$ SELECT public.purge_system_logs(); $cron$);
