-- ==========================================
-- Migration: Add document_urls to employees and update RLS policies
-- ==========================================

-- 1. Add document_urls column to employees table
ALTER TABLE public.employees 
ADD COLUMN IF NOT EXISTS document_urls JSONB DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.employees.document_urls IS 'مصفوفة روابط المستندات الإضافية والوثائق للموظف';

-- 2. Update the v_employee_directory view to include document_urls
DROP VIEW IF EXISTS public.v_employee_directory;

CREATE OR REPLACE VIEW public.v_employee_directory AS
SELECT 
    e.id,
    e.employee_code,
    e.full_name,
    e.phone,
    e.email,
    e.avatar_url,
    e.document_urls,
    e.is_active,
    e.role,
    e.department_id,
    d.name AS department_name,
    e.branch_id,
    b.name AS branch_name
FROM public.employees e
LEFT JOIN public.departments d ON e.department_id = d.id
LEFT JOIN public.branches b ON e.branch_id = b.id
WHERE e.is_active = true;

COMMENT ON VIEW public.v_employee_directory IS 'واجهة دليل الموظفين المحمية التي تستبعد البيانات الحساسة وتعرض الموظفين النشطين فقط';

-- 3. Update Storage RLS Policies for 'documents' and 'avatars'

-- Allow employees to UPDATE their own avatars
DROP POLICY IF EXISTS "Users can update their own avatars" ON storage.objects;
CREATE POLICY "Users can update their own avatars" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'avatars' AND owner = auth.uid());

-- Allow employees to DELETE their own avatars
DROP POLICY IF EXISTS "Users can delete their own avatars" ON storage.objects;
CREATE POLICY "Users can delete their own avatars" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'avatars' AND owner = auth.uid());

-- Allow employees to UPDATE their own documents
DROP POLICY IF EXISTS "Employees can update own documents" ON storage.objects;
CREATE POLICY "Employees can update own documents" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'documents' AND owner = auth.uid());

-- Allow employees to DELETE their own documents
DROP POLICY IF EXISTS "Employees can delete own documents" ON storage.objects;
CREATE POLICY "Employees can delete own documents" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'documents' AND owner = auth.uid());

-- Admins already have "ALL" privileges on documents via "Admins can manage documents"
-- But let's explicitly recreate them to ensure standard definitions.
DROP POLICY IF EXISTS "Admins can manage documents" ON storage.objects;
CREATE POLICY "Admins can manage documents" ON storage.objects
  TO authenticated USING (bucket_id = 'documents' AND is_admin());
