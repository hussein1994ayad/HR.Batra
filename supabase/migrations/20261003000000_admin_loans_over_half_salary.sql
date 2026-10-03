-- =====================================================================
-- السلفة بقسط أكثر من نص الراتب صارت مسموحة (تنبيه فقط)
--
-- بعض الموظفين يسددون جزء من السلفة نقداً (pay_loan_installment بطريقة cash)
-- فالإدارة تحتاج تعطي سلفة أكبر من حد 50%. الحد صار تنبيه بالواجهة فقط
-- عند اعتماد الأدمن (approve_loan / create_direct_loan).
-- وطلب الموظف من التطبيق هم (one_pending_loan_request): التطبيق ينبهه فقط،
-- ويبقى منع الأرقام الخيالية (أكثر من 100,000,000 د.ع) حماية من أخطاء الكتابة.
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

  -- طلبات المستخدمين عبر التطبيق/الموقع فقط (العمليات الداخلية والإعداد تمر)
  IF NEW.status = 'pending' AND current_user IN ('authenticated', 'anon') THEN
    IF EXISTS (SELECT 1 FROM loans WHERE employee_id = NEW.employee_id AND status = 'approved' AND remaining_amount > 0) THEN
      RAISE EXCEPTION 'لديك سلفة جارية لم تُسدَّد بعد. تقدر تطلب سلفة جديدة بعد إكمال سدادها.' USING ERRCODE = '55000';
    END IF;
    IF NEW.amount > 100000000 THEN
      RAISE EXCEPTION 'المبلغ كبير جداً (أكثر من 100,000,000 د.ع). تأكد من المبلغ.' USING ERRCODE = '22023';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
