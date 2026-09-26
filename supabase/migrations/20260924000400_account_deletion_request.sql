-- =========================================================================
-- HR Pro v6.0 — طلب حذف الحساب من التطبيق
-- Date: 2026-09-24
-- =========================================================================
-- كان التطبيق يبحث عن الأدمن في جدول employees ليرسل له الطلب، لكن RLS
-- لا يسمح للموظف برؤية غيره، فكان الطلب يُرسل للموظف نفسه ولا يصل للإدارة.
-- (Apple تشترط إمكانية طلب حذف الحساب من داخل التطبيق.)
-- =========================================================================

CREATE OR REPLACE FUNCTION public.request_account_deletion()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

REVOKE EXECUTE ON FUNCTION public.request_account_deletion() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.request_account_deletion() TO authenticated, service_role;
