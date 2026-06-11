-- =========================================================================
// نظام HR Pro v6.0 - إضافة حقل فرض تغيير كلمة المرور لجدول الموظفين
// =========================================================================

ALTER TABLE employees ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN DEFAULT true NOT NULL;

COMMENT ON COLUMN employees.must_change_password IS 'حقل يحدد ما إذا كان الموظف مطالباً بتغيير كلمة المرور المؤقتة عند أول تسجيل دخول';
