-- =========================================================================
-- الموظف يگدر يلغي طلب سلفة ما زال قيد المراجعة (مثل الإجازات)
-- =========================================================================
-- قبل: ماكو طريقة للإلغاء، والموظف ما يگدر يقدّم طلب ثاني (طلب معلّق واحد فقط)
-- إلا بعد ما الإدارة ترفض الأول.
-- الجدول يبقى للأدمن فقط بالتعديل؛ الإلغاء يمر من هذه الدالة: صاحب الطلب، والطلب pending.
-- =========================================================================
ALTER TABLE public.loans DROP CONSTRAINT IF EXISTS loans_status_check;
ALTER TABLE public.loans ADD CONSTRAINT loans_status_check
  CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled'));

CREATE OR REPLACE FUNCTION public.cancel_my_loan_request(p_loan_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  UPDATE loans SET status = 'cancelled'
  WHERE id = p_loan_id AND employee_id = auth.uid() AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يمكن إلغاء هذا الطلب (غير موجود أو تمت معالجته).' USING ERRCODE = '55000';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_my_loan_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_my_loan_request(uuid) TO authenticated;
