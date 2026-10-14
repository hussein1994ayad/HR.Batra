-- =====================================================================
-- المرحلة 1 (تكملة): سد «الخطر المتبقي» — مدير الفرع ما يكدر يستنتج الراتب من المبالغ.
-- كان يشوف مبلغ كل حركة خصم وأجر اليوم والدقيقة (أجر اليوم × 30 = الراتب) ومكافآت وخصومات فرعه اليدوية.
-- هسه: أعمدة المبالغ بحركات الرواتب ما تنقرا مباشرة لأي مستخدم (مثل الراتب بجدول الموظفين)، والأدمن يقراها من
-- get_payroll_event_amounts؛ أجر اليوم (payroll_day_rates) للأدمن بس؛ get_payroll_events و get_pending_payroll_decisions
-- ورد decide_payroll_event بدون مبالغ لغير الأدمن؛ المدير يقرر خصم بالمحسوب أو إعفاء (ما يكتب مبلغ).
-- الموظف يبقى يشوف مبالغ خصوماته المقررة من «راتبي» والكشوف.
-- =====================================================================

-- ---------------------------------------------------------------------
-- أعمدة المبالغ بحركات الرواتب ما تنقرا مباشرة.
-- ملاحظة للمطور: أي عمود جديد بحركات الرواتب لازم ينضاف لهذي القائمة حتى ينقرا (يفحصها test_column_grants.mjs).
-- ---------------------------------------------------------------------
REVOKE SELECT ON public.payroll_events FROM anon, authenticated;
GRANT SELECT (id, employee_id, event_date, event_type, minutes, days, direction, payroll_month, carried_from, status, source,
              source_id, adjusts_event_id, notes, decision_reason, decided_by, decided_at, salary_slip_id, created_by,
              created_at, updated_at)
  ON public.payroll_events TO authenticated;

