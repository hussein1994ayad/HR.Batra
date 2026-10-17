-- =====================================================================
-- المتأخرون اليوم (قسم في الرئيسية وصفحة التعاميم، بجانب المجازين)
--
-- get_late_today(): من سجّل حضوره اليوم متأخراً — الاسم والصورة والفرع ووقت
-- البصمة ودقائق التأخير (من بداية الدوام). بدون أي خصم أو سبب أو موقع.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_late_today()
RETURNS TABLE (
  employee_id uuid,
  full_name text,
  avatar_url text,
  branch_name text,
  check_in_time timestamptz,
  late_minutes integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT e.id, e.full_name, e.avatar_url, b.name, a.check_in_time,
         COALESCE(GREATEST(floor(public.payroll_local_minutes(a.check_in_time)
                                 - public.payroll_time_minutes(ws.check_in_time)), 0)::integer, 0)
  FROM attendance a
  JOIN employees e ON e.id = a.employee_id AND e.is_active
  LEFT JOIN branches b ON b.id = e.branch_id
  LEFT JOIN LATERAL public.payroll_schedule(e.id) ws ON true
  WHERE a.work_date = v_today
    AND a.status = 'late'
    AND a.check_in_time IS NOT NULL
  ORDER BY a.check_in_time;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_late_today() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_late_today() TO authenticated, service_role;
