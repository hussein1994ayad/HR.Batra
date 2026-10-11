-- =====================================================================
-- عمر بيانات التتبع (GPS) برقم واحد.
-- كان اكو قاعدتين: مهمة شهرية تحذف بعد 90 يوم (رقم ثابت بالكود)، والتنظيف اليومي يحذف حسب الإعداد
-- (tracking_archive_days، كان 180). فالـ 90 تمشي دائماً والإعداد بالشاشة ما إله تأثير فوقها.
-- هسه: الإعداد هو المصدر الوحيد (45 يوم)، والتنظيف اليومي (perform_daily_cleanup) هو اللي يحذف.
-- 45 يوم = مسير كامل (30–31 يوم) + وقت اعتماد رواتبه وأي اعتراض عليه؛ «البصمة الناقصة» تعتمد على آخر
-- نقطة تتبع بنفس اليوم، فالحد الأدنى 35 يوم حتى ما تنحذف نقاط مسير بعده مفتوح.
-- =====================================================================

-- الإعداد لازم يكون بين 35 و 366 يوم
CREATE OR REPLACE FUNCTION public.check_archive_policy()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_days int;
BEGIN
  IF NEW.key = 'archive_policy' AND NEW.value ? 'tracking_archive_days' THEN
    v_days := (NEW.value ->> 'tracking_archive_days')::int;
    IF v_days IS NULL OR v_days < 35 OR v_days > 366 THEN
      RAISE EXCEPTION 'مدة الاحتفاظ ببيانات التتبع لازم تكون بين 35 و 366 يوم (حتى ما تنحذف نقاط مسير رواتب بعده مفتوح).'
        USING ERRCODE = '22023';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_check_archive_policy ON public.system_settings;
CREATE TRIGGER trg_check_archive_policy BEFORE INSERT OR UPDATE OF value ON public.system_settings
  FOR EACH ROW EXECUTE FUNCTION public.check_archive_policy();

-- القيمة الجديدة: 45 يوم
INSERT INTO public.system_settings (key, value, description)
VALUES ('archive_policy', '{"tracking_archive_days": 45}'::jsonb, 'مدة الاحتفاظ ببيانات التتبع (GPS) بالأيام')
ON CONFLICT (key) DO UPDATE SET value = COALESCE(system_settings.value, '{}'::jsonb) || '{"tracking_archive_days": 45}'::jsonb;

-- الدالة الشهرية تقرأ نفس الإعداد (بدل 90 الثابتة)، والمهمة الشهرية تنلغي: التنظيف اليومي يكفي
CREATE OR REPLACE FUNCTION public.purge_old_location_tracking()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_days integer;
    v_deleted integer;
BEGIN
    SELECT COALESCE((value ->> 'tracking_archive_days')::int, 45) INTO v_days
    FROM system_settings WHERE key = 'archive_policy';
    v_days := GREATEST(COALESCE(v_days, 45), 35);
    DELETE FROM location_tracking
    WHERE timestamp < (now() - make_interval(days => v_days));
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$function$;

DO $$ BEGIN PERFORM cron.unschedule('monthly_purge_location_tracking'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
