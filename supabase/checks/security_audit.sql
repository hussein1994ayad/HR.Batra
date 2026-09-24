-- =========================================================================
-- HR Pro — فحص أمني لقاعدة البيانات الحية (قراءة فقط، لا يعدّل شيئاً)
-- =========================================================================
-- شغّله من Supabase Dashboard → SQL Editor بعد تطبيق الـ migrations.
-- كل استعلام يجب أن يرجع صفر نتائج، ما عدا الأخير (قائمة السياسات للمراجعة).
-- السبب: جزء من المخطط والسياسات أُضيف يدوياً من اللوحة وليس موجوداً في
-- ملفات الـ migrations، فلا يمكن التأكد منه إلا من القاعدة نفسها.
-- =========================================================================

-- 1) جداول في public بدون RLS
SELECT 'table_without_rls' AS issue, c.relname AS object
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity;

-- 2) دوال SECURITY DEFINER قابلة للتنفيذ من anon (عدا is_admin/is_manager)
SELECT 'definer_function_executable_by_anon' AS issue,
       p.oid::regprocedure::text AS object
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
  AND p.proname NOT IN ('is_admin', 'is_manager');

-- 3) Views لا تحترم RLS
SELECT 'view_without_security_invoker' AS issue, c.relname AS object
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'v'
  AND NOT COALESCE('security_invoker=true' = ANY(c.reloptions), false);

-- 4) سياسات تسمح لأي مستخدم بالكتابة بدون شرط (WITH CHECK true)
SELECT 'permissive_write_policy' AS issue,
       tablename || ' / ' || policyname AS object
FROM pg_policies
WHERE schemaname = 'public'
  AND cmd IN ('INSERT', 'UPDATE', 'ALL')
  AND (with_check = 'true' OR (with_check IS NULL AND qual = 'true'));

-- 5) نسخ متعددة من نفس الدالة (قد تبقى نسخة قديمة غير مؤمّنة)
SELECT 'overloaded_function' AS issue, proname AS object
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
GROUP BY proname
HAVING count(*) > 1;

-- 6) للمراجعة اليدوية: كل السياسات الحالية
SELECT tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname IN ('public', 'storage')
ORDER BY tablename, cmd, policyname;
