-- =====================================================================
-- المساعد الذكي للأدمن (HR Assistant) — دوال قراءة فقط.
-- يناديها الـ Edge Function `hr-assistant` بتوكن الأدمن نفسه. كل دالة: require_admin()، ترجع jsonb مختصر
-- بدون هواتف/إيميلات/مواقع/أجهزة. ماكو أي كتابة. قواعد اليوم (خصم/إعفاء) تُقرأ من محرّك الرواتب (payroll_events)
-- حتى تبقى قاعدة وحدة بالنظام.
-- =====================================================================

-- توحيد الحروف العربية للبحث (نفس normalizeArabicForSearch بالتطبيق): أ إ آ ٱ ← ا، ة ← ه، ى ئ ← ي، ؤ ← و، بدون تشكيل
CREATE OR REPLACE FUNCTION public.assistant_norm(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(regexp_replace(
    translate(lower(COALESCE(p, '')), 'أإآٱةىئؤ', 'ااااهييو'),
    '[ًٌٍَُِّْـ]', '', 'g'));
$function$;

-- اسم نوع الإجازة كما بالإعدادات
CREATE OR REPLACE FUNCTION public.assistant_leave_type_name(p_type text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT t ->> 'name' FROM jsonb_array_elements(COALESCE(public.leave_policy() -> 'active_types', '[]'::jsonb)) t
     WHERE t ->> 'id' = p_type LIMIT 1),
    CASE p_type WHEN 'annual' THEN 'اعتيادية' WHEN 'sick' THEN 'مرضية' ELSE p_type END);
$function$;

-- ---------------------------------------------------------------------
-- البحث عن موظف بالاسم أو الكود، واختيارياً الفرع
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_find_employees(p_query text, p_branch text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_q text := public.assistant_norm(p_query);
  v_b text := public.assistant_norm(p_branch);
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(x ORDER BY x ->> 'name') FROM (
      SELECT jsonb_build_object('id', e.id, 'name', e.full_name, 'code', e.employee_code, 'branch', b.name,
                                'department', d.name, 'active', e.is_active, 'role', e.role) AS x
      FROM employees e
      LEFT JOIN branches b ON b.id = e.branch_id
      LEFT JOIN departments d ON d.id = e.department_id
      WHERE (v_q = '' OR public.assistant_norm(e.full_name) LIKE '%' || v_q || '%'
             OR public.assistant_norm(e.employee_code) = v_q
             -- كل كلمات البحث موجودة بالاسم (علي سعيد ← علي محمد سعيد)
             OR NOT EXISTS (SELECT 1 FROM unnest(string_to_array(v_q, ' ')) w
                            WHERE w <> '' AND public.assistant_norm(e.full_name) NOT LIKE '%' || w || '%'))
        AND (v_b = '' OR public.assistant_norm(b.name) LIKE '%' || v_b || '%')
      LIMIT 15
    ) s), '[]'::jsonb);
END;
$function$;

