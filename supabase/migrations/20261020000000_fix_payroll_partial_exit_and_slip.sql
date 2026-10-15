-- =====================================================================
-- المرحلة 3 من إصلاحات تدقيق 14/10/2026: معادلات الراتب (قرارات صاحب الشركة 15/10/2026).
-- (PAY-001) الراتب الجزئي:
--   • اللي تنتهي خدمته داخل المسير: أجر اليوم × أيام الدوام اللي خدمها (الجمع والعطل الرسمية ما تنحسب)، حتى لو ما بصم.
--     ينخصم بس اللي قررته الإدارة (غياب، تأخير، إجازة بدون راتب أو زمنية). آخر يوم بعد يوم القطع = ينحسب بالمسير اللي بعده
--     لحد آخر يومه، وكشفه ينعتمد بدون انتظار نهاية الفترة.
--   • المباشر بنص المسير: الراتب ناقص أجر الأيام قبل المباشرة (نفس قانون أي موظف من يوم مباشرته).
--     كان: أجر اليوم × الأيام بحد 30 — بمسير 28 يوم يوم ناقص = 3 أيام خصم، وبمسير 31 يوم = ولا شي.
--   • كل حساب ويا سطر يشرح شلون انحسب (basic_note) + معاينة «إنهاء خدمات» قبل التأكيد (end_of_service_preview).
-- (PAY-006) خصومات أكبر من الراتب: الكشف ينعتمد بصافي صفر (المسير ينغلق)، والزايد ينكتب سطر «يتسوى خارج النظام».
-- (PAY-010) إلغاء الاعتماد يرجّع الأقساط اللي نقصت أو تأجلت وقت الاعتماد مثل ما جانت (سجل payroll_loan_caps).
-- (PAY-011) سطور الكشف بالدينار، وسطر «فرق تقريب» إذا جمعها يختلف عن المجموع المقرّب.
-- (PAY-008) قرار: يبقى مثل ما هو (الغياب ما ينخصم إلا بقرار الإدارة، والجمع مدفوعة).
-- الكشوف المعتمدة ما تتغير.
-- =====================================================================

