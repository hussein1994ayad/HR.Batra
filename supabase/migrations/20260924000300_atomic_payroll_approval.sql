-- =========================================================================
-- HR Pro v6.0 — اعتماد الراتب والتراجع عنه كعملية واحدة (Transaction)
-- Date: 2026-09-24
-- =========================================================================
--
-- كانت لوحة الويب تنفّذ ~10 عمليات كتابة متتالية (كشف الراتب، تسديد الأقساط،
-- قيود التسوية والخصومات) بدون transaction وبدون فحص أخطاء، فأي فشل في
-- المنتصف يترك الراتب "نصف معتمد". والتراجع كان يُرجع الأقساط حسب تاريخ
-- الاستحقاق وليس حسب الأقساط التي خُصمت فعلاً بهذا الكشف.
--
-- الآن:
--   • approve_salary_slip()  — كل شيء ينجح معاً أو يفشل معاً
--   • revert_salary_slip()   — يتراجع عن نفس الأقساط والقيود المرتبطة بالكشف
--   • bonuses_deductions.salary_slip_id و loan_installments.paid_by_slip_id
--     يربطان القيود والأقساط بالكشف الذي أنشأها
-- =========================================================================


-- =====================================================================
-- 1) أعمدة الربط
-- =====================================================================

ALTER TABLE bonuses_deductions
  ADD COLUMN IF NOT EXISTS salary_slip_id UUID REFERENCES salary_slips(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_bonuses_deductions_salary_slip ON bonuses_deductions(salary_slip_id);

ALTER TABLE loan_installments
  ADD COLUMN IF NOT EXISTS paid_by_slip_id UUID REFERENCES salary_slips(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_loan_installments_paid_by_slip ON loan_installments(paid_by_slip_id);

-- أعمدة طريقة السداد التي تكتبها صفحة السلف (سداد نقدي / خصم من الراتب)
-- كانت مستعملة في الويب بدون أي migration يضيفها
ALTER TABLE loan_installments ADD COLUMN IF NOT EXISTS payment_type TEXT;
ALTER TABLE loan_installments ADD COLUMN IF NOT EXISTS payment_note TEXT;

COMMENT ON COLUMN bonuses_deductions.salary_slip_id IS
'الكشف الذي أنشأ هذا القيد تلقائياً عند الاعتماد. يُحذف القيد مع الكشف عند التراجع. NULL = قيد يدوي.';
COMMENT ON COLUMN loan_installments.paid_by_slip_id IS
'الكشف الذي سدّد هذا القسط. يُستعمل لإرجاع القسط غير مدفوع عند التراجع عن الكشف.';


-- =====================================================================
-- 2) approve_salary_slip
--
-- p_adjustments: مصفوفة JSON من القيود التي تُنشأ مع الكشف:
--   [{ "type": "bonus"|"deduction", "amount": 1000, "reason": "...",
--      "issue_date": "2026-09-24", "skip_if_exists": true }]
-- skip_if_exists: لا يُنشأ القيد إذا وُجد قيد بنفس الموظف والنوع والسبب
-- (سلوك insertBDIfNotExist السابق لخصومات الحضور التلقائية).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.approve_salary_slip(
  p_employee_id uuid,
  p_work_month text,
  p_basic_salary numeric,
  p_allowances numeric,
  p_deductions numeric,
  p_loans_deduction numeric,
  p_net_salary numeric,
  p_installment_ids uuid[] DEFAULT '{}',
  p_adjustments jsonb DEFAULT '[]'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slip_id uuid;
  v_adj jsonb;
BEGIN
  PERFORM public.require_admin();

  IF EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_work_month) THEN
    RAISE EXCEPTION 'هذا الشهر مؤرشف مالياً ومقفل.' USING ERRCODE = '42501';
  END IF;

  BEGIN
    INSERT INTO salary_slips (employee_id, work_month, basic_salary, allowances,
                              deductions, loans_deduction, net_salary, status)
    VALUES (p_employee_id, p_work_month, p_basic_salary, COALESCE(p_allowances, 0),
            COALESCE(p_deductions, 0), COALESCE(p_loans_deduction, 0), p_net_salary, 'published')
    RETURNING id INTO v_slip_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'تم صرف الراتب مسبقاً لهذا الموظف في هذا الشهر.' USING ERRCODE = '23505';
  END;

  UPDATE loan_installments li
  SET is_paid = true, paid_at = now(), paid_by_slip_id = v_slip_id
  FROM loans l
  WHERE li.id = ANY(COALESCE(p_installment_ids, '{}'))
    AND li.loan_id = l.id
    AND l.employee_id = p_employee_id
    AND li.is_paid = false;

  FOR v_adj IN SELECT * FROM jsonb_array_elements(COALESCE(p_adjustments, '[]'::jsonb))
  LOOP
    CONTINUE WHEN COALESCE((v_adj->>'amount')::numeric, 0) <= 0;
    CONTINUE WHEN COALESCE((v_adj->>'skip_if_exists')::boolean, false) AND EXISTS (
      SELECT 1 FROM bonuses_deductions
      WHERE employee_id = p_employee_id
        AND type = v_adj->>'type'
        AND reason = v_adj->>'reason'
    );

    INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date,
                                    created_by, salary_slip_id)
    VALUES (p_employee_id, v_adj->>'type', (v_adj->>'amount')::numeric, v_adj->>'reason',
            COALESCE((v_adj->>'issue_date')::date, current_date), auth.uid(), v_slip_id);
  END LOOP;

  RETURN v_slip_id;
