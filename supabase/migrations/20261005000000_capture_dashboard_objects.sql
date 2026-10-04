-- =====================================================================
-- تسجيل أشياء موجودة بالقاعدة الحية بس ما مكتوبة بأي migration (انعملت يدوياً من لوحة Supabase).
--
-- الهدف: قاعدة جديدة تنبني من الـ migrations تطلع مطابقة للقاعدة الحية. على القاعدة الحية هذا الملف
-- ما يغيّر شي: الأعمدة بـ IF NOT EXISTS، والدوال بنفس تعريفها الحالي حرفياً (من pg_get_functiondef)،
-- والـ triggers ما تنعمل إلا إذا ما موجودة.
--
--  1) geofence_zones: أعمدة الموقع والمضلع اللي تستعملها صفحة "مناطق العمل" بالويب.
--  2) sync_geofence_coordinates: يحوّل المضلع [[lat,lng],...] لشكل coordinates [{lat,lng},...].
--  3) sync_geofences_to_branches: رسم منطقة = فرع بنفس المعرّف (إنشاء/تعديل/حذف) — حتى تنبصم منها.
--  4) invoke_push_notification: كل إشعار ينكتب يرسل push عبر Edge Function "push-notification".
--
-- ما انضاف هنا: الـ event trigger "ensure_rls" (rls_auto_enable) — ميزة من منصة Supabase نفسها (تفعيل RLS
-- تلقائياً للجداول الجديدة)، وإنشاؤه يحتاج صلاحيات المنصة.
-- =====================================================================

-- 1) الأعمدة
ALTER TABLE public.geofence_zones ADD COLUMN IF NOT EXISTS latitude double precision;
ALTER TABLE public.geofence_zones ADD COLUMN IF NOT EXISTS longitude double precision;
ALTER TABLE public.geofence_zones ADD COLUMN IF NOT EXISTS radius_meters integer;
ALTER TABLE public.geofence_zones ADD COLUMN IF NOT EXISTS polygon_coordinates jsonb;

-- 2) و 3) و 4) الدوال — نفس التعريف الحي حرفياً
CREATE OR REPLACE FUNCTION public.sync_geofence_coordinates()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    coord_elem jsonb;
    new_coords jsonb := '[]'::jsonb;
    lat_val double precision;
    lng_val double precision;
BEGIN
    IF NEW.polygon_coordinates IS NOT NULL AND jsonb_array_length(NEW.polygon_coordinates) > 0 THEN
        FOR coord_elem IN SELECT jsonb_array_elements(NEW.polygon_coordinates) LOOP
            IF jsonb_array_length(coord_elem) = 2 THEN
                lat_val := (coord_elem->>0)::double precision;
                lng_val := (coord_elem->>1)::double precision;
                new_coords := new_coords || jsonb_build_object('lat', lat_val, 'lng', lng_val);
            END IF;
        END LOOP;
        NEW.coordinates := new_coords;
    ELSIF NEW.coordinates IS NOT NULL AND jsonb_array_length(NEW.coordinates) > 0 THEN
        FOR coord_elem IN SELECT jsonb_array_elements(NEW.coordinates) LOOP
            IF coord_elem ? 'lat' AND coord_elem ? 'lng' THEN
                lat_val := (coord_elem->>'lat')::double precision;
                lng_val := (coord_elem->>'lng')::double precision;
                new_coords := new_coords || jsonb_build_array(lat_val, lng_val);
            END IF;
        END LOOP;
        NEW.polygon_coordinates := new_coords;
    END IF;
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_geofences_to_branches()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
    INSERT INTO branches (id, name, latitude, longitude, radius_meters, address)
    VALUES (new.id, new.name, COALESCE(new.latitude, 33.3152), COALESCE(new.longitude, 44.3661), COALESCE(new.radius_meters, 150.0), 'موقع عمل مرسوم')
    ON CONFLICT (id) DO UPDATE SET
      name = EXCLUDED.name,
      latitude = EXCLUDED.latitude,
      longitude = EXCLUDED.longitude,
      radius_meters = EXCLUDED.radius_meters;
  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM branches WHERE id = old.id;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.invoke_push_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM net.http_post(
    url := 'https://jgjlmddphhncatrhqrej.supabase.co/functions/v1/push-notification',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := json_build_object('record', row_to_json(NEW))::jsonb
  );
  RETURN NEW;
END;
$function$;

-- الـ triggers — تنعمل بس إذا ما موجودة (على القاعدة الحية موجودة فما يصير شي)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_sync_geofence_coordinates' AND tgrelid = 'public.geofence_zones'::regclass) THEN
    CREATE TRIGGER trg_sync_geofence_coordinates BEFORE INSERT OR UPDATE OF polygon_coordinates, coordinates ON public.geofence_zones
      FOR EACH ROW EXECUTE FUNCTION public.sync_geofence_coordinates();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_sync_geofences_to_branches' AND tgrelid = 'public.geofence_zones'::regclass) THEN
    CREATE TRIGGER trg_sync_geofences_to_branches AFTER INSERT OR DELETE OR UPDATE ON public.geofence_zones
      FOR EACH ROW EXECUTE FUNCTION public.sync_geofences_to_branches();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'on_notification_insert' AND tgrelid = 'public.notifications'::regclass) THEN
    CREATE TRIGGER on_notification_insert AFTER INSERT ON public.notifications
      FOR EACH ROW EXECUTE FUNCTION public.invoke_push_notification();
  END IF;
END;
$$;
