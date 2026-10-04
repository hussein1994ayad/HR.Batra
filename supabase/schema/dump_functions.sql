SELECT p.proname AS name,
       pg_get_function_identity_arguments(p.oid) AS args,
       pg_get_functiondef(p.oid) AS def
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prokind = 'f'
  AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
ORDER BY p.proname, args;