END;
$$;


-- =====================================================================
-- 3) revert_salary_slip
--
-- الكشوف الجديدة: يُرجع الأقساط المرتبطة (paid_by_slip_id) وتُحذف القيود
-- المرتبطة تلقائياً (ON DELETE CASCADE).
-- الكشوف القديمة (قبل هذا الملف، بدون روابط): نفس السلوك السابق للويب —
-- حذف القيود بنص السبب للفترة، وإرجاع الأقساط المستحقة ضمن الفترة.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.revert_salary_slip(
  p_slip_id uuid,
  p_period_start date,
  p_period_end date
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_slip salary_slips%ROWTYPE;
  v_linked boolean;
BEGIN
  PERFORM public.require_admin();

  SELECT * INTO v_slip FROM salary_slips WHERE id = p_slip_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'كشف الراتب غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF EXISTS (SELECT 1 FROM archived_months WHERE work_month = v_slip.work_month) THEN
    RAISE EXCEPTION 'هذا الشهر مؤرشف مالياً ومقفل.' USING ERRCODE = '42501';
  END IF;

  v_linked := EXISTS (SELECT 1 FROM loan_installments WHERE paid_by_slip_id = p_slip_id)
           OR EXISTS (SELECT 1 FROM bonuses_deductions WHERE salary_slip_id = p_slip_id);

  IF v_linked THEN
    UPDATE loan_installments
    SET is_paid = false, paid_at = NULL, paid_by_slip_id = NULL
    WHERE paid_by_slip_id = p_slip_id;
  ELSE
    DELETE FROM bonuses_deductions
    WHERE employee_id = v_slip.employee_id
      AND salary_slip_id IS NULL
      AND issue_date = p_period_end
      AND (reason LIKE '%للفترة من ' || p_period_start || ' إلى ' || p_period_end || '%'
           OR reason LIKE '%لشهر ' || v_slip.work_month || '%');

    UPDATE loan_installments li
    SET is_paid = false, paid_at = NULL
    FROM loans l
    WHERE li.loan_id = l.id
      AND l.employee_id = v_slip.employee_id
      AND li.is_paid = true
      AND li.due_date BETWEEN p_period_start AND p_period_end;
  END IF;

  DELETE FROM salary_slips WHERE id = p_slip_id;
END;
$$;


REVOKE EXECUTE ON FUNCTION
  public.approve_salary_slip(uuid, text, numeric, numeric, numeric, numeric, numeric, uuid[], jsonb),
  public.revert_salary_slip(uuid, date, date)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.approve_salary_slip(uuid, text, numeric, numeric, numeric, numeric, numeric, uuid[], jsonb),
  public.revert_salary_slip(uuid, date, date)
TO authenticated, service_role;
