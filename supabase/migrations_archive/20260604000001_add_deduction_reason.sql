-- ==========================================
-- إضافة عمود سبب الخصم لقرارات الغياب والتأخير
-- ==========================================

ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS deduction_reason TEXT;
