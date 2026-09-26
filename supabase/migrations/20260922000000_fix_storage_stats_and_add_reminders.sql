-- =========================================================================
-- HR Pro v6.0 - إصلاحان مهمان (2026-09-22)
-- =========================================================================
--
-- إصلاح 1: تذكير بصمة الدخول والخروج
--   المشكلة: الإعداد موجود في جدول work_schedules (reminder_minutes_after)
--            لكن ما فيه أي job يستخدمه ليرسل تذكير فعلي!
--   الحل: pg_cron job يشتغل كل دقيقة يفحص كل الموظفين ويرسل تذكير:
--           • قبل موعد بداية الدوام بـ 15 دقيقة → "الدوام يبدأ قريباً"
--           • بعد موعد بداية الدوام بـ reminder_minutes_after → "لم تسجل حضورك"
--           • قبل موعد نهاية الدوام بـ 15 دقيقة → "الدوام سينتهي قريباً"
--           • بعد موعد نهاية الدوام بـ reminder_minutes_after → "لم تسجل انصرافك"
--         يستخدم dedup key لمنع تكرار الإشعار في نفس اليوم
--
-- إصلاح 2: get_storage_stats يعيد صفر لأن metadata->>'size' قد يكون NULL
--   المشكلة: بعض الملفات ما فيها حقل size في metadata
--   الحل: نستخدم COALESCE مع عدة مصادر + نضيف عدد الملفات لكل bucket
-- =========================================================================


-- =====================================================================
-- إصلاح 2 (بالأول لأنه أسهل): get_storage_stats المحسّنة
-- =====================================================================

DROP FUNCTION IF EXISTS public.get_storage_stats();

