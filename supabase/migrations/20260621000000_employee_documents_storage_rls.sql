-- ===================================================
-- إضافة سياسات SELECT و INSERT و UPDATE و DELETE لـ employee-documents
-- لضمان أمان خصوصية مستندات الموظفين ومنع تصفح مستندات الآخرين
-- ===================================================

-- 1. حذف السياسات المفتوحة القديمة لـ employee-documents
DROP POLICY IF EXISTS "Allow authenticated to insert employee documents" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated to select employee documents" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated to update employee documents" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated to delete employee documents" ON storage.objects;

-- 2. إدراج السياسات المحكمة والآمنة الجديدة
CREATE POLICY "Admins can manage employee-documents" ON storage.objects
  TO authenticated USING (bucket_id = 'employee-documents' AND is_admin());

CREATE POLICY "Employees can view own employee-documents" ON storage.objects
  FOR SELECT TO authenticated USING (bucket_id = 'employee-documents' AND ((storage.foldername(name))[1] = (auth.uid())::text OR is_admin()));

CREATE POLICY "Employees can upload own employee-documents" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (bucket_id = 'employee-documents' AND ((storage.foldername(name))[1] = (auth.uid())::text OR is_admin()));

CREATE POLICY "Employees can update own employee-documents" ON storage.objects
  FOR UPDATE TO authenticated USING (bucket_id = 'employee-documents' AND ((storage.foldername(name))[1] = (auth.uid())::text OR is_admin()));

CREATE POLICY "Employees can delete own employee-documents" ON storage.objects
  FOR DELETE TO authenticated USING (bucket_id = 'employee-documents' AND ((storage.foldername(name))[1] = (auth.uid())::text OR is_admin()));
