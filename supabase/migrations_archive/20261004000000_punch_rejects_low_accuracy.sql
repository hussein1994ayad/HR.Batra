-- =========================================================================
-- البصمة ترفض الموقع التقريبي/الضعيف (فحص التوافق #4)
-- =========================================================================
-- أندرويد 12+ وiOS 14+ يسمحون بموقع "تقريبي" يبعد كيلومترات؛ كانت البصمة تُقبل إذا
-- وقعت النقطة المشوّشة داخل النطاق. التطبيق صار يرسل دقة الـ GPS (p_accuracy) والسيرفر
-- يرفض أي دقة أسوأ من 100 م (أو نطاق الفرع إذا أوسع). المعامل اختياري فالنسخ القديمة تشتغل.
-- الدالة منسوخة من 20260930000200 كما هي؛ التغيير الوحيد المعامل الجديد والفحص.
-- =========================================================================
DROP FUNCTION IF EXISTS public.punch_attendance(text, double precision, double precision, text, boolean, timestamptz);

CREATE OR REPLACE FUNCTION public.punch_attendance(p_type text, p_latitude double precision, p_longitude double precision, p_device_id text DEFAULT NULL::text, p_is_mocked boolean DEFAULT false, p_client_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_accuracy double precision DEFAULT NULL::double precision)
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
    CASE WHEN p_type = 'check_out' THEN 'بصمة انصراف ناجحة 🔴'
         WHEN v_att.status = 'late' THEN 'بصمة حضور متأخرة 🟠'
         ELSE 'بصمة حضور ناجحة 🟢' END,
    CASE p_type
      WHEN 'check_in' THEN CASE WHEN v_att.status = 'late'
        THEN format('تم تسجيل حضورك في فرع (%s) بعد بداية الدوام، ويُحتسب تأخيراً.', v_branch.name)
        ELSE format('تم تسجيل حضورك اليوم بنجاح في فرع (%s). دواماً موفقاً!', v_branch.name) END
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
$function$;

REVOKE EXECUTE ON FUNCTION public.punch_attendance(text, double precision, double precision, text, boolean, timestamptz, double precision) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.punch_attendance(text, double precision, double precision, text, boolean, timestamptz, double precision) TO authenticated, service_role;
