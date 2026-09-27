-- =====================================================================
-- سداد قسط بمبلغ مختلف عن المجدول (pay_loan_installment)
--
-- مثال: سلفة 500,000 على 5 أشهر (100,000 شهرياً):
--   • الشهر 2 دفع 150,000 ← الأقساط الباقية 100,000 / 100,000 / 50,000
--   • الشهر 2 دفع 50,000  ← الأقساط الباقية 100,000 / 100,000 / 150,000
--   • دفع أقل في آخر قسط ← يُضاف قسط جديد بالفرق للشهر التالي
-- إعادة التوزيع يسويها التريجر trg_update_loan_and_installments: كل الأقساط
-- غير المدفوعة بقيمة القسط الأساسي، وآخرها يأخذ الفرق (زيادة أو نقصان)،
-- والأقساط التي لم يعد لها رصيد تُحذف.
--
-- كانت الواجهة تسجل السداد بقيمة القسط المجدولة فقط، وتعديل قيمة قسط غير
-- مدفوع كان يُلغى فوراً لأن التريجر يعيد التوزيع.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.pay_loan_installment(
  p_installment_id uuid,
  p_amount numeric,
  p_method text DEFAULT 'cash',
  p_note text DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

COMMENT ON FUNCTION public.pay_loan_installment(uuid, numeric, text, text) IS
'يسجل سداد قسط بأي مبلغ (نقداً أو استقطاع راتب) ويعيد توزيع المتبقي على الأقساط القادمة. مقفل على الأدمن.';

REVOKE EXECUTE ON FUNCTION public.pay_loan_installment(uuid, numeric, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pay_loan_installment(uuid, numeric, text, text) TO authenticated, service_role;
