-- لقطة لكل شي بقاعدة البيانات اللي يخص التطبيق، سطر لكل عنصر (فئة + نص)، حتى قاعدتين تنقارن سطر بسطر.
-- تستعملها supabase/schema/baseline.mjs (ملف الأساس ضد الملفات القديمة، وضد القاعدة الحية) — المرحلة 10.
-- النصوص الطويلة (تعريف الدوال والمهام) تنقارن ببصمتها (md5) بس.
-- لازم تشتغل بـ search_path فارغ حتى الأسماء تطلع كاملة (public.x) بكل مكان.
-- الصلاحيات بس للأدوار اللي يستعملها التطبيق (grantee = 0 يعني PUBLIC)
WITH app_roles AS (
  SELECT unnest(ARRAY['anon', 'authenticated', 'service_role', 'postgres']) AS r
)
SELECT 'table' AS kind,
       format('%s kind=%s rls=%s force=%s', c.oid::regclass, c.relkind, c.relrowsecurity, c.relforcerowsecurity) AS item
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
  AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid AND d.deptype = 'e')

UNION ALL
SELECT 'table_grant', format('%s %s %s', c.oid::regclass, coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC'), a.privilege_type)
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace,
     LATERAL aclexplode(coalesce(c.relacl, acldefault(CASE WHEN c.relkind = 'S' THEN 's'::"char" ELSE 'r'::"char" END, c.relowner))) a
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
  AND (a.grantee = 0 OR a.grantee::regrole::text IN (SELECT r FROM app_roles))

UNION ALL
SELECT 'column', format('%s.%s %s notnull=%s default=%s identity=%s generated=%s',
       c.oid::regclass, quote_ident(a.attname), format_type(a.atttypid, a.atttypmod), a.attnotnull,
       pg_get_expr(d.adbin, d.adrelid), a.attidentity, a.attgenerated)
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm') AND a.attnum > 0 AND NOT a.attisdropped

UNION ALL
SELECT 'column_grant', format('%s.%s %s %s', c.oid::regclass, quote_ident(a.attname),
       coalesce(nullif(x.grantee::regrole::text, '-'), 'PUBLIC'), x.privilege_type)
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace,
     LATERAL aclexplode(a.attacl) x
WHERE n.nspname = 'public' AND a.attnum > 0 AND NOT a.attisdropped AND a.attacl IS NOT NULL
  AND (x.grantee = 0 OR x.grantee::regrole::text IN (SELECT r FROM app_roles))

UNION ALL
SELECT 'constraint', format('%s %s %s', con.conrelid::regclass, quote_ident(con.conname), pg_get_constraintdef(con.oid))
FROM pg_constraint con JOIN pg_namespace n ON n.oid = con.connamespace
WHERE n.nspname = 'public' AND con.conrelid <> 0

UNION ALL
SELECT 'index', pg_get_indexdef(i.indexrelid)
FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'

UNION ALL
SELECT 'function', format('%s(%s) secdef=%s volatile=%s config=%s def_md5=%s',
       p.oid::regproc, pg_get_function_identity_arguments(p.oid), p.prosecdef, p.provolatile,
       p.proconfig, md5(pg_get_functiondef(p.oid)))
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
  AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')

UNION ALL
SELECT 'function_grant', format('%s(%s) %s %s', p.oid::regproc, pg_get_function_identity_arguments(p.oid),
       coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC'), a.privilege_type)
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
     LATERAL aclexplode(coalesce(p.proacl, acldefault('f'::"char", p.proowner))) a
WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
  AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
  AND (a.grantee = 0 OR a.grantee::regrole::text IN (SELECT r FROM app_roles))

UNION ALL
SELECT 'trigger', format('%s enabled=%s', pg_get_triggerdef(t.oid), t.tgenabled)
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE NOT t.tgisinternal AND n.nspname IN ('public', 'storage')

UNION ALL
SELECT 'policy', format('%s.%s %s %s %s to=%s using=%s check=%s', schemaname, tablename, quote_ident(policyname),
       permissive, cmd, roles, qual, with_check)
FROM pg_policies
WHERE schemaname IN ('public', 'storage')

UNION ALL
SELECT 'view', format('%s md5=%s', c.oid::regclass, md5(pg_get_viewdef(c.oid)))
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('v', 'm')

UNION ALL
SELECT 'sequence', format('%s start=%s inc=%s min=%s max=%s cycle=%s', s.seqrelid::regclass, s.seqstart,
       s.seqincrement, s.seqmin, s.seqmax, s.seqcycle)
FROM pg_sequence s JOIN pg_class c ON c.oid = s.seqrelid JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'

UNION ALL
SELECT 'comment', format('%s %s', d.objoid::regclass, md5(d.description))
FROM pg_description d JOIN pg_class c ON c.oid = d.objoid JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE d.classoid = 'pg_class'::regclass AND d.objsubid = 0 AND n.nspname = 'public'

UNION ALL
SELECT 'column_comment', format('%s.%s %s', d.objoid::regclass, quote_ident(a.attname), md5(d.description))
FROM pg_description d JOIN pg_class c ON c.oid = d.objoid JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = d.objoid AND a.attnum = d.objsubid
WHERE d.classoid = 'pg_class'::regclass AND d.objsubid > 0 AND n.nspname = 'public'

UNION ALL
SELECT 'function_comment', format('%s(%s) %s', p.oid::regproc, pg_get_function_identity_arguments(p.oid), md5(d.description))
FROM pg_description d JOIN pg_proc p ON p.oid = d.objoid JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE d.classoid = 'pg_proc'::regclass AND n.nspname = 'public'

UNION ALL
SELECT 'type', format('%s %s %s', t.oid::regtype, t.typtype,
       (SELECT string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder) FROM pg_enum e WHERE e.enumtypid = t.oid))
FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'public' AND t.typtype IN ('e', 'd')

UNION ALL
SELECT 'realtime', format('%s.%s', schemaname, tablename)
FROM pg_publication_tables WHERE pubname = 'supabase_realtime'

UNION ALL
SELECT 'bucket', format('%s public=%s limit=%s types=%s', id, public, file_size_limit, allowed_mime_types)
FROM storage.buckets

UNION ALL
SELECT 'cron', format('%s %s md5=%s', jobname, schedule, md5(command))
FROM cron.job

UNION ALL
SELECT 'default_acl', format('%s %s %s %s', d.defaclrole::regrole, d.defaclobjtype,
       coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC'), a.privilege_type)
FROM pg_default_acl d JOIN pg_namespace n ON n.oid = d.defaclnamespace,
     LATERAL aclexplode(d.defaclacl) a
WHERE n.nspname = 'public' AND d.defaclrole::regrole::text = 'postgres'
  AND (a.grantee = 0 OR a.grantee::regrole::text IN (SELECT r FROM app_roles))

UNION ALL
SELECT 'schema_grant', format('public %s %s', coalesce(nullif(a.grantee::regrole::text, '-'), 'PUBLIC'), a.privilege_type)
FROM pg_namespace n, LATERAL aclexplode(n.nspacl) a
WHERE n.nspname = 'public' AND (a.grantee = 0 OR a.grantee::regrole::text IN (SELECT r FROM app_roles))