-- ---------------------------------------------------------------------
-- (PAY-001) حساب الراتب الأساسي للمسير + سطر الشرح
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
  v_basis text;
  v_note text;
  v_missing int;
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

  -- أيام الدوام ضمن الخدمة (حسب جدول الموظف بكل يوم، بدون الجمع/العطل الأسبوعية والرسمية)
  SELECT count(*) INTO v_scheduled
  FROM generate_series(v_from, v_to, interval '1 day') g(d)
  WHERE EXTRACT(DOW FROM g.d)::int = ANY (COALESCE((public.payroll_schedule_at(p_employee_id, g.d::date)).work_days, ARRAY[0, 1, 2, 3, 4, 6]))
    AND NOT EXISTS (SELECT 1 FROM official_holidays h WHERE h.holiday_date = g.d::date);

  IF v_employed_days <= 0 THEN
    v_basic := 0;
    v_basis := 'none';
    v_note := 'ما اشتغل بهالمسير';
  ELSIF v_emp.termination_date IS NOT NULL AND v_emp.termination_date < v_p.cutoff_date THEN
    -- نهاية خدمة داخل المسير: أيام الدوام اللي خدمها بس (قرار 15/10/2026)
    v_basic := round(v_daily * v_scheduled);
    v_basis := 'end_of_service';
    v_note := format('نهاية خدمة: %s يوم دوام من %s لحد %s (الجمع والعطل الرسمية ما تنحسب) × أجر اليوم %s = %s د.ع',
                     v_scheduled, to_char(v_from, 'DD/MM'), to_char(v_to, 'DD/MM'),
                     to_char(round(v_daily), 'FM999,999,999'), to_char(v_basic, 'FM999,999,999'));
  ELSIF v_employed_days < v_period_days THEN
    -- مباشرة بنص المسير: الراتب ناقص أجر الأيام قبل المباشرة (مثل خصم الغياب، مهما كان طول المسير)
    v_missing := v_period_days - v_employed_days;
    v_basic := GREATEST(v_month_basic - round(v_daily * v_missing), 0);
    v_basis := 'joined';
    v_note := format('باشر %s: الراتب %s ناقص %s يوم قبل المباشرة × أجر اليوم %s = %s د.ع',
                     to_char(v_from, 'DD/MM/YYYY'), to_char(v_month_basic, 'FM999,999,999'), v_missing,
                     to_char(round(v_daily), 'FM999,999,999'), to_char(v_basic, 'FM999,999,999'));
  ELSE
    v_basic := v_month_basic;
    v_basis := 'full';
    v_note := format('راتب المسير كامل: %s د.ع', to_char(v_month_basic, 'FM999,999,999'));
  END IF;

  SELECT
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = 1), 0) AS earnings,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = -1), 0) AS deductions,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = -1 AND event_type IN ('absence', 'late', 'early_leave', 'unpaid_leave')), 0) AS attendance_deductions,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND event_type = 'overtime'), 0) AS overtime,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND event_type = 'bonus'), 0) AS bonuses,
    count(*) FILTER (WHERE status = 'pending') AS pending,
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
    'basic_basis', v_basis,
    'basic_note', v_note,
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
    'has_schedule', (public.payroll_schedule_at(p_employee_id, LEAST(v_p.cutoff_date, (now() AT TIME ZONE public.company_timezone())::date))).id IS NOT NULL,
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
-- (PAY-010) سجل تعديلات الأقساط التلقائية وقت الاعتماد (حتى إلغاء الاعتماد يرجّعها)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payroll_loan_caps (
  id bigserial PRIMARY KEY,
  employee_id uuid NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  payroll_month text NOT NULL,
  salary_slip_id uuid,
  loan_id uuid NOT NULL,
  -- أقساط السلفة غير المسددة قبل التعديل (id, due_date, amount, amount_locked, payment_note, origin_kind, origin_month)
  installments_before jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_payroll_loan_caps_slip ON public.payroll_loan_caps (salary_slip_id);
ALTER TABLE public.payroll_loan_caps ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS payroll_loan_caps_admin_read ON public.payroll_loan_caps;
CREATE POLICY payroll_loan_caps_admin_read ON public.payroll_loan_caps FOR SELECT TO authenticated USING ((SELECT public.is_admin()));

CREATE OR REPLACE FUNCTION public._cap_loans_to_net(p_employee_id uuid, p_month text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_deficit numeric;
  v_cut numeric;
  v_total_cut numeric := 0;
  r record;
  v_new date;
BEGIN
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  v_deficit := -((public.payroll_employee_summary(p_employee_id, p_month) ->> 'net')::numeric);
  IF v_deficit IS NULL OR v_deficit <= 0 THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT li.* FROM loan_installments li JOIN loans l ON l.id = li.loan_id
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
      AND COALESCE(l.payment_method, '') <> 'cash'
      AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date
    ORDER BY li.due_date DESC, li.id DESC
  LOOP
    EXIT WHEN v_deficit <= 0;
    -- جدول السلفة قبل التعديل: إلغاء اعتماد الراتب يرجّعه (PAY-010)
    INSERT INTO payroll_loan_caps (employee_id, payroll_month, loan_id, installments_before)
    SELECT p_employee_id, p_month, r.loan_id, COALESCE(jsonb_agg(jsonb_build_object(
             'id', x.id, 'due_date', x.due_date, 'amount', x.amount, 'amount_locked', x.amount_locked,
             'payment_note', x.payment_note, 'origin_kind', x.origin_kind, 'origin_month', x.origin_month)), '[]'::jsonb)
    FROM loan_installments x WHERE x.loan_id = r.loan_id AND NOT x.is_paid;

    v_cut := LEAST(v_deficit, r.amount);
    IF v_cut < r.amount THEN
      -- ينقص هالشهر، والنقص شهر جديد بالأخير «باقي شهر …»
      PERFORM set_config('loans.shortfall_origin', r.due_date::text, true);
      UPDATE loan_installments
      SET amount = r.amount - v_cut, amount_locked = true,
          payment_note = COALESCE(payment_note, 'نقص تلقائياً: الراتب ما يكفي')
      WHERE id = r.id;
      PERFORM set_config('loans.shortfall_origin', '', true);
    ELSE
      -- ما يبقى شي من الراتب لهالقسط: يتأجل لآخر السلفة
      SELECT (max(due_date) + interval '1 month')::date INTO v_new FROM loan_installments WHERE loan_id = r.loan_id;
      UPDATE loan_installments
      SET due_date = v_new, origin_kind = 'postponed', origin_month = COALESCE(origin_month, r.due_date), amount_locked = false,
          payment_note = COALESCE(payment_note, 'تأجيل تلقائي: الراتب ما يكفي')
      WHERE id = r.id;
    END IF;
    v_deficit := v_deficit - v_cut;
    v_total_cut := v_total_cut + v_cut;
  END LOOP;

  IF v_total_cut > 0 THEN
    INSERT INTO notifications (employee_id, title, body, type)
    VALUES (p_employee_id, 'تعديل قسط السلفة 💸',
            format('راتب شهر %s ما يكفي للقسط كامل، فانخصم أقل بـ %s د.ع والباقي انضاف بآخر السلفة.',
                   p_month, to_char(v_total_cut, 'FM999,999,999')),
            'loan');
  END IF;
  RETURN v_total_cut;
END;
$function$;

-- ---------------------------------------------------------------------
-- الاعتماد: (PAY-006) صافي ما ينزل تحت الصفر، (PAY-011) سطور بالدينار + فرق التقريب، (PAY-010) ربط سجل الأقساط بالكشف
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_payroll_slip(p_employee_id uuid, p_month text, p_adjustments jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_sum jsonb;
  v_slip uuid;
  v_adj jsonb;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_term date;
  v_earn numeric;
  v_ded numeric;
  v_net numeric;
  v_excess numeric := 0;
  v_lines_earn numeric;
  v_lines_ded numeric;
  v_round_diff numeric;
BEGIN
  PERFORM public.require_admin();
  v_p := public.ensure_payroll_period(p_month);
  IF v_p.status <> 'open' OR EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month) THEN
    RAISE EXCEPTION 'مسير % مغلق. أعد فتحه أولاً.', p_month USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = p_employee_id AND work_month = p_month) THEN
    RAISE EXCEPTION 'تم صرف الراتب مسبقاً لهذا الموظف في هذا الشهر.' USING ERRCODE = '23505';
  END IF;
  -- الراتب ينعتمد بعد نهاية فترة الدوام، إلا آخر راتب لموظف ترك العمل (وآخر يوم دوامه فات)
  SELECT termination_date INTO v_term FROM employees WHERE id = p_employee_id;
  IF v_today <= v_p.cutoff_date
     AND NOT (v_term IS NOT NULL AND v_term BETWEEN v_p.start_date AND v_p.cutoff_date AND v_term < v_today) THEN
    RAISE EXCEPTION 'رواتب شهر % تنعتمد بعد نهاية الدوام المحسوب (من %). قبلها تكدر تعتمد بس آخر راتب لموظف ترك العمل.',
      p_month, to_char(v_p.cutoff_date + 1, 'DD/MM/YYYY') USING ERRCODE = '55000';
  END IF;

  PERFORM public.sync_payroll_period(p_month, p_employee_id);

  -- تعديلات يدوية وقت الاعتماد (مكافأة/خصم إضافي بسبب)
  FOR v_adj IN SELECT * FROM jsonb_array_elements(COALESCE(p_adjustments, '[]'::jsonb)) LOOP
    CONTINUE WHEN COALESCE((v_adj ->> 'amount')::numeric, 0) <= 0;
    INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, status, source, notes, created_by)
    VALUES (p_employee_id, v_p.cutoff_date,
            CASE WHEN v_adj ->> 'type' = 'bonus' THEN 'bonus' ELSE 'manual_deduction' END,
            round((v_adj ->> 'amount')::numeric),
            CASE WHEN v_adj ->> 'type' = 'bonus' THEN 1 ELSE -1 END,
            p_month, 'approved', 'approval', v_adj ->> 'reason', auth.uid());
  END LOOP;

  -- قسط السلفة ما يخلي الصافي بالسالب: ينقص بقد الممكن والباقي بآخر السلفة
  PERFORM public._cap_loans_to_net(p_employee_id, p_month);

  v_sum := public.payroll_employee_summary(p_employee_id, p_month);
  v_earn := (v_sum ->> 'earnings')::numeric;
  v_ded := (v_sum ->> 'deductions')::numeric;
  v_net := (v_sum ->> 'net')::numeric;
  -- (PAY-006) خصومات أكبر من الراتب (بعد ما الأقساط نزلت لصفر): الصافي صفر والزايد يتسوى خارج النظام، والمسير ينغلق
  IF v_net < 0 THEN
    v_excess := -v_net;
    v_ded := v_ded - v_excess;
    v_net := 0;
  END IF;

  INSERT INTO salary_slips (employee_id, work_month, basic_salary, allowances, deductions, loans_deduction, net_salary, status, computed_by_engine)
  VALUES (p_employee_id, p_month, (v_sum ->> 'basic')::numeric, v_earn, v_ded, (v_sum ->> 'loans')::numeric, v_net, 'published', true)
  RETURNING id INTO v_slip;

  -- (PAY-011) السطور بالدينار (المجموع ينحسب مقرّب مرة وحدة، والفرق سطر واضح)
  INSERT INTO salary_slip_lines (salary_slip_id, event_id, line_type, event_date, minutes, days, amount, direction, notes, carried_from)
  SELECT v_slip, pe.id, pe.event_type, pe.event_date, pe.minutes, pe.days, round(pe.amount), pe.direction, pe.notes, pe.carried_from
  FROM payroll_events pe
  WHERE pe.employee_id = p_employee_id AND pe.payroll_month = p_month AND pe.status = 'approved'
    AND (pe.amount > 0 OR pe.event_type = 'paid_leave');

  SELECT COALESCE(sum(amount) FILTER (WHERE direction = 1), 0), COALESCE(sum(amount) FILTER (WHERE direction = -1), 0)
  INTO v_lines_earn, v_lines_ded
  FROM salary_slip_lines WHERE salary_slip_id = v_slip;
  v_round_diff := (v_earn - v_lines_earn) - ((v_sum ->> 'deductions')::numeric - v_lines_ded);
  IF v_round_diff <> 0 THEN
    INSERT INTO salary_slip_lines (salary_slip_id, line_type, event_date, amount, direction, notes)
    VALUES (v_slip, 'rounding', v_p.cutoff_date, abs(v_round_diff), sign(v_round_diff)::smallint,
            'فرق تقريب: المجموع يتقرّب لأقرب دينار مرة وحدة');
  END IF;

  INSERT INTO salary_slip_lines (salary_slip_id, line_type, event_date, amount, direction, notes)
  SELECT v_slip, 'loan', li.due_date, li.amount, -1, 'قسط سلفة'
  FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  IF v_excess > 0 THEN
    INSERT INTO salary_slip_lines (salary_slip_id, line_type, event_date, amount, direction, notes)
    VALUES (v_slip, 'excess_deduction', v_p.cutoff_date, v_excess, 1,
            format('خصومات أكثر من الراتب بـ %s د.ع: ما انخصمت من الكشف (الصافي صفر) وتتسوى ويا الموظف خارج النظام',
                   to_char(v_excess, 'FM999,999,999')));
  END IF;

  UPDATE payroll_events SET salary_slip_id = v_slip, updated_at = now()
  WHERE employee_id = p_employee_id AND payroll_month = p_month AND status = 'approved';

  UPDATE loan_installments li
  SET is_paid = true, paid_at = now(), paid_by_slip_id = v_slip
  FROM loans l
  WHERE li.loan_id = l.id AND l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  -- (PAY-010) تعديلات الأقساط التلقائية تخص هالكشف
  UPDATE payroll_loan_caps SET salary_slip_id = v_slip
  WHERE employee_id = p_employee_id AND payroll_month = p_month AND salary_slip_id IS NULL;

  RETURN v_slip;
