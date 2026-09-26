-- =========================================================================
-- نظام HR Pro v6.0 - ملف تأمين وحماية الصلاحيات وسياسات RLS
-- Migration: 20260703000000_security_and_rls_hardening.sql
-- =========================================================================

-- 1. تأمين دالة إنشاء الموظف create_employee_secure (التحقق من صلاحية Admin)
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


-- 2. تأمين دالة الحذف الآمن safe_delete_employee
CREATE OR REPLACE FUNCTION public.safe_delete_employee(p_employee_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_id UUID;
  v_caller_role TEXT;
  v_target_role TEXT;
BEGIN
  -- التحقق من هوية المستدعي (يجب ألا يكون فارغاً ويجب أن يكون أدمن أو مدير)
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح: يجب تسجيل الدخول لتنفيذ هذا الإجراء.';
  END IF;

  SELECT role INTO v_caller_role FROM public.employees WHERE id = v_caller_id;
  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'manager') THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية. يجب أن تكون مديراً أو مشرفاً عاماً.';
  END IF;

  -- التحقق من وجود الموظف ومعرفة دوره
  SELECT role INTO v_target_role FROM public.employees WHERE id = p_employee_id;
  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'الموظف المطلوب غير موجود في النظام.';
  END IF;

  -- حماية حسابات الأدمن: لا يمكن لغير الأدمن حذف حساب أدمن
  IF v_target_role = 'admin' AND v_caller_role != 'admin' THEN
    RAISE EXCEPTION 'غير مصرح: لا يمكن لمدير عادي حذف حساب مسؤول نظام (Admin).';
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


-- 3. فصل وإحكام سياسات RLS لجدول الحضور (attendance)
DROP POLICY IF EXISTS "Employees can manage their own attendance" ON attendance;
DROP POLICY IF EXISTS "Admins and managers can view all attendance records" ON attendance;

CREATE POLICY "Employees can view own attendance and managers view all"
ON attendance FOR SELECT TO authenticated
USING (employee_id = auth.uid() OR is_admin() OR is_manager());

CREATE POLICY "Employees can punch their own attendance"
ON attendance FOR INSERT TO authenticated
WITH CHECK (employee_id = auth.uid() OR is_admin());

CREATE POLICY "Only admins and managers can update attendance"
ON attendance FOR UPDATE TO authenticated
USING (is_admin() OR is_manager())
WITH CHECK (is_admin() OR is_manager());

CREATE POLICY "Only admins can delete attendance"
ON attendance FOR DELETE TO authenticated
USING (is_admin());


-- 4. فصل وإحكام سياسات RLS لجدول الإجازات (leave_requests)
DROP POLICY IF EXISTS "Employees can view and create their own leave requests" ON leave_requests;
DROP POLICY IF EXISTS "Admins and managers can view and process leave requests" ON leave_requests;

CREATE POLICY "Employees can view own leaves and managers view all"
ON leave_requests FOR SELECT TO authenticated
USING (employee_id = auth.uid() OR is_admin() OR is_manager());

CREATE POLICY "Employees can submit their own leave requests"
ON leave_requests FOR INSERT TO authenticated
WITH CHECK (employee_id = auth.uid() AND (status = 'pending' OR status IS NULL));

CREATE POLICY "Admins and managers can approve or reject leave requests"
ON leave_requests FOR UPDATE TO authenticated
USING (is_admin() OR is_manager())
WITH CHECK (is_admin() OR is_manager());

CREATE POLICY "Employees can cancel their pending leave requests"
ON leave_requests FOR UPDATE TO authenticated
USING (employee_id = auth.uid() AND status = 'pending')
WITH CHECK (employee_id = auth.uid() AND status = 'cancelled');

CREATE POLICY "Only admins can delete leave requests"
ON leave_requests FOR DELETE TO authenticated
USING (is_admin());


-- 5. فصل وإحكام سياسات RLS لجدول السلف (loans)
DROP POLICY IF EXISTS "Employees can view and request loans" ON loans;
DROP POLICY IF EXISTS "Admins can manage loans" ON loans;

CREATE POLICY "Employees can view own loans and admins view all"
ON loans FOR SELECT TO authenticated
USING (employee_id = auth.uid() OR is_admin());

CREATE POLICY "Employees can request loans"
ON loans FOR INSERT TO authenticated
WITH CHECK (employee_id = auth.uid() AND (status = 'pending' OR status IS NULL));

CREATE POLICY "Only admins can update or process loans"
ON loans FOR UPDATE TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

CREATE POLICY "Only admins can delete loans"
ON loans FOR DELETE TO authenticated
USING (is_admin());
