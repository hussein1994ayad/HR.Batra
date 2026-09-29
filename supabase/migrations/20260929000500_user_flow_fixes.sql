-- =====================================================================
-- تصليحات فحص المستخدم الحقيقي (الموقع + التطبيق)
--
--  1) تعديل السلفة من الموقع كان يضاعف الأقساط (الحذف يولّد أقساطاً تلقائياً ثم
--     يُضاف الجدول الجديد فوقها): reschedule_loan يكتب الجدول ذرّياً.
--  2) المدير كان يتجاوز قيود القرار عبر تعديل سجل الحضور مباشرة (يعفي نفسه،
--     ويقرّر لفرع آخر): تريجر على attendance.
--  3) الإجازات: إلغاء الطلب المعلّق يعمل (كانت 'cancelled' مرفوضة بالقيد)، لا أحد
--     يعتمد إجازته، المدير لفرعه فقط، ولا طلب لأكثر من 30 يوماً للخلف.
--  4) طلب سلفة معلّق واحد لكل موظف.
--  5) get_my_payroll_preview: الموظف يرى حركات مسيره الحالي قبل الاعتماد.
--  6) get_payroll_run: من له كشف معتمد يظهر دائماً في مسير شهره.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.update_loan_and_installments_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_loan_id UUID;
    v_loan_amount NUMERIC;
    v_default_installment_amount NUMERIC;
    v_total_paid NUMERIC;
    v_new_remaining NUMERIC;
    v_unpaid_count INT;
    v_unpaid_record RECORD;
    v_allocated_so_far NUMERIC;
    v_alloc NUMERIC;
    v_last_due_date DATE;
    v_counter INT;
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
        SELECT amount, installment_amount INTO v_loan_amount, v_default_installment_amount
        FROM public.loans
        WHERE id = v_loan_id
        FOR UPDATE;

        IF FOUND THEN
            SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
            FROM public.loan_installments
            WHERE loan_id = v_loan_id AND is_paid = true;

            v_new_remaining := v_loan_amount - v_total_paid;
            IF v_new_remaining < 0 THEN
                v_new_remaining := 0;
            END IF;

            UPDATE public.loans
            SET remaining_amount = v_new_remaining
            WHERE id = v_loan_id;

            IF v_new_remaining <= 0 THEN
                DELETE FROM public.loan_installments
                WHERE loan_id = v_loan_id AND is_paid = false;
            ELSE
                SELECT COUNT(*) INTO v_unpaid_count
                FROM public.loan_installments
                WHERE loan_id = v_loan_id AND is_paid = false;

                v_allocated_so_far := 0;
                v_counter := 0;

                FOR v_unpaid_record IN
                    SELECT id, amount
                    FROM public.loan_installments
                    WHERE loan_id = v_loan_id AND is_paid = false
                    ORDER BY due_date ASC, id ASC
                LOOP
                    v_counter := v_counter + 1;

                    IF v_allocated_so_far < v_new_remaining THEN
                        IF v_counter = v_unpaid_count THEN
                            v_alloc := v_new_remaining - v_allocated_so_far;
                        ELSE
                            v_alloc := LEAST(v_default_installment_amount, v_new_remaining - v_allocated_so_far);
                        END IF;

                        UPDATE public.loan_installments
                        SET amount = v_alloc
                        WHERE id = v_unpaid_record.id;

                        v_allocated_so_far := v_allocated_so_far + v_alloc;
                    ELSE
                        DELETE FROM public.loan_installments
                        WHERE id = v_unpaid_record.id;
                    END IF;
                END LOOP;

                IF v_allocated_so_far < v_new_remaining THEN
                    SELECT COALESCE(MAX(due_date), CURRENT_DATE) INTO v_last_due_date
                    FROM public.loan_installments
                    WHERE loan_id = v_loan_id;

                    WHILE v_allocated_so_far < v_new_remaining LOOP
                        v_last_due_date := v_last_due_date + INTERVAL '1 month';
                        v_alloc := LEAST(v_default_installment_amount, v_new_remaining - v_allocated_so_far);

                        INSERT INTO public.loan_installments (loan_id, due_date, amount, is_paid)
                        VALUES (v_loan_id, v_last_due_date, v_alloc, false);

                        v_allocated_so_far := v_allocated_so_far + v_alloc;
                    END LOOP;
                END IF;
            END IF;
        END IF;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- 1) تعديل السلفة ذرّياً على السيرفر (الموقع كان يضاعف الأقساط)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reschedule_loan(
  p_loan_id uuid,
  p_amount numeric,
  p_installment_amount numeric,
  p_count integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_loan loans%ROWTYPE;
  v_paid numeric;
  v_paid_count integer;
  v_remaining numeric;
  v_left integer;
  v_base numeric;
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
  IF COALESCE(p_amount, 0) <= 0 OR COALESCE(p_installment_amount, 0) <= 0 OR COALESCE(p_count, 0) <= 0 THEN
    RAISE EXCEPTION 'اكتب مبلغاً وقسطاً وعدد أقساط أكبر من الصفر.' USING ERRCODE = '22023';
  END IF;
  IF p_installment_amount > p_amount THEN
    RAISE EXCEPTION 'القسط أكبر من مبلغ السلفة.' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(sum(amount), 0), count(*) INTO v_paid, v_paid_count
  FROM loan_installments WHERE loan_id = p_loan_id AND is_paid;
  v_remaining := round(p_amount - v_paid);
  IF v_remaining < 0 THEN
    RAISE EXCEPTION 'المبلغ الجديد أقل من المسدَّد (%).', to_char(v_paid, 'FM999,999,999') USING ERRCODE = '22023';
  END IF;
  v_left := p_count - v_paid_count;
  IF v_remaining > 0 AND v_left <= 0 THEN
    RAISE EXCEPTION 'عدد الأقساط يجب أن يكون أكبر من الأقساط المسددة (%).', v_paid_count USING ERRCODE = '22023';
  END IF;

  -- الجدول يُكتب هنا كاملاً: التريجر لا يولّد أقساطاً أثناء الحذف والإضافة
  PERFORM set_config('loans.skip_rebalance', 'on', true);

  UPDATE loans
  SET amount = round(p_amount), installment_amount = round(p_installment_amount),
      installment_count = p_count, remaining_amount = v_remaining
  WHERE id = p_loan_id;

  DELETE FROM loan_installments WHERE loan_id = p_loan_id AND NOT is_paid;

  IF v_remaining > 0 THEN
    v_first := (date_trunc('month', (now() AT TIME ZONE public.company_timezone())) + interval '1 month')::date;
    v_base := floor(v_remaining / v_left);
    FOR i IN 0 .. v_left - 1 LOOP
      INSERT INTO loan_installments (loan_id, due_date, amount, is_paid)
      VALUES (p_loan_id, (v_first + make_interval(months => i))::date,
              CASE WHEN i = v_left - 1 THEN v_remaining - v_base * (v_left - 1) ELSE v_base END, false);
    END LOOP;
  END IF;

  PERFORM set_config('loans.skip_rebalance', 'off', true);

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (v_loan.employee_id, 'تعديل تفاصيل السلفة 💸',
          format('قامت الإدارة بتعديل سلفتك: المبلغ الكلي %s د.ع، القسط الشهري %s د.ع، المتبقي %s د.ع على %s قسط.',
                 to_char(round(p_amount), 'FM999,999,999'), to_char(round(p_installment_amount), 'FM999,999,999'),
                 to_char(v_remaining, 'FM999,999,999'), GREATEST(v_left, 0)),
          'loan');
  RETURN GREATEST(v_left, 0);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.reschedule_loan(uuid, numeric, numeric, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reschedule_loan(uuid, numeric, numeric, integer) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- 2) قرارات الحضور: لا أحد يقرّر على نفسه، والمدير لفرعه فقط
--    (صفحة الحضور بالموقع تعدّل سجل الحضور مباشرة فكانت تتجاوز decide_payroll_event)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_attendance_decisions()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- دوال السيرفر (البصمة، decide_payroll_event) تعمل بصلاحية المالك ولها فحوصاتها
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  -- الموظف العادي: صلاحيات الجدول (RLS) تمنعه أصلاً من الكتابة
  IF NOT public.is_manager() THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.deduction_status IS NOT DISTINCT FROM OLD.deduction_status
     AND NEW.deduction_reason IS NOT DISTINCT FROM OLD.deduction_reason
     AND NEW.deduction_applied IS NOT DISTINCT FROM OLD.deduction_applied
     AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;
  IF NEW.employee_id = auth.uid() THEN
    RAISE EXCEPTION 'لا يمكنك اتخاذ قرار على حضورك.' USING ERRCODE = '42501';
  END IF;
  IF NOT public.payroll_same_branch(NEW.employee_id) THEN
    RAISE EXCEPTION 'غير مصرح: الموظف من فرع آخر.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_attendance_decisions ON public.attendance;
CREATE TRIGGER trg_protect_attendance_decisions
BEFORE INSERT OR UPDATE ON public.attendance
FOR EACH ROW EXECUTE FUNCTION public.protect_attendance_decisions();

-- ---------------------------------------------------------------------
-- 3) الإجازات: إلغاء الطلب المعلّق، لا موافقة على النفس، المدير لفرعه،
--    ولا طلب لتاريخ مضى عليه أكثر من 30 يوماً (من الموظف نفسه)
-- ---------------------------------------------------------------------
ALTER TABLE public.leave_requests DROP CONSTRAINT IF EXISTS leave_requests_status_check;
ALTER TABLE public.leave_requests ADD CONSTRAINT leave_requests_status_check
  CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled'));

