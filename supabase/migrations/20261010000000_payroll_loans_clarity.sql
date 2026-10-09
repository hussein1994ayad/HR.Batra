-- =====================================================================
-- الرواتب والسلف أوضح:
--   1) payroll_month_of(date): شهر الرواتب اللي يقع بيه التاريخ (قسط 28/10 تابع لرواتب شهر 11).
--   2) payroll_employee_summary: إضافات عرض فقط (أقساط هالمسير وأسبابها، أيام الدوام الفعلي/المجدول)؛ الصافي نفسه.
--   3) pay_loan_installment: «استقطاع راتب» يدوي على شهر رواتبه بعده ما صادر ينرفض (كان يعلّمه مسدد فالرواتب
--      ما تخصمه أبداً) — الصح «هالشهر أقل» (set_month_installment) حتى الكشف يخصمه.
--   4) settle_loan_on_exit: ترك العمل وعليه سلفة ← يخصم الباقي (أو جزء) من آخر راتب، والباقي يسدد نقداً.
--   5) تصليح عام محمي: أقساط «استقطاع راتب» انسجلت مسددة يدوياً قبل كشف مسير مفتوح ← ترجع غير مسددة بمبلغها.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.payroll_month_of(p_date date)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT period_month FROM payroll_periods WHERE p_date BETWEEN start_date AND cutoff_date ORDER BY period_month LIMIT 1),
    to_char(CASE WHEN EXTRACT(DAY FROM p_date) <= COALESCE((SELECT (value ->> 'cutoff_day')::int FROM system_settings WHERE key = 'payroll_policy'), 26)
                 THEN p_date ELSE (p_date + interval '1 month')::date END, 'YYYY-MM'));
$function$;

