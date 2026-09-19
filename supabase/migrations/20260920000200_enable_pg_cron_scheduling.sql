-- =========================================================================
-- HR Pro v6.0 - pg_cron scheduling for automated maintenance
-- Date: 2026-09-20
-- Related: audit point 28
-- =========================================================================
--
-- What this migration does:
--   • Enables pg_cron extension (Supabase supports it)
--   • Schedules perform_daily_cleanup() to run every day at 03:00 UTC
--   • Schedules a monthly location_tracking purge to keep DB size low
--
-- Rollback:
--   SELECT cron.unschedule('daily_cleanup');
--   SELECT cron.unschedule('monthly_purge_location_tracking');
-- =========================================================================


-- =====================================================================
-- Enable pg_cron (idempotent on Supabase)
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

GRANT USAGE ON SCHEMA cron TO postgres;


-- =====================================================================
-- Schedule 1: daily cleanup at 03:00 UTC (06:00 Baghdad)
-- Runs perform_daily_cleanup() then relies on the Edge Function
-- 'daily-cleanup' to physically delete files from Storage.
-- =====================================================================

-- Unschedule any existing job with this name (idempotent re-runs)
DO $$
BEGIN
    PERFORM cron.unschedule('daily_cleanup');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
    'daily_cleanup',
    '0 3 * * *',
    $$ SELECT public.perform_daily_cleanup(); $$
);


-- =====================================================================
-- Schedule 2: monthly location_tracking purge on the 1st at 04:00 UTC
-- Keeps only last 90 days of GPS points to control DB growth.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.purge_old_location_tracking()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM location_tracking
    WHERE timestamp < (now() - INTERVAL '90 days');
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION public.purge_old_location_tracking() IS
'يحذف نقاط GPS الأقدم من 90 يوماً من location_tracking. يعيد عدد الصفوف المحذوفة.';

DO $$
BEGIN
    PERFORM cron.unschedule('monthly_purge_location_tracking');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
    'monthly_purge_location_tracking',
    '0 4 1 * *',
    $$ SELECT public.purge_old_location_tracking(); $$
);


-- =====================================================================
-- Schedule 3: weekly refresh of orphan-file candidates on Fridays 05:00
-- (Materializes the get_orphan_storage_candidates() result into a table
-- so the admin panel can query it fast.)
-- =====================================================================

CREATE TABLE IF NOT EXISTS orphan_storage_candidates_cache (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bucket_id         TEXT NOT NULL,
    file_path         TEXT NOT NULL,
    file_size         BIGINT,
    last_seen_at      TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);

CREATE OR REPLACE FUNCTION public.refresh_orphan_candidates_cache()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_inserted INTEGER := 0;
BEGIN
    -- Placeholder: implementation depends on the exact shape of
    -- get_orphan_storage_candidates(); wire up when that RPC exists.
    -- For now we just clear the stale cache.
    TRUNCATE orphan_storage_candidates_cache;
    RETURN v_inserted;
END;
$$;

DO $$
BEGIN
    PERFORM cron.unschedule('weekly_orphan_candidates_refresh');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
    'weekly_orphan_candidates_refresh',
    '0 5 * * 5',
    $$ SELECT public.refresh_orphan_candidates_cache(); $$
);
