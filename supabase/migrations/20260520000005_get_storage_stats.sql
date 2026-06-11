-- ==========================================
-- نظام HR Pro v6.0 - دالة إحصائيات التخزين السحابي
-- ==========================================

CREATE OR REPLACE FUNCTION public.get_storage_stats()
RETURNS TABLE (bucket_name text, total_size bigint) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    b.id AS bucket_name,
    COALESCE(SUM((o.metadata->>'size')::bigint), 0)::bigint AS total_size
  FROM storage.buckets b
  LEFT JOIN storage.objects o ON o.bucket_id = b.id
  GROUP BY b.id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.get_storage_stats IS 'تقوم بحساب إجمالي حجم الملفات في كل مجلد تخزين سحابي على Supabase Storage لتقديم إحصائيات دقيقة';
