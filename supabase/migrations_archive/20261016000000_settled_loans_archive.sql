-- =====================================================================
-- السلف المسددة: سجل مالي دائم مختصر قبل حذف السلفة + تنظيف السلف من شاشة التنظيف + «تم تسليم الرواتب».
-- (1) settled_loans: سطر واحد لكل سلفة تسددت (رقم مرجعي، الموظف، المبلغ، كل استقطاع ورواتب يا شهر، تاريخ
--     التسوية، الرصيد صفر). للعرض والإثبات بس — ما يدخل بأي حساب راتب، فما يكرر خصم.
-- (2) السلفة المعتمدة ما تنحذف إلا من الأرشفة، والأرشفة تشترط: مسددة بالكامل + كل كشف خصم منها بمسير مغلق.
--     وكشف راتب بيه قسط سلفة تأرشفت ما ينلغي اعتماده (كان القسط يضيع: السلفة راحت وما يرجع ينخصم).
-- (3) رقم مرجعي لكل سلفة (loan_no).
-- (4)(5)(6) معاينة تنظيف السلف، قائمة المستثنى وسببه، وتقدير المساحة.
-- (9) «تم تسليم الرواتب» لكل مسير مغلق؛ حضور مسير ينحذف بعد ما يتسلّم المسير اللي بعده.
-- الكشوف (salary_slips / salary_slip_lines) ما تنلمس.
-- =====================================================================

-- ---------------------------------------------------------------------
-- (3) رقم مرجعي للسلفة
-- ---------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS public.loan_no_seq;
ALTER TABLE public.loans ADD COLUMN IF NOT EXISTS loan_no bigint;
UPDATE public.loans l SET loan_no = x.n
FROM (SELECT id, row_number() OVER (ORDER BY created_at, id) AS n FROM public.loans WHERE loan_no IS NULL) x
WHERE l.id = x.id AND l.loan_no IS NULL;
SELECT setval('public.loan_no_seq', GREATEST((SELECT COALESCE(max(loan_no), 0) FROM public.loans), 1),
              (SELECT count(*) > 0 FROM public.loans));
-- الرقم يعطيه السيرفر دائماً (trigger) — الموظف يقدّم الطلب بدون صلاحية على التسلسل، وما يكدر يكتب رقم من عنده
CREATE OR REPLACE FUNCTION public.assign_loan_no()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.loan_no := nextval('public.loan_no_seq');
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_assign_loan_no ON public.loans;
CREATE TRIGGER trg_assign_loan_no BEFORE INSERT ON public.loans
  FOR EACH ROW EXECUTE FUNCTION public.assign_loan_no();

-- الرقم المرجعي ما يتغير بعد الإنشاء
CREATE OR REPLACE FUNCTION public.keep_loan_no()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.loan_no := OLD.loan_no;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_keep_loan_no ON public.loans;
CREATE TRIGGER trg_keep_loan_no BEFORE UPDATE OF loan_no ON public.loans
  FOR EACH ROW EXECUTE FUNCTION public.keep_loan_no();

ALTER TABLE public.loans ALTER COLUMN loan_no SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS loans_loan_no_key ON public.loans (loan_no);
COMMENT ON COLUMN public.loans.loan_no IS 'رقم مرجعي للسلفة يطلع للمستخدم (L-0007) ويبقى بسجل السلف المسددة';

