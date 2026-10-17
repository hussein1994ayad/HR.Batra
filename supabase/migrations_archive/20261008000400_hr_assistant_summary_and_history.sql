-- =====================================================================
-- المساعد الذكي — المرحلة D:
--   1) ملخص صباحي للأدمن الساعة 10:00 بغداد (بدون ذكاء: أرقام من القاعدة، مجاني وثابت) كإشعار
--      نوع assistant_summary يوصل push بالآلية الحالية (trigger on_notification_insert). يتطفى من
--      system_settings.assistant_policy.morning_summary.
--   2) حفظ المحادثات: نص الرسائل فقط (بدون ملفات/صوت/بطاقات)، الأدمن صاحبها فقط، وتنحذف بعد 90 يوم.
-- =====================================================================

-- نوع إشعار جديد (نفس الأنواع الحالية + assistant_summary)
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  'leave', 'loan', 'bonus_deduction', 'attendance', 'salary', 'document', 'device', 'ota', 'system', 'memo', 'assistant_summary'));

INSERT INTO public.system_settings (key, value, description)
VALUES ('assistant_policy', '{"morning_summary": true}'::jsonb, 'المساعد الذكي: الملخص الصباحي للأدمن (10:00)')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------
-- نص الملخص (داخلي: يُستدعى من الإرسال المجدول ومن نسخة الأدمن أدناه)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_build_morning_summary(p_date date DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tz text := public.company_timezone();
  v_day date := COALESCE(p_date, (now() AT TIME ZONE public.company_timezone())::date);
  v_holiday text;
  v_total int; v_present int; v_late int; v_leave int; v_missing int;
  v_missing_names text[];
  v_pending int;
  v_cutoff date;
  v_lines text[] := '{}';
BEGIN
  SELECT name INTO v_holiday FROM official_holidays WHERE holiday_date = v_day LIMIT 1;

  SELECT count(*) FILTER (WHERE wd),
         count(*) FILTER (WHERE a.id IS NOT NULL AND a.status <> 'absent'),
         count(*) FILTER (WHERE a.status = 'late'),
         count(*) FILTER (WHERE lv.id IS NOT NULL),
         count(*) FILTER (WHERE (a.id IS NULL OR a.status = 'absent') AND lv.id IS NULL AND wd),
         (array_agg(e.full_name ORDER BY e.full_name) FILTER (WHERE (a.id IS NULL OR a.status = 'absent') AND lv.id IS NULL AND wd))[1:5]
    INTO v_total, v_present, v_late, v_leave, v_missing, v_missing_names
  FROM employees e
  LEFT JOIN attendance a ON a.employee_id = e.id AND a.work_date = v_day
  LEFT JOIN LATERAL (SELECT l.id FROM leave_requests l WHERE l.employee_id = e.id AND l.status = 'approved'
                       AND NOT COALESCE(l.is_hourly, false)
                       AND v_day BETWEEN (l.start_date AT TIME ZONE v_tz)::date AND (l.end_date AT TIME ZONE v_tz)::date
                     LIMIT 1) lv ON true
  CROSS JOIN LATERAL (SELECT EXTRACT(DOW FROM v_day)::int = ANY (COALESCE((public.payroll_schedule_at(e.id, v_day)).work_days,
                                                                          ARRAY[0, 1, 2, 3, 4, 6]))
                             AND v_holiday IS NULL AS wd) w
  WHERE e.is_active AND e.role <> 'admin';

  SELECT count(*) INTO v_pending FROM payroll_events WHERE status = 'pending';
  SELECT cutoff_date INTO v_cutoff FROM payroll_periods
   WHERE v_day BETWEEN start_date AND cutoff_date ORDER BY start_date LIMIT 1;

  IF v_holiday IS NOT NULL THEN
    v_lines := v_lines || ('اليوم عطلة رسمية: ' || v_holiday);
  ELSIF COALESCE(v_total, 0) = 0 THEN
    v_lines := v_lines || 'اليوم ماكو دوام مجدول.'::text;
  ELSE
    v_lines := v_lines || format('بصموا %s من %s · متأخر %s · إجازة %s · ما بصم بعد %s',
                                 v_present, v_total, v_late, v_leave, v_missing);
    IF v_missing > 0 THEN
      v_lines := v_lines || ('ما بصموا: ' || array_to_string(v_missing_names, '، ')
                             || CASE WHEN v_missing > 5 THEN format(' و%s غيرهم', v_missing - 5) ELSE '' END);
    END IF;
  END IF;
  IF v_pending > 0 THEN
    v_lines := v_lines || format('قرارات تنتظرك: %s', v_pending);
  END IF;
  IF v_cutoff IS NOT NULL THEN
    v_lines := v_lines || CASE WHEN v_cutoff = v_day THEN 'اليوم آخر يوم بفترة الرواتب.'
                               ELSE format('باقي %s يوم على قطع الرواتب (%s).', v_cutoff - v_day, to_char(v_cutoff, 'DD/MM')) END;
  END IF;

  RETURN jsonb_build_object(
    'date', v_day,
    'title', 'ملخص الصباح — ' || to_char(v_day, 'DD/MM'),
    'body', array_to_string(v_lines, E'\n'),
    'present', v_present, 'scheduled', v_total, 'late', v_late, 'on_leave', v_leave, 'not_punched', v_missing,
    'pending_decisions', v_pending, 'cutoff', v_cutoff);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.assistant_build_morning_summary(date) FROM PUBLIC, anon, authenticated;

-- نسخة الأدمن (أداة المساعد «ملخص اليوم»)
CREATE OR REPLACE FUNCTION public.assistant_morning_summary(p_date date DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  RETURN public.assistant_build_morning_summary(p_date);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.assistant_morning_summary(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assistant_morning_summary(date) TO authenticated;

-- ---------------------------------------------------------------------
-- الإرسال المجدول: إشعار واحد لكل أدمن فعّال باليوم (ما يتكرر لو انشغل مرتين)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_assistant_morning_summary()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_s jsonb;
  v_day date := (now() AT TIME ZONE public.company_timezone())::date;
  v_n int;
BEGIN
  PERFORM public.require_admin_or_system();
  IF NOT COALESCE((SELECT (value->>'morning_summary')::boolean FROM system_settings WHERE key = 'assistant_policy'), true) THEN
    RETURN 0;
  END IF;
  v_s := public.assistant_build_morning_summary(v_day);
  INSERT INTO notifications (employee_id, title, body, type)
  SELECT e.id, v_s->>'title', v_s->>'body', 'assistant_summary'
  FROM employees e
  WHERE e.role = 'admin' AND e.is_active
    AND NOT EXISTS (SELECT 1 FROM notifications n WHERE n.employee_id = e.id AND n.type = 'assistant_summary'
                      AND (n.created_at AT TIME ZONE public.company_timezone())::date = v_day);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.send_assistant_morning_summary() FROM PUBLIC, anon, authenticated;

-- تشغيل/إطفاء الملخص من التطبيق أو الموقع (أدمن فقط)
CREATE OR REPLACE FUNCTION public.assistant_set_morning_summary(p_enabled boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  INSERT INTO system_settings (key, value, description)
  VALUES ('assistant_policy', jsonb_build_object('morning_summary', p_enabled), 'المساعد الذكي: الملخص الصباحي للأدمن (10:00)')
  ON CONFLICT (key) DO UPDATE SET value = system_settings.value || jsonb_build_object('morning_summary', p_enabled);
  RETURN p_enabled;
END;
$function$;

CREATE OR REPLACE FUNCTION public.assistant_settings()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  RETURN jsonb_build_object('morning_summary',
    COALESCE((SELECT (value->>'morning_summary')::boolean FROM system_settings WHERE key = 'assistant_policy'), true));
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.assistant_set_morning_summary(boolean), public.assistant_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assistant_set_morning_summary(boolean), public.assistant_settings() TO authenticated;

-- ---------------------------------------------------------------------
-- حفظ المحادثات (نص فقط)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.assistant_conversations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    uuid NOT NULL DEFAULT auth.uid() REFERENCES public.employees(id) ON DELETE CASCADE,
  title       text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS assistant_conversations_owner_idx ON public.assistant_conversations (owner_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.assistant_messages (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  conversation_id  uuid NOT NULL REFERENCES public.assistant_conversations(id) ON DELETE CASCADE,
  role             text NOT NULL CHECK (role IN ('user', 'assistant')),
  text             text NOT NULL CHECK (char_length(text) BETWEEN 1 AND 20000),
  voice            boolean NOT NULL DEFAULT false,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS assistant_messages_conversation_idx ON public.assistant_messages (conversation_id, id);

COMMENT ON TABLE public.assistant_conversations IS 'محادثات المساعد الذكي المحفوظة (للأدمن صاحبها فقط، تنحذف بعد 90 يوم)';
COMMENT ON TABLE public.assistant_messages IS 'نص رسائل المساعد الذكي (بدون ملفات أو صوت)';

ALTER TABLE public.assistant_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assistant_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS assistant_conversations_owner ON public.assistant_conversations;
CREATE POLICY assistant_conversations_owner ON public.assistant_conversations
  FOR ALL TO authenticated
  USING (owner_id = auth.uid() AND public.is_admin())
  WITH CHECK (owner_id = auth.uid() AND public.is_admin());

DROP POLICY IF EXISTS assistant_messages_owner ON public.assistant_messages;
CREATE POLICY assistant_messages_owner ON public.assistant_messages
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.assistant_conversations c
                 WHERE c.id = conversation_id AND c.owner_id = auth.uid() AND public.is_admin()));

REVOKE ALL ON public.assistant_conversations, public.assistant_messages FROM anon;
GRANT SELECT, DELETE ON public.assistant_conversations TO authenticated;
GRANT SELECT ON public.assistant_messages TO authenticated;

-- حفظ دفعة رسائل (سؤال + جواب). بدون محادثة ← تنفتح وحدة جديدة عنوانها أول سؤال. يرجع رقم المحادثة.
CREATE OR REPLACE FUNCTION public.assistant_save_messages(p_conversation_id uuid, p_messages jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid := p_conversation_id;
  v_title text;
BEGIN
  PERFORM public.require_admin();
  IF jsonb_typeof(p_messages) IS DISTINCT FROM 'array' OR jsonb_array_length(p_messages) = 0 OR jsonb_array_length(p_messages) > 20 THEN
    RAISE EXCEPTION 'رسائل غير صالحة.';
  END IF;
  IF v_id IS NULL THEN
    SELECT left(regexp_replace(btrim(m->>'text'), '\s+', ' ', 'g'), 80) INTO v_title
    FROM jsonb_array_elements(p_messages) m WHERE m->>'role' = 'user' AND btrim(COALESCE(m->>'text', '')) <> '' LIMIT 1;
    INSERT INTO assistant_conversations (owner_id, title) VALUES (auth.uid(), COALESCE(NULLIF(v_title, ''), 'محادثة'))
    RETURNING id INTO v_id;
  ELSIF NOT EXISTS (SELECT 1 FROM assistant_conversations WHERE id = v_id AND owner_id = auth.uid()) THEN
    RAISE EXCEPTION 'المحادثة غير موجودة.';
  END IF;

  INSERT INTO assistant_messages (conversation_id, role, text, voice)
  SELECT v_id, m->>'role', left(btrim(m->>'text'), 20000), COALESCE((m->>'voice')::boolean, false)
  FROM jsonb_array_elements(p_messages) WITH ORDINALITY AS t(m, i)
  WHERE m->>'role' IN ('user', 'assistant') AND btrim(COALESCE(m->>'text', '')) <> ''
  ORDER BY i;
  UPDATE assistant_conversations SET updated_at = now() WHERE id = v_id;
  RETURN v_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.assistant_save_messages(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assistant_save_messages(uuid, jsonb) TO authenticated;

-- حذف المحادثات الأقدم من 90 يوم (pg_cron يومياً)
CREATE OR REPLACE FUNCTION public.purge_old_assistant_conversations()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_n int;
BEGIN
  PERFORM public.require_admin_or_system();
  DELETE FROM assistant_conversations WHERE updated_at < now() - interval '90 days';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.purge_old_assistant_conversations() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- الجدولة: 10:00 بغداد = 07:00 UTC؛ التنظيف 03:30 UTC
-- ---------------------------------------------------------------------
DO $$ BEGIN PERFORM cron.unschedule('assistant_morning_summary'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule('assistant_morning_summary', '0 7 * * *', $$ SELECT public.send_assistant_morning_summary(); $$);

DO $$ BEGIN PERFORM cron.unschedule('assistant_conversations_cleanup'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule('assistant_conversations_cleanup', '30 3 * * *', $$ SELECT public.purge_old_assistant_conversations(); $$);
