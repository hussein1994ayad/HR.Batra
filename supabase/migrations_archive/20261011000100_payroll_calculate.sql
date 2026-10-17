-- =====================================================================
-- فحص الرواتب — المرحلة 2: «احتساب الرواتب» بزر (مثل أنظمة HR المعروفة)، وسرعة، وصلاحيات المدير.
--   • فتح صفحة الرواتب ما يعيد الحساب (كان يحسب كل يوم لكل موظف بكل فتحة ← يبطأ ويفشل مع موظفين أكثر).
--   • calculate_payroll: يحسب المسير ويسجل وقت الاحتساب ومنو احتسبه.
--   • payroll_nightly (pg_cron 00:15 بغداد): يطبق الزيادات اللي حل شهرها ويحسب آخر 3 أيام لكل الموظفين
--     (غياب بدون بصمة، بصمة ناقصة) — فالأرقام محدّثة حتى بدون ضغط الزر.
--   • get_pending_payroll_decisions ما يعيد حساب كل المسيرات بكل طلب.
--   • get_payroll_events: المدير يشوف موظفين فرعه بس (كان يشوف كل الفروع).
-- =====================================================================

ALTER TABLE public.payroll_periods ADD COLUMN IF NOT EXISTS calculated_at timestamptz;
ALTER TABLE public.payroll_periods ADD COLUMN IF NOT EXISTS calculated_by uuid REFERENCES public.employees(id) ON DELETE SET NULL;
COMMENT ON COLUMN public.payroll_periods.calculated_at IS 'آخر «احتساب الرواتب» لهذا المسير';

-- ---------------------------------------------------------------------
-- عرض المسير (آخر تعريف: 20260929000500_user_flow_fixes.sql) بدون إعادة الحساب
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_payroll_run(p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_rows jsonb;
BEGIN
  PERFORM public.require_admin();
  IF p_month !~ '^\d{4}-\d{2}$' THEN
    RAISE EXCEPTION 'صيغة الشهر غير صحيحة.' USING ERRCODE = '22023';
  END IF;

  -- أشهر قبل نظام المسيرات: عرض الكشوف القديمة كما حُفظت (بدون حساب)
  IF p_month < (SELECT min(period_month) FROM payroll_periods) THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'employee_id', e.id, 'full_name', e.full_name, 'branch_id', e.branch_id, 'branch_name', b.name,
             'join_date', e.join_date, 'termination_date', e.termination_date, 'is_active', e.is_active,
             'period_days', 0, 'employed_days', 0, 'monthly_salary', COALESCE(e.monthly_salary_iqd, 0),
             'daily_rate', COALESCE(e.monthly_salary_iqd, 0) / 30.0, 'minute_rate', 0, 'shift_minutes', 480,
             'basic', s.basic_salary, 'earnings', s.allowances, 'bonuses', s.allowances, 'overtime', 0,
             'deductions', s.deductions, 'attendance_deductions', 0, 'loans', s.loans_deduction, 'net', s.net_salary,
             'pending_count', 0, 'missing_punches', 0, 'absence_days', 0, 'late_minutes', 0, 'early_minutes', 0,
             'overtime_minutes', 0, 'paid_leave_days', 0, 'unpaid_leave_days', 0,
             'slip', jsonb_build_object('id', s.id, 'basic_salary', s.basic_salary, 'allowances', s.allowances,
                                        'deductions', s.deductions, 'loans_deduction', s.loans_deduction,
                                        'net_salary', s.net_salary, 'created_at', s.created_at, 'legacy', true))
           ORDER BY e.full_name), '[]'::jsonb)
    INTO v_rows
    FROM salary_slips s
    JOIN employees e ON e.id = s.employee_id
    LEFT JOIN branches b ON b.id = e.branch_id
    WHERE s.work_month = p_month;

    RETURN jsonb_build_object(
      'period', jsonb_build_object(
        'period_month', p_month,
        'start_date', to_char((p_month || '-01')::date, 'YYYY-MM-DD'),
        'cutoff_date', to_char((p_month || '-01')::date + interval '1 month - 1 day', 'YYYY-MM-DD'),
        'payment_date', NULL, 'status', 'closed', 'legacy', true,
        'archived', EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month)),
      'rows', v_rows);
  END IF;

  v_p := public.ensure_payroll_period(p_month);
  -- بدون إعادة حساب عند كل فتح (كان يعيد كل يوم لكل موظف): الحساب بزر «احتساب الرواتب» + التحديث الليلي

  SELECT COALESCE(jsonb_agg(
           public.payroll_employee_summary(e.id, p_month)
             || jsonb_build_object('full_name', e.full_name, 'branch_id', e.branch_id, 'branch_name', b.name,
                                   'join_date', e.join_date, 'termination_date', e.termination_date,
                                   'is_active', e.is_active)
           ORDER BY e.full_name), '[]'::jsonb)
  INTO v_rows
  FROM employees e
  LEFT JOIN branches b ON b.id = e.branch_id
  WHERE (
      (e.join_date IS NULL OR e.join_date <= v_p.cutoff_date)
      AND (e.termination_date IS NULL OR e.termination_date >= v_p.start_date)
      AND (e.is_active OR e.termination_date IS NOT NULL)
    )
    -- من له كشف معتمد في هذا الشهر يظهر دائماً (حتى لو عُطّل حسابه لاحقاً)
    OR EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = e.id AND s.work_month = p_month);

  RETURN jsonb_build_object(
    'period', to_jsonb(v_p) || jsonb_build_object('archived', EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month)),
    'rows', v_rows
  );