-- ---------------------------------------------------------------------
-- (1) سجل السلف المسددة
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.settled_loans (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id         uuid NOT NULL UNIQUE,              -- معرّف السلفة الأصلية (انحذفت)
  loan_no         bigint NOT NULL,
  employee_id     uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  employee_name   text NOT NULL,                     -- نص محفوظ حتى لو انحذف الموظف
  employee_code   text,
  amount          numeric NOT NULL,                  -- المبلغ الأصلي
  total_deducted  numeric NOT NULL,                  -- مجموع المسدد (راتب + نقد)
  final_balance   numeric NOT NULL DEFAULT 0 CHECK (final_balance = 0),
  -- [{due_date, amount, paid_at, method: salary|cash, payroll_month, slip_id, note}]
  installments    jsonb NOT NULL,
  approved_at     timestamptz,
  settled_at      timestamptz NOT NULL,              -- تاريخ آخر تسديد
  archived_by     uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  archived_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS settled_loans_employee_idx ON public.settled_loans (employee_id);
COMMENT ON TABLE public.settled_loans IS 'سجل مالي دائم مختصر للسلف المسددة بعد حذف سجلها التشغيلي (للعرض والإثبات، ما يدخل بحساب الرواتب)';

ALTER TABLE public.settled_loans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS settled_loans_read ON public.settled_loans;
CREATE POLICY settled_loans_read ON public.settled_loans FOR SELECT TO authenticated
  USING (public.is_admin() OR employee_id = auth.uid());
REVOKE ALL ON public.settled_loans FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.settled_loans FROM authenticated;
GRANT SELECT ON public.settled_loans TO authenticated;

-- ---------------------------------------------------------------------
-- (2) ليش هذي السلفة ما تتأرشف هسه (NULL = تتأرشف)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.loan_archive_blocker(p_loan_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  l loans%ROWTYPE;
  v_open text;
BEGIN
  SELECT * INTO l FROM loans WHERE id = p_loan_id;
  IF NOT FOUND THEN RETURN 'السلفة غير موجودة.'; END IF;
  IF l.status <> 'approved' THEN RETURN 'السلفة مو معتمدة (طلب).'; END IF;
  IF COALESCE(l.remaining_amount, 0) > 0 OR EXISTS (SELECT 1 FROM loan_installments WHERE loan_id = l.id AND NOT is_paid) THEN
    RETURN format('عليها باقي %s د.ع.', to_char(COALESCE(l.remaining_amount, 0), 'FM999,999,999'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM loan_installments WHERE loan_id = l.id) THEN
    RETURN 'ما إلها أقساط مسجّلة.';
  END IF;
  -- كشف خصم منها ومسيره بعده مفتوح: ممكن ينلغي اعتماده، ووقتها القسط لازم يرجع غير مسدد
  SELECT min(s.work_month) INTO v_open
  FROM loan_installments li
  JOIN salary_slips s ON s.id = li.paid_by_slip_id
  JOIN payroll_periods pp ON pp.period_month = s.work_month
  WHERE li.loan_id = l.id AND pp.status <> 'closed';
  IF v_open IS NOT NULL THEN
    RETURN format('قسط منها مخصوم براتب مسير %s وهو بعده مفتوح. أغلق المسير أولاً.', v_open);
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.loan_archive_blocker(uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- (1) أرشفة سلفة مسددة: ملخص دائم ثم حذف السلفة وأقساطها — خطوة وحدة
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.archive_settled_loan(p_loan_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  l loans%ROWTYPE;
  v_why text;
  v_emp employees%ROWTYPE;
  v_inst jsonb;
  v_total numeric;
  v_settled timestamptz;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO l FROM loans WHERE id = p_loan_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'السلفة غير موجودة.' USING ERRCODE = 'P0002';
  END IF;
  v_why := public.loan_archive_blocker(p_loan_id);
  IF v_why IS NOT NULL THEN
    RAISE EXCEPTION 'السلفة ما تتأرشف: %', v_why USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_emp FROM employees WHERE id = l.employee_id;
  SELECT jsonb_agg(jsonb_build_object(
           'due_date', li.due_date, 'amount', li.amount, 'paid_at', li.paid_at,
           'method', CASE WHEN li.paid_by_slip_id IS NOT NULL THEN 'salary' ELSE 'cash' END,
           -- رواتب يا شهر: من الكشف إذا انخصم براتب، وإلا شهر الرواتب اللي يتبعه تاريخ القسط
           'payroll_month', COALESCE(s.work_month, public.payroll_month_of(li.due_date)),
           'slip_id', li.paid_by_slip_id, 'note', li.payment_note) ORDER BY li.due_date, li.created_at),
         sum(li.amount), max(li.paid_at)
  INTO v_inst, v_total, v_settled
  FROM loan_installments li LEFT JOIN salary_slips s ON s.id = li.paid_by_slip_id
  WHERE li.loan_id = l.id;

  INSERT INTO settled_loans (loan_id, loan_no, employee_id, employee_name, employee_code, amount, total_deducted, final_balance,
                             installments, approved_at, settled_at, archived_by)
  VALUES (l.id, l.loan_no, l.employee_id, COALESCE(v_emp.full_name, 'موظف محذوف'), v_emp.employee_code, l.amount, v_total, 0,
          v_inst, l.approved_at, COALESCE(v_settled, now()), auth.uid());

  PERFORM set_config('loans.archiving', 'on', true);
  DELETE FROM loans WHERE id = l.id;
  PERFORM set_config('loans.archiving', 'off', true);

  RETURN jsonb_build_object('success', true, 'loan_no', l.loan_no, 'pledge_url', l.pledge_url);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.archive_settled_loan(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.archive_settled_loan(uuid) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- (2) السلفة المعتمدة تنحذف بس من الأرشفة (حتى يبقى سجلها)، والطلبات غير المعتمدة تنحذف عادي
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_loan_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- حذف الموظف نهائياً يمسح سلفه بالتسلسل: وقتها سطر الموظف ما موجود بعد
  IF OLD.status <> 'approved' OR NOT EXISTS (SELECT 1 FROM employees e WHERE e.id = OLD.employee_id) THEN
    RETURN OLD;
  END IF;
  IF COALESCE(OLD.remaining_amount, 0) > 0
     OR EXISTS (SELECT 1 FROM loan_installments li WHERE li.loan_id = OLD.id AND NOT li.is_paid) THEN
    RAISE EXCEPTION 'السلفة بعدها عليها باقي (% د.ع). ما تنحذف إلا بعد تسديدها بالكامل.', to_char(COALESCE(OLD.remaining_amount, 0), 'FM999,999,999')
      USING ERRCODE = '42501';
  END IF;
  IF COALESCE(current_setting('loans.archiving', true), '') <> 'on' THEN
    RAISE EXCEPTION 'السلفة المسددة ما تنحذف مباشرة: استعمل «أرشفة السلفة» حتى ينحفظ سجلها المالي.' USING ERRCODE = '42501';
  END IF;
  RETURN OLD;
END;
$function$;

-- كشف راتب بيه قسط سلفة تأرشفت ما ينلغي اعتماده (القسط ما يرجع غير مسدد لأن السلفة انحذفت)
CREATE OR REPLACE FUNCTION public.guard_slip_with_archived_loan()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_no bigint;
BEGIN
  SELECT s.loan_no INTO v_no
  FROM settled_loans s, jsonb_array_elements(s.installments) i
  WHERE i ->> 'slip_id' = OLD.id::text
  LIMIT 1;
  IF v_no IS NOT NULL AND EXISTS (SELECT 1 FROM employees e WHERE e.id = OLD.employee_id) THEN
    RAISE EXCEPTION 'هذا الكشف بيه قسط من سلفة تأرشفت (L-%). ما ينلغي اعتماده، لأن القسط ما يرجع ينخصم.', lpad(v_no::text, 4, '0')
      USING ERRCODE = '42501';
  END IF;
  RETURN OLD;
END;
$function$;
DROP TRIGGER IF EXISTS trg_guard_slip_with_archived_loan ON public.salary_slips;
CREATE TRIGGER trg_guard_slip_with_archived_loan BEFORE DELETE ON public.salary_slips
  FOR EACH ROW EXECUTE FUNCTION public.guard_slip_with_archived_loan();

-- ---------------------------------------------------------------------
-- (9) «تم تسليم الرواتب» لكل مسير مغلق
-- ---------------------------------------------------------------------
ALTER TABLE public.payroll_periods ADD COLUMN IF NOT EXISTS delivered_at timestamptz;
ALTER TABLE public.payroll_periods ADD COLUMN IF NOT EXISTS delivered_by uuid REFERENCES public.employees(id) ON DELETE SET NULL;
COMMENT ON COLUMN public.payroll_periods.delivered_at IS 'الأدمن أكد إن رواتب هذا المسير تسلّمت للموظفين فعلاً (شرط لتنظيف حضور المسير اللي قبله)';

CREATE OR REPLACE FUNCTION public.mark_payroll_delivered(p_month text, p_delivered boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'هذا الشهر ما إله مسير رواتب.' USING ERRCODE = 'P0002';
  END IF;
  IF COALESCE(p_delivered, true) AND v_p.status <> 'closed' THEN
    RAISE EXCEPTION 'أغلق المسير أولاً، وبعدها أكد التسليم.' USING ERRCODE = '42501';
  END IF;
  UPDATE payroll_periods
  SET delivered_at = CASE WHEN COALESCE(p_delivered, true) THEN COALESCE(delivered_at, now()) END,
      delivered_by = CASE WHEN COALESCE(p_delivered, true) THEN COALESCE(delivered_by, auth.uid()) END
  WHERE period_month = p_month
  RETURNING * INTO v_p;
  RETURN jsonb_build_object('success', true, 'month', p_month, 'delivered_at', v_p.delivered_at);
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.mark_payroll_delivered(text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_payroll_delivered(text, boolean) TO authenticated, service_role;

-- إعادة فتح المسير تمسح علامة التسليم (لازم تنأكد من جديد بعد الإغلاق)
CREATE OR REPLACE FUNCTION public.clear_delivered_on_reopen()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status <> 'closed' THEN
    NEW.delivered_at := NULL;
    NEW.delivered_by := NULL;
  END IF;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_clear_delivered_on_reopen ON public.payroll_periods;
CREATE TRIGGER trg_clear_delivered_on_reopen BEFORE UPDATE ON public.payroll_periods
  FOR EACH ROW EXECUTE FUNCTION public.clear_delivered_on_reopen();

-- ---------------------------------------------------------------------
-- سجل التنظيف: تنظيف السلف ما إله فترة
-- ---------------------------------------------------------------------
ALTER TABLE public.payroll_cleanups ALTER COLUMN start_date DROP NOT NULL;
ALTER TABLE public.payroll_cleanups ALTER COLUMN end_date DROP NOT NULL;
ALTER TABLE public.payroll_cleanups ADD COLUMN IF NOT EXISTS loans_archived integer;
ALTER TABLE public.payroll_cleanups ADD COLUMN IF NOT EXISTS loan_requests_deleted integer;

-- حجم ملف التعهد بالتخزين (0 إذا ما معروف)
CREATE OR REPLACE FUNCTION public._pledge_bytes(p_url text)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_path text := substring(COALESCE(p_url, '') FROM '/loan-pledges/(.+)$');
  v bigint;
BEGIN
  IF v_path IS NULL OR to_regclass('storage.objects') IS NULL THEN RETURN 0; END IF;
  EXECUTE $q$SELECT COALESCE((metadata ->> 'size')::bigint, 0) FROM storage.objects WHERE bucket_id = 'loan-pledges' AND name = $1 LIMIT 1$q$
    INTO v USING split_part(v_path, '?', 1);
  RETURN COALESCE(v, 0);
EXCEPTION WHEN OTHERS THEN
  RETURN 0;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public._pledge_bytes(text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- (7) تنظيف مسير: المعاينة — مع قائمة المستثنى وسببه، تقدير المساحة، وشرط التسليم
--   الحضور: المسير مغلق + المسير اللي بعده مغلق ومؤكد تسليمه + ماكو حركة تنتظر قرار لأيامه.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_cleanup_preview(p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_next payroll_periods%ROWTYPE;
  v_tz text := public.company_timezone();
  v_pending int;
  v_att_done boolean;
  v_trk_done boolean;
  v_ntf_done boolean;
  v_closed boolean;
  v_next_closed boolean;
  v_next_delivered boolean;
  v_labels jsonb := '{"absence":"غياب","late":"تأخير","early_leave":"خروج مبكر","missing_punch":"بصمة ناقصة","overtime":"ساعات إضافية"}';
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'هذا الشهر ما إله مسير رواتب.' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_next FROM payroll_periods WHERE start_date > v_p.cutoff_date ORDER BY start_date LIMIT 1;

  v_closed := v_p.status = 'closed';
  v_next_closed := COALESCE(v_next.status = 'closed', false);
  v_next_delivered := v_next_closed AND v_next.delivered_at IS NOT NULL;
  SELECT count(*) INTO v_pending FROM payroll_events
  WHERE status = 'pending' AND event_date BETWEEN v_p.start_date AND v_p.cutoff_date;
  v_att_done := public.payroll_day_frozen(v_p.start_date) AND public.payroll_day_frozen(v_p.cutoff_date);
  v_trk_done := EXISTS (SELECT 1 FROM payroll_cleanups WHERE period_month = p_month AND tracking_deleted IS NOT NULL);
  v_ntf_done := EXISTS (SELECT 1 FROM payroll_cleanups WHERE period_month = p_month AND notifications_deleted IS NOT NULL);

  RETURN jsonb_build_object(
    'month', p_month, 'start_date', v_p.start_date, 'end_date', v_p.cutoff_date, 'status', v_p.status,
    'delivered_at', v_p.delivered_at,
    'next_month', v_next.period_month, 'next_status', v_next.status, 'next_delivered_at', v_next.delivered_at,
    'checks', jsonb_build_object('closed', v_closed, 'next_closed', v_next_closed, 'next_delivered', v_next_delivered,
                                 'pending_decisions', v_pending),
    -- المستثنى وسببه: الحركات اللي بعدها تنتظر قرار (تمنع حذف الحضور)
    'pending_list', COALESCE((
      SELECT jsonb_agg(x ORDER BY x ->> 'date', x ->> 'employee') FROM (
        SELECT jsonb_build_object('employee', e.full_name, 'date', pe.event_date,
                                  'type', COALESCE(v_labels ->> pe.event_type, pe.event_type), 'amount', pe.amount) AS x
        FROM payroll_events pe JOIN employees e ON e.id = pe.employee_id
        WHERE pe.status = 'pending' AND pe.event_date BETWEEN v_p.start_date AND v_p.cutoff_date
        ORDER BY pe.event_date LIMIT 100) q), '[]'::jsonb),
    'counts', jsonb_build_object(
      'attendance', (SELECT count(*) FROM attendance WHERE work_date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'tracking', (SELECT count(*) FROM location_tracking WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'stops', (SELECT count(*) FROM tracked_stops WHERE (start_time AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'violations', (SELECT count(*) FROM geofence_violations WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'notifications', (SELECT count(*) FROM notifications WHERE (created_at AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date)),
    -- تقدير المساحة (حجم السطور نفسها بدون الفهارس؛ تقريبي)
    'bytes', jsonb_build_object(
      'attendance', (SELECT COALESCE(sum(pg_column_size(a.*)), 0) FROM attendance a WHERE work_date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'tracking', (SELECT COALESCE(sum(pg_column_size(t.*)), 0) FROM location_tracking t WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date)
                + (SELECT COALESCE(sum(pg_column_size(s.*)), 0) FROM tracked_stops s WHERE (start_time AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date)
                + (SELECT COALESCE(sum(pg_column_size(g.*)), 0) FROM geofence_violations g WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date),
      'notifications', (SELECT COALESCE(sum(pg_column_size(n.*)), 0) FROM notifications n WHERE (created_at AT TIME ZONE v_tz)::date BETWEEN v_p.start_date AND v_p.cutoff_date)),
    'done', jsonb_build_object('attendance', v_att_done, 'tracking', v_trk_done, 'notifications', v_ntf_done),
    'can', jsonb_build_object(
      'attendance', v_closed AND v_next_delivered AND v_pending = 0 AND NOT v_att_done,
      'tracking', v_closed,
      'notifications', v_closed),
    'history', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'at', c.performed_at, 'by', (SELECT full_name FROM employees WHERE id = c.performed_by),
               'attendance', c.attendance_deleted, 'tracking', c.tracking_deleted, 'stops', c.stops_deleted,
               'violations', c.violations_deleted, 'notifications', c.notifications_deleted) ORDER BY c.performed_at DESC)
      FROM payroll_cleanups c WHERE c.period_month = p_month), '[]'::jsonb));
END;
$function$;

-- التنفيذ: نفس السابق + شرط التسليم
CREATE OR REPLACE FUNCTION public.payroll_cleanup_run(p_month text, p_attendance boolean DEFAULT false,
                                                      p_tracking boolean DEFAULT false, p_notifications boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v jsonb;
  v_start date;
  v_end date;
  v_tz text := public.company_timezone();
  v_att int;
  v_trk int;
  v_stops int;
  v_viol int;
  v_ntf int;
BEGIN
  PERFORM public.require_admin();
  IF NOT (COALESCE(p_attendance, false) OR COALESCE(p_tracking, false) OR COALESCE(p_notifications, false)) THEN
    RAISE EXCEPTION 'اختار شنو ينحذف: الحضور، التتبع، أو الإشعارات.' USING ERRCODE = '22023';
  END IF;
  -- عمليتين على نفس المسير بنفس اللحظة: الثانية تنتظر الأولى وتشوف نتيجتها
  PERFORM pg_advisory_xact_lock(hashtext('payroll_cleanup_' || p_month));

  v := public.payroll_cleanup_preview(p_month);
  v_start := (v ->> 'start_date')::date;
  v_end := (v ->> 'end_date')::date;

  IF NOT (v -> 'checks' ->> 'closed')::boolean THEN
    RAISE EXCEPTION 'المسير بعده مفتوح. اعتمد الرواتب وأغلق المسير أولاً.' USING ERRCODE = '42501';
  END IF;
  IF p_attendance THEN
    IF (v -> 'done' ->> 'attendance')::boolean THEN
      RAISE EXCEPTION 'حضور هذا المسير منظّف مسبقاً.' USING ERRCODE = '42501';
    END IF;
    IF NOT (v -> 'checks' ->> 'next_closed')::boolean THEN
      RAISE EXCEPTION 'حضور هذا المسير ينحذف بعد ما تعتمد وتغلق رواتب المسير اللي بعده (%).', COALESCE(v ->> 'next_month', 'الجاي')
        USING ERRCODE = '42501';
    END IF;
    IF NOT (v -> 'checks' ->> 'next_delivered')::boolean THEN
      RAISE EXCEPTION 'أكد «تم تسليم الرواتب» للمسير اللي بعده (%) من صفحة الرواتب أولاً.', COALESCE(v ->> 'next_month', 'الجاي')
        USING ERRCODE = '42501';
    END IF;
    IF (v -> 'checks' ->> 'pending_decisions')::int > 0 THEN
      RAISE EXCEPTION 'اكو % حركة (غياب/تأخير) لأيام هذا المسير بعدها تنتظر قرارك. احسمها أولاً.', (v -> 'checks' ->> 'pending_decisions')
        USING ERRCODE = '42501';
    END IF;
    PERFORM set_config('payroll.skip_sync', 'on', true);
    DELETE FROM attendance WHERE work_date BETWEEN v_start AND v_end;
    GET DIAGNOSTICS v_att = ROW_COUNT;
    PERFORM set_config('payroll.skip_sync', 'off', true);
  END IF;

  IF p_tracking THEN
    DELETE FROM location_tracking WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_start AND v_end;
    GET DIAGNOSTICS v_trk = ROW_COUNT;
    DELETE FROM tracked_stops WHERE (start_time AT TIME ZONE v_tz)::date BETWEEN v_start AND v_end;
    GET DIAGNOSTICS v_stops = ROW_COUNT;
    DELETE FROM geofence_violations WHERE ("timestamp" AT TIME ZONE v_tz)::date BETWEEN v_start AND v_end;
    GET DIAGNOSTICS v_viol = ROW_COUNT;
  END IF;

  IF p_notifications THEN
    DELETE FROM notifications WHERE (created_at AT TIME ZONE v_tz)::date BETWEEN v_start AND v_end;
    GET DIAGNOSTICS v_ntf = ROW_COUNT;
  END IF;

  INSERT INTO payroll_cleanups (period_month, start_date, end_date, attendance_deleted, tracking_deleted, stops_deleted,
                                violations_deleted, notifications_deleted, performed_by)
  VALUES (p_month, v_start, v_end, v_att, v_trk, v_stops, v_viol, v_ntf, auth.uid());

  RETURN jsonb_build_object('success', true, 'month', p_month, 'attendance_deleted', v_att, 'tracking_deleted', v_trk,
                            'stops_deleted', v_stops, 'violations_deleted', v_viol, 'notifications_deleted', v_ntf);
END;
$function$;

-- ---------------------------------------------------------------------
-- (4) تنظيف السلف: المعاينة — المسددة المرشحة للأرشفة، المستثناة وسببها، والطلبات المرفوضة/الملغاة القديمة
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.loans_cleanup_preview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  RETURN (
    WITH approved AS (
      SELECT l.id, l.loan_no, e.full_name, l.amount, l.remaining_amount, l.pledge_url, public.loan_archive_blocker(l.id) AS why,
             (SELECT max(paid_at) FROM loan_installments WHERE loan_id = l.id) AS settled_at,
             pg_column_size(l.*) + COALESCE((SELECT sum(pg_column_size(i.*)) FROM loan_installments i WHERE i.loan_id = l.id), 0) AS row_bytes
      FROM loans l JOIN employees e ON e.id = l.employee_id
      WHERE l.status = 'approved'
    ), requests AS (
      SELECT l.id, l.loan_no, e.full_name, l.amount, l.status, l.created_at, l.pledge_url,
             (l.created_at < now() - interval '30 days') AS old_enough, pg_column_size(l.*) AS row_bytes
      FROM loans l JOIN employees e ON e.id = l.employee_id
      WHERE l.status IN ('rejected', 'cancelled')
    )
    SELECT jsonb_build_object(
      'settled', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'loan_no', loan_no, 'employee', full_name, 'amount', amount,
                                     'settled_at', settled_at) ORDER BY loan_no) FROM approved WHERE why IS NULL), '[]'::jsonb),
      'excluded', COALESCE((SELECT jsonb_agg(jsonb_build_object('loan_no', loan_no, 'employee', full_name, 'amount', amount,
                                      'remaining', remaining_amount, 'reason', why) ORDER BY loan_no) FROM approved WHERE why IS NOT NULL), '[]'::jsonb),
      'requests', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', id, 'loan_no', loan_no, 'employee', full_name, 'amount', amount,
                                      'status', status, 'created_at', created_at) ORDER BY loan_no) FROM requests WHERE old_enough), '[]'::jsonb),
      'requests_recent', (SELECT count(*) FROM requests WHERE NOT old_enough),
      'bytes', jsonb_build_object(
        'settled_rows', COALESCE((SELECT sum(row_bytes) FROM approved WHERE why IS NULL), 0),
        'settled_files', COALESCE((SELECT sum(public._pledge_bytes(pledge_url)) FROM approved WHERE why IS NULL), 0),
        'requests_rows', COALESCE((SELECT sum(row_bytes) FROM requests WHERE old_enough), 0),
        'requests_files', COALESCE((SELECT sum(public._pledge_bytes(pledge_url)) FROM requests WHERE old_enough), 0)),
      'archived_total', (SELECT count(*) FROM settled_loans))
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.loans_cleanup_preview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.loans_cleanup_preview() TO authenticated, service_role;

-- التنفيذ: يأرشف كل المسددة المؤهلة ويحذف الطلبات المرفوضة/الملغاة الأقدم من 30 يوم. يرجّع روابط صور التعهد
-- حتى الشاشة تحذفها من التخزين (اللي يبقى يلكطه الفحص الأسبوعي للملفات اليتيمة).
CREATE OR REPLACE FUNCTION public.loans_cleanup_run(p_settled boolean DEFAULT false, p_requests boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  v_archived int;
  v_deleted int;
  v_urls text[] := '{}';
BEGIN
  PERFORM public.require_admin();
  IF NOT (COALESCE(p_settled, false) OR COALESCE(p_requests, false)) THEN
    RAISE EXCEPTION 'اختار شنو يتنظف: السلف المسددة أو الطلبات المرفوضة.' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('loans_cleanup'));

  IF p_settled THEN
    v_archived := 0;
    FOR r IN SELECT id, pledge_url FROM loans WHERE status = 'approved' AND public.loan_archive_blocker(id) IS NULL ORDER BY loan_no LOOP
      PERFORM public.archive_settled_loan(r.id);
      v_archived := v_archived + 1;
      IF COALESCE(r.pledge_url, '') <> '' THEN v_urls := v_urls || r.pledge_url; END IF;
    END LOOP;
  END IF;

  IF p_requests THEN
    v_deleted := 0;
    FOR r IN SELECT id, pledge_url FROM loans WHERE status IN ('rejected', 'cancelled') AND created_at < now() - interval '30 days' LOOP
      DELETE FROM loans WHERE id = r.id;
      v_deleted := v_deleted + 1;
      IF COALESCE(r.pledge_url, '') <> '' THEN v_urls := v_urls || r.pledge_url; END IF;
    END LOOP;
  END IF;

  INSERT INTO payroll_cleanups (period_month, start_date, end_date, loans_archived, loan_requests_deleted, performed_by)
  VALUES (NULL, NULL, NULL, v_archived, v_deleted, auth.uid());

  RETURN jsonb_build_object('success', true, 'loans_archived', v_archived, 'loan_requests_deleted', v_deleted, 'pledge_urls', to_jsonb(v_urls));
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.loans_cleanup_run(boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.loans_cleanup_run(boolean, boolean) TO authenticated, service_role;
