-- ==========================================
-- إضافة عمود حالة الخصم لقرارات الغياب والتأخير
-- ==========================================

ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS deduction_status TEXT DEFAULT 'pending' CHECK (deduction_status IN ('pending', 'applied', 'ignored'));
