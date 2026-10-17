-- =====================================================================
-- المرحلة 2 من إصلاحات تدقيق 14/10/2026: البصمة بدون إنترنت (BUG-001، FEATURE-004).
-- كان وقت البصمة المحفوظة بدون إنترنت = ساعة الموبايل، والسيرفر يقبله إذا خلال 48 ساعة: وضع الطيران + تغيير الساعة
-- يخفي التأخير والخروج المبكر، وما اكو أي علامة للإدارة.
-- هسه:
--   • التطبيق يحفظ آخر وقت سيرفر (server_now أو رد البصمة) مع عدّاد الموبايل منذ التشغيل (ما يتأثر بتغيير الساعة
--     ولا بإطفاء الشاشة)، ويحسب منها وقت البصمة الحقيقي. هذا الوقت «مؤكد» (offline_verified).
--   • إذا ما يكدر يحسبه (تطبيق قديم، الموبايل انطفى وشغل، ما اكو وقت سيرفر سابق): ساعة الموبايل + «يحتاج مراجعة».
--   • وقت ساعة الموبايل ينحفظ دائماً للبصمة بدون إنترنت، حتى الإدارة تقارن (فرق كبير = الساعة متغيّرة).
--   • تعديل الإدارة للوقت = «يدوي». «تمت المراجعة» من الأدمن أو مدير الفرع (mark_offline_punch_reviewed)، وينسجل.
-- =====================================================================

ALTER TABLE public.attendance
  ADD COLUMN IF NOT EXISTS check_in_time_source text,
  ADD COLUMN IF NOT EXISTS check_out_time_source text,
  ADD COLUMN IF NOT EXISTS check_in_device_time timestamptz,
  ADD COLUMN IF NOT EXISTS check_out_device_time timestamptz;

ALTER TABLE public.attendance DROP CONSTRAINT IF EXISTS attendance_time_source_check;
ALTER TABLE public.attendance ADD CONSTRAINT attendance_time_source_check CHECK (
  (check_in_time_source IS NULL OR check_in_time_source IN ('online', 'offline_verified', 'offline_review', 'offline_reviewed', 'manual'))
  AND (check_out_time_source IS NULL OR check_out_time_source IN ('online', 'offline_verified', 'offline_review', 'offline_reviewed', 'manual')));

COMMENT ON COLUMN public.attendance.check_in_time_source IS
  'online | offline_verified (محسوب من وقت السيرفر وعدّاد الموبايل) | offline_review (ساعة الموبايل، يحتاج مراجعة) | offline_reviewed | manual';
COMMENT ON COLUMN public.attendance.check_in_device_time IS 'وقت ساعة الموبايل لبصمة محفوظة بدون إنترنت (للمقارنة).';

-- الأيام القديمة: البصمة بدون إنترنت قبل هذا التحديث وقتها من ساعة الموبايل بدون تحقق
UPDATE public.attendance SET check_in_time_source = 'offline_review'
WHERE check_in_offline AND check_in_time IS NOT NULL AND check_in_time_source IS NULL;
UPDATE public.attendance SET check_out_time_source = 'offline_review'
WHERE check_out_offline AND check_out_time IS NOT NULL AND check_out_time_source IS NULL;

-- وقت السيرفر: التطبيق يحفظه ويا عدّاد الموبايل حتى يحسب وقت البصمة لو انقطع الإنترنت
CREATE OR REPLACE FUNCTION public.server_now()
 RETURNS timestamptz
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$ SELECT now(); $function$;
REVOKE ALL ON FUNCTION public.server_now() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.server_now() TO authenticated;

-- البصمة: نفس الدالة + الوقت المؤكد ومصدره (توقيع جديد بمعاملين اختياريين؛ التطبيق القديم يكمل يشتغل)
DROP FUNCTION IF EXISTS public.punch_attendance(text, double precision, double precision, text, boolean, timestamp with time zone, double precision);
CREATE OR REPLACE FUNCTION public.punch_attendance(p_type text, p_latitude double precision, p_longitude double precision, p_device_id text DEFAULT NULL::text, p_is_mocked boolean DEFAULT false, p_client_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_accuracy double precision DEFAULT NULL::double precision, p_trusted_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_time_check text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
REVOKE ALL ON FUNCTION public.punch_attendance(text, double precision, double precision, text, boolean, timestamp with time zone, double precision, timestamp with time zone, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.punch_attendance(text, double precision, double precision, text, boolean, timestamp with time zone, double precision, timestamp with time zone, text) TO authenticated;

-- مصدر الوقت: تعديل الإدارة للوقت = «يدوي»؛ وقت الموبايل ما يتغير؛ المصدر يتغير بس «يحتاج مراجعة» ← «تمت المراجعة»
CREATE OR REPLACE FUNCTION public.track_attendance_time_source()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
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
$function$;
DROP TRIGGER IF EXISTS trg_track_attendance_time_source ON public.attendance;
CREATE TRIGGER trg_track_attendance_time_source BEFORE INSERT OR UPDATE ON public.attendance
  FOR EACH ROW EXECUTE FUNCTION public.track_attendance_time_source();

-- «تمت المراجعة» لبصمة بدون إنترنت: الأدمن أو مدير الفرع (مو على نفسه)، وينسجل منو ومتى
CREATE OR REPLACE FUNCTION public.mark_offline_punch_reviewed(p_attendance_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
REVOKE ALL ON FUNCTION public.mark_offline_punch_reviewed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_offline_punch_reviewed(uuid) TO authenticated;
