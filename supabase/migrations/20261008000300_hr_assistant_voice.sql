-- =====================================================================
-- المساعد الذكي — السؤال بالصوت: أسماء الموظفين والفروع كسياق للنسخ حتى تنكتب الأسماء صح من الكلام العراقي.
-- قراءة فقط، أدمن فقط، أسماء بس (بدون أي بيانات ثانية).
-- =====================================================================
CREATE OR REPLACE FUNCTION public.assistant_name_hints()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  RETURN jsonb_build_object(
    'employees', COALESCE((SELECT jsonb_agg(full_name ORDER BY full_name) FROM employees WHERE is_active), '[]'::jsonb),
    'branches', COALESCE((SELECT jsonb_agg(name ORDER BY name) FROM branches), '[]'::jsonb));
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.assistant_name_hints() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assistant_name_hints() TO authenticated;