-- ---------------------------------------------------------------------
-- سجل الدوام يوم بيوم لموظف (أقصاها 93 يوم): الحالة، البصمات، الإجازة، وقرار الخصم من المحرّك
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_attendance_log(p_employee_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tz text := public.company_timezone();
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_emp record;
  v_days jsonb := '[]'::jsonb;
  d date;
  s work_schedules%ROWTYPE;
  v_holiday text;
  v_workday boolean;
  a attendance%ROWTYPE;
  v_has_att boolean;
  v_leave text;
  v_hourly text;
  v_events jsonb;
  v_status text;
  v_decision text;
  v_deducted numeric;
BEGIN
  PERFORM public.require_admin();
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN
    RAISE EXCEPTION 'حدد فترة صحيحة (من … إلى).' USING ERRCODE = '22023';
  END IF;
  IF p_to - p_from > 92 THEN
    RAISE EXCEPTION 'الفترة طويلة: أقصاها 3 أشهر بالطلب الواحد.' USING ERRCODE = '22023';
  END IF;

  SELECT e.id, e.full_name, e.employee_code, b.name AS branch, e.join_date, e.termination_date INTO v_emp
  FROM employees e LEFT JOIN branches b ON b.id = e.branch_id WHERE e.id = p_employee_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;

  d := p_from;
  WHILE d <= p_to LOOP
    s := public.payroll_schedule_at(p_employee_id, d);
    SELECT name INTO v_holiday FROM official_holidays WHERE holiday_date = d LIMIT 1;
    v_workday := EXTRACT(DOW FROM d)::int = ANY (COALESCE(s.work_days, ARRAY[0, 1, 2, 3, 4, 6])) AND v_holiday IS NULL;

    SELECT * INTO a FROM attendance WHERE employee_id = p_employee_id AND work_date = d LIMIT 1;
    v_has_att := FOUND;

    SELECT public.assistant_leave_type_name(l.leave_type) || CASE WHEN l.is_paid THEN '' ELSE ' (بدون راتب)' END INTO v_leave
    FROM leave_requests l
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT COALESCE(l.is_hourly, false)
      AND d BETWEEN (l.start_date AT TIME ZONE v_tz)::date AND (l.end_date AT TIME ZONE v_tz)::date
    LIMIT 1;

    SELECT string_agg(format('إذن %s→%s', to_char(l.start_hour, 'HH24:MI'), to_char(l.end_hour, 'HH24:MI')), '، ') INTO v_hourly
    FROM leave_requests l
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND COALESCE(l.is_hourly, false)
      AND (l.start_date AT TIME ZONE v_tz)::date = d;

    SELECT jsonb_agg(jsonb_build_object(
             'type', pe.event_type, 'minutes', pe.minutes, 'amount', round(pe.amount),
             'decision', CASE pe.status WHEN 'approved' THEN 'مخصوم' WHEN 'ignored' THEN 'معفى' ELSE 'بانتظار القرار' END,
             'reason', COALESCE(pe.decision_reason, pe.notes), 'payroll_month', pe.payroll_month) ORDER BY pe.event_type)
    INTO v_events
    FROM payroll_events pe
    WHERE pe.employee_id = p_employee_id AND pe.event_date = d AND pe.status <> 'void'
      AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch', 'unpaid_leave');

    v_status := CASE
      WHEN (v_emp.join_date IS NOT NULL AND d < v_emp.join_date)
           OR (v_emp.termination_date IS NOT NULL AND d > v_emp.termination_date) THEN 'خارج فترة الخدمة'
      WHEN v_holiday IS NOT NULL AND NOT v_has_att THEN 'عطلة رسمية'
      WHEN v_leave IS NOT NULL THEN 'إجازة'
      WHEN v_has_att AND a.status = 'absent' THEN 'غياب'
      WHEN v_has_att AND a.check_in_time IS NULL THEN 'بصمة ناقصة'
      WHEN v_has_att AND v_events @> '[{"type":"late"}]' THEN 'متأخر'
      WHEN v_has_att AND v_events @> '[{"type":"early_leave"}]' THEN 'خروج مبكر'
      WHEN v_has_att THEN 'حاضر'
      WHEN NOT v_workday THEN 'عطلة أسبوعية'
      WHEN d >= v_today THEN 'لم يحن بعد'
      ELSE 'غياب'
    END;

    SELECT CASE
             WHEN count(*) FILTER (WHERE e ->> 'type' <> 'missing_punch') = 0 THEN NULL
             WHEN bool_or(e ->> 'decision' = 'بانتظار القرار') THEN 'بانتظار القرار'
             WHEN bool_or(e ->> 'decision' = 'مخصوم') THEN 'مخصوم'
             ELSE 'معفى' END,
           COALESCE(sum((e ->> 'amount')::numeric) FILTER (WHERE e ->> 'decision' = 'مخصوم'), 0)
    INTO v_decision, v_deducted
    FROM jsonb_array_elements(COALESCE(v_events, '[]'::jsonb)) e;

    v_days := v_days || jsonb_build_object(
      'date', d, 'weekday', EXTRACT(DOW FROM d)::int, 'workday', v_workday, 'status', v_status,
      'holiday', v_holiday, 'leave', COALESCE(v_leave, v_hourly),
      'check_in', CASE WHEN v_has_att THEN to_char(a.check_in_time AT TIME ZONE v_tz, 'HH24:MI') END,
      'check_out', CASE WHEN v_has_att THEN to_char(a.check_out_time AT TIME ZONE v_tz, 'HH24:MI') END,
      'late_minutes', COALESCE((SELECT sum((e ->> 'minutes')::numeric) FROM jsonb_array_elements(COALESCE(v_events, '[]')) e WHERE e ->> 'type' = 'late'), 0),
      'early_minutes', COALESCE((SELECT sum((e ->> 'minutes')::numeric) FROM jsonb_array_elements(COALESCE(v_events, '[]')) e WHERE e ->> 'type' = 'early_leave'), 0),
      'decision', v_decision, 'deducted', v_deducted, 'events', COALESCE(v_events, '[]'::jsonb));
    d := d + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'employee', jsonb_build_object('id', v_emp.id, 'name', v_emp.full_name, 'code', v_emp.employee_code, 'branch', v_emp.branch),
    'from', p_from, 'to', p_to,
    'summary', (SELECT jsonb_build_object(
        'present', count(*) FILTER (WHERE x ->> 'status' IN ('حاضر', 'متأخر', 'خروج مبكر')),
        'late', count(*) FILTER (WHERE x ->> 'status' = 'متأخر'),
        'early_leave', count(*) FILTER (WHERE x ->> 'status' = 'خروج مبكر'),
        'absent', count(*) FILTER (WHERE x ->> 'status' = 'غياب'),
        'leave', count(*) FILTER (WHERE x ->> 'status' = 'إجازة'),
        'missing_punch', count(*) FILTER (WHERE x ->> 'status' = 'بصمة ناقصة'),
        'late_minutes', sum((x ->> 'late_minutes')::numeric),
        'deducted_days', count(*) FILTER (WHERE x ->> 'decision' = 'مخصوم'),
        'excused_days', count(*) FILTER (WHERE x ->> 'decision' = 'معفى'),
        'pending_days', count(*) FILTER (WHERE x ->> 'decision' = 'بانتظار القرار'),
        'deducted_total', sum((x ->> 'deducted')::numeric))
      FROM jsonb_array_elements(v_days) x),
    'days', v_days);
