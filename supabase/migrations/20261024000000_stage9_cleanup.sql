-- =====================================================================
-- المرحلة 9 (الجزء أ) من إصلاحات تدقيق 14/10/2026: تنظيف وترتيب. ما يتغير أي مبلغ ولا حساب.
-- (CODE-013) الراتب الافتراضي المخفي 600,000 ينشال: إضافة موظف بدون راتب صارت خطأ واضح.
-- (CODE-008) فهرسين مكررين ينحذفون، وفهرس ناقص لأقساط السلفة.
-- (CODE-006) جداول وأعمدة ميتة (فارغة وما يستعملها شي): documents، branch_schedules، orphan_storage_candidates_cache
--   ومهمتها الأسبوعية الفاضية، employees.plain_password (كان ينمسح دائماً)، leave_balances.annual_used/sick_used
--   (الرصيد ينحسب من الطلبات). tracking_schedules و employee_geofence_assignments تبقى لحد ما تتحدث كل نسخ التطبيق.
-- (CODE-007) رمز الإشعارات بمكان واحد (fcm_tokens): النسخ القديمة من التطبيق تكتب بمكانين ثانيين، فينتقل منها تلقائياً.
-- (CODE-003) دالة حساب اليوم انقسمت لأربع دوال صغيرة بنفس النص ونفس النتائج.
-- =====================================================================

-- ---------------------------------------------------------------------
-- (CODE-013) بدون راتب افتراضي
-- ---------------------------------------------------------------------
ALTER TABLE public.employees ALTER COLUMN monthly_salary_iqd DROP DEFAULT;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.employees WHERE monthly_salary_iqd IS NULL) THEN
    ALTER TABLE public.employees ALTER COLUMN monthly_salary_iqd SET NOT NULL;
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- (CODE-008) الفهارس
-- ---------------------------------------------------------------------
DROP INDEX IF EXISTS public.idx_attendance_employee_date;      -- نفس القيد الفريد (employee_id, work_date)
DROP INDEX IF EXISTS public.idx_salary_slips_employee_month;   -- نفس القيد الفريد (employee_id, work_month)
CREATE INDEX IF NOT EXISTS idx_loan_installments_loan ON public.loan_installments (loan_id, due_date);

-- ---------------------------------------------------------------------
-- (CODE-006) الجداول الميتة: تنحذف بس إذا فارغة (ما ينحذف أي سطر)
-- ---------------------------------------------------------------------
DO $$
DECLARE
  t text;
  n bigint;
BEGIN
  FOREACH t IN ARRAY ARRAY['documents', 'branch_schedules', 'orphan_storage_candidates_cache'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n;
      IF n > 0 THEN
        RAISE EXCEPTION 'الجدول % بيه % سطر: التحديث توقف (ما ينحذف شي بيه بيانات).', t, n;
      END IF;
    END IF;
  END LOOP;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'weekly_orphan_candidates_refresh') THEN
    PERFORM cron.unschedule('weekly_orphan_candidates_refresh');
  END IF;
END $$;
DROP FUNCTION IF EXISTS public.refresh_orphan_candidates_cache();
DROP TABLE IF EXISTS public.orphan_storage_candidates_cache;
DROP TABLE IF EXISTS public.branch_schedules;
DROP TABLE IF EXISTS public.documents;

-- أعمدة رصيد الإجازات المستخدم (الرصيد ينحسب من الطلبات بـ get_leave_balance)
ALTER TABLE public.leave_balances DROP COLUMN IF EXISTS annual_used;
ALTER TABLE public.leave_balances DROP COLUMN IF EXISTS sick_used;

