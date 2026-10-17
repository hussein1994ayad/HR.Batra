-- =====================================================================
-- لا يُعتمد كشف راتب بصافي سالب
-- ظهر كشف صافيه -66,667 لأن قسط السلفة (666,667) أكبر من الراتب (600,000).
-- الحل عند الإدارة: تأجيل القسط أو تسجيل دفعة جزئية من صفحة السلف قبل الاعتماد.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.reject_negative_salary_slip()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.net_salary < 0 THEN
    RAISE EXCEPTION 'صافي الراتب بالسالب (%). الخصومات وأقساط السلف أكبر من الراتب: أجّل القسط أو سجّل دفعة جزئية من صفحة السلف ثم أعد الاعتماد.',
      to_char(NEW.net_salary, 'FM999,999,999')
      USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_negative_salary_slip ON public.salary_slips;
CREATE TRIGGER trg_reject_negative_salary_slip
BEFORE INSERT OR UPDATE OF net_salary ON public.salary_slips
FOR EACH ROW EXECUTE FUNCTION public.reject_negative_salary_slip();
