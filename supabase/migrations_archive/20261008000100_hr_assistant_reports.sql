-- =====================================================================
-- المساعد الذكي — تقارير وتحليلات (قراءة فقط، أدمن فقط). نفس نمط 20261008000000_hr_assistant.sql:
-- كل دالة require_admin()، ترجع jsonb مختصر بدون هواتف/إيميلات/مواقع، وأرقام الخصم من payroll_events (محرّك الرواتب).
-- ما تنادي sync_payroll_period (ما تكتب شي) — تقرا الحركات كما هي.
-- =====================================================================

-- الموظفون المستحقون لمسير شهر (نفس شرط get_payroll_run)
CREATE OR REPLACE FUNCTION public.assistant_month_employees(p_month text)
 RETURNS TABLE(id uuid, full_name text, branch text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT e.id, e.full_name, b.name
  FROM employees e
  LEFT JOIN branches b ON b.id = e.branch_id
  JOIN payroll_periods p ON p.period_month = p_month
  WHERE ((e.join_date IS NULL OR e.join_date <= p.cutoff_date)
         AND (e.termination_date IS NULL OR e.termination_date >= p.start_date)
         AND (e.is_active OR e.termination_date IS NOT NULL))
     OR EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = e.id AND s.work_month = p_month);
$function$;

-- بيانات ناقصة تأثر على الحساب (بلا فرع/جدول/تاريخ مباشرة/راتب)
CREATE OR REPLACE FUNCTION public.assistant_data_issues()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(jsonb_agg(jsonb_build_object('employee', full_name, 'issues', issues) ORDER BY full_name), '[]'::jsonb)
  FROM (
    SELECT e.full_name, array_remove(ARRAY[
      CASE WHEN e.branch_id IS NULL THEN 'بدون فرع' END,
      CASE WHEN (public.payroll_schedule_at(e.id, (now() AT TIME ZONE public.company_timezone())::date)).id IS NULL THEN 'بدون جدول دوام' END,
      CASE WHEN e.join_date IS NULL THEN 'بدون تاريخ مباشرة' END,
      CASE WHEN COALESCE(e.monthly_salary_iqd, 0) <= 0 THEN 'بدون راتب' END], NULL) AS issues
    FROM employees e WHERE e.is_active
  ) x WHERE cardinality(issues) > 0;
$function$;