REVOKE EXECUTE ON FUNCTION public.payroll_month_of(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.payroll_month_of(date) TO authenticated;

-- ---------------------------------------------------------------------
-- ملخص راتب الموظف (آخر تعريف: 20260929000400_audit_fixes.sql) + loan_items و attended_days و scheduled_days
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_employee_summary(p_employee_id uuid, p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_emp employees%ROWTYPE;
  v_month_basic numeric;
  v_daily numeric;
  v_from date;
  v_to date;
  v_period_days int;
  v_employed_days int;
  v_basic numeric;
  v_ev record;
  v_loans numeric;
  v_slip salary_slips%ROWTYPE;
  v_exit_balance numeric := 0;
  v_loan_items jsonb;
  v_attended int;
  v_scheduled int;
BEGIN
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  v_month_basic := public.payroll_basic_salary(p_employee_id, p_month);
  v_daily := v_month_basic / 30;

  v_from := GREATEST(v_p.start_date, COALESCE(v_emp.join_date, v_p.start_date));
  v_to := LEAST(v_p.cutoff_date, COALESCE(v_emp.termination_date, v_p.cutoff_date));
  v_period_days := v_p.cutoff_date - v_p.start_date + 1;
  v_employed_days := GREATEST(v_to - v_from + 1, 0);
  -- فترة كاملة = الراتب كاملاً؛ جزئية (مباشرة/انتهاء خدمة) = أجر اليوم × الأيام (بحد 30)
  v_basic := CASE WHEN v_employed_days >= v_period_days THEN v_month_basic
                  ELSE round(v_daily * LEAST(v_employed_days, 30)) END;

  SELECT
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = 1), 0) AS earnings,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = -1), 0) AS deductions,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = -1 AND event_type IN ('absence', 'late', 'early_leave', 'unpaid_leave')), 0) AS attendance_deductions,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND event_type = 'overtime'), 0) AS overtime,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND event_type = 'bonus'), 0) AS bonuses,
    count(*) FILTER (WHERE status = 'pending' AND event_type <> 'missing_punch') AS pending,
    count(*) FILTER (WHERE status = 'pending' AND event_type = 'missing_punch') AS missing_punches,
    COALESCE(sum(days) FILTER (WHERE status = 'approved' AND event_type = 'absence'), 0) AS absence_days,
    COALESCE(sum(minutes) FILTER (WHERE status = 'approved' AND event_type = 'late'), 0) AS late_minutes,
    COALESCE(sum(minutes) FILTER (WHERE status = 'approved' AND event_type = 'early_leave'), 0) AS early_minutes,
    COALESCE(sum(minutes) FILTER (WHERE status = 'approved' AND event_type = 'overtime'), 0) AS overtime_minutes,
    COALESCE(sum(days) FILTER (WHERE event_type = 'paid_leave'), 0) AS paid_leave_days,
    COALESCE(sum(days) FILTER (WHERE status = 'approved' AND event_type = 'unpaid_leave'), 0) AS unpaid_leave_days
  INTO v_ev
  FROM payroll_events
  WHERE employee_id = p_employee_id AND payroll_month = p_month AND status <> 'void';

  SELECT COALESCE(sum(li.amount), 0) INTO v_loans
  FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'           -- السلفة النقدية تُسدَّد نقداً لا من الراتب
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  -- ترك العمل خلال المسير: ما يبقى من السلف بعد أقساط هذا المسير (تنبيه للإدارة)
  IF v_emp.termination_date IS NOT NULL AND v_emp.termination_date <= v_p.cutoff_date THEN
    SELECT COALESCE(sum(li.amount), 0) INTO v_exit_balance
    FROM loan_installments li JOIN loans l ON l.id = li.loan_id
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid AND li.due_date > v_p.cutoff_date;
  END IF;

  -- للعرض فقط: أقساط هالمسير وأسبابها، وأيام الدوام الفعلي مقابل المجدول (الحساب ما يتغير)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'installment_id', li.id, 'loan_id', l.id, 'loan_amount', l.amount, 'due_date', li.due_date, 'amount', li.amount,
           'origin_kind', li.origin_kind, 'origin_month', li.origin_month, 'amount_locked', li.amount_locked,
           'note', li.payment_note) ORDER BY li.due_date), '[]'::jsonb)
  INTO v_loan_items
  FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  SELECT count(DISTINCT a.work_date) INTO v_attended
  FROM attendance a
  WHERE a.employee_id = p_employee_id AND a.work_date BETWEEN v_from AND v_to AND a.status <> 'absent';

  SELECT count(*) INTO v_scheduled
  FROM generate_series(v_from, v_to, interval '1 day') g(d)
  WHERE EXTRACT(DOW FROM g.d)::int = ANY (COALESCE((public.payroll_schedule_at(p_employee_id, g.d::date)).work_days, ARRAY[0, 1, 2, 3, 4, 6]))
    AND NOT EXISTS (SELECT 1 FROM official_holidays h WHERE h.holiday_date = g.d::date);

  SELECT * INTO v_slip FROM salary_slips WHERE employee_id = p_employee_id AND work_month = p_month;

  RETURN jsonb_build_object(
    'employee_id', p_employee_id,
    'period_days', v_period_days,
    'employed_days', v_employed_days,
    'monthly_salary', v_month_basic,
    'daily_rate', round(v_daily, 4),
    'minute_rate', round(v_daily / public.payroll_shift_minutes(p_employee_id), 6),
    'shift_minutes', public.payroll_shift_minutes(p_employee_id),
    'basic', v_basic,
    'earnings', round(v_ev.earnings),
    'bonuses', round(v_ev.bonuses),
    'overtime', round(v_ev.overtime),
    'deductions', round(v_ev.deductions),
    'attendance_deductions', round(v_ev.attendance_deductions),
    'loans', v_loans,
    -- التقريب لأقرب دينار على المجموع (لا يوم بيوم)
    'net', v_basic + round(v_ev.earnings) - round(v_ev.deductions) - v_loans,
    'loan_balance_after_exit', v_exit_balance,
    'loan_items', v_loan_items,
    'attended_days', COALESCE(v_attended, 0),
    'scheduled_days', COALESCE(v_scheduled, 0),
    'pending_count', v_ev.pending,
    'missing_punches', v_ev.missing_punches,
    'absence_days', v_ev.absence_days,
    'late_minutes', v_ev.late_minutes,
    'early_minutes', v_ev.early_minutes,
    'overtime_minutes', v_ev.overtime_minutes,
    'paid_leave_days', v_ev.paid_leave_days,
    'unpaid_leave_days', v_ev.unpaid_leave_days,
    'slip', CASE WHEN v_slip.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_slip.id, 'basic_salary', v_slip.basic_salary, 'allowances', v_slip.allowances,
      'deductions', v_slip.deductions, 'loans_deduction', v_slip.loans_deduction,
      'net_salary', v_slip.net_salary, 'created_at', v_slip.created_at,
      'legacy', NOT v_slip.computed_by_engine) END
  );
