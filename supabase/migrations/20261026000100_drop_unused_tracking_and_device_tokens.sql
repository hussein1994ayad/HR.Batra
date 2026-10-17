-- =========================================================================
-- HR Pro — حذف جداول ما يستعملها شي (المرحلة 10 الجزء الثاني، تدقيق 14/10 CODE-006 و CODE-007)
-- Date: 2026-10-17
-- Related: audit stage 10 | stage 9 (20261024000000_stage9_cleanup.sql)
-- =========================================================================
--
-- • tracking_schedules و employee_geofence_assignments: فارغة، والتطبيق من المرحلة 9 ما يقراهن.
-- • device_tokens: المكان القديم الثاني لرمز الإشعارات؛ التطبيق من المرحلة 9 يكتب بـ fcm_tokens بس،
--   وأي رمز باقي بيه ينتقل لـ fcm_tokens قبل الحذف (نفس نقل المرحلة 9).
-- • عمود employees.fcm_token ودالة النقل منه يبقون (الجزء الثالث): النسخة الحالية من التطبيق بعدها تقرا العمود.
--
-- الشرط (قرار صاحب الشركة 17/10/2026): كل الموبايلات عليها نسخة المرحلة 9 أو أحدث قبل التطبيق على السيرفر.
-- الحذف محمي: إذا جدول التتبع أو السياج بيه بيانات، يوكف وما يحذف شي.
-- =========================================================================

DO $$
BEGIN
  IF to_regclass('public.tracking_schedules') IS NOT NULL AND EXISTS (SELECT 1 FROM public.tracking_schedules) THEN
    RAISE EXCEPTION 'tracking_schedules بيه بيانات — ما ينحذف';
  END IF;
  IF to_regclass('public.employee_geofence_assignments') IS NOT NULL AND EXISTS (SELECT 1 FROM public.employee_geofence_assignments) THEN
    RAISE EXCEPTION 'employee_geofence_assignments بيه بيانات — ما ينحذف';
  END IF;
END $$;

DROP TABLE IF EXISTS public.tracking_schedules;
DROP TABLE IF EXISTS public.employee_geofence_assignments;

-- رموز device_tokens الباقية تنتقل للمكان الواحد قبل الحذف
DO $$
BEGIN
  IF to_regclass('public.device_tokens') IS NOT NULL THEN
    INSERT INTO public.fcm_tokens (employee_id, token, device_platform)
    SELECT d.employee_id, d.token, d.platform FROM public.device_tokens d
    WHERE d.employee_id IS NOT NULL AND NULLIF(btrim(d.token), '') IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.employees e WHERE e.id = d.employee_id)
    ON CONFLICT (employee_id, token) DO NOTHING;
  END IF;
END $$;

-- إخفاء هوية الموظف المحذوف: نفس الدالة بدون مسح device_tokens (الجدول انحذف)
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

  -- حذف الحساب من المصادقة
  DELETE FROM auth.users WHERE id = p_employee_id;
END;
$function$;

-- الـ trigger اللي ينقل منه ينحذف وياه
DROP TABLE IF EXISTS public.device_tokens;