-- ---------------------------------------------------------------------
-- 1) سجل دوام فرع أو كل الشركة (أقصاها 31 يوم و60 موظف)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_branch_attendance(p_branch text, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b text := public.assistant_norm(p_branch);
  v_logs jsonb := '[]'::jsonb;
  r record;
  n int := 0;
BEGIN
  PERFORM public.require_admin();
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from OR p_to - p_from > 30 THEN
    RAISE EXCEPTION 'تقرير الفرع أو الشركة: حدد فترة صحيحة أقصاها 31 يوم.' USING ERRCODE = '22023';
  END IF;
  FOR r IN
    SELECT e.id FROM employees e LEFT JOIN branches b ON b.id = e.branch_id
    WHERE e.is_active AND (v_b = '' OR public.assistant_norm(b.name) LIKE '%' || v_b || '%')
    ORDER BY b.name, e.full_name
  LOOP
    n := n + 1;
    IF n > 60 THEN
      RAISE EXCEPTION 'عدد الموظفين كبير (أكثر من 60). حدد فرعاً.' USING ERRCODE = '22023';
    END IF;
    v_logs := v_logs || public.assistant_attendance_log(r.id, p_from, p_to);
  END LOOP;
  RETURN jsonb_build_object('scope', COALESCE(NULLIF(btrim(p_branch), ''), 'كل الفروع'), 'from', p_from, 'to', p_to, 'employees', v_logs);
END;
$function$;

-- ---------------------------------------------------------------------
-- 2) رواتب كل الموظفين لشهر مسير (بدون إعادة حساب)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_payroll_run(p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_rows jsonb;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('month', p_month, 'message', 'هذا الشهر ما بيه مسير بالنظام.');
  END IF;
  SELECT COALESCE(jsonb_agg(row ORDER BY row ->> 'branch', row ->> 'employee'), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT jsonb_build_object(
      'employee', m.full_name, 'branch', m.branch,
      'basic', COALESCE((s -> 'slip' ->> 'basic_salary')::numeric, (s ->> 'basic')::numeric),
      'earnings', COALESCE((s -> 'slip' ->> 'allowances')::numeric, (s ->> 'earnings')::numeric),
      'deductions', COALESCE((s -> 'slip' ->> 'deductions')::numeric, (s ->> 'deductions')::numeric),
      'loans', COALESCE((s -> 'slip' ->> 'loans_deduction')::numeric, (s ->> 'loans')::numeric),
      'net', COALESCE((s -> 'slip' ->> 'net_salary')::numeric, (s ->> 'net')::numeric),
      'absence_days', s -> 'absence_days', 'late_minutes', s -> 'late_minutes', 'pending', s -> 'pending_count',
      'issued', s -> 'slip' IS NOT NULL AND s -> 'slip' <> 'null'::jsonb) AS row
    FROM public.assistant_month_employees(p_month) m
    CROSS JOIN LATERAL (SELECT public.payroll_employee_summary(m.id, p_month) AS s) x
  ) y;
  RETURN jsonb_build_object(
    'month', p_month, 'period', jsonb_build_object('from', v_p.start_date, 'to', v_p.cutoff_date, 'status', v_p.status),
    'rows', v_rows,
    'totals', (SELECT jsonb_build_object('employees', count(*), 'issued', count(*) FILTER (WHERE (r ->> 'issued')::boolean),
                 'basic', sum((r ->> 'basic')::numeric), 'earnings', sum((r ->> 'earnings')::numeric),
                 'deductions', sum((r ->> 'deductions')::numeric), 'loans', sum((r ->> 'loans')::numeric),
                 'net', sum((r ->> 'net')::numeric))
               FROM jsonb_array_elements(v_rows) r));
END;
$function$;

-- ---------------------------------------------------------------------
-- 3) جاهزية رواتب الشهر: شنو باقي قبل الاعتماد
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_payroll_readiness(p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('month', p_month, 'message', 'هذا الشهر ما بيه مسير بالنظام.');
  END IF;
  RETURN jsonb_build_object(
    'month', p_month,
    'period', jsonb_build_object('from', v_p.start_date, 'to', v_p.cutoff_date, 'status', v_p.status,
                                 'ended', v_today > v_p.cutoff_date, 'days_left', GREATEST(v_p.cutoff_date - v_today, 0)),
    'pending_by_type', COALESCE((
      SELECT jsonb_object_agg(event_type, n) FROM (
        SELECT event_type, count(*) n FROM payroll_events
        WHERE payroll_month = p_month AND status = 'pending' AND salary_slip_id IS NULL GROUP BY event_type) t), '{}'::jsonb),
    'without_slip', COALESCE((
      SELECT jsonb_agg(m.full_name ORDER BY m.full_name) FROM public.assistant_month_employees(p_month) m
      WHERE NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = m.id AND s.work_month = p_month)), '[]'::jsonb),
    'negative_net', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('employee', m.full_name, 'net', (x.s ->> 'net')::numeric))
      FROM public.assistant_month_employees(p_month) m
      CROSS JOIN LATERAL (SELECT public.payroll_employee_summary(m.id, p_month) AS s) x
      WHERE (x.s ->> 'net')::numeric < 0 AND (x.s -> 'slip' IS NULL OR x.s -> 'slip' = 'null'::jsonb)), '[]'::jsonb),
    'data_issues', public.assistant_data_issues(),
    'loans_due', (SELECT COALESCE(sum(li.amount), 0) FROM loan_installments li JOIN loans l ON l.id = li.loan_id
                  WHERE l.status = 'approved' AND NOT li.is_paid AND COALESCE(l.payment_method, '') <> 'cash'
                    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date));
END;
$function$;