END;
$function$;

-- ---------------------------------------------------------------------
-- إلغاء الاعتماد: (PAY-010) يرجّع جدول الأقساط مثل ما جان قبل الاعتماد
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.revert_payroll_slip(p_slip_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_slip salary_slips%ROWTYPE;
  v_p payroll_periods%ROWTYPE;
  c record;
  v_before_ids uuid[];
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_slip FROM salary_slips WHERE id = p_slip_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'كشف الراتب غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = v_slip.work_month;
  IF (FOUND AND v_p.status <> 'open') OR EXISTS (SELECT 1 FROM archived_months WHERE work_month = v_slip.work_month) THEN
    RAISE EXCEPTION 'مسير % مغلق. أعد فتحه أولاً.', v_slip.work_month USING ERRCODE = '42501';
  END IF;

  IF NOT v_slip.computed_by_engine THEN
    -- كشف قديم (أرقام من المتصفح): نفس التراجع السابق، وحركات أيامه تعود لتُحتسب
    UPDATE payroll_events SET salary_slip_id = NULL, updated_at = now() WHERE salary_slip_id = p_slip_id;
    PERFORM public.revert_salary_slip(
      p_slip_id,
      COALESCE(v_p.start_date, (v_slip.work_month || '-01')::date),
      COALESCE(v_p.cutoff_date, ((v_slip.work_month || '-01')::date + interval '1 month - 1 day')::date));
    RETURN;
  END IF;

  DELETE FROM payroll_events WHERE salary_slip_id = p_slip_id AND source = 'approval';
  UPDATE payroll_events SET salary_slip_id = NULL, updated_at = now() WHERE salary_slip_id = p_slip_id;
  UPDATE loan_installments SET is_paid = false, paid_at = NULL, paid_by_slip_id = NULL WHERE paid_by_slip_id = p_slip_id;

  -- (PAY-010) الأقساط اللي نقصت/تأجلت وقت الاعتماد ترجع مثل ما جانت (أول نسخة لكل سلفة = قبل أي تعديل).
  -- بس إذا جدول السلفة ما تغيّر بعدها (ما انسدد قسط منها ولا انعادت جدولتها)؛ غير هيج يبقى الجدول الحالي (مجموعه صحيح).
  PERFORM set_config('loans.skip_rebalance', 'on', true);
  FOR c IN
    SELECT DISTINCT ON (loan_id) loan_id, installments_before
    FROM payroll_loan_caps WHERE salary_slip_id = p_slip_id
    ORDER BY loan_id, id
  LOOP
    SELECT COALESCE(array_agg((x ->> 'id')::uuid), '{}') INTO v_before_ids FROM jsonb_array_elements(c.installments_before) x;
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM unnest(v_before_ids) b(id)
      WHERE NOT EXISTS (SELECT 1 FROM loan_installments li WHERE li.id = b.id AND li.loan_id = c.loan_id AND NOT li.is_paid));
    CONTINUE WHEN (SELECT COALESCE(sum((x ->> 'amount')::numeric), 0) FROM jsonb_array_elements(c.installments_before) x)
      IS DISTINCT FROM (SELECT l.amount - COALESCE((SELECT sum(amount) FROM loan_installments WHERE loan_id = l.id AND is_paid), 0)
                        FROM loans l WHERE l.id = c.loan_id);
    DELETE FROM loan_installments WHERE loan_id = c.loan_id AND NOT is_paid AND NOT (id = ANY (v_before_ids));
    UPDATE loan_installments li
    SET due_date = (x ->> 'due_date')::date, amount = (x ->> 'amount')::numeric,
        amount_locked = (x ->> 'amount_locked')::boolean, payment_note = x ->> 'payment_note',
        origin_kind = x ->> 'origin_kind', origin_month = (x ->> 'origin_month')::date
    FROM jsonb_array_elements(c.installments_before) x
    WHERE li.id = (x ->> 'id')::uuid AND NOT li.is_paid;
    UPDATE loans l
    SET remaining_amount = GREATEST(l.amount - COALESCE((SELECT sum(amount) FROM loan_installments WHERE loan_id = l.id AND is_paid), 0), 0)
    WHERE l.id = c.loan_id;
  END LOOP;
  PERFORM set_config('loans.skip_rebalance', 'off', true);
  DELETE FROM payroll_loan_caps WHERE salary_slip_id = p_slip_id;

  DELETE FROM bonuses_deductions WHERE salary_slip_id = p_slip_id;
  DELETE FROM salary_slips WHERE id = p_slip_id;
