-- =====================================================================
-- المرحلة 6 من إصلاحات تدقيق 14/10/2026: الموقع والملفات.
-- (BUG-008) حذف الموظف نهائياً كان يخلي مستمسكاته وصورته بالتخزين للأبد ← تروح للسلة 30 يوم وبعدها تنحذف.
-- (BUG-009) تعديل المستمسكات (الموقع والتطبيق) كان يحذف الملفات من التخزين قبل ما ينحفظ التعديل ←
--   القاعدة نفسها تحط الملف المشال بالسلة بس بعد ما ينحفظ السطر (trash_removed_employee_files).
-- (BUG-010) رقم الموظف كان عشوائي (EMP-1000 لحد 9999) ويتكرر ← تسلسل بالسيرفر (EMP-003، EMP-004...).
-- (BUG-019) دالة daily-cleanup كانت مفتوحة لأي أحد ← تشتغل بس بكود مؤقت تصدره المهمة المجدولة بكل تشغيلة.
-- (CODE-005) تعديل الموظف، إنهاء خدماته، استرجاعه، وإتلافه: كل عملية بخطوة وحدة بالسيرفر (يا كلشي يا ولا شي).
--   ومعها تصليح: خيار «أرشفة» بالموقع كان يكتب نوع 'archive' والقاعدة تقبل 'archived' بس، فيعطل الموظف ويفشل بنص الطريق.
-- ما يتغير أي مبلغ.
-- =====================================================================

-- ---------------------------------------------------------------------
-- (BUG-008، BUG-009) الملف اللي يشيله التعديل (أو الحذف النهائي) يروح للسلة بعد ما ينحفظ التعديل
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trash_removed_employee_files()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
BEGIN
  FOR r IN
    -- مستمسكات انشالت من القائمة
    SELECT 'employee-documents' AS bucket, 'document' AS kind, substring(u FROM '/employee-documents/([^?#]+)') AS path
    FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(OLD.document_urls) = 'array' THEN OLD.document_urls ELSE '[]'::jsonb END) u
    WHERE NOT (CASE WHEN jsonb_typeof(NEW.document_urls) = 'array' THEN NEW.document_urls ELSE '[]'::jsonb END) ? u
    UNION ALL
    -- الصورة الشخصية انشالت (الحذف النهائي). تبديل الصورة يتكفل بيه التطبيق نفسه
    SELECT 'avatars', 'avatar', substring(OLD.avatar_url FROM '/avatars/([^?#]+)')
    WHERE OLD.avatar_url IS NOT NULL AND NEW.avatar_url IS NULL
  LOOP
    CONTINUE WHEN r.path IS NULL;
    -- بس الملف الموجود فعلاً، ومو بالسلة من قبل
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = r.bucket AND o.name = r.path);
    CONTINUE WHEN EXISTS (SELECT 1 FROM deleted_files d WHERE d.file_path = r.path AND d.restored_at IS NULL);
    INSERT INTO deleted_files (file_path, file_type, related_table, related_id, deleted_by, scheduled_deletion_date, file_size_bytes)
    SELECT r.path, r.kind, 'employees', NEW.id::text, auth.uid(), now() + interval '30 days',
           NULLIF(o.metadata ->> 'size', '')::bigint
    FROM storage.objects o WHERE o.bucket_id = r.bucket AND o.name = r.path
    LIMIT 1;
  END LOOP;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.trash_removed_employee_files() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_trash_removed_employee_files ON public.employees;
CREATE TRIGGER trg_trash_removed_employee_files AFTER UPDATE OF document_urls, avatar_url ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.trash_removed_employee_files();

-- ---------------------------------------------------------------------
-- (BUG-010) رقم الموظف بالتسلسل إذا ما انكتب رقم
-- ---------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS public.employee_code_seq;
SELECT setval('public.employee_code_seq',
              GREATEST(COALESCE((SELECT max(substring(employee_code FROM '^EMP-(\d{1,9})$')::bigint) FROM public.employees), 0), 1),
              (SELECT count(*) > 0 FROM public.employees WHERE employee_code ~ '^EMP-\d{1,9}$'));

CREATE OR REPLACE FUNCTION public.next_employee_code()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_code text;
BEGIN
  LOOP
    v_code := 'EMP-' || lpad(nextval('public.employee_code_seq')::text, 3, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM employees WHERE employee_code = v_code);
  END LOOP;
  RETURN v_code;
