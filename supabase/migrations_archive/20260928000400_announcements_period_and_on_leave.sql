-- =====================================================================
-- التعاميم: مدة عرض + جمهور مستهدف، و"المجازون الآن"
--
-- قبل: التعميم يُرسل كإشعار للمستهدفين، لكن يُحفظ في لوحة التطبيق للجميع
-- (حتى لو كان لفرع واحد) ويبقى للأبد.
-- الآن:
--   • starts_at / ends_at: يظهر من تاريخ لتاريخ ثم يختفي تلقائياً.
--   • target_branch_id / target_employee_ids: كل موظف يرى ما يخصه فقط.
--   • publish_announcement(): حفظ التعميم + إشعار المستهدفين في خطوة واحدة.
--   • get_active_announcements(): التعاميم السارية الآن لهذا الموظف.
--   • get_on_leave_now(): من هو مجاز الآن (يومية تشمل اليوم، أو زمنية اليوم
--     لم تنتهِ ساعتها) — الاسم والصورة والفرع فقط، بدون نوع الإجازة أو سببها.
-- =====================================================================

ALTER TABLE public.announcements
  ADD COLUMN IF NOT EXISTS starts_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS ends_at timestamptz,
  ADD COLUMN IF NOT EXISTS target_branch_id uuid REFERENCES public.branches(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS target_employee_ids uuid[];

UPDATE public.announcements SET starts_at = created_at WHERE starts_at > created_at;
-- التعاميم القديمة كانت بلا نهاية: تظهر أسبوعاً من نشرها ثم تختفي
UPDATE public.announcements SET ends_at = starts_at + interval '7 days' WHERE ends_at IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_announcements_period') THEN
    ALTER TABLE public.announcements
      ADD CONSTRAINT chk_announcements_period CHECK (ends_at IS NULL OR ends_at > starts_at);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_announcements_period ON public.announcements (starts_at, ends_at);

COMMENT ON COLUMN public.announcements.starts_at IS 'بداية ظهور التعميم في التطبيق';
COMMENT ON COLUMN public.announcements.ends_at IS 'نهاية ظهور التعميم (فارغ = بدون نهاية)';
COMMENT ON COLUMN public.announcements.target_branch_id IS 'تعميم لفرع معيّن (فارغ مع target_employee_ids فارغ = للجميع)';
COMMENT ON COLUMN public.announcements.target_employee_ids IS 'تعميم لموظفين محددين';

-- هل التعميم يخص هذا الموظف؟
CREATE OR REPLACE FUNCTION public.announcement_targets(a announcements, p_employee_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN a.target_employee_ids IS NOT NULL AND cardinality(a.target_employee_ids) > 0
      THEN p_employee_id = ANY (a.target_employee_ids)
    WHEN a.target_branch_id IS NOT NULL
      THEN EXISTS (SELECT 1 FROM employees e WHERE e.id = p_employee_id AND e.branch_id = a.target_branch_id)
    WHEN a.target_department_id IS NOT NULL
      THEN EXISTS (SELECT 1 FROM employees e WHERE e.id = p_employee_id AND e.department_id = a.target_department_id)
    ELSE true
  END;
$$;
REVOKE EXECUTE ON FUNCTION public.announcement_targets(announcements, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.announcement_targets(announcements, uuid) TO authenticated, service_role;

-- الموظف يقرأ ما يخصه فقط (كانت القراءة مفتوحة لكل التعاميم)
DROP POLICY IF EXISTS "Anyone authenticated can view announcements" ON public.announcements;
DROP POLICY IF EXISTS "Employees view announcements addressed to them" ON public.announcements;
CREATE POLICY "Employees view announcements addressed to them"
  ON public.announcements FOR SELECT TO authenticated
  USING (public.is_admin() OR public.is_manager() OR public.announcement_targets(announcements, auth.uid()));


-- ---------------------------------------------------------------------
-- نشر تعميم (الأدمن والمدير)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.publish_announcement(
  p_title text,
  p_content text,
  p_starts_at timestamptz DEFAULT NULL,
  p_ends_at timestamptz DEFAULT NULL,
  p_target text DEFAULT 'all',
  p_branch_id uuid DEFAULT NULL,
  p_employee_ids uuid[] DEFAULT NULL,
  p_pinned boolean DEFAULT false
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ann announcements%ROWTYPE;
  v_starts timestamptz := COALESCE(p_starts_at, now());
  v_count integer;
  v_period text;
BEGIN
  PERFORM public.require_admin_or_manager();

  IF COALESCE(btrim(p_title), '') = '' OR COALESCE(btrim(p_content), '') = '' THEN
    RAISE EXCEPTION 'اكتب عنوان التعميم ونصه.' USING ERRCODE = '22023';
  END IF;
  IF p_ends_at IS NOT NULL AND p_ends_at <= v_starts THEN
    RAISE EXCEPTION 'تاريخ انتهاء التعميم يجب أن يكون بعد تاريخ بدايته.' USING ERRCODE = '22023';
  END IF;
  IF p_ends_at IS NOT NULL AND p_ends_at <= now() THEN
    RAISE EXCEPTION 'تاريخ انتهاء التعميم مضى.' USING ERRCODE = '22023';
  END IF;
  IF p_target = 'branch' AND p_branch_id IS NULL THEN
    RAISE EXCEPTION 'اختر الفرع المستهدف.' USING ERRCODE = '22023';
  END IF;
  IF p_target = 'employees' AND COALESCE(cardinality(p_employee_ids), 0) = 0 THEN
    RAISE EXCEPTION 'اختر موظفاً واحداً على الأقل.' USING ERRCODE = '22023';
  END IF;

  INSERT INTO announcements (title, content, is_pinned, created_by, starts_at, ends_at, target_branch_id, target_employee_ids)
  VALUES (btrim(p_title), btrim(p_content), COALESCE(p_pinned, false), auth.uid(), v_starts, p_ends_at,
          CASE WHEN p_target = 'branch' THEN p_branch_id END,
          CASE WHEN p_target = 'employees' THEN p_employee_ids END)
  RETURNING * INTO v_ann;

  v_period := CASE
    WHEN p_ends_at IS NULL THEN ''
    ELSE format(' (ساري حتى %s)', to_char(p_ends_at AT TIME ZONE public.company_timezone(), 'YYYY-MM-DD'))
  END;

  INSERT INTO notifications (employee_id, title, body, type, is_read)
  SELECT e.id, '📢 ' || v_ann.title, v_ann.content || v_period, 'system', false
  FROM employees e
  WHERE e.is_active AND public.announcement_targets(v_ann, e.id);
  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN v_count;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.publish_announcement(text, text, timestamptz, timestamptz, text, uuid, uuid[], boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.publish_announcement(text, text, timestamptz, timestamptz, text, uuid, uuid[], boolean) TO authenticated, service_role;


-- ---------------------------------------------------------------------
-- التعاميم السارية الآن لهذا الموظف
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_active_announcements(p_limit integer DEFAULT 20)
RETURNS SETOF announcements
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.*
  FROM announcements a
  WHERE auth.uid() IS NOT NULL
    AND a.starts_at <= now()
    AND (a.ends_at IS NULL OR a.ends_at > now())
    AND public.announcement_targets(a, auth.uid())
  ORDER BY a.is_pinned DESC, a.starts_at DESC
  LIMIT GREATEST(COALESCE(p_limit, 20), 1);
$$;
REVOKE EXECUTE ON FUNCTION public.get_active_announcements(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_active_announcements(integer) TO authenticated, service_role;


-- ---------------------------------------------------------------------
-- المجازون الآن
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_on_leave_now()
RETURNS TABLE (
  employee_id uuid,
  full_name text,
  avatar_url text,
  branch_name text,
  is_hourly boolean,
  from_date date,
  to_date date,
  start_hour time,
  end_hour time
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tz text := public.company_timezone();
  v_local timestamp := now() AT TIME ZONE public.company_timezone();
  v_today date := v_local::date;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT DISTINCT ON (e.id)
    e.id, e.full_name, e.avatar_url, b.name,
    COALESCE(lr.is_hourly, false),
    (lr.start_date AT TIME ZONE v_tz)::date,
    (lr.end_date AT TIME ZONE v_tz)::date,
    lr.start_hour, lr.end_hour
  FROM leave_requests lr
  JOIN employees e ON e.id = lr.employee_id AND e.is_active
  LEFT JOIN branches b ON b.id = e.branch_id
  WHERE lr.status = 'approved'
    AND v_today BETWEEN (lr.start_date AT TIME ZONE v_tz)::date AND (lr.end_date AT TIME ZONE v_tz)::date
    AND (
      NOT COALESCE(lr.is_hourly, false)
      -- الزمنية تظهر طوال يومها حتى تنتهي ساعتها
      OR COALESCE(lr.end_hour, (lr.end_date AT TIME ZONE v_tz)::time) > v_local::time
    )
  ORDER BY e.id, COALESCE(lr.is_hourly, false), e.full_name;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.get_on_leave_now() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_on_leave_now() TO authenticated, service_role;
