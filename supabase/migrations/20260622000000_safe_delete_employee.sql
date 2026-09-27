-- =========================================================================
-- دالة الحذف الآمن للموظفين (Safe Employee Deletion & Anonymization)
-- تمنع الفقدان المتسلسل للبيانات (Cascade Data Loss) في الجداول المالية والدوام
-- =========================================================================

CREATE OR REPLACE FUNCTION public.safe_delete_employee(p_employee_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER -- تشغيل الدالة بصلاحيات المشرف لتتمكن من القراءة والحذف من auth.users
SET search_path = public, auth
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_role TEXT;
BEGIN
  -- 1. التحقق من هوية وصلاحية مستدعي الدالة (يجب أن يكون مدير عام أو مشرف)
  v_caller_id := auth.uid();
  IF v_caller_id IS NOT NULL THEN
    SELECT role INTO v_caller_role FROM public.employees WHERE id = v_caller_id;
    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'manager') THEN
      RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية. يجب أن تكون مديراً أو مشرفاً عاماً.';
    END IF;
  END IF;

  -- 2. التحقق من وجود الموظف المراد حذفه
  IF NOT EXISTS (SELECT 1 FROM public.employees WHERE id = p_employee_id) THEN
    RAISE EXCEPTION 'الموظف المطلوب غير موجود في النظام.';
  END If;

  -- 3. إخفاء هوية الموظف في جدول الموظفين العام وتصفير بياناته الحساسة
  UPDATE public.employees
  SET 
    full_name = 'مستخدم محذوف',
    phone = NULL,
    email = 'deleted_' || substring(p_employee_id::text from 1 for 8) || '@deleted.com',
    avatar_url = NULL,
    is_active = false,
    plain_password = NULL,
    document_urls = ARRAY[]::TEXT[]
  WHERE id = p_employee_id;

  -- 4. إزالة الهواتف المقرنة ورموز الإشعارات (Cascade items are cleaned manually here)
  DELETE FROM public.employee_devices WHERE employee_id = p_employee_id;
  DELETE FROM public.fcm_tokens WHERE employee_id = p_employee_id;

  -- 5. حذف الحساب نهائياً من جدول auth.users
  DELETE FROM auth.users WHERE id = p_employee_id;

END;
$$;

COMMENT ON FUNCTION public.safe_delete_employee IS 'تقوم بحذف حساب الموظف من المصادقة وتصفير بياناته الشخصية مع إبقاء سجلاته التاريخية للحماية من Cascade Data Loss';