CREATE OR REPLACE FUNCTION public.protect_leave_decisions()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.employee_id = auth.uid()
       AND (NEW.start_date AT TIME ZONE public.company_timezone())::date < v_today - 30 THEN
      RAISE EXCEPTION 'لا يمكن طلب إجازة لتاريخ مضى عليه أكثر من 30 يوماً. راجع الإدارة.' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    -- الموظف يلغي طلبه المعلّق فقط
    IF NEW.employee_id = auth.uid() THEN
      IF OLD.status = 'pending' AND NEW.status = 'cancelled' THEN
        RETURN NEW;
      END IF;
      RAISE EXCEPTION 'لا يمكنك اعتماد أو رفض طلب إجازتك.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.payroll_same_branch(NEW.employee_id) THEN
      RAISE EXCEPTION 'غير مصرح: الموظف من فرع آخر.' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_protect_leave_decisions ON public.leave_requests;
CREATE TRIGGER trg_protect_leave_decisions
BEFORE INSERT OR UPDATE ON public.leave_requests
FOR EACH ROW EXECUTE FUNCTION public.protect_leave_decisions();

-- ---------------------------------------------------------------------
-- 4) السلف: طلب واحد معلّق لكل موظف
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.one_pending_loan_request()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'pending' AND EXISTS (
    SELECT 1 FROM loans WHERE employee_id = NEW.employee_id AND status = 'pending' AND id <> NEW.id
  ) THEN
    RAISE EXCEPTION 'لديك طلب سلفة قيد المراجعة. انتظر قرار الإدارة قبل تقديم طلب جديد.' USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_one_pending_loan_request ON public.loans;
