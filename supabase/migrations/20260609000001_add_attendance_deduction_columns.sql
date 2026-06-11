-- =========================================================================
-- إضافة أعمدة قرارات الخصم إلى جدول الحضور (attendance)
-- deduction_applied: هل تم تطبيق خصم أم إعفاء؟
-- deduction_reason: سبب الخصم أو الإعفاء
-- =========================================================================

ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS deduction_applied BOOLEAN DEFAULT NULL,
ADD COLUMN IF NOT EXISTS deduction_reason TEXT DEFAULT NULL;

COMMENT ON COLUMN attendance.deduction_applied IS 'هل تم تطبيق خصم (true) أو إعفاء (false) أو لم يتخذ قرار بعد (null)';
COMMENT ON COLUMN attendance.deduction_reason IS 'سبب الخصم أو الإعفاء الذي أدخله المدير';
