-- =====================================================================
-- المساعد الذكي — اقتراح القرارات (قراءة فقط). الذكاء يقترح خصم/إعفاء مع سبب؛ التنفيذ ما يصير إلا لما الأدمن يضغط
-- «تأكيد» بالشاشة، وتنادي الشاشة decide_payroll_event الموجودة (نفس باب صفحة الرواتب).
-- =====================================================================

-- القرارات المعلّقة + سياق كل موظف حتى يقترح الذكاء بعدل (أول مرة؟ متكرر؟ انعفى قبل؟)
CREATE OR REPLACE FUNCTION public.assistant_decision_context(p_branch text DEFAULT NULL)
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
    SELECT jsonb_agg(jsonb_build_object(
      'event_id', pe.id, 'employee', e.full_name, 'branch', b.name, 'date', pe.event_date, 'type', pe.event_type,
      'minutes', pe.minutes, 'amount', round(pe.amount), 'payroll_month', pe.payroll_month, 'note', pe.notes,
      -- نفس النوع بنفس المسير (شكد تكرر)، والسابق خلال 90 يوم: كم مرة انخصم وكم مرة انعفى
      'same_type_this_month', (SELECT count(*) FROM payroll_events x WHERE x.employee_id = pe.employee_id AND x.payroll_month = pe.payroll_month
                                 AND x.event_type = pe.event_type AND x.status <> 'void'),
      'deducted_last_90d', (SELECT count(*) FROM payroll_events x WHERE x.employee_id = pe.employee_id AND x.event_type = pe.event_type
                              AND x.status = 'approved' AND x.event_date BETWEEN pe.event_date - 90 AND pe.event_date - 1),
      'excused_last_90d', (SELECT count(*) FROM payroll_events x WHERE x.employee_id = pe.employee_id AND x.event_type = pe.event_type
                             AND x.status = 'ignored' AND x.event_date BETWEEN pe.event_date - 90 AND pe.event_date - 1),
      'had_leave_request_that_day', EXISTS (SELECT 1 FROM leave_requests l WHERE l.employee_id = pe.employee_id
                             AND l.status IN ('pending', 'rejected')
                             AND pe.event_date BETWEEN (l.start_date AT TIME ZONE public.company_timezone())::date
                                                   AND (l.end_date AT TIME ZONE public.company_timezone())::date))
      ORDER BY pe.event_date, e.full_name)
    FROM payroll_events pe
    JOIN employees e ON e.id = pe.employee_id
    LEFT JOIN branches b ON b.id = e.branch_id
    WHERE pe.status = 'pending' AND pe.salary_slip_id IS NULL
      AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch')
      AND (v_b = '' OR public.assistant_norm(b.name) LIKE '%' || v_b || '%')
    LIMIT 60), '[]'::jsonb);
END;
$function$;

-- بيانات الحركات المقترحة من القاعدة (مو من الذكاء): بس اللي بعدها معلّقة
CREATE OR REPLACE FUNCTION public.assistant_pending_events(p_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object('event_id', pe.id, 'employee', e.full_name, 'date', pe.event_date, 'type', pe.event_type,
                                        'minutes', pe.minutes, 'amount', round(pe.amount)))
    FROM payroll_events pe JOIN employees e ON e.id = pe.employee_id
    WHERE pe.id = ANY (p_ids) AND pe.status = 'pending' AND pe.salary_slip_id IS NULL
      AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch')), '[]'::jsonb);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.assistant_decision_context(text), public.assistant_pending_events(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assistant_decision_context(text), public.assistant_pending_events(uuid[]) TO authenticated;
