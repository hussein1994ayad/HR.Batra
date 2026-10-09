-- =====================================================================
-- تصليحات الفلوس (فحص 2026-10-09):
--   1) حذف قسط مسدد كان يرجّع المبلغ دين على الموظف ← ممنوع (حذف السلفة كلها يبقى مسموح).
--   2) «التراجع عن السداد» على قسط انخصم من راتب معتمد كان يخليه ديناً معلّقاً ← ممنوع (الصح: إلغاء اعتماد الكشف).
--   3) خصومات/مكافآت يدوية مكررة من نسخة قديمة للتطبيق ← حماية من التكرار + منو سجّلها، وتنظيف المكرر الموجود.
--   4) الزيادة المجدولة ما كانت تنطبق (تاريخ بصيغة 2026/06/01) + تعديل الراتب كان يغيّر الأشهر المفتوحة القديمة
--      ← سجل رواتب بشهر سريان (salary_history)، والزيادة تنطبق من شهر رواتب تاريخها.
--   6) اعتماد الراتب قبل نهاية فترة الدوام ← ممنوع إلا لمن ترك العمل (آخر راتب).
--   8) صافي بالسالب بسبب قسط سلفة ← القسط ينقص بقد الراتب والباقي شهر جديد بالأخير (بدل ما يوقف الاعتماد).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) القسط المسدد ما ينحذف (إلا مع حذف السلفة كلها: وقتها السلفة الأم ما عادت موجودة)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_paid_installment_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.is_paid AND EXISTS (SELECT 1 FROM loans WHERE id = OLD.loan_id) THEN
    RAISE EXCEPTION 'القسط المسدد ما ينحذف: حذفه يرجّع مبلغه ديناً على الموظف. إذا انسجل بالغلط استعمل «التراجع عن السداد».'
      USING ERRCODE = '55000';
  END IF;
  RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS trg_guard_paid_installment_delete ON public.loan_installments;
CREATE TRIGGER trg_guard_paid_installment_delete BEFORE DELETE ON public.loan_installments
  FOR EACH ROW EXECUTE FUNCTION public.guard_paid_installment_delete();

-- ---------------------------------------------------------------------
-- 2) قسط انخصم من راتب معتمد: ما يتراجع ولا يتغير مبلغه إلا بإلغاء اعتماد الكشف (اللي يفك الربط بنفس الوقت)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_slip_paid_installment()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF OLD.paid_by_slip_id IS NOT NULL AND NEW.paid_by_slip_id IS NOT DISTINCT FROM OLD.paid_by_slip_id
     AND (NOT NEW.is_paid OR NEW.amount IS DISTINCT FROM OLD.amount) THEN
    RAISE EXCEPTION 'هذا القسط انخصم من راتب معتمد. حتى يرجع، ألغِ اعتماد ذاك الراتب من صفحة الرواتب.'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_guard_slip_paid_installment ON public.loan_installments;
CREATE TRIGGER trg_guard_slip_paid_installment BEFORE UPDATE OF is_paid, amount ON public.loan_installments
  FOR EACH ROW EXECUTE FUNCTION public.guard_slip_paid_installment();

-- ---------------------------------------------------------------------
-- 3) الخصومات والمكافآت اليدوية: منو سجّلها دائماً، ونفس القيد ما يتكرر خلال 10 دقائق
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_bonus_deduction_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.created_by := COALESCE(NEW.created_by, auth.uid());
  IF EXISTS (
    SELECT 1 FROM bonuses_deductions b
    WHERE b.employee_id = NEW.employee_id AND b.issue_date = NEW.issue_date AND b.type = NEW.type
      AND b.amount = NEW.amount AND b.reason IS NOT DISTINCT FROM NEW.reason
      AND b.created_at > now() - interval '10 minutes'
  ) THEN
    RAISE EXCEPTION '% بنفس المبلغ والسبب انسجل لهذا الموظف قبل دقائق، فما انضاف مرة ثانية.',
      CASE WHEN NEW.type = 'bonus' THEN 'مكافأة' ELSE 'خصم' END USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_guard_bonus_deduction_entry ON public.bonuses_deductions;
CREATE TRIGGER trg_guard_bonus_deduction_entry BEFORE INSERT ON public.bonuses_deductions
  FOR EACH ROW EXECUTE FUNCTION public.guard_bonus_deduction_entry();

