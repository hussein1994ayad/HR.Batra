-- =========================================================================
-- نظام HR Pro v6.0 - ملف الهجرة الشامل والتصحيحي (Comprehensive Schema & RPC Fixes)
-- Date: 2026-07-02
-- =========================================================================

-- 1. إضافة الأعمدة المفقودة لجدول جداول العمل (work_schedules)
ALTER TABLE public.work_schedules 
ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.branches(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_work_schedules_branch_id ON public.work_schedules(branch_id);

-- 2. إضافة عمود حالة التفعيل لمناطق السياج الجغرافي (geofence_zones)
ALTER TABLE public.geofence_zones 
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true NOT NULL;

-- 3. تصحيح دالة safe_delete_employee لمنع خطأ نوع البيانات (jsonb vs text[])
CREATE OR REPLACE FUNCTION public.safe_delete_employee(p_employee_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_role TEXT;
BEGIN
  -- التحقق من هوية وصلاحية المستدعي
  v_caller_id := auth.uid();
  IF v_caller_id IS NOT NULL THEN
    SELECT role INTO v_caller_role FROM public.employees WHERE id = v_caller_id;
    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'manager') THEN
      RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية. يجب أن تكون مديراً أو مشرفاً عاماً.';
    END IF;
  END IF;

  -- التحقق من وجود الموظف
  IF NOT EXISTS (SELECT 1 FROM public.employees WHERE id = p_employee_id) THEN
    RAISE EXCEPTION 'الموظف المطلوب غير موجود في النظام.';
  END IF;

  -- إخفاء هوية الموظف في جدول الموظفين وتصفير مستنداته بأمان
  UPDATE public.employees
  SET 
    full_name = 'مستخدم محذوف',
    phone = NULL,
    email = 'deleted_' || substring(p_employee_id::text from 1 for 8) || '@deleted.com',
    avatar_url = NULL,
    is_active = false,
    plain_password = NULL,
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

-- 4. تحديث وتوسيع دالة إنشاء الموظف بأمان (create_employee_secure) لتشمل القسم والتحويل الآمن للمستندات
CREATE OR REPLACE FUNCTION public.create_employee_secure(
  p_email text,
  p_password text,
  p_full_name text,
  p_phone text,
  p_role text,
  p_branch_id uuid,
  p_monthly_salary_iqd numeric,
  p_document_urls text[],
  p_employee_code text,
  p_employee_id uuid DEFAULT NULL,
  p_join_date date DEFAULT NULL,
  p_department_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  new_user_id uuid;
  new_identity_id uuid;
  hashed_password text;
BEGIN
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
    plain_password,
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
    p_password,
    true,
    true,
    to_jsonb(COALESCE(p_document_urls, ARRAY[]::text[])),
    COALESCE(p_join_date, CURRENT_DATE),
    now()
  );

  RETURN new_user_id;
END;
$function$;

-- 5. تصحيح دالة تفريغ بيانات الشهر (manual_purge_month_data)
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
  v_start_date := make_date(p_year, p_month, 1);
  v_end_date := (v_start_date + INTERVAL '1 month' - INTERVAL '1 day')::date;

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
    WITH del_att AS (
      DELETE FROM public.attendance
      WHERE work_date >= v_start_date AND work_date <= v_end_date
      RETURNING id
    )
    SELECT count(*)::integer INTO v_absent_count FROM del_att;
  END IF;

  RETURN QUERY SELECT v_notif_count, v_track_count, v_stops_count, v_viol_count, v_absent_count;
END;
$function$;

-- 6. توحيد وتحديث دالة التنظيف اليومي (perform_daily_cleanup)
CREATE OR REPLACE FUNCTION public.perform_daily_cleanup()
RETURNS TABLE (expired_file_path TEXT, expired_bucket_id TEXT, file_record_id UUID) AS $$
DECLARE
  archive_record RECORD;
  tracking_archive_days INT;
BEGIN
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
    'تنبيه: سيتم حذف بيانات الموظف (' || full_name || ') نهائياً وبشكل كامل في تاريخ ' || TO_CHAR(scheduled_deletion_date, 'YYYY-MM-DD') || '.',
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
    DELETE FROM public.employees WHERE id = archive_record.employee_id;
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. تحديث Storage RLS لـ employee-documents ليدعم المسارات المتداخلة وجميع الحالات بأمان
DROP POLICY IF EXISTS "Admins can manage employee-documents" ON storage.objects;
DROP POLICY IF EXISTS "Employees can view own employee-documents" ON storage.objects;
DROP POLICY IF EXISTS "Employees can upload own employee-documents" ON storage.objects;
DROP POLICY IF EXISTS "Employees can update own employee-documents" ON storage.objects;
DROP POLICY IF EXISTS "Employees can delete own employee-documents" ON storage.objects;

CREATE POLICY "Admins can manage employee-documents" ON storage.objects
  TO authenticated USING (bucket_id = 'employee-documents' AND is_admin());

CREATE POLICY "Employees can view own employee-documents" ON storage.objects
  FOR SELECT TO authenticated USING (
    bucket_id = 'employee-documents' AND (
      (storage.foldername(name))[1] = (auth.uid())::text 
      OR is_admin()
    )
  );

CREATE POLICY "Employees can upload own employee-documents" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (
    bucket_id = 'employee-documents' AND (
      (storage.foldername(name))[1] = (auth.uid())::text 
      OR is_admin()
    )
  );

CREATE POLICY "Employees can update own employee-documents" ON storage.objects
  FOR UPDATE TO authenticated USING (
    bucket_id = 'employee-documents' AND (
      (storage.foldername(name))[1] = (auth.uid())::text 
      OR is_admin()
    )
  );

CREATE POLICY "Employees can delete own employee-documents" ON storage.objects
  FOR DELETE TO authenticated USING (
    bucket_id = 'employee-documents' AND (
      (storage.foldername(name))[1] = (auth.uid())::text 
      OR is_admin()
    )
  );
