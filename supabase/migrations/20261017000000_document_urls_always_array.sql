-- =====================================================================
-- قائمة مستمسكات الموظف (employees.document_urls) لازم تكون قائمة JSON دائماً.
-- تصفير الإطلاق كتبها `{}` (كائن) بدل `[]` للحسابين، فصفحة الموظفين بالموقع وقفت («h.map is not a function»)،
-- والتطبيق والموظف ما يكدر يضيف مستمسك (فحص «إضافة فقط» يقارن قائمة بكائن).
-- هنا: تصحيح القيم الحالية + القيمة الافتراضية قائمة فارغة + قيد يمنع غير القائمة.
-- =====================================================================

UPDATE public.employees
SET document_urls = '[]'::jsonb
WHERE document_urls IS NOT NULL AND jsonb_typeof(document_urls) <> 'array';

ALTER TABLE public.employees ALTER COLUMN document_urls SET DEFAULT '[]'::jsonb;

ALTER TABLE public.employees DROP CONSTRAINT IF EXISTS employees_document_urls_is_array;
ALTER TABLE public.employees ADD CONSTRAINT employees_document_urls_is_array
  CHECK (document_urls IS NULL OR jsonb_typeof(document_urls) = 'array');