-- تنظيف (محمي): نسخ مكررة بدون منشئ (نفس الموظف/اليوم/النوع/المبلغ/السبب خلال ساعة) ← تبقى الأقدم،
-- و«تأخير مفقود» من النسخة القديمة لنفس يوم فيه تأخير محسوب بالمحرّك (كان ينخصم مرتين).
DELETE FROM public.bonuses_deductions b
USING public.bonuses_deductions o
WHERE b.created_by IS NULL AND b.salary_slip_id IS NULL AND NOT b.superseded_by_attendance
  AND o.id <> b.id AND o.employee_id = b.employee_id AND o.issue_date = b.issue_date AND o.type = b.type
  AND o.amount = b.amount AND o.reason IS NOT DISTINCT FROM b.reason AND o.salary_slip_id IS NULL
  AND NOT o.superseded_by_attendance
  AND (o.created_at < b.created_at OR (o.created_at = b.created_at AND o.id < b.id))
  AND b.created_at - o.created_at < interval '1 hour';

DELETE FROM public.bonuses_deductions b
WHERE b.created_by IS NULL AND b.salary_slip_id IS NULL AND NOT b.superseded_by_attendance
  AND b.type = 'deduction' AND b.reason LIKE 'تأخير مفقود%'
  AND EXISTS (SELECT 1 FROM public.payroll_events pe
              WHERE pe.employee_id = b.employee_id AND pe.event_date = b.issue_date
                AND pe.event_type = 'late' AND pe.status <> 'void');

-- ---------------------------------------------------------------------
-- 4) سجل الرواتب بشهر سريان
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.salary_history (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id     uuid NOT NULL REFERENCES public.employees(id) ON DELETE CASCADE,
  monthly_salary  numeric NOT NULL CHECK (monthly_salary >= 0),
  effective_month text NOT NULL CHECK (effective_month ~ '^\d{4}-\d{2}$'),
  source          text NOT NULL DEFAULT 'change' CHECK (source IN ('initial', 'change', 'scheduled')),
  created_by      uuid DEFAULT auth.uid() REFERENCES public.employees(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (employee_id, effective_month)
);
COMMENT ON TABLE public.salary_history IS 'راتب كل موظف من أي شهر رواتب يبدأ (الحساب يقرأ منه؛ monthly_salary_iqd = الراتب الحالي للعرض)';

ALTER TABLE public.salary_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS salary_history_admin ON public.salary_history;
CREATE POLICY salary_history_admin ON public.salary_history FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS salary_history_own ON public.salary_history;
CREATE POLICY salary_history_own ON public.salary_history FOR SELECT TO authenticated
  USING (employee_id = auth.uid());
REVOKE ALL ON public.salary_history FROM anon;

-- شهر رواتب من نص تاريخ بأي صيغة قديمة: 2026-06 / 2026-06-15 / 2026/06/01 (اليوم بعد القطع = الشهر الجاي)
CREATE OR REPLACE FUNCTION public._salary_effective_month(p_value text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v text := replace(btrim(COALESCE(p_value, '')), '/', '-');
BEGIN
  IF v ~ '^\d{4}-\d{1,2}-\d{1,2}' THEN
    RETURN public.payroll_month_of(to_date(substr(v, 1, 10), 'YYYY-MM-DD'));
  ELSIF v ~ '^\d{4}-\d{1,2}$' THEN
    RETURN to_char(to_date(v || '-01', 'YYYY-MM-DD'), 'YYYY-MM');
  END IF;
  RETURN NULL;
END;
$function$;

-- بذرة: الراتب الحالي من البداية + الزيادات المجدولة بشهرها
INSERT INTO public.salary_history (employee_id, monthly_salary, effective_month, source, created_by)
SELECT id, COALESCE(monthly_salary_iqd, 0), '2000-01', 'initial', NULL FROM public.employees
ON CONFLICT (employee_id, effective_month) DO NOTHING;

INSERT INTO public.salary_history (employee_id, monthly_salary, effective_month, source, created_by)
SELECT id, future_salary_iqd, public._salary_effective_month(future_salary_month), 'scheduled', NULL
FROM public.employees
WHERE future_salary_iqd IS NOT NULL AND public._salary_effective_month(future_salary_month) IS NOT NULL
ON CONFLICT (employee_id, effective_month) DO UPDATE SET monthly_salary = EXCLUDED.monthly_salary, source = 'scheduled';

-- الراتب الأساسي لشهر رواتب = آخر راتب سريانه قبل/بنفس الشهر
CREATE OR REPLACE FUNCTION public.payroll_basic_salary(p_employee_id uuid, p_month text)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT h.monthly_salary FROM salary_history h
     WHERE h.employee_id = p_employee_id AND h.effective_month <= p_month
     ORDER BY h.effective_month DESC, h.created_at DESC LIMIT 1),
    (SELECT COALESCE(e.monthly_salary_iqd, 0) FROM employees e WHERE e.id = p_employee_id),
    0);
