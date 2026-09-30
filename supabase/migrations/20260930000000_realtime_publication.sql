-- =========================================================================
-- التحديث المباشر (Realtime) للجداول التي تستمع لها الشاشات
-- =========================================================================
-- على القاعدة الحية كان جدول notifications وحده داخل publication الـ realtime،
-- فكل الاشتراكات الأخرى ترجع channelError ولا تتحدث الشاشات إلا بالسحب:
--   attendance        كارد الحضور بالرئيسية + لوحة الإدارة
--   leave_requests    عدّاد الطلبات بالموقع
--   loans             عدّاد السلف بالموقع
--   location_tracking خريطة التتبع المباشر (الموقع والتطبيق)
-- الـ Realtime يطبّق سياسات RLS نفسها، فكل مستخدم يستلم فقط الصفوف المسموح له بقراءتها.
-- =========================================================================
DO $$
DECLARE
  t text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RETURN;
  END IF;
  FOREACH t IN ARRAY ARRAY['attendance', 'leave_requests', 'loans', 'location_tracking'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;
