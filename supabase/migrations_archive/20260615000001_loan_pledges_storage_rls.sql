-- ===================================================
-- إضافة سياسات SELECT و UPDATE و DELETE لـ loan-pledges لتمكين الـ upsert
-- ===================================================

CREATE POLICY "Employees can view own loan pledges" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'loan-pledges'::text AND (storage.foldername(name))[2] = (auth.uid())::text);

CREATE POLICY "Employees can update own loan pledges" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'loan-pledges'::text AND (storage.foldername(name))[2] = (auth.uid())::text)
  WITH CHECK (bucket_id = 'loan-pledges'::text AND (storage.foldername(name))[2] = (auth.uid())::text);

CREATE POLICY "Employees can delete own loan pledges" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'loan-pledges'::text AND (storage.foldername(name))[2] = (auth.uid())::text);
