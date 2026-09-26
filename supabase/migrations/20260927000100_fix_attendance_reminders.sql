-- =====================================================================
-- إصلاح تذكيرات البصمة (check_and_send_attendance_reminders)
--
-- النسخة السابقة (20260922000000) كانت تفشل كل دقيقة على القاعدة الحية:
--   cannot cast type record to jsonb   (v_schedule::JSONB)
-- وحتى بدون هذا الخطأ:
--   • تذكيرات الانصراف لا تُرسل أبداً: "v_attendance IS NOT NULL" على record
--     تكون false إذا كان أي عمود فيه NULL (و check_out_time يكون NULL).
--   • جدول الفرع يطابق أي فرع (لا يقارن branch_id)، بعكس البصمة نفسها.
--   • مفتاح منع التكرار كان يظهر للموظف داخل نص الإشعار "[checkin_soon_...]".
--   • يذكّر الموظف المجاز.
-- الآن: نفس جدول الدوام الذي تستعمله البصمة (get_effective_work_schedule)،
-- ونفس المنطقة الزمنية (company_timezone)، وسجل منفصل يمنع التكرار.
--
-- التذكيرات الأربعة (مرة واحدة لكل موظف لكل يوم):
--   checkin_soon   قبل بداية الدوام بـ 15 دقيقة، ولم يسجّل حضور
--   checkin_late   بعد بداية الدوام بـ reminder_minutes_after، ولم يسجّل حضور
--   checkout_soon  قبل نهاية الدوام بـ 15 دقيقة، سجّل حضور ولم يسجّل انصراف
--   checkout_late  بعد نهاية الدوام بـ reminder_minutes_after، ولم يسجّل انصراف
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.attendance_reminder_log (
  employee_id uuid NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  work_date   date NOT NULL,
  kind        text NOT NULL,
  sent_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (employee_id, work_date, kind)
);
ALTER TABLE public.attendance_reminder_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.attendance_reminder_log FROM anon, authenticated;
COMMENT ON TABLE public.attendance_reminder_log IS
'تذكيرات البصمة المرسلة (لمنع التكرار). تكتبها check_and_send_attendance_reminders فقط.';

DROP FUNCTION IF EXISTS public.check_and_send_attendance_reminders();

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

COMMENT ON FUNCTION public.check_and_send_attendance_reminders(timestamptz) IS
'يرسل تذكيرات البصمة حسب جدول دوام كل موظف. يُستدعى كل دقيقة من pg_cron. p_now للاختبار فقط.';

REVOKE EXECUTE ON FUNCTION public.check_and_send_attendance_reminders(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_send_attendance_reminders(timestamptz) TO service_role;