$function$;

-- تسجيل أي تغيير بالراتب أو الزيادة المجدولة بالسجل، وإعادة حساب المسيرات المفتوحة (بدون كشف) لهذا الموظف
CREATE OR REPLACE FUNCTION public.record_salary_history()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_month text;
  v_old text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO salary_history (employee_id, monthly_salary, effective_month, source)
    VALUES (NEW.id, COALESCE(NEW.monthly_salary_iqd, 0), '2000-01', 'initial')
    ON CONFLICT (employee_id, effective_month) DO NOTHING;
  ELSE
    IF NEW.monthly_salary_iqd IS DISTINCT FROM OLD.monthly_salary_iqd THEN
      -- تغيير مباشر: من شهر الرواتب الحالي (الأشهر المفتوحة الأقدم تبقى بالراتب القديم)
      v_month := public.payroll_month_of((now() AT TIME ZONE public.company_timezone())::date);
      INSERT INTO salary_history (employee_id, monthly_salary, effective_month, source)
      VALUES (NEW.id, COALESCE(NEW.monthly_salary_iqd, 0), v_month, 'change')
      ON CONFLICT (employee_id, effective_month) DO UPDATE SET monthly_salary = EXCLUDED.monthly_salary, source = 'change',
        created_by = auth.uid(), created_at = now();
    END IF;
    IF NEW.future_salary_iqd IS DISTINCT FROM OLD.future_salary_iqd
       OR NEW.future_salary_month IS DISTINCT FROM OLD.future_salary_month THEN
      -- إلغاء/تغيير زيادة بعدها ما بدت ينمسح سطرها؛ الزيادة اللي بدت تبقى بالسجل (تاريخ)
      v_old := public._salary_effective_month(OLD.future_salary_month);
      IF v_old IS NOT NULL AND v_old > public.payroll_month_of((now() AT TIME ZONE public.company_timezone())::date) THEN
        DELETE FROM salary_history WHERE employee_id = NEW.id AND effective_month = v_old AND source = 'scheduled';
      END IF;
      v_month := public._salary_effective_month(NEW.future_salary_month);
      IF NEW.future_salary_iqd IS NOT NULL AND v_month IS NOT NULL THEN
        INSERT INTO salary_history (employee_id, monthly_salary, effective_month, source)
        VALUES (NEW.id, NEW.future_salary_iqd, v_month, 'scheduled')
        ON CONFLICT (employee_id, effective_month) DO UPDATE SET monthly_salary = EXCLUDED.monthly_salary, source = 'scheduled',
          created_by = auth.uid(), created_at = now();
      END IF;
    END IF;
  END IF;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_record_salary_history ON public.employees;
CREATE TRIGGER trg_record_salary_history
  AFTER INSERT OR UPDATE OF monthly_salary_iqd, future_salary_iqd, future_salary_month ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.record_salary_history();

-- إعادة الحساب بعد تغيير الراتب أو الزيادة المجدولة (كان بس للراتب المباشر)
CREATE OR REPLACE FUNCTION public.resync_payroll_on_salary_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
BEGIN
  IF NEW.monthly_salary_iqd IS NOT DISTINCT FROM OLD.monthly_salary_iqd
     AND NEW.future_salary_iqd IS NOT DISTINCT FROM OLD.future_salary_iqd
     AND NEW.future_salary_month IS NOT DISTINCT FROM OLD.future_salary_month THEN
    RETURN NEW;
  END IF;
  FOR r IN
    SELECT pp.period_month FROM payroll_periods pp
    WHERE pp.status = 'open'
      AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = NEW.id AND s.work_month = pp.period_month)
  LOOP
    PERFORM public.sync_payroll_period(r.period_month, NEW.id);
  END LOOP;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_resync_payroll_on_salary_change ON public.employees;
