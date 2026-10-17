-- =========================================================================
-- HR Pro — حذف عمود رمز الإشعارات القديم (المرحلة 10 الجزء الثالث، تدقيق 14/10 CODE-007)
-- Date: 2026-10-17
-- Related: audit stage 10 | 20261024000000_stage9_cleanup.sql (copy_legacy_push_token)
-- =========================================================================
--
-- رمز الإشعارات صار بـ fcm_tokens بس (من المرحلة 9). الموقع والتطبيق من المرحلة 10 الجزء الثاني ما يقرون
-- employees.fcm_token، فالعمود والـ trigger والدالة اللي تنقل منه ينحذفون. أي رمز باقي بالعمود ينتقل قبل الحذف.
--
-- قرار صاحب الشركة 17/10/2026: كل الموبايلات على النسخة الأخيرة (المشروع بعده بمرحلة البناء).
-- =========================================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'employees' AND column_name = 'fcm_token') THEN
    EXECUTE $copy$
      INSERT INTO public.fcm_tokens (employee_id, token)
      SELECT e.id, e.fcm_token FROM public.employees e WHERE NULLIF(btrim(e.fcm_token), '') IS NOT NULL
      ON CONFLICT (employee_id, token) DO NOTHING
    $copy$;
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_copy_legacy_push_token ON public.employees;
ALTER TABLE public.employees DROP COLUMN IF EXISTS fcm_token;
DROP FUNCTION IF EXISTS public.copy_legacy_push_token();
