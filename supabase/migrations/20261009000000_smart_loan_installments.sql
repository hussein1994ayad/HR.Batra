-- =====================================================================
-- أقساط سلف ذكية: القسط الشهري هو الأساس.
--   • الشهر اللي الموظف ما يكدر يدفع بيه كامل: set_month_installment (المبلغ المخفّض ينخصم من راتب ذاك الشهر)،
--     والنقص يصير شهر جديد بالأخير مكتوب عليه «باقي شهر MM/YYYY».
--   • الدفع الأقل بـ pay_loan_installment: نفس الشي (النقص = شهر جديد بالأخير، مو زيادة على آخر قسط).
--   • التأجيل: postpone_loan_installment ينقل قسط الشهر لشهر جديد بالأخير بملاحظة، والباقي ما يتغير.
--   • تعديل السلفة: reschedule_loan يكتب أقساط بالقسط الشهري بالضبط (آخرها الباقي) ويبدي من شهر الرواتب
--     المفتوح إذا كشفه ما صادر (قبل: يوزع بالتساوي ويبدي دائماً من الشهر الجاي فيضيع شهر).
--   • تصليح سلفة 632f0aaf… (محمي بشكل جدولها الحالي).
-- =====================================================================

ALTER TABLE public.loan_installments ADD COLUMN IF NOT EXISTS origin_kind text
  CHECK (origin_kind IN ('shortfall', 'postponed'));
ALTER TABLE public.loan_installments ADD COLUMN IF NOT EXISTS origin_month date;
ALTER TABLE public.loan_installments ADD COLUMN IF NOT EXISTS amount_locked boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.loan_installments.origin_kind IS 'shortfall = باقي شهر ما انسدد كامل؛ postponed = قسط شهر مؤجّل';
COMMENT ON COLUMN public.loan_installments.origin_month IS 'الشهر الأصلي (للعرض: «باقي شهر 10/2026» أو «مؤجّل من 12/2026»)';
COMMENT ON COLUMN public.loan_installments.amount_locked IS 'مبلغ ثابت حدده الأدمن لهالشهر؛ إعادة التوزيع ما تغيّره';

-- ---------------------------------------------------------------------
-- إعادة التوزيع بعد أي سداد/تعديل مبلغ: كل قسط غير مسدد = أقل شي بين القسط الشهري والباقي (بالترتيب، والمقفل
-- يبقى بمبلغه)، والزايد = أشهر جديدة بالأخير (كل شهر ≤ القسط الشهري) تتعلّم «باقي شهر …».
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_loan_and_installments_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_loan_id uuid;
    v_loan_amount numeric;
    v_base numeric;
    v_total_paid numeric;
    v_new_remaining numeric;
    v_left numeric;
    v_alloc numeric;
    v_row record;
    v_last_due date;
    v_origin date;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_loan_id := OLD.loan_id;
    ELSE
        v_loan_id := NEW.loan_id;
    END IF;

    -- إعادة الجدولة من reschedule_loan تكتب الجدول كاملاً بنفسها: لا توليد تلقائي أثناءها
    IF current_setting('loans.skip_rebalance', true) = 'on' THEN
        RETURN NULL;
    END IF;

    IF pg_trigger_depth() = 1 THEN
        -- قفل السلفة: تعديلان متزامنان لا يولّدان نفس الأشهر مرتين
        SELECT amount, installment_amount INTO v_loan_amount, v_base
        FROM public.loans WHERE id = v_loan_id FOR UPDATE;
        IF NOT FOUND THEN
            RETURN NULL;
        END IF;

        SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
        FROM public.loan_installments WHERE loan_id = v_loan_id AND is_paid;
        v_new_remaining := GREATEST(v_loan_amount - v_total_paid, 0);

        UPDATE public.loans SET remaining_amount = v_new_remaining WHERE id = v_loan_id;

        IF v_new_remaining <= 0 THEN
            DELETE FROM public.loan_installments WHERE loan_id = v_loan_id AND NOT is_paid;
            RETURN NULL;
        END IF;

        v_left := v_new_remaining;
        FOR v_row IN
            SELECT id, amount, amount_locked FROM public.loan_installments
            WHERE loan_id = v_loan_id AND NOT is_paid
            ORDER BY due_date, id
        LOOP
            IF v_left <= 0 THEN
                DELETE FROM public.loan_installments WHERE id = v_row.id;
                CONTINUE;
            END IF;
            v_alloc := CASE WHEN v_row.amount_locked THEN LEAST(v_row.amount, v_left) ELSE LEAST(v_base, v_left) END;
            IF v_alloc IS DISTINCT FROM v_row.amount THEN
                UPDATE public.loan_installments SET amount = v_alloc WHERE id = v_row.id;
            END IF;
            v_left := v_left - v_alloc;
        END LOOP;

        IF v_left > 0 THEN
            -- من وين جا النقص: الشهر اللي حدده الأدمن، أو القسط اللي انسدد بأقل من القسط الشهري
            v_origin := NULLIF(current_setting('loans.shortfall_origin', true), '')::date;
            IF v_origin IS NULL AND TG_OP = 'UPDATE' AND NEW.is_paid AND NOT OLD.is_paid AND NEW.amount < v_base THEN
                v_origin := NEW.due_date;
            END IF;

            SELECT COALESCE(MAX(due_date), (now() AT TIME ZONE public.company_timezone())::date) INTO v_last_due
            FROM public.loan_installments WHERE loan_id = v_loan_id;

            WHILE v_left > 0 LOOP
                v_last_due := (v_last_due + interval '1 month')::date;
                v_alloc := LEAST(v_base, v_left);
                INSERT INTO public.loan_installments (loan_id, due_date, amount, is_paid, origin_kind, origin_month)
                VALUES (v_loan_id, v_last_due, v_alloc, false,
                        CASE WHEN v_origin IS NOT NULL THEN 'shortfall' END, v_origin);
                v_left := v_left - v_alloc;
            END LOOP;
        END IF;
    END IF;

    RETURN NULL;
