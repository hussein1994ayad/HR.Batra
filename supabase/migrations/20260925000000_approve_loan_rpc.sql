-- =====================================================================
-- اعتماد السلف وتوليد أقساطها في معاملة واحدة (approve_loan / create_direct_loan)
--
-- كانت لوحة الويب والتطبيق تعتمدان السلفة بطريقتين مختلفتين وبخطوتين منفصلتين:
--   • الويب: يحدّث السلفة ثم يُدخل الأقساط — فشل الخطوة الثانية يترك سلفة
--     معتمدة بدون أقساط.
--   • التطبيق: يغيّر الحالة فقط (بدون remaining_amount/installment_*)،
--     ويقرّب القسط فلا يساوي مجموع الأقساط مبلغ السلفة، ولا يتحقق من
--     وجود سلفة جارية أو من حد 50% من الراتب.
-- الآن كلاهما يستدعي approve_loan، وإضافة الأدمن لسلفة مباشرة من التطبيق
-- (كانت تكتب عموداً غير موجود reason فتفشل دائماً) تستدعي create_direct_loan.
--
-- قواعد الجدولة (نفس features/loans/logic.ts في الويب):
--   • القسط = floor(المبلغ / الأشهر)، والقسط الأخير يأخذ فرق التقريب.
--   • تاريخ القسط n = تاريخ أول قسط + n شهر، مع تثبيت اليوم على آخر الشهر
--     (31 كانون الثاني + شهر = 28/29 شباط).
-- =====================================================================

ALTER TABLE loans ADD COLUMN IF NOT EXISTS notes TEXT;
COMMENT ON COLUMN loans.notes IS 'ملاحظات الإدارة أو سبب منح السلفة المباشرة';


-- ---------------------------------------------------------------------
-- مساعدتان داخليتان (غير متاحتين للعملاء)
-- ---------------------------------------------------------------------

-- يرفض شروط سلفة غير صالحة، ويرجع قيمة القسط الأساسي.
CREATE OR REPLACE FUNCTION public._validate_loan_terms(
  p_employee_id uuid,
  p_amount numeric,
  p_months integer,
  p_first_due date,
  p_ignore_loan uuid DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_salary numeric;
  v_base numeric;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 OR p_months IS NULL OR p_months <= 0 THEN
    RAISE EXCEPTION 'يرجى إدخال مبلغ وعدد أشهر سداد أكبر من الصفر.' USING ERRCODE = '22023';
  END IF;
  IF p_first_due IS NULL THEN
    RAISE EXCEPTION 'يرجى تحديد تاريخ استحقاق أول قسط.' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM loans
    WHERE employee_id = p_employee_id AND status = 'approved' AND remaining_amount > 0
      AND id IS DISTINCT FROM p_ignore_loan
  ) THEN
    RAISE EXCEPTION 'لا يمكن الموافقة: الموظف لديه سلفة نشطة حالياً. يرجى إغلاقها أولاً.' USING ERRCODE = '55000';
  END IF;

  v_base := floor(p_amount / p_months);
  SELECT monthly_salary_iqd INTO v_salary FROM employees WHERE id = p_employee_id;
  IF COALESCE(v_salary, 0) > 0 AND v_base > v_salary * 0.5 THEN
    RAISE EXCEPTION 'مبلغ القسط يتجاوز 50%% من راتب الموظف. يرجى زيادة مدة السداد أو تقليل المبلغ.' USING ERRCODE = '22023';
  END IF;
  RETURN v_base;
END;
$$;

