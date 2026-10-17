-- =========================================================================
-- HR Pro — ملف الأساس (المرحلة 10، تدقيق 14/10 CODE-002)
-- =========================================================================
-- القاعدة كاملة مثل ما تطلع من 95 ملف قديم (supabase/migrations_archive) — كل دالة بشكلها الأخير مرة وحدة.
-- مولّد تلقائياً: لا تعدّله. التوليد: node supabase/schema/baseline.mjs (والفحص: --check).
--
-- • للقواعد الجديدة الفارغة بس (فحوص، نسخة تجربة، نسخة احتياطية جديدة).
-- • السيرفر الحي: ينسجل كمطبّق بدون تشغيل (supabase migration repair --status applied 20261025000000).
-- • التعديلات الجاية = ملف migration جديد بعد هذا الملف، مثل قبل.
-- =========================================================================

-- القفل: إذا القاعدة موجودة يوكف وما يغير شي
DO $guard$
BEGIN
  IF to_regclass('public.employees') IS NOT NULL THEN
    RAISE EXCEPTION 'ملف الأساس للقواعد الجديدة الفارغة بس: القاعدة موجودة. سجّله كمطبّق بدل تشغيله: supabase migration repair --status applied 20261025000000';
  END IF;
END
$guard$;

-- الصلاحيات: Supabase يعطي كل جدول ودالة جديدة صلاحيات افتراضية لـ anon و authenticated و service_role،
-- و pg_dump يكتب الصلاحيات نسبةً لافتراضي Postgres الأصلي (يضيف بس، ما يشيل). فنوقف الافتراضي أثناء البناء
-- حتى كل عنصر يطلع بصلاحياته بالضبط؛ القواعد الافتراضية الأخيرة ترجع بنهاية الجزء الرئيسي (DEFAULT ACL).
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon, authenticated, service_role;

-- الإضافات (نفس الملفات القديمة؛ بـ Supabase موجودة أصلاً)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5
-- Dumped by pg_dump version 17.5

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: _anonymize_employee(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._anonymize_employee(p_employee_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth'
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


--
-- Name: _ar_time(time without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._ar_time(p_time time without time zone) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  SELECT to_char(p_time, 'FMHH12:MI') || CASE WHEN extract(hour FROM p_time) < 12 THEN ' ص' ELSE ' م' END;
$$;


--
-- Name: _cap_loans_to_net(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._cap_loans_to_net(p_employee_id uuid, p_month text) RETURNS numeric
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_deficit numeric;
  v_cut numeric;
  v_total_cut numeric := 0;
  r record;
  v_new date;
BEGIN
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  v_deficit := -((public.payroll_employee_summary(p_employee_id, p_month) ->> 'net')::numeric);
  IF v_deficit IS NULL OR v_deficit <= 0 THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT li.* FROM loan_installments li JOIN loans l ON l.id = li.loan_id
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
      AND COALESCE(l.payment_method, '') <> 'cash'
      AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date
    ORDER BY li.due_date DESC, li.id DESC
  LOOP
    EXIT WHEN v_deficit <= 0;
    -- جدول السلفة قبل التعديل: إلغاء اعتماد الراتب يرجّعه (PAY-010)
    INSERT INTO payroll_loan_caps (employee_id, payroll_month, loan_id, installments_before)
    SELECT p_employee_id, p_month, r.loan_id, COALESCE(jsonb_agg(jsonb_build_object(
             'id', x.id, 'due_date', x.due_date, 'amount', x.amount, 'amount_locked', x.amount_locked,
             'payment_note', x.payment_note, 'origin_kind', x.origin_kind, 'origin_month', x.origin_month)), '[]'::jsonb)
    FROM loan_installments x WHERE x.loan_id = r.loan_id AND NOT x.is_paid;

    v_cut := LEAST(v_deficit, r.amount);
    IF v_cut < r.amount THEN
      -- ينقص هالشهر، والنقص شهر جديد بالأخير «باقي شهر …»
      PERFORM set_config('loans.shortfall_origin', r.due_date::text, true);
      UPDATE loan_installments
      SET amount = r.amount - v_cut, amount_locked = true,
          payment_note = COALESCE(payment_note, 'نقص تلقائياً: الراتب ما يكفي')
      WHERE id = r.id;
      PERFORM set_config('loans.shortfall_origin', '', true);
    ELSE
      -- ما يبقى شي من الراتب لهالقسط: يتأجل لآخر السلفة
      SELECT (max(due_date) + interval '1 month')::date INTO v_new FROM loan_installments WHERE loan_id = r.loan_id;
      UPDATE loan_installments
      SET due_date = v_new, origin_kind = 'postponed', origin_month = COALESCE(origin_month, r.due_date), amount_locked = false,
          payment_note = COALESCE(payment_note, 'تأجيل تلقائي: الراتب ما يكفي')
      WHERE id = r.id;
    END IF;
    v_deficit := v_deficit - v_cut;
    v_total_cut := v_total_cut + v_cut;
  END LOOP;

  IF v_total_cut > 0 THEN
    INSERT INTO notifications (employee_id, title, body, type)
    VALUES (p_employee_id, 'تعديل قسط السلفة 💸',
            format('راتب شهر %s ما يكفي للقسط كامل، فانخصم أقل بـ %s د.ع والباقي انضاف بآخر السلفة.',
                   p_month, to_char(v_total_cut, 'FM999,999,999')),
            'loan');
  END IF;
  RETURN v_total_cut;
END;
$$;


--
-- Name: _insert_loan_installments(uuid, numeric, integer, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._insert_loan_installments(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  INSERT INTO loan_installments (loan_id, due_date, amount, is_paid)
  SELECT p_loan_id,
         (p_first_due + make_interval(months => g))::date,
         CASE WHEN g = p_months - 1
              THEN p_amount - floor(p_amount / p_months) * (p_months - 1)
              ELSE floor(p_amount / p_months) END,
         false
  FROM generate_series(0, p_months - 1) AS g;
$$;


--
-- Name: _loan_month_settled(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._loan_month_settled(p_employee_id uuid, p_due date) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM payroll_periods p
    WHERE p_due BETWEEN p.start_date AND p.cutoff_date
      AND (p.status = 'closed'
           OR EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = p_employee_id AND s.work_month = p.period_month)));
$$;


--
-- Name: _payroll_day_apply(uuid, date, text, numeric, numeric, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._payroll_day_apply(p_employee_id uuid, p_date date, p_natural text, p_daily numeric, p_minute numeric, p_policy jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_natural text := p_natural;
  v_daily numeric := p_daily;
  v_minute numeric := p_minute;
  v_policy jsonb := p_policy;
  v_status text;
  e payroll_events%ROWTYPE;
  d record;
  v_target text;
  v_desired_signed numeric;
  v_legacy uuid;
BEGIN
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
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: attendance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    check_in_time timestamp with time zone,
    check_out_time timestamp with time zone,
    check_in_lat double precision,
    check_in_lng double precision,
    check_out_lat double precision,
    check_out_lng double precision,
    is_mock_detected boolean DEFAULT false NOT NULL,
    status text NOT NULL,
    work_date date DEFAULT CURRENT_DATE NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    deduction_status text DEFAULT 'pending'::text,
    deduction_reason text,
    deduction_applied boolean,
    check_in_offline boolean DEFAULT false NOT NULL,
    check_out_offline boolean DEFAULT false NOT NULL,
    check_in_time_source text,
    check_out_time_source text,
    check_in_device_time timestamp with time zone,
    check_out_device_time timestamp with time zone,
    CONSTRAINT attendance_deduction_status_check CHECK ((deduction_status = ANY (ARRAY['pending'::text, 'applied'::text, 'ignored'::text]))),
    CONSTRAINT attendance_status_check CHECK ((status = ANY (ARRAY['present'::text, 'late'::text, 'absent'::text, 'half_day'::text]))),
    CONSTRAINT attendance_time_source_check CHECK ((((check_in_time_source IS NULL) OR (check_in_time_source = ANY (ARRAY['online'::text, 'offline_verified'::text, 'offline_review'::text, 'offline_reviewed'::text, 'manual'::text]))) AND ((check_out_time_source IS NULL) OR (check_out_time_source = ANY (ARRAY['online'::text, 'offline_verified'::text, 'offline_review'::text, 'offline_reviewed'::text, 'manual'::text]))))),
    CONSTRAINT chk_attendance_out_after_in CHECK (((check_out_time IS NULL) OR (check_in_time IS NULL) OR (check_out_time >= check_in_time)))
);


--
-- Name: TABLE attendance; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.attendance IS 'سجلات الدوام اليومي وحضور الموظفين مع حقول الفحص الجغرافي وكشف التزييف';


--
-- Name: COLUMN attendance.deduction_reason; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.deduction_reason IS 'سبب الخصم أو الإعفاء الذي أدخله المدير';


--
-- Name: COLUMN attendance.deduction_applied; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.deduction_applied IS 'هل تم تطبيق خصم (true) أو إعفاء (false) أو لم يتخذ قرار بعد (null)';


--
-- Name: COLUMN attendance.check_in_offline; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.check_in_offline IS 'TRUE إذا سُجّلت بصمة الحضور بدون إنترنت ورُفعت لاحقاً — الوقت مأخوذ من ساعة الجهاز ويحتاج مراجعة.';


--
-- Name: COLUMN attendance.check_in_time_source; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.check_in_time_source IS 'online | offline_verified (محسوب من وقت السيرفر وعدّاد الموبايل) | offline_review (ساعة الموبايل، يحتاج مراجعة) | offline_reviewed | manual';


--
-- Name: COLUMN attendance.check_in_device_time; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.attendance.check_in_device_time IS 'وقت ساعة الموبايل لبصمة محفوظة بدون إنترنت (للمقارنة).';


--
-- Name: work_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_schedules (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid,
    department_id uuid,
    name text NOT NULL,
    check_in_time time without time zone NOT NULL,
    check_out_time time without time zone NOT NULL,
    grace_period_minutes integer DEFAULT 15 NOT NULL,
    work_days integer[] NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    branch_id uuid,
    reminder_minutes_after integer DEFAULT 5 NOT NULL,
    CONSTRAINT chk_work_schedules_reminder_minutes CHECK (((reminder_minutes_after >= 0) AND (reminder_minutes_after <= 120)))
);


--
-- Name: TABLE work_schedules; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.work_schedules IS 'توقيتات وأيام العمل المحددة للموظفين والأقسام';


--
-- Name: COLUMN work_schedules.reminder_minutes_after; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.work_schedules.reminder_minutes_after IS 'دقائق بعد بداية/نهاية الدوام قبل إرسال تذكير البصمة (افتراضي 5)';


--
-- Name: _payroll_day_attendance_events(uuid, date, public.attendance, public.work_schedules, boolean, numeric, numeric, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._payroll_day_attendance_events(p_employee_id uuid, p_date date, p_att public.attendance, p_sched public.work_schedules, p_workday boolean, p_daily numeric, p_minute numeric, p_policy jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_att attendance%ROWTYPE := p_att;
  v_sched work_schedules%ROWTYPE := p_sched;
  v_has_sched boolean := p_sched.id IS NOT NULL;
  v_workday boolean := p_workday;
  v_daily numeric := p_daily;
  v_minute numeric := p_minute;
  v_policy jsonb := p_policy;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_grace int := COALESCE(p_sched.grace_period_minutes, 15);
  v_status text;
  v_mins numeric;
  v_last timestamptz;
BEGIN
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
END;
$$;


--
-- Name: _payroll_day_hourly_leaves(uuid, date, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._payroll_day_hourly_leaves(p_employee_id uuid, p_date date, p_minute numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_leave leave_requests%ROWTYPE;
  v_minute numeric := p_minute;
  v_whole_day boolean := false;
  v_mins numeric;
BEGIN
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
END;
$$;


--
-- Name: _payroll_day_leave_events(uuid, date, boolean, numeric, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._payroll_day_leave_events(p_employee_id uuid, p_date date, p_workday boolean, p_daily numeric, p_policy jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_leave leave_requests%ROWTYPE;
  v_workday boolean := p_workday;
  v_daily numeric := p_daily;
  v_policy jsonb := p_policy;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
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
END;
$$;


--
-- Name: payroll_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    event_date date NOT NULL,
    event_type text NOT NULL,
    minutes numeric(10,2) DEFAULT 0 NOT NULL,
    days numeric(6,2) DEFAULT 0 NOT NULL,
    amount numeric(14,2) DEFAULT 0 NOT NULL,
    direction smallint NOT NULL,
    payroll_month text NOT NULL,
    carried_from text,
    status text DEFAULT 'pending'::text NOT NULL,
    source text NOT NULL,
    source_id uuid,
    adjusts_event_id uuid,
    daily_rate numeric(14,4),
    minute_rate numeric(14,6),
    notes text,
    decision_reason text,
    decided_by uuid,
    decided_at timestamp with time zone,
    salary_slip_id uuid,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    amount_override numeric,
    CONSTRAINT payroll_events_amount_check CHECK ((amount >= (0)::numeric)),
    CONSTRAINT payroll_events_amount_override_check CHECK (((amount_override IS NULL) OR (amount_override >= (0)::numeric))),
    CONSTRAINT payroll_events_direction_check CHECK ((direction = ANY (ARRAY['-1'::integer, 0, 1]))),
    CONSTRAINT payroll_events_event_type_check CHECK ((event_type = ANY (ARRAY['absence'::text, 'late'::text, 'early_leave'::text, 'missing_punch'::text, 'unpaid_leave'::text, 'paid_leave'::text, 'overtime'::text, 'manual_deduction'::text, 'bonus'::text, 'allowance'::text, 'advance'::text, 'adjustment'::text, 'other'::text]))),
    CONSTRAINT payroll_events_source_check CHECK ((source = ANY (ARRAY['attendance'::text, 'no_record'::text, 'leave'::text, 'manual'::text, 'approval'::text, 'carry_over'::text, 'legacy'::text]))),
    CONSTRAINT payroll_events_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'ignored'::text, 'void'::text])))
);


--
-- Name: TABLE payroll_events; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payroll_events IS 'كل حركة تؤثر على الراتب بتاريخها الحقيقي والمسير الذي تُحتسب فيه. تُكتب فقط عبر دوال المحرّك.';


--
-- Name: COLUMN payroll_events.amount_override; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll_events.amount_override IS 'مبلغ كتبته الإدارة عند القرار بدل المحسوب (NULL = المحسوب). يبقى بعد إعادة الحساب';


--
-- Name: _payroll_event_computed_amount(public.payroll_events); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._payroll_event_computed_amount(e public.payroll_events) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT round(CASE e.event_type
    WHEN 'absence' THEN d.daily * GREATEST(e.days, 1)
    WHEN 'late' THEN LEAST(e.minutes * COALESCE(e.minute_rate, 0), d.daily)
    WHEN 'overtime' THEN e.minutes * COALESCE(e.minute_rate, 0)
                         * COALESCE((public.payroll_policy() ->> 'overtime_multiplier')::numeric, 1)
    ELSE e.minutes * COALESCE(e.minute_rate, 0)
  END, 2)
  FROM (SELECT COALESCE(e.daily_rate, public.payroll_daily_rate(e.employee_id, e.payroll_month)) AS daily) d;
$$;


--
-- Name: _payroll_settle(public.payroll_events, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._payroll_settle(p_event public.payroll_events, p_desired_signed numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: _pledge_bytes(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._pledge_bytes(p_url text) RETURNS bigint
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
DECLARE
  v_path text := substring(COALESCE(p_url, '') FROM '/loan-pledges/(.+)$');
  v bigint;
BEGIN
  IF v_path IS NULL OR to_regclass('storage.objects') IS NULL THEN RETURN 0; END IF;
  EXECUTE $q$SELECT COALESCE((metadata ->> 'size')::bigint, 0) FROM storage.objects WHERE bucket_id = 'loan-pledges' AND name = $1 LIMIT 1$q$
    INTO v USING split_part(v_path, '?', 1);
  RETURN COALESCE(v, 0);
EXCEPTION WHEN OTHERS THEN
  RETURN 0;
END;
$_$;


--
-- Name: _salary_effective_month(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._salary_effective_month(p_value text) RETURNS text
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
    AS $_$
DECLARE
  v text := replace(btrim(COALESCE(p_value, '')), '/', '-');
BEGIN
  IF v ~ '^\d{4}-\d{1,2}-\d{1,2}' THEN
    RETURN public.payroll_month_of(to_date(substr(v, 1, 10), 'YYYY-MM-DD'));
  ELSIF v ~ '^\d{4}-\d{1,2}$' THEN
    RETURN to_char(to_date(v || '-01', 'YYYY-MM-DD'), 'YYYY-MM');
  END IF;
  RETURN NULL;
END;
$_$;


--
-- Name: _validate_loan_terms(uuid, numeric, integer, date, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public._validate_loan_terms(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_ignore_loan uuid DEFAULT NULL::uuid) RETURNS numeric
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 OR p_months IS NULL OR p_months <= 0 THEN
    RAISE EXCEPTION 'يرجى إدخال مبلغ وعدد أشهر سداد أكبر من الصفر.' USING ERRCODE = '22023';
  END IF;
  IF p_first_due IS NULL THEN
    RAISE EXCEPTION 'يرجى تحديد تاريخ استحقاق أول قسط.' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM loans
    WHERE employee_id = p_employee_id AND status = 'approved' AND remaining_amount > 0
      AND id IS DISTINCT FROM p_ignore_loan
  ) THEN
    RAISE EXCEPTION 'لا يمكن الموافقة: الموظف لديه سلفة نشطة حالياً. يرجى إغلاقها أولاً.' USING ERRCODE = '55000';
  END IF;

  RETURN floor(p_amount / p_months);
END;
$$;


--
-- Name: announcements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.announcements (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    title text NOT NULL,
    content text NOT NULL,
    is_pinned boolean DEFAULT false NOT NULL,
    target_department_id uuid,
    created_by uuid,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    starts_at timestamp with time zone DEFAULT now() NOT NULL,
    ends_at timestamp with time zone,
    target_branch_id uuid,
    target_employee_ids uuid[],
    CONSTRAINT chk_announcements_period CHECK (((ends_at IS NULL) OR (ends_at > starts_at)))
);


--
-- Name: TABLE announcements; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.announcements IS 'لوحة الإعلانات الإدارية والتعاميم الموجهة للموظفين';


--
-- Name: COLUMN announcements.starts_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.announcements.starts_at IS 'بداية ظهور التعميم في التطبيق';


--
-- Name: COLUMN announcements.ends_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.announcements.ends_at IS 'نهاية ظهور التعميم (فارغ = بدون نهاية)';


--
-- Name: COLUMN announcements.target_branch_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.announcements.target_branch_id IS 'تعميم لفرع معيّن (فارغ مع target_employee_ids فارغ = للجميع)';


--
-- Name: COLUMN announcements.target_employee_ids; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.announcements.target_employee_ids IS 'تعميم لموظفين محددين';


--
-- Name: announcement_targets(public.announcements, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.announcement_targets(a public.announcements, p_employee_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT CASE
    WHEN a.target_employee_ids IS NOT NULL AND cardinality(a.target_employee_ids) > 0
      THEN p_employee_id = ANY (a.target_employee_ids)
    WHEN a.target_branch_id IS NOT NULL
      THEN EXISTS (SELECT 1 FROM employees e WHERE e.id = p_employee_id AND e.branch_id = a.target_branch_id)
    WHEN a.target_department_id IS NOT NULL
      THEN EXISTS (SELECT 1 FROM employees e WHERE e.id = p_employee_id AND e.department_id = a.target_department_id)
    ELSE true
  END;
$$;


--
-- Name: apply_due_salary_changes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.apply_due_salary_changes() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_now text := public.payroll_month_of((now() AT TIME ZONE public.company_timezone())::date);
  r record;
  v_n int := 0;
BEGIN
  PERFORM public.require_admin_or_system();
  FOR r IN
    SELECT id, future_salary_iqd FROM employees
    WHERE future_salary_iqd IS NOT NULL
      AND public._salary_effective_month(future_salary_month) IS NOT NULL
      AND public._salary_effective_month(future_salary_month) <= v_now
  LOOP
    UPDATE employees SET monthly_salary_iqd = r.future_salary_iqd, future_salary_iqd = NULL, future_salary_month = NULL
    WHERE id = r.id;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;


--
-- Name: approve_loan(uuid, numeric, integer, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.approve_loan(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_loan loans%ROWTYPE;
  v_base numeric;
BEGIN
  PERFORM public.require_admin();

  SELECT * INTO v_loan FROM loans WHERE id = p_loan_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'طلب السلفة غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF v_loan.status <> 'pending' THEN
    RAISE EXCEPTION 'تمت معالجة طلب السلفة هذا مسبقاً.' USING ERRCODE = '55000';
  END IF;

  v_base := public._validate_loan_terms(v_loan.employee_id, p_amount, p_months, p_first_due, p_loan_id);

  UPDATE loans
  SET status = 'approved',
      amount = p_amount,
      installment_count = p_months,
      installment_amount = v_base,
      remaining_amount = p_amount,
      approved_by = auth.uid(),
      approved_at = now()
  WHERE id = p_loan_id;

  PERFORM public._insert_loan_installments(p_loan_id, p_amount, p_months, p_first_due);
END;
$$;


--
-- Name: FUNCTION approve_loan(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.approve_loan(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date) IS 'اعتماد طلب سلفة معلّق وتوليد أقساطه في معاملة واحدة. مقفل على الأدمن.
يرفض إن كانت للموظف سلفة جارية. القسط فوق نص الراتب مسموح (تنبيه بالواجهة).';


--
-- Name: approve_payroll_slip(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.approve_payroll_slip(p_employee_id uuid, p_month text, p_adjustments jsonb DEFAULT '[]'::jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_sum jsonb;
  v_slip uuid;
  v_adj jsonb;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_term date;
  v_earn numeric;
  v_ded numeric;
  v_net numeric;
  v_excess numeric := 0;
  v_lines_earn numeric;
  v_lines_ded numeric;
  v_round_diff numeric;
BEGIN
  PERFORM public.require_admin();
  v_p := public.ensure_payroll_period(p_month);
  IF v_p.status <> 'open' OR EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month) THEN
    RAISE EXCEPTION 'مسير % مغلق. أعد فتحه أولاً.', p_month USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = p_employee_id AND work_month = p_month) THEN
    RAISE EXCEPTION 'تم صرف الراتب مسبقاً لهذا الموظف في هذا الشهر.' USING ERRCODE = '23505';
  END IF;
  -- الراتب ينعتمد بعد نهاية فترة الدوام، إلا آخر راتب لموظف ترك العمل (وآخر يوم دوامه فات)
  SELECT termination_date INTO v_term FROM employees WHERE id = p_employee_id;
  IF v_today <= v_p.cutoff_date
     AND NOT (v_term IS NOT NULL AND v_term BETWEEN v_p.start_date AND v_p.cutoff_date AND v_term < v_today) THEN
    RAISE EXCEPTION 'رواتب شهر % تنعتمد بعد نهاية الدوام المحسوب (من %). قبلها تكدر تعتمد بس آخر راتب لموظف ترك العمل.',
      p_month, to_char(v_p.cutoff_date + 1, 'DD/MM/YYYY') USING ERRCODE = '55000';
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

  -- قسط السلفة ما يخلي الصافي بالسالب: ينقص بقد الممكن والباقي بآخر السلفة
  PERFORM public._cap_loans_to_net(p_employee_id, p_month);

  v_sum := public.payroll_employee_summary(p_employee_id, p_month);
  v_earn := (v_sum ->> 'earnings')::numeric;
  v_ded := (v_sum ->> 'deductions')::numeric;
  v_net := (v_sum ->> 'net')::numeric;
  -- (PAY-006) خصومات أكبر من الراتب (بعد ما الأقساط نزلت لصفر): الصافي صفر والزايد يتسوى خارج النظام، والمسير ينغلق
  IF v_net < 0 THEN
    v_excess := -v_net;
    v_ded := v_ded - v_excess;
    v_net := 0;
  END IF;

  INSERT INTO salary_slips (employee_id, work_month, basic_salary, allowances, deductions, loans_deduction, net_salary, status, computed_by_engine)
  VALUES (p_employee_id, p_month, (v_sum ->> 'basic')::numeric, v_earn, v_ded, (v_sum ->> 'loans')::numeric, v_net, 'published', true)
  RETURNING id INTO v_slip;

  -- (PAY-011) السطور بالدينار (المجموع ينحسب مقرّب مرة وحدة، والفرق سطر واضح)
  INSERT INTO salary_slip_lines (salary_slip_id, event_id, line_type, event_date, minutes, days, amount, direction, notes, carried_from)
  SELECT v_slip, pe.id, pe.event_type, pe.event_date, pe.minutes, pe.days, round(pe.amount), pe.direction, pe.notes, pe.carried_from
  FROM payroll_events pe
  WHERE pe.employee_id = p_employee_id AND pe.payroll_month = p_month AND pe.status = 'approved'
    AND (pe.amount > 0 OR pe.event_type = 'paid_leave');

  SELECT COALESCE(sum(amount) FILTER (WHERE direction = 1), 0), COALESCE(sum(amount) FILTER (WHERE direction = -1), 0)
  INTO v_lines_earn, v_lines_ded
  FROM salary_slip_lines WHERE salary_slip_id = v_slip;
  v_round_diff := (v_earn - v_lines_earn) - ((v_sum ->> 'deductions')::numeric - v_lines_ded);
  IF v_round_diff <> 0 THEN
    INSERT INTO salary_slip_lines (salary_slip_id, line_type, event_date, amount, direction, notes)
    VALUES (v_slip, 'rounding', v_p.cutoff_date, abs(v_round_diff), sign(v_round_diff)::smallint,
            'فرق تقريب: المجموع يتقرّب لأقرب دينار مرة وحدة');
  END IF;

  INSERT INTO salary_slip_lines (salary_slip_id, line_type, event_date, amount, direction, notes)
  SELECT v_slip, 'loan', li.due_date, li.amount, -1, 'قسط سلفة'
  FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  IF v_excess > 0 THEN
    INSERT INTO salary_slip_lines (salary_slip_id, line_type, event_date, amount, direction, notes)
    VALUES (v_slip, 'excess_deduction', v_p.cutoff_date, v_excess, 1,
            format('خصومات أكثر من الراتب بـ %s د.ع: ما انخصمت من الكشف (الصافي صفر) وتتسوى ويا الموظف خارج النظام',
                   to_char(v_excess, 'FM999,999,999')));
  END IF;

  UPDATE payroll_events SET salary_slip_id = v_slip, updated_at = now()
  WHERE employee_id = p_employee_id AND payroll_month = p_month AND status = 'approved';

  UPDATE loan_installments li
  SET is_paid = true, paid_at = now(), paid_by_slip_id = v_slip
  FROM loans l
  WHERE li.loan_id = l.id AND l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  -- (PAY-010) تعديلات الأقساط التلقائية تخص هالكشف
  UPDATE payroll_loan_caps SET salary_slip_id = v_slip
  WHERE employee_id = p_employee_id AND payroll_month = p_month AND salary_slip_id IS NULL;

  RETURN v_slip;
END;
$$;


--
-- Name: approve_salary_slip(uuid, text, numeric, numeric, numeric, numeric, numeric, uuid[], jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.approve_salary_slip(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[] DEFAULT '{}'::uuid[], p_adjustments jsonb DEFAULT '[]'::jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: approve_salary_slip_legacy(uuid, text, numeric, numeric, numeric, numeric, numeric, uuid[], jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.approve_salary_slip_legacy(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[] DEFAULT '{}'::uuid[], p_adjustments jsonb DEFAULT '[]'::jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_slip_id uuid;
  v_adj jsonb;
BEGIN
  PERFORM public.require_admin();

  IF EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_work_month) THEN
    RAISE EXCEPTION 'هذا الشهر مؤرشف مالياً ومقفل.' USING ERRCODE = '42501';
  END IF;

  BEGIN
    INSERT INTO salary_slips (employee_id, work_month, basic_salary, allowances,
                              deductions, loans_deduction, net_salary, status)
    VALUES (p_employee_id, p_work_month, p_basic_salary, COALESCE(p_allowances, 0),
            COALESCE(p_deductions, 0), COALESCE(p_loans_deduction, 0), p_net_salary, 'published')
    RETURNING id INTO v_slip_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'تم صرف الراتب مسبقاً لهذا الموظف في هذا الشهر.' USING ERRCODE = '23505';
  END;

  UPDATE loan_installments li
  SET is_paid = true, paid_at = now(), paid_by_slip_id = v_slip_id
  FROM loans l
  WHERE li.id = ANY(COALESCE(p_installment_ids, '{}'))
    AND li.loan_id = l.id
    AND l.employee_id = p_employee_id
    AND li.is_paid = false;

  FOR v_adj IN SELECT * FROM jsonb_array_elements(COALESCE(p_adjustments, '[]'::jsonb))
  LOOP
    CONTINUE WHEN COALESCE((v_adj->>'amount')::numeric, 0) <= 0;
    CONTINUE WHEN COALESCE((v_adj->>'skip_if_exists')::boolean, false) AND EXISTS (
      SELECT 1 FROM bonuses_deductions
      WHERE employee_id = p_employee_id
        AND type = v_adj->>'type'
        AND reason = v_adj->>'reason'
    );

    INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date,
                                    created_by, salary_slip_id)
    VALUES (p_employee_id, v_adj->>'type', (v_adj->>'amount')::numeric, v_adj->>'reason',
            COALESCE((v_adj->>'issue_date')::date, current_date), auth.uid(), v_slip_id);
  END LOOP;

  RETURN v_slip_id;
END;
$$;


--
-- Name: archive_settled_loan(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_settled_loan(p_loan_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  l loans%ROWTYPE;
  v_why text;
  v_emp employees%ROWTYPE;
  v_inst jsonb;
  v_total numeric;
  v_settled timestamptz;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO l FROM loans WHERE id = p_loan_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'السلفة غير موجودة.' USING ERRCODE = 'P0002';
  END IF;
  v_why := public.loan_archive_blocker(p_loan_id);
  IF v_why IS NOT NULL THEN
    RAISE EXCEPTION 'السلفة ما تتأرشف: %', v_why USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_emp FROM employees WHERE id = l.employee_id;
  SELECT jsonb_agg(jsonb_build_object(
           'due_date', li.due_date, 'amount', li.amount, 'paid_at', li.paid_at,
           'method', CASE WHEN li.paid_by_slip_id IS NOT NULL THEN 'salary' ELSE 'cash' END,
           -- رواتب يا شهر: من الكشف إذا انخصم براتب، وإلا شهر الرواتب اللي يتبعه تاريخ القسط
           'payroll_month', COALESCE(s.work_month, public.payroll_month_of(li.due_date)),
           'slip_id', li.paid_by_slip_id, 'note', li.payment_note) ORDER BY li.due_date, li.created_at),
         sum(li.amount), max(li.paid_at)
  INTO v_inst, v_total, v_settled
  FROM loan_installments li LEFT JOIN salary_slips s ON s.id = li.paid_by_slip_id
  WHERE li.loan_id = l.id;

  INSERT INTO settled_loans (loan_id, loan_no, employee_id, employee_name, employee_code, amount, total_deducted, final_balance,
                             installments, approved_at, settled_at, archived_by)
  VALUES (l.id, l.loan_no, l.employee_id, COALESCE(v_emp.full_name, 'موظف محذوف'), v_emp.employee_code, l.amount, v_total, 0,
          v_inst, l.approved_at, COALESCE(v_settled, now()), auth.uid());

  PERFORM set_config('loans.archiving', 'on', true);
  DELETE FROM loans WHERE id = l.id;
  PERFORM set_config('loans.archiving', 'off', true);

  RETURN jsonb_build_object('success', true, 'loan_no', l.loan_no, 'pledge_url', l.pledge_url);
END;
$$;


--
-- Name: assign_employee_code(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_employee_code() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.employee_code IS NULL OR btrim(NEW.employee_code) = '' THEN
    NEW.employee_code := public.next_employee_code();
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: assign_loan_no(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_loan_no() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  NEW.loan_no := nextval('public.loan_no_seq');
  RETURN NEW;
END;
$$;


--
-- Name: assistant_alerts(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_alerts(p_from date, p_to date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_days text[] := ARRAY['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
BEGIN
  PERFORM public.require_admin();
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from OR p_to - p_from > 92 THEN
    RAISE EXCEPTION 'حدد فترة صحيحة أقصاها 3 أشهر.' USING ERRCODE = '22023';
  END IF;
  RETURN jsonb_build_object('from', p_from, 'to', p_to,
    -- يتأخر بنفس يوم الأسبوع 3 مرات أو أكثر
    'recurring_late_weekday', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('employee', e.full_name, 'weekday', v_days[dow + 1], 'times', n) ORDER BY n DESC)
      FROM (SELECT employee_id, EXTRACT(DOW FROM event_date)::int dow, count(*) n FROM payroll_events
            WHERE event_type = 'late' AND status <> 'void' AND event_date BETWEEN p_from AND p_to
            GROUP BY 1, 2 HAVING count(*) >= 3) t JOIN employees e ON e.id = t.employee_id), '[]'::jsonb),
    'repeated_missing_punch', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('employee', e.full_name, 'times', n) ORDER BY n DESC)
      FROM (SELECT employee_id, count(*) n FROM payroll_events
            WHERE event_type = 'missing_punch' AND status <> 'void' AND event_date BETWEEN p_from AND p_to
            GROUP BY 1 HAVING count(*) >= 3) t JOIN employees e ON e.id = t.employee_id), '[]'::jsonb),
    -- بصمات محفوظة بدون إنترنت (وقتها من ساعة الموبايل) — تستاهل مراجعة إذا كثيرة
    'many_offline_punches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('employee', e.full_name, 'times', n) ORDER BY n DESC)
      FROM (SELECT employee_id, count(*) n FROM attendance
            WHERE (check_in_offline OR check_out_offline) AND work_date BETWEEN p_from AND p_to
            GROUP BY 1 HAVING count(*) >= 3) t JOIN employees e ON e.id = t.employee_id), '[]'::jsonb),
    'low_annual_leave', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('employee', full_name, 'left_days', left_days) ORDER BY left_days)
      FROM (SELECT e.full_name, (public.get_leave_balance(e.id, NULL, NULL) -> 'annual' ->> 'left')::numeric AS left_days
            FROM employees e WHERE e.is_active) x WHERE left_days IS NOT NULL AND left_days < 2), '[]'::jsonb),
    'data_issues', public.assistant_data_issues());
END;
$$;


--
-- Name: assistant_attendance_log(uuid, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_attendance_log(p_employee_id uuid, p_from date, p_to date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_tz text := public.company_timezone();
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_emp record;
  v_days jsonb := '[]'::jsonb;
  d date;
  s work_schedules%ROWTYPE;
  v_holiday text;
  v_workday boolean;
  a attendance%ROWTYPE;
  v_has_att boolean;
  v_leave text;
  v_hourly text;
  v_events jsonb;
  v_status text;
  v_decision text;
  v_deducted numeric;
BEGIN
  PERFORM public.require_admin();
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
    RAISE EXCEPTION 'حدد فترة صحيحة (من … إلى).' USING ERRCODE = '22023';
  END IF;
  IF p_to - p_from > 92 THEN
    RAISE EXCEPTION 'الفترة طويلة: أقصاها 3 أشهر بالطلب الواحد.' USING ERRCODE = '22023';
  END IF;

  SELECT e.id, e.full_name, e.employee_code, b.name AS branch, e.join_date, e.termination_date INTO v_emp
  FROM employees e LEFT JOIN branches b ON b.id = e.branch_id WHERE e.id = p_employee_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;

  d := p_from;
  WHILE d <= p_to LOOP
    s := public.payroll_schedule_at(p_employee_id, d);
    SELECT name INTO v_holiday FROM official_holidays WHERE holiday_date = d LIMIT 1;
    v_workday := EXTRACT(DOW FROM d)::int = ANY (COALESCE(s.work_days, ARRAY[0, 1, 2, 3, 4, 6])) AND v_holiday IS NULL;

    SELECT * INTO a FROM attendance WHERE employee_id = p_employee_id AND work_date = d LIMIT 1;
    v_has_att := FOUND;

    SELECT public.assistant_leave_type_name(l.leave_type) || CASE WHEN l.is_paid THEN '' ELSE ' (بدون راتب)' END INTO v_leave
    FROM leave_requests l
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT COALESCE(l.is_hourly, false)
      AND d BETWEEN (l.start_date AT TIME ZONE v_tz)::date AND (l.end_date AT TIME ZONE v_tz)::date
    LIMIT 1;

    SELECT string_agg(format('إذن %s→%s', to_char(l.start_hour, 'HH24:MI'), to_char(l.end_hour, 'HH24:MI')), '، ') INTO v_hourly
    FROM leave_requests l
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND COALESCE(l.is_hourly, false)
      AND (l.start_date AT TIME ZONE v_tz)::date = d;

    SELECT jsonb_agg(jsonb_build_object(
             'type', pe.event_type, 'minutes', pe.minutes, 'amount', round(pe.amount),
             'decision', CASE pe.status WHEN 'approved' THEN 'مخصوم' WHEN 'ignored' THEN 'معفى' ELSE 'بانتظار القرار' END,
             'reason', COALESCE(pe.decision_reason, pe.notes), 'payroll_month', pe.payroll_month) ORDER BY pe.event_type)
    INTO v_events
    FROM payroll_events pe
    WHERE pe.employee_id = p_employee_id AND pe.event_date = d AND pe.status <> 'void'
      AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch', 'unpaid_leave');

    v_status := CASE
      WHEN NOT public.employee_in_service(p_employee_id, d) THEN 'خارج فترة الخدمة'
      WHEN v_holiday IS NOT NULL AND NOT v_has_att THEN 'عطلة رسمية'
      WHEN v_leave IS NOT NULL THEN 'إجازة'
      WHEN v_has_att AND a.status = 'absent' THEN 'غياب'
      WHEN v_has_att AND a.check_in_time IS NULL THEN 'بصمة ناقصة'
      WHEN v_has_att AND v_events @> '[{"type":"late"}]' THEN 'متأخر'
      WHEN v_has_att AND v_events @> '[{"type":"early_leave"}]' THEN 'خروج مبكر'
      WHEN v_has_att THEN 'حاضر'
      WHEN NOT v_workday THEN 'عطلة أسبوعية'
      WHEN d >= v_today THEN 'لم يحن بعد'
      ELSE 'غياب'
    END;

    SELECT CASE
             WHEN count(*) FILTER (WHERE e ->> 'type' <> 'missing_punch') = 0 THEN NULL
             WHEN bool_or(e ->> 'decision' = 'بانتظار القرار') THEN 'بانتظار القرار'
             WHEN bool_or(e ->> 'decision' = 'مخصوم') THEN 'مخصوم'
             ELSE 'معفى' END,
           COALESCE(sum((e ->> 'amount')::numeric) FILTER (WHERE e ->> 'decision' = 'مخصوم'), 0)
    INTO v_decision, v_deducted
    FROM jsonb_array_elements(COALESCE(v_events, '[]'::jsonb)) e;

    v_days := v_days || jsonb_build_object(
      'date', d, 'weekday', EXTRACT(DOW FROM d)::int, 'workday', v_workday, 'status', v_status,
      'holiday', v_holiday, 'leave', COALESCE(v_leave, v_hourly),
      'check_in', CASE WHEN v_has_att THEN to_char(a.check_in_time AT TIME ZONE v_tz, 'HH24:MI') END,
      'check_out', CASE WHEN v_has_att THEN to_char(a.check_out_time AT TIME ZONE v_tz, 'HH24:MI') END,
      'late_minutes', COALESCE((SELECT sum((e ->> 'minutes')::numeric) FROM jsonb_array_elements(COALESCE(v_events, '[]')) e WHERE e ->> 'type' = 'late'), 0),
      'early_minutes', COALESCE((SELECT sum((e ->> 'minutes')::numeric) FROM jsonb_array_elements(COALESCE(v_events, '[]')) e WHERE e ->> 'type' = 'early_leave'), 0),
      'decision', v_decision, 'deducted', v_deducted, 'events', COALESCE(v_events, '[]'::jsonb));
    d := d + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'employee', jsonb_build_object('id', v_emp.id, 'name', v_emp.full_name, 'code', v_emp.employee_code, 'branch', v_emp.branch),
    'from', p_from, 'to', p_to,
    'summary', (SELECT jsonb_build_object(
        'present', count(*) FILTER (WHERE x ->> 'status' IN ('حاضر', 'متأخر', 'خروج مبكر')),
        'late', count(*) FILTER (WHERE x ->> 'status' = 'متأخر'),
        'early_leave', count(*) FILTER (WHERE x ->> 'status' = 'خروج مبكر'),
        'absent', count(*) FILTER (WHERE x ->> 'status' = 'غياب'),
        'leave', count(*) FILTER (WHERE x ->> 'status' = 'إجازة'),
        'missing_punch', count(*) FILTER (WHERE x ->> 'status' = 'بصمة ناقصة'),
        'late_minutes', sum((x ->> 'late_minutes')::numeric),
        'deducted_days', count(*) FILTER (WHERE x ->> 'decision' = 'مخصوم'),
        'excused_days', count(*) FILTER (WHERE x ->> 'decision' = 'معفى'),
        'pending_days', count(*) FILTER (WHERE x ->> 'decision' = 'بانتظار القرار'),
        'deducted_total', sum((x ->> 'deducted')::numeric))
      FROM jsonb_array_elements(v_days) x),
    'days', v_days);
END;
$$;


--
-- Name: assistant_branch_attendance(text, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_branch_attendance(p_branch text, p_from date, p_to date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_b text := public.assistant_norm(p_branch);
  v_logs jsonb := '[]'::jsonb;
  r record;
  n int := 0;
BEGIN
  PERFORM public.require_admin();
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from OR p_to - p_from > 30 THEN
    RAISE EXCEPTION 'تقرير الفرع أو الشركة: حدد فترة صحيحة أقصاها 31 يوم.' USING ERRCODE = '22023';
  END IF;
  FOR r IN
    SELECT e.id FROM employees e LEFT JOIN branches b ON b.id = e.branch_id
    WHERE e.is_active AND (v_b = '' OR public.assistant_norm(b.name) LIKE '%' || v_b || '%')
    ORDER BY b.name, e.full_name
  LOOP
    n := n + 1;
    IF n > 60 THEN
      RAISE EXCEPTION 'عدد الموظفين كبير (أكثر من 60). حدد فرعاً.' USING ERRCODE = '22023';
    END IF;
    v_logs := v_logs || public.assistant_attendance_log(r.id, p_from, p_to);
  END LOOP;
  RETURN jsonb_build_object('scope', COALESCE(NULLIF(btrim(p_branch), ''), 'كل الفروع'), 'from', p_from, 'to', p_to, 'employees', v_logs);
END;
$$;


--
-- Name: assistant_branch_ranking(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_branch_ranking(p_from date, p_to date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin();
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from OR p_to - p_from > 92 THEN
    RAISE EXCEPTION 'حدد فترة صحيحة أقصاها 3 أشهر.' USING ERRCODE = '22023';
  END IF;
  RETURN jsonb_build_object('from', p_from, 'to', p_to,
    'branches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'branch', branch, 'employees', emps, 'present_days', present, 'absence_days', absences,
               'late_times', lates, 'late_minutes_per_employee', round(late_minutes / NULLIF(emps, 0), 1),
               'attendance_rate', round(100.0 * present / NULLIF(present + absences, 0), 1))
             ORDER BY round(100.0 * present / NULLIF(present + absences, 0), 1) DESC NULLS LAST, late_minutes / NULLIF(emps, 0))
      FROM (
        SELECT COALESCE(b.name, 'بدون فرع') AS branch, count(DISTINCT e.id) AS emps,
               (SELECT count(*) FROM attendance a JOIN employees x ON x.id = a.employee_id
                WHERE x.is_active AND x.branch_id IS NOT DISTINCT FROM b.id AND a.work_date BETWEEN p_from AND p_to AND a.status <> 'absent') AS present,
               COALESCE((SELECT sum(pe.days) FROM payroll_events pe JOIN employees x ON x.id = pe.employee_id
                WHERE x.is_active AND x.branch_id IS NOT DISTINCT FROM b.id AND pe.event_type = 'absence' AND pe.status <> 'void'
                  AND pe.status <> 'ignored' AND pe.event_date BETWEEN p_from AND p_to), 0) AS absences,
               (SELECT count(*) FROM payroll_events pe JOIN employees x ON x.id = pe.employee_id
                WHERE x.is_active AND x.branch_id IS NOT DISTINCT FROM b.id AND pe.event_type = 'late' AND pe.status <> 'void'
                  AND pe.event_date BETWEEN p_from AND p_to) AS lates,
               COALESCE((SELECT sum(pe.minutes) FROM payroll_events pe JOIN employees x ON x.id = pe.employee_id
                WHERE x.is_active AND x.branch_id IS NOT DISTINCT FROM b.id AND pe.event_type = 'late' AND pe.status <> 'void'
                  AND pe.event_date BETWEEN p_from AND p_to), 0) AS late_minutes
        FROM employees e LEFT JOIN branches b ON b.id = e.branch_id
        WHERE e.is_active GROUP BY b.id, b.name
      ) s), '[]'::jsonb),
    -- حاضر 5 أيام أو أكثر وبدون أي تأخير/غياب/خروج مبكر/بصمة ناقصة بالفترة
    'most_disciplined', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('employee', full_name, 'branch', branch, 'present_days', days) ORDER BY days DESC, full_name)
      FROM (
        SELECT e.full_name, b.name AS branch, count(a.id) AS days
        FROM employees e LEFT JOIN branches b ON b.id = e.branch_id
        JOIN attendance a ON a.employee_id = e.id AND a.work_date BETWEEN p_from AND p_to AND a.status <> 'absent'
        WHERE e.is_active AND NOT EXISTS (
          SELECT 1 FROM payroll_events pe WHERE pe.employee_id = e.id AND pe.event_date BETWEEN p_from AND p_to
            AND pe.status NOT IN ('void', 'ignored') AND pe.event_type IN ('late', 'absence', 'early_leave', 'missing_punch'))
        GROUP BY e.id, e.full_name, b.name HAVING count(a.id) >= 5
        ORDER BY count(a.id) DESC LIMIT 10) t), '[]'::jsonb));
END;
$$;


--
-- Name: assistant_branches(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_branches() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('name', b.name,
             'employees', (SELECT count(*) FROM employees e WHERE e.branch_id = b.id AND e.is_active)) ORDER BY b.name)
    FROM branches b), '[]'::jsonb);
END;
$$;


--
-- Name: assistant_build_morning_summary(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_build_morning_summary(p_date date DEFAULT NULL::date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: assistant_compare(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_compare(p_employee_id uuid, p_branch text, p_month_a text, p_month_b text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin();
  RETURN jsonb_build_object(
    'scope', CASE WHEN p_employee_id IS NOT NULL THEN (SELECT full_name FROM employees WHERE id = p_employee_id)
                  ELSE COALESCE(NULLIF(btrim(p_branch), ''), 'كل الفروع') END,
    'a', public.assistant_month_metrics(p_employee_id, p_branch, p_month_a),
    'b', public.assistant_month_metrics(p_employee_id, p_branch, p_month_b));
END;
$$;


--
-- Name: assistant_data_issues(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_data_issues() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('employee', full_name, 'issues', issues) ORDER BY full_name), '[]'::jsonb)
  FROM (
    SELECT e.full_name, array_remove(ARRAY[
      CASE WHEN e.branch_id IS NULL THEN 'بدون فرع' END,
      CASE WHEN (public.payroll_schedule_at(e.id, (now() AT TIME ZONE public.company_timezone())::date)).id IS NULL THEN 'بدون جدول دوام' END,
      CASE WHEN e.join_date IS NULL THEN 'بدون تاريخ مباشرة' END,
      CASE WHEN COALESCE(e.monthly_salary_iqd, 0) <= 0 THEN 'بدون راتب' END], NULL) AS issues
    FROM employees e WHERE e.is_active
  ) x WHERE cardinality(issues) > 0;
$$;


--
-- Name: assistant_day_overview(date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_day_overview(p_date date DEFAULT NULL::date, p_branch text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_tz text := public.company_timezone();
  v_day date := COALESCE(p_date, (now() AT TIME ZONE public.company_timezone())::date);
  v_b text := public.assistant_norm(p_branch);
BEGIN
  PERFORM public.require_admin();
  RETURN jsonb_build_object('date', v_day,
    'holiday', (SELECT name FROM official_holidays WHERE holiday_date = v_day LIMIT 1),
    'branches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('branch', branch, 'present', present, 'late', late, 'on_leave', on_leave,
                                          'absent', absent, 'absent_names', absent_names, 'late_names', late_names)
                       ORDER BY branch)
      FROM (
        SELECT COALESCE(b.name, 'بدون فرع') AS branch,
               count(*) FILTER (WHERE a.id IS NOT NULL AND a.status <> 'absent') AS present,
               count(*) FILTER (WHERE a.status = 'late') AS late,
               count(*) FILTER (WHERE lv.id IS NOT NULL) AS on_leave,
               count(*) FILTER (WHERE (a.id IS NULL OR a.status = 'absent') AND lv.id IS NULL AND wd) AS absent,
               array_remove(array_agg(e.full_name) FILTER (WHERE (a.id IS NULL OR a.status = 'absent') AND lv.id IS NULL AND wd), NULL) AS absent_names,
               array_remove(array_agg(e.full_name) FILTER (WHERE a.status = 'late'), NULL) AS late_names
        FROM employees e
        LEFT JOIN branches b ON b.id = e.branch_id
        LEFT JOIN attendance a ON a.employee_id = e.id AND a.work_date = v_day
        LEFT JOIN LATERAL (SELECT l.id FROM leave_requests l WHERE l.employee_id = e.id AND l.status = 'approved'
                             AND NOT COALESCE(l.is_hourly, false)
                             AND v_day BETWEEN (l.start_date AT TIME ZONE v_tz)::date AND (l.end_date AT TIME ZONE v_tz)::date
                           LIMIT 1) lv ON true
        CROSS JOIN LATERAL (SELECT EXTRACT(DOW FROM v_day)::int = ANY (COALESCE((public.payroll_schedule_at(e.id, v_day)).work_days,
                                                                                ARRAY[0, 1, 2, 3, 4, 6]))
                                   AND NOT EXISTS (SELECT 1 FROM official_holidays h WHERE h.holiday_date = v_day) AS wd) w
        WHERE e.is_active AND (v_b = '' OR public.assistant_norm(b.name) LIKE '%' || v_b || '%')
        GROUP BY COALESCE(b.name, 'بدون فرع')
      ) s), '[]'::jsonb));
END;
$$;


--
-- Name: assistant_decision_context(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_decision_context(p_branch text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_b text := public.assistant_norm(p_branch);
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'event_id', pe.id, 'employee', e.full_name, 'branch', b.name, 'date', pe.event_date, 'type', pe.event_type,
      'minutes', pe.minutes, 'amount', round(pe.amount), 'payroll_month', pe.payroll_month, 'note', pe.notes,
      -- نفس النوع بنفس المسير (شكد تكرر)، والسابق خلال 90 يوم: كم مرة انخصم وكم مرة انعفى
      'same_type_this_month', (SELECT count(*) FROM payroll_events x WHERE x.employee_id = pe.employee_id AND x.payroll_month = pe.payroll_month
                                 AND x.event_type = pe.event_type AND x.status <> 'void'),
      'deducted_last_90d', (SELECT count(*) FROM payroll_events x WHERE x.employee_id = pe.employee_id AND x.event_type = pe.event_type
                              AND x.status = 'approved' AND x.event_date BETWEEN pe.event_date - 90 AND pe.event_date - 1),
      'excused_last_90d', (SELECT count(*) FROM payroll_events x WHERE x.employee_id = pe.employee_id AND x.event_type = pe.event_type
                             AND x.status = 'ignored' AND x.event_date BETWEEN pe.event_date - 90 AND pe.event_date - 1),
      'had_leave_request_that_day', EXISTS (SELECT 1 FROM leave_requests l WHERE l.employee_id = pe.employee_id
                             AND l.status IN ('pending', 'rejected')
                             AND pe.event_date BETWEEN (l.start_date AT TIME ZONE public.company_timezone())::date
                                                   AND (l.end_date AT TIME ZONE public.company_timezone())::date))
      ORDER BY pe.event_date, e.full_name)
    FROM payroll_events pe
    JOIN employees e ON e.id = pe.employee_id
    LEFT JOIN branches b ON b.id = e.branch_id
    WHERE pe.status = 'pending' AND pe.salary_slip_id IS NULL
      AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch')
      AND (v_b = '' OR public.assistant_norm(b.name) LIKE '%' || v_b || '%')
    LIMIT 60), '[]'::jsonb);
END;
$$;


--
-- Name: assistant_documents(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_documents(p_employee_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_name text;
  v_urls jsonb;
BEGIN
  PERFORM public.require_admin();
  SELECT full_name, CASE WHEN jsonb_typeof(document_urls) = 'array' THEN document_urls ELSE '[]'::jsonb END
  INTO v_name, v_urls FROM employees WHERE id = p_employee_id;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  RETURN jsonb_build_object('employee', v_name, 'count', jsonb_array_length(v_urls), 'urls', v_urls);
END;
$$;


--
-- Name: assistant_find_employees(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_find_employees(p_query text, p_branch text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_q text := public.assistant_norm(p_query);
  v_b text := public.assistant_norm(p_branch);
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(x ORDER BY x ->> 'name') FROM (
      SELECT jsonb_build_object('id', e.id, 'name', e.full_name, 'code', e.employee_code, 'branch', b.name,
                                'department', d.name, 'active', e.is_active, 'role', e.role) AS x
      FROM employees e
      LEFT JOIN branches b ON b.id = e.branch_id
      LEFT JOIN departments d ON d.id = e.department_id
      WHERE (v_q = '' OR public.assistant_norm(e.full_name) LIKE '%' || v_q || '%'
             OR public.assistant_norm(e.employee_code) = v_q
             -- كل كلمات البحث موجودة بالاسم (علي سعيد ← علي محمد سعيد)
             OR NOT EXISTS (SELECT 1 FROM unnest(string_to_array(v_q, ' ')) w
                            WHERE w <> '' AND public.assistant_norm(e.full_name) NOT LIKE '%' || w || '%'))
        AND (v_b = '' OR public.assistant_norm(b.name) LIKE '%' || v_b || '%')
      LIMIT 15
    ) s), '[]'::jsonb);
END;
$$;


--
-- Name: assistant_leave_type_name(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_leave_type_name(p_type text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(
    (SELECT t ->> 'name' FROM jsonb_array_elements(COALESCE(public.leave_policy() -> 'active_types', '[]'::jsonb)) t
     WHERE t ->> 'id' = p_type LIMIT 1),
    CASE p_type WHEN 'annual' THEN 'اعتيادية' WHEN 'sick' THEN 'مرضية' ELSE p_type END);
$$;


--
-- Name: assistant_leaves(uuid, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_leaves(p_employee_id uuid, p_from date, p_to date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_tz text := public.company_timezone();
BEGIN
  PERFORM public.require_admin();
  RETURN jsonb_build_object(
    'balance', public.get_leave_balance(p_employee_id, NULL, NULL),
    'requests', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'type', public.assistant_leave_type_name(l.leave_type), 'status', l.status, 'paid', l.is_paid, 'hourly', COALESCE(l.is_hourly, false),
        'from', (l.start_date AT TIME ZONE v_tz)::date, 'to', (l.end_date AT TIME ZONE v_tz)::date,
        'hours', CASE WHEN l.is_hourly THEN format('%s→%s', to_char(l.start_hour, 'HH24:MI'), to_char(l.end_hour, 'HH24:MI')) END,
        'reason', l.reason) ORDER BY l.start_date DESC)
      FROM leave_requests l
      WHERE l.employee_id = p_employee_id
        AND (l.end_date AT TIME ZONE v_tz)::date >= COALESCE(p_from, '-infinity'::date)
        AND (l.start_date AT TIME ZONE v_tz)::date <= COALESCE(p_to, 'infinity'::date)), '[]'::jsonb));
END;
$$;


--
-- Name: assistant_loans(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_loans(p_employee_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'status', l.status, 'amount', l.amount, 'remaining', l.remaining_amount, 'installment', l.installment_amount,
      'installments_count', l.installment_count, 'cash', COALESCE(l.payment_method, '') = 'cash',
      'requested_at', (l.created_at AT TIME ZONE public.company_timezone())::date,
      'installments', (SELECT jsonb_agg(jsonb_build_object('due_date', li.due_date, 'amount', li.amount, 'paid', li.is_paid)
                                        ORDER BY li.due_date) FROM loan_installments li WHERE li.loan_id = l.id))
      ORDER BY l.created_at DESC)
    FROM loans l WHERE l.employee_id = p_employee_id), '[]'::jsonb);
END;
$$;


--
-- Name: assistant_month_employees(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_month_employees(p_month text) RETURNS TABLE(id uuid, full_name text, branch text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT e.id, e.full_name, b.name
  FROM employees e
  LEFT JOIN branches b ON b.id = e.branch_id
  JOIN payroll_periods p ON p.period_month = p_month
  WHERE ((e.join_date IS NULL OR e.join_date <= p.cutoff_date)
         AND (e.termination_date IS NULL OR e.termination_date >= p.start_date)
         AND (e.is_active OR e.termination_date IS NOT NULL))
     OR EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = e.id AND s.work_month = p_month);
$$;


--
-- Name: assistant_month_metrics(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_month_metrics(p_employee_id uuid, p_branch text, p_month text) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  WITH scope AS (
    SELECT e.id FROM employees e LEFT JOIN branches b ON b.id = e.branch_id
    WHERE (p_employee_id IS NOT NULL AND e.id = p_employee_id)
       OR (p_employee_id IS NULL AND (public.assistant_norm(p_branch) = ''
           OR public.assistant_norm(b.name) LIKE '%' || public.assistant_norm(p_branch) || '%'))
  ), per AS (SELECT * FROM payroll_periods WHERE period_month = p_month)
  SELECT jsonb_build_object(
    'month', p_month,
    'present_days', (SELECT count(*) FROM attendance a, per WHERE a.employee_id IN (SELECT id FROM scope)
                       AND a.work_date BETWEEN per.start_date AND per.cutoff_date AND a.status <> 'absent'),
    'late_times', count(*) FILTER (WHERE pe.event_type = 'late'),
    'late_minutes', COALESCE(sum(pe.minutes) FILTER (WHERE pe.event_type = 'late'), 0),
    'absence_days', COALESCE(sum(pe.days) FILTER (WHERE pe.event_type = 'absence'), 0),
    'early_leave_times', count(*) FILTER (WHERE pe.event_type = 'early_leave'),
    'deducted', COALESCE(round(sum(pe.amount) FILTER (WHERE pe.status = 'approved' AND pe.direction = -1)), 0),
    'excused', count(*) FILTER (WHERE pe.status = 'ignored'))
  FROM payroll_events pe, per
  WHERE pe.employee_id IN (SELECT id FROM scope) AND pe.status <> 'void'
    AND pe.event_date BETWEEN per.start_date AND per.cutoff_date;
$$;


--
-- Name: assistant_morning_summary(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_morning_summary(p_date date DEFAULT NULL::date) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin();
  RETURN public.assistant_build_morning_summary(p_date);
END;
$$;


--
-- Name: assistant_name_hints(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_name_hints() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin();
  RETURN jsonb_build_object(
    'employees', COALESCE((SELECT jsonb_agg(full_name ORDER BY full_name) FROM employees WHERE is_active), '[]'::jsonb),
    'branches', COALESCE((SELECT jsonb_agg(name ORDER BY name) FROM branches), '[]'::jsonb));
END;
$$;


--
-- Name: assistant_norm(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_norm(p text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT btrim(regexp_replace(
    translate(lower(COALESCE(p, '')), 'أإآٱةىئؤ', 'ااااهييو'),
    '[ًٌٍَُِّْـ]', '', 'g'));
$$;


--
-- Name: assistant_payroll(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_payroll(p_employee_id uuid, p_month text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_name text;
BEGIN
  PERFORM public.require_admin();
  IF p_month !~ '^\d{4}-\d{2}$' THEN
    RAISE EXCEPTION 'الشهر لازم يكون بصيغة YYYY-MM.' USING ERRCODE = '22023';
  END IF;
  SELECT full_name INTO v_name FROM employees WHERE id = p_employee_id;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('employee', v_name, 'month', p_month, 'message', 'هذا الشهر ما بيه مسير بالنظام.');
  END IF;

  RETURN jsonb_build_object(
    'employee', v_name, 'month', p_month, 'period', jsonb_build_object('from', v_p.start_date, 'to', v_p.cutoff_date, 'status', v_p.status),
    'summary', public.payroll_employee_summary(p_employee_id, p_month) - 'employee_id',
    'events', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'date', pe.event_date, 'type', pe.event_type, 'minutes', pe.minutes, 'days', pe.days, 'amount', round(pe.amount),
        'direction', pe.direction,
        'decision', CASE pe.status WHEN 'approved' THEN 'محتسب' WHEN 'ignored' THEN 'معفى' ELSE 'بانتظار القرار' END,
        'reason', COALESCE(pe.decision_reason, pe.notes), 'carried_from', pe.carried_from) ORDER BY pe.event_date, pe.event_type)
      FROM payroll_events pe
      WHERE pe.employee_id = p_employee_id AND pe.payroll_month = p_month AND pe.status <> 'void'
        AND (pe.amount > 0 OR pe.status = 'pending' OR pe.event_type = 'paid_leave')), '[]'::jsonb),
    'loan_installments', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('due_date', li.due_date, 'amount', li.amount, 'paid', li.is_paid) ORDER BY li.due_date)
      FROM loan_installments li JOIN loans l ON l.id = li.loan_id
      WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND COALESCE(l.payment_method, '') <> 'cash'
        AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date), '[]'::jsonb));
END;
$_$;


--
-- Name: assistant_payroll_readiness(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_payroll_readiness(p_month text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('month', p_month, 'message', 'هذا الشهر ما بيه مسير بالنظام.');
  END IF;
  RETURN jsonb_build_object(
    'month', p_month,
    'period', jsonb_build_object('from', v_p.start_date, 'to', v_p.cutoff_date, 'status', v_p.status,
                                 'ended', v_today > v_p.cutoff_date, 'days_left', GREATEST(v_p.cutoff_date - v_today, 0)),
    'pending_by_type', COALESCE((
      SELECT jsonb_object_agg(event_type, n) FROM (
        SELECT event_type, count(*) n FROM payroll_events
        WHERE payroll_month = p_month AND status = 'pending' AND salary_slip_id IS NULL GROUP BY event_type) t), '{}'::jsonb),
    'without_slip', COALESCE((
      SELECT jsonb_agg(m.full_name ORDER BY m.full_name) FROM public.assistant_month_employees(p_month) m
      WHERE NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = m.id AND s.work_month = p_month)), '[]'::jsonb),
    'negative_net', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('employee', m.full_name, 'net', (x.s ->> 'net')::numeric))
      FROM public.assistant_month_employees(p_month) m
      CROSS JOIN LATERAL (SELECT public.payroll_employee_summary(m.id, p_month) AS s) x
      WHERE (x.s ->> 'net')::numeric < 0 AND (x.s -> 'slip' IS NULL OR x.s -> 'slip' = 'null'::jsonb)), '[]'::jsonb),
    'data_issues', public.assistant_data_issues(),
    'loans_due', (SELECT COALESCE(sum(li.amount), 0) FROM loan_installments li JOIN loans l ON l.id = li.loan_id
                  WHERE l.status = 'approved' AND NOT li.is_paid AND COALESCE(l.payment_method, '') <> 'cash'
                    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date));
END;
$$;


--
-- Name: assistant_payroll_run(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_payroll_run(p_month text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_rows jsonb;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('month', p_month, 'message', 'هذا الشهر ما بيه مسير بالنظام.');
  END IF;
  SELECT COALESCE(jsonb_agg(row ORDER BY row ->> 'branch', row ->> 'employee'), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT jsonb_build_object(
      'employee', m.full_name, 'branch', m.branch,
      'basic', COALESCE((s -> 'slip' ->> 'basic_salary')::numeric, (s ->> 'basic')::numeric),
      'earnings', COALESCE((s -> 'slip' ->> 'allowances')::numeric, (s ->> 'earnings')::numeric),
      'deductions', COALESCE((s -> 'slip' ->> 'deductions')::numeric, (s ->> 'deductions')::numeric),
      'loans', COALESCE((s -> 'slip' ->> 'loans_deduction')::numeric, (s ->> 'loans')::numeric),
      'net', COALESCE((s -> 'slip' ->> 'net_salary')::numeric, (s ->> 'net')::numeric),
      'absence_days', s -> 'absence_days', 'late_minutes', s -> 'late_minutes', 'pending', s -> 'pending_count',
      'issued', s -> 'slip' IS NOT NULL AND s -> 'slip' <> 'null'::jsonb) AS row
    FROM public.assistant_month_employees(p_month) m
    CROSS JOIN LATERAL (SELECT public.payroll_employee_summary(m.id, p_month) AS s) x
  ) y;
  RETURN jsonb_build_object(
    'month', p_month, 'period', jsonb_build_object('from', v_p.start_date, 'to', v_p.cutoff_date, 'status', v_p.status),
    'rows', v_rows,
    'totals', (SELECT jsonb_build_object('employees', count(*), 'issued', count(*) FILTER (WHERE (r ->> 'issued')::boolean),
                 'basic', sum((r ->> 'basic')::numeric), 'earnings', sum((r ->> 'earnings')::numeric),
                 'deductions', sum((r ->> 'deductions')::numeric), 'loans', sum((r ->> 'loans')::numeric),
                 'net', sum((r ->> 'net')::numeric))
               FROM jsonb_array_elements(v_rows) r));
END;
$$;


--
-- Name: assistant_pending_decisions(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_pending_decisions(p_branch text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_b text := public.assistant_norm(p_branch);
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('employee', e.full_name, 'branch', b.name, 'date', pe.event_date, 'type', pe.event_type,
                                        'minutes', pe.minutes, 'amount', round(pe.amount), 'payroll_month', pe.payroll_month)
                     ORDER BY pe.event_date, e.full_name)
    FROM payroll_events pe
    JOIN employees e ON e.id = pe.employee_id
    LEFT JOIN branches b ON b.id = e.branch_id
    WHERE pe.status = 'pending' AND pe.salary_slip_id IS NULL
      AND (v_b = '' OR public.assistant_norm(b.name) LIKE '%' || v_b || '%')
    LIMIT 200), '[]'::jsonb);
END;
$$;


--
-- Name: assistant_pending_events(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_pending_events(p_ids uuid[]) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('event_id', pe.id, 'employee', e.full_name, 'date', pe.event_date, 'type', pe.event_type,
                                        'minutes', pe.minutes, 'amount', round(pe.amount)))
    FROM payroll_events pe JOIN employees e ON e.id = pe.employee_id
    WHERE pe.id = ANY (p_ids) AND pe.status = 'pending' AND pe.salary_slip_id IS NULL
      AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch')), '[]'::jsonb);
END;
$$;


--
-- Name: assistant_save_messages(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_save_messages(p_conversation_id uuid, p_messages jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: assistant_set_morning_summary(boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_set_morning_summary(p_enabled boolean) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin();
  INSERT INTO system_settings (key, value, description)
  VALUES ('assistant_policy', jsonb_build_object('morning_summary', p_enabled), 'المساعد الذكي: الملخص الصباحي للأدمن (10:00)')
  ON CONFLICT (key) DO UPDATE SET value = system_settings.value || jsonb_build_object('morning_summary', p_enabled);
  RETURN p_enabled;
END;
$$;


--
-- Name: assistant_settings(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_settings() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin();
  RETURN jsonb_build_object('morning_summary',
    COALESCE((SELECT (value->>'morning_summary')::boolean FROM system_settings WHERE key = 'assistant_policy'), true));
END;
$$;


--
-- Name: assistant_top_late(date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assistant_top_late(p_from date, p_to date, p_branch text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_b text := public.assistant_norm(p_branch);
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(x ORDER BY (x ->> 'late_minutes')::numeric DESC)
    FROM (
      SELECT jsonb_build_object('employee', e.full_name, 'branch', b.name, 'late_days', count(*),
                                'late_minutes', sum(pe.minutes),
                                'deducted', round(sum(pe.amount) FILTER (WHERE pe.status = 'approved'))) AS x
      FROM payroll_events pe
      JOIN employees e ON e.id = pe.employee_id
      LEFT JOIN branches b ON b.id = e.branch_id
      WHERE pe.event_type = 'late' AND pe.status <> 'void' AND pe.event_date BETWEEN p_from AND p_to
        AND (v_b = '' OR public.assistant_norm(b.name) LIKE '%' || v_b || '%')
      GROUP BY e.full_name, b.name
      ORDER BY sum(pe.minutes) DESC
      LIMIT 20
    ) s), '[]'::jsonb);
END;
$$;


--
-- Name: calculate_payroll(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_payroll(p_month text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
DECLARE
  v_p payroll_periods%ROWTYPE;
BEGIN
  PERFORM public.require_admin();
  IF p_month !~ '^\d{4}-\d{2}$' THEN
    RAISE EXCEPTION 'صيغة الشهر غير صحيحة.' USING ERRCODE = '22023';
  END IF;
  IF p_month >= (SELECT min(period_month) FROM payroll_periods) THEN
    v_p := public.ensure_payroll_period(p_month);
    IF v_p.status = 'open' AND NOT EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month) THEN
      PERFORM public.sync_payroll_period(p_month);
      UPDATE payroll_periods SET calculated_at = now(), calculated_by = auth.uid() WHERE period_month = p_month;
    END IF;
  END IF;
  RETURN public.get_payroll_run(p_month);
END;
$_$;


--
-- Name: calculate_payroll_batch(text, uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculate_payroll_batch(p_month text, p_after uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 10) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
$_$;


--
-- Name: cancel_my_loan_request(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_my_loan_request(p_loan_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  UPDATE loans SET status = 'cancelled'
  WHERE id = p_loan_id AND employee_id = auth.uid() AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يمكن إلغاء هذا الطلب (غير موجود أو تمت معالجته).' USING ERRCODE = '55000';
  END IF;
END;
$$;


--
-- Name: check_and_send_attendance_reminders(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_and_send_attendance_reminders(p_now timestamp with time zone DEFAULT now()) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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
                         v_emp.full_name, public._ar_time(v_sched.check_in_time));
      ELSIF v_local >= v_start + v_after AND v_local < v_start + v_after + interval '2 minutes' THEN
        v_kind := 'checkin_late';
        v_title := '⚠️ لم تسجّل الحضور بعد';
        v_body := format('بدأ الدوام الساعة %s ولم يُسجَّل حضورك. سجّل بصمة الحضور الآن.',
                         public._ar_time(v_sched.check_in_time));
      END IF;
    ELSIF v_att.check_out_time IS NULL THEN
      IF v_local >= v_end - interval '15 minutes' AND v_local < v_end - interval '13 minutes' THEN
        v_kind := 'checkout_soon';
        v_title := '🔔 الدوام ينتهي خلال 15 دقيقة';
        v_body := format('ينتهي دوامك الساعة %s. لا تنسَ تسجيل الانصراف قبل المغادرة.',
                         public._ar_time(v_sched.check_out_time));
      ELSIF v_local >= v_end + v_after AND v_local < v_end + v_after + interval '2 minutes' THEN
        v_kind := 'checkout_late';
        v_title := '⚠️ لم تسجّل الانصراف';
        v_body := format('انتهى دوامك الساعة %s ولم يُسجَّل انصرافك. سجّل بصمة الانصراف الآن.',
                         public._ar_time(v_sched.check_out_time));
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


--
-- Name: FUNCTION check_and_send_attendance_reminders(p_now timestamp with time zone); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.check_and_send_attendance_reminders(p_now timestamp with time zone) IS 'يرسل تذكيرات البصمة حسب جدول دوام كل موظف. يُستدعى كل دقيقة من pg_cron. p_now للاختبار فقط.';


--
-- Name: check_archive_policy(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_archive_policy() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_days int;
BEGIN
  IF NEW.key = 'archive_policy' AND NEW.value ? 'tracking_archive_days' THEN
    v_days := (NEW.value ->> 'tracking_archive_days')::int;
    IF v_days IS NULL OR v_days < 35 OR v_days > 366 THEN
      RAISE EXCEPTION 'مدة الاحتفاظ ببيانات التتبع لازم تكون بين 35 و 366 يوم (حتى ما تنحذف نقاط مسير رواتب بعده مفتوح).'
        USING ERRCODE = '22023';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: check_bonus_deduction_amount(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_bonus_deduction_amount() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_salary numeric;
BEGIN
  SELECT monthly_salary_iqd INTO v_salary FROM employees WHERE id = NEW.employee_id;
  IF NEW.type = 'deduction' AND COALESCE(v_salary, 0) > 0 AND NEW.amount > v_salary THEN
    RAISE EXCEPTION 'مبلغ الخصم (% د.ع) أكبر من راتب الموظف الشهري (% د.ع). تأكد من المبلغ.',
      to_char(NEW.amount, 'FM999,999,999,999'), to_char(v_salary, 'FM999,999,999') USING ERRCODE = '22023';
  END IF;
  IF NEW.amount > 100000000 THEN
    RAISE EXCEPTION 'المبلغ كبير جداً (أكثر من 100,000,000 د.ع). تأكد من المبلغ.' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: check_employee_basics(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_employee_basics() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF btrim(COALESCE(NEW.full_name, '')) = '' THEN
    RAISE EXCEPTION 'اسم الموظف مطلوب.' USING ERRCODE = '23514';
  END IF;
  IF NEW.termination_date IS NOT NULL AND NEW.join_date IS NOT NULL AND NEW.termination_date < NEW.join_date THEN
    RAISE EXCEPTION 'تاريخ آخر يوم عمل (%) قبل تاريخ المباشرة (%).', NEW.termination_date, NEW.join_date USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: check_employee_branch(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_employee_branch() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF COALESCE(NEW.is_active, true) AND NEW.branch_id IS NULL THEN
    RAISE EXCEPTION 'اختر فرع الموظف: كل موظف نشط لازم يكون إله فرع.' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: clear_delivered_on_reopen(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clear_delivered_on_reopen() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.status <> 'closed' THEN
    NEW.delivered_at := NULL;
    NEW.delivered_by := NULL;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: close_payroll_period(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.close_payroll_period(p_month text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: company_timezone(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.company_timezone() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(
    (SELECT value #>> '{}' FROM system_settings WHERE key = 'timezone'),
    'Asia/Baghdad'
  );
$$;


--
-- Name: copy_legacy_push_token(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.copy_legacy_push_token() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_emp uuid;
  v_token text;
  v_platform text;
BEGIN
  -- كل جدول بأسماء أعمدته (الحقل اللي مو موجود ما ينقرا)
  IF TG_TABLE_NAME = 'employees' THEN
    v_emp := NEW.id;
    v_token := NEW.fcm_token;
  ELSE
    v_emp := NEW.employee_id;
    v_token := NEW.token;
    v_platform := NEW.platform;
  END IF;
  IF v_emp IS NOT NULL AND NULLIF(btrim(v_token), '') IS NOT NULL THEN
    INSERT INTO fcm_tokens (employee_id, token, device_platform, updated_at)
    VALUES (v_emp, v_token, v_platform, now())
    ON CONFLICT (employee_id, token) DO UPDATE SET updated_at = now();
  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: create_default_leave_balance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_default_leave_balance() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO leave_balances (employee_id) VALUES (NEW.id)
  ON CONFLICT (employee_id) DO NOTHING;
  RETURN NEW;
END;
$$;


--
-- Name: create_direct_loan(uuid, numeric, integer, date, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_direct_loan(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_pledge_url text, p_notes text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_base numeric;
  v_loan_id uuid;
BEGIN
  PERFORM public.require_admin();

  IF p_pledge_url IS NULL OR btrim(p_pledge_url) = '' THEN
    RAISE EXCEPTION 'صورة التعهد الخطي إلزامية لكل سلفة.' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM employees WHERE id = p_employee_id AND is_active) THEN
    RAISE EXCEPTION 'الموظف غير موجود أو غير نشط.' USING ERRCODE = 'P0002';
  END IF;

  v_base := public._validate_loan_terms(p_employee_id, p_amount, p_months, p_first_due);

  -- تُدرج معتمدة مباشرة، فلا يُرسل تنبيه "طلب جديد" للمدراء (المُطلق يعمل على 'pending' فقط)
  INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount,
                     pledge_url, status, notes, approved_by, approved_at)
  VALUES (p_employee_id, p_amount, v_base, p_months, p_amount,
          p_pledge_url, 'approved', NULLIF(btrim(COALESCE(p_notes, '')), ''), auth.uid(), now())
  RETURNING id INTO v_loan_id;

  PERFORM public._insert_loan_installments(v_loan_id, p_amount, p_months, p_first_due);

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (
    p_employee_id,
    'تم منحك سلفة مالية جديدة 💸',
    format('تم اعتماد سلفة جديدة لك بقيمة %s د.ع مقسمة على %s أقساط شهرية.',
           to_char(p_amount, 'FM999G999G999'), p_months),
    'loan'
  );

  RETURN v_loan_id;
END;
$$;


--
-- Name: FUNCTION create_direct_loan(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_pledge_url text, p_notes text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.create_direct_loan(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_pledge_url text, p_notes text) IS 'منح سلفة معتمدة مباشرة لموظف مع أقساطها وإشعاره، في معاملة واحدة. مقفل على الأدمن.';


--
-- Name: create_employee_secure(text, text, text, text, text, uuid, numeric, text[], text, uuid, date, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_employee_secure(p_email text, p_password text, p_full_name text, p_phone text, p_role text, p_branch_id uuid, p_monthly_salary_iqd numeric, p_document_urls text[], p_employee_code text, p_employee_id uuid DEFAULT NULL::uuid, p_join_date date DEFAULT NULL::date, p_department_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
  new_user_id uuid;
  new_identity_id uuid;
  hashed_password text;
  v_caller_id uuid;
BEGIN
  -- التحقق من هوية وصلاحية المنفذ
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح: تتطلب هذه العملية صلاحية مسؤول النظام (Admin).';
  END IF;

  -- التحقق من عدم تكرار البريد الإلكتروني
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = p_email) THEN
    RAISE EXCEPTION 'البريد الإلكتروني مسجل بالفعل لموظف آخر';
  END IF;

  new_user_id := COALESCE(p_employee_id, gen_random_uuid());
  new_identity_id := gen_random_uuid();
  hashed_password := extensions.crypt(p_password, extensions.gen_salt('bf'));

  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    is_super_admin,
    is_sso_user,
    is_anonymous,
    phone,
    phone_confirmed_at,
    created_at,
    updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    new_user_id,
    'authenticated',
    'authenticated',
    p_email,
    hashed_password,
    now(),
    '{"provider": "email", "providers": ["email"]}'::jsonb,
    json_build_object('full_name', p_full_name),
    false,
    false,
    false,
    p_phone,
    CASE WHEN p_phone IS NOT NULL AND p_phone != '' THEN now() ELSE NULL END,
    now(),
    now()
  );

  INSERT INTO auth.identities (
    id,
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    new_identity_id,
    new_user_id::text,
    new_user_id,
    json_build_object(
      'sub', new_user_id::text,
      'email', p_email,
      'email_verified', true,
      'phone_verified', false
    ),
    'email',
    NULL,
    now(),
    now()
  );

  INSERT INTO public.employees (
    id,
    employee_code,
    full_name,
    email,
    phone,
    role,
    branch_id,
    department_id,
    monthly_salary_iqd,
    is_active,
    must_change_password,
    document_urls,
    join_date,
    created_at
  ) VALUES (
    new_user_id,
    p_employee_code,
    p_full_name,
    p_email,
    NULLIF(p_phone, ''),
    p_role,
    p_branch_id,
    p_department_id,
    p_monthly_salary_iqd,
    true,
    true,
    to_jsonb(COALESCE(p_document_urls, ARRAY[]::text[])),
    COALESCE(p_join_date, (now() AT TIME ZONE public.company_timezone())::date),
    now()
  );

  RETURN new_user_id;
END;
$$;


--
-- Name: FUNCTION create_employee_secure(p_email text, p_password text, p_full_name text, p_phone text, p_role text, p_branch_id uuid, p_monthly_salary_iqd numeric, p_document_urls text[], p_employee_code text, p_employee_id uuid, p_join_date date, p_department_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.create_employee_secure(p_email text, p_password text, p_full_name text, p_phone text, p_role text, p_branch_id uuid, p_monthly_salary_iqd numeric, p_document_urls text[], p_employee_code text, p_employee_id uuid, p_join_date date, p_department_id uuid) IS 'إنشاء موظف جديد مع حساب Supabase Auth مربوط. مقفل على الأدمن فقط.
البارامترات: email, password, full_name, phone, role, branch_id, monthly_salary_iqd,
document_urls, employee_code, employee_id?, join_date?, department_id?.
يعيد UUID الموظف الجديد.';


--
-- Name: decide_absence_day(uuid, date, boolean, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decide_absence_day(p_employee_id uuid, p_date date, p_approve boolean, p_reason text DEFAULT NULL::text, p_amount numeric DEFAULT NULL::numeric) RETURNS public.payroll_events
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: decide_payroll_event(uuid, boolean, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.decide_payroll_event(p_event_id uuid, p_approve boolean, p_reason text DEFAULT NULL::text, p_amount numeric DEFAULT NULL::numeric) RETURNS public.payroll_events
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
  v_computed numeric;
  v_daily numeric;
  v_cap numeric;
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
    -- مدير الفرع ما يشوف المبالغ (منها ينعرف الراتب)، فما يكتب مبلغ: يقرر خصم بالمحسوب أو إعفاء
    IF NOT public.is_admin() THEN
      RAISE EXCEPTION 'مبلغ الخصم يحدده مسؤول النظام (الأدمن). مدير الفرع يقرر خصم بالمبلغ المحسوب أو إعفاء.'
        USING ERRCODE = '42501';
    END IF;
    -- الحد حسب النوع: الخصم ≤ أجر يوم (العقوبة الأكبر = «خصم يدوي» بسبب)، الإضافي ≤ المحسوب (الأكثر = «مكافأة»)
    v_computed := public._payroll_event_computed_amount(e);
    v_daily := round(COALESCE(e.daily_rate, public.payroll_daily_rate(e.employee_id, e.payroll_month)) * GREATEST(e.days, 1), 2);
    v_cap := CASE WHEN e.event_type = 'overtime' THEN v_computed ELSE v_daily END;
    IF v_amount > v_cap THEN
      IF e.event_type = 'overtime' THEN
        RAISE EXCEPTION 'مبلغ الإضافي ما يتجاوز المحسوب (% د.ع). للمبلغ الأكبر سجّل «مكافأة» بسبب واضح.',
          to_char(v_cap, 'FM999,999,990') USING ERRCODE = '22023';
      END IF;
      RAISE EXCEPTION 'خصم % ما يتجاوز أجر يوم واحد (% د.ع). للعقوبة الأكبر سجّل «خصم يدوي» بسبب واضح.',
        COALESCE(v_labels ->> e.event_type, ''), to_char(v_cap, 'FM999,999,990') USING ERRCODE = '22023';
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
  -- الرد لمدير الفرع بدون مبالغ (منها ينعرف الراتب)
  IF NOT public.is_admin() THEN
    e.amount := NULL; e.amount_override := NULL; e.daily_rate := NULL; e.minute_rate := NULL;
  END IF;
  RETURN e;
END;
$$;


--
-- Name: destroy_archived_employee(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.destroy_archived_employee(p_archive_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  a archived_employees%ROWTYPE;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO a FROM archived_employees WHERE id = p_archive_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'سجل الأرشيف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF EXISTS (SELECT 1 FROM employees WHERE id = a.employee_id) THEN
    PERFORM public.safe_delete_employee(a.employee_id);
  END IF;
  UPDATE archived_employees
  SET archive_type = 'permanent', notes = 'تم الإتلاف النهائي اليدوي للبيانات والحساب من قبل المسؤول.'
  WHERE id = p_archive_id;
END;
$$;


--
-- Name: distance_meters(double precision, double precision, double precision, double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.distance_meters(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;


--
-- Name: employee_assignment_at(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.employee_assignment_at(p_employee_id uuid, p_date date) RETURNS TABLE(branch_id uuid, department_id uuid)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT x.branch_id, x.department_id FROM (
    (SELECT h.branch_id, h.department_id, 0 AS pri
     FROM employee_assignment_history h
     WHERE h.employee_id = p_employee_id AND h.effective_from <= p_date
     ORDER BY h.effective_from DESC, h.recorded_at DESC, h.id DESC
     LIMIT 1)
    UNION ALL
    (SELECT e.branch_id, e.department_id, 1 FROM employees e WHERE e.id = p_employee_id)
  ) x
  ORDER BY x.pri
  LIMIT 1;
$$;


--
-- Name: employee_in_service(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.employee_in_service(p_employee_id uuid, p_date date) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE((
    SELECT (e.join_date IS NULL OR p_date >= e.join_date)
       AND (e.termination_date IS NULL OR p_date <= e.termination_date)
       AND NOT EXISTS (SELECT 1 FROM employee_service_breaks b
                       WHERE b.employee_id = e.id AND p_date > b.last_day AND p_date < b.return_date)
    FROM employees e WHERE e.id = p_employee_id), false);
$$;


--
-- Name: employee_shift_hours(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.employee_shift_hours(p_employee_id uuid) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(
    (SELECT NULLIF(
              EXTRACT(EPOCH FROM (
                CASE WHEN ws.check_out_time > ws.check_in_time
                     THEN ws.check_out_time - ws.check_in_time
                     ELSE ws.check_out_time - ws.check_in_time + interval '24 hours' END
              )) / 3600, 0)
     FROM work_schedules ws
     JOIN employees e ON e.id = p_employee_id
     WHERE ws.check_in_time IS NOT NULL AND ws.check_out_time IS NOT NULL
       AND (ws.employee_id = e.id
        OR (ws.employee_id IS NULL AND ws.department_id IS NOT NULL AND ws.department_id = e.department_id)
        OR (ws.employee_id IS NULL AND ws.department_id IS NULL AND ws.branch_id IS NOT NULL AND ws.branch_id = e.branch_id))
     ORDER BY CASE WHEN ws.employee_id IS NOT NULL THEN 0
                   WHEN ws.department_id IS NOT NULL THEN 1 ELSE 2 END,
              ws.created_at DESC
     LIMIT 1),
    8
  )::numeric;
$$;


--
-- Name: employee_work_days(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.employee_work_days(p_employee_id uuid) RETURNS integer[]
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(
    (SELECT ws.work_days
     FROM work_schedules ws
     JOIN employees e ON e.id = p_employee_id
     WHERE ws.employee_id = e.id
        OR (ws.employee_id IS NULL AND ws.department_id IS NOT NULL AND ws.department_id = e.department_id)
        OR (ws.employee_id IS NULL AND ws.department_id IS NULL AND ws.branch_id IS NOT NULL AND ws.branch_id = e.branch_id)
     ORDER BY CASE WHEN ws.employee_id IS NOT NULL THEN 0
                   WHEN ws.department_id IS NOT NULL THEN 1 ELSE 2 END,
              ws.created_at DESC
     LIMIT 1),
    ARRAY[0, 1, 2, 3, 4, 6]
  );
$$;


--
-- Name: end_employee_service(uuid, text, text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.end_employee_service(p_employee_id uuid, p_type text, p_reason text DEFAULT NULL::text, p_last_day date DEFAULT NULL::date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_emp employees%ROWTYPE;
  v_kind text := CASE p_type WHEN 'archive' THEN 'archived' WHEN 'scheduled' THEN 'scheduled_deletion' WHEN 'immediate' THEN 'permanent' END;
BEGIN
  PERFORM public.require_admin();
  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'نوع الإجراء غير معروف.' USING ERRCODE = '22023';
  END IF;
  IF p_employee_id = auth.uid() THEN
    RAISE EXCEPTION 'ما تكدر تنهي خدماتك بنفسك.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;

  -- آخر يوم عمل فعلي يحدد آخر راتب (بدونه = اليوم)
  UPDATE employees SET is_active = false, termination_date = COALESCE(p_last_day, termination_date) WHERE id = p_employee_id;

  INSERT INTO archived_employees (employee_id, employee_code, full_name, archive_type, archive_reason, scheduled_deletion_date, archived_by, archived_at)
  VALUES (p_employee_id, v_emp.employee_code, v_emp.full_name, v_kind,
          COALESCE(NULLIF(btrim(p_reason), ''),
                   CASE p_type WHEN 'immediate' THEN 'حذف فوري نهائي من لوحة التحكم'
                               WHEN 'scheduled' THEN 'حذف مجدول بعد 30 يوماً من لوحة التحكم'
                               ELSE 'أرشفة وتعطيل الحساب الإداري للموظف' END),
          CASE WHEN p_type = 'scheduled' THEN now() + interval '30 days' END,
          auth.uid(), now());

  IF p_type = 'immediate' THEN
    -- إخفاء الهوية وحذف حساب الدخول (المستمسكات والصورة تروح للسلة)
    PERFORM public.safe_delete_employee(p_employee_id);
  END IF;
END;
$$;


--
-- Name: end_of_service_preview(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.end_of_service_preview(p_employee_id uuid, p_last_day date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_emp employees%ROWTYPE;
  v_last_month text;
  v_month text;
  v_p payroll_periods%ROWTYPE;
  v_periods jsonb := '[]'::jsonb;
  v_total numeric := 0;
  v_loans_left numeric := 0;
  v_cut_total numeric := 0;
  v_s jsonb;
  v_net numeric;
  v_loans numeric;
  v_result jsonb;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF p_last_day IS NULL OR (v_emp.join_date IS NOT NULL AND p_last_day < v_emp.join_date) THEN
    RAISE EXCEPTION 'آخر يوم عمل لازم يكون بعد تاريخ المباشرة.' USING ERRCODE = '22023';
  END IF;

  v_last_month := public.payroll_month_of(p_last_day);
  BEGIN
    -- نجرّب: آخر يوم + إعادة حساب المسيرات المفتوحة، ونقرا النتيجة، وبعدها كلشي يتراجع (ما ينحفظ شي)
    UPDATE employees SET termination_date = p_last_day WHERE id = p_employee_id;
    FOR v_month IN
      SELECT pp.period_month FROM payroll_periods pp
      WHERE pp.status = 'open' AND pp.period_month <= v_last_month
        AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = p_employee_id AND s.work_month = pp.period_month)
      UNION
      SELECT v_last_month
      ORDER BY 1
    LOOP
      v_p := public.ensure_payroll_period(v_month);
      CONTINUE WHEN v_p.status <> 'open' OR EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = p_employee_id AND s.work_month = v_month);
      PERFORM public.sync_payroll_period(v_month, p_employee_id);
      v_s := public.payroll_employee_summary(p_employee_id, v_month);
      CONTINUE WHEN (v_s ->> 'employed_days')::int = 0 AND (v_s ->> 'net')::numeric = 0;
      v_net := (v_s ->> 'net')::numeric;
      v_loans := (v_s ->> 'loans')::numeric;
      v_periods := v_periods || jsonb_build_array(jsonb_build_object(
        'month', v_month, 'start_date', v_p.start_date, 'cutoff_date', v_p.cutoff_date,
        'can_approve_now', p_last_day < (now() AT TIME ZONE public.company_timezone())::date OR v_p.cutoff_date < (now() AT TIME ZONE public.company_timezone())::date,
        -- مثل الاعتماد: القسط ينقص بقد الراتب، وإذا الخصومات بعدها أكثر = صافي صفر والزايد خارج النظام
        'expected_net', GREATEST(v_net, 0),
        'loan_cut', LEAST(v_loans, GREATEST(-v_net, 0)),
        'excess_deductions', GREATEST(-(v_net + v_loans), 0),
        'summary', v_s));
      v_total := v_total + GREATEST(v_net, 0);
      v_cut_total := v_cut_total + LEAST(v_loans, GREATEST(-v_net, 0));
    END LOOP;
    SELECT COALESCE(sum(li.amount), 0) INTO v_loans_left
    FROM loan_installments li JOIN loans l ON l.id = li.loan_id
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
      AND li.due_date > (SELECT cutoff_date FROM payroll_periods WHERE period_month = v_last_month);
    -- الباقي من السلف بعد آخر راتب (مع الأقساط اللي تنقص لأن الراتب ما يكفي): الشركة تسويه ويا الموظف خارج النظام
    v_result := jsonb_build_object('employee_id', p_employee_id, 'last_day', p_last_day, 'periods', v_periods,
                                   'total_net', v_total, 'loans_left_after', v_loans_left + v_cut_total);
    RAISE EXCEPTION 'preview_rollback' USING ERRCODE = 'P0001';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'preview_rollback' THEN
      RAISE;
    END IF;
  END;
  RETURN v_result;
END;
$$;


--
-- Name: payroll_periods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_periods (
    period_month text NOT NULL,
    start_date date NOT NULL,
    cutoff_date date NOT NULL,
    payment_date date NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    closed_at timestamp with time zone,
    closed_by uuid,
    reopened_at timestamp with time zone,
    reopened_by uuid,
    reopen_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    calculated_at timestamp with time zone,
    calculated_by uuid,
    delivered_at timestamp with time zone,
    delivered_by uuid,
    CONSTRAINT payroll_periods_check CHECK ((cutoff_date >= start_date)),
    CONSTRAINT payroll_periods_period_month_check CHECK ((period_month ~ '^\d{4}-\d{2}$'::text)),
    CONSTRAINT payroll_periods_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text])))
);


--
-- Name: TABLE payroll_periods; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payroll_periods IS 'مسيرات الرواتب: من اليوم التالي لقطع الشهر السابق حتى يوم القطع (26) من الشهر.';


--
-- Name: COLUMN payroll_periods.calculated_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll_periods.calculated_at IS 'آخر «احتساب الرواتب» لهذا المسير';


--
-- Name: COLUMN payroll_periods.delivered_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.payroll_periods.delivered_at IS 'الأدمن أكد إن رواتب هذا المسير تسلّمت للموظفين فعلاً (شرط لتنظيف حضور المسير اللي قبله)';


--
-- Name: ensure_payroll_period(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_payroll_period(p_month text) RETURNS public.payroll_periods
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: fmt_days(numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fmt_days(v numeric) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT CASE WHEN v = trunc(v) THEN trunc(v)::text ELSE rtrim(rtrim(round(v, 2)::text, '0'), '.') END;
$$;


--
-- Name: get_absent_today(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_absent_today() RETURNS TABLE(employee_id uuid, full_name text, avatar_url text, branch_name text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: get_active_announcements(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_active_announcements(p_limit integer DEFAULT 20) RETURNS SETOF public.announcements
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT a.*
  FROM announcements a
  WHERE auth.uid() IS NOT NULL
    AND a.starts_at <= now()
    AND (a.ends_at IS NULL OR a.ends_at > now())
    AND public.announcement_targets(a, auth.uid())
  ORDER BY a.is_pinned DESC, a.starts_at DESC
  LIMIT GREATEST(COALESCE(p_limit, 20), 1);
$$;


--
-- Name: get_database_size(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_database_size() RETURNS TABLE(db_size bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin_or_manager();
  RETURN QUERY SELECT pg_database_size(current_database())::bigint AS db_size;
END;
$$;


--
-- Name: FUNCTION get_database_size(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_database_size() IS 'يعيد حجم قاعدة البيانات الحالي بالبايت. يستخدم في شاشة storage_stats.';


--
-- Name: get_database_table_sizes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_database_table_sizes() RETURNS TABLE(table_name text, row_count bigint, total_bytes bigint, pretty_size text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin_or_manager();

  RETURN QUERY
  SELECT
    c.relname::text AS table_name,
    c.reltuples::bigint AS row_count,
    pg_total_relation_size(c.oid)::bigint AS total_bytes,
    pg_size_pretty(pg_total_relation_size(c.oid))::text AS pretty_size
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
  ORDER BY pg_total_relation_size(c.oid) DESC;
END;
$$;


--
-- Name: FUNCTION get_database_table_sizes(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_database_table_sizes() IS 'يعيد قائمة الجداول مع أحجامها للعرض في لوحة الإدارة.';


--
-- Name: get_effective_work_schedule(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_effective_work_schedule(p_employee_id uuid DEFAULT NULL::uuid) RETURNS SETOF public.work_schedules
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_emp_id uuid := COALESCE(p_employee_id, auth.uid());
BEGIN
  IF auth.uid() IS NOT NULL AND v_emp_id <> auth.uid()
     AND NOT (public.is_admin() OR v_emp_id = ANY (public.managed_employee_ids())) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT ws.*
  FROM work_schedules ws
  JOIN employees e ON e.id = v_emp_id
  WHERE ws.employee_id = e.id
     OR (ws.employee_id IS NULL AND ws.department_id IS NOT NULL
         AND ws.department_id = e.department_id)
     OR (ws.employee_id IS NULL AND ws.department_id IS NULL
         AND ws.branch_id IS NOT NULL AND ws.branch_id = e.branch_id)
  ORDER BY
    CASE
      WHEN ws.employee_id IS NOT NULL THEN 0
      WHEN ws.department_id IS NOT NULL THEN 1
      ELSE 2
    END,
    ws.created_at DESC
  LIMIT 1;
END;
$$;


--
-- Name: get_employee_directory(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_employee_directory() RETURNS TABLE(id uuid, employee_code text, full_name text, phone text, email text, avatar_url text, role text, department_id uuid, department_name text, branch_id uuid, branch_name text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT e.id, e.employee_code, e.full_name, e.phone, e.email, e.avatar_url,
         e.role, e.department_id, d.name, e.branch_id, b.name
  FROM employees e
  LEFT JOIN departments d ON d.id = e.department_id
  LEFT JOIN branches b ON b.id = e.branch_id
  WHERE e.is_active = true
  ORDER BY e.full_name;
END;
$$;


--
-- Name: get_employee_history(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_employee_history(p_employee_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_emp employees%ROWTYPE;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_events jsonb;
BEGIN
  IF NOT (public.is_admin() OR p_employee_id = auth.uid() OR p_employee_id = ANY (public.managed_employee_ids())) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  IF NOT FOUND THEN
    RETURN '[]'::jsonb;
  END IF;

  WITH h AS (
    SELECT hh.effective_from, hh.branch_id, hh.department_id,
           lag(hh.branch_id) OVER w AS prev_branch, lag(hh.department_id) OVER w AS prev_dept,
           row_number() OVER w AS rn
    FROM employee_assignment_history hh
    WHERE hh.employee_id = p_employee_id
    WINDOW w AS (ORDER BY hh.effective_from, hh.recorded_at, hh.id)
  ), ev AS (
    SELECT v_emp.join_date AS d, 1 AS ord, 'join' AS kind,
           'باشر بالعمل' || COALESCE(' بفرع ' || (SELECT b.name FROM h JOIN branches b ON b.id = h.branch_id WHERE h.rn = 1), '') AS txt
    WHERE v_emp.join_date IS NOT NULL
    UNION ALL
    SELECT h.effective_from, 2, 'transfer',
           concat_ws('، ',
             CASE WHEN h.branch_id IS DISTINCT FROM h.prev_branch THEN
               format('انتقل من %s إلى %s',
                      COALESCE(bp.name, CASE WHEN h.prev_branch IS NULL THEN 'بدون فرع' ELSE 'فرع محذوف' END),
                      COALESCE(bn.name, CASE WHEN h.branch_id IS NULL THEN 'بدون فرع' ELSE 'فرع محذوف' END)) END,
             CASE WHEN h.department_id IS DISTINCT FROM h.prev_dept THEN
               format('صار بقسم %s', COALESCE(dn.name, CASE WHEN h.department_id IS NULL THEN 'عام (بدون قسم)' ELSE 'قسم محذوف' END)) END)
    FROM h
    LEFT JOIN branches bp ON bp.id = h.prev_branch
    LEFT JOIN branches bn ON bn.id = h.branch_id
    LEFT JOIN departments dn ON dn.id = h.department_id
    WHERE h.rn > 1 AND (h.branch_id IS DISTINCT FROM h.prev_branch OR h.department_id IS DISTINCT FROM h.prev_dept)
    UNION ALL
    SELECT b.last_day, 3, 'exit', 'ترك العمل (آخر يوم عمل)' FROM employee_service_breaks b WHERE b.employee_id = p_employee_id
    UNION ALL
    SELECT b.return_date, 4, 'return', format('رجع للعمل بعد انقطاع %s يوم', b.return_date - b.last_day - 1)
    FROM employee_service_breaks b WHERE b.employee_id = p_employee_id
    UNION ALL
    SELECT v_emp.termination_date, 5, 'exit',
           CASE WHEN v_emp.termination_date >= v_today THEN 'آخر يوم عمل (انتهاء الخدمات)' ELSE 'انتهت خدماته (آخر يوم عمل)' END
    WHERE v_emp.termination_date IS NOT NULL
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object('date', ev.d, 'kind', ev.kind, 'text', ev.txt) ORDER BY ev.d, ev.ord), '[]'::jsonb)
  INTO v_events
  FROM ev;
  RETURN v_events;
END;
$$;


--
-- Name: get_employee_pay(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_employee_pay(p_employee_ids uuid[] DEFAULT NULL::uuid[]) RETURNS TABLE(employee_id uuid, monthly_salary_iqd numeric, future_salary_iqd numeric, future_salary_month text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  -- الأدمن: رواتب الكل (أو المطلوبين). أي مستخدم ثاني: راتبه هو بس
  SELECT e.id, e.monthly_salary_iqd, e.future_salary_iqd, e.future_salary_month
  FROM employees e
  WHERE (p_employee_ids IS NULL OR e.id = ANY (p_employee_ids))
    AND (public.is_admin() OR e.id = auth.uid());
$$;


--
-- Name: get_late_today(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_late_today() RETURNS TABLE(employee_id uuid, full_name text, avatar_url text, branch_name text, check_in_time timestamp with time zone, late_minutes integer)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT e.id, e.full_name, e.avatar_url, b.name, a.check_in_time,
         COALESCE(GREATEST(floor(public.payroll_local_minutes(a.check_in_time)
                                 - public.payroll_time_minutes(ws.check_in_time)), 0)::integer, 0)
  FROM attendance a
  JOIN employees e ON e.id = a.employee_id AND e.is_active
  LEFT JOIN branches b ON b.id = e.branch_id
  LEFT JOIN LATERAL public.payroll_schedule(e.id) ws ON true
  WHERE a.work_date = v_today
    AND a.status = 'late'
    AND a.deduction_status = 'applied'   -- يظهر بس إذا الإدارة طبّقت خصم التأخير
    AND a.check_in_time IS NOT NULL
  ORDER BY a.check_in_time;
END;
$$;


--
-- Name: get_leave_balance(uuid, date, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_leave_balance(p_employee_id uuid DEFAULT NULL::uuid, p_on date DEFAULT NULL::date, p_exclude uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_emp uuid := COALESCE(p_employee_id, auth.uid());
  v_tz text := public.company_timezone();
  v_on date := COALESCE(p_on, (now() AT TIME ZONE public.company_timezone())::date);
  v_year_start date := date_trunc('year', v_on)::date;
  v_month_start date := date_trunc('month', v_on)::date;
  v_policy jsonb := public.leave_policy();
  v_lb leave_balances%ROWTYPE;
  v_annual numeric; v_sick numeric; v_hours numeric;
  r record;
BEGIN
  IF auth.uid() IS NOT NULL AND v_emp <> auth.uid()
     AND NOT (public.is_admin() OR v_emp = ANY (public.managed_employee_ids())) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_lb FROM leave_balances WHERE employee_id = v_emp;
  v_annual := COALESCE(v_lb.annual_entitlement, (v_policy ->> 'default_annual')::numeric, 21);
  v_sick   := COALESCE(v_lb.sick_entitlement, (v_policy ->> 'default_sick')::numeric, 15);
  v_hours  := COALESCE(v_lb.hourly_monthly_hours, (v_policy ->> 'hourly_monthly_hours')::numeric, 8);

  SELECT
    COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'annual' AND lr.status = 'approved'), 0) AS annual_used,
    COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'annual' AND lr.status = 'pending'), 0) AS annual_pending,
    COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'sick' AND lr.status = 'approved'), 0) AS sick_used,
    COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'sick' AND lr.status = 'pending'), 0) AS sick_pending
  INTO r
  FROM leave_requests lr
  WHERE lr.employee_id = v_emp
    AND lr.id IS DISTINCT FROM p_exclude
    AND NOT COALESCE(lr.is_hourly, false)
    AND (lr.start_date AT TIME ZONE v_tz)::date >= v_year_start
    AND (lr.start_date AT TIME ZONE v_tz)::date < (v_year_start + interval '1 year')::date;

  RETURN jsonb_build_object(
    'year', EXTRACT(YEAR FROM v_on)::int,
    'month', to_char(v_on, 'YYYY-MM'),
    'annual', jsonb_build_object('entitlement', v_annual, 'used', r.annual_used, 'pending', r.annual_pending,
                                 'left', v_annual - r.annual_used - r.annual_pending),
    'sick', jsonb_build_object('entitlement', v_sick, 'used', r.sick_used, 'pending', r.sick_pending,
                               'left', v_sick - r.sick_used - r.sick_pending),
    'hourly', (
      SELECT jsonb_build_object(
        'allowance_hours', v_hours,
        'used_hours', COALESCE(SUM(public.leave_request_hours(lr)) FILTER (WHERE lr.status = 'approved'), 0),
        'pending_hours', COALESCE(SUM(public.leave_request_hours(lr)) FILTER (WHERE lr.status = 'pending'), 0),
        'left_hours', v_hours - COALESCE(SUM(public.leave_request_hours(lr)) FILTER (WHERE lr.status IN ('approved', 'pending')), 0))
      FROM leave_requests lr
      WHERE lr.employee_id = v_emp
        AND lr.id IS DISTINCT FROM p_exclude
        AND lr.is_hourly
        AND (lr.start_date AT TIME ZONE v_tz)::date >= v_month_start
        AND (lr.start_date AT TIME ZONE v_tz)::date < (v_month_start + interval '1 month')::date
    )
  );
END;
$$;


--
-- Name: FUNCTION get_leave_balance(p_employee_id uuid, p_on date, p_exclude uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_leave_balance(p_employee_id uuid, p_on date, p_exclude uuid) IS 'رصيد الإجازات: السنوية والمرضية للسنة، والزمنيات للشهر. الموظف يرى رصيده فقط؛ الأدمن والمدير أي موظف.';


--
-- Name: get_my_payroll_preview(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_payroll_preview() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_me uuid := auth.uid();
  v_month text;
  v_p payroll_periods%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;
  v_month := public.payroll_natural_month((now() AT TIME ZONE public.company_timezone())::date);
  IF v_month IS NULL THEN
    RETURN NULL;
  END IF;
  v_p := public.ensure_payroll_period(v_month);
  PERFORM public.sync_payroll_period(v_month, v_me);

  RETURN jsonb_build_object(
    'period', to_jsonb(v_p),
    -- اللي ينتظر قرار الإدارة ما يبين للموظف (قاعدة: التأخير ما يظهر قبل الخصم)
    'summary', public.payroll_employee_summary(v_me, v_month) || jsonb_build_object('pending_count', 0, 'missing_punches', 0),
    'events', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'event_date', pe.event_date, 'event_type', pe.event_type, 'minutes', pe.minutes, 'days', pe.days,
               'amount', pe.amount, 'direction', pe.direction, 'status', pe.status, 'notes', pe.notes,
               'carried_from', pe.carried_from)
             ORDER BY pe.event_date, pe.event_type)
      FROM payroll_events pe
      WHERE pe.employee_id = v_me AND pe.payroll_month = v_month AND pe.status = 'approved'
        AND (pe.amount > 0 OR pe.event_type = 'paid_leave')), '[]'::jsonb)
  );
END;
$$;


--
-- Name: get_on_leave_now(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_on_leave_now() RETURNS TABLE(employee_id uuid, full_name text, avatar_url text, branch_name text, is_hourly boolean, from_date date, to_date date, start_hour time without time zone, end_hour time without time zone)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_tz text := public.company_timezone();
  v_local timestamp := now() AT TIME ZONE public.company_timezone();
  v_today date := v_local::date;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT DISTINCT ON (e.id)
    e.id, e.full_name, e.avatar_url, b.name,
    COALESCE(lr.is_hourly, false),
    (lr.start_date AT TIME ZONE v_tz)::date,
    (lr.end_date AT TIME ZONE v_tz)::date,
    lr.start_hour, lr.end_hour
  FROM leave_requests lr
  JOIN employees e ON e.id = lr.employee_id AND e.is_active
  LEFT JOIN branches b ON b.id = e.branch_id
  WHERE lr.status = 'approved'
    AND v_today BETWEEN (lr.start_date AT TIME ZONE v_tz)::date AND (lr.end_date AT TIME ZONE v_tz)::date
    AND (
      NOT COALESCE(lr.is_hourly, false)
      -- الزمنية تظهر طوال يومها حتى تنتهي ساعتها
      OR COALESCE(lr.end_hour, (lr.end_date AT TIME ZONE v_tz)::time) > v_local::time
    )
  ORDER BY e.id, COALESCE(lr.is_hourly, false), e.full_name;
END;
$$;


--
-- Name: get_orphan_storage_candidates(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_orphan_storage_candidates() RETURNS TABLE(bucket_id text, file_path text, file_size bigint, created_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin();

  RETURN QUERY
  SELECT
    CASE
      WHEN df.file_type = 'avatar' THEN 'avatars'::TEXT
      WHEN df.file_type = 'document' THEN 'employee-documents'::TEXT
      WHEN df.file_type = 'pledge' THEN 'loan-pledges'::TEXT
      WHEN df.file_type = 'logo' THEN 'company-logos'::TEXT
      ELSE 'employee-documents'::TEXT
    END as bucket_id,
    df.file_path,
    COALESCE(df.file_size_bytes, 0) as file_size,
    df.deleted_at as created_at
  FROM public.deleted_files df
  WHERE df.restored_at IS NULL;
END;
$$;


--
-- Name: FUNCTION get_orphan_storage_candidates(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_orphan_storage_candidates() IS 'يعيد الملفات في التخزين التي لا يوجد لها سجل في قاعدة البيانات (ملفات يتيمة).
لا يحذف — فقط يعيد مرشحين للحذف اليدوي من قِبل الأدمن.';


--
-- Name: get_payroll_event_amounts(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_payroll_event_amounts(p_from date, p_to date) RETURNS TABLE(event_id uuid, employee_id uuid, event_date date, event_type text, amount numeric)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT pe.id, pe.employee_id, pe.event_date, pe.event_type, pe.amount
  FROM payroll_events pe
  WHERE public.is_admin() AND pe.status <> 'void' AND pe.event_date BETWEEN p_from AND p_to;
$$;


--
-- Name: get_payroll_events(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_payroll_events(p_month text, p_employee_id uuid DEFAULT NULL::uuid) RETURNS SETOF public.payroll_events
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  r payroll_events%ROWTYPE;
  v_admin boolean := public.is_admin();
BEGIN
  FOR r IN
    SELECT pe.* FROM payroll_events pe
    WHERE (v_admin
           OR (pe.employee_id = auth.uid() AND pe.status = 'approved')
           OR (pe.employee_id <> auth.uid() AND public.is_manager() AND public.payroll_same_branch(pe.employee_id)))
      AND pe.payroll_month = p_month
      AND (p_employee_id IS NULL OR pe.employee_id = p_employee_id)
      AND pe.status <> 'void'
    ORDER BY pe.event_date, pe.event_type
  LOOP
    IF NOT v_admin AND r.employee_id <> auth.uid() THEN
      r.amount := NULL; r.amount_override := NULL; r.daily_rate := NULL; r.minute_rate := NULL;
    END IF;
    RETURN NEXT r;
  END LOOP;
END;
$$;


--
-- Name: get_payroll_run(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_payroll_run(p_month text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_rows jsonb;
BEGIN
  PERFORM public.require_admin();
  IF p_month !~ '^\d{4}-\d{2}$' THEN
    RAISE EXCEPTION 'صيغة الشهر غير صحيحة.' USING ERRCODE = '22023';
  END IF;

  -- أشهر قبل نظام المسيرات: عرض الكشوف القديمة كما حُفظت (بدون حساب)
  IF p_month < (SELECT min(period_month) FROM payroll_periods) THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'employee_id', e.id, 'full_name', e.full_name, 'branch_id', e.branch_id, 'branch_name', b.name,
             'join_date', e.join_date, 'termination_date', e.termination_date, 'is_active', e.is_active,
             'period_days', 0, 'employed_days', 0, 'monthly_salary', COALESCE(e.monthly_salary_iqd, 0),
             'daily_rate', COALESCE(e.monthly_salary_iqd, 0) / 30.0, 'minute_rate', 0, 'shift_minutes', 480,
             'basic', s.basic_salary, 'earnings', s.allowances, 'bonuses', s.allowances, 'overtime', 0,
             'deductions', s.deductions, 'attendance_deductions', 0, 'loans', s.loans_deduction, 'net', s.net_salary,
             'pending_count', 0, 'missing_punches', 0, 'absence_days', 0, 'late_minutes', 0, 'early_minutes', 0,
             'overtime_minutes', 0, 'paid_leave_days', 0, 'unpaid_leave_days', 0,
             'slip', jsonb_build_object('id', s.id, 'basic_salary', s.basic_salary, 'allowances', s.allowances,
                                        'deductions', s.deductions, 'loans_deduction', s.loans_deduction,
                                        'net_salary', s.net_salary, 'created_at', s.created_at, 'legacy', true))
           ORDER BY e.full_name), '[]'::jsonb)
    INTO v_rows
    FROM salary_slips s
    JOIN employees e ON e.id = s.employee_id
    LEFT JOIN branches b ON b.id = e.branch_id
    WHERE s.work_month = p_month;

    RETURN jsonb_build_object(
      'period', jsonb_build_object(
        'period_month', p_month,
        'start_date', to_char((p_month || '-01')::date, 'YYYY-MM-DD'),
        'cutoff_date', to_char((p_month || '-01')::date + interval '1 month - 1 day', 'YYYY-MM-DD'),
        'payment_date', NULL, 'status', 'closed', 'legacy', true,
        'archived', EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month)),
      'rows', v_rows);
  END IF;

  v_p := public.ensure_payroll_period(p_month);
  -- بدون إعادة حساب عند كل فتح (كان يعيد كل يوم لكل موظف): الحساب بزر «احتساب الرواتب» + التحديث الليلي

  SELECT COALESCE(jsonb_agg(
           public.payroll_employee_summary(e.id, p_month)
             || jsonb_build_object('full_name', e.full_name, 'branch_id', e.branch_id, 'branch_name', b.name,
                                   'join_date', e.join_date, 'termination_date', e.termination_date,
                                   'is_active', e.is_active)
           ORDER BY e.full_name), '[]'::jsonb)
  INTO v_rows
  FROM employees e
  LEFT JOIN branches b ON b.id = e.branch_id
  WHERE (
      (e.join_date IS NULL OR e.join_date <= v_p.cutoff_date)
      AND (e.termination_date IS NULL OR e.termination_date >= v_p.start_date)
      AND (e.is_active OR e.termination_date IS NOT NULL)
    )
    -- من له كشف معتمد في هذا الشهر يظهر دائماً (حتى لو عُطّل حسابه لاحقاً)
    OR EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = e.id AND s.work_month = p_month);

  RETURN jsonb_build_object(
    'period', to_jsonb(v_p) || jsonb_build_object('archived', EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month)),
    'rows', v_rows
  );
END;
$_$;


--
-- Name: get_pending_payroll_decisions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_pending_payroll_decisions() RETURNS TABLE(id uuid, employee_id uuid, full_name text, branch_id uuid, branch_name text, event_date date, event_type text, minutes numeric, days numeric, amount numeric, direction smallint, payroll_month text, carried_from text, status text, source text, source_id uuid, notes text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
#variable_conflict use_column
DECLARE
  v_admin boolean := public.is_admin();
BEGIN
  PERFORM public.require_admin_or_manager();
  RETURN QUERY
  SELECT pe.id, pe.employee_id, e.full_name, e.branch_id, b.name, pe.event_date, pe.event_type, pe.minutes, pe.days,
         CASE WHEN v_admin THEN pe.amount END, pe.direction, pe.payroll_month, pe.carried_from, pe.status, pe.source,
         pe.source_id, pe.notes
  FROM payroll_events pe
  JOIN employees e ON e.id = pe.employee_id
  LEFT JOIN branches b ON b.id = e.branch_id
  JOIN payroll_periods p ON p.period_month = pe.payroll_month AND p.status = 'open'
  WHERE pe.status = 'pending'
    AND (v_admin OR (pe.employee_id <> auth.uid() AND public.payroll_same_branch(pe.employee_id)))
    AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch', 'overtime')
  ORDER BY pe.event_date DESC, e.full_name;
END;
$$;


--
-- Name: get_storage_stats(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_storage_stats() RETURNS TABLE(bucket_name text, total_size bigint, file_count bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'storage'
    AS $$
BEGIN
    PERFORM public.require_admin_or_manager();

    RETURN QUERY
    SELECT
        b.id::TEXT AS bucket_name,
        COALESCE(SUM(
            COALESCE(
                (o.metadata->>'size')::BIGINT,
                (o.metadata->>'contentLength')::BIGINT,
                (o.user_metadata->>'size')::BIGINT,
                0
            )
        ), 0)::BIGINT AS total_size,
        COUNT(o.id)::BIGINT AS file_count
    FROM storage.buckets b
    LEFT JOIN storage.objects o ON o.bucket_id = b.id
    GROUP BY b.id
    ORDER BY b.id;
END;
$$;


--
-- Name: FUNCTION get_storage_stats(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_storage_stats() IS 'إحصائيات تخزين موثوقة: حجم بايت + عدد ملفات لكل bucket. تستعمل عدة مفاتيح احتياطية في metadata.';


--
-- Name: guard_bonus_deduction_entry(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_bonus_deduction_entry() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  NEW.created_by := COALESCE(NEW.created_by, auth.uid());
  IF EXISTS (
    SELECT 1 FROM bonuses_deductions b
    WHERE b.employee_id = NEW.employee_id AND b.issue_date = NEW.issue_date AND b.type = NEW.type
      AND b.amount = NEW.amount AND b.reason IS NOT DISTINCT FROM NEW.reason
      AND b.created_at > now() - interval '10 minutes'
  ) THEN
    RAISE EXCEPTION '% بنفس المبلغ والسبب انسجل لهذا الموظف قبل دقائق، فما انضاف مرة ثانية.',
      CASE WHEN NEW.type = 'bonus' THEN 'مكافأة' ELSE 'خصم' END USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: guard_loan_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_loan_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  -- حذف الموظف نهائياً يمسح سلفه بالتسلسل: وقتها سطر الموظف ما موجود بعد
  IF OLD.status <> 'approved' OR NOT EXISTS (SELECT 1 FROM employees e WHERE e.id = OLD.employee_id) THEN
    RETURN OLD;
  END IF;
  IF COALESCE(OLD.remaining_amount, 0) > 0
     OR EXISTS (SELECT 1 FROM loan_installments li WHERE li.loan_id = OLD.id AND NOT li.is_paid) THEN
    RAISE EXCEPTION 'السلفة بعدها عليها باقي (% د.ع). ما تنحذف إلا بعد تسديدها بالكامل.', to_char(COALESCE(OLD.remaining_amount, 0), 'FM999,999,999')
      USING ERRCODE = '42501';
  END IF;
  IF COALESCE(current_setting('loans.archiving', true), '') <> 'on' THEN
    RAISE EXCEPTION 'السلفة المسددة ما تنحذف مباشرة: استعمل «أرشفة السلفة» حتى ينحفظ سجلها المالي.' USING ERRCODE = '42501';
  END IF;
  RETURN OLD;
END;
$$;


--
-- Name: guard_loan_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_loan_status() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF OLD.status = 'approved' AND NEW.status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'السلفة معتمدة: ما ترجع طلب ولا تنرفض ولا تنلغي. إذا بيها غلط عدّلها، وإذا انسددت تتأرشف.'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: guard_paid_installment_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_paid_installment_delete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF OLD.is_paid AND EXISTS (SELECT 1 FROM loans WHERE id = OLD.loan_id) THEN
    RAISE EXCEPTION 'القسط المسدد ما ينحذف: حذفه يرجّع مبلغه ديناً على الموظف. إذا انسجل بالغلط استعمل «التراجع عن السداد».'
      USING ERRCODE = '55000';
  END IF;
  RETURN OLD;
END;
$$;


--
-- Name: guard_slip_paid_installment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_slip_paid_installment() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF OLD.paid_by_slip_id IS NOT NULL AND NEW.paid_by_slip_id IS NOT DISTINCT FROM OLD.paid_by_slip_id
     AND (NOT NEW.is_paid OR NEW.amount IS DISTINCT FROM OLD.amount) THEN
    RAISE EXCEPTION 'هذا القسط انخصم من راتب معتمد. حتى يرجع، ألغِ اعتماد ذاك الراتب من صفحة الرواتب.'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: guard_slip_with_archived_loan(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_slip_with_archived_loan() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_no bigint;
BEGIN
  SELECT s.loan_no INTO v_no
  FROM settled_loans s, jsonb_array_elements(s.installments) i
  WHERE i ->> 'slip_id' = OLD.id::text
  LIMIT 1;
  IF v_no IS NOT NULL AND EXISTS (SELECT 1 FROM employees e WHERE e.id = OLD.employee_id) THEN
    RAISE EXCEPTION 'هذا الكشف بيه قسط من سلفة تأرشفت (L-%). ما ينلغي اعتماده، لأن القسط ما يرجع ينخصم.', lpad(v_no::text, 4, '0')
      USING ERRCODE = '42501';
  END IF;
  RETURN OLD;
END;
$$;


--
-- Name: hard_delete_employee(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.hard_delete_employee(p_employee_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.safe_delete_employee(p_employee_id);
END;
$$;


--
-- Name: FUNCTION hard_delete_employee(p_employee_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.hard_delete_employee(p_employee_id uuid) IS 'غلاف متوافق مع الإصدارات القديمة يستدعي safe_delete_employee بنفس الصلاحيات.';


--
-- Name: invoke_push_notification(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.invoke_push_notification() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM net.http_post(
    url := 'https://jgjlmddphhncatrhqrej.supabase.co/functions/v1/push-notification',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := json_build_object('record', row_to_json(NEW))::jsonb
  );
  RETURN NEW;
END;
$$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM employees 
    WHERE id = auth.uid() AND role = 'admin' AND is_active = true
  );
END;
$$;


--
-- Name: FUNCTION is_admin(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.is_admin() IS 'يعيد TRUE إذا كان المستخدم الحالي (auth.uid) أدمن فعّال. يُستخدم في RLS policies.';


--
-- Name: is_manager(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_manager() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM employees 
    WHERE id = auth.uid() AND role = 'manager' AND is_active = true
  );
END;
$$;


--
-- Name: FUNCTION is_manager(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.is_manager() IS 'يعيد TRUE إذا كان المستخدم الحالي manager فعّال (لا يشمل admin). يستخدم في RLS policies.';


--
-- Name: issue_cleanup_token(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.issue_cleanup_token() RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_token uuid;
BEGIN
  DELETE FROM cleanup_run_tokens WHERE created_at < now() - interval '1 day';
  INSERT INTO cleanup_run_tokens DEFAULT VALUES RETURNING token INTO v_token;
  RETURN v_token;
END;
$$;


--
-- Name: keep_loan_no(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.keep_loan_no() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  NEW.loan_no := OLD.loan_no;
  RETURN NEW;
END;
$$;


--
-- Name: keep_payroll_policy_keys(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.keep_payroll_policy_keys() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_cutoff int;
BEGIN
  IF NEW.key <> 'payroll_policy' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' THEN
    NEW.value := COALESCE(OLD.value, '{}'::jsonb) || COALESCE(NEW.value, '{}'::jsonb);
  END IF;
  v_cutoff := COALESCE((NEW.value ->> 'cutoff_day')::int, 26);
  NEW.value := NEW.value || jsonb_build_object('cycle_start_day', v_cutoff + 1, 'cycle_end_day', v_cutoff);
  RETURN NEW;
END;
$$;


--
-- Name: keep_status_on_early_checkout(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.keep_status_on_early_checkout() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.status = 'half_day' AND OLD.status IN ('present', 'late')
     AND OLD.check_out_time IS NULL AND NEW.check_out_time IS NOT NULL THEN
    NEW.status := OLD.status;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: leave_policy(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.leave_policy() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE((SELECT value FROM system_settings WHERE key = 'leave_policy'), '{}'::jsonb);
$$;


--
-- Name: leave_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_requests (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    start_date timestamp with time zone NOT NULL,
    end_date timestamp with time zone NOT NULL,
    leave_type text NOT NULL,
    is_hourly boolean DEFAULT false NOT NULL,
    start_hour time without time zone,
    end_hour time without time zone,
    is_paid boolean DEFAULT true NOT NULL,
    reason text,
    status text DEFAULT 'pending'::text NOT NULL,
    attachment_url text,
    approved_by uuid,
    approved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    rejection_reason text,
    CONSTRAINT leave_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text])))
);


--
-- Name: TABLE leave_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.leave_requests IS 'طلبات الإجازات اليومية والساعية مع المرفقات وحالة الاعتماد';


--
-- Name: leave_request_days(public.leave_requests); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.leave_request_days(lr public.leave_requests) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: leave_request_hours(public.leave_requests); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.leave_request_hours(lr public.leave_requests) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  SELECT CASE WHEN lr.is_hourly
    THEN round(GREATEST(EXTRACT(EPOCH FROM COALESCE(lr.end_hour - lr.start_hour, lr.end_date - lr.start_date)) / 3600, 0)::numeric, 2)
    ELSE 0::numeric END;
$$;


--
-- Name: loan_archive_blocker(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.loan_archive_blocker(p_loan_id uuid) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  l loans%ROWTYPE;
  v_open text;
BEGIN
  SELECT * INTO l FROM loans WHERE id = p_loan_id;
  IF NOT FOUND THEN RETURN 'السلفة غير موجودة.'; END IF;
  IF l.status <> 'approved' THEN RETURN 'السلفة مو معتمدة (طلب).'; END IF;
  IF COALESCE(l.remaining_amount, 0) > 0 OR EXISTS (SELECT 1 FROM loan_installments WHERE loan_id = l.id AND NOT is_paid) THEN
    RETURN format('عليها باقي %s د.ع.', to_char(COALESCE(l.remaining_amount, 0), 'FM999,999,999'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM loan_installments WHERE loan_id = l.id) THEN
    RETURN 'ما إلها أقساط مسجّلة.';
  END IF;
  -- كشف خصم منها ومسيره بعده مفتوح: ممكن ينلغي اعتماده، ووقتها القسط لازم يرجع غير مسدد
  SELECT min(s.work_month) INTO v_open
  FROM loan_installments li
  JOIN salary_slips s ON s.id = li.paid_by_slip_id
  JOIN payroll_periods pp ON pp.period_month = s.work_month
  WHERE li.loan_id = l.id AND pp.status <> 'closed';
  IF v_open IS NOT NULL THEN
    RETURN format('قسط منها مخصوم براتب مسير %s وهو بعده مفتوح. أغلق المسير أولاً.', v_open);
  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: loans_cleanup_preview(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.loans_cleanup_preview() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin();
  RETURN (
    WITH approved AS (
      SELECT l.id, l.loan_no, e.full_name, l.amount, l.remaining_amount, l.pledge_url, public.loan_archive_blocker(l.id) AS why,
             (SELECT max(paid_at) FROM loan_installments WHERE loan_id = l.id) AS settled_at,
             pg_column_size(l.*) + COALESCE((SELECT sum(pg_column_size(i.*)) FROM loan_installments i WHERE i.loan_id = l.id), 0) AS row_bytes
      FROM loans l JOIN employees e ON e.id = l.employee_id
      WHERE l.status = 'approved'
    ), requests AS (
      SELECT l.id, l.loan_no, e.full_name, l.amount, l.status, l.created_at, l.pledge_url,
             (l.created_at < now() - interval '30 days') AS old_enough, pg_column_size(l.*) AS row_bytes
      FROM loans l JOIN employees e ON e.id = l.employee_id
      WHERE l.status IN ('rejected', 'cancelled')
    )
    SELECT jsonb_build_object(
      'settled', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'loan_no', loan_no, 'employee', full_name, 'amount', amount,
                                     'settled_at', settled_at) ORDER BY loan_no) FROM approved WHERE why IS NULL), '[]'::jsonb),
      'excluded', COALESCE((SELECT jsonb_agg(jsonb_build_object('loan_no', loan_no, 'employee', full_name, 'amount', amount,
                                      'remaining', remaining_amount, 'reason', why) ORDER BY loan_no) FROM approved WHERE why IS NOT NULL), '[]'::jsonb),
      'requests', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'loan_no', loan_no, 'employee', full_name, 'amount', amount,
                                      'status', status, 'created_at', created_at) ORDER BY loan_no) FROM requests WHERE old_enough), '[]'::jsonb),
      'requests_recent', (SELECT count(*) FROM requests WHERE NOT old_enough),
      'bytes', jsonb_build_object(
        'settled_rows', COALESCE((SELECT sum(row_bytes) FROM approved WHERE why IS NULL), 0),
        'settled_files', COALESCE((SELECT sum(public._pledge_bytes(pledge_url)) FROM approved WHERE why IS NULL), 0),
        'requests_rows', COALESCE((SELECT sum(row_bytes) FROM requests WHERE old_enough), 0),
        'requests_files', COALESCE((SELECT sum(public._pledge_bytes(pledge_url)) FROM requests WHERE old_enough), 0)),
      'archived_total', (SELECT count(*) FROM settled_loans))
  );
END;
$$;


--
-- Name: loans_cleanup_run(boolean, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.loans_cleanup_run(p_settled boolean DEFAULT false, p_requests boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  r record;
  v_archived int;
  v_deleted int;
  v_urls text[] := '{}';
BEGIN
  PERFORM public.require_admin();
  IF NOT (COALESCE(p_settled, false) OR COALESCE(p_requests, false)) THEN
    RAISE EXCEPTION 'اختار شنو يتنظف: السلف المسددة أو الطلبات المرفوضة.' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('loans_cleanup'));

  IF p_settled THEN
    v_archived := 0;
    FOR r IN SELECT id, pledge_url FROM loans WHERE status = 'approved' AND public.loan_archive_blocker(id) IS NULL ORDER BY loan_no LOOP
      PERFORM public.archive_settled_loan(r.id);
      v_archived := v_archived + 1;
      IF COALESCE(r.pledge_url, '') <> '' THEN v_urls := v_urls || r.pledge_url; END IF;
    END LOOP;
  END IF;

  IF p_requests THEN
    v_deleted := 0;
    FOR r IN SELECT id, pledge_url FROM loans WHERE status IN ('rejected', 'cancelled') AND created_at < now() - interval '30 days' LOOP
      DELETE FROM loans WHERE id = r.id;
      v_deleted := v_deleted + 1;
      IF COALESCE(r.pledge_url, '') <> '' THEN v_urls := v_urls || r.pledge_url; END IF;
    END LOOP;
  END IF;

  INSERT INTO payroll_cleanups (period_month, start_date, end_date, loans_archived, loan_requests_deleted, performed_by)
  VALUES (NULL, NULL, NULL, v_archived, v_deleted, auth.uid());

  RETURN jsonb_build_object('success', true, 'loans_archived', v_archived, 'loan_requests_deleted', v_deleted, 'pledge_urls', to_jsonb(v_urls));
END;
$$;


--
-- Name: managed_employee_ids(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.managed_employee_ids() RETURNS uuid[]
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(array_agg(t.id), '{}'::uuid[])
  FROM employees me
  JOIN employees t ON t.branch_id = me.branch_id
  WHERE me.id = auth.uid() AND me.role = 'manager' AND me.is_active AND me.branch_id IS NOT NULL;
$$;


--
-- Name: manual_purge_month_data(integer, integer, boolean, boolean, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manual_purge_month_data(p_year integer, p_month integer, p_notifications boolean DEFAULT false, p_tracking boolean DEFAULT false, p_absences boolean DEFAULT false) RETURNS TABLE(notifications_deleted integer, tracking_deleted integer, stops_deleted integer, violations_deleted integer, absences_deleted integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: FUNCTION manual_purge_month_data(p_year integer, p_month integer, p_notifications boolean, p_tracking boolean, p_absences boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.manual_purge_month_data(p_year integer, p_month integer, p_notifications boolean, p_tracking boolean, p_absences boolean) IS 'حذف يدوي لبيانات شهر معيّن حسب الخيارات: الإشعارات، التتبع (نقاط، وقفات، مخالفات)، سجلات الحضور.
مقفل على الأدمن. البارامترات: السنة، الشهر، ثلاث قيم منطقية.';


--
-- Name: mark_offline_punch_reviewed(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_offline_punch_reviewed(p_attendance_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  a attendance%ROWTYPE;
BEGIN
  PERFORM public.require_admin_or_manager();
  SELECT * INTO a FROM attendance WHERE id = p_attendance_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'سجل الحضور غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF NOT public.is_admin() AND (a.employee_id = auth.uid() OR NOT (a.employee_id = ANY (public.managed_employee_ids()))) THEN
    RAISE EXCEPTION 'غير مصرح: الموظف من فرع آخر أو هذي بصمتك.' USING ERRCODE = '42501';
  END IF;
  IF a.check_in_time_source IS DISTINCT FROM 'offline_review' AND a.check_out_time_source IS DISTINCT FROM 'offline_review' THEN
    RETURN;
  END IF;
  UPDATE attendance
  SET check_in_time_source = CASE WHEN check_in_time_source = 'offline_review' THEN 'offline_reviewed' ELSE check_in_time_source END,
      check_out_time_source = CASE WHEN check_out_time_source = 'offline_review' THEN 'offline_reviewed' ELSE check_out_time_source END
  WHERE id = p_attendance_id;
  INSERT INTO audit_log (table_name, action, actor_id, row_id, old_data, new_data)
  VALUES ('attendance', 'UPDATE', auth.uid(), p_attendance_id,
          jsonb_build_object('check_in_time_source', a.check_in_time_source, 'check_out_time_source', a.check_out_time_source),
          jsonb_build_object('offline_punch_reviewed', true));
END;
$$;


--
-- Name: mark_payroll_delivered(text, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_payroll_delivered(p_month text, p_delivered boolean DEFAULT true) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_p payroll_periods%ROWTYPE;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'هذا الشهر ما إله مسير رواتب.' USING ERRCODE = 'P0002';
  END IF;
  IF COALESCE(p_delivered, true) AND v_p.status <> 'closed' THEN
    RAISE EXCEPTION 'أغلق المسير أولاً، وبعدها أكد التسليم.' USING ERRCODE = '42501';
  END IF;
  UPDATE payroll_periods
  SET delivered_at = CASE WHEN COALESCE(p_delivered, true) THEN COALESCE(delivered_at, now()) END,
      delivered_by = CASE WHEN COALESCE(p_delivered, true) THEN COALESCE(delivered_by, auth.uid()) END
  WHERE period_month = p_month
  RETURNING * INTO v_p;
  RETURN jsonb_build_object('success', true, 'month', p_month, 'delivered_at', v_p.delivered_at);
END;
$$;


--
-- Name: next_employee_code(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.next_employee_code() RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_code text;
BEGIN
  LOOP
    v_code := 'EMP-' || lpad(nextval('public.employee_code_seq')::text, 3, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM employees WHERE employee_code = v_code);
  END LOOP;
  RETURN v_code;
END;
$$;


--
-- Name: notify_admins_of_new_leave_request(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_admins_of_new_leave_request() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_employee_name  TEXT;
    v_leave_type_ar  TEXT;
    v_days_count     INTEGER;
BEGIN
    -- Only for newly-created PENDING requests
    IF NEW.status != 'pending' THEN
        RETURN NEW;
    END IF;

    -- Employee name for the notification body
    SELECT full_name INTO v_employee_name
    FROM employees
    WHERE id = NEW.employee_id;

    -- Arabic label for leave type
    v_leave_type_ar := CASE NEW.leave_type
        WHEN 'annual'    THEN 'سنوية'
        WHEN 'sick'      THEN 'مرضية'
        WHEN 'emergency' THEN 'طارئة'
        WHEN 'maternity' THEN 'أمومة'
        ELSE                  'أخرى'
    END;

    -- Number of days requested (rounded)
    v_days_count := GREATEST(1, (NEW.end_date::DATE - NEW.start_date::DATE) + 1);

    -- Insert one notification per admin/manager
    INSERT INTO notifications (employee_id, title, body, type)
    SELECT
        e.id,
        '📋 طلب إجازة جديد بانتظار الموافقة',
        format(
            'قدّم %s طلب إجازة %s لمدة %s يوم — يرجى المراجعة والاعتماد.',
            COALESCE(v_employee_name, 'موظف'),
            v_leave_type_ar,
            v_days_count
        ),
        'leave'
    FROM employees e
    WHERE e.role IN ('admin', 'manager')
      AND e.is_active = true
      AND e.id != NEW.employee_id;

    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION notify_admins_of_new_leave_request(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.notify_admins_of_new_leave_request() IS 'ينشئ إشعارات للمدراء والأدمنز فور إدراج طلب إجازة جديد. مربوط بـ trigger AFTER INSERT.';


--
-- Name: notify_admins_of_new_loan_request(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_admins_of_new_loan_request() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_employee_name  TEXT;
    v_amount_str     TEXT;
BEGIN
    IF NEW.status != 'pending' THEN
        RETURN NEW;
    END IF;

    SELECT full_name INTO v_employee_name
    FROM employees
    WHERE id = NEW.employee_id;

    v_amount_str := to_char(NEW.amount, 'FM999G999G999') || ' د.ع';

    INSERT INTO notifications (employee_id, title, body, type)
    SELECT
        e.id,
        '💰 طلب سلفة جديد بانتظار الموافقة',
        format(
            'قدّم %s طلب سلفة بمبلغ %s على %s قسط — يرجى المراجعة.',
            COALESCE(v_employee_name, 'موظف'),
            v_amount_str,
            COALESCE(NEW.installment_count::TEXT, '—')
        ),
        'loan'
    FROM employees e
    -- مدير الفرع ما يعتمد سلف (للأدمن فقط)، فما يستلم إشعار طلبات السلف
    WHERE e.role = 'admin'
      AND e.is_active = true
      AND e.id != NEW.employee_id;

    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION notify_admins_of_new_loan_request(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.notify_admins_of_new_loan_request() IS 'ينشئ إشعارات للمدراء والأدمنز فور إدراج طلب سلفة جديد. مربوط بـ trigger AFTER INSERT.';


--
-- Name: notify_employee_on_leave_decision(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_employee_on_leave_decision() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    IF OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected') THEN
        INSERT INTO notifications (employee_id, title, body, type)
        VALUES (
            NEW.employee_id,
            CASE NEW.status
                WHEN 'approved' THEN '✅ تمت الموافقة على طلب الإجازة'
                ELSE '❌ تم رفض طلب الإجازة'
            END,
            CASE NEW.status
                WHEN 'approved' THEN 'طلب الإجازة الذي قدّمته حصل على الموافقة الرسمية. رحلة سعيدة!'
                ELSE COALESCE(
                    'طلب الإجازة الذي قدّمته لم يتم اعتماده. السبب: ' || NULLIF(btrim(NEW.rejection_reason), ''),
                    'طلب الإجازة الذي قدّمته لم يتم اعتماده. راجع إدارة الموارد البشرية للتفاصيل.'
                )
            END,
            'leave'
        );
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: notify_employee_on_loan_decision(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_employee_on_loan_decision() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    IF OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected') THEN
        INSERT INTO notifications (employee_id, title, body, type)
        VALUES (
            NEW.employee_id,
            CASE NEW.status
                WHEN 'approved' THEN '✅ تمت الموافقة على طلب السلفة'
                ELSE '❌ تم رفض طلب السلفة'
            END,
            CASE NEW.status
                WHEN 'approved' THEN format(
                    'تم اعتماد سلفتك بقيمة %s د.ع على %s قسط شهري (القسط %s د.ع).',
                    to_char(NEW.amount, 'FM999,999,999,990'),
                    NEW.installment_count,
                    to_char(NEW.installment_amount, 'FM999,999,999,990'))
                ELSE COALESCE(
                    'طلب السلفة لم يتم اعتماده. السبب: ' || NULLIF(btrim(NEW.rejection_reason), ''),
                    'طلب السلفة الذي قدّمته لم يتم اعتماده. راجع إدارة الموارد البشرية.'
                )
            END,
            'loan'
        );
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: one_pending_loan_request(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.one_pending_loan_request() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.status = 'pending' AND EXISTS (
    SELECT 1 FROM loans WHERE employee_id = NEW.employee_id AND status = 'pending' AND id <> NEW.id
  ) THEN
    RAISE EXCEPTION 'لديك طلب سلفة قيد المراجعة. انتظر قرار الإدارة قبل تقديم طلب جديد.' USING ERRCODE = '23505';
  END IF;

  -- طلبات المستخدمين عبر التطبيق/الموقع فقط (العمليات الداخلية والإعداد تمر)
  IF NEW.status = 'pending' AND current_user IN ('authenticated', 'anon') THEN
    IF EXISTS (SELECT 1 FROM loans WHERE employee_id = NEW.employee_id AND status = 'approved' AND remaining_amount > 0) THEN
      RAISE EXCEPTION 'لديك سلفة جارية لم تُسدَّد بعد. تقدر تطلب سلفة جديدة بعد إكمال سدادها.' USING ERRCODE = '55000';
    END IF;
    IF NEW.amount > 100000000 THEN
      RAISE EXCEPTION 'المبلغ كبير جداً (أكثر من 100,000,000 د.ع). تأكد من المبلغ.' USING ERRCODE = '22023';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: pay_loan_installment(uuid, numeric, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pay_loan_installment(p_installment_id uuid, p_amount numeric, p_method text DEFAULT 'cash'::text, p_note text DEFAULT NULL::text) RETURNS numeric
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_inst loan_installments%ROWTYPE;
  v_loan loans%ROWTYPE;
  v_remaining numeric;
BEGIN
  PERFORM public.require_admin();

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'يرجى إدخال مبلغ سداد أكبر من الصفر.' USING ERRCODE = '22023';
  END IF;
  IF p_method NOT IN ('cash', 'salary_deduction') THEN
    RAISE EXCEPTION 'طريقة السداد غير صحيحة.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_inst FROM loan_installments WHERE id = p_installment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'القسط غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF v_inst.is_paid THEN
    RAISE EXCEPTION 'هذا القسط مسدد مسبقاً.' USING ERRCODE = '55000';
  END IF;

  SELECT * INTO v_loan FROM loans WHERE id = v_inst.loan_id FOR UPDATE;
  IF v_loan.status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'السلفة غير معتمدة.' USING ERRCODE = '55000';
  END IF;

  -- «استقطاع راتب» يدوي قبل ما يصدر كشف ذاك الشهر: الكشف نفسه راح يخصم القسط، فالتسجيل اليدوي يخليه ما ينخصم أبداً
  IF p_method = 'salary_deduction' AND COALESCE(v_loan.payment_method, '') <> 'cash'
     AND NOT public._loan_month_settled(v_loan.employee_id, v_inst.due_date) THEN
    RAISE EXCEPTION 'راتب شهر % بعده ما صادر: الرواتب راح تخصم هذا القسط وحدها. إذا الموظف هالشهر يكدر يدفع أقل، استعمل «هالشهر أقل».',
      public.payroll_month_of(v_inst.due_date) USING ERRCODE = '22023';
  END IF;

  v_remaining := v_loan.amount - COALESCE((
    SELECT SUM(amount) FROM loan_installments WHERE loan_id = v_loan.id AND is_paid
  ), 0);
  IF p_amount > v_remaining THEN
    RAISE EXCEPTION 'المبلغ أكبر من المتبقي على السلفة (%).', to_char(v_remaining, 'FM999,999,999')
      USING ERRCODE = '22023';
  END IF;

  UPDATE loan_installments
  SET amount = round(p_amount),
      is_paid = true,
      paid_at = now(),
      payment_type = p_method,
      payment_note = NULLIF(btrim(COALESCE(p_note, '')), '')
  WHERE id = p_installment_id;

  SELECT remaining_amount INTO v_remaining FROM loans WHERE id = v_loan.id;

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (
    v_loan.employee_id,
    'تسجيل دفعة سلفة 💸',
    format('تم تسجيل دفعة بمبلغ %s د.ع من سلفتك. المتبقي: %s د.ع.',
           to_char(round(p_amount), 'FM999,999,999'), to_char(v_remaining, 'FM999,999,999')),
    'loan'
  );

  RETURN v_remaining;
END;
$$;


--
-- Name: FUNCTION pay_loan_installment(p_installment_id uuid, p_amount numeric, p_method text, p_note text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.pay_loan_installment(p_installment_id uuid, p_amount numeric, p_method text, p_note text) IS 'يسجل سداد قسط بأي مبلغ (نقداً أو استقطاع راتب) ويعيد توزيع المتبقي على الأقساط القادمة. مقفل على الأدمن.';


--
-- Name: payroll_basic_salary(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_basic_salary(p_employee_id uuid, p_month text) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(
    (SELECT h.monthly_salary FROM salary_history h
     WHERE h.employee_id = p_employee_id AND h.effective_month <= p_month
     ORDER BY h.effective_month DESC, h.created_at DESC LIMIT 1),
    (SELECT COALESCE(e.monthly_salary_iqd, 0) FROM employees e WHERE e.id = p_employee_id),
    0);
$$;


--
-- Name: payroll_cleanup_preview(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_cleanup_preview(p_month text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
  v_next_delivered boolean;
  v_labels jsonb := '{"absence":"غياب","late":"تأخير","early_leave":"خروج مبكر","missing_punch":"بصمة ناقصة","overtime":"ساعات إضافية"}';
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'هذا الشهر ما إله مسير رواتب.' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_next FROM payroll_periods WHERE start_date > v_p.cutoff_date ORDER BY start_date LIMIT 1;

  v_closed := v_p.status = 'closed';
  v_next_closed := COALESCE(v_next.status = 'closed', false);
  v_next_delivered := v_next_closed AND v_next.delivered_at IS NOT NULL;
  SELECT count(*) INTO v_pending FROM payroll_events
  WHERE status = 'pending' AND event_date BETWEEN v_p.start_date AND v_p.cutoff_date;
  v_att_done := public.payroll_day_frozen(v_p.start_date) AND public.payroll_day_frozen(v_p.cutoff_date);
  v_trk_done := EXISTS (SELECT 1 FROM payroll_cleanups WHERE period_month = p_month AND tracking_deleted IS NOT NULL);
  v_ntf_done := EXISTS (SELECT 1 FROM payroll_cleanups WHERE period_month = p_month AND notifications_deleted IS NOT NULL);

  RETURN jsonb_build_object(
    'month', p_month, 'start_date', v_p.start_date, 'end_date', v_p.cutoff_date, 'status', v_p.status,
    'delivered_at', v_p.delivered_at,
    'next_month', v_next.period_month, 'next_status', v_next.status, 'next_delivered_at', v_next.delivered_at,
    'checks', jsonb_build_object('closed', v_closed, 'next_closed', v_next_closed, 'next_delivered', v_next_delivered,
                                 'pending_decisions', v_pending),
    -- المستثنى وسببه: الحركات اللي بعدها تنتظر قرار (تمنع حذف الحضور)
    'pending_list', COALESCE((
      SELECT jsonb_agg(x ORDER BY x ->> 'date', x ->> 'employee') FROM (
        SELECT jsonb_build_object('employee', e.full_name, 'date', pe.event_date,
                                  'type', COALESCE(v_labels ->> pe.event_type, pe.event_type), 'amount', pe.amount) AS x
        FROM payroll_events pe JOIN employees e ON e.id = pe.employee_id
        WHERE pe.status = 'pending' AND pe.event_date BETWEEN v_p.start_date AND v_p.cutoff_date
        ORDER BY pe.event_date LIMIT 100) q), '[]'::jsonb),
    'counts', jsonb_build_object(
      'attendance', (SELECT count(*) FROM attendance WHERE work_date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'tracking', (SELECT count(*) FROM location_tracking WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'stops', (SELECT count(*) FROM tracked_stops WHERE (start_time AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'violations', (SELECT count(*) FROM geofence_violations WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'notifications', (SELECT count(*) FROM notifications WHERE (created_at AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date)),
    -- تقدير المساحة (حجم السطور نفسها بدون الفهارس؛ تقريبي)
    'bytes', jsonb_build_object(
      'attendance', (SELECT COALESCE(sum(pg_column_size(a.*)), 0) FROM attendance a WHERE work_date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'tracking', (SELECT COALESCE(sum(pg_column_size(t.*)), 0) FROM location_tracking t WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date)
                + (SELECT COALESCE(sum(pg_column_size(s.*)), 0) FROM tracked_stops s WHERE (start_time AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date)
                + (SELECT COALESCE(sum(pg_column_size(g.*)), 0) FROM geofence_violations g WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'notifications', (SELECT COALESCE(sum(pg_column_size(n.*)), 0) FROM notifications n WHERE (created_at AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date)),
    'done', jsonb_build_object('attendance', v_att_done, 'tracking', v_trk_done, 'notifications', v_ntf_done),
    'can', jsonb_build_object(
      'attendance', v_closed AND v_next_delivered AND v_pending = 0 AND NOT v_att_done,
      'tracking', v_closed,
      'notifications', v_closed),
    'history', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'at', c.performed_at, 'by', (SELECT full_name FROM employees WHERE id = c.performed_by),
               'attendance', c.attendance_deleted, 'tracking', c.tracking_deleted, 'stops', c.stops_deleted,
               'violations', c.violations_deleted, 'notifications', c.notifications_deleted) ORDER BY c.performed_at DESC)
      FROM payroll_cleanups c WHERE c.period_month = p_month), '[]'::jsonb));
END;
$$;


--
-- Name: payroll_cleanup_run(text, boolean, boolean, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_cleanup_run(p_month text, p_attendance boolean DEFAULT false, p_tracking boolean DEFAULT false, p_notifications boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
    IF NOT (v -> 'checks' ->> 'next_delivered')::boolean THEN
      RAISE EXCEPTION 'أكد «تم تسليم الرواتب» للمسير اللي بعده (%) من صفحة الرواتب أولاً.', COALESCE(v ->> 'next_month', 'الجاي')
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
$$;


--
-- Name: payroll_daily_rate(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_daily_rate(p_employee_id uuid, p_month text) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(public.payroll_basic_salary(p_employee_id, p_month), 0) / 30;
$$;


--
-- Name: payroll_day_frozen(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_day_frozen(p_date date) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (SELECT 1 FROM payroll_cleanups c
                 WHERE c.attendance_deleted IS NOT NULL AND p_date BETWEEN c.start_date AND c.end_date)
      OR EXISTS (SELECT 1 FROM archived_months am JOIN payroll_periods pp ON pp.period_month = am.work_month
                 WHERE p_date BETWEEN pp.start_date AND pp.cutoff_date);
$$;


--
-- Name: payroll_day_rates(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_day_rates(p_date date DEFAULT NULL::date) RETURNS TABLE(employee_id uuid, daily_rate numeric)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_date date := COALESCE(p_date, (now() AT TIME ZONE public.company_timezone())::date);
  v_month text := COALESCE(public.payroll_natural_month(v_date), public.payroll_month_of(v_date));
BEGIN
  PERFORM public.require_admin_or_manager();
  IF NOT public.is_admin() THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT e.id, round(public.payroll_daily_rate(e.id, v_month), 2)
  FROM employees e
  WHERE e.is_active;
END;
$$;


--
-- Name: payroll_employee_summary(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_employee_summary(p_employee_id uuid, p_month text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
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
  v_basis text;
  v_note text;
  v_missing int;
  v_ev record;
  v_loans numeric;
  v_slip salary_slips%ROWTYPE;
  v_exit_balance numeric := 0;
  v_loan_items jsonb;
  v_attended int;
  v_scheduled int;
  v_gap int;
  v_gap_note text;
BEGIN
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  v_month_basic := public.payroll_basic_salary(p_employee_id, p_month);
  v_daily := v_month_basic / 30;

  v_from := GREATEST(v_p.start_date, COALESCE(v_emp.join_date, v_p.start_date));
  v_to := LEAST(v_p.cutoff_date, COALESCE(v_emp.termination_date, v_p.cutoff_date));
  v_period_days := v_p.cutoff_date - v_p.start_date + 1;
  -- أيام الانقطاع (ترك ورجع) داخل المسير ما تنحسب خدمة (تدقيق 14/10 PAY-009)
  SELECT string_agg(format('ترك بعد %s ورجع %s', to_char(b.last_day, 'DD/MM'), to_char(b.return_date, 'DD/MM')), '، ' ORDER BY b.last_day)
  INTO v_gap_note
  FROM (SELECT DISTINCT b.id, b.last_day, b.return_date
        FROM employee_service_breaks b
        WHERE b.employee_id = p_employee_id AND b.last_day < v_to AND b.return_date > v_from) b;
  SELECT count(*) INTO v_gap
  FROM generate_series(v_from, v_to, interval '1 day') g(d)
  WHERE EXISTS (SELECT 1 FROM employee_service_breaks b WHERE b.employee_id = p_employee_id AND g.d::date > b.last_day AND g.d::date < b.return_date);
  v_employed_days := GREATEST(v_to - v_from + 1 - v_gap, 0);

  -- أيام الدوام ضمن الخدمة (حسب جدول الموظف بكل يوم، بدون الجمع/العطل الأسبوعية والرسمية)
  SELECT count(*) INTO v_scheduled
  FROM generate_series(v_from, v_to, interval '1 day') g(d)
  WHERE EXTRACT(DOW FROM g.d)::int = ANY (COALESCE((public.payroll_schedule_at(p_employee_id, g.d::date)).work_days, ARRAY[0, 1, 2, 3, 4, 6]))
    AND NOT EXISTS (SELECT 1 FROM official_holidays h WHERE h.holiday_date = g.d::date)
    AND NOT EXISTS (SELECT 1 FROM employee_service_breaks b WHERE b.employee_id = p_employee_id AND g.d::date > b.last_day AND g.d::date < b.return_date);

  IF v_employed_days <= 0 THEN
    v_basic := 0;
    v_basis := 'none';
    v_note := 'ما اشتغل بهالمسير';
  ELSIF v_emp.termination_date IS NOT NULL AND v_emp.termination_date < v_p.cutoff_date THEN
    -- نهاية خدمة داخل المسير: أيام الدوام اللي خدمها بس (قرار 15/10/2026)
    v_basic := round(v_daily * v_scheduled);
    v_basis := 'end_of_service';
    v_note := format('نهاية خدمة: %s يوم دوام من %s لحد %s (الجمع والعطل الرسمية%s ما تنحسب) × أجر اليوم %s = %s د.ع',
                     v_scheduled, to_char(v_from, 'DD/MM'), to_char(v_to, 'DD/MM'),
                     CASE WHEN v_gap > 0 THEN ' وأيام الانقطاع' ELSE '' END,
                     to_char(round(v_daily), 'FM999,999,999'), to_char(v_basic, 'FM999,999,999'));
  ELSIF v_employed_days < v_period_days AND v_gap > 0 THEN
    -- رجع للعمل بعد انقطاع (قرار 15/10/2026: مثل المباشر): الراتب ناقص أجر أيام الانقطاع (وأيام قبل المباشرة إن وجدت)
    v_missing := v_period_days - v_employed_days;
    v_basic := GREATEST(v_month_basic - round(v_daily * v_missing), 0);
    v_basis := 'returned';
    v_note := format('%s: الراتب %s ناقص %s × أجر اليوم %s = %s د.ع',
                     v_gap_note, to_char(v_month_basic, 'FM999,999,999'),
                     CASE WHEN v_missing > v_gap THEN format('%s يوم (%s انقطاع + %s قبل المباشرة)', v_missing, v_gap, v_missing - v_gap)
                          ELSE format('%s يوم انقطاع', v_gap) END,
                     to_char(round(v_daily), 'FM999,999,999'), to_char(v_basic, 'FM999,999,999'));
  ELSIF v_employed_days < v_period_days THEN
    -- مباشرة بنص المسير: الراتب ناقص أجر الأيام قبل المباشرة (مثل خصم الغياب، مهما كان طول المسير)
    v_missing := v_period_days - v_employed_days;
    v_basic := GREATEST(v_month_basic - round(v_daily * v_missing), 0);
    v_basis := 'joined';
    v_note := format('باشر %s: الراتب %s ناقص %s يوم قبل المباشرة × أجر اليوم %s = %s د.ع',
                     to_char(v_from, 'DD/MM/YYYY'), to_char(v_month_basic, 'FM999,999,999'), v_missing,
                     to_char(round(v_daily), 'FM999,999,999'), to_char(v_basic, 'FM999,999,999'));
  ELSE
    v_basic := v_month_basic;
    v_basis := 'full';
    v_note := format('راتب المسير كامل: %s د.ع', to_char(v_month_basic, 'FM999,999,999'));
  END IF;

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

  SELECT * INTO v_slip FROM salary_slips WHERE employee_id = p_employee_id AND work_month = p_month;

  RETURN jsonb_build_object(
    'employee_id', p_employee_id,
    'period_days', v_period_days,
    'employed_days', v_employed_days,
    'gap_days', v_gap,
    'monthly_salary', v_month_basic,
    'daily_rate', round(v_daily, 4),
    'minute_rate', round(v_daily / public.payroll_shift_minutes(p_employee_id), 6),
    'shift_minutes', public.payroll_shift_minutes(p_employee_id),
    'basic', v_basic,
    'basic_basis', v_basis,
    'basic_note', v_note,
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
$$;


--
-- Name: payroll_hourly_leave_overlap(uuid, date, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_hourly_leave_overlap(p_employee_id uuid, p_date date, p_from numeric, p_to numeric) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: payroll_legacy_slip(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_legacy_slip(p_employee_id uuid, p_month text) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT id FROM salary_slips
  WHERE employee_id = p_employee_id AND work_month = p_month AND NOT computed_by_engine;
$$;


--
-- Name: payroll_legacy_slip(uuid, text, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_legacy_slip(p_employee_id uuid, p_month text, p_date date) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT id FROM salary_slips
  WHERE employee_id = p_employee_id AND work_month = p_month AND NOT computed_by_engine
    AND p_date <= (created_at AT TIME ZONE public.company_timezone())::date;
$$;


--
-- Name: payroll_local_minutes(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_local_minutes(p_ts timestamp with time zone) RETURNS numeric
    LANGUAGE sql STABLE
    AS $$
  SELECT EXTRACT(HOUR FROM (p_ts AT TIME ZONE public.company_timezone())) * 60
       + EXTRACT(MINUTE FROM (p_ts AT TIME ZONE public.company_timezone()));
$$;


--
-- Name: payroll_month_add(text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_month_add(p_month text, p_n integer) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT to_char((p_month || '-01')::date + make_interval(months => p_n), 'YYYY-MM');
$$;


--
-- Name: payroll_month_of(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_month_of(p_date date) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(
    (SELECT period_month FROM payroll_periods WHERE p_date BETWEEN start_date AND cutoff_date ORDER BY period_month LIMIT 1),
    to_char(CASE WHEN EXTRACT(DAY FROM p_date) <= COALESCE((SELECT (value ->> 'cutoff_day')::int FROM system_settings WHERE key = 'payroll_policy'), 26)
                 THEN p_date ELSE (p_date + interval '1 month')::date END, 'YYYY-MM'));
$$;


--
-- Name: payroll_natural_month(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_natural_month(p_date date) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: payroll_nightly(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_nightly() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: payroll_policy(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_policy() RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE((SELECT value FROM system_settings WHERE key = 'payroll_policy'), '{}'::jsonb);
$$;


--
-- Name: payroll_same_branch(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_same_branch(p_employee_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM employees me JOIN employees t ON t.id = p_employee_id
    WHERE me.id = auth.uid() AND me.branch_id IS NOT NULL AND t.branch_id = me.branch_id
  );
$$;


--
-- Name: payroll_schedule(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_schedule(p_employee_id uuid) RETURNS public.work_schedules
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: payroll_schedule_at(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_schedule_at(p_employee_id uuid, p_date date) RETURNS public.work_schedules
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  h record;
  r work_schedules%ROWTYPE;
  v_branch uuid;
  v_dept uuid;
BEGIN
  SELECT a.branch_id, a.department_id INTO v_branch, v_dept FROM public.employee_assignment_at(p_employee_id, p_date) a;
  SELECT x.* INTO h
  FROM (
    SELECT DISTINCT ON (wh.schedule_id) wh.*
    FROM work_schedule_history wh
    WHERE wh.effective_from <= p_date
    ORDER BY wh.schedule_id, wh.effective_from DESC, wh.recorded_at DESC
  ) x
  WHERE NOT x.removed
    AND (x.employee_id = p_employee_id
     OR (x.employee_id IS NULL AND x.department_id IS NOT NULL AND x.department_id = v_dept)
     OR (x.employee_id IS NULL AND x.department_id IS NULL AND x.branch_id IS NOT NULL AND x.branch_id = v_branch))
  ORDER BY CASE WHEN x.employee_id IS NOT NULL THEN 0 WHEN x.department_id IS NOT NULL THEN 1 ELSE 2 END,
           x.schedule_created_at DESC
  LIMIT 1;
  IF FOUND THEN
    r.id := h.schedule_id;
    r.employee_id := h.employee_id;
    r.department_id := h.department_id;
    r.branch_id := h.branch_id;
    r.check_in_time := h.check_in_time;
    r.check_out_time := h.check_out_time;
    r.grace_period_minutes := h.grace_period_minutes;
    r.work_days := h.work_days;
    r.created_at := h.schedule_created_at;
  END IF;
  RETURN r;
END;
$$;


--
-- Name: payroll_shift_minutes(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_shift_minutes(p_employee_id uuid) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT COALESCE(NULLIF(public.employee_shift_hours(p_employee_id), 0), 8) * 60;
$$;


--
-- Name: payroll_shift_minutes_at(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_shift_minutes_at(p_employee_id uuid, p_date date) RETURNS numeric
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  s work_schedules%ROWTYPE := public.payroll_schedule_at(p_employee_id, p_date);
  v_hours numeric;
BEGIN
  IF s.check_in_time IS NULL OR s.check_out_time IS NULL THEN
    RETURN 8 * 60;
  END IF;
  v_hours := EXTRACT(EPOCH FROM (CASE WHEN s.check_out_time > s.check_in_time THEN s.check_out_time - s.check_in_time
                                      ELSE s.check_out_time - s.check_in_time + interval '24 hours' END)) / 3600;
  RETURN COALESCE(NULLIF(v_hours, 0), 8) * 60;
END;
$$;


--
-- Name: payroll_target_month(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_target_month(p_employee_id uuid, p_natural text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: payroll_time_minutes(time without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.payroll_time_minutes(p_t time without time zone) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT EXTRACT(HOUR FROM p_t) * 60 + EXTRACT(MINUTE FROM p_t);
$$;


--
-- Name: perform_daily_cleanup(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.perform_daily_cleanup() RETURNS TABLE(expired_file_path text, expired_bucket_id text, file_record_id uuid)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: FUNCTION perform_daily_cleanup(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.perform_daily_cleanup() IS 'التنظيف اليومي المؤتمت: يفرغ سلة المحذوفات بعد 30 يوم ويؤرشف بيانات التتبع القديمة.
يُستدعى من Edge Function daily-cleanup أو من pg_cron. يعيد قائمة الملفات المطلوب حذفها من التخزين.';


--
-- Name: postpone_loan_installment(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.postpone_loan_installment(p_installment_id uuid, p_note text DEFAULT NULL::text) RETURNS date
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_inst loan_installments%ROWTYPE;
  v_loan loans%ROWTYPE;
  v_new date;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_inst FROM loan_installments WHERE id = p_installment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'القسط غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF v_inst.is_paid THEN
    RAISE EXCEPTION 'هذا القسط مسدد مسبقاً.' USING ERRCODE = '55000';
  END IF;
  SELECT * INTO v_loan FROM loans WHERE id = v_inst.loan_id FOR UPDATE;
  IF v_loan.status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'السلفة غير معتمدة.' USING ERRCODE = '55000';
  END IF;
  IF public._loan_month_settled(v_loan.employee_id, v_inst.due_date) THEN
    RAISE EXCEPTION 'راتب هذا الشهر صادر أو الفترة مقفلة؛ ما يتأجل قسطه.' USING ERRCODE = '55000';
  END IF;

  SELECT (max(due_date) + interval '1 month')::date INTO v_new FROM loan_installments WHERE loan_id = v_loan.id;
  -- تغيير التاريخ بس (المبلغ نفسه)، فالتريجر ما يعيد التوزيع
  UPDATE loan_installments
  SET due_date = v_new, origin_kind = 'postponed', origin_month = COALESCE(origin_month, v_inst.due_date),
      amount_locked = false,
      payment_note = COALESCE(NULLIF(btrim(COALESCE(p_note, '')), ''), payment_note)
  WHERE id = p_installment_id;

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (v_loan.employee_id, 'تأجيل قسط السلفة 📅',
          format('تم تأجيل قسط شهر %s (%s د.ع) إلى شهر %s.%s', to_char(v_inst.due_date, 'MM/YYYY'),
                 to_char(v_inst.amount, 'FM999,999,999'), to_char(v_new, 'MM/YYYY'),
                 COALESCE(' ملاحظة: ' || NULLIF(btrim(COALESCE(p_note, '')), ''), '')),
          'loan');
  RETURN v_new;
END;
$$;


--
-- Name: protect_attendance_decisions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_attendance_decisions() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  -- دوال السيرفر (البصمة، decide_payroll_event) تعمل بصلاحية المالك ولها فحوصاتها
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  -- الموظف العادي: صلاحيات الجدول (RLS) تمنعه أصلاً من الكتابة
  IF NOT public.is_manager() THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.deduction_status IS NOT DISTINCT FROM OLD.deduction_status
     AND NEW.deduction_reason IS NOT DISTINCT FROM OLD.deduction_reason
     AND NEW.deduction_applied IS NOT DISTINCT FROM OLD.deduction_applied
     AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;
  IF NEW.employee_id = auth.uid() THEN
    RAISE EXCEPTION 'لا يمكنك اتخاذ قرار على حضورك.' USING ERRCODE = '42501';
  END IF;
  IF NOT public.payroll_same_branch(NEW.employee_id) THEN
    RAISE EXCEPTION 'غير مصرح: الموظف من فرع آخر.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: protect_attendance_times(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_attendance_times() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
     OR NEW.work_date IS DISTINCT FROM OLD.work_date
     OR NEW.check_in_time IS DISTINCT FROM OLD.check_in_time
     OR NEW.check_out_time IS DISTINCT FROM OLD.check_out_time
     OR NEW.check_in_lat IS DISTINCT FROM OLD.check_in_lat
     OR NEW.check_in_lng IS DISTINCT FROM OLD.check_in_lng
     OR NEW.check_out_lat IS DISTINCT FROM OLD.check_out_lat
     OR NEW.check_out_lng IS DISTINCT FROM OLD.check_out_lng
     OR NEW.is_mock_detected IS DISTINCT FROM OLD.is_mock_detected
     OR NEW.branch_id IS DISTINCT FROM OLD.branch_id
  THEN
    RAISE EXCEPTION 'غير مصرح: تعديل أوقات البصمة وموقعها للأدمن فقط.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: protect_employee_columns(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_employee_columns() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.role IS DISTINCT FROM OLD.role
     OR NEW.is_active IS DISTINCT FROM OLD.is_active
     OR NEW.branch_id IS DISTINCT FROM OLD.branch_id
     OR NEW.department_id IS DISTINCT FROM OLD.department_id
     OR NEW.employee_code IS DISTINCT FROM OLD.employee_code
     OR NEW.full_name IS DISTINCT FROM OLD.full_name
     OR NEW.email IS DISTINCT FROM OLD.email
     OR NEW.join_date IS DISTINCT FROM OLD.join_date
     OR NEW.termination_date IS DISTINCT FROM OLD.termination_date
     OR NEW.monthly_salary_iqd IS DISTINCT FROM OLD.monthly_salary_iqd
     OR NEW.future_salary_iqd IS DISTINCT FROM OLD.future_salary_iqd
     OR NEW.future_salary_month IS DISTINCT FROM OLD.future_salary_month
     OR NEW.device_id_lock IS DISTINCT FROM OLD.device_id_lock
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR (NEW.must_change_password AND NOT COALESCE(OLD.must_change_password, false))
  THEN
    RAISE EXCEPTION 'غير مصرح: هذه البيانات يعدّلها قسم الموارد البشرية فقط.' USING ERRCODE = '42501';
  END IF;

  -- المستمسكات: إضافة فقط. كل القديمة تبقى، والجديدة من مجلد الموظف نفسه.
  IF NEW.document_urls IS DISTINCT FROM OLD.document_urls THEN
    IF NOT (COALESCE(NEW.document_urls, '[]'::jsonb) @> COALESCE(OLD.document_urls, '[]'::jsonb))
       OR EXISTS (
         SELECT 1
         FROM jsonb_array_elements_text(COALESCE(NEW.document_urls, '[]'::jsonb)) AS u(url)
         WHERE NOT (COALESCE(OLD.document_urls, '[]'::jsonb) ? u.url)
           AND position('/employee-documents/' || OLD.id::text || '/' IN u.url) = 0
       )
    THEN
      RAISE EXCEPTION 'غير مصرح: تقدر تضيف مستمسكات فقط، والحذف أو التعديل من قسم الموارد البشرية.' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: protect_leave_decisions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_leave_decisions() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.employee_id = auth.uid()
       AND (NEW.start_date AT TIME ZONE public.company_timezone())::date < v_today - 30 THEN
      RAISE EXCEPTION 'لا يمكن طلب إجازة لتاريخ مضى عليه أكثر من 30 يوماً. راجع الإدارة.' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
  END IF;

  -- صاحب الطلب (موظف أو مدير): يلغي طلبه المعلّق بس
  IF OLD.employee_id = auth.uid() OR NEW.employee_id = auth.uid() THEN
    IF OLD.status = 'pending' AND NEW.status = 'cancelled' AND NEW.employee_id = OLD.employee_id THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'لا يمكنك اعتماد أو رفض أو تعديل طلب إجازتك.' USING ERRCODE = '42501';
  END IF;

  -- مدير الفرع: يقرر على طلبات فرعه المعلّقة بس
  IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
     OR NOT (OLD.employee_id = ANY (public.managed_employee_ids())) THEN
    RAISE EXCEPTION 'غير مصرح: الموظف من فرع آخر.' USING ERRCODE = '42501';
  END IF;
  IF OLD.status <> 'pending' THEN
    RAISE EXCEPTION 'الإجازة انقررت. تعديلها بعد القرار من مسؤول النظام (الأدمن) فقط.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: publish_announcement(text, text, timestamp with time zone, timestamp with time zone, text, uuid, uuid[], boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.publish_announcement(p_title text, p_content text, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_ends_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_target text DEFAULT 'all'::text, p_branch_id uuid DEFAULT NULL::uuid, p_employee_ids uuid[] DEFAULT NULL::uuid[], p_pinned boolean DEFAULT false) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_ann announcements%ROWTYPE;
  v_starts timestamptz := COALESCE(p_starts_at, now());
  v_count integer;
  v_period text;
BEGIN
  PERFORM public.require_admin_or_manager();

  IF COALESCE(btrim(p_title), '') = '' OR COALESCE(btrim(p_content), '') = '' THEN
    RAISE EXCEPTION 'اكتب عنوان التعميم ونصه.' USING ERRCODE = '22023';
  END IF;
  IF p_ends_at IS NOT NULL AND p_ends_at <= v_starts THEN
    RAISE EXCEPTION 'تاريخ انتهاء التعميم يجب أن يكون بعد تاريخ بدايته.' USING ERRCODE = '22023';
  END IF;
  IF p_ends_at IS NOT NULL AND p_ends_at <= now() THEN
    RAISE EXCEPTION 'تاريخ انتهاء التعميم مضى.' USING ERRCODE = '22023';
  END IF;
  IF p_target = 'branch' AND p_branch_id IS NULL THEN
    RAISE EXCEPTION 'اختر الفرع المستهدف.' USING ERRCODE = '22023';
  END IF;
  IF p_target = 'employees' AND COALESCE(cardinality(p_employee_ids), 0) = 0 THEN
    RAISE EXCEPTION 'اختر موظفاً واحداً على الأقل.' USING ERRCODE = '22023';
  END IF;

  INSERT INTO announcements (title, content, is_pinned, created_by, starts_at, ends_at, target_branch_id, target_employee_ids)
  VALUES (btrim(p_title), btrim(p_content), COALESCE(p_pinned, false), auth.uid(), v_starts, p_ends_at,
          CASE WHEN p_target = 'branch' THEN p_branch_id END,
          CASE WHEN p_target = 'employees' THEN p_employee_ids END)
  RETURNING * INTO v_ann;

  v_period := CASE
    WHEN p_ends_at IS NULL THEN ''
    ELSE format(' (ساري حتى %s)', to_char(p_ends_at AT TIME ZONE public.company_timezone(), 'YYYY-MM-DD'))
  END;

  INSERT INTO notifications (employee_id, title, body, type, is_read)
  SELECT e.id, '📢 ' || v_ann.title, v_ann.content || v_period, 'system', false
  FROM employees e
  WHERE e.is_active AND public.announcement_targets(v_ann, e.id);
  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN v_count;
END;
$$;


--
-- Name: punch_attendance(text, double precision, double precision, text, boolean, timestamp with time zone, double precision, timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.punch_attendance(p_type text, p_latitude double precision, p_longitude double precision, p_device_id text DEFAULT NULL::text, p_is_mocked boolean DEFAULT false, p_client_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_accuracy double precision DEFAULT NULL::double precision, p_trusted_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_time_check text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  -- هامش تسامح لفرق حساب المسافة بين الجهاز والسيرفر
  c_distance_tolerance_m constant double precision := 10;
  c_offline_max_age constant interval := interval '48 hours';
  -- أسوأ دقة GPS مقبولة (الموقع التقريبي بأندرويد 12+/iOS 14+ يبعد كيلومترات)
  c_max_accuracy_m constant double precision := 100;

  v_uid uuid := auth.uid();
  v_emp employees%ROWTYPE;
  v_branch branches%ROWTYPE;
  v_sched work_schedules%ROWTYPE;
  v_att attendance%ROWTYPE;
  v_tz text := public.company_timezone();
  v_now timestamptz := now();
  v_time timestamptz;
  v_offline boolean := false;
  v_local timestamp;
  v_work_date date;
  v_distance double precision;
  v_deadline timestamp;
  v_early_limit timestamp;
  v_status text;
  v_has_row boolean;
  -- مصدر الوقت: online = وقت السيرفر، offline_verified = محسوب من وقت السيرفر وعدّاد الموبايل، offline_review = ساعة الموبايل
  v_source text := 'online';
  v_device timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول.' USING ERRCODE = '42501';
  END IF;
  IF p_type NOT IN ('check_in', 'check_out') THEN
    RAISE EXCEPTION 'نوع بصمة غير صالح: %', p_type USING ERRCODE = '22023';
  END IF;
  IF p_latitude IS NULL OR p_longitude IS NULL THEN
    RAISE EXCEPTION 'الموقع الجغرافي مطلوب.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_emp FROM employees WHERE id = v_uid;
  IF NOT FOUND OR NOT v_emp.is_active THEN
    RAISE EXCEPTION 'هذا الحساب معطل حالياً.' USING ERRCODE = '42501';
  END IF;

  -- الجهاز المعتمد (إن كان قفل الجهاز مفعّلاً)
  IF COALESCE(v_emp.device_id_lock, '') NOT IN ('', 'force_lock_active')
     AND p_device_id IS DISTINCT FROM v_emp.device_id_lock THEN
    RAISE EXCEPTION 'هذا الجهاز غير معتمد للبصمة. راجع الإدارة لاعتماد جهازك.'
      USING ERRCODE = '42501';
  END IF;

  IF p_is_mocked THEN
    INSERT INTO mock_gps_attempts (employee_id, latitude, longitude, app_used)
    VALUES (v_uid, p_latitude, p_longitude, 'punch_attendance');
    RETURN jsonb_build_object('ok', false, 'code', 'mock_gps',
      'message', 'تم رصد موقع وهمي. تم تسجيل المحاولة وإبلاغ الإدارة.');
  END IF;

  -- الوقت: وقت السيرفر، أو لبصمة محفوظة بدون إنترنت:
  --   «مؤكد» = التطبيق حسبه من آخر وقت سيرفر + عدّاد الموبايل منذ التشغيل (ما يتأثر بتغيير الساعة ولا بإطفاء الشاشة)؛
  --   غيره (تطبيق قديم، الموبايل انطفى، ما اكو وقت سيرفر سابق) = ساعة الموبايل ويتعلّم «يحتاج مراجعة».
  -- (تدقيق 14/10 BUG-001: وضع الطيران + تغيير ساعة الموبايل كان يخفي التأخير والخروج المبكر)
  IF p_client_time IS NULL THEN
    v_time := v_now;
  ELSE
    v_device := p_client_time;
    IF p_time_check = 'anchored' AND p_trusted_time IS NOT NULL
       AND p_trusted_time <= v_now + interval '5 minutes' AND p_trusted_time >= v_now - c_offline_max_age THEN
      v_time := p_trusted_time;
      v_source := 'offline_verified';
    ELSE
      v_time := p_client_time;
      v_source := 'offline_review';
    END IF;
    IF v_time > v_now + interval '5 minutes' THEN
      RETURN jsonb_build_object('ok', false, 'code', 'clock_in_future',
        'message', 'وقت البصمة المحفوظة في المستقبل — ساعة الجهاز غير مضبوطة.');
    END IF;
    IF v_time < v_now - c_offline_max_age THEN
      RETURN jsonb_build_object('ok', false, 'code', 'offline_too_old',
        'message', 'البصمة المحفوظة أقدم من 48 ساعة ولا يمكن قبولها. راجع الإدارة.');
    END IF;
    v_offline := true;
  END IF;

  v_local := v_time AT TIME ZONE v_tz;
  v_work_date := v_local::date;

  -- المسافة من الفرع
  SELECT * INTO v_branch FROM branches WHERE id = v_emp.branch_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'code', 'no_branch',
      'message', 'لم يتم تعيين فرع لحسابك. راجع الإدارة.');
  END IF;

  -- دقة الموقع: فرع نطاقه أوسع من 100 م يتحمّل دقة بقدر نطاقه.
  -- النسخ القديمة من التطبيق ما ترسل الدقة (NULL) فتمر كما كانت.
  IF p_accuracy IS NOT NULL AND p_accuracy > GREATEST(c_max_accuracy_m, v_branch.radius_meters) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'low_accuracy',
      'accuracy_m', round(p_accuracy::numeric),
      'message', format('دقة الموقع ضعيفة (± %s م). فعّل «الموقع الدقيق» وانتظر لحظات بمكان مفتوح ثم حاول مرة ثانية.',
                        round(p_accuracy::numeric)));
  END IF;

  v_distance := public.distance_meters(p_latitude, p_longitude, v_branch.latitude, v_branch.longitude);
  IF v_distance > v_branch.radius_meters + c_distance_tolerance_m THEN
    RETURN jsonb_build_object('ok', false, 'code', 'out_of_range',
      'distance_m', round(v_distance::numeric, 1),
      'message', format('أنت خارج نطاق الفرع الجغرافي. المتبقي لتصل للفرع: %s متر.',
                        round((v_distance - v_branch.radius_meters)::numeric, 1)));
  END IF;

  SELECT * INTO v_sched FROM public.get_effective_work_schedule(v_uid);

  SELECT * INTO v_att FROM attendance
  WHERE employee_id = v_uid AND work_date = v_work_date
  FOR UPDATE;
  v_has_row := FOUND;

  IF p_type = 'check_in' THEN
    IF v_has_row AND v_att.check_in_time IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'code', 'already_checked_in',
        'message', 'لقد قمت بتسجيل بصمة الحضور مسبقاً لهذا اليوم!');
    END IF;

    -- متأخر إذا بعد موعد الحضور + فترة السماح (الافتراضي 08:30 + 15 دقيقة)
    -- (مقارنة timestamp وليس time حتى لا يلف الوقت بعد منتصف الليل)
    v_deadline := v_work_date + COALESCE(v_sched.check_in_time, time '08:30')
                  + make_interval(mins => COALESCE(v_sched.grace_period_minutes, 15));
    v_status := CASE WHEN v_local > v_deadline THEN 'late' ELSE 'present' END;

    IF v_has_row THEN
      -- سطر موجود (انصراف سُجّل قبل الحضور بالخطأ)
      UPDATE attendance
      SET check_in_time = v_time, check_in_lat = p_latitude, check_in_lng = p_longitude,
          check_in_offline = v_offline, status = v_status,
          check_in_time_source = v_source, check_in_device_time = v_device
      WHERE id = v_att.id
      RETURNING * INTO v_att;
    ELSE
      INSERT INTO attendance (employee_id, branch_id, work_date, status,
                              check_in_time, check_in_lat, check_in_lng, check_in_offline,
                              check_in_time_source, check_in_device_time)
      VALUES (v_uid, v_branch.id, v_work_date, v_status,
              v_time, p_latitude, p_longitude, v_offline, v_source, v_device)
      RETURNING * INTO v_att;
    END IF;
  ELSE
    IF v_has_row AND v_att.check_out_time IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'code', 'already_checked_out',
        'message', 'لقد قمت بتسجيل بصمة الانصراف مسبقاً لهذا اليوم!');
    END IF;

    IF NOT v_has_row THEN
      -- انصراف بدون حضور: يُحتسب نصف يوم
      INSERT INTO attendance (employee_id, branch_id, work_date, status,
                              check_out_time, check_out_lat, check_out_lng, check_out_offline,
                              check_out_time_source, check_out_device_time)
      VALUES (v_uid, v_branch.id, v_work_date, 'half_day',
              v_time, p_latitude, p_longitude, v_offline, v_source, v_device)
      RETURNING * INTO v_att;
    ELSE
      -- خروج مبكر بأكثر من 15 دقيقة يُحتسب نصف يوم (الافتراضي 16:30)
      v_early_limit := v_work_date + COALESCE(v_sched.check_out_time, time '16:30')
                       - interval '15 minutes';
      v_status := CASE
        WHEN v_local < v_early_limit THEN 'half_day'
        ELSE v_att.status
      END;

      UPDATE attendance
      SET check_out_time = v_time, check_out_lat = p_latitude, check_out_lng = p_longitude,
          check_out_offline = v_offline, status = v_status,
          check_out_time_source = v_source, check_out_device_time = v_device
      WHERE id = v_att.id
      RETURNING * INTO v_att;
    END IF;
  END IF;

  -- نقطة تتبع + إشعار نجاح للموظف
  INSERT INTO location_tracking (employee_id, latitude, longitude, is_moving, timestamp)
  VALUES (v_uid, p_latitude, p_longitude, false, v_time);

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (
    v_uid,
    -- التأخير ما يُذكر بالإشعار: الموظف يُبلَّغ بالخصم فقط إذا الإدارة طبّقته (decide_payroll_event)
    CASE WHEN p_type = 'check_out' THEN 'بصمة انصراف ناجحة 🔴' ELSE 'بصمة حضور ناجحة 🟢' END,
    CASE p_type
      WHEN 'check_in' THEN format('تم تسجيل حضورك اليوم بنجاح في فرع (%s). دواماً موفقاً!', v_branch.name)
      ELSE format('تم تسجيل انصرافك بنجاح من فرع (%s). يعطيك العافية!', v_branch.name)
    END,
    'attendance'
  );

  RETURN jsonb_build_object(
    'ok', true,
    'status', v_att.status,
    'work_date', v_att.work_date,
    'check_in_time', v_att.check_in_time,
    'check_out_time', v_att.check_out_time,
    'offline', v_offline,
    'time_source', v_source,
    'server_time', v_now,
    'distance_m', round(v_distance::numeric, 1)
  );
END;
$$;


--
-- Name: purge_old_assistant_conversations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purge_old_assistant_conversations() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE v_n int;
BEGIN
  PERFORM public.require_admin_or_system();
  DELETE FROM assistant_conversations WHERE updated_at < now() - interval '90 days';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;


--
-- Name: purge_old_location_tracking(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purge_old_location_tracking() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_days integer;
    v_deleted integer;
BEGIN
    SELECT COALESCE((value ->> 'tracking_archive_days')::int, 45) INTO v_days
    FROM system_settings WHERE key = 'archive_policy';
    v_days := GREATEST(COALESCE(v_days, 45), 35);
    DELETE FROM location_tracking
    WHERE timestamp < (now() - make_interval(days => v_days));
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$;


--
-- Name: FUNCTION purge_old_location_tracking(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.purge_old_location_tracking() IS 'يحذف نقاط GPS الأقدم من 90 يوماً من location_tracking. يعيد عدد الصفوف المحذوفة.';


--
-- Name: purge_system_logs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.purge_system_logs() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
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
$_$;


--
-- Name: reactivate_employee(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reactivate_employee(p_employee_id uuid, p_return_date date DEFAULT NULL::date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_emp employees%ROWTYPE;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_return date := COALESCE(p_return_date, (now() AT TIME ZONE public.company_timezone())::date);
  v_month text;
  v_gap int := 0;
  v_warnings jsonb := '[]'::jsonb;
  r record;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF v_emp.is_active THEN
    RAISE EXCEPTION 'حساب % مفعّل أصلاً.', v_emp.full_name USING ERRCODE = '22023';
  END IF;
  IF v_return > v_today THEN
    RAISE EXCEPTION 'تاريخ الرجوع ما يكون بالمستقبل: فعّل الحساب يوم يرجع.' USING ERRCODE = '22023';
  END IF;
  IF v_emp.join_date IS NOT NULL AND v_return < v_emp.join_date THEN
    RAISE EXCEPTION 'تاريخ الرجوع قبل تاريخ المباشرة (%).', to_char(v_emp.join_date, 'DD/MM/YYYY') USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('employees.return_date', v_return::text, true);
  UPDATE employees SET is_active = true WHERE id = p_employee_id;
  PERFORM set_config('employees.return_date', '', true);
  IF v_emp.termination_date IS NOT NULL AND v_return > v_emp.termination_date + 1 THEN
    v_gap := v_return - v_emp.termination_date - 1;
  END IF;

  -- المسيرات المفتوحة من آخر يوم عمل لحد اليوم تنعاد (أيام الانقطاع ما تطلع غياب)
  FOR r IN
    SELECT pp.period_month FROM payroll_periods pp
    WHERE pp.status = 'open' AND pp.cutoff_date >= COALESCE(v_emp.termination_date, v_return) AND pp.start_date <= v_today
      AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = p_employee_id AND s.work_month = pp.period_month)
    ORDER BY 1
  LOOP
    PERFORM public.sync_payroll_period(r.period_month, p_employee_id);
  END LOOP;

  -- راتب شهر الرجوع معتمد (مثلاً آخر راتب قبل الترك): أيام رجوعه ما تنحسب إلا بإلغاء الاعتماد وإعادته
  v_month := public.payroll_month_of(v_return);
  IF EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = p_employee_id AND s.work_month = v_month) THEN
    v_warnings := v_warnings || to_jsonb(format(
      'راتب الشهر %s %s معتمد من قبل الرجوع: ألغِ اعتماده من صفحة الرواتب وأعد اعتماده حتى تنحسب أيام رجوعه.',
      (ARRAY['الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس', 'السابع', 'الثامن', 'التاسع', 'العاشر', 'الحادي عشر', 'الثاني عشر'])[split_part(v_month, '-', 2)::int],
      split_part(v_month, '-', 1)));
  END IF;

  RETURN jsonb_build_object('employee_id', p_employee_id, 'last_day', v_emp.termination_date, 'return_date', v_return,
                            'gap_days', v_gap, 'warnings', v_warnings);
END;
$$;


--
-- Name: record_audit_log(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_audit_log() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_actor_id     UUID;
    v_actor_email  TEXT;
    v_changed_cols TEXT[];
    v_row_id       UUID;
BEGIN
    -- من هو الفاعل؟
    v_actor_id := auth.uid();
    IF v_actor_id IS NOT NULL THEN
        SELECT email INTO v_actor_email FROM auth.users WHERE id = v_actor_id;
    END IF;

    -- التقاط row_id بحسب نوع الجدول
    IF TG_OP = 'DELETE' THEN
        v_row_id := (OLD.id)::UUID;
    ELSE
        v_row_id := (NEW.id)::UUID;
    END IF;

    -- الأعمدة التي تغيّرت (فقط للـ UPDATE)
    IF TG_OP = 'UPDATE' THEN
        SELECT array_agg(key) INTO v_changed_cols
        FROM jsonb_each(to_jsonb(OLD)) o
        WHERE o.value IS DISTINCT FROM (to_jsonb(NEW) -> o.key);
    END IF;

    -- إدراج السطر في audit_log
    INSERT INTO audit_log (
        table_name, row_id, action, actor_id, actor_email,
        old_data, new_data, changed_columns
    ) VALUES (
        TG_TABLE_NAME,
        v_row_id,
        TG_OP,
        v_actor_id,
        v_actor_email,
        CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) ELSE NULL END,
        v_changed_cols
    );

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;


--
-- Name: FUNCTION record_audit_log(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.record_audit_log() IS 'Trigger function عامة لتسجيل التغييرات في audit_log. تلتقط: من فعل، متى، أي أعمدة تغيّرت.';


--
-- Name: record_employee_assignment(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_employee_assignment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO employee_assignment_history (employee_id, branch_id, department_id, effective_from, recorded_by)
    VALUES (NEW.id, NEW.branch_id, NEW.department_id, DATE '1900-01-01', auth.uid());
    RETURN NULL;
  END IF;
  IF NEW.branch_id IS NOT DISTINCT FROM OLD.branch_id AND NEW.department_id IS NOT DISTINCT FROM OLD.department_id THEN
    RETURN NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM employee_assignment_history WHERE employee_id = NEW.id) THEN
    INSERT INTO employee_assignment_history (employee_id, branch_id, department_id, effective_from)
    VALUES (NEW.id, OLD.branch_id, OLD.department_id, DATE '1900-01-01');
  END IF;
  INSERT INTO employee_assignment_history (employee_id, branch_id, department_id, effective_from, recorded_by)
  VALUES (NEW.id, NEW.branch_id, NEW.department_id, v_today, auth.uid());
  PERFORM public.sync_payroll_day(NEW.id, v_today);
  RETURN NULL;
END;
$$;


--
-- Name: record_salary_history(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_salary_history() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_month text;
  v_old text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO salary_history (employee_id, monthly_salary, effective_month, source)
    VALUES (NEW.id, COALESCE(NEW.monthly_salary_iqd, 0), '2000-01', 'initial')
    ON CONFLICT (employee_id, effective_month) DO NOTHING;
  ELSE
    IF NEW.monthly_salary_iqd IS DISTINCT FROM OLD.monthly_salary_iqd THEN
      -- تغيير مباشر: من شهر الرواتب الحالي (الأشهر المفتوحة الأقدم تبقى بالراتب القديم)
      v_month := public.payroll_month_of((now() AT TIME ZONE public.company_timezone())::date);
      INSERT INTO salary_history (employee_id, monthly_salary, effective_month, source)
      VALUES (NEW.id, COALESCE(NEW.monthly_salary_iqd, 0), v_month, 'change')
      ON CONFLICT (employee_id, effective_month) DO UPDATE SET monthly_salary = EXCLUDED.monthly_salary, source = 'change',
        created_by = auth.uid(), created_at = now();
    END IF;
    IF NEW.future_salary_iqd IS DISTINCT FROM OLD.future_salary_iqd
       OR NEW.future_salary_month IS DISTINCT FROM OLD.future_salary_month THEN
      -- إلغاء/تغيير زيادة بعدها ما بدت ينمسح سطرها؛ الزيادة اللي بدت تبقى بالسجل (تاريخ)
      v_old := public._salary_effective_month(OLD.future_salary_month);
      IF v_old IS NOT NULL AND v_old > public.payroll_month_of((now() AT TIME ZONE public.company_timezone())::date) THEN
        DELETE FROM salary_history WHERE employee_id = NEW.id AND effective_month = v_old AND source = 'scheduled';
      END IF;
      v_month := public._salary_effective_month(NEW.future_salary_month);
      IF NEW.future_salary_iqd IS NOT NULL AND v_month IS NOT NULL THEN
        INSERT INTO salary_history (employee_id, monthly_salary, effective_month, source)
        VALUES (NEW.id, NEW.future_salary_iqd, v_month, 'scheduled')
        ON CONFLICT (employee_id, effective_month) DO UPDATE SET monthly_salary = EXCLUDED.monthly_salary, source = 'scheduled',
          created_by = auth.uid(), created_at = now();
      END IF;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;


--
-- Name: record_work_schedule_history(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.record_work_schedule_history() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  r work_schedules%ROWTYPE;
BEGIN
  IF TG_OP = 'DELETE' THEN r := OLD; ELSE r := NEW; END IF;
  -- تعديل الاسم أو وقت التذكير ما يغيّر الحساب
  IF TG_OP = 'UPDATE'
     AND NEW.employee_id IS NOT DISTINCT FROM OLD.employee_id AND NEW.department_id IS NOT DISTINCT FROM OLD.department_id
     AND NEW.branch_id IS NOT DISTINCT FROM OLD.branch_id AND NEW.check_in_time IS NOT DISTINCT FROM OLD.check_in_time
     AND NEW.check_out_time IS NOT DISTINCT FROM OLD.check_out_time
     AND NEW.grace_period_minutes IS NOT DISTINCT FROM OLD.grace_period_minutes
     AND NEW.work_days IS NOT DISTINCT FROM OLD.work_days THEN
    RETURN NULL;
  END IF;
  -- أكثر من تعديل بنفس اليوم: آخر واحد هو الساري
  DELETE FROM work_schedule_history WHERE schedule_id = r.id AND effective_from = v_today;
  INSERT INTO work_schedule_history (schedule_id, employee_id, department_id, branch_id, check_in_time, check_out_time,
                                     grace_period_minutes, work_days, schedule_created_at, effective_from, removed)
  VALUES (r.id, r.employee_id, r.department_id, r.branch_id, r.check_in_time, r.check_out_time,
          r.grace_period_minutes, r.work_days, r.created_at, v_today, TG_OP = 'DELETE');
  RETURN NULL;
END;
$$;


--
-- Name: register_device_login(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.register_device_login(p_device_id text, p_model text DEFAULT NULL::text, p_os_version text DEFAULT NULL::text, p_legacy_device_id text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_emp employees%ROWTYPE;
  v_lock text;
  v_has_devices boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول.' USING ERRCODE = '42501';
  END IF;
  IF COALESCE(p_device_id, '') = '' THEN
    RAISE EXCEPTION 'معرّف الجهاز مطلوب.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_emp FROM employees WHERE id = v_uid FOR UPDATE;
  IF NOT FOUND OR NOT v_emp.is_active THEN
    RAISE EXCEPTION 'هذا الحساب معطل حالياً.' USING ERRCODE = '42501';
  END IF;
  v_lock := COALESCE(v_emp.device_id_lock, '');

  -- ترحيل المعرّف القديم إلى الجديد
  IF COALESCE(p_legacy_device_id, '') <> '' AND p_legacy_device_id <> p_device_id THEN
    IF v_lock = p_legacy_device_id THEN
      UPDATE employees SET device_id_lock = p_device_id WHERE id = v_uid;
      v_lock := p_device_id;
    END IF;
    DELETE FROM employee_devices
    WHERE employee_id = v_uid AND device_id = p_device_id
      AND EXISTS (SELECT 1 FROM employee_devices
                  WHERE employee_id = v_uid AND device_id = p_legacy_device_id);
    UPDATE employee_devices SET device_id = p_device_id
    WHERE employee_id = v_uid AND device_id = p_legacy_device_id;
  END IF;

  -- الحالة 1: القفل غير مفعّل → نسجّل الجهاز الحالي فقط
  IF v_lock = '' THEN
    DELETE FROM employee_devices WHERE employee_id = v_uid AND device_id <> p_device_id;
    INSERT INTO employee_devices (employee_id, device_id, model, os_version, is_approved, approved_at)
    VALUES (v_uid, p_device_id, p_model, p_os_version, true, now())
    ON CONFLICT (employee_id, device_id) DO UPDATE
      SET model = EXCLUDED.model, os_version = EXCLUDED.os_version,
          is_approved = true, approved_at = COALESCE(employee_devices.approved_at, now());
    RETURN jsonb_build_object('ok', true);
  END IF;

  SELECT EXISTS (SELECT 1 FROM employee_devices WHERE employee_id = v_uid) INTO v_has_devices;

  -- الحالة 2: أول دخول، أو 3: الأدمن طلب إعادة الضبط → اعتماد هذا الجهاز
  IF NOT v_has_devices OR v_lock = 'force_lock_active' THEN
    DELETE FROM employee_devices WHERE employee_id = v_uid;
    INSERT INTO employee_devices (employee_id, device_id, model, os_version, is_approved, approved_at)
    VALUES (v_uid, p_device_id, p_model, p_os_version, true, now());
    UPDATE employees SET device_id_lock = p_device_id WHERE id = v_uid;
    RETURN jsonb_build_object('ok', true);
  END IF;

  -- الحالة 4: قفل على جهاز محدد
  IF v_lock = p_device_id AND EXISTS (
    SELECT 1 FROM employee_devices
    WHERE employee_id = v_uid AND device_id = p_device_id AND is_approved
  ) THEN
    RETURN jsonb_build_object('ok', true);
  END IF;

  -- جهاز غير معتمد: طلب ربط جديد + إشعار للموظف والإدارة
  INSERT INTO employee_devices (employee_id, device_id, model, os_version, is_approved)
  VALUES (v_uid, p_device_id, p_model, p_os_version, false)
  ON CONFLICT (employee_id, device_id) DO NOTHING;

  INSERT INTO notifications (employee_id, title, body, type)
  SELECT id, n.title, n.body, 'device'
  FROM (
    SELECT v_uid AS id,
           'محاولة خرق أمني للدخول ⚠️' AS title,
           format('تمت محاولة تسجيل دخول إلى حسابك (%s) من جهاز جديد (%s). تم تقديم طلب ربط جهاز جديد وبانتظار موافقة الإدارة.',
                  v_emp.full_name, COALESCE(p_model, 'غير معروف')) AS body
    UNION ALL
    SELECT e.id,
           'طلب اعتماد جهاز جديد 📱',
           format('الموظف (%s) حاول الدخول من جهاز غير معتمد (%s).',
                  v_emp.full_name, COALESCE(p_model, 'غير معروف'))
    FROM employees e
    WHERE e.role = 'admin' AND e.is_active AND e.id <> v_uid
  ) n
  WHERE NOT EXISTS (
    SELECT 1 FROM notifications x
    WHERE x.employee_id = n.id AND x.title = n.title AND x.body = n.body
      AND x.created_at > now() - interval '1 hour'
  );

  RETURN jsonb_build_object('ok', false, 'code', 'device_locked');
END;
$$;


--
-- Name: reject_future_attendance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reject_future_attendance() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  -- إدخالات المستخدمين فقط (البصمة من السيرفر تستعمل وقت السيرفر أصلاً)
  -- رسالة عربية قبل قيد chk_attendance_out_after_in
  IF NEW.check_out_time IS NOT NULL AND NEW.check_in_time IS NOT NULL AND NEW.check_out_time < NEW.check_in_time THEN
    RAISE EXCEPTION 'وقت الانصراف لازم يكون بعد وقت الحضور.' USING ERRCODE = '23514';
  END IF;
  IF current_user IN ('authenticated', 'anon')
     AND (TG_OP = 'INSERT' OR NEW.work_date IS DISTINCT FROM OLD.work_date)
     AND NEW.work_date > (now() AT TIME ZONE public.company_timezone())::date THEN
    RAISE EXCEPTION 'لا يمكن تسجيل حضور أو غياب ليوم لم يأتِ بعد (%).', NEW.work_date USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: reject_negative_salary_slip(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reject_negative_salary_slip() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.net_salary < 0 THEN
    RAISE EXCEPTION 'صافي الراتب بالسالب (%): الخصومات أكبر من الراتب. راجع خصوماته قبل الاعتماد.',
      to_char(NEW.net_salary, 'FM999,999,999')
      USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: reopen_payroll_period(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reopen_payroll_period(p_month text, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: request_account_deletion(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.request_account_deletion() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_name text;
  v_sent integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول.' USING ERRCODE = '42501';
  END IF;

  SELECT full_name INTO v_name FROM employees WHERE id = v_uid;

  INSERT INTO notifications (employee_id, title, body, type)
  SELECT e.id,
         'طلب حذف حساب موظف ⚠️',
         format('الموظف (%s) قدم طلباً لحذف حسابه. يرجى مراجعة حسابه المالي وإجراءات الإغلاق من لوحة الإدارة.',
                COALESCE(v_name, 'غير معروف')),
         'system'
  FROM employees e
  WHERE e.role = 'admin' AND e.is_active AND e.id <> v_uid
    -- طلب واحد في اليوم يكفي
    AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.employee_id = e.id
        AND n.title = 'طلب حذف حساب موظف ⚠️'
        AND n.body LIKE '%(' || COALESCE(v_name, 'غير معروف') || ')%'
        AND n.created_at > now() - interval '1 day'
    );
  GET DIAGNOSTICS v_sent = ROW_COUNT;

  RETURN v_sent;
END;
$$;


--
-- Name: require_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.require_admin() RETURNS void
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح: هذه العملية لمسؤول النظام (Admin) فقط.'
      USING ERRCODE = '42501';
  END IF;
END;
$$;


--
-- Name: require_admin_or_manager(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.require_admin_or_manager() RETURNS void
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NOT (public.is_admin() OR public.is_manager()) THEN
    RAISE EXCEPTION 'غير مصرح: هذه العملية للإدارة فقط.'
      USING ERRCODE = '42501';
  END IF;
END;
$$;


--
-- Name: require_admin_or_system(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.require_admin_or_system() RETURNS void
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF COALESCE(auth.role(), '') = 'anon' THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح: هذه العملية لمسؤول النظام (Admin) فقط.'
      USING ERRCODE = '42501';
  END IF;
END;
$$;


--
-- Name: reschedule_loan(uuid, numeric, numeric, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reschedule_loan(p_loan_id uuid, p_amount numeric, p_installment_amount numeric, p_count integer) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_loan loans%ROWTYPE;
  v_paid numeric;
  v_paid_count integer;
  v_remaining numeric;
  v_base numeric := round(p_installment_amount);
  v_n integer := 0;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_month text;
  v_first date;
  i integer;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_loan FROM loans WHERE id = p_loan_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'السلفة غير موجودة.' USING ERRCODE = 'P0002';
  END IF;
  IF v_loan.status <> 'approved' THEN
    RAISE EXCEPTION 'يمكن تعديل السلف المعتمدة فقط.' USING ERRCODE = '55000';
  END IF;
  IF COALESCE(p_amount, 0) <= 0 OR COALESCE(v_base, 0) <= 0 THEN
    RAISE EXCEPTION 'اكتب مبلغاً وقسطاً شهرياً أكبر من الصفر.' USING ERRCODE = '22023';
  END IF;
  IF v_base > p_amount THEN
    RAISE EXCEPTION 'القسط أكبر من مبلغ السلفة.' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(sum(amount), 0), count(*) INTO v_paid, v_paid_count
  FROM loan_installments WHERE loan_id = p_loan_id AND is_paid;
  v_remaining := round(p_amount - v_paid);
  IF v_remaining < 0 THEN
    RAISE EXCEPTION 'المبلغ الجديد أقل من المسدَّد (%).', to_char(v_paid, 'FM999,999,999') USING ERRCODE = '22023';
  END IF;
  IF v_remaining > 0 THEN
    v_n := ceil(v_remaining / v_base)::int;
  END IF;

  -- أول شهر: شهر الرواتب المفتوح الحالي إذا كشفه ما صادر، وإلا اللي بعده (بدون فترة مسجّلة: الشهر الجاي)
  SELECT period_month, GREATEST(to_date(period_month || '-01', 'YYYY-MM-DD'), start_date) INTO v_month, v_first
  FROM payroll_periods WHERE v_today BETWEEN start_date AND cutoff_date LIMIT 1;
  IF v_month IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM payroll_periods WHERE period_month = v_month AND status = 'closed')
       OR EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = v_loan.employee_id AND work_month = v_month) THEN
      v_first := (date_trunc('month', v_first) + interval '1 month')::date;
    END IF;
  ELSE
    v_first := (date_trunc('month', v_today) + interval '1 month')::date;
  END IF;

  -- الجدول يُكتب هنا كاملاً: التريجر لا يولّد أقساطاً أثناء الحذف والإضافة
  PERFORM set_config('loans.skip_rebalance', 'on', true);

  UPDATE loans
  SET amount = round(p_amount), installment_amount = v_base,
      installment_count = v_paid_count + v_n, remaining_amount = v_remaining
  WHERE id = p_loan_id;

  DELETE FROM loan_installments WHERE loan_id = p_loan_id AND NOT is_paid;

  FOR i IN 0 .. v_n - 1 LOOP
    INSERT INTO loan_installments (loan_id, due_date, amount, is_paid)
    VALUES (p_loan_id, (v_first + make_interval(months => i))::date,
            CASE WHEN i = v_n - 1 THEN v_remaining - v_base * (v_n - 1) ELSE v_base END, false);
  END LOOP;

  PERFORM set_config('loans.skip_rebalance', 'off', true);

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (v_loan.employee_id, 'تعديل تفاصيل السلفة 💸',
          CASE WHEN v_n = 0 THEN format('قامت الإدارة بتعديل سلفتك: المبلغ الكلي %s د.ع، والسلفة مسددة بالكامل.',
                                        to_char(round(p_amount), 'FM999,999,999'))
               ELSE format('قامت الإدارة بتعديل سلفتك: المبلغ الكلي %s د.ع، القسط الشهري %s د.ع، المتبقي %s د.ع على %s قسط من شهر %s إلى شهر %s.',
                           to_char(round(p_amount), 'FM999,999,999'), to_char(v_base, 'FM999,999,999'),
                           to_char(v_remaining, 'FM999,999,999'), v_n, to_char(v_first, 'MM/YYYY'),
                           to_char((v_first + make_interval(months => v_n - 1))::date, 'MM/YYYY')) END,
          'loan');
  RETURN v_n;
END;
$$;


--
-- Name: restore_archived_employee(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.restore_archived_employee(p_archive_id uuid, p_return_date date DEFAULT NULL::date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  a archived_employees%ROWTYPE;
  v_result jsonb := jsonb_build_object('gap_days', 0, 'warnings', '[]'::jsonb);
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO a FROM archived_employees WHERE id = p_archive_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'سجل الأرشيف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF a.archive_type = 'permanent' THEN
    RAISE EXCEPTION 'هذا الموظف انحذف نهائياً وما يرجع.' USING ERRCODE = '55000';
  END IF;
  IF EXISTS (SELECT 1 FROM employees WHERE id = a.employee_id AND NOT is_active) THEN
    v_result := public.reactivate_employee(a.employee_id, p_return_date);
  END IF;
  DELETE FROM archived_employees WHERE id = p_archive_id;
  RETURN v_result;
END;
$$;


--
-- Name: resync_payroll_on_salary_change(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resync_payroll_on_salary_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  r record;
BEGIN
  IF NEW.monthly_salary_iqd IS NOT DISTINCT FROM OLD.monthly_salary_iqd
     AND NEW.future_salary_iqd IS NOT DISTINCT FROM OLD.future_salary_iqd
     AND NEW.future_salary_month IS NOT DISTINCT FROM OLD.future_salary_month THEN
    RETURN NEW;
  END IF;
  FOR r IN
    SELECT pp.period_month FROM payroll_periods pp
    WHERE pp.status = 'open'
      AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = NEW.id AND s.work_month = pp.period_month)
  LOOP
    PERFORM public.sync_payroll_period(r.period_month, NEW.id);
  END LOOP;
  RETURN NEW;
END;
$$;


--
-- Name: revert_payroll_slip(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revert_payroll_slip(p_slip_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_slip salary_slips%ROWTYPE;
  v_p payroll_periods%ROWTYPE;
  c record;
  v_before_ids uuid[];
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

  -- (PAY-010) الأقساط اللي نقصت/تأجلت وقت الاعتماد ترجع مثل ما جانت (أول نسخة لكل سلفة = قبل أي تعديل).
  -- بس إذا جدول السلفة ما تغيّر بعدها (ما انسدد قسط منها ولا انعادت جدولتها)؛ غير هيج يبقى الجدول الحالي (مجموعه صحيح).
  PERFORM set_config('loans.skip_rebalance', 'on', true);
  FOR c IN
    SELECT DISTINCT ON (loan_id) loan_id, installments_before
    FROM payroll_loan_caps WHERE salary_slip_id = p_slip_id
    ORDER BY loan_id, id
  LOOP
    SELECT COALESCE(array_agg((x ->> 'id')::uuid), '{}') INTO v_before_ids FROM jsonb_array_elements(c.installments_before) x;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM unnest(v_before_ids) b(id)
      WHERE NOT EXISTS (SELECT 1 FROM loan_installments li WHERE li.id = b.id AND li.loan_id = c.loan_id AND NOT li.is_paid));
    CONTINUE WHEN (SELECT COALESCE(sum((x ->> 'amount')::numeric), 0) FROM jsonb_array_elements(c.installments_before) x)
      IS DISTINCT FROM (SELECT l.amount - COALESCE((SELECT sum(amount) FROM loan_installments WHERE loan_id = l.id AND is_paid), 0)
                        FROM loans l WHERE l.id = c.loan_id);
    DELETE FROM loan_installments WHERE loan_id = c.loan_id AND NOT is_paid AND NOT (id = ANY (v_before_ids));
    UPDATE loan_installments li
    SET due_date = (x ->> 'due_date')::date, amount = (x ->> 'amount')::numeric,
        amount_locked = (x ->> 'amount_locked')::boolean, payment_note = x ->> 'payment_note',
        origin_kind = x ->> 'origin_kind', origin_month = (x ->> 'origin_month')::date
    FROM jsonb_array_elements(c.installments_before) x
    WHERE li.id = (x ->> 'id')::uuid AND NOT li.is_paid;
    UPDATE loans l
    SET remaining_amount = GREATEST(l.amount - COALESCE((SELECT sum(amount) FROM loan_installments WHERE loan_id = l.id AND is_paid), 0), 0)
    WHERE l.id = c.loan_id;
  END LOOP;
  PERFORM set_config('loans.skip_rebalance', 'off', true);
  DELETE FROM payroll_loan_caps WHERE salary_slip_id = p_slip_id;

  DELETE FROM bonuses_deductions WHERE salary_slip_id = p_slip_id;
  DELETE FROM salary_slips WHERE id = p_slip_id;
END;
$$;


--
-- Name: revert_salary_slip(uuid, date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revert_salary_slip(p_slip_id uuid, p_period_start date, p_period_end date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_slip salary_slips%ROWTYPE;
  v_linked boolean;
BEGIN
  PERFORM public.require_admin();

  SELECT * INTO v_slip FROM salary_slips WHERE id = p_slip_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'كشف الراتب غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF EXISTS (SELECT 1 FROM archived_months WHERE work_month = v_slip.work_month) THEN
    RAISE EXCEPTION 'هذا الشهر مؤرشف مالياً ومقفل.' USING ERRCODE = '42501';
  END IF;

  v_linked := EXISTS (SELECT 1 FROM loan_installments WHERE paid_by_slip_id = p_slip_id)
           OR EXISTS (SELECT 1 FROM bonuses_deductions WHERE salary_slip_id = p_slip_id);

  IF v_linked THEN
    UPDATE loan_installments
    SET is_paid = false, paid_at = NULL, paid_by_slip_id = NULL
    WHERE paid_by_slip_id = p_slip_id;
  ELSE
    DELETE FROM bonuses_deductions
    WHERE employee_id = v_slip.employee_id
      AND salary_slip_id IS NULL
      AND issue_date = p_period_end
      AND (reason LIKE '%للفترة من ' || p_period_start || ' إلى ' || p_period_end || '%'
           OR reason LIKE '%لشهر ' || v_slip.work_month || '%');

    UPDATE loan_installments li
    SET is_paid = false, paid_at = NULL
    FROM loans l
    WHERE li.loan_id = l.id
      AND l.employee_id = v_slip.employee_id
      AND li.is_paid = true
      AND li.due_date BETWEEN p_period_start AND p_period_end;
  END IF;

  DELETE FROM salary_slips WHERE id = p_slip_id;
END;
$$;


--
-- Name: safe_archive_payroll_month(text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.safe_archive_payroll_month(target_month text, cycle_start_day integer DEFAULT 25, cycle_end_day integer DEFAULT 24) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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
$$;


--
-- Name: FUNCTION safe_archive_payroll_month(target_month text, cycle_start_day integer, cycle_end_day integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.safe_archive_payroll_month(target_month text, cycle_start_day integer, cycle_end_day integer) IS 'أرشفة شهر مالي معتمد: تحذف الحضور والخصومات التفصيلية للدورة وتقفل الشهر. مقفل على الأدمن.
البارامترات: work_month بصيغة YYYY-MM، يوم بداية ونهاية الدورة.';


--
-- Name: safe_delete_employee(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.safe_delete_employee(p_employee_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth'
    AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح: يجب تسجيل الدخول لتنفيذ هذا الإجراء.' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح: حذف الموظفين لمسؤول النظام (Admin) فقط.' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.employees WHERE id = p_employee_id) THEN
    RAISE EXCEPTION 'الموظف المطلوب غير موجود في النظام.';
  END IF;

  IF p_employee_id = auth.uid() THEN
    RAISE EXCEPTION 'لا يمكنك حذف حسابك بنفسك.';
  END IF;

  PERFORM public._anonymize_employee(p_employee_id);
END;
$$;


--
-- Name: FUNCTION safe_delete_employee(p_employee_id uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.safe_delete_employee(p_employee_id uuid) IS 'حذف آمن لموظف: يخفي هويته (الاسم، الهاتف، البريد، المستندات)، يحذف أجهزته وتوكناته وحساب المصادقة،
ويُبقي سجلات الحضور والرواتب لأغراض المحاسبة. للأدمن والمدير فقط (لا يحذف المدير أدمن).';


--
-- Name: save_employee(uuid, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_employee(p_employee_id uuid, p_email text, p_password text, p_phone text, p_changes jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_unknown text;
  c jsonb := COALESCE(p_changes, '{}'::jsonb);
BEGIN
  PERFORM public.require_admin();
  IF NOT EXISTS (SELECT 1 FROM employees WHERE id = p_employee_id) THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  SELECT string_agg(k, '، ') INTO v_unknown
  FROM jsonb_object_keys(c) k
  WHERE k NOT IN ('full_name', 'role', 'branch_id', 'department_id', 'join_date', 'document_urls',
                  'monthly_salary_iqd', 'future_salary_iqd', 'future_salary_month');
  IF v_unknown IS NOT NULL THEN
    RAISE EXCEPTION 'حقل ما ينحفظ من هنا: %', v_unknown USING ERRCODE = '22023';
  END IF;

  PERFORM public.update_employee_credentials(p_employee_id, p_email, p_password, p_phone);

  UPDATE employees e SET
    full_name = CASE WHEN c ? 'full_name' THEN c ->> 'full_name' ELSE e.full_name END,
    role = CASE WHEN c ? 'role' THEN c ->> 'role' ELSE e.role END,
    branch_id = CASE WHEN c ? 'branch_id' THEN NULLIF(c ->> 'branch_id', '')::uuid ELSE e.branch_id END,
    department_id = CASE WHEN c ? 'department_id' THEN NULLIF(c ->> 'department_id', '')::uuid ELSE e.department_id END,
    join_date = CASE WHEN c ? 'join_date' THEN NULLIF(c ->> 'join_date', '')::date ELSE e.join_date END,
    document_urls = CASE WHEN c ? 'document_urls' THEN COALESCE(c -> 'document_urls', '[]'::jsonb) ELSE e.document_urls END,
    monthly_salary_iqd = CASE WHEN c ? 'monthly_salary_iqd' THEN COALESCE((c ->> 'monthly_salary_iqd')::numeric, 0) ELSE e.monthly_salary_iqd END,
    future_salary_iqd = CASE WHEN c ? 'future_salary_iqd' THEN (c ->> 'future_salary_iqd')::numeric ELSE e.future_salary_iqd END,
    future_salary_month = CASE WHEN c ? 'future_salary_month' THEN NULLIF(c ->> 'future_salary_month', '') ELSE e.future_salary_month END
  WHERE e.id = p_employee_id;
END;
$$;


--
-- Name: send_assistant_morning_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_assistant_morning_summary() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: send_idempotent_notification(uuid, text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_idempotent_notification(p_employee_id uuid, p_title text, p_body text, p_type text, p_dedup_window_minutes integer DEFAULT 60) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF auth.uid() IS NOT NULL
     AND p_employee_id IS DISTINCT FROM auth.uid()
     AND NOT (public.is_admin() OR p_employee_id = ANY (public.managed_employee_ids())) THEN
    RAISE EXCEPTION 'غير مصرح بإرسال إشعار لموظف آخر.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.notifications
    WHERE employee_id = p_employee_id
      AND title = p_title
      AND body = p_body
      AND created_at > (NOW() - (p_dedup_window_minutes || ' minutes')::INTERVAL)
  ) THEN
    RETURN false;
  END IF;

  INSERT INTO public.notifications (employee_id, title, body, type, is_read, created_at)
  VALUES (p_employee_id, p_title, p_body, p_type, false, NOW());

  RETURN true;
END;
$$;


--
-- Name: FUNCTION send_idempotent_notification(p_employee_id uuid, p_title text, p_body text, p_type text, p_dedup_window_minutes integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.send_idempotent_notification(p_employee_id uuid, p_title text, p_body text, p_type text, p_dedup_window_minutes integer) IS 'إرسال إشعار دون تكرار: يفحص إذا كان إشعار بنفس المحتوى موجود لنفس الموظف اليوم قبل الإدراج.
البارامترات: employee_id, title, body, type, نافذة التكرار بالدقائق. يعيد TRUE إذا أُدرج إشعار جديد.';


--
-- Name: server_now(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.server_now() RETURNS timestamp with time zone
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$ SELECT now(); $$;


--
-- Name: set_employee_leave_entitlement(uuid, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_employee_leave_entitlement(p_employee_id uuid, p_annual numeric, p_sick numeric, p_hourly_monthly_hours numeric) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.require_admin();
  IF COALESCE(p_annual, 0) < 0 OR COALESCE(p_sick, 0) < 0 OR COALESCE(p_hourly_monthly_hours, 0) < 0 THEN
    RAISE EXCEPTION 'الرصيد لا يمكن أن يكون بالسالب.' USING ERRCODE = '22023';
  END IF;
  INSERT INTO leave_balances (employee_id, annual_entitlement, sick_entitlement, hourly_monthly_hours)
  VALUES (p_employee_id, p_annual, p_sick, p_hourly_monthly_hours)
  ON CONFLICT (employee_id) DO UPDATE
  SET annual_entitlement = EXCLUDED.annual_entitlement,
      sick_entitlement = EXCLUDED.sick_entitlement,
      hourly_monthly_hours = EXCLUDED.hourly_monthly_hours,
      updated_at = now();
END;
$$;


--
-- Name: set_month_installment(uuid, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_month_installment(p_installment_id uuid, p_amount numeric, p_note text DEFAULT NULL::text) RETURNS numeric
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_inst loan_installments%ROWTYPE;
  v_loan loans%ROWTYPE;
  v_last date;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_inst FROM loan_installments WHERE id = p_installment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'القسط غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF v_inst.is_paid THEN
    RAISE EXCEPTION 'هذا القسط مسدد مسبقاً.' USING ERRCODE = '55000';
  END IF;
  SELECT * INTO v_loan FROM loans WHERE id = v_inst.loan_id FOR UPDATE;
  IF v_loan.status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'السلفة غير معتمدة.' USING ERRCODE = '55000';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'اكتب المبلغ اللي يكدر يدفعه (أكبر من صفر). إذا ما يكدر يدفع شي، استعمل التأجيل.' USING ERRCODE = '22023';
  END IF;
  IF round(p_amount) >= v_inst.amount THEN
    RAISE EXCEPTION 'المبلغ لازم يكون أقل من قسط الشهر (%).', to_char(v_inst.amount, 'FM999,999,999') USING ERRCODE = '22023';
  END IF;
  IF public._loan_month_settled(v_loan.employee_id, v_inst.due_date) THEN
    RAISE EXCEPTION 'راتب هذا الشهر صادر أو الفترة مقفلة؛ ما يتغير قسطه.' USING ERRCODE = '55000';
  END IF;

  PERFORM set_config('loans.shortfall_origin', v_inst.due_date::text, true);
  UPDATE loan_installments
  SET amount = round(p_amount), amount_locked = true,
      payment_note = COALESCE(NULLIF(btrim(COALESCE(p_note, '')), ''), payment_note)
  WHERE id = p_installment_id;
  PERFORM set_config('loans.shortfall_origin', '', true);

  SELECT max(due_date) INTO v_last FROM loan_installments WHERE loan_id = v_loan.id;
  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (v_loan.employee_id, 'تعديل قسط السلفة 💸',
          format('قسط شهر %s صار %s د.ع، والباقي (%s د.ع) انضاف بآخر السلفة. آخر قسط بشهر %s.',
                 to_char(v_inst.due_date, 'MM/YYYY'), to_char(round(p_amount), 'FM999,999,999'),
                 to_char(v_inst.amount - round(p_amount), 'FM999,999,999'), to_char(v_last, 'MM/YYYY')),
          'loan');
  RETURN (SELECT remaining_amount FROM loans WHERE id = v_loan.id);
END;
$$;


--
-- Name: set_payroll_policy(integer, integer, boolean, numeric, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_payroll_policy(p_cutoff_day integer, p_payment_day integer, p_overtime_enabled boolean, p_overtime_multiplier numeric DEFAULT 1, p_overtime_min_minutes integer DEFAULT 30) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: set_termination_date(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_termination_date() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_return date;
BEGIN
  IF COALESCE(OLD.is_active, true) AND NOT COALESCE(NEW.is_active, true) AND NEW.termination_date IS NULL THEN
    NEW.termination_date := v_today;
  ELSIF NOT COALESCE(OLD.is_active, true) AND COALESCE(NEW.is_active, true) THEN
    -- الأيام بين آخر يوم عمل ويوم الرجوع ما تطلع غياب، وتنقص من راتب ذاك المسير مثل الأيام قبل المباشرة
    v_return := COALESCE(NULLIF(current_setting('employees.return_date', true), '')::date, v_today);
    IF OLD.termination_date IS NOT NULL AND v_return > OLD.termination_date + 1 THEN
      INSERT INTO employee_service_breaks (employee_id, last_day, return_date, recorded_by)
      VALUES (NEW.id, OLD.termination_date, v_return, auth.uid());
    END IF;
    NEW.termination_date := NULL;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: settle_loan_on_exit(uuid, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.settle_loan_on_exit(p_employee_id uuid, p_month text, p_amount numeric DEFAULT NULL::numeric) RETURNS numeric
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_emp employees%ROWTYPE;
  v_future numeric;
  v_take numeric;
  v_left numeric;
  v_loan record;
  v_part numeric;
  v_rest numeric;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  IF NOT FOUND OR v_p.status <> 'open' THEN
    RAISE EXCEPTION 'مسير % مو مفتوح.', p_month USING ERRCODE = '55000';
  END IF;
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  IF v_emp.termination_date IS NULL OR v_emp.termination_date > v_p.cutoff_date OR v_emp.termination_date < v_p.start_date THEN
    RAISE EXCEPTION 'الموظف ما ترك العمل خلال هذا المسير.' USING ERRCODE = '55000';
  END IF;
  IF EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = p_employee_id AND work_month = p_month) THEN
    RAISE EXCEPTION 'راتبه الأخير صادر. ألغِ الاعتماد أولاً.' USING ERRCODE = '55000';
  END IF;

  SELECT COALESCE(sum(li.amount), 0) INTO v_future
  FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid AND li.due_date > v_p.cutoff_date;
  IF v_future <= 0 THEN
    RAISE EXCEPTION 'ماكو أقساط باقية بعد هذا المسير.' USING ERRCODE = '55000';
  END IF;

  v_take := round(COALESCE(p_amount, LEAST(v_future, GREATEST((public.payroll_employee_summary(p_employee_id, p_month) ->> 'net')::numeric, 0))));
  IF v_take <= 0 OR v_take > v_future THEN
    RAISE EXCEPTION 'المبلغ لازم يكون بين 1 و %.', to_char(v_future, 'FM999,999,999') USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('loans.skip_rebalance', 'on', true);
  v_left := v_take;
  FOR v_loan IN
    SELECT l.id, sum(li.amount) AS future
    FROM loans l JOIN loan_installments li ON li.loan_id = l.id
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid AND li.due_date > v_p.cutoff_date
    GROUP BY l.id, l.created_at ORDER BY l.created_at
  LOOP
    v_part := LEAST(v_left, v_loan.future);
    v_rest := v_loan.future - v_part;
    DELETE FROM loan_installments WHERE loan_id = v_loan.id AND NOT is_paid AND due_date > v_p.cutoff_date;
    IF v_part > 0 THEN
      INSERT INTO loan_installments (loan_id, due_date, amount, is_paid, amount_locked, payment_type, payment_note)
      VALUES (v_loan.id, v_p.cutoff_date, v_part, false, true, 'salary_deduction', 'تسوية ترك العمل من آخر راتب');
    END IF;
    IF v_rest > 0 THEN
      INSERT INTO loan_installments (loan_id, due_date, amount, is_paid, amount_locked, payment_type, payment_note)
      VALUES (v_loan.id, (v_p.cutoff_date + interval '1 month')::date, v_rest, false, true, 'cash', 'يسدد نقداً بعد ترك العمل');
    END IF;
    v_left := v_left - v_part;
  END LOOP;
  PERFORM set_config('loans.skip_rebalance', 'off', true);

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (p_employee_id, 'تسوية السلفة 💸',
          format('بسبب ترك العمل ينخصم %s د.ع من آخر راتب.%s', to_char(v_take, 'FM999,999,999'),
                 CASE WHEN v_future > v_take THEN format(' الباقي %s د.ع يسدد نقداً.', to_char(v_future - v_take, 'FM999,999,999')) ELSE '' END),
          'loan');
  RETURN v_take;
END;
$$;


--
-- Name: sync_geofence_coordinates(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_geofence_coordinates() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    coord_elem jsonb;
    new_coords jsonb := '[]'::jsonb;
    lat_val double precision;
    lng_val double precision;
BEGIN
    IF NEW.polygon_coordinates IS NOT NULL AND jsonb_array_length(NEW.polygon_coordinates) > 0 THEN
        FOR coord_elem IN SELECT jsonb_array_elements(NEW.polygon_coordinates) LOOP
            IF jsonb_array_length(coord_elem) = 2 THEN
                lat_val := (coord_elem->>0)::double precision;
                lng_val := (coord_elem->>1)::double precision;
                new_coords := new_coords || jsonb_build_object('lat', lat_val, 'lng', lng_val);
            END IF;
        END LOOP;
        NEW.coordinates := new_coords;
    ELSIF NEW.coordinates IS NOT NULL AND jsonb_array_length(NEW.coordinates) > 0 THEN
        FOR coord_elem IN SELECT jsonb_array_elements(NEW.coordinates) LOOP
            IF coord_elem ? 'lat' AND coord_elem ? 'lng' THEN
                lat_val := (coord_elem->>'lat')::double precision;
                lng_val := (coord_elem->>'lng')::double precision;
                new_coords := new_coords || jsonb_build_array(lat_val, lng_val);
            END IF;
        END LOOP;
        NEW.polygon_coordinates := new_coords;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: sync_geofences_to_branches(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_geofences_to_branches() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
    INSERT INTO branches (id, name, latitude, longitude, radius_meters, address)
    VALUES (new.id, new.name, COALESCE(new.latitude, 33.3152), COALESCE(new.longitude, 44.3661), COALESCE(new.radius_meters, 150.0), 'موقع عمل مرسوم')
    ON CONFLICT (id) DO UPDATE SET
      name = EXCLUDED.name,
      latitude = EXCLUDED.latitude,
      longitude = EXCLUDED.longitude,
      radius_meters = EXCLUDED.radius_meters;
  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM branches WHERE id = old.id;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: sync_payroll_day(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_payroll_day(p_employee_id uuid, p_date date) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_natural text;
  v_emp employees%ROWTYPE;
  v_sched work_schedules%ROWTYPE;
  v_att attendance%ROWTYPE;
  v_has_att boolean;
  v_policy jsonb := public.payroll_policy();
  v_daily numeric;
  v_minute numeric;
  v_workday boolean;
  v_full_leave leave_requests%ROWTYPE;
  v_has_full_leave boolean;
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
  v_daily := public.payroll_daily_rate(p_employee_id, v_natural);
  v_minute := v_daily / public.payroll_shift_minutes_at(p_employee_id, p_date);
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
      PERFORM public._payroll_day_attendance_events(p_employee_id, p_date, v_att, v_sched, v_workday, v_daily, v_minute, v_policy);
    ELSE
      PERFORM public._payroll_day_leave_events(p_employee_id, p_date, v_workday, v_daily, v_policy);
    END IF;
    PERFORM public._payroll_day_hourly_leaves(p_employee_id, p_date, v_minute);
  END IF;

  PERFORM public._payroll_day_apply(p_employee_id, p_date, v_natural, v_daily, v_minute, v_policy);
END;
$$;


--
-- Name: sync_payroll_manual(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_payroll_manual(p_bd_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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
$$;


--
-- Name: sync_payroll_period(text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_payroll_period(p_month text, p_employee_id uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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
$$;


--
-- Name: track_attendance_time_source(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.track_attendance_time_source() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  -- دوال السيرفر (البصمة، القرارات) تكتب المصدر بنفسها
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.check_in_time_source := CASE WHEN NEW.check_in_time IS NOT NULL THEN 'manual' END;
    NEW.check_out_time_source := CASE WHEN NEW.check_out_time IS NOT NULL THEN 'manual' END;
    NEW.check_in_device_time := NULL;
    NEW.check_out_device_time := NULL;
    RETURN NEW;
  END IF;

  IF NEW.check_in_device_time IS DISTINCT FROM OLD.check_in_device_time
     OR NEW.check_out_device_time IS DISTINCT FROM OLD.check_out_device_time THEN
    RAISE EXCEPTION 'وقت ساعة الموبايل ما يتعدّل.' USING ERRCODE = '42501';
  END IF;

  IF NEW.check_in_time IS DISTINCT FROM OLD.check_in_time THEN
    NEW.check_in_time_source := CASE WHEN NEW.check_in_time IS NOT NULL THEN 'manual' END;
  ELSIF NEW.check_in_time_source IS DISTINCT FROM OLD.check_in_time_source
        AND NOT (OLD.check_in_time_source = 'offline_review' AND NEW.check_in_time_source = 'offline_reviewed') THEN
    RAISE EXCEPTION 'مصدر وقت البصمة ما يتغير يدوياً (بس «تمت المراجعة»).' USING ERRCODE = '42501';
  END IF;

  IF NEW.check_out_time IS DISTINCT FROM OLD.check_out_time THEN
    NEW.check_out_time_source := CASE WHEN NEW.check_out_time IS NOT NULL THEN 'manual' END;
  ELSIF NEW.check_out_time_source IS DISTINCT FROM OLD.check_out_time_source
        AND NOT (OLD.check_out_time_source = 'offline_review' AND NEW.check_out_time_source = 'offline_reviewed') THEN
    RAISE EXCEPTION 'مصدر وقت البصمة ما يتغير يدوياً (بس «تمت المراجعة»).' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: trash_removed_employee_files(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trash_removed_employee_files() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  r record;
BEGIN
  FOR r IN
    -- مستمسكات انشالت من القائمة
    SELECT 'employee-documents' AS bucket, 'document' AS kind, substring(u FROM '/employee-documents/([^?#]+)') AS path
    FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(OLD.document_urls) = 'array' THEN OLD.document_urls ELSE '[]'::jsonb END) u
    WHERE NOT (CASE WHEN jsonb_typeof(NEW.document_urls) = 'array' THEN NEW.document_urls ELSE '[]'::jsonb END) ? u
    UNION ALL
    -- الصورة الشخصية انشالت (الحذف النهائي). تبديل الصورة يتكفل بيه التطبيق نفسه
    SELECT 'avatars', 'avatar', substring(OLD.avatar_url FROM '/avatars/([^?#]+)')
    WHERE OLD.avatar_url IS NOT NULL AND NEW.avatar_url IS NULL
  LOOP
    CONTINUE WHEN r.path IS NULL;
    -- بس الملف الموجود فعلاً، ومو بالسلة من قبل
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = r.bucket AND o.name = r.path);
    CONTINUE WHEN EXISTS (SELECT 1 FROM deleted_files d WHERE d.file_path = r.path AND d.restored_at IS NULL);
    INSERT INTO deleted_files (file_path, file_type, related_table, related_id, deleted_by, scheduled_deletion_date, file_size_bytes)
    SELECT r.path, r.kind, 'employees', NEW.id::text, auth.uid(), now() + interval '30 days',
           NULLIF(o.metadata ->> 'size', '')::bigint
    FROM storage.objects o WHERE o.bucket_id = r.bucket AND o.name = r.path
    LIMIT 1;
  END LOOP;
  RETURN NULL;
END;
$$;


--
-- Name: trg_payroll_attendance(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_payroll_attendance() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: trg_payroll_holiday(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_payroll_holiday() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_emp record;
  v_day date := COALESCE(NEW.holiday_date, OLD.holiday_date);
BEGIN
  FOR v_emp IN SELECT id FROM employees WHERE is_active OR termination_date IS NOT NULL ORDER BY id LOOP
    PERFORM public.sync_payroll_day(v_emp.id, v_day);
  END LOOP;
  RETURN NULL;
END;
$$;


--
-- Name: trg_payroll_leave(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_payroll_leave() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: trg_payroll_manual(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_payroll_manual() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  PERFORM public.sync_payroll_manual(COALESCE(NEW.id, OLD.id));
  RETURN NULL;
END;
$$;


--
-- Name: update_employee_credentials(uuid, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_employee_credentials(p_employee_id uuid, p_email text, p_password text DEFAULT NULL::text, p_phone text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'auth', 'extensions'
    AS $$
DECLARE
  v_hashed_password text;
BEGIN
  PERFORM public.require_admin();

  IF p_password IS NOT NULL AND p_password != '' THEN
    v_hashed_password := extensions.crypt(p_password, extensions.gen_salt('bf'));
    UPDATE auth.users
    SET email = p_email,
        encrypted_password = v_hashed_password,
        phone = NULLIF(p_phone, ''),
        updated_at = now()
    WHERE id = p_employee_id;
  ELSE
    UPDATE auth.users
    SET email = p_email,
        phone = NULLIF(p_phone, ''),
        updated_at = now()
    WHERE id = p_employee_id;
  END IF;

  UPDATE auth.identities
  SET identity_data = jsonb_set(identity_data, '{email}', to_jsonb(p_email)),
      updated_at = now()
  WHERE user_id = p_employee_id;

  UPDATE public.employees
  SET email = p_email,
      phone = NULLIF(p_phone, '')
  WHERE id = p_employee_id;
END;
$$;


--
-- Name: FUNCTION update_employee_credentials(p_employee_id uuid, p_email text, p_password text, p_phone text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_employee_credentials(p_employee_id uuid, p_email text, p_password text, p_phone text) IS 'تحديث كلمة المرور و/أو البريد الإلكتروني لموظف. مقفل على الأدمن.
البارامترات: employee_id, email, password?, phone?.';


--
-- Name: update_loan_and_installments_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_loan_and_installments_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_loan_id uuid;
    v_loan_amount numeric;
    v_base numeric;
    v_total_paid numeric;
    v_new_remaining numeric;
    v_left numeric;
    v_alloc numeric;
    v_row record;
    v_last_due date;
    v_origin date;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_loan_id := OLD.loan_id;
    ELSE
        v_loan_id := NEW.loan_id;
    END IF;

    -- إعادة الجدولة من reschedule_loan تكتب الجدول كاملاً بنفسها: لا توليد تلقائي أثناءها
    IF current_setting('loans.skip_rebalance', true) = 'on' THEN
        RETURN NULL;
    END IF;

    IF pg_trigger_depth() = 1 THEN
        -- قفل السلفة: تعديلان متزامنان لا يولّدان نفس الأشهر مرتين
        SELECT amount, installment_amount INTO v_loan_amount, v_base
        FROM public.loans WHERE id = v_loan_id FOR UPDATE;
        IF NOT FOUND THEN
            RETURN NULL;
        END IF;

        SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
        FROM public.loan_installments WHERE loan_id = v_loan_id AND is_paid;
        v_new_remaining := GREATEST(v_loan_amount - v_total_paid, 0);

        UPDATE public.loans SET remaining_amount = v_new_remaining WHERE id = v_loan_id;

        IF v_new_remaining <= 0 THEN
            DELETE FROM public.loan_installments WHERE loan_id = v_loan_id AND NOT is_paid;
            RETURN NULL;
        END IF;

        v_left := v_new_remaining;
        FOR v_row IN
            SELECT id, amount, amount_locked FROM public.loan_installments
            WHERE loan_id = v_loan_id AND NOT is_paid
            ORDER BY due_date, id
        LOOP
            IF v_left <= 0 THEN
                DELETE FROM public.loan_installments WHERE id = v_row.id;
                CONTINUE;
            END IF;
            v_alloc := CASE WHEN v_row.amount_locked THEN LEAST(v_row.amount, v_left) ELSE LEAST(v_base, v_left) END;
            IF v_alloc IS DISTINCT FROM v_row.amount THEN
                UPDATE public.loan_installments SET amount = v_alloc WHERE id = v_row.id;
            END IF;
            v_left := v_left - v_alloc;
        END LOOP;

        IF v_left > 0 THEN
            -- من وين جا النقص: الشهر اللي حدده الأدمن، أو القسط اللي انسدد بأقل من القسط الشهري
            v_origin := NULLIF(current_setting('loans.shortfall_origin', true), '')::date;
            IF v_origin IS NULL AND TG_OP = 'UPDATE' AND NEW.is_paid AND NOT OLD.is_paid AND NEW.amount < v_base THEN
                v_origin := NEW.due_date;
            END IF;

            SELECT COALESCE(MAX(due_date), (now() AT TIME ZONE public.company_timezone())::date) INTO v_last_due
            FROM public.loan_installments WHERE loan_id = v_loan_id;

            WHILE v_left > 0 LOOP
                v_last_due := (v_last_due + interval '1 month')::date;
                v_alloc := LEAST(v_base, v_left);
                INSERT INTO public.loan_installments (loan_id, due_date, amount, is_paid, origin_kind, origin_month)
                VALUES (v_loan_id, v_last_due, v_alloc, false,
                        CASE WHEN v_origin IS NOT NULL THEN 'shortfall' END, v_origin);
                v_left := v_left - v_alloc;
            END LOOP;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;


--
-- Name: FUNCTION update_loan_and_installments_trigger(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_loan_and_installments_trigger() IS 'Trigger function: يحدّث remaining_amount ويعيد توزيع الأقساط غير المسددة. يقفل صف السلفة لمنع التوليد المكرر.';


--
-- Name: validate_leave_request(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_leave_request() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_tz text := public.company_timezone();
  v_types jsonb := public.leave_policy() -> 'active_types';
  v_days numeric;
  v_hours numeric;
  v_bal jsonb;
  v_left numeric;
BEGIN
  -- يتفحص: طلب جديد، أو اعتماد، أو تعديل تواريخ/نوع إجازة معتمدة (كان التعديل بعد الاعتماد يتخطى الرصيد والتداخل)
  IF TG_OP = 'UPDATE' AND NOT (
       (NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved')
       OR (NEW.status = 'approved' AND (
             NEW.start_date IS DISTINCT FROM OLD.start_date OR NEW.end_date IS DISTINCT FROM OLD.end_date
             OR NEW.leave_type IS DISTINCT FROM OLD.leave_type OR NEW.is_hourly IS DISTINCT FROM OLD.is_hourly
             OR NEW.start_hour IS DISTINCT FROM OLD.start_hour OR NEW.end_hour IS DISTINCT FROM OLD.end_hour))) THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' AND NEW.status NOT IN ('pending', 'approved') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' AND jsonb_typeof(v_types) = 'array' AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_types) t WHERE t ->> 'id' = NEW.leave_type
  ) THEN
    RAISE EXCEPTION 'نوع الإجازة غير متاح حالياً.' USING ERRCODE = '22023';
  END IF;

  IF NEW.start_date IS NULL OR NEW.end_date IS NULL OR NEW.end_date < NEW.start_date THEN
    RAISE EXCEPTION 'تاريخ نهاية الإجازة يجب أن يكون بعد تاريخ بدايتها.' USING ERRCODE = '22023';
  END IF;
  IF NEW.is_hourly AND NEW.start_hour IS NOT NULL AND NEW.end_hour IS NOT NULL
     AND NEW.end_hour <= NEW.start_hour THEN
    RAISE EXCEPTION 'وقت نهاية الإجازة الزمنية يجب أن يكون بعد وقت بدايتها.' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM leave_requests o
    WHERE o.employee_id = NEW.employee_id
      AND o.id IS DISTINCT FROM NEW.id
      AND o.status IN ('pending', 'approved')
      AND (o.start_date AT TIME ZONE v_tz)::date <= (NEW.end_date AT TIME ZONE v_tz)::date
      AND (o.end_date AT TIME ZONE v_tz)::date >= (NEW.start_date AT TIME ZONE v_tz)::date
      AND (
        NOT (COALESCE(o.is_hourly, false) AND COALESCE(NEW.is_hourly, false))
        OR o.start_hour IS NULL OR NEW.start_hour IS NULL
        OR (o.start_hour < NEW.end_hour AND NEW.start_hour < o.end_hour)
      )
  ) THEN
    RAISE EXCEPTION 'توجد إجازة أخرى (قيد الانتظار أو معتمدة) تتداخل مع هذه التواريخ.' USING ERRCODE = '23P01';
  END IF;

  v_bal := public.get_leave_balance(NEW.employee_id, (NEW.start_date AT TIME ZONE v_tz)::date, NEW.id);

  IF COALESCE(NEW.is_hourly, false) THEN
    v_hours := public.leave_request_hours(NEW);
    v_left := (v_bal -> 'hourly' ->> 'left_hours')::numeric;
    IF v_hours > v_left THEN
      RAISE EXCEPTION 'رصيد الإجازات الزمنية لهذا الشهر غير كافٍ: المطلوب % ساعة والمتبقي % ساعة.',
        public.fmt_days(v_hours), public.fmt_days(GREATEST(v_left, 0)) USING ERRCODE = '22023';
    END IF;
  ELSE
    v_days := public.leave_request_days(NEW);
    IF v_days = 0 THEN
      RAISE EXCEPTION 'الأيام المختارة كلها عطلة رسمية، لا حاجة لإجازة.' USING ERRCODE = '22023';
    END IF;
    IF NEW.leave_type IN ('annual', 'sick') THEN
      v_left := (v_bal -> NEW.leave_type ->> 'left')::numeric;
      IF v_days > v_left THEN
        RAISE EXCEPTION 'رصيد الإجازة غير كافٍ: المطلوب % يوم والمتبقي % يوم.',
          public.fmt_days(v_days), public.fmt_days(GREATEST(v_left, 0)) USING ERRCODE = '22023';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: app_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_versions (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    version_code integer NOT NULL,
    version_name text NOT NULL,
    apk_url text NOT NULL,
    ipa_url text,
    is_mandatory boolean DEFAULT false NOT NULL,
    release_notes text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: TABLE app_versions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.app_versions IS 'سجل إصدارات التطبيق وملفات التحميل لغرض تحديثات OTA';


--
-- Name: archived_employees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.archived_employees (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    employee_code text,
    full_name text NOT NULL,
    archived_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    archive_reason text,
    archive_type text NOT NULL,
    scheduled_deletion_date timestamp with time zone,
    archived_by uuid,
    notes text,
    CONSTRAINT archived_employees_archive_type_check CHECK ((archive_type = ANY (ARRAY['permanent'::text, 'scheduled_deletion'::text, 'archived'::text])))
);


--
-- Name: TABLE archived_employees; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.archived_employees IS 'سجلات الموظفين المستقيلين أو المفصولين مع طريقة وخيارات الأرشفة والحذف المجدول';


--
-- Name: archived_months; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.archived_months (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    work_month text NOT NULL,
    archived_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    archived_by uuid,
    attendance_deleted integer DEFAULT 0,
    bd_deleted integer DEFAULT 0,
    notifications_deleted integer DEFAULT 0
);


--
-- Name: TABLE archived_months; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.archived_months IS 'سجل الأشهر المؤرشفة التي تم تنظيف بياناتها التفصيلية بأمان بعد اعتماد جميع الرواتب';


--
-- Name: assistant_conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assistant_conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid DEFAULT auth.uid() NOT NULL,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT assistant_conversations_title_check CHECK (((char_length(title) >= 1) AND (char_length(title) <= 120)))
);


--
-- Name: TABLE assistant_conversations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.assistant_conversations IS 'محادثات المساعد الذكي المحفوظة (للأدمن صاحبها فقط، تنحذف بعد 90 يوم)';


--
-- Name: assistant_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assistant_messages (
    id bigint NOT NULL,
    conversation_id uuid NOT NULL,
    role text NOT NULL,
    text text NOT NULL,
    voice boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT assistant_messages_role_check CHECK ((role = ANY (ARRAY['user'::text, 'assistant'::text]))),
    CONSTRAINT assistant_messages_text_check CHECK (((char_length(text) >= 1) AND (char_length(text) <= 20000)))
);


--
-- Name: TABLE assistant_messages; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.assistant_messages IS 'نص رسائل المساعد الذكي (بدون ملفات أو صوت)';


--
-- Name: assistant_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.assistant_messages ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.assistant_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: attendance_reminder_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_reminder_log (
    employee_id uuid NOT NULL,
    work_date date NOT NULL,
    kind text NOT NULL,
    sent_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE attendance_reminder_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.attendance_reminder_log IS 'تذكيرات البصمة المرسلة (لمنع التكرار). تكتبها check_and_send_attendance_reminders فقط.';


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    table_name text NOT NULL,
    row_id uuid,
    action text NOT NULL,
    actor_id uuid,
    actor_email text,
    old_data jsonb,
    new_data jsonb,
    changed_columns text[],
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    ip_address inet,
    CONSTRAINT audit_log_action_check CHECK ((action = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


--
-- Name: TABLE audit_log; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.audit_log IS 'سجل تدقيق شامل للتغييرات على الجداول الحساسة (salary_slips, loans, employees, ...).
كل تحديث/إدراج/حذف يترك أثراً مع من فعل ومتى وأي أعمدة تغيّرت.';


--
-- Name: bonuses_deductions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bonuses_deductions (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    type text NOT NULL,
    amount numeric NOT NULL,
    reason text NOT NULL,
    issue_date date DEFAULT CURRENT_DATE NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    salary_slip_id uuid,
    superseded_by_attendance boolean DEFAULT false NOT NULL,
    CONSTRAINT bonuses_deductions_type_check CHECK ((type = ANY (ARRAY['bonus'::text, 'deduction'::text]))),
    CONSTRAINT chk_bd_amount_positive CHECK ((amount > (0)::numeric))
);


--
-- Name: TABLE bonuses_deductions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.bonuses_deductions IS 'سجل المكافآت والخصومات الفورية الصادرة بحق الموظف بالدينار العراقي';


--
-- Name: COLUMN bonuses_deductions.salary_slip_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bonuses_deductions.salary_slip_id IS 'الكشف الذي أنشأ هذا القيد تلقائياً عند الاعتماد. يُحذف القيد مع الكشف عند التراجع. NULL = قيد يدوي.';


--
-- Name: branches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.branches (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    radius_meters double precision DEFAULT 100 NOT NULL,
    address text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: TABLE branches; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.branches IS 'فروع الشركة ونطاقات الجغرافي الخاصة بالبصمة';


--
-- Name: cleanup_run_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cleanup_run_tokens (
    token uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: company_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_settings (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    logo_url text,
    address text,
    phone text,
    email text,
    website text,
    tax_number text,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: TABLE company_settings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.company_settings IS 'إعدادات وبيانات الشركة العامة المظهرة في التقارير وكشوف الرواتب';


--
-- Name: deleted_files; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deleted_files (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    file_path text NOT NULL,
    file_type text NOT NULL,
    related_table text,
    related_id text,
    deleted_by uuid,
    deleted_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    scheduled_deletion_date timestamp with time zone NOT NULL,
    file_size_bytes bigint,
    restored_at timestamp with time zone,
    CONSTRAINT deleted_files_file_type_check CHECK ((file_type = ANY (ARRAY['avatar'::text, 'document'::text, 'pledge'::text, 'logo'::text, 'other'::text])))
);


--
-- Name: TABLE deleted_files; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.deleted_files IS 'سلة المحذوفات للاحتفاظ بالملفات المحذوفة مؤقتاً لمدة 30 يوماً قبل الحذف التام';


--
-- Name: departments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departments (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    manager_id uuid,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: TABLE departments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.departments IS 'الأقسام الإدارية للشركة';


--
-- Name: device_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_tokens (
    employee_id uuid NOT NULL,
    token text NOT NULL,
    platform text NOT NULL,
    CONSTRAINT device_tokens_platform_check CHECK ((platform = ANY (ARRAY['android'::text, 'ios'::text])))
);


--
-- Name: TABLE device_tokens; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.device_tokens IS 'رموز أجهزة الهواتف المخصصة لإرسال إشعارات Push عبر FCM';


--
-- Name: employee_assignment_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_assignment_history (
    id bigint NOT NULL,
    employee_id uuid NOT NULL,
    branch_id uuid,
    department_id uuid,
    effective_from date NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    recorded_by uuid
);


--
-- Name: employee_assignment_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employee_assignment_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_assignment_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.employee_assignment_history_id_seq OWNED BY public.employee_assignment_history.id;


--
-- Name: employee_code_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employee_code_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_devices (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    device_id text NOT NULL,
    model text,
    os_version text,
    is_approved boolean DEFAULT false NOT NULL,
    approved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: TABLE employee_devices; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.employee_devices IS 'الأجهزة المعتمدة للموظفين لضمان تسجيل الدخول من جهاز واحد معتمد فقط';


--
-- Name: employee_geofence_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_geofence_assignments (
    employee_id uuid NOT NULL,
    zone_id uuid NOT NULL
);


--
-- Name: TABLE employee_geofence_assignments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.employee_geofence_assignments IS 'تعيين وتخصيص مناطق السياج الجغرافي للموظفين ميدانياً';


--
-- Name: employee_service_breaks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_service_breaks (
    id bigint NOT NULL,
    employee_id uuid NOT NULL,
    last_day date NOT NULL,
    return_date date NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    recorded_by uuid,
    CONSTRAINT employee_service_breaks_dates CHECK ((return_date > (last_day + 1)))
);


--
-- Name: employee_service_breaks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.employee_service_breaks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_service_breaks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.employee_service_breaks_id_seq OWNED BY public.employee_service_breaks.id;


--
-- Name: employees; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employees (
    id uuid NOT NULL,
    employee_code text NOT NULL,
    full_name text NOT NULL,
    phone text,
    email text,
    avatar_url text,
    is_active boolean DEFAULT true NOT NULL,
    role text DEFAULT 'employee'::text NOT NULL,
    department_id uuid,
    branch_id uuid,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    monthly_salary_iqd numeric NOT NULL,
    future_salary_iqd numeric,
    future_salary_month text,
    join_date date DEFAULT CURRENT_DATE,
    device_id_lock text,
    fcm_token text,
    must_change_password boolean DEFAULT true NOT NULL,
    document_urls jsonb DEFAULT '[]'::jsonb,
    termination_date date,
    CONSTRAINT chk_employees_name_not_blank CHECK ((btrim(full_name) <> ''::text)),
    CONSTRAINT chk_employees_salary_non_negative CHECK (((monthly_salary_iqd >= (0)::numeric) AND ((future_salary_iqd IS NULL) OR (future_salary_iqd >= (0)::numeric)))),
    CONSTRAINT chk_employees_termination_after_join CHECK (((termination_date IS NULL) OR (join_date IS NULL) OR (termination_date >= join_date))),
    CONSTRAINT employees_document_urls_is_array CHECK (((document_urls IS NULL) OR (jsonb_typeof(document_urls) = 'array'::text))),
    CONSTRAINT employees_role_check CHECK ((role = ANY (ARRAY['employee'::text, 'manager'::text, 'admin'::text])))
);


--
-- Name: TABLE employees; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.employees IS 'بيانات الموظفين الأساسية وربطهم بالأقسام والفروع والمهام الإدارية';


--
-- Name: COLUMN employees.must_change_password; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.must_change_password IS 'حقل يحدد ما إذا كان الموظف مطالباً بتغيير كلمة المرور المؤقتة عند أول تسجيل دخول';


--
-- Name: COLUMN employees.document_urls; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.document_urls IS 'مصفوفة روابط المستندات الإضافية والوثائق للموظف';


--
-- Name: COLUMN employees.termination_date; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.employees.termination_date IS 'آخر يوم خدمة؛ يُضبط تلقائياً عند تعطيل الحساب. يدخل الموظف في مسير الفترة التي فيها هذا اليوم.';


--
-- Name: fcm_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fcm_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    token text NOT NULL,
    device_platform text DEFAULT 'android'::text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: geofence_violations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.geofence_violations (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    zone_id uuid NOT NULL,
    violation_type text NOT NULL,
    "timestamp" timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT geofence_violations_violation_type_check CHECK ((violation_type = ANY (ARRAY['entry'::text, 'exit'::text])))
);


--
-- Name: TABLE geofence_violations; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.geofence_violations IS 'مخالفات الدخول والخروج المسجلة من وإلى مناطق السياج الجغرافي للموظفين المكلفين';


--
-- Name: geofence_zones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.geofence_zones (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    coordinates jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    latitude double precision,
    longitude double precision,
    radius_meters integer,
    polygon_coordinates jsonb
);


--
-- Name: TABLE geofence_zones; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.geofence_zones IS 'مناطق ومساحات السياج الجغرافي المرسومة لمتابعة الموظفين';


--
-- Name: leave_balances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_balances (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    annual_entitlement integer,
    sick_entitlement integer,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    hourly_monthly_hours numeric(6,2)
);


--
-- Name: TABLE leave_balances; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.leave_balances IS 'أرصدة إجازات الموظفين السنوية والمرضية والمنقضية';


--
-- Name: COLUMN leave_balances.annual_entitlement; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_balances.annual_entitlement IS 'أيام السنوية لهذا الموظف؛ فارغ = leave_policy.default_annual';


--
-- Name: COLUMN leave_balances.sick_entitlement; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_balances.sick_entitlement IS 'أيام المرضية لهذا الموظف؛ فارغ = leave_policy.default_sick';


--
-- Name: COLUMN leave_balances.hourly_monthly_hours; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.leave_balances.hourly_monthly_hours IS 'ساعات الزمنيات الشهرية لهذا الموظف؛ فارغ = leave_policy.hourly_monthly_hours';


--
-- Name: loan_installments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loan_installments (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    loan_id uuid NOT NULL,
    due_date date NOT NULL,
    amount numeric NOT NULL,
    is_paid boolean DEFAULT false NOT NULL,
    paid_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    paid_by_slip_id uuid,
    payment_type text,
    payment_note text,
    origin_kind text,
    origin_month date,
    amount_locked boolean DEFAULT false NOT NULL,
    CONSTRAINT loan_installments_origin_kind_check CHECK ((origin_kind = ANY (ARRAY['shortfall'::text, 'postponed'::text])))
);


--
-- Name: TABLE loan_installments; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.loan_installments IS 'الأقساط الشهرية وجدول سداد السلف';


--
-- Name: COLUMN loan_installments.paid_by_slip_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.loan_installments.paid_by_slip_id IS 'الكشف الذي سدّد هذا القسط. يُستعمل لإرجاع القسط غير مدفوع عند التراجع عن الكشف.';


--
-- Name: COLUMN loan_installments.origin_kind; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.loan_installments.origin_kind IS 'shortfall = باقي شهر ما انسدد كامل؛ postponed = قسط شهر مؤجّل';


--
-- Name: COLUMN loan_installments.origin_month; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.loan_installments.origin_month IS 'الشهر الأصلي (للعرض: «باقي شهر 10/2026» أو «مؤجّل من 12/2026»)';


--
-- Name: COLUMN loan_installments.amount_locked; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.loan_installments.amount_locked IS 'مبلغ ثابت حدده الأدمن لهالشهر؛ إعادة التوزيع ما تغيّره';


--
-- Name: loan_no_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.loan_no_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: loans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loans (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    amount numeric NOT NULL,
    installment_amount numeric NOT NULL,
    installment_count integer NOT NULL,
    remaining_amount numeric NOT NULL,
    pledge_url text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    payment_method text,
    approved_by uuid,
    approved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    rejection_reason text,
    notes text,
    loan_no bigint NOT NULL,
    CONSTRAINT chk_loans_installment_le_amount CHECK ((installment_amount <= amount)),
    CONSTRAINT chk_loans_positive_amounts CHECK (((amount > (0)::numeric) AND (installment_count > 0) AND (installment_amount > (0)::numeric) AND (remaining_amount >= (0)::numeric))),
    CONSTRAINT loans_payment_method_check CHECK ((payment_method = ANY (ARRAY['cash'::text, 'bank'::text, 'salary_deduction'::text]))),
    CONSTRAINT loans_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text])))
);


--
-- Name: TABLE loans; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.loans IS 'طلبات القروض والسلف المالية للموظفين وصورة تعهد السلفة الإلزامية';


--
-- Name: COLUMN loans.notes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.loans.notes IS 'ملاحظات الإدارة أو سبب منح السلفة المباشرة';


--
-- Name: COLUMN loans.loan_no; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.loans.loan_no IS 'رقم مرجعي للسلفة يطلع للمستخدم (L-0007) ويبقى بسجل السلف المسددة';


--
-- Name: location_tracking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.location_tracking (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    battery_level integer,
    is_moving boolean,
    "timestamp" timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: TABLE location_tracking; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.location_tracking IS 'بيانات تتبع الموقع الجغرافي المستمر للموظفين الميدانيين أثناء العمل';


--
-- Name: mock_gps_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mock_gps_attempts (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    latitude double precision,
    longitude double precision,
    app_used text,
    "timestamp" timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: TABLE mock_gps_attempts; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.mock_gps_attempts IS 'سجل محاولات تزييف وتعديل الموقع الجغرافي باستخدام تطبيقات Mock GPS';


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    type text NOT NULL,
    is_read boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT notifications_type_check CHECK ((type = ANY (ARRAY['leave'::text, 'loan'::text, 'bonus_deduction'::text, 'attendance'::text, 'salary'::text, 'document'::text, 'device'::text, 'ota'::text, 'system'::text, 'memo'::text, 'assistant_summary'::text])))
);


--
-- Name: TABLE notifications; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.notifications IS 'سجل وتاريخ الإشعارات الواردة للموظفين والأدمن وتصنيفاتها';


--
-- Name: official_holidays; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.official_holidays (
    holiday_date date NOT NULL,
    name text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT official_holidays_name_check CHECK ((btrim(name) <> ''::text))
);


--
-- Name: TABLE official_holidays; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.official_holidays IS 'العطل الرسمية: لا يُحتسب فيها غياب ولا تُرسل تذكيرات بصمة.';


--
-- Name: payroll_cleanups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_cleanups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    period_month text,
    start_date date,
    end_date date,
    attendance_deleted integer,
    tracking_deleted integer,
    stops_deleted integer,
    violations_deleted integer,
    notifications_deleted integer,
    performed_by uuid,
    performed_at timestamp with time zone DEFAULT now() NOT NULL,
    loans_archived integer,
    loan_requests_deleted integer
);


--
-- Name: TABLE payroll_cleanups; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.payroll_cleanups IS 'سجل تنظيف البيانات القديمة: منو، متى، أي فترة، وكم سطر انحذف من كل فئة';


--
-- Name: payroll_loan_caps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_loan_caps (
    id bigint NOT NULL,
    employee_id uuid NOT NULL,
    payroll_month text NOT NULL,
    salary_slip_id uuid,
    loan_id uuid NOT NULL,
    installments_before jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: payroll_loan_caps_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payroll_loan_caps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payroll_loan_caps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payroll_loan_caps_id_seq OWNED BY public.payroll_loan_caps.id;


--
-- Name: salary_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salary_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    monthly_salary numeric NOT NULL,
    effective_month text NOT NULL,
    source text DEFAULT 'change'::text NOT NULL,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT salary_history_effective_month_check CHECK ((effective_month ~ '^\d{4}-\d{2}$'::text)),
    CONSTRAINT salary_history_monthly_salary_check CHECK ((monthly_salary >= (0)::numeric)),
    CONSTRAINT salary_history_source_check CHECK ((source = ANY (ARRAY['initial'::text, 'change'::text, 'scheduled'::text])))
);


--
-- Name: TABLE salary_history; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.salary_history IS 'راتب كل موظف من أي شهر رواتب يبدأ (الحساب يقرأ منه؛ monthly_salary_iqd = الراتب الحالي للعرض)';


--
-- Name: salary_slip_lines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salary_slip_lines (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    salary_slip_id uuid NOT NULL,
    event_id uuid,
    line_type text NOT NULL,
    event_date date,
    minutes numeric(10,2) DEFAULT 0 NOT NULL,
    days numeric(6,2) DEFAULT 0 NOT NULL,
    amount numeric(14,2) DEFAULT 0 NOT NULL,
    direction smallint NOT NULL,
    notes text,
    carried_from text
);


--
-- Name: salary_slips; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.salary_slips (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    work_month text NOT NULL,
    basic_salary numeric NOT NULL,
    allowances numeric DEFAULT 0 NOT NULL,
    deductions numeric DEFAULT 0 NOT NULL,
    loans_deduction numeric DEFAULT 0 NOT NULL,
    net_salary numeric NOT NULL,
    pdf_url text,
    status text DEFAULT 'draft'::text NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    computed_by_engine boolean DEFAULT false NOT NULL,
    CONSTRAINT salary_slips_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text])))
);


--
-- Name: TABLE salary_slips; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.salary_slips IS 'كشوف الرواتب الشهرية المفصلة للموظفين مصحوبة بملف PDF ومفصلة بالدينار العراقي';


--
-- Name: settled_loans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settled_loans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    loan_id uuid NOT NULL,
    loan_no bigint NOT NULL,
    employee_id uuid,
    employee_name text NOT NULL,
    employee_code text,
    amount numeric NOT NULL,
    total_deducted numeric NOT NULL,
    final_balance numeric DEFAULT 0 NOT NULL,
    installments jsonb NOT NULL,
    approved_at timestamp with time zone,
    settled_at timestamp with time zone NOT NULL,
    archived_by uuid,
    archived_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT settled_loans_final_balance_check CHECK ((final_balance = (0)::numeric))
);


--
-- Name: TABLE settled_loans; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.settled_loans IS 'سجل مالي دائم مختصر للسلف المسددة بعد حذف سجلها التشغيلي (للعرض والإثبات، ما يدخل بحساب الرواتب)';


--
-- Name: system_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_settings (
    key text NOT NULL,
    value jsonb NOT NULL,
    description text
);


--
-- Name: TABLE system_settings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.system_settings IS 'إعدادات النظام العامة مثل فترات أرشفة بيانات التتبع وغيرها';


--
-- Name: tracked_stops; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tracked_stops (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone,
    duration_minutes integer,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: TABLE tracked_stops; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.tracked_stops IS 'سجل الوقفات المكتشفة التي تتجاوز الـ 5 دقائق للموظف أثناء تتبعه';


--
-- Name: tracking_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tracking_schedules (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    employee_id uuid NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    tracking_days integer[] NOT NULL,
    interval_minutes integer DEFAULT 5 NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


--
-- Name: TABLE tracking_schedules; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.tracking_schedules IS 'مواعيد التتبع الجغرافي التلقائي المحددة للموظفين ميدانياً';


--
-- Name: v_attendance_with_employee; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_attendance_with_employee WITH (security_invoker='true') AS
 SELECT a.id,
    a.employee_id,
    e.full_name AS employee_name,
    e.employee_code,
    e.avatar_url,
    d.name AS department_name,
    b.name AS branch_name,
    a.branch_id,
    a.check_in_time,
    a.check_out_time,
    a.check_in_lat,
    a.check_in_lng,
    a.check_out_lat,
    a.check_out_lng,
    a.is_mock_detected,
    a.status,
    a.work_date,
    a.created_at
   FROM (((public.attendance a
     LEFT JOIN public.employees e ON ((e.id = a.employee_id)))
     LEFT JOIN public.departments d ON ((d.id = e.department_id)))
     LEFT JOIN public.branches b ON ((b.id = a.branch_id)));


--
-- Name: VIEW v_attendance_with_employee; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_attendance_with_employee IS 'كل سجل حضور مع اسم الموظف، القسم، والفرع. يقلل N+1 في شاشات تقارير الحضور.';


--
-- Name: v_device_requests; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_device_requests WITH (security_invoker='true') AS
 SELECT ed.id,
    ed.employee_id,
    e.full_name AS employee_name,
    e.employee_code,
    ed.device_id,
    ed.model,
    ed.os_version,
    ed.is_approved,
    ed.approved_at,
    ed.created_at,
    e.device_id_lock AS currently_locked_device
   FROM (public.employee_devices ed
     LEFT JOIN public.employees e ON ((e.id = ed.employee_id)))
  WHERE (ed.is_approved = false);


--
-- Name: VIEW v_device_requests; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_device_requests IS 'طلبات الأجهزة الجديدة المعلقة (is_approved=false) مع اسم الموظف. يستخدم في شاشة إدارة الأجهزة.';


--
-- Name: v_employee_directory; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_employee_directory WITH (security_invoker='true') AS
 SELECT e.id,
    e.employee_code,
    e.full_name,
    e.phone,
    e.email,
    e.avatar_url,
    e.document_urls,
    e.is_active,
    e.role,
    e.department_id,
    d.name AS department_name,
    e.branch_id,
    b.name AS branch_name
   FROM ((public.employees e
     LEFT JOIN public.departments d ON ((e.department_id = d.id)))
     LEFT JOIN public.branches b ON ((e.branch_id = b.id)))
  WHERE (e.is_active = true);


--
-- Name: VIEW v_employee_directory; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_employee_directory IS 'واجهة دليل الموظفين المحمية التي تستبعد البيانات الحساسة وتعرض الموظفين النشطين فقط';


--
-- Name: v_leaves_with_employee; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_leaves_with_employee WITH (security_invoker='true') AS
 SELECT lr.id,
    lr.employee_id,
    e.full_name AS employee_name,
    e.employee_code,
    d.name AS department_name,
    lr.start_date,
    lr.end_date,
    lr.leave_type,
    lr.is_hourly,
    lr.start_hour,
    lr.end_hour,
    lr.is_paid,
    lr.reason,
    lr.status,
    lr.attachment_url,
    lr.approved_by,
    lr.approved_at,
    lr.created_at
   FROM ((public.leave_requests lr
     LEFT JOIN public.employees e ON ((e.id = lr.employee_id)))
     LEFT JOIN public.departments d ON ((d.id = e.department_id)));


--
-- Name: v_loans_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_loans_summary WITH (security_invoker='true') AS
 SELECT l.id,
    l.employee_id,
    e.full_name AS employee_name,
    e.employee_code,
    l.amount,
    l.installment_count,
    l.installment_amount,
    l.pledge_url,
    l.status,
    l.approved_by,
    l.approved_at,
    l.rejection_reason,
    l.created_at,
    COALESCE(paid.paid_count, (0)::bigint) AS paid_installments,
    COALESCE(paid.paid_amount, (0)::numeric) AS total_paid_amount,
    (l.amount - COALESCE(paid.paid_amount, (0)::numeric)) AS remaining_amount
   FROM ((public.loans l
     LEFT JOIN public.employees e ON ((e.id = l.employee_id)))
     LEFT JOIN LATERAL ( SELECT count(*) FILTER (WHERE loan_installments.is_paid) AS paid_count,
            COALESCE(sum(loan_installments.amount) FILTER (WHERE loan_installments.is_paid), (0)::numeric) AS paid_amount
           FROM public.loan_installments
          WHERE (loan_installments.loan_id = l.id)) paid ON (true));


--
-- Name: VIEW v_loans_summary; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_loans_summary IS 'السلف مع اسم الموظف وعدد ومبلغ الأقساط المدفوعة والمتبقي المحسوب. تجنّب N+1 في شاشة إدارة السلف.';


--
-- Name: v_payroll_with_employee; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_payroll_with_employee WITH (security_invoker='true') AS
 SELECT s.id,
    s.employee_id,
    e.full_name AS employee_name,
    e.employee_code,
    d.name AS department_name,
    b.name AS branch_name,
    s.work_month,
    s.basic_salary,
    s.allowances,
    s.deductions,
    s.loans_deduction,
    s.net_salary,
    s.pdf_url,
    s.status,
    s.created_at
   FROM (((public.salary_slips s
     LEFT JOIN public.employees e ON ((e.id = s.employee_id)))
     LEFT JOIN public.departments d ON ((d.id = e.department_id)))
     LEFT JOIN public.branches b ON ((b.id = e.branch_id)));


--
-- Name: VIEW v_payroll_with_employee; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_payroll_with_employee IS 'كشوف الرواتب الشهرية مع بيانات الموظف الكاملة. يستخدم في شاشة payroll وتصدير Excel/PDF.';


--
-- Name: v_security_incidents; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_security_incidents WITH (security_invoker='true') AS
 SELECT 'mock_gps'::text AS incident_type,
    m.id,
    m.employee_id,
    e.full_name AS employee_name,
    m.latitude,
    m.longitude,
    m.app_used AS details,
    m."timestamp" AS occurred_at
   FROM (public.mock_gps_attempts m
     LEFT JOIN public.employees e ON ((e.id = m.employee_id)))
UNION ALL
 SELECT 'geofence_violation'::text AS incident_type,
    v.id,
    v.employee_id,
    e.full_name AS employee_name,
    NULL::double precision AS latitude,
    NULL::double precision AS longitude,
    v.violation_type AS details,
    v."timestamp" AS occurred_at
   FROM (public.geofence_violations v
     LEFT JOIN public.employees e ON ((e.id = v.employee_id)))
  ORDER BY 8 DESC;


--
-- Name: VIEW v_security_incidents; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.v_security_incidents IS 'الحوادث الأمنية الموحدة: محاولات تزييف GPS ومخالفات السياج الجغرافي في تدفق واحد مرتب زمنياً.';


--
-- Name: work_schedule_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_schedule_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    schedule_id uuid NOT NULL,
    employee_id uuid,
    department_id uuid,
    branch_id uuid,
    check_in_time time without time zone,
    check_out_time time without time zone,
    grace_period_minutes integer,
    work_days integer[],
    schedule_created_at timestamp with time zone,
    effective_from date NOT NULL,
    removed boolean DEFAULT false NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    recorded_by uuid DEFAULT auth.uid()
);


--
-- Name: employee_assignment_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_assignment_history ALTER COLUMN id SET DEFAULT nextval('public.employee_assignment_history_id_seq'::regclass);


--
-- Name: employee_service_breaks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_service_breaks ALTER COLUMN id SET DEFAULT nextval('public.employee_service_breaks_id_seq'::regclass);


--
-- Name: payroll_loan_caps id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_loan_caps ALTER COLUMN id SET DEFAULT nextval('public.payroll_loan_caps_id_seq'::regclass);


--
-- Data for Name: announcements; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: app_versions; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: archived_employees; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: archived_months; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: assistant_conversations; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: assistant_messages; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: attendance; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: attendance_reminder_log; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: bonuses_deductions; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: branches; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: cleanup_run_tokens; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: company_settings; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: deleted_files; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: departments; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: device_tokens; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: employee_assignment_history; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: employee_devices; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: employee_geofence_assignments; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: employee_service_breaks; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: fcm_tokens; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: geofence_violations; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: geofence_zones; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: leave_balances; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: leave_requests; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: loan_installments; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: loans; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: location_tracking; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: mock_gps_attempts; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: official_holidays; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: payroll_cleanups; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: payroll_events; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: payroll_loan_caps; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: payroll_periods; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.payroll_periods VALUES ('2026-09', '2026-09-01', '2026-09-26', '2026-09-30', 'open', NULL, NULL, NULL, NULL, NULL, now(), NULL, NULL, NULL, NULL);


--
-- Data for Name: salary_history; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: salary_slip_lines; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: salary_slips; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: settled_loans; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: system_settings; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.system_settings VALUES ('leave_policy', '{"active_types": [{"id": "annual", "name": "إجازة سنوية"}, {"id": "sick", "name": "إجازة مرضية"}, {"id": "emergency", "name": "إجازة طارئة"}, {"id": "maternity", "name": "إجازة أمومة"}, {"id": "other", "name": "إجازة أخرى"}], "default_sick": 15, "default_annual": 21, "hourly_monthly_hours": 8}', 'سياسة الإجازات العامة وأنواعها المتاحة بالشركة');
INSERT INTO public.system_settings VALUES ('payroll_policy', '{"cutoff_day": 26, "payment_day": 30, "cycle_end_day": 26, "cycle_start_day": 27, "overtime_enabled": false, "overtime_multiplier": 1, "overtime_min_minutes": 30}', 'إعدادات دورة الرواتب');
INSERT INTO public.system_settings VALUES ('assistant_policy', '{"morning_summary": true}', 'المساعد الذكي: الملخص الصباحي للأدمن (10:00)');
INSERT INTO public.system_settings VALUES ('archive_policy', '{"tracking_archive_days": 45}', 'مدة الاحتفاظ ببيانات التتبع (GPS) بالأيام');


--
-- Data for Name: tracked_stops; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: tracking_schedules; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: work_schedule_history; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Data for Name: work_schedules; Type: TABLE DATA; Schema: public; Owner: -
--



--
-- Name: assistant_messages_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.assistant_messages_id_seq', 1, false);


--
-- Name: employee_assignment_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.employee_assignment_history_id_seq', 1, false);


--
-- Name: employee_code_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.employee_code_seq', 1, false);


--
-- Name: employee_service_breaks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.employee_service_breaks_id_seq', 1, false);


--
-- Name: loan_no_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.loan_no_seq', 1, false);


--
-- Name: payroll_loan_caps_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payroll_loan_caps_id_seq', 1, false);


--
-- Name: announcements announcements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_pkey PRIMARY KEY (id);


--
-- Name: app_versions app_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_versions
    ADD CONSTRAINT app_versions_pkey PRIMARY KEY (id);


--
-- Name: archived_employees archived_employees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archived_employees
    ADD CONSTRAINT archived_employees_pkey PRIMARY KEY (id);


--
-- Name: archived_months archived_months_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archived_months
    ADD CONSTRAINT archived_months_pkey PRIMARY KEY (id);


--
-- Name: archived_months archived_months_work_month_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archived_months
    ADD CONSTRAINT archived_months_work_month_key UNIQUE (work_month);


--
-- Name: assistant_conversations assistant_conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_conversations
    ADD CONSTRAINT assistant_conversations_pkey PRIMARY KEY (id);


--
-- Name: assistant_messages assistant_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_messages
    ADD CONSTRAINT assistant_messages_pkey PRIMARY KEY (id);


--
-- Name: attendance attendance_employee_id_work_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_employee_id_work_date_key UNIQUE (employee_id, work_date);


--
-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_pkey PRIMARY KEY (id);


--
-- Name: attendance_reminder_log attendance_reminder_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_reminder_log
    ADD CONSTRAINT attendance_reminder_log_pkey PRIMARY KEY (employee_id, work_date, kind);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: bonuses_deductions bonuses_deductions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bonuses_deductions
    ADD CONSTRAINT bonuses_deductions_pkey PRIMARY KEY (id);


--
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (id);


--
-- Name: cleanup_run_tokens cleanup_run_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cleanup_run_tokens
    ADD CONSTRAINT cleanup_run_tokens_pkey PRIMARY KEY (token);


--
-- Name: company_settings company_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_settings
    ADD CONSTRAINT company_settings_pkey PRIMARY KEY (id);


--
-- Name: deleted_files deleted_files_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deleted_files
    ADD CONSTRAINT deleted_files_pkey PRIMARY KEY (id);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (id);


--
-- Name: device_tokens device_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT device_tokens_pkey PRIMARY KEY (employee_id, token);


--
-- Name: employee_assignment_history employee_assignment_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_assignment_history
    ADD CONSTRAINT employee_assignment_history_pkey PRIMARY KEY (id);


--
-- Name: employee_devices employee_devices_employee_id_device_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_devices
    ADD CONSTRAINT employee_devices_employee_id_device_id_key UNIQUE (employee_id, device_id);


--
-- Name: employee_devices employee_devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_devices
    ADD CONSTRAINT employee_devices_pkey PRIMARY KEY (id);


--
-- Name: employee_geofence_assignments employee_geofence_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_geofence_assignments
    ADD CONSTRAINT employee_geofence_assignments_pkey PRIMARY KEY (employee_id, zone_id);


--
-- Name: employee_service_breaks employee_service_breaks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_service_breaks
    ADD CONSTRAINT employee_service_breaks_pkey PRIMARY KEY (id);


--
-- Name: employees employees_employee_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_employee_code_key UNIQUE (employee_code);


--
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- Name: fcm_tokens fcm_tokens_employee_id_token_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fcm_tokens
    ADD CONSTRAINT fcm_tokens_employee_id_token_key UNIQUE (employee_id, token);


--
-- Name: fcm_tokens fcm_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fcm_tokens
    ADD CONSTRAINT fcm_tokens_pkey PRIMARY KEY (id);


--
-- Name: geofence_violations geofence_violations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geofence_violations
    ADD CONSTRAINT geofence_violations_pkey PRIMARY KEY (id);


--
-- Name: geofence_zones geofence_zones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geofence_zones
    ADD CONSTRAINT geofence_zones_pkey PRIMARY KEY (id);


--
-- Name: leave_balances leave_balances_employee_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT leave_balances_employee_id_key UNIQUE (employee_id);


--
-- Name: leave_balances leave_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT leave_balances_pkey PRIMARY KEY (id);


--
-- Name: leave_requests leave_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_pkey PRIMARY KEY (id);


--
-- Name: loan_installments loan_installments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_installments
    ADD CONSTRAINT loan_installments_pkey PRIMARY KEY (id);


--
-- Name: loans loans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_pkey PRIMARY KEY (id);


--
-- Name: location_tracking location_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location_tracking
    ADD CONSTRAINT location_tracking_pkey PRIMARY KEY (id);


--
-- Name: mock_gps_attempts mock_gps_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mock_gps_attempts
    ADD CONSTRAINT mock_gps_attempts_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: official_holidays official_holidays_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.official_holidays
    ADD CONSTRAINT official_holidays_pkey PRIMARY KEY (holiday_date);


--
-- Name: payroll_cleanups payroll_cleanups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_cleanups
    ADD CONSTRAINT payroll_cleanups_pkey PRIMARY KEY (id);


--
-- Name: payroll_events payroll_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_events
    ADD CONSTRAINT payroll_events_pkey PRIMARY KEY (id);


--
-- Name: payroll_loan_caps payroll_loan_caps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_loan_caps
    ADD CONSTRAINT payroll_loan_caps_pkey PRIMARY KEY (id);


--
-- Name: payroll_periods payroll_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_pkey PRIMARY KEY (period_month);


--
-- Name: salary_history salary_history_employee_id_effective_month_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_history
    ADD CONSTRAINT salary_history_employee_id_effective_month_key UNIQUE (employee_id, effective_month);


--
-- Name: salary_history salary_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_history
    ADD CONSTRAINT salary_history_pkey PRIMARY KEY (id);


--
-- Name: salary_slip_lines salary_slip_lines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_slip_lines
    ADD CONSTRAINT salary_slip_lines_pkey PRIMARY KEY (id);


--
-- Name: salary_slips salary_slips_employee_id_work_month_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_slips
    ADD CONSTRAINT salary_slips_employee_id_work_month_key UNIQUE (employee_id, work_month);


--
-- Name: salary_slips salary_slips_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_slips
    ADD CONSTRAINT salary_slips_pkey PRIMARY KEY (id);


--
-- Name: settled_loans settled_loans_loan_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settled_loans
    ADD CONSTRAINT settled_loans_loan_id_key UNIQUE (loan_id);


--
-- Name: settled_loans settled_loans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settled_loans
    ADD CONSTRAINT settled_loans_pkey PRIMARY KEY (id);


--
-- Name: system_settings system_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_pkey PRIMARY KEY (key);


--
-- Name: tracked_stops tracked_stops_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracked_stops
    ADD CONSTRAINT tracked_stops_pkey PRIMARY KEY (id);


--
-- Name: tracking_schedules tracking_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracking_schedules
    ADD CONSTRAINT tracking_schedules_pkey PRIMARY KEY (id);


--
-- Name: work_schedule_history work_schedule_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedule_history
    ADD CONSTRAINT work_schedule_history_pkey PRIMARY KEY (id);


--
-- Name: work_schedules work_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_pkey PRIMARY KEY (id);


--
-- Name: assistant_conversations_owner_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assistant_conversations_owner_idx ON public.assistant_conversations USING btree (owner_id, updated_at DESC);


--
-- Name: assistant_messages_conversation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assistant_messages_conversation_idx ON public.assistant_messages USING btree (conversation_id, id);


--
-- Name: idx_announcements_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_announcements_period ON public.announcements USING btree (starts_at, ends_at);


--
-- Name: idx_archived_employees_deletion_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_archived_employees_deletion_date ON public.archived_employees USING btree (scheduled_deletion_date);


--
-- Name: idx_audit_log_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_actor ON public.audit_log USING btree (actor_id, created_at DESC);


--
-- Name: idx_audit_log_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_created_at ON public.audit_log USING btree (created_at DESC);


--
-- Name: idx_audit_log_table_row; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_table_row ON public.audit_log USING btree (table_name, row_id, created_at DESC);


--
-- Name: idx_bonuses_deductions_salary_slip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bonuses_deductions_salary_slip ON public.bonuses_deductions USING btree (salary_slip_id);


--
-- Name: idx_deleted_files_deletion_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deleted_files_deletion_date ON public.deleted_files USING btree (scheduled_deletion_date);


--
-- Name: idx_employee_assignment_history_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_assignment_history_lookup ON public.employee_assignment_history USING btree (employee_id, effective_from DESC, recorded_at DESC, id DESC);


--
-- Name: idx_employee_service_breaks_emp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_service_breaks_emp ON public.employee_service_breaks USING btree (employee_id, last_day);


--
-- Name: idx_employees_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_branch ON public.employees USING btree (branch_id);


--
-- Name: idx_employees_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employees_department ON public.employees USING btree (department_id);


--
-- Name: idx_fcm_tokens_employee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_fcm_tokens_employee_id ON public.fcm_tokens USING btree (employee_id);


--
-- Name: idx_leave_requests_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_dates ON public.leave_requests USING btree (start_date, end_date);


--
-- Name: idx_leave_requests_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_requests_employee ON public.leave_requests USING btree (employee_id);


--
-- Name: idx_loan_installments_loan; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_loan_installments_loan ON public.loan_installments USING btree (loan_id, due_date);


--
-- Name: idx_loan_installments_paid_by_slip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_loan_installments_paid_by_slip ON public.loan_installments USING btree (paid_by_slip_id);


--
-- Name: idx_loans_employee; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_loans_employee ON public.loans USING btree (employee_id);


--
-- Name: idx_location_tracking_employee_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_location_tracking_employee_time ON public.location_tracking USING btree (employee_id, "timestamp");


--
-- Name: idx_notifications_employee_read; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_employee_read ON public.notifications USING btree (employee_id, is_read);


--
-- Name: idx_payroll_events_day; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_events_day ON public.payroll_events USING btree (employee_id, event_date);


--
-- Name: idx_payroll_events_month; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_events_month ON public.payroll_events USING btree (payroll_month, employee_id);


--
-- Name: idx_payroll_events_slip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_events_slip ON public.payroll_events USING btree (salary_slip_id);


--
-- Name: idx_payroll_loan_caps_slip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_loan_caps_slip ON public.payroll_loan_caps USING btree (salary_slip_id);


--
-- Name: idx_salary_slip_lines_slip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_salary_slip_lines_slip ON public.salary_slip_lines USING btree (salary_slip_id);


--
-- Name: idx_tracked_stops_employee_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tracked_stops_employee_time ON public.tracked_stops USING btree (employee_id, start_time);


--
-- Name: idx_work_schedule_history_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_schedule_history_lookup ON public.work_schedule_history USING btree (schedule_id, effective_from DESC, recorded_at DESC);


--
-- Name: idx_work_schedules_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_schedules_branch_id ON public.work_schedules USING btree (branch_id);


--
-- Name: loans_loan_no_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX loans_loan_no_key ON public.loans USING btree (loan_no);


--
-- Name: payroll_cleanups_range_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_cleanups_range_idx ON public.payroll_cleanups USING btree (start_date, end_date) WHERE (attendance_deleted IS NOT NULL);


--
-- Name: settled_loans_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX settled_loans_employee_idx ON public.settled_loans USING btree (employee_id);


--
-- Name: uq_payroll_events_engine_day; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_payroll_events_engine_day ON public.payroll_events USING btree (employee_id, event_date, event_type, source, COALESCE(source_id, '00000000-0000-0000-0000-000000000000'::uuid)) WHERE ((status <> 'void'::text) AND (source = ANY (ARRAY['attendance'::text, 'no_record'::text, 'leave'::text])));


--
-- Name: uq_payroll_events_manual; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_payroll_events_manual ON public.payroll_events USING btree (source_id) WHERE ((status <> 'void'::text) AND (source = 'manual'::text));


--
-- Name: uq_payroll_events_open_adjustment; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_payroll_events_open_adjustment ON public.payroll_events USING btree (adjusts_event_id) WHERE ((status <> 'void'::text) AND (source = 'carry_over'::text) AND (salary_slip_id IS NULL));


--
-- Name: notifications on_notification_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER on_notification_insert AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.invoke_push_notification();


--
-- Name: employees trg_assign_employee_code; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_assign_employee_code BEFORE INSERT ON public.employees FOR EACH ROW EXECUTE FUNCTION public.assign_employee_code();


--
-- Name: loans trg_assign_loan_no; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_assign_loan_no BEFORE INSERT ON public.loans FOR EACH ROW EXECUTE FUNCTION public.assign_loan_no();


--
-- Name: bonuses_deductions trg_audit_bonuses; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_bonuses AFTER INSERT OR DELETE OR UPDATE ON public.bonuses_deductions FOR EACH ROW EXECUTE FUNCTION public.record_audit_log();


--
-- Name: employees trg_audit_employees; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_employees AFTER INSERT OR DELETE OR UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.record_audit_log();


--
-- Name: leave_requests trg_audit_leave_requests; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_leave_requests AFTER DELETE OR UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.record_audit_log();


--
-- Name: loans trg_audit_loans; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_loans AFTER INSERT OR DELETE OR UPDATE ON public.loans FOR EACH ROW EXECUTE FUNCTION public.record_audit_log();


--
-- Name: salary_slips trg_audit_salary_slips; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_salary_slips AFTER INSERT OR DELETE OR UPDATE ON public.salary_slips FOR EACH ROW EXECUTE FUNCTION public.record_audit_log();


--
-- Name: system_settings trg_check_archive_policy; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_check_archive_policy BEFORE INSERT OR UPDATE OF value ON public.system_settings FOR EACH ROW EXECUTE FUNCTION public.check_archive_policy();


--
-- Name: bonuses_deductions trg_check_bonus_deduction_amount; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_check_bonus_deduction_amount BEFORE INSERT OR UPDATE OF amount, type, employee_id ON public.bonuses_deductions FOR EACH ROW EXECUTE FUNCTION public.check_bonus_deduction_amount();


--
-- Name: employees trg_check_employee_basics; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_check_employee_basics BEFORE INSERT OR UPDATE OF full_name, join_date, termination_date ON public.employees FOR EACH ROW EXECUTE FUNCTION public.check_employee_basics();


--
-- Name: employees trg_check_employee_branch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_check_employee_branch BEFORE INSERT OR UPDATE OF branch_id, is_active ON public.employees FOR EACH ROW EXECUTE FUNCTION public.check_employee_branch();


--
-- Name: payroll_periods trg_clear_delivered_on_reopen; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_clear_delivered_on_reopen BEFORE UPDATE ON public.payroll_periods FOR EACH ROW EXECUTE FUNCTION public.clear_delivered_on_reopen();


--
-- Name: device_tokens trg_copy_legacy_push_token; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_copy_legacy_push_token AFTER INSERT OR UPDATE ON public.device_tokens FOR EACH ROW EXECUTE FUNCTION public.copy_legacy_push_token();


--
-- Name: employees trg_copy_legacy_push_token; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_copy_legacy_push_token AFTER UPDATE OF fcm_token ON public.employees FOR EACH ROW WHEN (((new.fcm_token IS NOT NULL) AND (new.fcm_token IS DISTINCT FROM old.fcm_token))) EXECUTE FUNCTION public.copy_legacy_push_token();


--
-- Name: employees trg_create_default_leave_balance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_create_default_leave_balance AFTER INSERT ON public.employees FOR EACH ROW EXECUTE FUNCTION public.create_default_leave_balance();


--
-- Name: bonuses_deductions trg_guard_bonus_deduction_entry; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_guard_bonus_deduction_entry BEFORE INSERT ON public.bonuses_deductions FOR EACH ROW EXECUTE FUNCTION public.guard_bonus_deduction_entry();


--
-- Name: loans trg_guard_loan_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_guard_loan_delete BEFORE DELETE ON public.loans FOR EACH ROW EXECUTE FUNCTION public.guard_loan_delete();


--
-- Name: loans trg_guard_loan_status; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_guard_loan_status BEFORE UPDATE OF status ON public.loans FOR EACH ROW EXECUTE FUNCTION public.guard_loan_status();


--
-- Name: loan_installments trg_guard_paid_installment_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_guard_paid_installment_delete BEFORE DELETE ON public.loan_installments FOR EACH ROW EXECUTE FUNCTION public.guard_paid_installment_delete();


--
-- Name: loan_installments trg_guard_slip_paid_installment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_guard_slip_paid_installment BEFORE UPDATE OF is_paid, amount ON public.loan_installments FOR EACH ROW EXECUTE FUNCTION public.guard_slip_paid_installment();


--
-- Name: salary_slips trg_guard_slip_with_archived_loan; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_guard_slip_with_archived_loan BEFORE DELETE ON public.salary_slips FOR EACH ROW EXECUTE FUNCTION public.guard_slip_with_archived_loan();


--
-- Name: loans trg_keep_loan_no; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_keep_loan_no BEFORE UPDATE OF loan_no ON public.loans FOR EACH ROW EXECUTE FUNCTION public.keep_loan_no();


--
-- Name: system_settings trg_keep_payroll_policy_keys; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_keep_payroll_policy_keys BEFORE INSERT OR UPDATE ON public.system_settings FOR EACH ROW EXECUTE FUNCTION public.keep_payroll_policy_keys();


--
-- Name: attendance trg_keep_status_on_early_checkout; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_keep_status_on_early_checkout BEFORE UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.keep_status_on_early_checkout();


--
-- Name: leave_requests trg_notify_admins_new_leave_request; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_admins_new_leave_request AFTER INSERT ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.notify_admins_of_new_leave_request();


--
-- Name: loans trg_notify_admins_new_loan_request; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_admins_new_loan_request AFTER INSERT ON public.loans FOR EACH ROW EXECUTE FUNCTION public.notify_admins_of_new_loan_request();


--
-- Name: leave_requests trg_notify_employee_leave_decision; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_employee_leave_decision AFTER UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.notify_employee_on_leave_decision();


--
-- Name: loans trg_notify_employee_loan_decision; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_employee_loan_decision AFTER UPDATE ON public.loans FOR EACH ROW EXECUTE FUNCTION public.notify_employee_on_loan_decision();


--
-- Name: loans trg_one_pending_loan_request; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_one_pending_loan_request BEFORE INSERT ON public.loans FOR EACH ROW EXECUTE FUNCTION public.one_pending_loan_request();


--
-- Name: attendance trg_payroll_attendance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_attendance AFTER INSERT OR DELETE OR UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.trg_payroll_attendance();


--
-- Name: official_holidays trg_payroll_holiday; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_holiday AFTER INSERT OR DELETE ON public.official_holidays FOR EACH ROW EXECUTE FUNCTION public.trg_payroll_holiday();


--
-- Name: leave_requests trg_payroll_leave; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_leave AFTER INSERT OR DELETE OR UPDATE OF status, start_date, end_date, is_paid, is_hourly, start_hour, end_hour ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.trg_payroll_leave();


--
-- Name: bonuses_deductions trg_payroll_manual; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_manual AFTER INSERT OR DELETE OR UPDATE ON public.bonuses_deductions FOR EACH ROW EXECUTE FUNCTION public.trg_payroll_manual();


--
-- Name: attendance trg_protect_attendance_decisions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_protect_attendance_decisions BEFORE INSERT OR UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.protect_attendance_decisions();


--
-- Name: attendance trg_protect_attendance_times; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_protect_attendance_times BEFORE UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.protect_attendance_times();


--
-- Name: employees trg_protect_employee_columns; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_protect_employee_columns BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.protect_employee_columns();


--
-- Name: leave_requests trg_protect_leave_decisions; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_protect_leave_decisions BEFORE INSERT OR UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.protect_leave_decisions();


--
-- Name: employees trg_record_employee_assignment; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_record_employee_assignment AFTER INSERT OR UPDATE OF branch_id, department_id ON public.employees FOR EACH ROW EXECUTE FUNCTION public.record_employee_assignment();


--
-- Name: employees trg_record_salary_history; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_record_salary_history AFTER INSERT OR UPDATE OF monthly_salary_iqd, future_salary_iqd, future_salary_month ON public.employees FOR EACH ROW EXECUTE FUNCTION public.record_salary_history();


--
-- Name: attendance trg_reject_future_attendance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_reject_future_attendance BEFORE INSERT OR UPDATE OF work_date, check_in_time, check_out_time ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.reject_future_attendance();


--
-- Name: salary_slips trg_reject_negative_salary_slip; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_reject_negative_salary_slip BEFORE INSERT OR UPDATE OF net_salary ON public.salary_slips FOR EACH ROW EXECUTE FUNCTION public.reject_negative_salary_slip();


--
-- Name: employees trg_resync_payroll_on_salary_change; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_resync_payroll_on_salary_change AFTER UPDATE OF monthly_salary_iqd, future_salary_iqd, future_salary_month ON public.employees FOR EACH ROW EXECUTE FUNCTION public.resync_payroll_on_salary_change();


--
-- Name: employees trg_set_termination_date; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_set_termination_date BEFORE UPDATE OF is_active ON public.employees FOR EACH ROW EXECUTE FUNCTION public.set_termination_date();


--
-- Name: geofence_zones trg_sync_geofence_coordinates; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_geofence_coordinates BEFORE INSERT OR UPDATE OF polygon_coordinates, coordinates ON public.geofence_zones FOR EACH ROW EXECUTE FUNCTION public.sync_geofence_coordinates();


--
-- Name: geofence_zones trg_sync_geofences_to_branches; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sync_geofences_to_branches AFTER INSERT OR DELETE OR UPDATE ON public.geofence_zones FOR EACH ROW EXECUTE FUNCTION public.sync_geofences_to_branches();


--
-- Name: attendance trg_track_attendance_time_source; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_track_attendance_time_source BEFORE INSERT OR UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.track_attendance_time_source();


--
-- Name: employees trg_trash_removed_employee_files; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_trash_removed_employee_files AFTER UPDATE OF document_urls, avatar_url ON public.employees FOR EACH ROW EXECUTE FUNCTION public.trash_removed_employee_files();


--
-- Name: loan_installments trg_update_loan_and_installments; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_loan_and_installments AFTER DELETE OR UPDATE OF is_paid, amount ON public.loan_installments FOR EACH ROW EXECUTE FUNCTION public.update_loan_and_installments_trigger();


--
-- Name: leave_requests trg_validate_leave_request; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validate_leave_request BEFORE INSERT OR UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.validate_leave_request();


--
-- Name: work_schedules trg_work_schedule_history; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_work_schedule_history AFTER INSERT OR DELETE OR UPDATE ON public.work_schedules FOR EACH ROW EXECUTE FUNCTION public.record_work_schedule_history();


--
-- Name: announcements announcements_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: announcements announcements_target_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_target_branch_id_fkey FOREIGN KEY (target_branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;


--
-- Name: announcements announcements_target_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_target_department_id_fkey FOREIGN KEY (target_department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: archived_employees archived_employees_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archived_employees
    ADD CONSTRAINT archived_employees_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: archived_months archived_months_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.archived_months
    ADD CONSTRAINT archived_months_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: assistant_conversations assistant_conversations_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_conversations
    ADD CONSTRAINT assistant_conversations_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: assistant_messages assistant_messages_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_messages
    ADD CONSTRAINT assistant_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.assistant_conversations(id) ON DELETE CASCADE;


--
-- Name: attendance attendance_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: attendance attendance_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: attendance_reminder_log attendance_reminder_log_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_reminder_log
    ADD CONSTRAINT attendance_reminder_log_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: audit_log audit_log_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: bonuses_deductions bonuses_deductions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bonuses_deductions
    ADD CONSTRAINT bonuses_deductions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: bonuses_deductions bonuses_deductions_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bonuses_deductions
    ADD CONSTRAINT bonuses_deductions_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: bonuses_deductions bonuses_deductions_salary_slip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bonuses_deductions
    ADD CONSTRAINT bonuses_deductions_salary_slip_id_fkey FOREIGN KEY (salary_slip_id) REFERENCES public.salary_slips(id) ON DELETE CASCADE;


--
-- Name: deleted_files deleted_files_deleted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deleted_files
    ADD CONSTRAINT deleted_files_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: device_tokens device_tokens_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT device_tokens_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: employee_assignment_history employee_assignment_history_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_assignment_history
    ADD CONSTRAINT employee_assignment_history_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: employee_devices employee_devices_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_devices
    ADD CONSTRAINT employee_devices_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: employee_geofence_assignments employee_geofence_assignments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_geofence_assignments
    ADD CONSTRAINT employee_geofence_assignments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: employee_geofence_assignments employee_geofence_assignments_zone_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_geofence_assignments
    ADD CONSTRAINT employee_geofence_assignments_zone_id_fkey FOREIGN KEY (zone_id) REFERENCES public.geofence_zones(id) ON DELETE CASCADE;


--
-- Name: employee_service_breaks employee_service_breaks_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_service_breaks
    ADD CONSTRAINT employee_service_breaks_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: employees employees_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE SET NULL;


--
-- Name: employees employees_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE SET NULL;


--
-- Name: fcm_tokens fcm_tokens_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fcm_tokens
    ADD CONSTRAINT fcm_tokens_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: departments fk_departments_manager; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT fk_departments_manager FOREIGN KEY (manager_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: geofence_violations geofence_violations_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geofence_violations
    ADD CONSTRAINT geofence_violations_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: geofence_violations geofence_violations_zone_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geofence_violations
    ADD CONSTRAINT geofence_violations_zone_id_fkey FOREIGN KEY (zone_id) REFERENCES public.geofence_zones(id) ON DELETE CASCADE;


--
-- Name: leave_balances leave_balances_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_balances
    ADD CONSTRAINT leave_balances_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: leave_requests leave_requests_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: leave_requests leave_requests_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: loan_installments loan_installments_loan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_installments
    ADD CONSTRAINT loan_installments_loan_id_fkey FOREIGN KEY (loan_id) REFERENCES public.loans(id) ON DELETE CASCADE;


--
-- Name: loan_installments loan_installments_paid_by_slip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loan_installments
    ADD CONSTRAINT loan_installments_paid_by_slip_id_fkey FOREIGN KEY (paid_by_slip_id) REFERENCES public.salary_slips(id) ON DELETE SET NULL;


--
-- Name: loans loans_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: loans loans_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: location_tracking location_tracking_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location_tracking
    ADD CONSTRAINT location_tracking_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: mock_gps_attempts mock_gps_attempts_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mock_gps_attempts
    ADD CONSTRAINT mock_gps_attempts_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: official_holidays official_holidays_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.official_holidays
    ADD CONSTRAINT official_holidays_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: payroll_cleanups payroll_cleanups_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_cleanups
    ADD CONSTRAINT payroll_cleanups_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: payroll_events payroll_events_adjusts_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_events
    ADD CONSTRAINT payroll_events_adjusts_event_id_fkey FOREIGN KEY (adjusts_event_id) REFERENCES public.payroll_events(id) ON DELETE SET NULL;


--
-- Name: payroll_events payroll_events_decided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_events
    ADD CONSTRAINT payroll_events_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: payroll_events payroll_events_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_events
    ADD CONSTRAINT payroll_events_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: payroll_events payroll_events_payroll_month_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_events
    ADD CONSTRAINT payroll_events_payroll_month_fkey FOREIGN KEY (payroll_month) REFERENCES public.payroll_periods(period_month);


--
-- Name: payroll_events payroll_events_salary_slip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_events
    ADD CONSTRAINT payroll_events_salary_slip_id_fkey FOREIGN KEY (salary_slip_id) REFERENCES public.salary_slips(id) ON DELETE SET NULL;


--
-- Name: payroll_loan_caps payroll_loan_caps_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_loan_caps
    ADD CONSTRAINT payroll_loan_caps_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: payroll_periods payroll_periods_calculated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_calculated_by_fkey FOREIGN KEY (calculated_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: payroll_periods payroll_periods_closed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: payroll_periods payroll_periods_delivered_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_delivered_by_fkey FOREIGN KEY (delivered_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: payroll_periods payroll_periods_reopened_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_reopened_by_fkey FOREIGN KEY (reopened_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: salary_history salary_history_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_history
    ADD CONSTRAINT salary_history_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: salary_history salary_history_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_history
    ADD CONSTRAINT salary_history_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: salary_slip_lines salary_slip_lines_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_slip_lines
    ADD CONSTRAINT salary_slip_lines_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.payroll_events(id) ON DELETE SET NULL;


--
-- Name: salary_slip_lines salary_slip_lines_salary_slip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_slip_lines
    ADD CONSTRAINT salary_slip_lines_salary_slip_id_fkey FOREIGN KEY (salary_slip_id) REFERENCES public.salary_slips(id) ON DELETE CASCADE;


--
-- Name: salary_slips salary_slips_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.salary_slips
    ADD CONSTRAINT salary_slips_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: settled_loans settled_loans_archived_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settled_loans
    ADD CONSTRAINT settled_loans_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: settled_loans settled_loans_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settled_loans
    ADD CONSTRAINT settled_loans_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;


--
-- Name: tracked_stops tracked_stops_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracked_stops
    ADD CONSTRAINT tracked_stops_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: tracking_schedules tracking_schedules_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tracking_schedules
    ADD CONSTRAINT tracking_schedules_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: work_schedules work_schedules_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.branches(id) ON DELETE CASCADE;


--
-- Name: work_schedules work_schedules_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id) ON DELETE CASCADE;


--
-- Name: work_schedules work_schedules_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- Name: leave_requests Admins and branch managers decide leave requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins and branch managers decide leave requests" ON public.leave_requests FOR UPDATE TO authenticated USING ((( SELECT public.is_admin() AS is_admin) OR ((employee_id <> auth.uid()) AND (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[]))))) WITH CHECK ((( SELECT public.is_admin() AS is_admin) OR ((employee_id <> auth.uid()) AND (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[])))));


--
-- Name: attendance Admins and branch managers update attendance; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins and branch managers update attendance" ON public.attendance FOR UPDATE TO authenticated USING ((( SELECT public.is_admin() AS is_admin) OR ((employee_id <> auth.uid()) AND (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[]))))) WITH CHECK ((( SELECT public.is_admin() AS is_admin) OR ((employee_id <> auth.uid()) AND (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[])))));


--
-- Name: employee_devices Admins can manage all devices; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can manage all devices" ON public.employee_devices TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: loan_installments Admins can manage installments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can manage installments" ON public.loan_installments TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: leave_balances Admins can manage leave balances; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can manage leave balances" ON public.leave_balances TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: salary_slips Admins can manage salary slips; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can manage salary slips" ON public.salary_slips TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: system_settings Admins can manage system settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can manage system settings" ON public.system_settings TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: archived_employees Admins can view and manage archived employees; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view and manage archived employees" ON public.archived_employees TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: deleted_files Admins can view and manage deleted files; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view and manage deleted files" ON public.deleted_files TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: employees Admins have full access on employees; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins have full access on employees" ON public.employees TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: bonuses_deductions Admins manage bonuses/deductions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins manage bonuses/deductions" ON public.bonuses_deductions TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: official_holidays Admins manage official holidays; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins manage official holidays" ON public.official_holidays TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: work_schedule_history Admins read schedule history; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins read schedule history" ON public.work_schedule_history FOR SELECT TO authenticated USING (public.is_admin());


--
-- Name: app_versions Anyone authenticated can view app versions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone authenticated can view app versions" ON public.app_versions FOR SELECT TO authenticated USING (true);


--
-- Name: branches Anyone authenticated can view branches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone authenticated can view branches" ON public.branches FOR SELECT TO authenticated USING (true);


--
-- Name: company_settings Anyone authenticated can view company settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone authenticated can view company settings" ON public.company_settings FOR SELECT TO authenticated USING (true);


--
-- Name: departments Anyone authenticated can view departments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone authenticated can view departments" ON public.departments FOR SELECT TO authenticated USING (true);


--
-- Name: geofence_zones Anyone authenticated can view geofence zones; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone authenticated can view geofence zones" ON public.geofence_zones FOR SELECT TO authenticated USING (true);


--
-- Name: system_settings Anyone authenticated can view system settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Anyone authenticated can view system settings" ON public.system_settings FOR SELECT TO authenticated USING (true);


--
-- Name: attendance Attendance readable by owner, admins and branch managers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Attendance readable by owner, admins and branch managers" ON public.attendance FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR ( SELECT public.is_admin() AS is_admin) OR (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[]))));


--
-- Name: archived_months Authenticated can view archived months; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated can view archived months" ON public.archived_months FOR SELECT TO authenticated USING (true);


--
-- Name: work_schedules Authenticated can view work schedules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated can view work schedules" ON public.work_schedules FOR SELECT TO authenticated USING (true);


--
-- Name: payroll_periods Authenticated read payroll periods; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated read payroll periods" ON public.payroll_periods FOR SELECT TO authenticated USING (true);


--
-- Name: fcm_tokens Employee can manage own FCM token; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employee can manage own FCM token" ON public.fcm_tokens USING ((employee_id = auth.uid())) WITH CHECK ((employee_id = auth.uid()));


--
-- Name: device_tokens Employee can manage own device tokens; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employee can manage own device tokens" ON public.device_tokens USING ((employee_id = auth.uid())) WITH CHECK ((employee_id = auth.uid()));


--
-- Name: leave_requests Employees can cancel their pending leave requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can cancel their pending leave requests" ON public.leave_requests FOR UPDATE TO authenticated USING (((employee_id = auth.uid()) AND (status = 'pending'::text))) WITH CHECK (((employee_id = auth.uid()) AND (status = 'cancelled'::text)));


--
-- Name: location_tracking Employees can insert their own location tracking; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can insert their own location tracking" ON public.location_tracking FOR INSERT TO authenticated WITH CHECK ((employee_id = auth.uid()));


--
-- Name: geofence_violations Employees can insert violations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can insert violations" ON public.geofence_violations FOR INSERT TO authenticated WITH CHECK ((employee_id = auth.uid()));


--
-- Name: mock_gps_attempts Employees can report mock gps attempts; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can report mock gps attempts" ON public.mock_gps_attempts FOR INSERT TO authenticated WITH CHECK ((employee_id = auth.uid()));


--
-- Name: tracked_stops Employees can report tracking metrics; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can report tracking metrics" ON public.tracked_stops FOR INSERT TO authenticated WITH CHECK ((employee_id = auth.uid()));


--
-- Name: loans Employees can request loans; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can request loans" ON public.loans FOR INSERT TO authenticated WITH CHECK (((employee_id = auth.uid()) AND ((status = 'pending'::text) OR (status IS NULL))));


--
-- Name: leave_requests Employees can submit their own leave requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can submit their own leave requests" ON public.leave_requests FOR INSERT TO authenticated WITH CHECK (((employee_id = auth.uid()) AND ((status = 'pending'::text) OR (status IS NULL))));


--
-- Name: notifications Employees can update their own notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can update their own notifications" ON public.notifications FOR UPDATE TO authenticated USING ((employee_id = auth.uid())) WITH CHECK ((employee_id = auth.uid()));


--
-- Name: loans Employees can view own loans and admins view all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can view own loans and admins view all" ON public.loans FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR public.is_admin()));


--
-- Name: bonuses_deductions Employees can view their own bonuses/deductions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can view their own bonuses/deductions" ON public.bonuses_deductions FOR SELECT TO authenticated USING ((employee_id = auth.uid()));


--
-- Name: employees Employees can view their own details; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can view their own details" ON public.employees FOR SELECT USING (((id = auth.uid()) OR public.is_admin() OR (public.is_manager() AND public.payroll_same_branch(id))));


--
-- Name: employee_devices Employees can view their own devices; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can view their own devices" ON public.employee_devices FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR public.is_admin()));


--
-- Name: loan_installments Employees can view their own loan installments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can view their own loan installments" ON public.loan_installments FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.loans
  WHERE ((loans.id = loan_installments.loan_id) AND (loans.employee_id = auth.uid())))) OR public.is_admin()));


--
-- Name: notifications Employees can view their own notifications; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can view their own notifications" ON public.notifications FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR public.is_admin()));


--
-- Name: salary_slips Employees can view their own salary slips; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees can view their own salary slips" ON public.salary_slips FOR SELECT TO authenticated USING (((employee_id = auth.uid()) AND (status = 'published'::text)));


--
-- Name: employees Employees update their own row (columns guarded by trigger); Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees update their own row (columns guarded by trigger)" ON public.employees FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK ((id = auth.uid()));


--
-- Name: announcements Employees view announcements addressed to them; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Employees view announcements addressed to them" ON public.announcements FOR SELECT TO authenticated USING ((public.is_admin() OR public.is_manager() OR public.announcement_targets(announcements.*, auth.uid())));


--
-- Name: official_holidays Everyone reads official holidays; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Everyone reads official holidays" ON public.official_holidays FOR SELECT TO authenticated USING (true);


--
-- Name: employee_geofence_assignments Geofence assignments readable by owner, admins and branch manag; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Geofence assignments readable by owner, admins and branch manag" ON public.employee_geofence_assignments FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR ( SELECT public.is_admin() AS is_admin) OR (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[]))));


--
-- Name: notifications Insert own notifications, admins any, branch managers their bra; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Insert own notifications, admins any, branch managers their bra" ON public.notifications FOR INSERT TO authenticated WITH CHECK (((employee_id = auth.uid()) OR ( SELECT public.is_admin() AS is_admin) OR (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[]))));


--
-- Name: leave_balances Leave balance readable by owner, admins and branch managers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Leave balance readable by owner, admins and branch managers" ON public.leave_balances FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR ( SELECT public.is_admin() AS is_admin) OR (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[]))));


--
-- Name: leave_requests Leaves readable by owner, admins and branch managers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Leaves readable by owner, admins and branch managers" ON public.leave_requests FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR ( SELECT public.is_admin() AS is_admin) OR (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[]))));


--
-- Name: mock_gps_attempts Mock GPS readable by admins and branch managers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Mock GPS readable by admins and branch managers" ON public.mock_gps_attempts FOR SELECT TO authenticated USING ((( SELECT public.is_admin() AS is_admin) OR (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[]))));


--
-- Name: attendance Only admins can delete attendance; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can delete attendance" ON public.attendance FOR DELETE TO authenticated USING (public.is_admin());


--
-- Name: leave_requests Only admins can delete leave requests; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can delete leave requests" ON public.leave_requests FOR DELETE TO authenticated USING (public.is_admin());


--
-- Name: loans Only admins can delete loans; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can delete loans" ON public.loans FOR DELETE TO authenticated USING (public.is_admin());


--
-- Name: attendance Only admins can insert attendance; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can insert attendance" ON public.attendance FOR INSERT TO authenticated WITH CHECK (public.is_admin());


--
-- Name: announcements Only admins can manage announcements; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can manage announcements" ON public.announcements TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: app_versions Only admins can manage app versions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can manage app versions" ON public.app_versions TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: archived_months Only admins can manage archived months; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can manage archived months" ON public.archived_months TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: employee_geofence_assignments Only admins can manage geofence assignments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can manage geofence assignments" ON public.employee_geofence_assignments TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: geofence_zones Only admins can manage geofence zones; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can manage geofence zones" ON public.geofence_zones TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: tracking_schedules Only admins can manage tracking schedules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can manage tracking schedules" ON public.tracking_schedules TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: work_schedules Only admins can manage work schedules; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can manage work schedules" ON public.work_schedules TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: branches Only admins can modify branches; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can modify branches" ON public.branches TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: company_settings Only admins can modify company settings; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can modify company settings" ON public.company_settings TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: departments Only admins can modify departments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can modify departments" ON public.departments TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: loans Only admins can update or process loans; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Only admins can update or process loans" ON public.loans FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: payroll_events Payroll events: admins, own decided, branch managers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Payroll events: admins, own decided, branch managers" ON public.payroll_events FOR SELECT TO authenticated USING ((( SELECT public.is_admin() AS is_admin) OR ((employee_id = auth.uid()) AND (status = 'approved'::text)) OR ((employee_id <> auth.uid()) AND (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[])))));


--
-- Name: salary_slip_lines Slip lines readable by owner and admins; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Slip lines readable by owner and admins" ON public.salary_slip_lines FOR SELECT TO authenticated USING ((public.is_admin() OR (EXISTS ( SELECT 1
   FROM public.salary_slips s
  WHERE ((s.id = salary_slip_lines.salary_slip_id) AND (s.employee_id = auth.uid()))))));


--
-- Name: tracked_stops Stops readable by admins and branch managers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Stops readable by admins and branch managers" ON public.tracked_stops FOR SELECT TO authenticated USING ((( SELECT public.is_admin() AS is_admin) OR (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[]))));


--
-- Name: location_tracking Tracking readable by admins and branch managers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Tracking readable by admins and branch managers" ON public.location_tracking FOR SELECT TO authenticated USING ((( SELECT public.is_admin() AS is_admin) OR (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[]))));


--
-- Name: tracking_schedules Tracking schedule readable by owner, admins and branch managers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Tracking schedule readable by owner, admins and branch managers" ON public.tracking_schedules FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR ( SELECT public.is_admin() AS is_admin) OR (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[]))));


--
-- Name: geofence_violations Violations readable by admins and branch managers; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Violations readable by admins and branch managers" ON public.geofence_violations FOR SELECT TO authenticated USING ((( SELECT public.is_admin() AS is_admin) OR (employee_id = ANY (( SELECT public.managed_employee_ids() AS managed_employee_ids)::uuid[]))));


--
-- Name: announcements; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

--
-- Name: app_versions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.app_versions ENABLE ROW LEVEL SECURITY;

--
-- Name: archived_employees; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.archived_employees ENABLE ROW LEVEL SECURITY;

--
-- Name: archived_months; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.archived_months ENABLE ROW LEVEL SECURITY;

--
-- Name: assistant_conversations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.assistant_conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: assistant_conversations assistant_conversations_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY assistant_conversations_owner ON public.assistant_conversations TO authenticated USING (((owner_id = auth.uid()) AND public.is_admin())) WITH CHECK (((owner_id = auth.uid()) AND public.is_admin()));


--
-- Name: assistant_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.assistant_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: assistant_messages assistant_messages_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY assistant_messages_owner ON public.assistant_messages FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.assistant_conversations c
  WHERE ((c.id = assistant_messages.conversation_id) AND (c.owner_id = auth.uid()) AND public.is_admin()))));


--
-- Name: attendance; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance_reminder_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance_reminder_log ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log audit_log admin read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "audit_log admin read" ON public.audit_log FOR SELECT USING (public.is_admin());


--
-- Name: audit_log audit_log no direct writes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "audit_log no direct writes" ON public.audit_log USING (false) WITH CHECK (false);


--
-- Name: bonuses_deductions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bonuses_deductions ENABLE ROW LEVEL SECURITY;

--
-- Name: branches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;

--
-- Name: cleanup_run_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cleanup_run_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: company_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: deleted_files; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.deleted_files ENABLE ROW LEVEL SECURITY;

--
-- Name: departments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.departments ENABLE ROW LEVEL SECURITY;

--
-- Name: device_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_assignment_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_assignment_history ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_assignment_history employee_assignment_history_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_assignment_history_admin_read ON public.employee_assignment_history FOR SELECT TO authenticated USING (( SELECT public.is_admin() AS is_admin));


--
-- Name: employee_devices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_devices ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_geofence_assignments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_geofence_assignments ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_service_breaks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_service_breaks ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_service_breaks employee_service_breaks_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_service_breaks_admin_read ON public.employee_service_breaks FOR SELECT TO authenticated USING (( SELECT public.is_admin() AS is_admin));


--
-- Name: employees; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

--
-- Name: fcm_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: geofence_violations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.geofence_violations ENABLE ROW LEVEL SECURITY;

--
-- Name: geofence_zones; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.geofence_zones ENABLE ROW LEVEL SECURITY;

--
-- Name: leave_balances; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_balances ENABLE ROW LEVEL SECURITY;

--
-- Name: leave_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: loan_installments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.loan_installments ENABLE ROW LEVEL SECURITY;

--
-- Name: loans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.loans ENABLE ROW LEVEL SECURITY;

--
-- Name: location_tracking; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.location_tracking ENABLE ROW LEVEL SECURITY;

--
-- Name: mock_gps_attempts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.mock_gps_attempts ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: official_holidays; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.official_holidays ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_cleanups; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_cleanups ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_cleanups payroll_cleanups_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_cleanups_admin_read ON public.payroll_cleanups FOR SELECT TO authenticated USING (public.is_admin());


--
-- Name: payroll_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_events ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_loan_caps; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_loan_caps ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_loan_caps payroll_loan_caps_admin_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_loan_caps_admin_read ON public.payroll_loan_caps FOR SELECT TO authenticated USING (( SELECT public.is_admin() AS is_admin));


--
-- Name: payroll_periods; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_periods ENABLE ROW LEVEL SECURITY;

--
-- Name: salary_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.salary_history ENABLE ROW LEVEL SECURITY;

--
-- Name: salary_history salary_history_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_history_admin ON public.salary_history TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: salary_history salary_history_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY salary_history_own ON public.salary_history FOR SELECT TO authenticated USING ((employee_id = auth.uid()));


--
-- Name: salary_slip_lines; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.salary_slip_lines ENABLE ROW LEVEL SECURITY;

--
-- Name: salary_slips; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.salary_slips ENABLE ROW LEVEL SECURITY;

--
-- Name: settled_loans; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.settled_loans ENABLE ROW LEVEL SECURITY;

--
-- Name: settled_loans settled_loans_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY settled_loans_read ON public.settled_loans FOR SELECT TO authenticated USING ((public.is_admin() OR (employee_id = auth.uid())));


--
-- Name: system_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: tracked_stops; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tracked_stops ENABLE ROW LEVEL SECURITY;

--
-- Name: tracking_schedules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tracking_schedules ENABLE ROW LEVEL SECURITY;

--
-- Name: work_schedule_history; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_schedule_history ENABLE ROW LEVEL SECURITY;

--
-- Name: work_schedules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_schedules ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION _anonymize_employee(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._anonymize_employee(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public._anonymize_employee(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION _ar_time(p_time time without time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._ar_time(p_time time without time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public._ar_time(p_time time without time zone) TO authenticated;
GRANT ALL ON FUNCTION public._ar_time(p_time time without time zone) TO service_role;


--
-- Name: FUNCTION _cap_loans_to_net(p_employee_id uuid, p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._cap_loans_to_net(p_employee_id uuid, p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public._cap_loans_to_net(p_employee_id uuid, p_month text) TO service_role;


--
-- Name: FUNCTION _insert_loan_installments(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._insert_loan_installments(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date) FROM PUBLIC;
GRANT ALL ON FUNCTION public._insert_loan_installments(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date) TO service_role;


--
-- Name: FUNCTION _loan_month_settled(p_employee_id uuid, p_due date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._loan_month_settled(p_employee_id uuid, p_due date) FROM PUBLIC;
GRANT ALL ON FUNCTION public._loan_month_settled(p_employee_id uuid, p_due date) TO service_role;


--
-- Name: FUNCTION _payroll_day_apply(p_employee_id uuid, p_date date, p_natural text, p_daily numeric, p_minute numeric, p_policy jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._payroll_day_apply(p_employee_id uuid, p_date date, p_natural text, p_daily numeric, p_minute numeric, p_policy jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public._payroll_day_apply(p_employee_id uuid, p_date date, p_natural text, p_daily numeric, p_minute numeric, p_policy jsonb) TO service_role;


--
-- Name: TABLE attendance; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.attendance TO anon;
GRANT ALL ON TABLE public.attendance TO authenticated;
GRANT ALL ON TABLE public.attendance TO service_role;


--
-- Name: TABLE work_schedules; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.work_schedules TO anon;
GRANT ALL ON TABLE public.work_schedules TO authenticated;
GRANT ALL ON TABLE public.work_schedules TO service_role;


--
-- Name: FUNCTION _payroll_day_attendance_events(p_employee_id uuid, p_date date, p_att public.attendance, p_sched public.work_schedules, p_workday boolean, p_daily numeric, p_minute numeric, p_policy jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._payroll_day_attendance_events(p_employee_id uuid, p_date date, p_att public.attendance, p_sched public.work_schedules, p_workday boolean, p_daily numeric, p_minute numeric, p_policy jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public._payroll_day_attendance_events(p_employee_id uuid, p_date date, p_att public.attendance, p_sched public.work_schedules, p_workday boolean, p_daily numeric, p_minute numeric, p_policy jsonb) TO service_role;


--
-- Name: FUNCTION _payroll_day_hourly_leaves(p_employee_id uuid, p_date date, p_minute numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._payroll_day_hourly_leaves(p_employee_id uuid, p_date date, p_minute numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public._payroll_day_hourly_leaves(p_employee_id uuid, p_date date, p_minute numeric) TO service_role;


--
-- Name: FUNCTION _payroll_day_leave_events(p_employee_id uuid, p_date date, p_workday boolean, p_daily numeric, p_policy jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._payroll_day_leave_events(p_employee_id uuid, p_date date, p_workday boolean, p_daily numeric, p_policy jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public._payroll_day_leave_events(p_employee_id uuid, p_date date, p_workday boolean, p_daily numeric, p_policy jsonb) TO service_role;


--
-- Name: TABLE payroll_events; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE public.payroll_events TO anon;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE public.payroll_events TO authenticated;
GRANT ALL ON TABLE public.payroll_events TO service_role;


--
-- Name: COLUMN payroll_events.id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(id) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.employee_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(employee_id) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.event_date; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(event_date) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.event_type; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(event_type) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.minutes; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(minutes) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.days; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(days) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.direction; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(direction) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.payroll_month; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(payroll_month) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.carried_from; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(carried_from) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.status; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(status) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.source; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(source) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.source_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(source_id) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.adjusts_event_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(adjusts_event_id) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.notes; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(notes) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.decision_reason; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(decision_reason) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.decided_by; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(decided_by) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.decided_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(decided_at) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.salary_slip_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(salary_slip_id) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.created_by; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(created_by) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.created_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(created_at) ON TABLE public.payroll_events TO authenticated;


--
-- Name: COLUMN payroll_events.updated_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(updated_at) ON TABLE public.payroll_events TO authenticated;


--
-- Name: FUNCTION _payroll_event_computed_amount(e public.payroll_events); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._payroll_event_computed_amount(e public.payroll_events) FROM PUBLIC;
GRANT ALL ON FUNCTION public._payroll_event_computed_amount(e public.payroll_events) TO service_role;


--
-- Name: FUNCTION _payroll_settle(p_event public.payroll_events, p_desired_signed numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._payroll_settle(p_event public.payroll_events, p_desired_signed numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public._payroll_settle(p_event public.payroll_events, p_desired_signed numeric) TO service_role;


--
-- Name: FUNCTION _pledge_bytes(p_url text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._pledge_bytes(p_url text) FROM PUBLIC;
GRANT ALL ON FUNCTION public._pledge_bytes(p_url text) TO service_role;


--
-- Name: FUNCTION _salary_effective_month(p_value text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._salary_effective_month(p_value text) FROM PUBLIC;
GRANT ALL ON FUNCTION public._salary_effective_month(p_value text) TO authenticated;
GRANT ALL ON FUNCTION public._salary_effective_month(p_value text) TO service_role;


--
-- Name: FUNCTION _validate_loan_terms(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_ignore_loan uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public._validate_loan_terms(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_ignore_loan uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public._validate_loan_terms(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_ignore_loan uuid) TO service_role;


--
-- Name: TABLE announcements; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.announcements TO anon;
GRANT ALL ON TABLE public.announcements TO authenticated;
GRANT ALL ON TABLE public.announcements TO service_role;


--
-- Name: FUNCTION announcement_targets(a public.announcements, p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.announcement_targets(a public.announcements, p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.announcement_targets(a public.announcements, p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.announcement_targets(a public.announcements, p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION apply_due_salary_changes(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.apply_due_salary_changes() FROM PUBLIC;
GRANT ALL ON FUNCTION public.apply_due_salary_changes() TO service_role;


--
-- Name: FUNCTION approve_loan(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.approve_loan(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.approve_loan(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date) TO authenticated;
GRANT ALL ON FUNCTION public.approve_loan(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date) TO service_role;


--
-- Name: FUNCTION approve_payroll_slip(p_employee_id uuid, p_month text, p_adjustments jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.approve_payroll_slip(p_employee_id uuid, p_month text, p_adjustments jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.approve_payroll_slip(p_employee_id uuid, p_month text, p_adjustments jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.approve_payroll_slip(p_employee_id uuid, p_month text, p_adjustments jsonb) TO service_role;


--
-- Name: FUNCTION approve_salary_slip(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[], p_adjustments jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.approve_salary_slip(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[], p_adjustments jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.approve_salary_slip(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[], p_adjustments jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.approve_salary_slip(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[], p_adjustments jsonb) TO service_role;


--
-- Name: FUNCTION approve_salary_slip_legacy(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[], p_adjustments jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.approve_salary_slip_legacy(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[], p_adjustments jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.approve_salary_slip_legacy(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[], p_adjustments jsonb) TO service_role;


--
-- Name: FUNCTION archive_settled_loan(p_loan_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.archive_settled_loan(p_loan_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.archive_settled_loan(p_loan_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.archive_settled_loan(p_loan_id uuid) TO service_role;


--
-- Name: FUNCTION assign_employee_code(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assign_employee_code() FROM PUBLIC;
GRANT ALL ON FUNCTION public.assign_employee_code() TO service_role;


--
-- Name: FUNCTION assign_loan_no(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assign_loan_no() FROM PUBLIC;
GRANT ALL ON FUNCTION public.assign_loan_no() TO authenticated;
GRANT ALL ON FUNCTION public.assign_loan_no() TO service_role;


--
-- Name: FUNCTION assistant_alerts(p_from date, p_to date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_alerts(p_from date, p_to date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_alerts(p_from date, p_to date) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_alerts(p_from date, p_to date) TO service_role;


--
-- Name: FUNCTION assistant_attendance_log(p_employee_id uuid, p_from date, p_to date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_attendance_log(p_employee_id uuid, p_from date, p_to date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_attendance_log(p_employee_id uuid, p_from date, p_to date) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_attendance_log(p_employee_id uuid, p_from date, p_to date) TO service_role;


--
-- Name: FUNCTION assistant_branch_attendance(p_branch text, p_from date, p_to date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_branch_attendance(p_branch text, p_from date, p_to date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_branch_attendance(p_branch text, p_from date, p_to date) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_branch_attendance(p_branch text, p_from date, p_to date) TO service_role;


--
-- Name: FUNCTION assistant_branch_ranking(p_from date, p_to date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_branch_ranking(p_from date, p_to date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_branch_ranking(p_from date, p_to date) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_branch_ranking(p_from date, p_to date) TO service_role;


--
-- Name: FUNCTION assistant_branches(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_branches() FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_branches() TO authenticated;
GRANT ALL ON FUNCTION public.assistant_branches() TO service_role;


--
-- Name: FUNCTION assistant_build_morning_summary(p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_build_morning_summary(p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_build_morning_summary(p_date date) TO service_role;


--
-- Name: FUNCTION assistant_compare(p_employee_id uuid, p_branch text, p_month_a text, p_month_b text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_compare(p_employee_id uuid, p_branch text, p_month_a text, p_month_b text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_compare(p_employee_id uuid, p_branch text, p_month_a text, p_month_b text) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_compare(p_employee_id uuid, p_branch text, p_month_a text, p_month_b text) TO service_role;


--
-- Name: FUNCTION assistant_data_issues(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_data_issues() FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_data_issues() TO service_role;


--
-- Name: FUNCTION assistant_day_overview(p_date date, p_branch text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_day_overview(p_date date, p_branch text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_day_overview(p_date date, p_branch text) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_day_overview(p_date date, p_branch text) TO service_role;


--
-- Name: FUNCTION assistant_decision_context(p_branch text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_decision_context(p_branch text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_decision_context(p_branch text) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_decision_context(p_branch text) TO service_role;


--
-- Name: FUNCTION assistant_documents(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_documents(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_documents(p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_documents(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION assistant_find_employees(p_query text, p_branch text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_find_employees(p_query text, p_branch text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_find_employees(p_query text, p_branch text) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_find_employees(p_query text, p_branch text) TO service_role;


--
-- Name: FUNCTION assistant_leave_type_name(p_type text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_leave_type_name(p_type text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_leave_type_name(p_type text) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_leave_type_name(p_type text) TO service_role;


--
-- Name: FUNCTION assistant_leaves(p_employee_id uuid, p_from date, p_to date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_leaves(p_employee_id uuid, p_from date, p_to date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_leaves(p_employee_id uuid, p_from date, p_to date) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_leaves(p_employee_id uuid, p_from date, p_to date) TO service_role;


--
-- Name: FUNCTION assistant_loans(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_loans(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_loans(p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_loans(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION assistant_month_employees(p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_month_employees(p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_month_employees(p_month text) TO service_role;


--
-- Name: FUNCTION assistant_month_metrics(p_employee_id uuid, p_branch text, p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_month_metrics(p_employee_id uuid, p_branch text, p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_month_metrics(p_employee_id uuid, p_branch text, p_month text) TO service_role;


--
-- Name: FUNCTION assistant_morning_summary(p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_morning_summary(p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_morning_summary(p_date date) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_morning_summary(p_date date) TO service_role;


--
-- Name: FUNCTION assistant_name_hints(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_name_hints() FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_name_hints() TO authenticated;
GRANT ALL ON FUNCTION public.assistant_name_hints() TO service_role;


--
-- Name: FUNCTION assistant_norm(p text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_norm(p text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_norm(p text) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_norm(p text) TO service_role;


--
-- Name: FUNCTION assistant_payroll(p_employee_id uuid, p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_payroll(p_employee_id uuid, p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_payroll(p_employee_id uuid, p_month text) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_payroll(p_employee_id uuid, p_month text) TO service_role;


--
-- Name: FUNCTION assistant_payroll_readiness(p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_payroll_readiness(p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_payroll_readiness(p_month text) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_payroll_readiness(p_month text) TO service_role;


--
-- Name: FUNCTION assistant_payroll_run(p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_payroll_run(p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_payroll_run(p_month text) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_payroll_run(p_month text) TO service_role;


--
-- Name: FUNCTION assistant_pending_decisions(p_branch text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_pending_decisions(p_branch text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_pending_decisions(p_branch text) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_pending_decisions(p_branch text) TO service_role;


--
-- Name: FUNCTION assistant_pending_events(p_ids uuid[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_pending_events(p_ids uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_pending_events(p_ids uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_pending_events(p_ids uuid[]) TO service_role;


--
-- Name: FUNCTION assistant_save_messages(p_conversation_id uuid, p_messages jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_save_messages(p_conversation_id uuid, p_messages jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_save_messages(p_conversation_id uuid, p_messages jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_save_messages(p_conversation_id uuid, p_messages jsonb) TO service_role;


--
-- Name: FUNCTION assistant_set_morning_summary(p_enabled boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_set_morning_summary(p_enabled boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_set_morning_summary(p_enabled boolean) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_set_morning_summary(p_enabled boolean) TO service_role;


--
-- Name: FUNCTION assistant_settings(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_settings() FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_settings() TO authenticated;
GRANT ALL ON FUNCTION public.assistant_settings() TO service_role;


--
-- Name: FUNCTION assistant_top_late(p_from date, p_to date, p_branch text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.assistant_top_late(p_from date, p_to date, p_branch text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.assistant_top_late(p_from date, p_to date, p_branch text) TO authenticated;
GRANT ALL ON FUNCTION public.assistant_top_late(p_from date, p_to date, p_branch text) TO service_role;


--
-- Name: FUNCTION calculate_payroll(p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.calculate_payroll(p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.calculate_payroll(p_month text) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_payroll(p_month text) TO service_role;


--
-- Name: FUNCTION calculate_payroll_batch(p_month text, p_after uuid, p_limit integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.calculate_payroll_batch(p_month text, p_after uuid, p_limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.calculate_payroll_batch(p_month text, p_after uuid, p_limit integer) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_payroll_batch(p_month text, p_after uuid, p_limit integer) TO service_role;


--
-- Name: FUNCTION cancel_my_loan_request(p_loan_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_my_loan_request(p_loan_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_my_loan_request(p_loan_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_my_loan_request(p_loan_id uuid) TO service_role;


--
-- Name: FUNCTION check_and_send_attendance_reminders(p_now timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.check_and_send_attendance_reminders(p_now timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.check_and_send_attendance_reminders(p_now timestamp with time zone) TO service_role;


--
-- Name: FUNCTION check_archive_policy(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.check_archive_policy() FROM PUBLIC;
GRANT ALL ON FUNCTION public.check_archive_policy() TO authenticated;
GRANT ALL ON FUNCTION public.check_archive_policy() TO service_role;


--
-- Name: FUNCTION check_bonus_deduction_amount(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.check_bonus_deduction_amount() FROM PUBLIC;
GRANT ALL ON FUNCTION public.check_bonus_deduction_amount() TO authenticated;
GRANT ALL ON FUNCTION public.check_bonus_deduction_amount() TO service_role;


--
-- Name: FUNCTION check_employee_basics(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.check_employee_basics() FROM PUBLIC;
GRANT ALL ON FUNCTION public.check_employee_basics() TO authenticated;
GRANT ALL ON FUNCTION public.check_employee_basics() TO service_role;


--
-- Name: FUNCTION check_employee_branch(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.check_employee_branch() FROM PUBLIC;
GRANT ALL ON FUNCTION public.check_employee_branch() TO authenticated;
GRANT ALL ON FUNCTION public.check_employee_branch() TO service_role;


--
-- Name: FUNCTION clear_delivered_on_reopen(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.clear_delivered_on_reopen() FROM PUBLIC;
GRANT ALL ON FUNCTION public.clear_delivered_on_reopen() TO authenticated;
GRANT ALL ON FUNCTION public.clear_delivered_on_reopen() TO service_role;


--
-- Name: FUNCTION close_payroll_period(p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.close_payroll_period(p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.close_payroll_period(p_month text) TO authenticated;
GRANT ALL ON FUNCTION public.close_payroll_period(p_month text) TO service_role;


--
-- Name: FUNCTION company_timezone(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.company_timezone() FROM PUBLIC;
GRANT ALL ON FUNCTION public.company_timezone() TO authenticated;
GRANT ALL ON FUNCTION public.company_timezone() TO service_role;


--
-- Name: FUNCTION copy_legacy_push_token(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.copy_legacy_push_token() FROM PUBLIC;
GRANT ALL ON FUNCTION public.copy_legacy_push_token() TO service_role;


--
-- Name: FUNCTION create_default_leave_balance(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_default_leave_balance() FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_default_leave_balance() TO authenticated;
GRANT ALL ON FUNCTION public.create_default_leave_balance() TO service_role;


--
-- Name: FUNCTION create_direct_loan(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_pledge_url text, p_notes text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_direct_loan(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_pledge_url text, p_notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_direct_loan(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_pledge_url text, p_notes text) TO authenticated;
GRANT ALL ON FUNCTION public.create_direct_loan(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_pledge_url text, p_notes text) TO service_role;


--
-- Name: FUNCTION create_employee_secure(p_email text, p_password text, p_full_name text, p_phone text, p_role text, p_branch_id uuid, p_monthly_salary_iqd numeric, p_document_urls text[], p_employee_code text, p_employee_id uuid, p_join_date date, p_department_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.create_employee_secure(p_email text, p_password text, p_full_name text, p_phone text, p_role text, p_branch_id uuid, p_monthly_salary_iqd numeric, p_document_urls text[], p_employee_code text, p_employee_id uuid, p_join_date date, p_department_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_employee_secure(p_email text, p_password text, p_full_name text, p_phone text, p_role text, p_branch_id uuid, p_monthly_salary_iqd numeric, p_document_urls text[], p_employee_code text, p_employee_id uuid, p_join_date date, p_department_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.create_employee_secure(p_email text, p_password text, p_full_name text, p_phone text, p_role text, p_branch_id uuid, p_monthly_salary_iqd numeric, p_document_urls text[], p_employee_code text, p_employee_id uuid, p_join_date date, p_department_id uuid) TO service_role;


--
-- Name: FUNCTION decide_absence_day(p_employee_id uuid, p_date date, p_approve boolean, p_reason text, p_amount numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.decide_absence_day(p_employee_id uuid, p_date date, p_approve boolean, p_reason text, p_amount numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.decide_absence_day(p_employee_id uuid, p_date date, p_approve boolean, p_reason text, p_amount numeric) TO authenticated;
GRANT ALL ON FUNCTION public.decide_absence_day(p_employee_id uuid, p_date date, p_approve boolean, p_reason text, p_amount numeric) TO service_role;


--
-- Name: FUNCTION decide_payroll_event(p_event_id uuid, p_approve boolean, p_reason text, p_amount numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.decide_payroll_event(p_event_id uuid, p_approve boolean, p_reason text, p_amount numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.decide_payroll_event(p_event_id uuid, p_approve boolean, p_reason text, p_amount numeric) TO authenticated;
GRANT ALL ON FUNCTION public.decide_payroll_event(p_event_id uuid, p_approve boolean, p_reason text, p_amount numeric) TO service_role;


--
-- Name: FUNCTION destroy_archived_employee(p_archive_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.destroy_archived_employee(p_archive_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.destroy_archived_employee(p_archive_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.destroy_archived_employee(p_archive_id uuid) TO service_role;


--
-- Name: FUNCTION distance_meters(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.distance_meters(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision) FROM PUBLIC;
GRANT ALL ON FUNCTION public.distance_meters(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision) TO authenticated;
GRANT ALL ON FUNCTION public.distance_meters(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision) TO service_role;


--
-- Name: FUNCTION employee_assignment_at(p_employee_id uuid, p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.employee_assignment_at(p_employee_id uuid, p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.employee_assignment_at(p_employee_id uuid, p_date date) TO service_role;


--
-- Name: FUNCTION employee_in_service(p_employee_id uuid, p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.employee_in_service(p_employee_id uuid, p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.employee_in_service(p_employee_id uuid, p_date date) TO service_role;


--
-- Name: FUNCTION employee_shift_hours(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.employee_shift_hours(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.employee_shift_hours(p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.employee_shift_hours(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION employee_work_days(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.employee_work_days(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.employee_work_days(p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.employee_work_days(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION end_employee_service(p_employee_id uuid, p_type text, p_reason text, p_last_day date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.end_employee_service(p_employee_id uuid, p_type text, p_reason text, p_last_day date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.end_employee_service(p_employee_id uuid, p_type text, p_reason text, p_last_day date) TO authenticated;
GRANT ALL ON FUNCTION public.end_employee_service(p_employee_id uuid, p_type text, p_reason text, p_last_day date) TO service_role;


--
-- Name: FUNCTION end_of_service_preview(p_employee_id uuid, p_last_day date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.end_of_service_preview(p_employee_id uuid, p_last_day date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.end_of_service_preview(p_employee_id uuid, p_last_day date) TO authenticated;
GRANT ALL ON FUNCTION public.end_of_service_preview(p_employee_id uuid, p_last_day date) TO service_role;


--
-- Name: TABLE payroll_periods; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.payroll_periods TO anon;
GRANT ALL ON TABLE public.payroll_periods TO authenticated;
GRANT ALL ON TABLE public.payroll_periods TO service_role;


--
-- Name: FUNCTION ensure_payroll_period(p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.ensure_payroll_period(p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.ensure_payroll_period(p_month text) TO service_role;


--
-- Name: FUNCTION fmt_days(v numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.fmt_days(v numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.fmt_days(v numeric) TO authenticated;
GRANT ALL ON FUNCTION public.fmt_days(v numeric) TO service_role;


--
-- Name: FUNCTION get_absent_today(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_absent_today() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_absent_today() TO authenticated;
GRANT ALL ON FUNCTION public.get_absent_today() TO service_role;


--
-- Name: FUNCTION get_active_announcements(p_limit integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_active_announcements(p_limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_active_announcements(p_limit integer) TO authenticated;
GRANT ALL ON FUNCTION public.get_active_announcements(p_limit integer) TO service_role;


--
-- Name: FUNCTION get_database_size(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_database_size() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_database_size() TO authenticated;
GRANT ALL ON FUNCTION public.get_database_size() TO service_role;


--
-- Name: FUNCTION get_database_table_sizes(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_database_table_sizes() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_database_table_sizes() TO authenticated;
GRANT ALL ON FUNCTION public.get_database_table_sizes() TO service_role;


--
-- Name: FUNCTION get_effective_work_schedule(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_effective_work_schedule(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_effective_work_schedule(p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_effective_work_schedule(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION get_employee_directory(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_employee_directory() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_employee_directory() TO authenticated;
GRANT ALL ON FUNCTION public.get_employee_directory() TO service_role;


--
-- Name: FUNCTION get_employee_history(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_employee_history(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_employee_history(p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_employee_history(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION get_employee_pay(p_employee_ids uuid[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_employee_pay(p_employee_ids uuid[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_employee_pay(p_employee_ids uuid[]) TO authenticated;
GRANT ALL ON FUNCTION public.get_employee_pay(p_employee_ids uuid[]) TO service_role;


--
-- Name: FUNCTION get_late_today(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_late_today() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_late_today() TO authenticated;
GRANT ALL ON FUNCTION public.get_late_today() TO service_role;


--
-- Name: FUNCTION get_leave_balance(p_employee_id uuid, p_on date, p_exclude uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_leave_balance(p_employee_id uuid, p_on date, p_exclude uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_leave_balance(p_employee_id uuid, p_on date, p_exclude uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_leave_balance(p_employee_id uuid, p_on date, p_exclude uuid) TO service_role;


--
-- Name: FUNCTION get_my_payroll_preview(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_my_payroll_preview() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_my_payroll_preview() TO authenticated;
GRANT ALL ON FUNCTION public.get_my_payroll_preview() TO service_role;


--
-- Name: FUNCTION get_on_leave_now(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_on_leave_now() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_on_leave_now() TO authenticated;
GRANT ALL ON FUNCTION public.get_on_leave_now() TO service_role;


--
-- Name: FUNCTION get_orphan_storage_candidates(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_orphan_storage_candidates() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_orphan_storage_candidates() TO authenticated;
GRANT ALL ON FUNCTION public.get_orphan_storage_candidates() TO service_role;


--
-- Name: FUNCTION get_payroll_event_amounts(p_from date, p_to date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_payroll_event_amounts(p_from date, p_to date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_payroll_event_amounts(p_from date, p_to date) TO authenticated;
GRANT ALL ON FUNCTION public.get_payroll_event_amounts(p_from date, p_to date) TO service_role;


--
-- Name: FUNCTION get_payroll_events(p_month text, p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_payroll_events(p_month text, p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_payroll_events(p_month text, p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_payroll_events(p_month text, p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION get_payroll_run(p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_payroll_run(p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_payroll_run(p_month text) TO authenticated;
GRANT ALL ON FUNCTION public.get_payroll_run(p_month text) TO service_role;


--
-- Name: FUNCTION get_pending_payroll_decisions(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_pending_payroll_decisions() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_pending_payroll_decisions() TO authenticated;
GRANT ALL ON FUNCTION public.get_pending_payroll_decisions() TO service_role;


--
-- Name: FUNCTION get_storage_stats(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_storage_stats() FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_storage_stats() TO authenticated;
GRANT ALL ON FUNCTION public.get_storage_stats() TO service_role;


--
-- Name: FUNCTION guard_bonus_deduction_entry(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.guard_bonus_deduction_entry() FROM PUBLIC;
GRANT ALL ON FUNCTION public.guard_bonus_deduction_entry() TO authenticated;
GRANT ALL ON FUNCTION public.guard_bonus_deduction_entry() TO service_role;


--
-- Name: FUNCTION guard_loan_delete(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.guard_loan_delete() FROM PUBLIC;
GRANT ALL ON FUNCTION public.guard_loan_delete() TO authenticated;
GRANT ALL ON FUNCTION public.guard_loan_delete() TO service_role;


--
-- Name: FUNCTION guard_loan_status(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.guard_loan_status() FROM PUBLIC;
GRANT ALL ON FUNCTION public.guard_loan_status() TO authenticated;
GRANT ALL ON FUNCTION public.guard_loan_status() TO service_role;


--
-- Name: FUNCTION guard_paid_installment_delete(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.guard_paid_installment_delete() FROM PUBLIC;
GRANT ALL ON FUNCTION public.guard_paid_installment_delete() TO authenticated;
GRANT ALL ON FUNCTION public.guard_paid_installment_delete() TO service_role;


--
-- Name: FUNCTION guard_slip_paid_installment(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.guard_slip_paid_installment() FROM PUBLIC;
GRANT ALL ON FUNCTION public.guard_slip_paid_installment() TO authenticated;
GRANT ALL ON FUNCTION public.guard_slip_paid_installment() TO service_role;


--
-- Name: FUNCTION guard_slip_with_archived_loan(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.guard_slip_with_archived_loan() FROM PUBLIC;
GRANT ALL ON FUNCTION public.guard_slip_with_archived_loan() TO authenticated;
GRANT ALL ON FUNCTION public.guard_slip_with_archived_loan() TO service_role;


--
-- Name: FUNCTION hard_delete_employee(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.hard_delete_employee(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.hard_delete_employee(p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.hard_delete_employee(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION invoke_push_notification(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.invoke_push_notification() FROM PUBLIC;
GRANT ALL ON FUNCTION public.invoke_push_notification() TO authenticated;
GRANT ALL ON FUNCTION public.invoke_push_notification() TO service_role;


--
-- Name: FUNCTION is_admin(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_admin() TO authenticated;
GRANT ALL ON FUNCTION public.is_admin() TO service_role;
GRANT ALL ON FUNCTION public.is_admin() TO anon;


--
-- Name: FUNCTION is_manager(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.is_manager() FROM PUBLIC;
GRANT ALL ON FUNCTION public.is_manager() TO authenticated;
GRANT ALL ON FUNCTION public.is_manager() TO service_role;
GRANT ALL ON FUNCTION public.is_manager() TO anon;


--
-- Name: FUNCTION issue_cleanup_token(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.issue_cleanup_token() FROM PUBLIC;
GRANT ALL ON FUNCTION public.issue_cleanup_token() TO service_role;


--
-- Name: FUNCTION keep_loan_no(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.keep_loan_no() FROM PUBLIC;
GRANT ALL ON FUNCTION public.keep_loan_no() TO authenticated;
GRANT ALL ON FUNCTION public.keep_loan_no() TO service_role;


--
-- Name: FUNCTION keep_payroll_policy_keys(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.keep_payroll_policy_keys() FROM PUBLIC;
GRANT ALL ON FUNCTION public.keep_payroll_policy_keys() TO authenticated;
GRANT ALL ON FUNCTION public.keep_payroll_policy_keys() TO service_role;


--
-- Name: FUNCTION keep_status_on_early_checkout(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.keep_status_on_early_checkout() FROM PUBLIC;
GRANT ALL ON FUNCTION public.keep_status_on_early_checkout() TO authenticated;
GRANT ALL ON FUNCTION public.keep_status_on_early_checkout() TO service_role;


--
-- Name: FUNCTION leave_policy(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.leave_policy() FROM PUBLIC;
GRANT ALL ON FUNCTION public.leave_policy() TO authenticated;
GRANT ALL ON FUNCTION public.leave_policy() TO service_role;


--
-- Name: TABLE leave_requests; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.leave_requests TO anon;
GRANT ALL ON TABLE public.leave_requests TO authenticated;
GRANT ALL ON TABLE public.leave_requests TO service_role;


--
-- Name: FUNCTION leave_request_days(lr public.leave_requests); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.leave_request_days(lr public.leave_requests) FROM PUBLIC;
GRANT ALL ON FUNCTION public.leave_request_days(lr public.leave_requests) TO authenticated;
GRANT ALL ON FUNCTION public.leave_request_days(lr public.leave_requests) TO service_role;


--
-- Name: FUNCTION leave_request_hours(lr public.leave_requests); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.leave_request_hours(lr public.leave_requests) FROM PUBLIC;
GRANT ALL ON FUNCTION public.leave_request_hours(lr public.leave_requests) TO authenticated;
GRANT ALL ON FUNCTION public.leave_request_hours(lr public.leave_requests) TO service_role;


--
-- Name: FUNCTION loan_archive_blocker(p_loan_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.loan_archive_blocker(p_loan_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.loan_archive_blocker(p_loan_id uuid) TO service_role;


--
-- Name: FUNCTION loans_cleanup_preview(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.loans_cleanup_preview() FROM PUBLIC;
GRANT ALL ON FUNCTION public.loans_cleanup_preview() TO authenticated;
GRANT ALL ON FUNCTION public.loans_cleanup_preview() TO service_role;


--
-- Name: FUNCTION loans_cleanup_run(p_settled boolean, p_requests boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.loans_cleanup_run(p_settled boolean, p_requests boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.loans_cleanup_run(p_settled boolean, p_requests boolean) TO authenticated;
GRANT ALL ON FUNCTION public.loans_cleanup_run(p_settled boolean, p_requests boolean) TO service_role;


--
-- Name: FUNCTION managed_employee_ids(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.managed_employee_ids() FROM PUBLIC;
GRANT ALL ON FUNCTION public.managed_employee_ids() TO authenticated;
GRANT ALL ON FUNCTION public.managed_employee_ids() TO service_role;


--
-- Name: FUNCTION manual_purge_month_data(p_year integer, p_month integer, p_notifications boolean, p_tracking boolean, p_absences boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.manual_purge_month_data(p_year integer, p_month integer, p_notifications boolean, p_tracking boolean, p_absences boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.manual_purge_month_data(p_year integer, p_month integer, p_notifications boolean, p_tracking boolean, p_absences boolean) TO authenticated;
GRANT ALL ON FUNCTION public.manual_purge_month_data(p_year integer, p_month integer, p_notifications boolean, p_tracking boolean, p_absences boolean) TO service_role;


--
-- Name: FUNCTION mark_offline_punch_reviewed(p_attendance_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.mark_offline_punch_reviewed(p_attendance_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.mark_offline_punch_reviewed(p_attendance_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.mark_offline_punch_reviewed(p_attendance_id uuid) TO service_role;


--
-- Name: FUNCTION mark_payroll_delivered(p_month text, p_delivered boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.mark_payroll_delivered(p_month text, p_delivered boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.mark_payroll_delivered(p_month text, p_delivered boolean) TO authenticated;
GRANT ALL ON FUNCTION public.mark_payroll_delivered(p_month text, p_delivered boolean) TO service_role;


--
-- Name: FUNCTION next_employee_code(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.next_employee_code() FROM PUBLIC;
GRANT ALL ON FUNCTION public.next_employee_code() TO service_role;


--
-- Name: FUNCTION notify_admins_of_new_leave_request(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_admins_of_new_leave_request() FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_admins_of_new_leave_request() TO authenticated;
GRANT ALL ON FUNCTION public.notify_admins_of_new_leave_request() TO service_role;


--
-- Name: FUNCTION notify_admins_of_new_loan_request(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_admins_of_new_loan_request() FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_admins_of_new_loan_request() TO authenticated;
GRANT ALL ON FUNCTION public.notify_admins_of_new_loan_request() TO service_role;


--
-- Name: FUNCTION notify_employee_on_leave_decision(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_employee_on_leave_decision() FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_employee_on_leave_decision() TO authenticated;
GRANT ALL ON FUNCTION public.notify_employee_on_leave_decision() TO service_role;


--
-- Name: FUNCTION notify_employee_on_loan_decision(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.notify_employee_on_loan_decision() FROM PUBLIC;
GRANT ALL ON FUNCTION public.notify_employee_on_loan_decision() TO authenticated;
GRANT ALL ON FUNCTION public.notify_employee_on_loan_decision() TO service_role;


--
-- Name: FUNCTION one_pending_loan_request(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.one_pending_loan_request() FROM PUBLIC;
GRANT ALL ON FUNCTION public.one_pending_loan_request() TO authenticated;
GRANT ALL ON FUNCTION public.one_pending_loan_request() TO service_role;


--
-- Name: FUNCTION pay_loan_installment(p_installment_id uuid, p_amount numeric, p_method text, p_note text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pay_loan_installment(p_installment_id uuid, p_amount numeric, p_method text, p_note text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pay_loan_installment(p_installment_id uuid, p_amount numeric, p_method text, p_note text) TO authenticated;
GRANT ALL ON FUNCTION public.pay_loan_installment(p_installment_id uuid, p_amount numeric, p_method text, p_note text) TO service_role;


--
-- Name: FUNCTION payroll_basic_salary(p_employee_id uuid, p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_basic_salary(p_employee_id uuid, p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_basic_salary(p_employee_id uuid, p_month text) TO service_role;


--
-- Name: FUNCTION payroll_cleanup_preview(p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_cleanup_preview(p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_cleanup_preview(p_month text) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_cleanup_preview(p_month text) TO service_role;


--
-- Name: FUNCTION payroll_cleanup_run(p_month text, p_attendance boolean, p_tracking boolean, p_notifications boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_cleanup_run(p_month text, p_attendance boolean, p_tracking boolean, p_notifications boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_cleanup_run(p_month text, p_attendance boolean, p_tracking boolean, p_notifications boolean) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_cleanup_run(p_month text, p_attendance boolean, p_tracking boolean, p_notifications boolean) TO service_role;


--
-- Name: FUNCTION payroll_daily_rate(p_employee_id uuid, p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_daily_rate(p_employee_id uuid, p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_daily_rate(p_employee_id uuid, p_month text) TO service_role;


--
-- Name: FUNCTION payroll_day_frozen(p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_day_frozen(p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_day_frozen(p_date date) TO service_role;


--
-- Name: FUNCTION payroll_day_rates(p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_day_rates(p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_day_rates(p_date date) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_day_rates(p_date date) TO service_role;


--
-- Name: FUNCTION payroll_employee_summary(p_employee_id uuid, p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_employee_summary(p_employee_id uuid, p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_employee_summary(p_employee_id uuid, p_month text) TO service_role;


--
-- Name: FUNCTION payroll_hourly_leave_overlap(p_employee_id uuid, p_date date, p_from numeric, p_to numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_hourly_leave_overlap(p_employee_id uuid, p_date date, p_from numeric, p_to numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_hourly_leave_overlap(p_employee_id uuid, p_date date, p_from numeric, p_to numeric) TO service_role;


--
-- Name: FUNCTION payroll_legacy_slip(p_employee_id uuid, p_month text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_legacy_slip(p_employee_id uuid, p_month text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_legacy_slip(p_employee_id uuid, p_month text) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_legacy_slip(p_employee_id uuid, p_month text) TO service_role;


--
-- Name: FUNCTION payroll_legacy_slip(p_employee_id uuid, p_month text, p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_legacy_slip(p_employee_id uuid, p_month text, p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_legacy_slip(p_employee_id uuid, p_month text, p_date date) TO service_role;


--
-- Name: FUNCTION payroll_local_minutes(p_ts timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_local_minutes(p_ts timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_local_minutes(p_ts timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_local_minutes(p_ts timestamp with time zone) TO service_role;


--
-- Name: FUNCTION payroll_month_add(p_month text, p_n integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_month_add(p_month text, p_n integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_month_add(p_month text, p_n integer) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_month_add(p_month text, p_n integer) TO service_role;


--
-- Name: FUNCTION payroll_month_of(p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_month_of(p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_month_of(p_date date) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_month_of(p_date date) TO service_role;


--
-- Name: FUNCTION payroll_natural_month(p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_natural_month(p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_natural_month(p_date date) TO service_role;


--
-- Name: FUNCTION payroll_nightly(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_nightly() FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_nightly() TO service_role;


--
-- Name: FUNCTION payroll_policy(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_policy() FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_policy() TO service_role;


--
-- Name: FUNCTION payroll_same_branch(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_same_branch(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_same_branch(p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_same_branch(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION payroll_schedule(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_schedule(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_schedule(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION payroll_schedule_at(p_employee_id uuid, p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_schedule_at(p_employee_id uuid, p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_schedule_at(p_employee_id uuid, p_date date) TO service_role;


--
-- Name: FUNCTION payroll_shift_minutes(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_shift_minutes(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_shift_minutes(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION payroll_shift_minutes_at(p_employee_id uuid, p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_shift_minutes_at(p_employee_id uuid, p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_shift_minutes_at(p_employee_id uuid, p_date date) TO service_role;


--
-- Name: FUNCTION payroll_target_month(p_employee_id uuid, p_natural text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_target_month(p_employee_id uuid, p_natural text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_target_month(p_employee_id uuid, p_natural text) TO service_role;


--
-- Name: FUNCTION payroll_time_minutes(p_t time without time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.payroll_time_minutes(p_t time without time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.payroll_time_minutes(p_t time without time zone) TO authenticated;
GRANT ALL ON FUNCTION public.payroll_time_minutes(p_t time without time zone) TO service_role;


--
-- Name: FUNCTION perform_daily_cleanup(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.perform_daily_cleanup() FROM PUBLIC;
GRANT ALL ON FUNCTION public.perform_daily_cleanup() TO authenticated;
GRANT ALL ON FUNCTION public.perform_daily_cleanup() TO service_role;


--
-- Name: FUNCTION postpone_loan_installment(p_installment_id uuid, p_note text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.postpone_loan_installment(p_installment_id uuid, p_note text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.postpone_loan_installment(p_installment_id uuid, p_note text) TO authenticated;
GRANT ALL ON FUNCTION public.postpone_loan_installment(p_installment_id uuid, p_note text) TO service_role;


--
-- Name: FUNCTION protect_attendance_decisions(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.protect_attendance_decisions() FROM PUBLIC;
GRANT ALL ON FUNCTION public.protect_attendance_decisions() TO authenticated;
GRANT ALL ON FUNCTION public.protect_attendance_decisions() TO service_role;


--
-- Name: FUNCTION protect_attendance_times(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.protect_attendance_times() FROM PUBLIC;
GRANT ALL ON FUNCTION public.protect_attendance_times() TO authenticated;
GRANT ALL ON FUNCTION public.protect_attendance_times() TO service_role;


--
-- Name: FUNCTION protect_employee_columns(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.protect_employee_columns() FROM PUBLIC;
GRANT ALL ON FUNCTION public.protect_employee_columns() TO authenticated;
GRANT ALL ON FUNCTION public.protect_employee_columns() TO service_role;


--
-- Name: FUNCTION protect_leave_decisions(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.protect_leave_decisions() FROM PUBLIC;
GRANT ALL ON FUNCTION public.protect_leave_decisions() TO authenticated;
GRANT ALL ON FUNCTION public.protect_leave_decisions() TO service_role;


--
-- Name: FUNCTION publish_announcement(p_title text, p_content text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_target text, p_branch_id uuid, p_employee_ids uuid[], p_pinned boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.publish_announcement(p_title text, p_content text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_target text, p_branch_id uuid, p_employee_ids uuid[], p_pinned boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.publish_announcement(p_title text, p_content text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_target text, p_branch_id uuid, p_employee_ids uuid[], p_pinned boolean) TO authenticated;
GRANT ALL ON FUNCTION public.publish_announcement(p_title text, p_content text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_target text, p_branch_id uuid, p_employee_ids uuid[], p_pinned boolean) TO service_role;


--
-- Name: FUNCTION punch_attendance(p_type text, p_latitude double precision, p_longitude double precision, p_device_id text, p_is_mocked boolean, p_client_time timestamp with time zone, p_accuracy double precision, p_trusted_time timestamp with time zone, p_time_check text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.punch_attendance(p_type text, p_latitude double precision, p_longitude double precision, p_device_id text, p_is_mocked boolean, p_client_time timestamp with time zone, p_accuracy double precision, p_trusted_time timestamp with time zone, p_time_check text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.punch_attendance(p_type text, p_latitude double precision, p_longitude double precision, p_device_id text, p_is_mocked boolean, p_client_time timestamp with time zone, p_accuracy double precision, p_trusted_time timestamp with time zone, p_time_check text) TO authenticated;
GRANT ALL ON FUNCTION public.punch_attendance(p_type text, p_latitude double precision, p_longitude double precision, p_device_id text, p_is_mocked boolean, p_client_time timestamp with time zone, p_accuracy double precision, p_trusted_time timestamp with time zone, p_time_check text) TO service_role;


--
-- Name: FUNCTION purge_old_assistant_conversations(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.purge_old_assistant_conversations() FROM PUBLIC;
GRANT ALL ON FUNCTION public.purge_old_assistant_conversations() TO service_role;


--
-- Name: FUNCTION purge_old_location_tracking(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.purge_old_location_tracking() FROM PUBLIC;
GRANT ALL ON FUNCTION public.purge_old_location_tracking() TO service_role;


--
-- Name: FUNCTION purge_system_logs(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.purge_system_logs() FROM PUBLIC;
GRANT ALL ON FUNCTION public.purge_system_logs() TO service_role;


--
-- Name: FUNCTION reactivate_employee(p_employee_id uuid, p_return_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reactivate_employee(p_employee_id uuid, p_return_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reactivate_employee(p_employee_id uuid, p_return_date date) TO authenticated;
GRANT ALL ON FUNCTION public.reactivate_employee(p_employee_id uuid, p_return_date date) TO service_role;


--
-- Name: FUNCTION record_audit_log(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.record_audit_log() FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_audit_log() TO authenticated;
GRANT ALL ON FUNCTION public.record_audit_log() TO service_role;


--
-- Name: FUNCTION record_employee_assignment(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.record_employee_assignment() FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_employee_assignment() TO authenticated;
GRANT ALL ON FUNCTION public.record_employee_assignment() TO service_role;


--
-- Name: FUNCTION record_salary_history(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.record_salary_history() FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_salary_history() TO authenticated;
GRANT ALL ON FUNCTION public.record_salary_history() TO service_role;


--
-- Name: FUNCTION record_work_schedule_history(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.record_work_schedule_history() FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_work_schedule_history() TO service_role;


--
-- Name: FUNCTION register_device_login(p_device_id text, p_model text, p_os_version text, p_legacy_device_id text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.register_device_login(p_device_id text, p_model text, p_os_version text, p_legacy_device_id text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.register_device_login(p_device_id text, p_model text, p_os_version text, p_legacy_device_id text) TO authenticated;
GRANT ALL ON FUNCTION public.register_device_login(p_device_id text, p_model text, p_os_version text, p_legacy_device_id text) TO service_role;


--
-- Name: FUNCTION reject_future_attendance(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reject_future_attendance() FROM PUBLIC;
GRANT ALL ON FUNCTION public.reject_future_attendance() TO authenticated;
GRANT ALL ON FUNCTION public.reject_future_attendance() TO service_role;


--
-- Name: FUNCTION reject_negative_salary_slip(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reject_negative_salary_slip() FROM PUBLIC;
GRANT ALL ON FUNCTION public.reject_negative_salary_slip() TO authenticated;
GRANT ALL ON FUNCTION public.reject_negative_salary_slip() TO service_role;


--
-- Name: FUNCTION reopen_payroll_period(p_month text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reopen_payroll_period(p_month text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reopen_payroll_period(p_month text, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.reopen_payroll_period(p_month text, p_reason text) TO service_role;


--
-- Name: FUNCTION request_account_deletion(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.request_account_deletion() FROM PUBLIC;
GRANT ALL ON FUNCTION public.request_account_deletion() TO authenticated;
GRANT ALL ON FUNCTION public.request_account_deletion() TO service_role;


--
-- Name: FUNCTION require_admin(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.require_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION public.require_admin() TO authenticated;
GRANT ALL ON FUNCTION public.require_admin() TO service_role;


--
-- Name: FUNCTION require_admin_or_manager(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.require_admin_or_manager() FROM PUBLIC;
GRANT ALL ON FUNCTION public.require_admin_or_manager() TO authenticated;
GRANT ALL ON FUNCTION public.require_admin_or_manager() TO service_role;


--
-- Name: FUNCTION require_admin_or_system(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.require_admin_or_system() FROM PUBLIC;
GRANT ALL ON FUNCTION public.require_admin_or_system() TO authenticated;
GRANT ALL ON FUNCTION public.require_admin_or_system() TO service_role;


--
-- Name: FUNCTION reschedule_loan(p_loan_id uuid, p_amount numeric, p_installment_amount numeric, p_count integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.reschedule_loan(p_loan_id uuid, p_amount numeric, p_installment_amount numeric, p_count integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.reschedule_loan(p_loan_id uuid, p_amount numeric, p_installment_amount numeric, p_count integer) TO authenticated;
GRANT ALL ON FUNCTION public.reschedule_loan(p_loan_id uuid, p_amount numeric, p_installment_amount numeric, p_count integer) TO service_role;


--
-- Name: FUNCTION restore_archived_employee(p_archive_id uuid, p_return_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.restore_archived_employee(p_archive_id uuid, p_return_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.restore_archived_employee(p_archive_id uuid, p_return_date date) TO authenticated;
GRANT ALL ON FUNCTION public.restore_archived_employee(p_archive_id uuid, p_return_date date) TO service_role;


--
-- Name: FUNCTION resync_payroll_on_salary_change(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.resync_payroll_on_salary_change() FROM PUBLIC;
GRANT ALL ON FUNCTION public.resync_payroll_on_salary_change() TO authenticated;
GRANT ALL ON FUNCTION public.resync_payroll_on_salary_change() TO service_role;


--
-- Name: FUNCTION revert_payroll_slip(p_slip_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.revert_payroll_slip(p_slip_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.revert_payroll_slip(p_slip_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.revert_payroll_slip(p_slip_id uuid) TO service_role;


--
-- Name: FUNCTION revert_salary_slip(p_slip_id uuid, p_period_start date, p_period_end date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.revert_salary_slip(p_slip_id uuid, p_period_start date, p_period_end date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.revert_salary_slip(p_slip_id uuid, p_period_start date, p_period_end date) TO authenticated;
GRANT ALL ON FUNCTION public.revert_salary_slip(p_slip_id uuid, p_period_start date, p_period_end date) TO service_role;


--
-- Name: FUNCTION safe_archive_payroll_month(target_month text, cycle_start_day integer, cycle_end_day integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.safe_archive_payroll_month(target_month text, cycle_start_day integer, cycle_end_day integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.safe_archive_payroll_month(target_month text, cycle_start_day integer, cycle_end_day integer) TO authenticated;
GRANT ALL ON FUNCTION public.safe_archive_payroll_month(target_month text, cycle_start_day integer, cycle_end_day integer) TO service_role;


--
-- Name: FUNCTION safe_delete_employee(p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.safe_delete_employee(p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.safe_delete_employee(p_employee_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.safe_delete_employee(p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION save_employee(p_employee_id uuid, p_email text, p_password text, p_phone text, p_changes jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.save_employee(p_employee_id uuid, p_email text, p_password text, p_phone text, p_changes jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.save_employee(p_employee_id uuid, p_email text, p_password text, p_phone text, p_changes jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.save_employee(p_employee_id uuid, p_email text, p_password text, p_phone text, p_changes jsonb) TO service_role;


--
-- Name: FUNCTION send_assistant_morning_summary(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.send_assistant_morning_summary() FROM PUBLIC;
GRANT ALL ON FUNCTION public.send_assistant_morning_summary() TO service_role;


--
-- Name: FUNCTION send_idempotent_notification(p_employee_id uuid, p_title text, p_body text, p_type text, p_dedup_window_minutes integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.send_idempotent_notification(p_employee_id uuid, p_title text, p_body text, p_type text, p_dedup_window_minutes integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.send_idempotent_notification(p_employee_id uuid, p_title text, p_body text, p_type text, p_dedup_window_minutes integer) TO authenticated;
GRANT ALL ON FUNCTION public.send_idempotent_notification(p_employee_id uuid, p_title text, p_body text, p_type text, p_dedup_window_minutes integer) TO service_role;


--
-- Name: FUNCTION server_now(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.server_now() FROM PUBLIC;
GRANT ALL ON FUNCTION public.server_now() TO authenticated;
GRANT ALL ON FUNCTION public.server_now() TO service_role;


--
-- Name: FUNCTION set_employee_leave_entitlement(p_employee_id uuid, p_annual numeric, p_sick numeric, p_hourly_monthly_hours numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_employee_leave_entitlement(p_employee_id uuid, p_annual numeric, p_sick numeric, p_hourly_monthly_hours numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_employee_leave_entitlement(p_employee_id uuid, p_annual numeric, p_sick numeric, p_hourly_monthly_hours numeric) TO authenticated;
GRANT ALL ON FUNCTION public.set_employee_leave_entitlement(p_employee_id uuid, p_annual numeric, p_sick numeric, p_hourly_monthly_hours numeric) TO service_role;


--
-- Name: FUNCTION set_month_installment(p_installment_id uuid, p_amount numeric, p_note text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_month_installment(p_installment_id uuid, p_amount numeric, p_note text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_month_installment(p_installment_id uuid, p_amount numeric, p_note text) TO authenticated;
GRANT ALL ON FUNCTION public.set_month_installment(p_installment_id uuid, p_amount numeric, p_note text) TO service_role;


--
-- Name: FUNCTION set_payroll_policy(p_cutoff_day integer, p_payment_day integer, p_overtime_enabled boolean, p_overtime_multiplier numeric, p_overtime_min_minutes integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_payroll_policy(p_cutoff_day integer, p_payment_day integer, p_overtime_enabled boolean, p_overtime_multiplier numeric, p_overtime_min_minutes integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_payroll_policy(p_cutoff_day integer, p_payment_day integer, p_overtime_enabled boolean, p_overtime_multiplier numeric, p_overtime_min_minutes integer) TO authenticated;
GRANT ALL ON FUNCTION public.set_payroll_policy(p_cutoff_day integer, p_payment_day integer, p_overtime_enabled boolean, p_overtime_multiplier numeric, p_overtime_min_minutes integer) TO service_role;


--
-- Name: FUNCTION set_termination_date(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.set_termination_date() FROM PUBLIC;
GRANT ALL ON FUNCTION public.set_termination_date() TO authenticated;
GRANT ALL ON FUNCTION public.set_termination_date() TO service_role;


--
-- Name: FUNCTION settle_loan_on_exit(p_employee_id uuid, p_month text, p_amount numeric); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.settle_loan_on_exit(p_employee_id uuid, p_month text, p_amount numeric) FROM PUBLIC;
GRANT ALL ON FUNCTION public.settle_loan_on_exit(p_employee_id uuid, p_month text, p_amount numeric) TO authenticated;
GRANT ALL ON FUNCTION public.settle_loan_on_exit(p_employee_id uuid, p_month text, p_amount numeric) TO service_role;


--
-- Name: FUNCTION sync_geofence_coordinates(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sync_geofence_coordinates() FROM PUBLIC;
GRANT ALL ON FUNCTION public.sync_geofence_coordinates() TO authenticated;
GRANT ALL ON FUNCTION public.sync_geofence_coordinates() TO service_role;


--
-- Name: FUNCTION sync_geofences_to_branches(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sync_geofences_to_branches() FROM PUBLIC;
GRANT ALL ON FUNCTION public.sync_geofences_to_branches() TO authenticated;
GRANT ALL ON FUNCTION public.sync_geofences_to_branches() TO service_role;


--
-- Name: FUNCTION sync_payroll_day(p_employee_id uuid, p_date date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sync_payroll_day(p_employee_id uuid, p_date date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sync_payroll_day(p_employee_id uuid, p_date date) TO service_role;


--
-- Name: FUNCTION sync_payroll_manual(p_bd_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sync_payroll_manual(p_bd_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sync_payroll_manual(p_bd_id uuid) TO service_role;


--
-- Name: FUNCTION sync_payroll_period(p_month text, p_employee_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.sync_payroll_period(p_month text, p_employee_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.sync_payroll_period(p_month text, p_employee_id uuid) TO service_role;


--
-- Name: FUNCTION track_attendance_time_source(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.track_attendance_time_source() FROM PUBLIC;
GRANT ALL ON FUNCTION public.track_attendance_time_source() TO authenticated;
GRANT ALL ON FUNCTION public.track_attendance_time_source() TO service_role;


--
-- Name: FUNCTION trash_removed_employee_files(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trash_removed_employee_files() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trash_removed_employee_files() TO service_role;


--
-- Name: FUNCTION trg_payroll_attendance(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_payroll_attendance() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_payroll_attendance() TO authenticated;
GRANT ALL ON FUNCTION public.trg_payroll_attendance() TO service_role;


--
-- Name: FUNCTION trg_payroll_holiday(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_payroll_holiday() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_payroll_holiday() TO service_role;


--
-- Name: FUNCTION trg_payroll_leave(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_payroll_leave() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_payroll_leave() TO authenticated;
GRANT ALL ON FUNCTION public.trg_payroll_leave() TO service_role;


--
-- Name: FUNCTION trg_payroll_manual(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.trg_payroll_manual() FROM PUBLIC;
GRANT ALL ON FUNCTION public.trg_payroll_manual() TO authenticated;
GRANT ALL ON FUNCTION public.trg_payroll_manual() TO service_role;


--
-- Name: FUNCTION update_employee_credentials(p_employee_id uuid, p_email text, p_password text, p_phone text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_employee_credentials(p_employee_id uuid, p_email text, p_password text, p_phone text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_employee_credentials(p_employee_id uuid, p_email text, p_password text, p_phone text) TO authenticated;
GRANT ALL ON FUNCTION public.update_employee_credentials(p_employee_id uuid, p_email text, p_password text, p_phone text) TO service_role;


--
-- Name: FUNCTION update_loan_and_installments_trigger(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_loan_and_installments_trigger() FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_loan_and_installments_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.update_loan_and_installments_trigger() TO service_role;


--
-- Name: FUNCTION validate_leave_request(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.validate_leave_request() FROM PUBLIC;
GRANT ALL ON FUNCTION public.validate_leave_request() TO authenticated;
GRANT ALL ON FUNCTION public.validate_leave_request() TO service_role;


--
-- Name: TABLE app_versions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.app_versions TO anon;
GRANT ALL ON TABLE public.app_versions TO authenticated;
GRANT ALL ON TABLE public.app_versions TO service_role;


--
-- Name: TABLE archived_employees; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.archived_employees TO anon;
GRANT ALL ON TABLE public.archived_employees TO authenticated;
GRANT ALL ON TABLE public.archived_employees TO service_role;


--
-- Name: TABLE archived_months; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.archived_months TO anon;
GRANT ALL ON TABLE public.archived_months TO authenticated;
GRANT ALL ON TABLE public.archived_months TO service_role;


--
-- Name: TABLE assistant_conversations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.assistant_conversations TO authenticated;
GRANT ALL ON TABLE public.assistant_conversations TO service_role;


--
-- Name: TABLE assistant_messages; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.assistant_messages TO authenticated;
GRANT ALL ON TABLE public.assistant_messages TO service_role;


--
-- Name: TABLE attendance_reminder_log; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.attendance_reminder_log TO service_role;


--
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.audit_log TO anon;
GRANT ALL ON TABLE public.audit_log TO authenticated;
GRANT ALL ON TABLE public.audit_log TO service_role;


--
-- Name: TABLE bonuses_deductions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.bonuses_deductions TO anon;
GRANT ALL ON TABLE public.bonuses_deductions TO authenticated;
GRANT ALL ON TABLE public.bonuses_deductions TO service_role;


--
-- Name: TABLE branches; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.branches TO anon;
GRANT ALL ON TABLE public.branches TO authenticated;
GRANT ALL ON TABLE public.branches TO service_role;


--
-- Name: TABLE cleanup_run_tokens; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.cleanup_run_tokens TO service_role;


--
-- Name: TABLE company_settings; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.company_settings TO anon;
GRANT ALL ON TABLE public.company_settings TO authenticated;
GRANT ALL ON TABLE public.company_settings TO service_role;


--
-- Name: TABLE deleted_files; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.deleted_files TO anon;
GRANT ALL ON TABLE public.deleted_files TO authenticated;
GRANT ALL ON TABLE public.deleted_files TO service_role;


--
-- Name: TABLE departments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.departments TO anon;
GRANT ALL ON TABLE public.departments TO authenticated;
GRANT ALL ON TABLE public.departments TO service_role;


--
-- Name: TABLE device_tokens; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.device_tokens TO anon;
GRANT ALL ON TABLE public.device_tokens TO authenticated;
GRANT ALL ON TABLE public.device_tokens TO service_role;


--
-- Name: TABLE employee_assignment_history; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.employee_assignment_history TO anon;
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.employee_assignment_history TO authenticated;
GRANT ALL ON TABLE public.employee_assignment_history TO service_role;


--
-- Name: TABLE employee_devices; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.employee_devices TO anon;
GRANT ALL ON TABLE public.employee_devices TO authenticated;
GRANT ALL ON TABLE public.employee_devices TO service_role;


--
-- Name: TABLE employee_geofence_assignments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.employee_geofence_assignments TO anon;
GRANT ALL ON TABLE public.employee_geofence_assignments TO authenticated;
GRANT ALL ON TABLE public.employee_geofence_assignments TO service_role;


--
-- Name: TABLE employee_service_breaks; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.employee_service_breaks TO anon;
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.employee_service_breaks TO authenticated;
GRANT ALL ON TABLE public.employee_service_breaks TO service_role;


--
-- Name: TABLE employees; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE public.employees TO anon;
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE public.employees TO authenticated;
GRANT ALL ON TABLE public.employees TO service_role;


--
-- Name: COLUMN employees.id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(id) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.employee_code; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(employee_code) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.full_name; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(full_name) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.phone; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(phone) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.email; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(email) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.avatar_url; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(avatar_url) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.is_active; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(is_active) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.role; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(role) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.department_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(department_id) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.branch_id; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(branch_id) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.created_at; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(created_at) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.join_date; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(join_date) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.device_id_lock; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(device_id_lock) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.fcm_token; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(fcm_token) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.must_change_password; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(must_change_password) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.document_urls; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(document_urls) ON TABLE public.employees TO authenticated;


--
-- Name: COLUMN employees.termination_date; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT(termination_date) ON TABLE public.employees TO authenticated;


--
-- Name: TABLE fcm_tokens; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.fcm_tokens TO anon;
GRANT ALL ON TABLE public.fcm_tokens TO authenticated;
GRANT ALL ON TABLE public.fcm_tokens TO service_role;


--
-- Name: TABLE geofence_violations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.geofence_violations TO anon;
GRANT ALL ON TABLE public.geofence_violations TO authenticated;
GRANT ALL ON TABLE public.geofence_violations TO service_role;


--
-- Name: TABLE geofence_zones; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.geofence_zones TO anon;
GRANT ALL ON TABLE public.geofence_zones TO authenticated;
GRANT ALL ON TABLE public.geofence_zones TO service_role;


--
-- Name: TABLE leave_balances; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.leave_balances TO anon;
GRANT ALL ON TABLE public.leave_balances TO authenticated;
GRANT ALL ON TABLE public.leave_balances TO service_role;


--
-- Name: TABLE loan_installments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.loan_installments TO anon;
GRANT ALL ON TABLE public.loan_installments TO authenticated;
GRANT ALL ON TABLE public.loan_installments TO service_role;


--
-- Name: TABLE loans; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.loans TO anon;
GRANT ALL ON TABLE public.loans TO authenticated;
GRANT ALL ON TABLE public.loans TO service_role;


--
-- Name: TABLE location_tracking; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.location_tracking TO anon;
GRANT ALL ON TABLE public.location_tracking TO authenticated;
GRANT ALL ON TABLE public.location_tracking TO service_role;


--
-- Name: TABLE mock_gps_attempts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.mock_gps_attempts TO anon;
GRANT ALL ON TABLE public.mock_gps_attempts TO authenticated;
GRANT ALL ON TABLE public.mock_gps_attempts TO service_role;


--
-- Name: TABLE notifications; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.notifications TO anon;
GRANT ALL ON TABLE public.notifications TO authenticated;
GRANT ALL ON TABLE public.notifications TO service_role;


--
-- Name: TABLE official_holidays; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.official_holidays TO anon;
GRANT ALL ON TABLE public.official_holidays TO authenticated;
GRANT ALL ON TABLE public.official_holidays TO service_role;


--
-- Name: TABLE payroll_cleanups; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.payroll_cleanups TO authenticated;
GRANT ALL ON TABLE public.payroll_cleanups TO service_role;


--
-- Name: TABLE payroll_loan_caps; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.payroll_loan_caps TO anon;
GRANT ALL ON TABLE public.payroll_loan_caps TO authenticated;
GRANT ALL ON TABLE public.payroll_loan_caps TO service_role;


--
-- Name: TABLE salary_history; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.salary_history TO authenticated;
GRANT ALL ON TABLE public.salary_history TO service_role;


--
-- Name: TABLE salary_slip_lines; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.salary_slip_lines TO anon;
GRANT ALL ON TABLE public.salary_slip_lines TO authenticated;
GRANT ALL ON TABLE public.salary_slip_lines TO service_role;


--
-- Name: TABLE salary_slips; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.salary_slips TO anon;
GRANT ALL ON TABLE public.salary_slips TO authenticated;
GRANT ALL ON TABLE public.salary_slips TO service_role;


--
-- Name: TABLE settled_loans; Type: ACL; Schema: public; Owner: -
--

GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.settled_loans TO authenticated;
GRANT ALL ON TABLE public.settled_loans TO service_role;


--
-- Name: TABLE system_settings; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.system_settings TO anon;
GRANT ALL ON TABLE public.system_settings TO authenticated;
GRANT ALL ON TABLE public.system_settings TO service_role;


--
-- Name: TABLE tracked_stops; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tracked_stops TO anon;
GRANT ALL ON TABLE public.tracked_stops TO authenticated;
GRANT ALL ON TABLE public.tracked_stops TO service_role;


--
-- Name: TABLE tracking_schedules; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.tracking_schedules TO anon;
GRANT ALL ON TABLE public.tracking_schedules TO authenticated;
GRANT ALL ON TABLE public.tracking_schedules TO service_role;


--
-- Name: TABLE v_attendance_with_employee; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_attendance_with_employee TO authenticated;
GRANT ALL ON TABLE public.v_attendance_with_employee TO service_role;


--
-- Name: TABLE v_device_requests; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_device_requests TO authenticated;
GRANT ALL ON TABLE public.v_device_requests TO service_role;


--
-- Name: TABLE v_employee_directory; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_employee_directory TO authenticated;
GRANT ALL ON TABLE public.v_employee_directory TO service_role;


--
-- Name: TABLE v_leaves_with_employee; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_leaves_with_employee TO service_role;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,UPDATE ON TABLE public.v_leaves_with_employee TO authenticated;


--
-- Name: TABLE v_loans_summary; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_loans_summary TO authenticated;
GRANT ALL ON TABLE public.v_loans_summary TO service_role;


--
-- Name: TABLE v_payroll_with_employee; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_payroll_with_employee TO authenticated;
GRANT ALL ON TABLE public.v_payroll_with_employee TO service_role;


--
-- Name: TABLE v_security_incidents; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.v_security_incidents TO authenticated;
GRANT ALL ON TABLE public.v_security_incidents TO service_role;


--
-- Name: TABLE work_schedule_history; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.work_schedule_history TO anon;
GRANT ALL ON TABLE public.work_schedule_history TO authenticated;
GRANT ALL ON TABLE public.work_schedule_history TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--


-- =========================================================================
-- برا الجزء الرئيسي: نفس اللي سوته الملفات القديمة
-- =========================================================================

-- يوم بداية الحساب = يوم بناء القاعدة (مثل 20260929000000_payroll_engine.sql)
UPDATE public.system_settings SET value = value || jsonb_build_object('no_record_from', to_char((now() AT TIME ZONE 'Asia/Baghdad')::date, 'YYYY-MM-DD'))
WHERE key = 'payroll_policy' AND NOT (value ? 'no_record_from');

-- تخزين الملفات
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('avatars', 'avatars', true, 1048576, ARRAY['image/jpeg', 'image/png', 'image/webp']::text[])
  ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, public = EXCLUDED.public, file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('company-logos', 'company-logos', true, 2097152, ARRAY['image/jpeg', 'image/png', 'image/webp']::text[])
  ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, public = EXCLUDED.public, file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('documents', 'documents', false, 10485760, NULL)
  ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, public = EXCLUDED.public, file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('loan-pledges', 'loan-pledges', false, 2097152, ARRAY['image/jpeg', 'image/png', 'image/webp']::text[])
  ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, public = EXCLUDED.public, file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES ('ota-updates', 'ota-updates', true, 104857600, ARRAY['application/vnd.android.package-archive', 'application/octet-stream']::text[])
  ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, public = EXCLUDED.public, file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;

-- صلاحيات تخزين الملفات
DROP POLICY IF EXISTS "Admins can manage documents" ON storage.objects;
CREATE POLICY "Admins can manage documents" ON storage.objects AS PERMISSIVE FOR ALL TO authenticated
  USING (((bucket_id = 'documents'::text) AND public.is_admin()));
DROP POLICY IF EXISTS "Admins can manage employee-documents" ON storage.objects;
CREATE POLICY "Admins can manage employee-documents" ON storage.objects AS PERMISSIVE FOR ALL TO authenticated
  USING (((bucket_id = 'employee-documents'::text) AND public.is_admin()));
DROP POLICY IF EXISTS "Admins can view and manage loan pledges" ON storage.objects;
CREATE POLICY "Admins can view and manage loan pledges" ON storage.objects AS PERMISSIVE FOR ALL TO authenticated
  USING (((bucket_id = 'loan-pledges'::text) AND public.is_admin()));
DROP POLICY IF EXISTS "Avatars are public" ON storage.objects;
CREATE POLICY "Avatars are public" ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
  USING ((bucket_id = 'avatars'::text));
DROP POLICY IF EXISTS "Employees can add own documents" ON storage.objects;
CREATE POLICY "Employees can add own documents" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((bucket_id = 'employee-documents'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
DROP POLICY IF EXISTS "Employees can delete own documents" ON storage.objects;
CREATE POLICY "Employees can delete own documents" ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING (((bucket_id = 'documents'::text) AND (owner = auth.uid())));
DROP POLICY IF EXISTS "Employees can delete own loan pledges" ON storage.objects;
CREATE POLICY "Employees can delete own loan pledges" ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING (((bucket_id = 'loan-pledges'::text) AND ((storage.foldername(name))[2] = (auth.uid())::text)));
DROP POLICY IF EXISTS "Employees can update own documents" ON storage.objects;
CREATE POLICY "Employees can update own documents" ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((bucket_id = 'documents'::text) AND (owner = auth.uid())));
DROP POLICY IF EXISTS "Employees can update own loan pledges" ON storage.objects;
CREATE POLICY "Employees can update own loan pledges" ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((bucket_id = 'loan-pledges'::text) AND ((storage.foldername(name))[2] = (auth.uid())::text)))
  WITH CHECK (((bucket_id = 'loan-pledges'::text) AND ((storage.foldername(name))[2] = (auth.uid())::text)));
DROP POLICY IF EXISTS "Employees can upload loan pledges" ON storage.objects;
CREATE POLICY "Employees can upload loan pledges" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((bucket_id = 'loan-pledges'::text) AND (owner = auth.uid())));
DROP POLICY IF EXISTS "Employees can upload own documents" ON storage.objects;
CREATE POLICY "Employees can upload own documents" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((bucket_id = 'documents'::text) AND ((owner = auth.uid()) OR public.is_admin())));
DROP POLICY IF EXISTS "Employees can upload own leave attachments" ON storage.objects;
CREATE POLICY "Employees can upload own leave attachments" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((bucket_id = 'employee-documents'::text) AND ((storage.foldername(name))[1] = 'leaves'::text) AND ((storage.foldername(name))[2] = (auth.uid())::text)));
DROP POLICY IF EXISTS "Employees can view own documents" ON storage.objects;
CREATE POLICY "Employees can view own documents" ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
  USING (((bucket_id = 'documents'::text) AND ((owner = auth.uid()) OR public.is_admin())));
DROP POLICY IF EXISTS "Employees can view own employee-documents" ON storage.objects;
CREATE POLICY "Employees can view own employee-documents" ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
  USING (((bucket_id = 'employee-documents'::text) AND (((storage.foldername(name))[1] = (auth.uid())::text) OR public.is_admin())));
DROP POLICY IF EXISTS "Employees can view own loan pledges" ON storage.objects;
CREATE POLICY "Employees can view own loan pledges" ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
  USING (((bucket_id = 'loan-pledges'::text) AND ((storage.foldername(name))[2] = (auth.uid())::text)));
DROP POLICY IF EXISTS "Leave attachments visible to owner and branch managers" ON storage.objects;
CREATE POLICY "Leave attachments visible to owner and branch managers" ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
  USING (((bucket_id = 'employee-documents'::text) AND ((storage.foldername(name))[1] = 'leaves'::text) AND (((storage.foldername(name))[2] = (auth.uid())::text) OR ((storage.foldername(name))[2] = ANY ((( SELECT public.managed_employee_ids() AS managed_employee_ids))::text[])))));
DROP POLICY IF EXISTS "Logos are public" ON storage.objects;
CREATE POLICY "Logos are public" ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
  USING ((bucket_id = 'company-logos'::text));
DROP POLICY IF EXISTS "OTA updates are public" ON storage.objects;
CREATE POLICY "OTA updates are public" ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
  USING ((bucket_id = 'ota-updates'::text));
DROP POLICY IF EXISTS "Only admins can delete employee-documents" ON storage.objects;
CREATE POLICY "Only admins can delete employee-documents" ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING (((bucket_id = 'employee-documents'::text) AND public.is_admin()));
DROP POLICY IF EXISTS "Only admins can manage company logos" ON storage.objects;
CREATE POLICY "Only admins can manage company logos" ON storage.objects AS PERMISSIVE FOR ALL TO authenticated
  USING (((bucket_id = 'company-logos'::text) AND public.is_admin()))
  WITH CHECK (((bucket_id = 'company-logos'::text) AND public.is_admin()));
DROP POLICY IF EXISTS "Only admins can upload OTA updates" ON storage.objects;
CREATE POLICY "Only admins can upload OTA updates" ON storage.objects AS PERMISSIVE FOR ALL TO authenticated
  USING (((bucket_id = 'ota-updates'::text) AND public.is_admin()))
  WITH CHECK (((bucket_id = 'ota-updates'::text) AND public.is_admin()));
DROP POLICY IF EXISTS "Users can delete their own avatars" ON storage.objects;
CREATE POLICY "Users can delete their own avatars" ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING (((bucket_id = 'avatars'::text) AND (owner = auth.uid())));
DROP POLICY IF EXISTS "Users can update their own avatars" ON storage.objects;
CREATE POLICY "Users can update their own avatars" ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((bucket_id = 'avatars'::text) AND (owner = auth.uid())));
DROP POLICY IF EXISTS "Users upload avatars into their own folder" ON storage.objects;
CREATE POLICY "Users upload avatars into their own folder" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((bucket_id = 'avatars'::text) AND (((storage.foldername(name))[1] = (auth.uid())::text) OR public.is_admin())));

-- التحديث المباشر (Realtime)
DO $realtime$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['attendance', 'leave_requests', 'loans', 'location_tracking', 'notifications'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication_tables
                   WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END
$realtime$;

-- المهام المجدولة
SELECT cron.schedule('assistant_conversations_cleanup', '30 3 * * *', $cron$ SELECT public.purge_old_assistant_conversations(); $cron$);
SELECT cron.schedule('assistant_morning_summary', '0 7 * * *', $cron$ SELECT public.send_assistant_morning_summary(); $cron$);
SELECT cron.schedule('attendance_reminders_every_minute', '* * * * *', $cron$ SELECT public.check_and_send_attendance_reminders(); $cron$);
SELECT cron.schedule('daily_cleanup', '0 3 * * *', $cron$ SELECT public.perform_daily_cleanup(); $cron$);
SELECT cron.schedule('daily_trash_storage_cleanup', '15 3 * * *', $cron$
  SELECT net.http_post(
    url := 'https://jgjlmddphhncatrhqrej.supabase.co/functions/v1/daily-cleanup',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cleanup-token', public.issue_cleanup_token()::text),
    body := '{}'::jsonb
  );
$cron$);
SELECT cron.schedule('payroll_nightly', '15 21 * * *', $cron$ SELECT public.payroll_nightly(); $cron$);
SELECT cron.schedule('system_logs_cleanup', '45 3 * * *', $cron$ SELECT public.purge_system_logs(); $cron$);

-- إعدادات الجلسة ترجع مثل Supabase (pg_dump غيّرها فوق) حتى الملفات اللي بعده تشتغل عادي
SELECT pg_catalog.set_config('search_path', '"$user", public, extensions', false);
RESET check_function_bodies;
RESET client_min_messages;
RESET row_security;
RESET xmloption;
RESET statement_timeout;
RESET lock_timeout;
RESET idle_in_transaction_session_timeout;
RESET transaction_timeout;
