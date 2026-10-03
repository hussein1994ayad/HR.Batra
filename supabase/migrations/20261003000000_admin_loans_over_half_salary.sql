-- =====================================================================
-- الأدمن يقدر يعطي سلفة قسطها أكثر من نص الراتب
--
-- بعض الموظفين يسددون جزء من السلفة نقداً (pay_loan_installment بطريقة cash)
-- فالإدارة تحتاج تعطي سلفة أكبر من حد 50%. الحد صار تنبيه بالواجهة فقط
-- عند اعتماد الأدمن (approve_loan / create_direct_loan).
-- طلب الموظف من التطبيق يبقى محدداً بنص الراتب (one_pending_loan_request).
-- =====================================================================

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

  RETURN floor(p_amount / p_months);
END;
$$;

REVOKE EXECUTE ON FUNCTION public._validate_loan_terms(uuid, numeric, integer, date, uuid)
FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.approve_loan(uuid, numeric, integer, date) IS
'اعتماد طلب سلفة معلّق وتوليد أقساطه في معاملة واحدة. مقفل على الأدمن.
يرفض إن كانت للموظف سلفة جارية. القسط فوق نص الراتب مسموح (تنبيه بالواجهة).';
