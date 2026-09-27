-- =========================================================================
-- HR Pro v6.0 — البصمة وقفل الجهاز يُحسبان في السيرفر
-- Date: 2026-09-24
-- =========================================================================
--
-- قبل هذا الملف كان التطبيق يكتب في جدول attendance مباشرة، وكل الفحوصات
-- (المسافة من الفرع، الوقت، حالة التأخير، الجهاز المعتمد) تتم على الموبايل.
-- أي موظف يقدر يرسل بصمة بأي وقت ومكان عبر الـ API. وبصمة الانصراف كانت
-- تفشل بصمت لأن سياسة UPDATE على attendance للأدمن/المدير فقط.
--
-- الآن:
--   • punch_attendance()         — المصدر الوحيد لبصمة الموظف
--   • register_device_login()    — منطق قفل الجهاز الواحد
--   • get_effective_work_schedule() — جدول الدوام الفعلي بأولوية واضحة
--     (الموظف ← القسم ← الفرع) تستعمله البصمة والتتبع معاً
--   • الموظف لم يعد يملك INSERT على attendance ولا كتابة على employee_devices
-- =========================================================================


-- =====================================================================
-- 1) أعمدة جديدة
-- =====================================================================

-- البصمات التي سُجّلت بدون إنترنت ثم رُفعت لاحقاً (وقتها من ساعة الجهاز)
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS check_in_offline  BOOLEAN DEFAULT false NOT NULL;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS check_out_offline BOOLEAN DEFAULT false NOT NULL;

COMMENT ON COLUMN attendance.check_in_offline IS
'TRUE إذا سُجّلت بصمة الحضور بدون إنترنت ورُفعت لاحقاً — الوقت مأخوذ من ساعة الجهاز ويحتاج مراجعة.';


-- =====================================================================
-- 2) دوال مساعدة
-- =====================================================================

-- المنطقة الزمنية للشركة (قابلة للتغيير من system_settings: key = 'timezone')
CREATE OR REPLACE FUNCTION public.company_timezone()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT value #>> '{}' FROM system_settings WHERE key = 'timezone'),
    'Asia/Baghdad'
  );
$$;

-- المسافة بالمتر بين نقطتين (Haversine)
CREATE OR REPLACE FUNCTION public.distance_meters(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision
)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- جدول الدوام الفعلي للموظف: الخاص به ← جدول قسمه ← جدول فرعه (الأحدث عند التساوي)
CREATE OR REPLACE FUNCTION public.get_effective_work_schedule(p_employee_id uuid DEFAULT NULL)
RETURNS SETOF work_schedules
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_emp_id uuid := COALESCE(p_employee_id, auth.uid());
BEGIN
  IF auth.uid() IS NOT NULL AND v_emp_id <> auth.uid()
     AND NOT (public.is_admin() OR public.is_manager()) THEN
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


