-- =========================================================================
-- الحذف الفعلي لملفات سلة المحذوفات من التخزين
-- =========================================================================
-- perform_daily_cleanup() (03:00 UTC) يرجع قائمة الملفات المنتهية فقط ولا يحذفها
-- من Storage، ودالة daily-cleanup لم تكن تُستدعى من أي مكان، فكانت الملفات تبقى
-- للأبد. هذه المهمة تستدعي الدالة يومياً 03:15 UTC بنفس أسلوب invoke_push_notification.
-- إذا لم تكن الدالة منشورة بعد، الطلب يفشل بهدوء ولا يؤثر على شيء.
--
-- Rollback: SELECT cron.unschedule('daily_trash_storage_cleanup');
-- =========================================================================
DO $$
BEGIN
  PERFORM cron.unschedule('daily_trash_storage_cleanup');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'daily_trash_storage_cleanup',
  '15 3 * * *',
  $job$
  SELECT net.http_post(
    url := 'https://jgjlmddphhncatrhqrej.supabase.co/functions/v1/daily-cleanup',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb
  );
  $job$
);
