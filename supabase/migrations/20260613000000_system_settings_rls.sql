-- سياسات إعدادات النظام (system_settings)

-- 1. السماح للمشرفين (Admins) برؤية وتعديل وإضافة الإعدادات
CREATE POLICY "Admins can manage system settings"
ON system_settings
FOR ALL
TO authenticated
USING (is_admin())
WITH CHECK (is_admin());

-- 2. السماح للموظفين العاديين (Authenticated) بقراءة الإعدادات
CREATE POLICY "Anyone authenticated can view system settings"
ON system_settings
FOR SELECT
TO authenticated
USING (true);