END;
$function$;
REVOKE ALL ON FUNCTION public.next_employee_code() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.assign_employee_code()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.employee_code IS NULL OR btrim(NEW.employee_code) = '' THEN
    NEW.employee_code := public.next_employee_code();
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION public.assign_employee_code() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_assign_employee_code ON public.employees;
CREATE TRIGGER trg_assign_employee_code BEFORE INSERT ON public.employees
  FOR EACH ROW EXECUTE FUNCTION public.assign_employee_code();

-- ---------------------------------------------------------------------
-- (CODE-005) تعديل الموظف: الإيميل وكلمة السر والهاتف وباقي البيانات بخطوة وحدة
-- p_changes: الحقول اللي تتغير بس (full_name, role, branch_id, department_id, join_date, document_urls,
-- monthly_salary_iqd, future_salary_iqd, future_salary_month)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_employee(p_employee_id uuid, p_email text, p_password text, p_phone text, p_changes jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_unknown text;
  c jsonb := COALESCE(p_changes, '{}'::jsonb);
BEGIN
  PERFORM public.require_admin();
  IF NOT EXISTS (SELECT 1 FROM employees WHERE id = p_employee_id) THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  SELECT string_agg(k, '، ') INTO v_unknown
  FROM jsonb_object_keys(c) k
  WHERE k NOT IN ('full_name', 'role', 'branch_id', 'department_id', 'join_date', 'document_urls',
                  'monthly_salary_iqd', 'future_salary_iqd', 'future_salary_month');
  IF v_unknown IS NOT NULL THEN
    RAISE EXCEPTION 'حقل ما ينحفظ من هنا: %', v_unknown USING ERRCODE = '22023';
  END IF;

  PERFORM public.update_employee_credentials(p_employee_id, p_email, p_password, p_phone);

  UPDATE employees e SET
    full_name = CASE WHEN c ? 'full_name' THEN c ->> 'full_name' ELSE e.full_name END,
    role = CASE WHEN c ? 'role' THEN c ->> 'role' ELSE e.role END,
    branch_id = CASE WHEN c ? 'branch_id' THEN NULLIF(c ->> 'branch_id', '')::uuid ELSE e.branch_id END,
    department_id = CASE WHEN c ? 'department_id' THEN NULLIF(c ->> 'department_id', '')::uuid ELSE e.department_id END,
    join_date = CASE WHEN c ? 'join_date' THEN NULLIF(c ->> 'join_date', '')::date ELSE e.join_date END,
    document_urls = CASE WHEN c ? 'document_urls' THEN COALESCE(c -> 'document_urls', '[]'::jsonb) ELSE e.document_urls END,
    monthly_salary_iqd = CASE WHEN c ? 'monthly_salary_iqd' THEN COALESCE((c ->> 'monthly_salary_iqd')::numeric, 0) ELSE e.monthly_salary_iqd END,
    future_salary_iqd = CASE WHEN c ? 'future_salary_iqd' THEN (c ->> 'future_salary_iqd')::numeric ELSE e.future_salary_iqd END,
    future_salary_month = CASE WHEN c ? 'future_salary_month' THEN NULLIF(c ->> 'future_salary_month', '') ELSE e.future_salary_month END
  WHERE e.id = p_employee_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.save_employee(uuid, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_employee(uuid, text, text, text, jsonb) TO authenticated;

-- ---------------------------------------------------------------------
-- (CODE-005) إنهاء الخدمات: آخر يوم + تعطيل (أو حذف فوري) + سجل الأرشيف، بخطوة وحدة
-- p_type: archive | scheduled (حذف بعد 30 يوم) | immediate (حذف فوري)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.end_employee_service(p_employee_id uuid, p_type text, p_reason text DEFAULT NULL, p_last_day date DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp employees%ROWTYPE;
  v_kind text := CASE p_type WHEN 'archive' THEN 'archived' WHEN 'scheduled' THEN 'scheduled_deletion' WHEN 'immediate' THEN 'permanent' END;
BEGIN
  PERFORM public.require_admin();
  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'نوع الإجراء غير معروف.' USING ERRCODE = '22023';
  END IF;
  IF p_employee_id = auth.uid() THEN
    RAISE EXCEPTION 'ما تكدر تنهي خدماتك بنفسك.' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الموظف غير موجود.' USING ERRCODE = 'P0002';
  END IF;

  -- آخر يوم عمل فعلي يحدد آخر راتب (بدونه = اليوم)
  UPDATE employees SET is_active = false, termination_date = COALESCE(p_last_day, termination_date) WHERE id = p_employee_id;

  INSERT INTO archived_employees (employee_id, employee_code, full_name, archive_type, archive_reason, scheduled_deletion_date, archived_by, archived_at)
  VALUES (p_employee_id, v_emp.employee_code, v_emp.full_name, v_kind,
          COALESCE(NULLIF(btrim(p_reason), ''),
                   CASE p_type WHEN 'immediate' THEN 'حذف فوري نهائي من لوحة التحكم'
                               WHEN 'scheduled' THEN 'حذف مجدول بعد 30 يوماً من لوحة التحكم'
                               ELSE 'أرشفة وتعطيل الحساب الإداري للموظف' END),
          CASE WHEN p_type = 'scheduled' THEN now() + interval '30 days' END,
          auth.uid(), now());

  IF p_type = 'immediate' THEN
    -- إخفاء الهوية وحذف حساب الدخول (المستمسكات والصورة تروح للسلة)
    PERFORM public.safe_delete_employee(p_employee_id);
  END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.end_employee_service(uuid, text, text, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.end_employee_service(uuid, text, text, date) TO authenticated;

-- ---------------------------------------------------------------------
-- (CODE-005) استرجاع موظف من الأرشيف بتاريخ رجوعه، بخطوة وحدة
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.restore_archived_employee(p_archive_id uuid, p_return_date date DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  a archived_employees%ROWTYPE;
  v_result jsonb := jsonb_build_object('gap_days', 0, 'warnings', '[]'::jsonb);
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO a FROM archived_employees WHERE id = p_archive_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'سجل الأرشيف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF a.archive_type = 'permanent' THEN
    RAISE EXCEPTION 'هذا الموظف انحذف نهائياً وما يرجع.' USING ERRCODE = '55000';
  END IF;
  IF EXISTS (SELECT 1 FROM employees WHERE id = a.employee_id AND NOT is_active) THEN
    v_result := public.reactivate_employee(a.employee_id, p_return_date);
  END IF;
  DELETE FROM archived_employees WHERE id = p_archive_id;
  RETURN v_result;
END;
$function$;
REVOKE ALL ON FUNCTION public.restore_archived_employee(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.restore_archived_employee(uuid, date) TO authenticated;

-- ---------------------------------------------------------------------
-- (CODE-005) إتلاف موظف مؤرشف نهائياً، بخطوة وحدة
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.destroy_archived_employee(p_archive_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  a archived_employees%ROWTYPE;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO a FROM archived_employees WHERE id = p_archive_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'سجل الأرشيف غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF EXISTS (SELECT 1 FROM employees WHERE id = a.employee_id) THEN
    PERFORM public.safe_delete_employee(a.employee_id);
  END IF;
  UPDATE archived_employees
  SET archive_type = 'permanent', notes = 'تم الإتلاف النهائي اليدوي للبيانات والحساب من قبل المسؤول.'
  WHERE id = p_archive_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.destroy_archived_employee(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.destroy_archived_employee(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- (BUG-019) daily-cleanup: كود مؤقت لكل تشغيلة من المهمة المجدولة (ماكو كلمة سر تنحفظ بمكان)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cleanup_run_tokens (
  token uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.cleanup_run_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cleanup_run_tokens FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.issue_cleanup_token()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_token uuid;
BEGIN
  DELETE FROM cleanup_run_tokens WHERE created_at < now() - interval '1 day';
  INSERT INTO cleanup_run_tokens DEFAULT VALUES RETURNING token INTO v_token;
  RETURN v_token;
END;
$function$;
REVOKE ALL ON FUNCTION public.issue_cleanup_token() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('daily_trash_storage_cleanup', '15 3 * * *', $cron$
  SELECT net.http_post(
    url := 'https://jgjlmddphhncatrhqrej.supabase.co/functions/v1/daily-cleanup',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cleanup-token', public.issue_cleanup_token()::text),
    body := '{}'::jsonb
  );
$cron$);
