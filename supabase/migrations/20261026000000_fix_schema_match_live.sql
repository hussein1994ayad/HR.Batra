-- =========================================================================
-- HR Pro — الملفات تطابق السيرفر الحي (المرحلة 10 الجزء الثاني، تدقيق 14/10 CODE-002)
-- Date: 2026-10-17
-- Related: audit stage 10 | supabase/schema/baseline.mjs --live
-- =========================================================================
--
-- مقارنة ملف الأساس ويا السيرفر الحي لكطت 6 اختلافات قديمة (من أيار وحزيران 2026، أشياء انعملت من لوحة
-- Supabase قبل ما تنكتب الملفات). السيرفر الحي هو الشغال، فالملفات تمشي عليه. على السيرفر الحي ما يتغير شي
-- (غير وصف دليل الموظفين ينضاف)، وأي قاعدة جديدة تطلع مثل الحية بالضبط.
--
-- قرار صاحب الشركة 17/10/2026: «إي، ضيفها».
-- =========================================================================

-- 1) تاريخ المباشرة بدون قيمة افتراضية (مثل الحية): الموقع والتطبيق يطلبونه، ودوال إضافة الموظف تحط يوم بغداد
ALTER TABLE public.employees ALTER COLUMN join_date DROP DEFAULT;

-- 2) حالة منطقة السياج تقبل الفارغ (مثل الحية؛ الافتراضي يبقى true)
ALTER TABLE public.geofence_zones ALTER COLUMN is_active DROP NOT NULL;

-- 3) طريقة دفع القسط افتراضياً: خصم من الراتب (مثل الحية)
ALTER TABLE public.loan_installments ALTER COLUMN payment_type SET DEFAULT 'salary_deduction';

-- 4) وصف دليل الموظفين (ينضاف للحية؛ توثيق بس)
COMMENT ON VIEW public.v_employee_directory IS 'واجهة دليل الموظفين المحمية التي تستبعد البيانات الحساسة وتعرض الموظفين النشطين فقط';

-- 5) رفع صورة تعهد السلفة: المجلد الثاني بالمسار = رقم الموظف (مثل الحية؛ الملفات القديمة چانت تفحص owner)
DROP POLICY IF EXISTS "Employees can upload loan pledges" ON storage.objects;
CREATE POLICY "Employees can upload loan pledges" ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'loan-pledges' AND (storage.foldername(name))[2] = (auth.uid())::text);

-- 6) مخزن مستمسكات الموظفين (موجود بالحية، انعمل من اللوحة؛ صلاحياته بالملفات من 20260621000000)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('employee-documents', 'employee-documents', false, 10485760, ARRAY['image/*', 'application/pdf']::text[])
ON CONFLICT (id) DO NOTHING;