-- =====================================================================
-- 3) punch_attendance — بصمة الحضور/الانصراف
--
-- يرجع jsonb:
--   { ok: true,  status, work_date, check_in_time, check_out_time, offline, distance_m }
--   { ok: false, code, message }   ← رفض منطقي (خارج النطاق، مكرر، موقع وهمي...)
-- أخطاء الصلاحية (غير مسجل، حساب معطل، جهاز غير معتمد) تُرمى كاستثناء.
--
-- p_client_time: يُرسل فقط لبصمة أوفلاين تُرفع لاحقاً. يُقبل إذا كان خلال آخر
-- 48 ساعة وليس في المستقبل، وتُعلَّم البصمة offline لمراجعة الإدارة.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.punch_attendance(
  p_type text,
  p_latitude double precision,
  p_longitude double precision,
  p_device_id text DEFAULT NULL,
  p_is_mocked boolean DEFAULT false,
  p_client_time timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- هامش تسامح لفرق حساب المسافة بين الجهاز والسيرفر
  c_distance_tolerance_m constant double precision := 10;
  c_offline_max_age constant interval := interval '48 hours';

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

  -- الوقت: وقت السيرفر، أو وقت الجهاز لبصمة أوفلاين ضمن حدود معقولة
  IF p_client_time IS NULL THEN
    v_time := v_now;
  ELSE
    IF p_client_time > v_now + interval '5 minutes' THEN
      RETURN jsonb_build_object('ok', false, 'code', 'clock_in_future',
        'message', 'وقت البصمة المحفوظة في المستقبل — ساعة الجهاز غير مضبوطة.');
    END IF;
    IF p_client_time < v_now - c_offline_max_age THEN
      RETURN jsonb_build_object('ok', false, 'code', 'offline_too_old',
        'message', 'البصمة المحفوظة أقدم من 48 ساعة ولا يمكن قبولها. راجع الإدارة.');
    END IF;
    v_time := p_client_time;
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
          check_in_offline = v_offline, status = v_status
      WHERE id = v_att.id
      RETURNING * INTO v_att;
    ELSE
      INSERT INTO attendance (employee_id, branch_id, work_date, status,
                              check_in_time, check_in_lat, check_in_lng, check_in_offline)
      VALUES (v_uid, v_branch.id, v_work_date, v_status,
              v_time, p_latitude, p_longitude, v_offline)
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
                              check_out_time, check_out_lat, check_out_lng, check_out_offline)
      VALUES (v_uid, v_branch.id, v_work_date, 'half_day',
              v_time, p_latitude, p_longitude, v_offline)
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
          check_out_offline = v_offline, status = v_status
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
    CASE p_type WHEN 'check_in' THEN 'بصمة حضور ناجحة 🟢' ELSE 'بصمة انصراف ناجحة 🔴' END,
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
    'distance_m', round(v_distance::numeric, 1)
  );
END;
$$;


-- =====================================================================
-- 4) register_device_login — قفل الجهاز الواحد (كان كله في التطبيق)
--
-- يرجع { ok: true } أو { ok: false, code: 'device_locked' }.
-- p_legacy_device_id: المعرّف القديم المولّد عشوائياً في SharedPreferences.
-- إذا كان الحساب مقفولاً عليه، يُنقل القفل للمعرّف الجديد الثابت تلقائياً
-- حتى لا ينقفل الموظفون الحاليون بعد التحديث.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.register_device_login(
  p_device_id text,
  p_model text DEFAULT NULL,
  p_os_version text DEFAULT NULL,
  p_legacy_device_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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


-- =====================================================================
-- 5) صلاحيات الجداول — الكتابة عبر الدوال فقط
-- =====================================================================

-- attendance: الموظف لا يكتب مباشرة (الأدمن يصحح من لوحة التحكم)
DROP POLICY IF EXISTS "Employees can punch their own attendance" ON attendance;
DROP POLICY IF EXISTS "Only admins can insert attendance" ON attendance;
CREATE POLICY "Only admins can insert attendance"
ON attendance FOR INSERT TO authenticated
WITH CHECK (is_admin());

-- employee_devices: الموظف يقرأ أجهزته فقط (كان يقدر يعتمد جهازه بنفسه)
DROP POLICY IF EXISTS "Employees can view and insert their own devices" ON employee_devices;
DROP POLICY IF EXISTS "Employees can view their own devices" ON employee_devices;
CREATE POLICY "Employees can view their own devices"
ON employee_devices FOR SELECT TO authenticated
USING (employee_id = auth.uid() OR is_admin());


-- =====================================================================
-- 6) EXECUTE
-- =====================================================================

REVOKE EXECUTE ON FUNCTION
  public.company_timezone(),
  public.distance_meters(double precision, double precision, double precision, double precision),
  public.get_effective_work_schedule(uuid),
  public.punch_attendance(text, double precision, double precision, text, boolean, timestamptz),
  public.register_device_login(text, text, text, text)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.company_timezone(),
  public.distance_meters(double precision, double precision, double precision, double precision),
  public.get_effective_work_schedule(uuid),
  public.punch_attendance(text, double precision, double precision, text, boolean, timestamptz),
  public.register_device_login(text, text, text, text)
TO authenticated, service_role;
