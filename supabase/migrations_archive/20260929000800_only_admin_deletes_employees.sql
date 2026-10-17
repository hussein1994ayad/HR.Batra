-- =========================================================================
-- حذف الموظف للأدمن فقط
-- =========================================================================
-- safe_delete_employee (وغلافها hard_delete_employee) كانت تسمح لمدير الفرع بحذف أي
-- موظف غير أدمن، حتى من فرع آخر (يُخفي بياناته الشخصية ويحذف حساب دخوله).
-- قرار الإدارة: مدير الفرع ليس له حق الحذف إطلاقاً. الجداول نفسها (employees،
-- archived_employees) كانت أصلاً للأدمن فقط، فهذه الدالة كانت الطريق الوحيد.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.safe_delete_employee(p_employee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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

REVOKE ALL ON FUNCTION public.safe_delete_employee(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.safe_delete_employee(uuid) TO authenticated;