END;
$function$;

-- ---------------------------------------------------------------------
-- «احتساب الرواتب»: يحسب المسير كله ويسجّل الوقت، ويرجع نفس شكل get_payroll_run
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_payroll(p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
BEGIN
  PERFORM public.require_admin();
  IF p_month !~ '^\d{4}-\d{2}$' THEN
    RAISE EXCEPTION 'صيغة الشهر غير صحيحة.' USING ERRCODE = '22023';
  END IF;
  IF p_month >= (SELECT min(period_month) FROM payroll_periods) THEN
    v_p := public.ensure_payroll_period(p_month);
    IF v_p.status = 'open' AND NOT EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month) THEN
      PERFORM public.sync_payroll_period(p_month);
      UPDATE payroll_periods SET calculated_at = now(), calculated_by = auth.uid() WHERE period_month = p_month;
    END IF;
  END IF;
  RETURN public.get_payroll_run(p_month);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.calculate_payroll(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.calculate_payroll(text) TO authenticated;

-- ---------------------------------------------------------------------
-- التحديث الليلي: الزيادات المستحقة + حساب آخر 3 أيام لكل موظف بالخدمة
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_nightly()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_emp record;
  d date;
  v_n int := 0;
BEGIN
  PERFORM public.require_admin_or_system();
  PERFORM public.apply_due_salary_changes();
  IF public.payroll_natural_month(v_today) IS NULL THEN
    RETURN 0;
  END IF;
  FOR v_emp IN
    SELECT id FROM employees
    WHERE (is_active OR termination_date >= v_today - 3)
      AND (join_date IS NULL OR join_date <= v_today)
  LOOP
    FOR d IN SELECT generate_series(v_today - 3, v_today - 1, interval '1 day')::date LOOP
      PERFORM public.sync_payroll_day(v_emp.id, d);
    END LOOP;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.payroll_nightly() FROM PUBLIC, anon, authenticated;

DO $$ BEGIN PERFORM cron.unschedule('payroll_nightly'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule('payroll_nightly', '15 21 * * *', $cron$ SELECT public.payroll_nightly(); $cron$);

-- ---------------------------------------------------------------------
-- القرارات المعلّقة (آخر تعريف: 20260929000400_audit_fixes.sql) بدون إعادة حساب كل المسيرات بكل طلب
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_pending_payroll_decisions()
 RETURNS TABLE(id uuid, employee_id uuid, full_name text, branch_id uuid, branch_name text, event_date date, event_type text, minutes numeric, days numeric, amount numeric, direction smallint, payroll_month text, carried_from text, status text, source text, source_id uuid, notes text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN
  PERFORM public.require_admin_or_manager();
  RETURN QUERY
  SELECT pe.id, pe.employee_id, e.full_name, e.branch_id, b.name, pe.event_date, pe.event_type, pe.minutes, pe.days,
         pe.amount, pe.direction, pe.payroll_month, pe.carried_from, pe.status, pe.source, pe.source_id, pe.notes
  FROM payroll_events pe
  JOIN employees e ON e.id = pe.employee_id
  LEFT JOIN branches b ON b.id = e.branch_id
  JOIN payroll_periods p ON p.period_month = pe.payroll_month AND p.status = 'open'
  WHERE pe.status = 'pending'
    AND (public.is_admin() OR (pe.employee_id <> auth.uid() AND public.payroll_same_branch(pe.employee_id)))
    AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch', 'overtime')
  ORDER BY pe.event_date DESC, e.full_name;
END;
$function$;

-- ---------------------------------------------------------------------
-- حركات الرواتب: الأدمن كل الموظفين، المدير فرعه بس، والموظف نفسه
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_payroll_events(p_month text, p_employee_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF payroll_events
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT pe.* FROM payroll_events pe
  WHERE (public.is_admin()
         OR pe.employee_id = auth.uid()
         OR (public.is_manager() AND public.payroll_same_branch(pe.employee_id)))
    AND pe.payroll_month = p_month
    AND (p_employee_id IS NULL OR pe.employee_id = p_employee_id)
    AND pe.status <> 'void'
  ORDER BY pe.event_date, pe.event_type;
$function$;