-- كلمة السر المكشوفة: ما تنحفظ أصلاً (trigger يمسحها)، فالعمود والـ trigger ينشالون والدوال ما تذكرها
CREATE OR REPLACE FUNCTION public._anonymize_employee(p_employee_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.update_employee_credentials(p_employee_id uuid, p_email text, p_password text DEFAULT NULL::text, p_phone text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.create_employee_secure(p_email text, p_password text, p_full_name text, p_phone text, p_role text, p_branch_id uuid, p_monthly_salary_iqd numeric, p_document_urls text[], p_employee_code text, p_employee_id uuid DEFAULT NULL::uuid, p_join_date date DEFAULT NULL::date, p_department_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
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
$function$;

DROP TRIGGER IF EXISTS trg_strip_plain_password ON public.employees;
DROP FUNCTION IF EXISTS public.strip_plain_password();
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.employees WHERE plain_password IS NOT NULL) THEN
    RAISE EXCEPTION 'عمود plain_password بيه قيم: التحديث توقف.';
  END IF;
END $$;
ALTER TABLE public.employees DROP COLUMN IF EXISTS plain_password;

-- ---------------------------------------------------------------------
-- (CODE-007) رمز الإشعارات بمكان واحد: fcm_tokens
-- ---------------------------------------------------------------------
INSERT INTO public.fcm_tokens (employee_id, token)
SELECT e.id, e.fcm_token FROM public.employees e WHERE NULLIF(btrim(e.fcm_token), '') IS NOT NULL
ON CONFLICT (employee_id, token) DO NOTHING;
INSERT INTO public.fcm_tokens (employee_id, token, device_platform)
SELECT d.employee_id, d.token, d.platform FROM public.device_tokens d
WHERE d.employee_id IS NOT NULL AND NULLIF(btrim(d.token), '') IS NOT NULL
  AND EXISTS (SELECT 1 FROM public.employees e WHERE e.id = d.employee_id)
ON CONFLICT (employee_id, token) DO NOTHING;

-- النسخ القديمة من التطبيق تكتب الرمز بـ employees.fcm_token و device_tokens: ينتقل لـ fcm_tokens تلقائياً
CREATE OR REPLACE FUNCTION public.copy_legacy_push_token()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
REVOKE ALL ON FUNCTION public.copy_legacy_push_token() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_copy_legacy_push_token ON public.employees;
CREATE TRIGGER trg_copy_legacy_push_token AFTER UPDATE OF fcm_token ON public.employees
  FOR EACH ROW WHEN (NEW.fcm_token IS NOT NULL AND NEW.fcm_token IS DISTINCT FROM OLD.fcm_token)
  EXECUTE FUNCTION public.copy_legacy_push_token();
DROP TRIGGER IF EXISTS trg_copy_legacy_push_token ON public.device_tokens;
CREATE TRIGGER trg_copy_legacy_push_token AFTER INSERT OR UPDATE ON public.device_tokens
  FOR EACH ROW EXECUTE FUNCTION public.copy_legacy_push_token();

-- ---------------------------------------------------------------------
-- (CODE-003) حساب اليوم بأربع دوال صغيرة (النص منقول بدون تغيير)، والدالة الأصلية ترتبها
-- ---------------------------------------------------------------------
-- حركات يوم فيه سجل حضور: غياب مسجّل، بصمة ناقصة، تأخير، خروج مبكر، إضافي (تكتب بـ _pd)
CREATE OR REPLACE FUNCTION public._payroll_day_attendance_events(p_employee_id uuid, p_date date, p_att attendance, p_sched work_schedules, p_workday boolean, p_daily numeric, p_minute numeric, p_policy jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
REVOKE ALL ON FUNCTION public._payroll_day_attendance_events(uuid, date, attendance, work_schedules, boolean, numeric, numeric, jsonb) FROM PUBLIC, anon, authenticated;

-- يوم بدون سجل حضور: إجازة يومية معتمدة، وإلا غياب ينتظر قرار (تكتب بـ _pd)
CREATE OR REPLACE FUNCTION public._payroll_day_leave_events(p_employee_id uuid, p_date date, p_workday boolean, p_daily numeric, p_policy jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
REVOKE ALL ON FUNCTION public._payroll_day_leave_events(uuid, date, boolean, numeric, jsonb) FROM PUBLIC, anon, authenticated;

-- الإجازات الزمنية المعتمدة باليوم (ما تنحسب فوق يوم كامل محسوب) (تكتب بـ _pd)
CREATE OR REPLACE FUNCTION public._payroll_day_hourly_leaves(p_employee_id uuid, p_date date, p_minute numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
REVOKE ALL ON FUNCTION public._payroll_day_hourly_leaves(uuid, date, numeric) FROM PUBLIC, anon, authenticated;

-- يطابق حركات اليوم بالقاعدة ويا المطلوب (_pd): يلغي اللي ما عادت مطلوبة، وينشئ أو يحدّث الباقي
CREATE OR REPLACE FUNCTION public._payroll_day_apply(p_employee_id uuid, p_date date, p_natural text, p_daily numeric, p_minute numeric, p_policy jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
REVOKE ALL ON FUNCTION public._payroll_day_apply(uuid, date, text, numeric, numeric, jsonb) FROM PUBLIC, anon, authenticated;

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
$function$;
