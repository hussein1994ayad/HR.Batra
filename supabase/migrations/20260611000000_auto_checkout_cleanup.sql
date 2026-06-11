-- ==========================================
-- نظام HR Pro v6.0 - تحديث دالة التنظيف اليومي لإضافة الإغلاق التلقائي للدوام
-- ==========================================

CREATE OR REPLACE FUNCTION perform_daily_cleanup()
RETURNS TABLE (expired_file_path TEXT, expired_bucket_id TEXT, file_record_id UUID) AS $$
DECLARE
  archive_record RECORD;
  tracking_archive_days INT;
BEGIN
  -- 1. الحصول على مدة أرشفة التتبع من إعدادات النظام
  SELECT COALESCE((value->>'tracking_archive_days')::INT, 180) INTO tracking_archive_days
  FROM system_settings WHERE key = 'archive_policy';

  -- 2. حذف بيانات التتبع والموقع القديمة
  DELETE FROM location_tracking WHERE timestamp < (NOW() - (tracking_archive_days || ' days')::INTERVAL);
  DELETE FROM tracked_stops WHERE start_time < (NOW() - (tracking_archive_days || ' days')::INTERVAL);
  DELETE FROM geofence_violations WHERE timestamp < (NOW() - (tracking_archive_days || ' days')::INTERVAL);

  -- 3. إشعارات حذف الموظفين المؤرشفين
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
    AND NOT EXISTS (
      SELECT 1 FROM notifications 
      WHERE notifications.employee_id = COALESCE(archived_employees.archived_by, (SELECT id FROM employees WHERE role = 'admin' LIMIT 1))
        AND notifications.title = 'تنبيه: حذف مجدول لموظف خلال أسبوع'
        AND notifications.created_at > NOW() - INTERVAL '1 day'
    );

  -- 4. معالجة الحذف المجدول
  FOR archive_record IN 
    SELECT employee_id, full_name FROM archived_employees 
    WHERE archive_type = 'scheduled_deletion' AND scheduled_deletion_date <= NOW()
  LOOP
    DELETE FROM employees WHERE id = archive_record.employee_id;
    UPDATE archived_employees 
    SET 
      archive_type = 'permanent', 
      notes = COALESCE(notes, '') || ' - تم التنفيذ التلقائي للحذف المجدول بتاريخ ' || TO_CHAR(NOW(), 'YYYY-MM-DD') || '.'
    WHERE employee_id = archive_record.employee_id;
  END LOOP;

  -- (تم إلغاء الإغلاق التلقائي والعقوبات بناءً على رغبة الإدارة)

  -- 5. إرجاع قائمة الملفات المنتهية في سلة المحذوفات
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

COMMENT ON FUNCTION perform_daily_cleanup IS 'تنظيف الموقع وإرجاع الملفات المنتهية والإغلاق التلقائي للدوامات المفتوحة';
