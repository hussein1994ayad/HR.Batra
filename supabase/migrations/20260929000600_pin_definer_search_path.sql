-- =========================================================================
-- تثبيت search_path لدوال SECURITY DEFINER القديمة التي أُنشئت بدونه
-- (تنبيه Supabase: function_search_path_mutable). بدون تثبيته يمكن نظرياً
-- لأي مستخدم يملك schema في مسار البحث أن يظلّل جدولاً تستعمله الدالة.
-- كل هذه الدوال تستعمل جداول public أو أسماء مؤهلة (auth.uid, net.http_post)،
-- فالسلوك لا يتغير.
-- =========================================================================
DO $$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.is_admin()',
    'public.is_manager()',
    'public.hard_delete_employee(uuid)',
    'public.invoke_push_notification()',
    'public.purge_old_location_tracking()',
    'public.refresh_orphan_candidates_cache()'
  ] LOOP
    IF to_regprocedure(f) IS NOT NULL THEN
      EXECUTE format('ALTER FUNCTION %s SET search_path = public', f);
    END IF;
  END LOOP;
END $$;