-- ---------------------------------------------------------------------
-- 4) تنبيهات وأنماط
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_alerts(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_days text[] := ARRAY['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
BEGIN
  PERFORM public.require_admin();
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from OR p_to - p_from > 92 THEN
    RAISE EXCEPTION 'حدد فترة صحيحة أقصاها 3 أشهر.' USING ERRCODE = '22023';
  END IF;
  RETURN jsonb_build_object('from', p_from, 'to', p_to,
    -- يتأخر بنفس يوم الأسبوع 3 مرات أو أكثر
    'recurring_late_weekday', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('employee', e.full_name, 'weekday', v_days[dow + 1], 'times', n) ORDER BY n DESC)
      FROM (SELECT employee_id, EXTRACT(DOW FROM event_date)::int dow, count(*) n FROM payroll_events
            WHERE event_type = 'late' AND status <> 'void' AND event_date BETWEEN p_from AND p_to
            GROUP BY 1, 2 HAVING count(*) >= 3) t JOIN employees e ON e.id = t.employee_id), '[]'::jsonb),
    'repeated_missing_punch', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('employee', e.full_name, 'times', n) ORDER BY n DESC)
      FROM (SELECT employee_id, count(*) n FROM payroll_events
            WHERE event_type = 'missing_punch' AND status <> 'void' AND event_date BETWEEN p_from AND p_to
            GROUP BY 1 HAVING count(*) >= 3) t JOIN employees e ON e.id = t.employee_id), '[]'::jsonb),
    -- بصمات محفوظة بدون إنترنت (وقتها من ساعة الموبايل) — تستاهل مراجعة إذا كثيرة
    'many_offline_punches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('employee', e.full_name, 'times', n) ORDER BY n DESC)
      FROM (SELECT employee_id, count(*) n FROM attendance
            WHERE (check_in_offline OR check_out_offline) AND work_date BETWEEN p_from AND p_to
            GROUP BY 1 HAVING count(*) >= 3) t JOIN employees e ON e.id = t.employee_id), '[]'::jsonb),
    'low_annual_leave', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('employee', full_name, 'left_days', left_days) ORDER BY left_days)
      FROM (SELECT e.full_name, (public.get_leave_balance(e.id, NULL, NULL) -> 'annual' ->> 'left')::numeric AS left_days
            FROM employees e WHERE e.is_active) x WHERE left_days IS NOT NULL AND left_days < 2), '[]'::jsonb),
    'data_issues', public.assistant_data_issues());
END;
$function$;