END;
$function$;

-- ---------------------------------------------------------------------
-- راتب موظف لشهر مسير ('YYYY-MM'): الملخص + الحركات بالتفصيل
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_payroll(p_employee_id uuid, p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_name text;
BEGIN
  PERFORM public.require_admin();
  IF p_month !~ '^\d{4}-\d{2}$' THEN
    RAISE EXCEPTION 'الشهر لازم يكون بصيغة YYYY-MM.' USING ERRCODE = '22023';
  END IF;
  SELECT full_name INTO v_name FROM employees WHERE id = p_employee_id;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('employee', v_name, 'month', p_month, 'message', 'هذا الشهر ما بيه مسير بالنظام.');
  END IF;

  RETURN jsonb_build_object(
    'employee', v_name, 'month', p_month, 'period', jsonb_build_object('from', v_p.start_date, 'to', v_p.cutoff_date, 'status', v_p.status),
    'summary', public.payroll_employee_summary(p_employee_id, p_month) - 'employee_id',
    'events', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'date', pe.event_date, 'type', pe.event_type, 'minutes', pe.minutes, 'days', pe.days, 'amount', round(pe.amount),
        'direction', pe.direction,
        'decision', CASE pe.status WHEN 'approved' THEN 'محتسب' WHEN 'ignored' THEN 'معفى' ELSE 'بانتظار القرار' END,
        'reason', COALESCE(pe.decision_reason, pe.notes), 'carried_from', pe.carried_from) ORDER BY pe.event_date, pe.event_type)
      FROM payroll_events pe
      WHERE pe.employee_id = p_employee_id AND pe.payroll_month = p_month AND pe.status <> 'void'
        AND (pe.amount > 0 OR pe.status = 'pending' OR pe.event_type = 'paid_leave')), '[]'::jsonb),
    'loan_installments', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('due_date', li.due_date, 'amount', li.amount, 'paid', li.is_paid) ORDER BY li.due_date)
      FROM loan_installments li JOIN loans l ON l.id = li.loan_id
      WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND COALESCE(l.payment_method, '') <> 'cash'
        AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date), '[]'::jsonb));
END;
$function$;