END;
$function$;

-- ---------------------------------------------------------------------
-- تسجيل دفعة (آخر تعريف: 20260927000000_flexible_installment_payment.sql) + رفض «استقطاع راتب» قبل كشف الشهر
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pay_loan_installment(p_installment_id uuid, p_amount numeric, p_method text DEFAULT 'cash'::text, p_note text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_inst loan_installments%ROWTYPE;
  v_loan loans%ROWTYPE;
  v_remaining numeric;
BEGIN
  PERFORM public.require_admin();

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'يرجى إدخال مبلغ سداد أكبر من الصفر.' USING ERRCODE = '22023';
  END IF;
  IF p_method NOT IN ('cash', 'salary_deduction') THEN
    RAISE EXCEPTION 'طريقة السداد غير صحيحة.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_inst FROM loan_installments WHERE id = p_installment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'القسط غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF v_inst.is_paid THEN
    RAISE EXCEPTION 'هذا القسط مسدد مسبقاً.' USING ERRCODE = '55000';
  END IF;

  SELECT * INTO v_loan FROM loans WHERE id = v_inst.loan_id FOR UPDATE;
  IF v_loan.status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'السلفة غير معتمدة.' USING ERRCODE = '55000';
  END IF;

  -- «استقطاع راتب» يدوي قبل ما يصدر كشف ذاك الشهر: الكشف نفسه راح يخصم القسط، فالتسجيل اليدوي يخليه ما ينخصم أبداً
  IF p_method = 'salary_deduction' AND COALESCE(v_loan.payment_method, '') <> 'cash'
     AND NOT public._loan_month_settled(v_loan.employee_id, v_inst.due_date) THEN
    RAISE EXCEPTION 'راتب شهر % بعده ما صادر: الرواتب راح تخصم هذا القسط وحدها. إذا الموظف هالشهر يكدر يدفع أقل، استعمل «هالشهر أقل».',
      public.payroll_month_of(v_inst.due_date) USING ERRCODE = '22023';
  END IF;

  v_remaining := v_loan.amount - COALESCE((
    SELECT SUM(amount) FROM loan_installments WHERE loan_id = v_loan.id AND is_paid
  ), 0);
  IF p_amount > v_remaining THEN
    RAISE EXCEPTION 'المبلغ أكبر من المتبقي على السلفة (%).', to_char(v_remaining, 'FM999,999,999')
      USING ERRCODE = '22023';
  END IF;

  UPDATE loan_installments
  SET amount = round(p_amount),
      is_paid = true,
      paid_at = now(),
      payment_type = p_method,
      payment_note = NULLIF(btrim(COALESCE(p_note, '')), '')
  WHERE id = p_installment_id;

  SELECT remaining_amount INTO v_remaining FROM loans WHERE id = v_loan.id;

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (
    v_loan.employee_id,
    'تسجيل دفعة سلفة 💸',
    format('تم تسجيل دفعة بمبلغ %s د.ع من سلفتك. المتبقي: %s د.ع.',
           to_char(round(p_amount), 'FM999,999,999'), to_char(v_remaining, 'FM999,999,999')),
    'loan'
  );

  RETURN v_remaining;
END;
$function$;

-- ---------------------------------------------------------------------
-- ترك العمل وعليه سلفة: ينقل مبلغ من الأقساط الجاية لآخر راتب (قسط بتاريخ قطع المسير)، والباقي قسط واحد يسدد نقداً.
-- p_amount فارغ = الأقل بين الباقي وصافي آخر راتب. يرجع المبلغ اللي انخصم.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.settle_loan_on_exit(p_employee_id uuid, p_month text, p_amount numeric DEFAULT NULL)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_emp employees%ROWTYPE;
  v_future numeric;
  v_take numeric;
  v_left numeric;
  v_loan record;
  v_part numeric;
  v_rest numeric;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  IF NOT FOUND OR v_p.status <> 'open' THEN
    RAISE EXCEPTION 'مسير % مو مفتوح.', p_month USING ERRCODE = '55000';
  END IF;
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  IF v_emp.termination_date IS NULL OR v_emp.termination_date > v_p.cutoff_date OR v_emp.termination_date < v_p.start_date THEN
    RAISE EXCEPTION 'الموظف ما ترك العمل خلال هذا المسير.' USING ERRCODE = '55000';
  END IF;
  IF EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = p_employee_id AND work_month = p_month) THEN
    RAISE EXCEPTION 'راتبه الأخير صادر. ألغِ الاعتماد أولاً.' USING ERRCODE = '55000';
  END IF;

  SELECT COALESCE(sum(li.amount), 0) INTO v_future
  FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid AND li.due_date > v_p.cutoff_date;
  IF v_future <= 0 THEN
    RAISE EXCEPTION 'ماكو أقساط باقية بعد هذا المسير.' USING ERRCODE = '55000';
  END IF;

  v_take := round(COALESCE(p_amount, LEAST(v_future, GREATEST((public.payroll_employee_summary(p_employee_id, p_month) ->> 'net')::numeric, 0))));
  IF v_take <= 0 OR v_take > v_future THEN
    RAISE EXCEPTION 'المبلغ لازم يكون بين 1 و %.', to_char(v_future, 'FM999,999,999') USING ERRCODE = '22023';
  END IF;

  PERFORM set_config('loans.skip_rebalance', 'on', true);
  v_left := v_take;
  FOR v_loan IN
    SELECT l.id, sum(li.amount) AS future
    FROM loans l JOIN loan_installments li ON li.loan_id = l.id
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid AND li.due_date > v_p.cutoff_date
    GROUP BY l.id, l.created_at ORDER BY l.created_at
  LOOP
    v_part := LEAST(v_left, v_loan.future);
    v_rest := v_loan.future - v_part;
    DELETE FROM loan_installments WHERE loan_id = v_loan.id AND NOT is_paid AND due_date > v_p.cutoff_date;
    IF v_part > 0 THEN
      INSERT INTO loan_installments (loan_id, due_date, amount, is_paid, amount_locked, payment_type, payment_note)
      VALUES (v_loan.id, v_p.cutoff_date, v_part, false, true, 'salary_deduction', 'تسوية ترك العمل من آخر راتب');
    END IF;
    IF v_rest > 0 THEN
      INSERT INTO loan_installments (loan_id, due_date, amount, is_paid, amount_locked, payment_type, payment_note)
      VALUES (v_loan.id, (v_p.cutoff_date + interval '1 month')::date, v_rest, false, true, 'cash', 'يسدد نقداً بعد ترك العمل');
    END IF;
    v_left := v_left - v_part;
  END LOOP;
  PERFORM set_config('loans.skip_rebalance', 'off', true);

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (p_employee_id, 'تسوية السلفة 💸',
          format('بسبب ترك العمل ينخصم %s د.ع من آخر راتب.%s', to_char(v_take, 'FM999,999,999'),
                 CASE WHEN v_future > v_take THEN format(' الباقي %s د.ع يسدد نقداً.', to_char(v_future - v_take, 'FM999,999,999')) ELSE '' END),
          'loan');
  RETURN v_take;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.settle_loan_on_exit(uuid, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.settle_loan_on_exit(uuid, text, numeric) TO authenticated;

-- ---------------------------------------------------------------------
-- تصليح عام: «استقطاع راتب» انسجل مسدد يدوياً (مو من كشف) على شهر رواتب بعده مفتوح وبدون كشف للموظف
-- ← يرجع غير مسدد بمبلغه (مقفل) حتى الكشف يخصمه، والباقي يتوزع (شهر جديد «باقي شهر …» إذا لزم).
-- ---------------------------------------------------------------------
DO $repair$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT li.id, li.due_date
    FROM loan_installments li
    JOIN loans l ON l.id = li.loan_id
    JOIN payroll_periods p ON li.due_date BETWEEN p.start_date AND p.cutoff_date AND p.status = 'open'
    WHERE li.is_paid AND li.payment_type = 'salary_deduction' AND li.paid_by_slip_id IS NULL
      AND l.status = 'approved' AND COALESCE(l.payment_method, '') <> 'cash'
      AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = l.employee_id AND s.work_month = p.period_month)
    ORDER BY li.due_date
  LOOP
    PERFORM set_config('loans.shortfall_origin', r.due_date::text, true);
    UPDATE loan_installments SET is_paid = false, paid_at = NULL, amount_locked = true WHERE id = r.id;
    PERFORM set_config('loans.shortfall_origin', '', true);
  END LOOP;
END
$repair$;