-- ---------------------------------------------------------------------
-- 5) مقارنة شهرين (موظف أو فرع)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_month_metrics(p_employee_id uuid, p_branch text, p_month text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH scope AS (
    SELECT e.id FROM employees e LEFT JOIN branches b ON b.id = e.branch_id
    WHERE (p_employee_id IS NOT NULL AND e.id = p_employee_id)
       OR (p_employee_id IS NULL AND (public.assistant_norm(p_branch) = ''
           OR public.assistant_norm(b.name) LIKE '%' || public.assistant_norm(p_branch) || '%'))
  ), per AS (SELECT * FROM payroll_periods WHERE period_month = p_month)
  SELECT jsonb_build_object(
    'month', p_month,
    'present_days', (SELECT count(*) FROM attendance a, per WHERE a.employee_id IN (SELECT id FROM scope)
                       AND a.work_date BETWEEN per.start_date AND per.cutoff_date AND a.status <> 'absent'),
    'late_times', count(*) FILTER (WHERE pe.event_type = 'late'),
    'late_minutes', COALESCE(sum(pe.minutes) FILTER (WHERE pe.event_type = 'late'), 0),
    'absence_days', COALESCE(sum(pe.days) FILTER (WHERE pe.event_type = 'absence'), 0),
    'early_leave_times', count(*) FILTER (WHERE pe.event_type = 'early_leave'),
    'deducted', COALESCE(round(sum(pe.amount) FILTER (WHERE pe.status = 'approved' AND pe.direction = -1)), 0),
    'excused', count(*) FILTER (WHERE pe.status = 'ignored'))
  FROM payroll_events pe, per
  WHERE pe.employee_id IN (SELECT id FROM scope) AND pe.status <> 'void'
    AND pe.event_date BETWEEN per.start_date AND per.cutoff_date;
$function$;

CREATE OR REPLACE FUNCTION public.assistant_compare(p_employee_id uuid, p_branch text, p_month_a text, p_month_b text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  RETURN jsonb_build_object(
    'scope', CASE WHEN p_employee_id IS NOT NULL THEN (SELECT full_name FROM employees WHERE id = p_employee_id)
                  ELSE COALESCE(NULLIF(btrim(p_branch), ''), 'كل الفروع') END,
    'a', public.assistant_month_metrics(p_employee_id, p_branch, p_month_a),
    'b', public.assistant_month_metrics(p_employee_id, p_branch, p_month_b));
END;
$function$;

-- ---------------------------------------------------------------------
-- 6) ترتيب الفروع بالانضباط + الأكثر انضباطاً
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_branch_ranking(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from OR p_to - p_from > 92 THEN
    RAISE EXCEPTION 'حدد فترة صحيحة أقصاها 3 أشهر.' USING ERRCODE = '22023';
  END IF;
  RETURN jsonb_build_object('from', p_from, 'to', p_to,
    'branches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'branch', branch, 'employees', emps, 'present_days', present, 'absence_days', absences,
               'late_times', lates, 'late_minutes_per_employee', round(late_minutes / NULLIF(emps, 0), 1),
               'attendance_rate', round(100.0 * present / NULLIF(present + absences, 0), 1))
             ORDER BY round(100.0 * present / NULLIF(present + absences, 0), 1) DESC NULLS LAST, late_minutes / NULLIF(emps, 0))
      FROM (
        SELECT COALESCE(b.name, 'بدون فرع') AS branch, count(DISTINCT e.id) AS emps,
               (SELECT count(*) FROM attendance a JOIN employees x ON x.id = a.employee_id
                WHERE x.is_active AND x.branch_id IS NOT DISTINCT FROM b.id AND a.work_date BETWEEN p_from AND p_to AND a.status <> 'absent') AS present,
               COALESCE((SELECT sum(pe.days) FROM payroll_events pe JOIN employees x ON x.id = pe.employee_id
                WHERE x.is_active AND x.branch_id IS NOT DISTINCT FROM b.id AND pe.event_type = 'absence' AND pe.status <> 'void'
                  AND pe.status <> 'ignored' AND pe.event_date BETWEEN p_from AND p_to), 0) AS absences,
               (SELECT count(*) FROM payroll_events pe JOIN employees x ON x.id = pe.employee_id
                WHERE x.is_active AND x.branch_id IS NOT DISTINCT FROM b.id AND pe.event_type = 'late' AND pe.status <> 'void'
                  AND pe.event_date BETWEEN p_from AND p_to) AS lates,
               COALESCE((SELECT sum(pe.minutes) FROM payroll_events pe JOIN employees x ON x.id = pe.employee_id
                WHERE x.is_active AND x.branch_id IS NOT DISTINCT FROM b.id AND pe.event_type = 'late' AND pe.status <> 'void'
                  AND pe.event_date BETWEEN p_from AND p_to), 0) AS late_minutes
        FROM employees e LEFT JOIN branches b ON b.id = e.branch_id
        WHERE e.is_active GROUP BY b.id, b.name
      ) s), '[]'::jsonb),
    -- حاضر 5 أيام أو أكثر وبدون أي تأخير/غياب/خروج مبكر/بصمة ناقصة بالفترة
    'most_disciplined', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('employee', full_name, 'branch', branch, 'present_days', days) ORDER BY days DESC, full_name)
      FROM (
        SELECT e.full_name, b.name AS branch, count(a.id) AS days
        FROM employees e LEFT JOIN branches b ON b.id = e.branch_id
        JOIN attendance a ON a.employee_id = e.id AND a.work_date BETWEEN p_from AND p_to AND a.status <> 'absent'
        WHERE e.is_active AND NOT EXISTS (
          SELECT 1 FROM payroll_events pe WHERE pe.employee_id = e.id AND pe.event_date BETWEEN p_from AND p_to
            AND pe.status NOT IN ('void', 'ignored') AND pe.event_type IN ('late', 'absence', 'early_leave', 'missing_punch'))
        GROUP BY e.id, e.full_name, b.name HAVING count(a.id) >= 5
        ORDER BY count(a.id) DESC LIMIT 10) t), '[]'::jsonb));
END;
$function$;

REVOKE EXECUTE ON FUNCTION
  public.assistant_month_employees(text), public.assistant_data_issues(), public.assistant_month_metrics(uuid, text, text)
FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION
  public.assistant_branch_attendance(text, date, date), public.assistant_payroll_run(text), public.assistant_payroll_readiness(text),
  public.assistant_alerts(date, date), public.assistant_compare(uuid, text, text, text), public.assistant_branch_ranking(date, date)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.assistant_branch_attendance(text, date, date), public.assistant_payroll_run(text), public.assistant_payroll_readiness(text),
  public.assistant_alerts(date, date), public.assistant_compare(uuid, text, text, text), public.assistant_branch_ranking(date, date)
TO authenticated;
