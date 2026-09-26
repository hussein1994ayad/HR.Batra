-- =========================================================================
-- Reconcile drift on the live project before the July+ migrations.
-- Production was partly edited from the dashboard, so a few objects exist
-- there with a different shape than this repo expects. Every statement is
-- guarded, so on a database built purely from this repo it is a no-op.
-- =========================================================================

-- Return type differs on production; later migrations recreate it with
-- CREATE OR REPLACE, which cannot change a return type.
DROP FUNCTION IF EXISTS public.get_database_size();

-- Dashboard-era overload that writes text[] into document_urls. The repo's
-- version takes extra optional params; keeping both makes RPC calls ambiguous.
DROP FUNCTION IF EXISTS public.create_employee_secure(
  text, text, text, text, text, uuid, numeric, text[], text);

-- employees.document_urls is text[] on production but jsonb everywhere in
-- the repo (functions assign '[]'::jsonb to it). Convert, keeping the data.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'employees'
      AND column_name = 'document_urls' AND data_type = 'ARRAY'
  ) THEN
    DROP VIEW IF EXISTS public.v_employee_directory;
    ALTER TABLE public.employees ALTER COLUMN document_urls DROP DEFAULT;
    ALTER TABLE public.employees
      ALTER COLUMN document_urls TYPE jsonb
      USING to_jsonb(COALESCE(document_urls, ARRAY[]::text[]));
    ALTER TABLE public.employees ALTER COLUMN document_urls SET DEFAULT '[]'::jsonb;

    CREATE VIEW public.v_employee_directory AS
    SELECT e.id, e.employee_code, e.full_name, e.phone, e.email, e.avatar_url,
           e.document_urls, e.is_active, e.role, e.department_id,
           d.name AS department_name, e.branch_id, b.name AS branch_name
    FROM employees e
    LEFT JOIN departments d ON e.department_id = d.id
    LEFT JOIN branches b ON e.branch_id = b.id
    WHERE e.is_active = true;
  END IF;
END $$;
