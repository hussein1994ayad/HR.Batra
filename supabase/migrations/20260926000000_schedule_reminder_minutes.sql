-- =========================================================================
-- عمود "التذكير بعد" لجداول الدوام
-- =========================================================================
-- دالة التذكيرات (20260922000000) تقرأ reminder_minutes_after من الجدول،
-- لكن العمود لم يكن موجوداً فكانت تستعمل 5 دقائق دائماً، وشاشة أوقات عمل
-- الأفرع في التطبيق تعرض الإعداد بدون أن تحفظه. إضافة فقط — لا حذف.
-- =========================================================================

ALTER TABLE work_schedules
  ADD COLUMN IF NOT EXISTS reminder_minutes_after INTEGER NOT NULL DEFAULT 5;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_schedules_reminder_minutes'
  ) THEN
    ALTER TABLE work_schedules
      ADD CONSTRAINT chk_work_schedules_reminder_minutes
      CHECK (reminder_minutes_after BETWEEN 0 AND 120);
  END IF;
END $$;

COMMENT ON COLUMN work_schedules.reminder_minutes_after IS
  'دقائق بعد بداية/نهاية الدوام قبل إرسال تذكير البصمة (افتراضي 5)';
