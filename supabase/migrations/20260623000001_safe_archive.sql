-- =========================================================================
-- نظام HR Pro - أرشفة ذكية وحماية البيانات المالية
-- يوفر نظام أرشفة آمن يحذف بيانات الحضور القديمة بعد اعتماد جميع الرواتب
-- =========================================================================

-- 1. جدول الأشهر المؤرشفة
CREATE TABLE IF NOT EXISTS archived_months (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    work_month TEXT NOT NULL UNIQUE, -- مثل '2026-01'
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    archived_by UUID REFERENCES employees(id) ON DELETE SET NULL,
    attendance_deleted INTEGER DEFAULT 0, -- عدد سجلات الحضور المحذوفة
    bd_deleted INTEGER DEFAULT 0, -- عدد سجلات المكافآت/الخصومات المحذوفة
    notifications_deleted INTEGER DEFAULT 0 -- عدد الإشعارات المحذوفة
);

COMMENT ON TABLE archived_months IS 'سجل الأشهر المؤرشفة التي تم تنظيف بياناتها التفصيلية بأمان بعد اعتماد جميع الرواتب';

-- 2. تمكين RLS
ALTER TABLE archived_months ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_users_archived_months" ON archived_months
    FOR ALL USING (auth.role() = 'authenticated');

-- 3. دالة الأرشفة الذكية الآمنة
CREATE OR REPLACE FUNCTION safe_archive_payroll_month(
    target_month TEXT,
    cycle_start_day INT DEFAULT 25,
    cycle_end_day INT DEFAULT 24
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_year INT;
    v_month INT;
    v_active_emp_count INT;
    v_slips_count INT;
    v_unpaid_installments INT;
    v_latest_slip_date TIMESTAMP;
    v_days_since_latest INT;
    v_att_deleted INT;
    v_bd_deleted INT;
    v_notif_deleted INT;
    v_already_archived BOOLEAN;
    v_missing_employees TEXT[];
BEGIN
    -- فحص 0: هل الشهر مؤرشف مسبقاً؟
    SELECT EXISTS(SELECT 1 FROM archived_months WHERE work_month = target_month) INTO v_already_archived;
    IF v_already_archived THEN
        RETURN json_build_object(
            'success', false,
            'error', 'هذا الشهر مؤرشف مسبقاً ولا يمكن أرشفته مرة أخرى.'
        );
    END IF;

    -- حساب فترة الدورة المالية (مثل 25 من الشهر السابق إلى 24 من الشهر الحالي)
    v_year := SPLIT_PART(target_month, '-', 1)::INT;
    v_month := SPLIT_PART(target_month, '-', 2)::INT;

    -- تاريخ البداية: cycle_start_day من الشهر السابق
    IF v_month = 1 THEN
        v_start_date := MAKE_DATE(v_year - 1, 12, cycle_start_day);
    ELSE
        v_start_date := MAKE_DATE(v_year, v_month - 1, cycle_start_day);
    END IF;

    -- تاريخ النهاية: cycle_end_day من الشهر الحالي
    v_end_date := MAKE_DATE(v_year, v_month, cycle_end_day);

    -- فحص 1: هل كل الموظفين النشطين عندهم كشف راتب معتمد؟
    SELECT COUNT(*) INTO v_active_emp_count
    FROM employees WHERE is_active = true;

    SELECT COUNT(*) INTO v_slips_count
    FROM salary_slips WHERE work_month = target_month;

    IF v_slips_count < v_active_emp_count THEN
        -- جمع أسماء الموظفين الذين بدون راتب معتمد
        SELECT ARRAY_AGG(e.full_name) INTO v_missing_employees
        FROM employees e
        WHERE e.is_active = true
            AND NOT EXISTS (
                SELECT 1 FROM salary_slips ss
                WHERE ss.employee_id = e.id AND ss.work_month = target_month
            );

        RETURN json_build_object(
            'success', false,
            'error', 'لا يمكن الأرشفة: يوجد ' || (v_active_emp_count - v_slips_count) || ' موظف بدون راتب معتمد لهذا الشهر.',
            'missing_employees', v_missing_employees
        );
    END IF;

    -- فحص 2: هل مرّت 60 يوم على الأقل من آخر اعتماد؟
    SELECT MAX(created_at) INTO v_latest_slip_date
    FROM salary_slips WHERE work_month = target_month;

    v_days_since_latest := EXTRACT(DAY FROM (NOW() - v_latest_slip_date));

    IF v_days_since_latest < 60 THEN
        RETURN json_build_object(
            'success', false,
            'error', 'لا يمكن الأرشفة بعد: لم تمر 60 يوماً من آخر اعتماد راتب لهذا الشهر (مرّ ' || v_days_since_latest || ' يوم فقط). يمكن الأرشفة بعد ' || (60 - v_days_since_latest) || ' يوم.'
        );
    END IF;

    -- فحص 3: لا توجد أقساط سلف غير مدفوعة ضمن الفترة
    SELECT COUNT(*) INTO v_unpaid_installments
    FROM loan_installments li
    JOIN loans l ON li.loan_id = l.id
    WHERE li.due_date >= v_start_date
        AND li.due_date <= v_end_date
        AND li.is_paid = false
        AND l.status = 'approved';

    IF v_unpaid_installments > 0 THEN
        RETURN json_build_object(
            'success', false,
            'error', 'لا يمكن الأرشفة: يوجد ' || v_unpaid_installments || ' قسط سلفة غير مدفوع ضمن هذه الفترة. يرجى اعتماد الرواتب أو سداد الأقساط أولاً.'
        );
    END IF;

    -- ✅ كل الفحوصات نجحت — بدء الأرشفة الآمنة

    -- حذف سجلات الحضور التفصيلية للفترة
    DELETE FROM attendance
    WHERE work_date >= v_start_date AND work_date <= v_end_date;
    GET DIAGNOSTICS v_att_deleted = ROW_COUNT;

    -- حذف سجلات المكافآت والخصومات للفترة (الأرقام النهائية محفوظة بـ salary_slips)
    DELETE FROM bonuses_deductions
    WHERE issue_date >= v_start_date AND issue_date <= v_end_date;
    GET DIAGNOSTICS v_bd_deleted = ROW_COUNT;

    -- حذف الإشعارات القديمة (أكثر من 90 يوم)
    DELETE FROM notifications
    WHERE created_at < NOW() - INTERVAL '90 days';
    GET DIAGNOSTICS v_notif_deleted = ROW_COUNT;

    -- تسجيل الشهر كمؤرشف
    INSERT INTO archived_months (work_month, attendance_deleted, bd_deleted, notifications_deleted)
    VALUES (target_month, v_att_deleted, v_bd_deleted, v_notif_deleted);

    RETURN json_build_object(
        'success', true,
        'message', 'تم أرشفة شهر ' || target_month || ' بنجاح! 📦',
        'attendance_deleted', v_att_deleted,
        'bd_deleted', v_bd_deleted,
        'notifications_deleted', v_notif_deleted
    );
END;
$$;

COMMENT ON FUNCTION safe_archive_payroll_month IS 'أرشفة ذكية وآمنة لشهر مالي معتمد — تحذف بيانات الحضور والخصومات التفصيلية بعد فحوصات أمنية متعددة';

-- 4. تحديث دالة التنظيف اليومي لتشمل تنظيف الإشعارات القديمة تلقائياً
CREATE OR REPLACE FUNCTION public.perform_daily_cleanup()
RETURNS TABLE (expired_file_path TEXT, expired_bucket_id TEXT, file_record_id UUID) AS $$
DECLARE
  archive_record RECORD;
  tracking_archive_days INT;
BEGIN
  -- 1. الحصول على مدة أرشفة التتبع من إعدادات النظام (الافتراضي 180 يوماً / 6 أشهر)
  SELECT COALESCE((value->>'tracking_archive_days')::INT, 180) INTO tracking_archive_days
  FROM system_settings WHERE key = 'archive_policy';

  -- 2. حذف بيانات التتبع والموقع القديمة التي تجاوزت فترة الأرشفة
  DELETE FROM location_tracking WHERE timestamp < (NOW() - (tracking_archive_days || ' days')::INTERVAL);
  DELETE FROM tracked_stops WHERE start_time < (NOW() - (tracking_archive_days || ' days')::INTERVAL);
  DELETE FROM geofence_violations WHERE timestamp < (NOW() - (tracking_archive_days || ' days')::INTERVAL);

  -- 3. تنظيف الإشعارات القديمة تلقائياً
  -- حذف الإشعارات المقروءة التي مر عليها أكثر من 30 يوم
  DELETE FROM notifications WHERE is_read = true AND created_at < (NOW() - INTERVAL '30 days');
  -- حذف كل الإشعارات التي مر عليها أكثر من 90 يوم
  DELETE FROM notifications WHERE created_at < (NOW() - INTERVAL '90 days');

  -- 4. إرسال إشعارات التنبيه للأدمن عن موظف مجدول للحذف قبل الحذف بأسبوع
  INSERT INTO notifications (employee_id, title, body, type, is_read, created_at)
  SELECT 
    COALESCE(archived_by, (SELECT id FROM employees WHERE role = 'admin' LIMIT 1)),
    'تنبيه: حذف مجدول لموظف خلال أسبوع',
    'تنبيه: سيتم حذف بيانات الموظف (' || full_name || ') نهائياً وبشكل كامل في تاريخ ' || TO_CHAR(scheduled_deletion_date, 'YYYY-MM-DD') || '.',
    'system',
    false,
    NOW()
  FROM archived_employees
  WHERE archive_type = 'scheduled_deletion' 
    AND scheduled_deletion_date BETWEEN NOW() AND NOW() + INTERVAL '7 days'
    -- تجنب تكرار الإشعار يومياً
    AND NOT EXISTS (
      SELECT 1 FROM notifications 
      WHERE notifications.employee_id = COALESCE(archived_employees.archived_by, (SELECT id FROM employees WHERE role = 'admin' LIMIT 1))
        AND notifications.title = 'تنبيه: حذف مجدول لموظف خلال أسبوع'
        AND notifications.created_at > NOW() - INTERVAL '1 day'
    );

  -- 5. معالجة الحذف المجدول للموظفين المؤرشفين الذين تجاوزوا التاريخ المحدد
  FOR archive_record IN 
    SELECT employee_id, full_name FROM archived_employees 
    WHERE archive_type = 'scheduled_deletion' AND scheduled_deletion_date <= NOW()
  LOOP
    -- حذف الموظف نهائياً من قاعدة البيانات (تلقائياً يحذف متعلقاته بسبب CASCADE)
    DELETE FROM employees WHERE id = archive_record.employee_id;
    
    -- تحديث حالة الأرشيف ليصبح حذفاً مكتملاً
    UPDATE archived_employees 
    SET 
      archive_type = 'permanent', 
      notes = COALESCE(notes, '') || ' - تم التنفيذ التلقائي للحذف المجدول بتاريخ ' || TO_CHAR(NOW(), 'YYYY-MM-DD') || '.'
    WHERE employee_id = archive_record.employee_id;
  END LOOP;

  -- 6. إرجاع قائمة الملفات المنتهية في سلة المحذوفات (تجاوزت 30 يوماً) ليتم حذفها من Storage
  RETURN QUERY 
  SELECT 
    df.file_path as expired_file_path, 
    CASE 
      WHEN df.file_type = 'avatar' THEN 'avatars'::TEXT
      WHEN df.file_type = 'document' THEN 'documents'::TEXT
      WHEN df.file_type = 'pledge' THEN 'loan-pledges'::TEXT
      WHEN df.file_type = 'logo' THEN 'company-logos'::TEXT
      ELSE 'documents'::TEXT
    END as expired_bucket_id,
    df.id as file_record_id
  FROM deleted_files df
  WHERE df.scheduled_deletion_date <= NOW() AND df.restored_at IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