CREATE TRIGGER trg_one_pending_loan_request
BEFORE INSERT ON public.loans
FOR EACH ROW EXECUTE FUNCTION public.one_pending_loan_request();

-- ---------------------------------------------------------------------
-- 5) "مسير هذا الشهر" للموظف قبل الاعتماد: الحركات والمبلغ المتوقع
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_payroll_preview()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  v_month text;
  v_p payroll_periods%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;
  v_month := public.payroll_natural_month((now() AT TIME ZONE public.company_timezone())::date);
  IF v_month IS NULL THEN
    RETURN NULL;
  END IF;
  v_p := public.ensure_payroll_period(v_month);
  PERFORM public.sync_payroll_period(v_month, v_me);

  RETURN jsonb_build_object(
    'period', to_jsonb(v_p),
    'summary', public.payroll_employee_summary(v_me, v_month),
    'events', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'event_date', pe.event_date, 'event_type', pe.event_type, 'minutes', pe.minutes, 'days', pe.days,
               'amount', pe.amount, 'direction', pe.direction, 'status', pe.status, 'notes', pe.notes,
               'carried_from', pe.carried_from)
             ORDER BY pe.event_date, pe.event_type)
      FROM payroll_events pe
      WHERE pe.employee_id = v_me AND pe.payroll_month = v_month AND pe.status <> 'void'
        AND (pe.amount > 0 OR pe.event_type IN ('missing_punch', 'paid_leave'))), '[]'::jsonb)
  );
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_my_payroll_preview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_payroll_preview() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_payroll_run(p_month text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  PERFORM public.sync_payroll_period(p_month);

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
$$;
