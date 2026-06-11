-- ==========================================
-- تحديث قيد نوع الإشعارات ليشمل التعاميم الإدارية
-- ==========================================

ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN ('leave', 'loan', 'bonus_deduction', 'attendance', 'salary', 'document', 'device', 'ota', 'system', 'memo'));