CREATE OR REPLACE FUNCTION public._insert_loan_installments(
  p_loan_id uuid,
  p_amount numeric,
  p_months integer,
  p_first_due date
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO loan_installments (loan_id, due_date, amount, is_paid)
  SELECT p_loan_id,
         (p_first_due + make_interval(months => g))::date,
         CASE WHEN g = p_months - 1
              THEN p_amount - floor(p_amount / p_months) * (p_months - 1)
              ELSE floor(p_amount / p_months) END,
         false
  FROM generate_series(0, p_months - 1) AS g;
$$;

REVOKE EXECUTE ON FUNCTION
  public._validate_loan_terms(uuid, numeric, integer, date, uuid),
  public._insert_loan_installments(uuid, numeric, integer, date)
FROM PUBLIC, anon, authenticated;


-- ---------------------------------------------------------------------
-- approve_loan: اعتماد طلب معلّق (بمبلغ ومدة قابلين للتعديل)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_loan(
  p_loan_id uuid,
  p_amount numeric,
  p_months integer,
  p_first_due date
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_loan loans%ROWTYPE;
  v_base numeric;
BEGIN
  PERFORM public.require_admin();

  SELECT * INTO v_loan FROM loans WHERE id = p_loan_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'طلب السلفة غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF v_loan.status <> 'pending' THEN
    RAISE EXCEPTION 'تمت معالجة طلب السلفة هذا مسبقاً.' USING ERRCODE = '55000';
  END IF;

  v_base := public._validate_loan_terms(v_loan.employee_id, p_amount, p_months, p_first_due, p_loan_id);

  UPDATE loans
  SET status = 'approved',
      amount = p_amount,
      installment_count = p_months,
      installment_amount = v_base,
      remaining_amount = p_amount,
      approved_by = auth.uid(),
      approved_at = now()
  WHERE id = p_loan_id;

  PERFORM public._insert_loan_installments(p_loan_id, p_amount, p_months, p_first_due);
END;
$$;

COMMENT ON FUNCTION public.approve_loan(uuid, numeric, integer, date) IS
'اعتماد طلب سلفة معلّق وتوليد أقساطه في معاملة واحدة. مقفل على الأدمن.
يرفض إن كانت للموظف سلفة جارية أو تجاوز القسط 50% من الراتب.';


-- ---------------------------------------------------------------------
-- create_direct_loan: الأدمن يمنح سلفة معتمدة مباشرة لموظف
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_direct_loan(
  p_employee_id uuid,
  p_amount numeric,
  p_months integer,
  p_first_due date,
  p_pledge_url text,
  p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base numeric;
  v_loan_id uuid;
BEGIN
  PERFORM public.require_admin();

  IF p_pledge_url IS NULL OR btrim(p_pledge_url) = '' THEN
    RAISE EXCEPTION 'صورة التعهد الخطي إلزامية لكل سلفة.' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM employees WHERE id = p_employee_id AND is_active) THEN
    RAISE EXCEPTION 'الموظف غير موجود أو غير نشط.' USING ERRCODE = 'P0002';
  END IF;

  v_base := public._validate_loan_terms(p_employee_id, p_amount, p_months, p_first_due);

  -- تُدرج معتمدة مباشرة، فلا يُرسل تنبيه "طلب جديد" للمدراء (المُطلق يعمل على 'pending' فقط)
  INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount,
                     pledge_url, status, notes, approved_by, approved_at)
  VALUES (p_employee_id, p_amount, v_base, p_months, p_amount,
          p_pledge_url, 'approved', NULLIF(btrim(COALESCE(p_notes, '')), ''), auth.uid(), now())
  RETURNING id INTO v_loan_id;

  PERFORM public._insert_loan_installments(v_loan_id, p_amount, p_months, p_first_due);

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (
    p_employee_id,
    'تم منحك سلفة مالية جديدة 💸',
    format('تم اعتماد سلفة جديدة لك بقيمة %s د.ع مقسمة على %s أقساط شهرية.',
           to_char(p_amount, 'FM999G999G999'), p_months),
    'loan'
  );

  RETURN v_loan_id;
END;
$$;

COMMENT ON FUNCTION public.create_direct_loan(uuid, numeric, integer, date, text, text) IS
'منح سلفة معتمدة مباشرة لموظف مع أقساطها وإشعاره، في معاملة واحدة. مقفل على الأدمن.';

REVOKE EXECUTE ON FUNCTION
  public.approve_loan(uuid, numeric, integer, date),
  public.create_direct_loan(uuid, numeric, integer, date, text, text)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.approve_loan(uuid, numeric, integer, date),
  public.create_direct_loan(uuid, numeric, integer, date, text, text)
TO authenticated, service_role;


-- =====================================================================
-- إصلاح: إشعار المدراء بطلب سلفة جديد
-- 20260920000300 يقرأ NEW.installments وهو عمود غير موجود في loans
-- (الاسم الصحيح installment_count)، فكان كل إدراج لطلب سلفة يفشل بالخطأ:
--   record "new" has no field "installments"
-- =====================================================================

CREATE OR REPLACE FUNCTION public.notify_admins_of_new_loan_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_employee_name  TEXT;
    v_amount_str     TEXT;
BEGIN
    IF NEW.status != 'pending' THEN
        RETURN NEW;
    END IF;

    SELECT full_name INTO v_employee_name
    FROM employees
    WHERE id = NEW.employee_id;

    v_amount_str := to_char(NEW.amount, 'FM999G999G999') || ' د.ع';

    INSERT INTO notifications (employee_id, title, body, type)
    SELECT
        e.id,
        '💰 طلب سلفة جديد بانتظار الموافقة',
        format(
            'قدّم %s طلب سلفة بمبلغ %s على %s قسط — يرجى المراجعة.',
            COALESCE(v_employee_name, 'موظف'),
            v_amount_str,
            COALESCE(NEW.installment_count::TEXT, '—')
        ),
        'loan'
    FROM employees e
    WHERE e.role IN ('admin', 'manager')
      AND e.is_active = true
      AND e.id != NEW.employee_id;

    RETURN NEW;
END;
$$;