END;
$function$;

-- ---------------------------------------------------------------------
-- (PAY-001) معاينة «إنهاء خدمات»: شلون راح ينحسب آخر راتب لو آخر يوم = p_last_day (بدون ما يتغير شي)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.end_of_service_preview(p_employee_id uuid, p_last_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp employees%ROWTYPE;
  v_last_month text;
  v_month text;
  v_p payroll_periods%ROWTYPE;
  v_periods jsonb := '[]'::jsonb;
  v_total numeric := 0;
  v_loans_left numeric := 0;
  v_cut_total numeric := 0;
  v_s jsonb;
  v_net numeric;
  v_loans numeric;
  v_result jsonb;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF p_last_day IS NULL OR (v_emp.join_date IS NOT NULL AND p_last_day < v_emp.join_date) THEN
    RAISE EXCEPTION 'آخر يوم عمل لازم يكون بعد تاريخ المباشرة.' USING ERRCODE = '22023';
  END IF;

  v_last_month := public.payroll_month_of(p_last_day);
  BEGIN
    -- نجرّب: آخر يوم + إعادة حساب المسيرات المفتوحة، ونقرا النتيجة، وبعدها كلشي يتراجع (ما ينحفظ شي)
    UPDATE employees SET termination_date = p_last_day WHERE id = p_employee_id;
    FOR v_month IN
      SELECT pp.period_month FROM payroll_periods pp
      WHERE pp.status = 'open' AND pp.period_month <= v_last_month
        AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = p_employee_id AND s.work_month = pp.period_month)
      UNION
      SELECT v_last_month
      ORDER BY 1
    LOOP
      v_p := public.ensure_payroll_period(v_month);
      CONTINUE WHEN v_p.status <> 'open' OR EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = p_employee_id AND s.work_month = v_month);
      PERFORM public.sync_payroll_period(v_month, p_employee_id);
      v_s := public.payroll_employee_summary(p_employee_id, v_month);
      CONTINUE WHEN (v_s ->> 'employed_days')::int = 0 AND (v_s ->> 'net')::numeric = 0;
      v_net := (v_s ->> 'net')::numeric;
      v_loans := (v_s ->> 'loans')::numeric;
      v_periods := v_periods || jsonb_build_array(jsonb_build_object(
        'month', v_month, 'start_date', v_p.start_date, 'cutoff_date', v_p.cutoff_date,
        'can_approve_now', p_last_day < (now() AT TIME ZONE public.company_timezone())::date OR v_p.cutoff_date < (now() AT TIME ZONE public.company_timezone())::date,
        -- مثل الاعتماد: القسط ينقص بقد الراتب، وإذا الخصومات بعدها أكثر = صافي صفر والزايد خارج النظام
        'expected_net', GREATEST(v_net, 0),
        'loan_cut', LEAST(v_loans, GREATEST(-v_net, 0)),
        'excess_deductions', GREATEST(-(v_net + v_loans), 0),
        'summary', v_s));
      v_total := v_total + GREATEST(v_net, 0);
      v_cut_total := v_cut_total + LEAST(v_loans, GREATEST(-v_net, 0));
    END LOOP;
    SELECT COALESCE(sum(li.amount), 0) INTO v_loans_left
    FROM loan_installments li JOIN loans l ON l.id = li.loan_id
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
      AND li.due_date > (SELECT cutoff_date FROM payroll_periods WHERE period_month = v_last_month);
    -- الباقي من السلف بعد آخر راتب (مع الأقساط اللي تنقص لأن الراتب ما يكفي): الشركة تسويه ويا الموظف خارج النظام
    v_result := jsonb_build_object('employee_id', p_employee_id, 'last_day', p_last_day, 'periods', v_periods,
                                   'total_net', v_total, 'loans_left_after', v_loans_left + v_cut_total);
    RAISE EXCEPTION 'preview_rollback' USING ERRCODE = 'P0001';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'preview_rollback' THEN
      RAISE;
    END IF;
  END;
  RETURN v_result;
END;
$function$;
REVOKE ALL ON FUNCTION public.end_of_service_preview(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.end_of_service_preview(uuid, date) TO authenticated;
