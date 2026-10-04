-- =========================================================================
-- طلب السلفة من التطبيق: إلغاء حد نص الراتب (تنبيه فقط بالتطبيق)
-- =========================================================================
-- هذا الجزء أُضيف لملف 20261003000000 بعد ما انطبق على القاعدة الحية، فـ db push تخطاه.
-- نفس الدالة كما هي بذاك الملف: يبقى منع طلب ثانٍ معلّق، ومنع سلفة مع سلفة جارية،
-- ومنع الأرقام الخيالية (أكثر من 100,000,000 د.ع).
-- =========================================================================
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