-- ---------------------------------------------------------------------
-- سلف موظف: المبلغ، المدفوع، الباقي، الأقساط
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_loans(p_employee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'status', l.status, 'amount', l.amount, 'remaining', l.remaining_amount, 'installment', l.installment_amount,
      'installments_count', l.installment_count, 'cash', COALESCE(l.payment_method, '') = 'cash',
      'requested_at', (l.created_at AT TIME ZONE public.company_timezone())::date,
      'installments', (SELECT jsonb_agg(jsonb_build_object('due_date', li.due_date, 'amount', li.amount, 'paid', li.is_paid)
                                        ORDER BY li.due_date) FROM loan_installments li WHERE li.loan_id = l.id))
      ORDER BY l.created_at DESC)
    FROM loans l WHERE l.employee_id = p_employee_id), '[]'::jsonb);
END;
$function$;

-- ---------------------------------------------------------------------
-- إجازات موظف بفترة + الرصيد
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_leaves(p_employee_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tz text := public.company_timezone();
BEGIN
  PERFORM public.require_admin();
  RETURN jsonb_build_object(
    'balance', public.get_leave_balance(p_employee_id, NULL, NULL),
    'requests', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'type', public.assistant_leave_type_name(l.leave_type), 'status', l.status, 'paid', l.is_paid, 'hourly', COALESCE(l.is_hourly, false),
        'from', (l.start_date AT TIME ZONE v_tz)::date, 'to', (l.end_date AT TIME ZONE v_tz)::date,
        'hours', CASE WHEN l.is_hourly THEN format('%s→%s', to_char(l.start_hour, 'HH24:MI'), to_char(l.end_hour, 'HH24:MI')) END,
        'reason', l.reason) ORDER BY l.start_date DESC)
      FROM leave_requests l
      WHERE l.employee_id = p_employee_id
        AND (l.end_date AT TIME ZONE v_tz)::date >= COALESCE(p_from, '-infinity'::date)
        AND (l.start_date AT TIME ZONE v_tz)::date <= COALESCE(p_to, 'infinity'::date)), '[]'::jsonb));
END;
$function$;

-- ---------------------------------------------------------------------
-- وثائق موظف: العدد والروابط (الروابط تروح للشاشة فقط، مو للذكاء)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_documents(p_employee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_name text;
  v_urls jsonb;
BEGIN
  PERFORM public.require_admin();
  SELECT full_name, CASE WHEN jsonb_typeof(document_urls) = 'array' THEN document_urls ELSE '[]'::jsonb END
  INTO v_name, v_urls FROM employees WHERE id = p_employee_id;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  RETURN jsonb_build_object('employee', v_name, 'count', jsonb_array_length(v_urls), 'urls', v_urls);
END;
$function$;

-- ---------------------------------------------------------------------
-- ملخص يوم لكل فرع: حاضر/متأخر/غايب/مجاز (الغياب = يوم دوام بدون بصمة ولا إجازة)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_day_overview(p_date date DEFAULT NULL, p_branch text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tz text := public.company_timezone();
  v_day date := COALESCE(p_date, (now() AT TIME ZONE public.company_timezone())::date);
  v_b text := public.assistant_norm(p_branch);
BEGIN
  PERFORM public.require_admin();
  RETURN jsonb_build_object('date', v_day,
    'holiday', (SELECT name FROM official_holidays WHERE holiday_date = v_day LIMIT 1),
    'branches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('branch', branch, 'present', present, 'late', late, 'on_leave', on_leave,
                                          'absent', absent, 'absent_names', absent_names, 'late_names', late_names)
                       ORDER BY branch)
      FROM (
        SELECT COALESCE(b.name, 'بدون فرع') AS branch,
               count(*) FILTER (WHERE a.id IS NOT NULL AND a.status <> 'absent') AS present,
               count(*) FILTER (WHERE a.status = 'late') AS late,
               count(*) FILTER (WHERE lv.id IS NOT NULL) AS on_leave,
               count(*) FILTER (WHERE (a.id IS NULL OR a.status = 'absent') AND lv.id IS NULL AND wd) AS absent,
               array_remove(array_agg(e.full_name) FILTER (WHERE (a.id IS NULL OR a.status = 'absent') AND lv.id IS NULL AND wd), NULL) AS absent_names,
               array_remove(array_agg(e.full_name) FILTER (WHERE a.status = 'late'), NULL) AS late_names
        FROM employees e
        LEFT JOIN branches b ON b.id = e.branch_id
        LEFT JOIN attendance a ON a.employee_id = e.id AND a.work_date = v_day
        LEFT JOIN LATERAL (SELECT l.id FROM leave_requests l WHERE l.employee_id = e.id AND l.status = 'approved'
                             AND NOT COALESCE(l.is_hourly, false)
                             AND v_day BETWEEN (l.start_date AT TIME ZONE v_tz)::date AND (l.end_date AT TIME ZONE v_tz)::date
                           LIMIT 1) lv ON true
        CROSS JOIN LATERAL (SELECT EXTRACT(DOW FROM v_day)::int = ANY (COALESCE((public.payroll_schedule_at(e.id, v_day)).work_days,
                                                                                ARRAY[0, 1, 2, 3, 4, 6]))
                                   AND NOT EXISTS (SELECT 1 FROM official_holidays h WHERE h.holiday_date = v_day) AS wd) w
        WHERE e.is_active AND (v_b = '' OR public.assistant_norm(b.name) LIKE '%' || v_b || '%')
        GROUP BY COALESCE(b.name, 'بدون فرع')
      ) s), '[]'::jsonb));