CREATE TRIGGER trg_resync_payroll_on_salary_change
  AFTER UPDATE OF monthly_salary_iqd, future_salary_iqd, future_salary_month ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.resync_payroll_on_salary_change();

-- الزيادة اللي حل شهرها تصير هي الراتب الحالي (للعرض)، والحقول المجدولة تنمسح. يرجع عدد الموظفين.
CREATE OR REPLACE FUNCTION public.apply_due_salary_changes()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_now text := public.payroll_month_of((now() AT TIME ZONE public.company_timezone())::date);
  r record;
  v_n int := 0;
BEGIN
  PERFORM public.require_admin_or_system();
  FOR r IN
    SELECT id, future_salary_iqd FROM employees
    WHERE future_salary_iqd IS NOT NULL
      AND public._salary_effective_month(future_salary_month) IS NOT NULL
      AND public._salary_effective_month(future_salary_month) <= v_now
  LOOP
    UPDATE employees SET monthly_salary_iqd = r.future_salary_iqd, future_salary_iqd = NULL, future_salary_month = NULL
    WHERE id = r.id;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.apply_due_salary_changes() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._salary_effective_month(text) FROM PUBLIC, anon;

-- الزيادات المعلّقة اللي فات شهرها تنطبق هسه (مثل 800,000 من حزيران)
SELECT public.apply_due_salary_changes();

-- ---------------------------------------------------------------------
-- 8) قسط سلفة أكبر من الراتب المتبقي: ينقص بقد الصافي والباقي شهر جديد بالأخير (أو تأجيل إذا ما يكفي شي)
-- ---------------------------------------------------------------------
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

REVOKE EXECUTE ON FUNCTION public._cap_loans_to_net(uuid, text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- اعتماد الكشف (آخر تعريف: 20260929000400_audit_fixes.sql) + 6) بعد نهاية الفترة بس (إلا من ترك) + 8) تقليص القسط
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

  INSERT INTO salary_slips (employee_id, work_month, basic_salary, allowances, deductions, loans_deduction, net_salary, status, computed_by_engine)
  VALUES (p_employee_id, p_month, (v_sum ->> 'basic')::numeric, (v_sum ->> 'earnings')::numeric,
          (v_sum ->> 'deductions')::numeric, (v_sum ->> 'loans')::numeric, (v_sum ->> 'net')::numeric, 'published', true)
  RETURNING id INTO v_slip;

  INSERT INTO salary_slip_lines (salary_slip_id, event_id, line_type, event_date, minutes, days, amount, direction, notes, carried_from)
  SELECT v_slip, pe.id, pe.event_type, pe.event_date, pe.minutes, pe.days, pe.amount, pe.direction, pe.notes, pe.carried_from
  FROM payroll_events pe
  WHERE pe.employee_id = p_employee_id AND pe.payroll_month = p_month AND pe.status = 'approved'
    AND (pe.amount > 0 OR pe.event_type = 'paid_leave');

  INSERT INTO salary_slip_lines (salary_slip_id, line_type, event_date, amount, direction, notes)
  SELECT v_slip, 'loan', li.due_date, li.amount, -1, 'قسط سلفة'
  FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  UPDATE payroll_events SET salary_slip_id = v_slip, updated_at = now()
  WHERE employee_id = p_employee_id AND payroll_month = p_month AND status = 'approved';

  UPDATE loan_installments li
  SET is_paid = true, paid_at = now(), paid_by_slip_id = v_slip
  FROM loans l
  WHERE li.loan_id = l.id AND l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  RETURN v_slip;
END;
$function$;

-- الرسالة القديمة للصافي السالب كانت تذكر التأجيل اليدوي؛ هسه القسط ينقص وحده، فالسالب يعني خصومات أكبر من الراتب
CREATE OR REPLACE FUNCTION public.reject_negative_salary_slip()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.net_salary < 0 THEN
    RAISE EXCEPTION 'صافي الراتب بالسالب (%): الخصومات أكبر من الراتب. راجع خصوماته قبل الاعتماد.',
      to_char(NEW.net_salary, 'FM999,999,999')
      USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$function$;