END;
$function$;

-- ---------------------------------------------------------------------
-- يرجع شهر الرواتب اللي يقع بيه تاريخ القسط، وهل كشف الموظف لذاك الشهر صادر (أو الفترة مقفلة).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._loan_month_settled(p_employee_id uuid, p_due date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM payroll_periods p
    WHERE p_due BETWEEN p.start_date AND p.cutoff_date
      AND (p.status = 'closed'
           OR EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = p_employee_id AND s.work_month = p.period_month)));
$function$;

REVOKE EXECUTE ON FUNCTION public._loan_month_settled(uuid, date) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- «هالشهر يكدر يدفع بس X»: القسط يبقى غير مسدد بمبلغ X ثابت (الرواتب تخصمه)، والنقص شهر جديد بالأخير.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_month_installment(p_installment_id uuid, p_amount numeric, p_note text DEFAULT NULL)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_inst loan_installments%ROWTYPE;
  v_loan loans%ROWTYPE;
  v_last date;
BEGIN
  PERFORM public.require_admin();
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
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'اكتب المبلغ اللي يكدر يدفعه (أكبر من صفر). إذا ما يكدر يدفع شي، استعمل التأجيل.' USING ERRCODE = '22023';
  END IF;
  IF round(p_amount) >= v_inst.amount THEN
    RAISE EXCEPTION 'المبلغ لازم يكون أقل من قسط الشهر (%).', to_char(v_inst.amount, 'FM999,999,999') USING ERRCODE = '22023';
  END IF;
  IF public._loan_month_settled(v_loan.employee_id, v_inst.due_date) THEN
    RAISE EXCEPTION 'راتب هذا الشهر صادر أو الفترة مقفلة؛ ما يتغير قسطه.' USING ERRCODE = '55000';
  END IF;

  PERFORM set_config('loans.shortfall_origin', v_inst.due_date::text, true);
  UPDATE loan_installments
  SET amount = round(p_amount), amount_locked = true,
      payment_note = COALESCE(NULLIF(btrim(COALESCE(p_note, '')), ''), payment_note)
  WHERE id = p_installment_id;
  PERFORM set_config('loans.shortfall_origin', '', true);

  SELECT max(due_date) INTO v_last FROM loan_installments WHERE loan_id = v_loan.id;
  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (v_loan.employee_id, 'تعديل قسط السلفة 💸',
          format('قسط شهر %s صار %s د.ع، والباقي (%s د.ع) انضاف بآخر السلفة. آخر قسط بشهر %s.',
                 to_char(v_inst.due_date, 'MM/YYYY'), to_char(round(p_amount), 'FM999,999,999'),
                 to_char(v_inst.amount - round(p_amount), 'FM999,999,999'), to_char(v_last, 'MM/YYYY')),
          'loan');
  RETURN (SELECT remaining_amount FROM loans WHERE id = v_loan.id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.set_month_installment(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_month_installment(uuid, numeric, text) TO authenticated;

-- ---------------------------------------------------------------------
-- تأجيل قسط شهر: ينتقل لشهر جديد بعد آخر قسط (بملاحظة)، والأقساط الثانية ما تتغير.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.postpone_loan_installment(p_installment_id uuid, p_note text DEFAULT NULL)
 RETURNS date
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_inst loan_installments%ROWTYPE;
  v_loan loans%ROWTYPE;
  v_new date;
BEGIN
  PERFORM public.require_admin();
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
  IF public._loan_month_settled(v_loan.employee_id, v_inst.due_date) THEN
    RAISE EXCEPTION 'راتب هذا الشهر صادر أو الفترة مقفلة؛ ما يتأجل قسطه.' USING ERRCODE = '55000';
  END IF;

  SELECT (max(due_date) + interval '1 month')::date INTO v_new FROM loan_installments WHERE loan_id = v_loan.id;
  -- تغيير التاريخ بس (المبلغ نفسه)، فالتريجر ما يعيد التوزيع
  UPDATE loan_installments
  SET due_date = v_new, origin_kind = 'postponed', origin_month = COALESCE(origin_month, v_inst.due_date),
      amount_locked = false,
      payment_note = COALESCE(NULLIF(btrim(COALESCE(p_note, '')), ''), payment_note)
  WHERE id = p_installment_id;

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (v_loan.employee_id, 'تأجيل قسط السلفة 📅',
          format('تم تأجيل قسط شهر %s (%s د.ع) إلى شهر %s.%s', to_char(v_inst.due_date, 'MM/YYYY'),
                 to_char(v_inst.amount, 'FM999,999,999'), to_char(v_new, 'MM/YYYY'),
                 COALESCE(' ملاحظة: ' || NULLIF(btrim(COALESCE(p_note, '')), ''), '')),
          'loan');
  RETURN v_new;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.postpone_loan_installment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.postpone_loan_installment(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- تعديل السلفة: أقساط بالقسط الشهري بالضبط وآخرها الباقي؛ العدد ينحسب. يبدي من شهر الرواتب المفتوح إذا كشف
-- الموظف لذاك الشهر ما صادر، وإلا الشهر اللي بعده. (p_count باقي بالتوقيع للتوافق ويُتجاهل.)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reschedule_loan(p_loan_id uuid, p_amount numeric, p_installment_amount numeric, p_count integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_loan loans%ROWTYPE;
  v_paid numeric;
  v_paid_count integer;
  v_remaining numeric;
  v_base numeric := round(p_installment_amount);
  v_n integer := 0;
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_month text;
  v_first date;
  i integer;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_loan FROM loans WHERE id = p_loan_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'السلفة غير موجودة.' USING ERRCODE = 'P0002';
  END IF;
  IF v_loan.status <> 'approved' THEN
    RAISE EXCEPTION 'يمكن تعديل السلف المعتمدة فقط.' USING ERRCODE = '55000';
  END IF;
  IF COALESCE(p_amount, 0) <= 0 OR COALESCE(v_base, 0) <= 0 THEN
    RAISE EXCEPTION 'اكتب مبلغاً وقسطاً شهرياً أكبر من الصفر.' USING ERRCODE = '22023';
  END IF;
  IF v_base > p_amount THEN
    RAISE EXCEPTION 'القسط أكبر من مبلغ السلفة.' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(sum(amount), 0), count(*) INTO v_paid, v_paid_count
  FROM loan_installments WHERE loan_id = p_loan_id AND is_paid;
  v_remaining := round(p_amount - v_paid);
  IF v_remaining < 0 THEN
    RAISE EXCEPTION 'المبلغ الجديد أقل من المسدَّد (%).', to_char(v_paid, 'FM999,999,999') USING ERRCODE = '22023';
  END IF;
  IF v_remaining > 0 THEN
    v_n := ceil(v_remaining / v_base)::int;
  END IF;

  -- أول شهر: شهر الرواتب المفتوح الحالي إذا كشفه ما صادر، وإلا اللي بعده (بدون فترة مسجّلة: الشهر الجاي)
  SELECT period_month, GREATEST(to_date(period_month || '-01', 'YYYY-MM-DD'), start_date) INTO v_month, v_first
  FROM payroll_periods WHERE v_today BETWEEN start_date AND cutoff_date LIMIT 1;
  IF v_month IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM payroll_periods WHERE period_month = v_month AND status = 'closed')
       OR EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = v_loan.employee_id AND work_month = v_month) THEN
      v_first := (date_trunc('month', v_first) + interval '1 month')::date;
    END IF;
  ELSE
    v_first := (date_trunc('month', v_today) + interval '1 month')::date;
  END IF;

  -- الجدول يُكتب هنا كاملاً: التريجر لا يولّد أقساطاً أثناء الحذف والإضافة
  PERFORM set_config('loans.skip_rebalance', 'on', true);

  UPDATE loans
  SET amount = round(p_amount), installment_amount = v_base,
      installment_count = v_paid_count + v_n, remaining_amount = v_remaining
  WHERE id = p_loan_id;

  DELETE FROM loan_installments WHERE loan_id = p_loan_id AND NOT is_paid;

  FOR i IN 0 .. v_n - 1 LOOP
    INSERT INTO loan_installments (loan_id, due_date, amount, is_paid)
    VALUES (p_loan_id, (v_first + make_interval(months => i))::date,
            CASE WHEN i = v_n - 1 THEN v_remaining - v_base * (v_n - 1) ELSE v_base END, false);
  END LOOP;

  PERFORM set_config('loans.skip_rebalance', 'off', true);

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (v_loan.employee_id, 'تعديل تفاصيل السلفة 💸',
          CASE WHEN v_n = 0 THEN format('قامت الإدارة بتعديل سلفتك: المبلغ الكلي %s د.ع، والسلفة مسددة بالكامل.',
                                        to_char(round(p_amount), 'FM999,999,999'))
               ELSE format('قامت الإدارة بتعديل سلفتك: المبلغ الكلي %s د.ع، القسط الشهري %s د.ع، المتبقي %s د.ع على %s قسط من شهر %s إلى شهر %s.',
                           to_char(round(p_amount), 'FM999,999,999'), to_char(v_base, 'FM999,999,999'),
                           to_char(v_remaining, 'FM999,999,999'), v_n, to_char(v_first, 'MM/YYYY'),
                           to_char((v_first + make_interval(months => v_n - 1))::date, 'MM/YYYY')) END,
          'loan');
  RETURN v_n;
END;
$function$;

-- ---------------------------------------------------------------------
-- تصليح سلفة 632f0aaf… (10,000,000): الـ 100,000 انسجلت «مسددة» على قسط شهر 11 يوم 4/10، فشهر 10 ضاع
-- والرواتب ما راح تخصمها، وبعدها التعديل وزّع الباقي بالتساوي (710,256). الصح: قسط شهر 10 = 100,000 غير مسدد
-- (ينخصم من راتب شهر 10)، بعدها 700,000 شهرياً، وآخر شهر الباقي «باقي شهر 10/2026».
-- ينفذ بس إذا الجدول بعده بنفس الشكل وكشف شهر 10 ما صادر.
-- ---------------------------------------------------------------------
DO $repair$
DECLARE
  v_loan_id uuid := '632f0aaf-fade-45a1-a60f-ad79e3c31df1';
  v_loan loans%ROWTYPE;
  v_row uuid;
  v_left numeric;
  v_due date := '2026-11-01';
BEGIN
  SELECT * INTO v_loan FROM loans WHERE id = v_loan_id FOR UPDATE;
  IF NOT FOUND OR v_loan.status <> 'approved' OR v_loan.installment_amount <> 700000 THEN
    RETURN;
  END IF;
  SELECT id INTO v_row FROM loan_installments
  WHERE loan_id = v_loan_id AND is_paid AND amount = 100000 AND due_date = '2026-11-01' AND paid_by_slip_id IS NULL;
  IF v_row IS NULL
     OR (SELECT count(*) FROM loan_installments WHERE loan_id = v_loan_id AND NOT is_paid AND amount IN (710256, 710261)) <> 13
     OR (SELECT count(*) FROM loan_installments WHERE loan_id = v_loan_id AND NOT is_paid) <> 13
     OR EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = v_loan.employee_id AND work_month = '2026-10') THEN
    RETURN;
  END IF;

  PERFORM set_config('loans.skip_rebalance', 'on', true);
  DELETE FROM loan_installments WHERE loan_id = v_loan_id AND NOT is_paid;
  UPDATE loan_installments
  SET is_paid = false, paid_at = NULL, due_date = '2026-10-01', amount_locked = true, payment_type = 'salary_deduction'
  WHERE id = v_row;

  v_left := v_loan.amount - COALESCE((SELECT sum(amount) FROM loan_installments WHERE loan_id = v_loan_id AND is_paid), 0) - 100000;
  WHILE v_left > 0 LOOP
    INSERT INTO loan_installments (loan_id, due_date, amount, is_paid, origin_kind, origin_month)
    VALUES (v_loan_id, v_due, LEAST(700000, v_left), false,
            CASE WHEN v_left < 700000 THEN 'shortfall' END, CASE WHEN v_left < 700000 THEN '2026-10-01'::date END);
    v_left := v_left - LEAST(700000, v_left);
    v_due := (v_due + interval '1 month')::date;
  END LOOP;

  UPDATE loans
  SET remaining_amount = amount - COALESCE((SELECT sum(amount) FROM loan_installments WHERE loan_id = v_loan_id AND is_paid), 0),
      installment_count = (SELECT count(*) FROM loan_installments WHERE loan_id = v_loan_id)
  WHERE id = v_loan_id;
  PERFORM set_config('loans.skip_rebalance', 'off', true);
END
$repair$;