END;
$function$;

-- ---------------------------------------------------------------------
-- القرارات المعلّقة (غياب/تأخير/خروج مبكر/بصمة ناقصة) حسب الفرع
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_pending_decisions(p_branch text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b text := public.assistant_norm(p_branch);
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('employee', e.full_name, 'branch', b.name, 'date', pe.event_date, 'type', pe.event_type,
                                        'minutes', pe.minutes, 'amount', round(pe.amount), 'payroll_month', pe.payroll_month)
                     ORDER BY pe.event_date, e.full_name)
    FROM payroll_events pe
    JOIN employees e ON e.id = pe.employee_id
    LEFT JOIN branches b ON b.id = e.branch_id
    WHERE pe.status = 'pending' AND pe.salary_slip_id IS NULL
      AND (v_b = '' OR public.assistant_norm(b.name) LIKE '%' || v_b || '%')
    LIMIT 200), '[]'::jsonb);
END;
$function$;

-- ---------------------------------------------------------------------
-- أكثر الموظفين تأخيراً بفترة
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_top_late(p_from date, p_to date, p_branch text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b text := public.assistant_norm(p_branch);
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(x ORDER BY (x ->> 'late_minutes')::numeric DESC)
    FROM (
      SELECT jsonb_build_object('employee', e.full_name, 'branch', b.name, 'late_days', count(*),
                                'late_minutes', sum(pe.minutes),
                                'deducted', round(sum(pe.amount) FILTER (WHERE pe.status = 'approved'))) AS x
      FROM payroll_events pe
      JOIN employees e ON e.id = pe.employee_id
      LEFT JOIN branches b ON b.id = e.branch_id
      WHERE pe.event_type = 'late' AND pe.status <> 'void' AND pe.event_date BETWEEN p_from AND p_to
        AND (v_b = '' OR public.assistant_norm(b.name) LIKE '%' || v_b || '%')
      GROUP BY e.full_name, b.name
      ORDER BY sum(pe.minutes) DESC
      LIMIT 20
    ) s), '[]'::jsonb);
END;
$function$;

-- ---------------------------------------------------------------------
-- الفروع (للأسماء الصحيحة)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assistant_branches()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('name', b.name,
             'employees', (SELECT count(*) FROM employees e WHERE e.branch_id = b.id AND e.is_active)) ORDER BY b.name)
    FROM branches b), '[]'::jsonb);
END;
$function$;

REVOKE EXECUTE ON FUNCTION
  public.assistant_leave_type_name(text), public.assistant_find_employees(text, text),
  public.assistant_attendance_log(uuid, date, date), public.assistant_payroll(uuid, text), public.assistant_loans(uuid),
  public.assistant_leaves(uuid, date, date), public.assistant_documents(uuid), public.assistant_day_overview(date, text),
  public.assistant_pending_decisions(text), public.assistant_top_late(date, date, text), public.assistant_branches()
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.assistant_find_employees(text, text),
  public.assistant_attendance_log(uuid, date, date), public.assistant_payroll(uuid, text), public.assistant_loans(uuid),
  public.assistant_leaves(uuid, date, date), public.assistant_documents(uuid), public.assistant_day_overview(date, text),
  public.assistant_pending_decisions(text), public.assistant_top_late(date, date, text), public.assistant_branches()
TO authenticated;
