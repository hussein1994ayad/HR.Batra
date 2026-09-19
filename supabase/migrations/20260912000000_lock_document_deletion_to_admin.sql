-- ‰Ÿ«„ HR Pro v6.0 - Õ’— ’·«ÕÌ… Õ–› «·ÊÀ«∆ﬁ Ê«·„” ‰œ«  »«·¬œ„‰ Ê«·„œ—«¡ ›ﬁÿ
DROP POLICY IF EXISTS " \Employees can delete own employee-documents\\ ON storage.objects;
DROP POLICY IF EXISTS \\Only admins and managers can delete employee-documents\\ ON storage.objects;

CREATE POLICY \\Only admins and managers can delete employee-documents\\ ON storage.objects
 FOR DELETE TO authenticated USING (
 bucket_id = 'employee-documents' AND (is_admin() OR is_manager())
 );