-- مبالغ الحركات لفترة: للأدمن بس (غيره يرجعله فارغ)
CREATE OR REPLACE FUNCTION public.get_payroll_event_amounts(p_from date, p_to date)
 RETURNS TABLE(event_id uuid, employee_id uuid, event_date date, event_type text, amount numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT pe.id, pe.employee_id, pe.event_date, pe.event_type, pe.amount
  FROM payroll_events pe
  WHERE public.is_admin() AND pe.status <> 'void' AND pe.event_date BETWEEN p_from AND p_to;
$function$;
REVOKE ALL ON FUNCTION public.get_payroll_event_amounts(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_payroll_event_amounts(date, date) TO authenticated;

-- أجر اليوم للأدمن بس (المدير يرجعله فارغ، بدون خطأ)
CREATE OR REPLACE FUNCTION public.payroll_day_rates(p_date date DEFAULT NULL::date)
 RETURNS TABLE(employee_id uuid, daily_rate numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_date date := COALESCE(p_date, (now() AT TIME ZONE public.company_timezone())::date);
  v_month text := COALESCE(public.payroll_natural_month(v_date), public.payroll_month_of(v_date));
BEGIN
  PERFORM public.require_admin_or_manager();
  IF NOT public.is_admin() THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT e.id, round(public.payroll_daily_rate(e.id, v_month), 2)
  FROM employees e
  WHERE e.is_active;
END;
$function$;

-- حركات مسير: الأدمن كلها، الموظف حركاته المقررة (بمبالغها)، مدير الفرع حركات فرعه بدون مبالغ
CREATE OR REPLACE FUNCTION public.get_payroll_events(p_month text, p_employee_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF payroll_events
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r payroll_events%ROWTYPE;
  v_admin boolean := public.is_admin();
BEGIN
  FOR r IN
    SELECT pe.* FROM payroll_events pe
    WHERE (v_admin
           OR (pe.employee_id = auth.uid() AND pe.status = 'approved')
           OR (pe.employee_id <> auth.uid() AND public.is_manager() AND public.payroll_same_branch(pe.employee_id)))
      AND pe.payroll_month = p_month
      AND (p_employee_id IS NULL OR pe.employee_id = p_employee_id)
      AND pe.status <> 'void'
    ORDER BY pe.event_date, pe.event_type
  LOOP
    IF NOT v_admin AND r.employee_id <> auth.uid() THEN
      r.amount := NULL; r.amount_override := NULL; r.daily_rate := NULL; r.minute_rate := NULL;
    END IF;
    RETURN NEXT r;
  END LOOP;
END;
$function$;

-- القرارات المعلّقة: المبلغ للأدمن بس
CREATE OR REPLACE FUNCTION public.get_pending_payroll_decisions()
 RETURNS TABLE(id uuid, employee_id uuid, full_name text, branch_id uuid, branch_name text, event_date date, event_type text, minutes numeric, days numeric, amount numeric, direction smallint, payroll_month text, carried_from text, status text, source text, source_id uuid, notes text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_admin boolean := public.is_admin();
BEGIN
  PERFORM public.require_admin_or_manager();
  RETURN QUERY
  SELECT pe.id, pe.employee_id, e.full_name, e.branch_id, b.name, pe.event_date, pe.event_type, pe.minutes, pe.days,
         CASE WHEN v_admin THEN pe.amount END, pe.direction, pe.payroll_month, pe.carried_from, pe.status, pe.source,
         pe.source_id, pe.notes
  FROM payroll_events pe
  JOIN employees e ON e.id = pe.employee_id
  LEFT JOIN branches b ON b.id = e.branch_id
  JOIN payroll_periods p ON p.period_month = pe.payroll_month AND p.status = 'open'
  WHERE pe.status = 'pending'
    AND (v_admin OR (pe.employee_id <> auth.uid() AND public.payroll_same_branch(pe.employee_id)))
    AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch', 'overtime')
  ORDER BY pe.event_date DESC, e.full_name;
END;
$function$;

-- المكافآت والخصومات اليدوية: الأدمن وصاحبها بس (كان مدير الفرع يقراها)
DROP POLICY IF EXISTS "Managers read branch bonuses/deductions" ON public.bonuses_deductions;

-- القرار: المدير ما يكتب مبلغ، والرد إله بدون مبالغ
CREATE OR REPLACE FUNCTION public.decide_payroll_event(p_event_id uuid, p_approve boolean, p_reason text DEFAULT NULL::text, p_amount numeric DEFAULT NULL::numeric)
 RETURNS payroll_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  e payroll_events%ROWTYPE;
  v_att_id uuid;
  v_branch uuid;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'ignored' END;
  v_labels jsonb := '{"absence":"غياب","late":"تأخير","early_leave":"خروج مبكر","missing_punch":"بدون بصمة انصراف","overtime":"ساعات إضافية"}';
  -- المبلغ اللي كتبه الأدمن (بس عند الخصم/الاعتماد). NULL = المبلغ المحسوب
  v_amount numeric := CASE WHEN p_approve AND p_amount IS NOT NULL THEN round(p_amount, 2) END;
  v_salary numeric;
  v_final numeric;
  v_had_override boolean;
  v_computed numeric;
  v_daily numeric;
  v_cap numeric;
BEGIN
  PERFORM public.require_admin_or_manager();
  SELECT * INTO e FROM payroll_events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND OR e.status = 'void' THEN
    RAISE EXCEPTION 'الحركة غير موجودة.' USING ERRCODE = 'P0002';
  END IF;
  IF NOT public.is_admin() THEN
    IF e.employee_id = auth.uid() THEN
      RAISE EXCEPTION 'لا يمكنك اتخاذ قرار على حركاتك الخاصة.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.payroll_same_branch(e.employee_id) THEN
      RAISE EXCEPTION 'غير مصرح: الموظف من فرع آخر.' USING ERRCODE = '42501';
    END IF;
  END IF;
  IF e.event_type NOT IN ('absence', 'late', 'early_leave', 'missing_punch', 'overtime') THEN
    RAISE EXCEPTION 'هذه الحركة لا تحتاج قراراً.' USING ERRCODE = '22023';
  END IF;
  IF v_amount IS NOT NULL THEN
    IF v_amount < 0 THEN
      RAISE EXCEPTION 'المبلغ لازم يكون صفر أو أكثر.' USING ERRCODE = '22023';
    END IF;
    -- حماية من غلطة كتابة (صفر زايد): مبلغ حركة وحدة ما يتجاوز الراتب الشهري
    v_salary := public.payroll_basic_salary(e.employee_id, e.payroll_month);
    IF v_salary > 0 AND v_amount > v_salary THEN
      RAISE EXCEPTION 'المبلغ (%) أكبر من راتب الموظف الشهري (%).', to_char(v_amount, 'FM999,999,999'), to_char(v_salary, 'FM999,999,999')
        USING ERRCODE = '22023';
    END IF;
    -- مدير الفرع ما يشوف المبالغ (منها ينعرف الراتب)، فما يكتب مبلغ: يقرر خصم بالمحسوب أو إعفاء
    IF NOT public.is_admin() THEN
      RAISE EXCEPTION 'مبلغ الخصم يحدده مسؤول النظام (الأدمن). مدير الفرع يقرر خصم بالمبلغ المحسوب أو إعفاء.'
        USING ERRCODE = '42501';
    END IF;
    -- الحد حسب النوع: الخصم ≤ أجر يوم (العقوبة الأكبر = «خصم يدوي» بسبب)، الإضافي ≤ المحسوب (الأكثر = «مكافأة»)
    v_computed := public._payroll_event_computed_amount(e);
    v_daily := round(COALESCE(e.daily_rate, public.payroll_daily_rate(e.employee_id, e.payroll_month)) * GREATEST(e.days, 1), 2);
    v_cap := CASE WHEN e.event_type = 'overtime' THEN v_computed ELSE v_daily END;
    IF v_amount > v_cap THEN
      IF e.event_type = 'overtime' THEN
        RAISE EXCEPTION 'مبلغ الإضافي ما يتجاوز المحسوب (% د.ع). للمبلغ الأكبر سجّل «مكافأة» بسبب واضح.',
          to_char(v_cap, 'FM999,999,990') USING ERRCODE = '22023';
      END IF;
      RAISE EXCEPTION 'خصم % ما يتجاوز أجر يوم واحد (% د.ع). للعقوبة الأكبر سجّل «خصم يدوي» بسبب واضح.',
        COALESCE(v_labels ->> e.event_type, ''), to_char(v_cap, 'FM999,999,990') USING ERRCODE = '22023';
    END IF;
  END IF;

  -- الغياب والتأخير قرارهما محفوظ في سجل الحضور أيضاً (للتوافق مع الشاشات)
  IF e.event_type IN ('absence', 'late') THEN
    IF e.source = 'no_record' THEN
      -- موظف بدون فرع: نسجل اليوم بفرع اللي قرر (أو أول فرع) بدل ما يعلق القرار
      SELECT COALESCE(
        (SELECT branch_id FROM employees WHERE id = e.employee_id),
        (SELECT branch_id FROM employees WHERE id = auth.uid()),
        (SELECT id FROM branches ORDER BY created_at LIMIT 1)) INTO v_branch;
      IF v_branch IS NULL THEN
        RAISE EXCEPTION 'ماكو أي فرع بالنظام. أضف فرعاً أولاً.' USING ERRCODE = '22023';
      END IF;
      INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status, deduction_reason)
      VALUES (e.employee_id, v_branch, e.event_date, 'absent', CASE WHEN p_approve THEN 'applied' ELSE 'ignored' END, p_reason)
      RETURNING id INTO v_att_id;
    ELSE
      UPDATE attendance
      SET deduction_status = CASE WHEN p_approve THEN 'applied' ELSE 'ignored' END,
          deduction_applied = p_approve,
          deduction_reason = COALESCE(NULLIF(btrim(p_reason), ''), deduction_reason)
      WHERE id = e.source_id;
    END IF;
    SELECT * INTO e FROM payroll_events
    WHERE employee_id = e.employee_id AND event_date = e.event_date AND event_type = e.event_type
      AND status <> 'void' ORDER BY updated_at DESC LIMIT 1;
  END IF;

  v_had_override := e.amount_override IS NOT NULL;
  IF e.salary_slip_id IS NULL THEN
    UPDATE payroll_events
    SET status = v_status, decision_reason = NULLIF(btrim(p_reason), ''), decided_by = auth.uid(), decided_at = now(),
        amount_override = v_amount,
        amount = COALESCE(v_amount,
                          -- رجوع للمحسوب بعد مبلغ معدّل على بصمة ناقصة (الباقي يرجّعه إعادة الحساب تحت)
                          CASE WHEN e.amount_override IS NOT NULL AND e.event_type = 'missing_punch'
                               THEN round(e.minutes * COALESCE(e.minute_rate, 0), 2) ELSE amount END),
        -- بصمة ناقصة كانت «تأكيد بدون مبلغ» وانكتب إلها مبلغ = خصم
        direction = CASE WHEN v_amount > 0 AND direction = 0 THEN -1 ELSE direction END,
        payroll_month = CASE
          WHEN EXISTS (SELECT 1 FROM payroll_periods WHERE period_month = e.payroll_month AND status = 'open')
               AND NOT EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = e.employee_id AND work_month = e.payroll_month)
            THEN e.payroll_month
          ELSE public.payroll_target_month(e.employee_id, e.payroll_month) END,
        updated_at = now()
    WHERE id = e.id
    RETURNING * INTO e;
    -- انمسح مبلغ معدّل سابق: نرجع للمبلغ المحسوب من الدوام
    IF v_had_override AND v_amount IS NULL AND p_approve AND e.event_type <> 'missing_punch' THEN
      PERFORM public.sync_payroll_day(e.employee_id, e.event_date);
      SELECT * INTO e FROM payroll_events WHERE id = e.id;
    END IF;
    v_final := e.amount;
  ELSE
    -- داخل كشف معتمد: الحركة ما تتغير، والفرق يصير تسوية بأول مسير مفتوح
    UPDATE payroll_events SET decision_reason = NULLIF(btrim(p_reason), ''), decided_by = auth.uid(), decided_at = now(),
                              amount_override = v_amount
    WHERE id = e.id;
    v_final := COALESCE(v_amount, e.amount);
    PERFORM public._payroll_settle(e, CASE WHEN p_approve THEN e.direction * v_final ELSE 0 END);
  END IF;

  -- إشعار للموظف بالخصم أو باعتماد الإضافي فقط. الإعفاء (مثل: نسي البصمة وهو مداوم) بدون إشعار:
  -- الموظف ما تبلّغ بالتأخير أصلاً، والملاحظة تبقى محفوظة بالقرار (decision_reason)
  IF p_approve AND (e.event_type <> 'missing_punch' OR v_final > 0) THEN
    INSERT INTO notifications (employee_id, title, body, type)
    VALUES (e.employee_id,
            CASE WHEN p_approve AND e.direction < 0 THEN 'إشعار بخصم ⚠️'
                 WHEN p_approve THEN 'اعتماد ساعات إضافية ✅'
                 ELSE 'إعفاء من الخصم 🎉' END,
            format('%s ليوم %s%s%s',
                   CASE WHEN p_approve AND e.direction < 0 THEN 'تم تطبيق خصم ' || COALESCE(v_labels ->> e.event_type, '')
                        WHEN p_approve THEN 'تم اعتماد ساعات إضافية'
                        ELSE 'تم إعفاؤك من خصم ' || COALESCE(v_labels ->> e.event_type, '') END,
                   e.event_date,
                   CASE WHEN p_approve AND v_final > 0 THEN format(' بمبلغ %s د.ع', to_char(v_final, 'FM999,999,999')) ELSE '' END,
                   CASE WHEN NULLIF(btrim(p_reason), '') IS NOT NULL THEN '. السبب: ' || btrim(p_reason) ELSE '' END),
            'attendance');
  END IF;
  -- الرد لمدير الفرع بدون مبالغ (منها ينعرف الراتب)
  IF NOT public.is_admin() THEN
    e.amount := NULL; e.amount_override := NULL; e.daily_rate := NULL; e.minute_rate := NULL;
  END IF;
  RETURN e;
END;
$function$;