CREATE OR REPLACE FUNCTION public.get_storage_stats()
RETURNS TABLE (
    bucket_name  TEXT,
    total_size   BIGINT,
    file_count   BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.id::TEXT AS bucket_name,
        COALESCE(SUM(
            COALESCE(
                (o.metadata->>'size')::BIGINT,
                (o.metadata->>'contentLength')::BIGINT,
                (o.user_metadata->>'size')::BIGINT,
                0
            )
        ), 0)::BIGINT AS total_size,
        COUNT(o.id)::BIGINT AS file_count
    FROM storage.buckets b
    LEFT JOIN storage.objects o ON o.bucket_id = b.id
    GROUP BY b.id
    ORDER BY b.id;
END;
$$;

COMMENT ON FUNCTION public.get_storage_stats() IS
'إحصائيات تخزين موثوقة: حجم بايت + عدد ملفات لكل bucket. تستعمل عدة مفاتيح احتياطية في metadata.';


-- =====================================================================
-- إصلاح 1: نظام تذكيرات الدوام
-- =====================================================================

-- Function: يفحص كل الموظفين النشطين ويرسل التذكيرات المطلوبة
CREATE OR REPLACE FUNCTION public.check_and_send_attendance_reminders()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_emp                RECORD;
    v_schedule           RECORD;
    v_now                TIMESTAMP WITH TIME ZONE := timezone('Asia/Baghdad', now());
    v_now_time           TIME := v_now::TIME;
    v_now_dow            INTEGER := EXTRACT(DOW FROM v_now)::INTEGER;
    v_today              DATE := v_now::DATE;
    v_attendance         RECORD;
    v_reminder_minutes   INTEGER;
    v_check_in_time      TIME;
    v_check_out_time     TIME;
    v_reminder_key       TEXT;
    v_notifications_sent INTEGER := 0;
BEGIN
    -- نفحص كل موظف نشط
    FOR v_emp IN
        SELECT id, full_name, branch_id, department_id
        FROM employees
        WHERE is_active = true
    LOOP
        -- ابحث عن أول work_schedule يطابق الموظف أو قسمه أو فرعه
        SELECT * INTO v_schedule
        FROM work_schedules
        WHERE (employee_id = v_emp.id)
           OR (v_emp.department_id IS NOT NULL AND department_id = v_emp.department_id)
           OR (v_emp.branch_id IS NOT NULL AND employee_id IS NULL AND department_id IS NULL)
        ORDER BY
            (CASE WHEN employee_id = v_emp.id THEN 1
                  WHEN department_id = v_emp.department_id THEN 2
                  ELSE 3 END)
        LIMIT 1;

        IF v_schedule IS NULL THEN CONTINUE; END IF;

        -- هل اليوم من أيام الدوام؟
        IF NOT (v_schedule.work_days @> ARRAY[v_now_dow]::INTEGER[]) THEN
            CONTINUE;
        END IF;

        v_check_in_time  := v_schedule.check_in_time;
        v_check_out_time := v_schedule.check_out_time;
        v_reminder_minutes := COALESCE(
            (v_schedule::JSONB->>'reminder_minutes_after')::INTEGER, 5
        );

        -- سجل الحضور اليومي
        SELECT * INTO v_attendance
        FROM attendance
        WHERE employee_id = v_emp.id AND work_date = v_today;

        -- ================================================================
        -- تذكير 1: قبل بداية الدوام بـ 15 دقيقة
        -- ================================================================
        IF v_attendance IS NULL AND
           v_now_time BETWEEN (v_check_in_time - INTERVAL '15 minutes')::TIME
                          AND (v_check_in_time - INTERVAL '13 minutes')::TIME
        THEN
            v_reminder_key := 'checkin_soon_' || v_today::TEXT;
            IF NOT EXISTS (
                SELECT 1 FROM notifications
                WHERE employee_id = v_emp.id
                  AND type = 'attendance'
                  AND body LIKE '%' || v_reminder_key || '%'
                  AND created_at >= v_today::TIMESTAMP
            ) THEN
                INSERT INTO notifications (employee_id, title, body, type)
                VALUES (
                    v_emp.id,
                    '⏰ الدوام يبدأ خلال 15 دقيقة',
                    'مرحباً ' || v_emp.full_name || '، دوامك يبدأ الساعة '
                    || TO_CHAR(v_check_in_time, 'HH12:MI AM') || '. لا تنسَ تسجيل حضورك. ['
                    || v_reminder_key || ']',
                    'attendance'
                );
                v_notifications_sent := v_notifications_sent + 1;
            END IF;
        END IF;

        -- ================================================================
        -- تذكير 2: بعد بداية الدوام بـ reminder_minutes_after (لم يسجل حضور)
        -- ================================================================
        IF (v_attendance IS NULL OR v_attendance.check_in_time IS NULL) AND
           v_now_time BETWEEN (v_check_in_time + (v_reminder_minutes || ' minutes')::INTERVAL)::TIME
                          AND (v_check_in_time + ((v_reminder_minutes + 2) || ' minutes')::INTERVAL)::TIME
        THEN
            v_reminder_key := 'checkin_late_' || v_today::TEXT;
            IF NOT EXISTS (
                SELECT 1 FROM notifications
                WHERE employee_id = v_emp.id
                  AND type = 'attendance'
                  AND body LIKE '%' || v_reminder_key || '%'
                  AND created_at >= v_today::TIMESTAMP
            ) THEN
                INSERT INTO notifications (employee_id, title, body, type)
                VALUES (
                    v_emp.id,
                    '⚠️ تذكير: لم تسجّل الحضور بعد',
                    'لم يتم رصد تسجيل حضورك اليوم. الوقت الرسمي كان '
                    || TO_CHAR(v_check_in_time, 'HH12:MI AM') || '. يرجى المبادرة بتسجيل الحضور. ['
                    || v_reminder_key || ']',
                    'attendance'
                );
                v_notifications_sent := v_notifications_sent + 1;
            END IF;
        END IF;

        -- ================================================================
        -- تذكير 3: قبل نهاية الدوام بـ 15 دقيقة
        -- ================================================================
        IF v_attendance IS NOT NULL AND v_attendance.check_in_time IS NOT NULL
           AND v_attendance.check_out_time IS NULL
           AND v_now_time BETWEEN (v_check_out_time - INTERVAL '15 minutes')::TIME
                              AND (v_check_out_time - INTERVAL '13 minutes')::TIME
        THEN
            v_reminder_key := 'checkout_soon_' || v_today::TEXT;
            IF NOT EXISTS (
                SELECT 1 FROM notifications
                WHERE employee_id = v_emp.id
                  AND type = 'attendance'
                  AND body LIKE '%' || v_reminder_key || '%'
                  AND created_at >= v_today::TIMESTAMP
            ) THEN
                INSERT INTO notifications (employee_id, title, body, type)
                VALUES (
                    v_emp.id,
                    '🔔 الدوام سينتهي خلال 15 دقيقة',
                    'ينتهي دوامك الساعة ' || TO_CHAR(v_check_out_time, 'HH12:MI AM')
                    || '. جهّز نفسك لتسجيل الانصراف. [' || v_reminder_key || ']',
                    'attendance'
                );
                v_notifications_sent := v_notifications_sent + 1;
            END IF;
        END IF;

        -- ================================================================
        -- تذكير 4: بعد نهاية الدوام (لم يسجل انصراف)
        -- ================================================================
        IF v_attendance IS NOT NULL AND v_attendance.check_in_time IS NOT NULL
           AND v_attendance.check_out_time IS NULL
           AND v_now_time BETWEEN (v_check_out_time + (v_reminder_minutes || ' minutes')::INTERVAL)::TIME
                              AND (v_check_out_time + ((v_reminder_minutes + 2) || ' minutes')::INTERVAL)::TIME
        THEN
            v_reminder_key := 'checkout_late_' || v_today::TEXT;
            IF NOT EXISTS (
                SELECT 1 FROM notifications
                WHERE employee_id = v_emp.id
                  AND type = 'attendance'
                  AND body LIKE '%' || v_reminder_key || '%'
                  AND created_at >= v_today::TIMESTAMP
            ) THEN
                INSERT INTO notifications (employee_id, title, body, type)
                VALUES (
                    v_emp.id,
                    '⚠️ تذكير: لم تسجّل الانصراف',
                    'انتهى دوامك الساعة ' || TO_CHAR(v_check_out_time, 'HH12:MI AM')
                    || '. يرجى تسجيل الانصراف قبل مغادرة الفرع. ['
                    || v_reminder_key || ']',
                    'attendance'
                );
                v_notifications_sent := v_notifications_sent + 1;
            END IF;
        END IF;

    END LOOP;

    RETURN v_notifications_sent;
END;
$$;

COMMENT ON FUNCTION public.check_and_send_attendance_reminders() IS
'يفحص كل الموظفين النشطين ويرسل تذكيرات حضور/انصراف حسب work_schedule. يستدعى كل دقيقة من pg_cron.';


-- =====================================================================
-- pg_cron schedule: كل دقيقة
-- =====================================================================
DO $$
BEGIN
    PERFORM cron.unschedule('attendance_reminders_every_minute');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
    'attendance_reminders_every_minute',
    '* * * * *',  -- كل دقيقة
    $$ SELECT public.check_and_send_attendance_reminders(); $$
);
