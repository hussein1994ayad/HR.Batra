-- ===================================================
-- إضافة سياسة RLS لجدول device_tokens لتمكين الموظفين من حفظ رموزهم
-- ===================================================

CREATE POLICY "Employee can manage own device tokens"
  ON device_tokens FOR ALL
  USING (employee_id = auth.uid())
  WITH CHECK (employee_id = auth.uid());
