-- =========================================================================
-- HR Pro v6.0 — خصم رصيد الإجازات تلقائياً + إشعارات القرار بدون تكرار
-- Date: 2026-09-24
-- =========================================================================
--
-- 1. رصيد الإجازات (leave_balances.annual_used / sick_used) لم يكن يُحدَّث
--    بأي مكان. الآن Trigger يزيده عند الموافقة ويُرجعه عند إلغاء الموافقة
--    أو حذف الطلب. الأيام = أيام تقويمية بتوقيت الشركة (الإجازة الساعية لا تُخصم).
-- 2. كل موظف يحصل على سطر رصيد تلقائياً (كان التطبيق يحاول إنشاءه وRLS يرفض).
-- 3. إشعار القرار (موافقة/رفض) يُرسل من Trigger فقط — لوحة الويب كانت ترسل
--    نسخة ثانية فيصل الإشعار مرتين. سبب الرفض يُحفظ في rejection_reason
--    (كان trigger الإجازة يعرض سبب الموظف نفسه كسبب للرفض).
-- =========================================================================


-- =====================================================================
-- 1) عدد أيام الإجازة
-- =====================================================================

CREATE OR REPLACE FUNCTION public.leave_request_days(lr leave_requests)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN lr.is_hourly THEN 0
    ELSE GREATEST(1,
      (lr.end_date AT TIME ZONE public.company_timezone())::date
      - (lr.start_date AT TIME ZONE public.company_timezone())::date + 1)
  END;
$$;


-- =====================================================================
-- 2) Trigger: تحديث الرصيد عند تغيّر حالة الطلب
-- =====================================================================

CREATE OR REPLACE FUNCTION public.apply_leave_balance_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_counted boolean := false;
  v_new_counted boolean := false;
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    v_old_counted := OLD.status = 'approved' AND OLD.leave_type IN ('annual', 'sick');
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    v_new_counted := NEW.status = 'approved' AND NEW.leave_type IN ('annual', 'sick');
  END IF;

  -- إرجاع الأيام القديمة
  IF v_old_counted THEN
    UPDATE leave_balances
    SET annual_used = CASE WHEN OLD.leave_type = 'annual'
                           THEN GREATEST(0, annual_used - public.leave_request_days(OLD))
                           ELSE annual_used END,
        sick_used   = CASE WHEN OLD.leave_type = 'sick'
                           THEN GREATEST(0, sick_used - public.leave_request_days(OLD))
                           ELSE sick_used END,
        updated_at  = now()
    WHERE employee_id = OLD.employee_id;
  END IF;

  -- خصم الأيام الجديدة
  IF v_new_counted THEN
    INSERT INTO leave_balances (employee_id) VALUES (NEW.employee_id)
    ON CONFLICT (employee_id) DO NOTHING;

    UPDATE leave_balances
    SET annual_used = annual_used + CASE WHEN NEW.leave_type = 'annual'
                                         THEN public.leave_request_days(NEW) ELSE 0 END,
        sick_used   = sick_used + CASE WHEN NEW.leave_type = 'sick'
                                       THEN public.leave_request_days(NEW) ELSE 0 END,
        updated_at  = now()
    WHERE employee_id = NEW.employee_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_apply_leave_balance_change ON leave_requests;
CREATE TRIGGER trg_apply_leave_balance_change
  AFTER INSERT OR DELETE OR UPDATE OF status, leave_type, start_date, end_date, is_hourly
  ON leave_requests
  FOR EACH ROW EXECUTE FUNCTION public.apply_leave_balance_change();


-- =====================================================================
-- 3) سطر رصيد لكل موظف
-- =====================================================================

CREATE OR REPLACE FUNCTION public.create_default_leave_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO leave_balances (employee_id) VALUES (NEW.id)
  ON CONFLICT (employee_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_default_leave_balance ON employees;
CREATE TRIGGER trg_create_default_leave_balance
  AFTER INSERT ON employees
  FOR EACH ROW EXECUTE FUNCTION public.create_default_leave_balance();

INSERT INTO leave_balances (employee_id)
SELECT id FROM employees
ON CONFLICT (employee_id) DO NOTHING;

-- مزامنة لمرة واحدة: الإجازات الموافق عليها سابقاً لم تُخصم أبداً.
-- GREATEST يحافظ على أي قيمة أعلى أدخلها الأدمن يدوياً.
UPDATE leave_balances lb
SET annual_used = GREATEST(lb.annual_used, t.annual_days),
    sick_used   = GREATEST(lb.sick_used, t.sick_days),
    updated_at  = now()
FROM (
  SELECT employee_id,
         COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE leave_type = 'annual'), 0) AS annual_days,
         COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE leave_type = 'sick'), 0)   AS sick_days
  FROM leave_requests lr
  WHERE status = 'approved'
    AND date_part('year', start_date AT TIME ZONE public.company_timezone())
        = date_part('year', now() AT TIME ZONE public.company_timezone())
  GROUP BY employee_id
) t
WHERE t.employee_id = lb.employee_id;


-- =====================================================================
-- 4) إشعارات القرار — المصدر الوحيد (الويب والتطبيق لم يعودا يرسلانها)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.notify_employee_on_leave_decision()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected') THEN
        INSERT INTO notifications (employee_id, title, body, type)
        VALUES (
            NEW.employee_id,
            CASE NEW.status
                WHEN 'approved' THEN '✅ تمت الموافقة على طلب الإجازة'
                ELSE '❌ تم رفض طلب الإجازة'
            END,
            CASE NEW.status
                WHEN 'approved' THEN 'طلب الإجازة الذي قدّمته حصل على الموافقة الرسمية. رحلة سعيدة!'
                ELSE COALESCE(
                    'طلب الإجازة الذي قدّمته لم يتم اعتماده. السبب: ' || NULLIF(btrim(NEW.rejection_reason), ''),
                    'طلب الإجازة الذي قدّمته لم يتم اعتماده. راجع إدارة الموارد البشرية للتفاصيل.'
                )
            END,
            'leave'
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_employee_on_loan_decision()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected') THEN
        INSERT INTO notifications (employee_id, title, body, type)
        VALUES (
            NEW.employee_id,
            CASE NEW.status
                WHEN 'approved' THEN '✅ تمت الموافقة على طلب السلفة'
                ELSE '❌ تم رفض طلب السلفة'
            END,
            CASE NEW.status
                WHEN 'approved' THEN format(
                    'تم اعتماد سلفتك بقيمة %s د.ع على %s قسط شهري (القسط %s د.ع).',
                    to_char(NEW.amount, 'FM999,999,999,990'),
                    NEW.installment_count,
                    to_char(NEW.installment_amount, 'FM999,999,999,990'))
                ELSE COALESCE(
                    'طلب السلفة لم يتم اعتماده. السبب: ' || NULLIF(btrim(NEW.rejection_reason), ''),
                    'طلب السلفة الذي قدّمته لم يتم اعتماده. راجع إدارة الموارد البشرية.'
                )
            END,
            'loan'
        );
    END IF;
    RETURN NEW;
END;
$$;

-- الـ Triggers نفسها معرّفة في 20260920000300؛ نعيد ربطها لضمان وجودها
DROP TRIGGER IF EXISTS trg_notify_employee_leave_decision ON leave_requests;
CREATE TRIGGER trg_notify_employee_leave_decision
    AFTER UPDATE ON leave_requests
    FOR EACH ROW EXECUTE FUNCTION public.notify_employee_on_leave_decision();

DROP TRIGGER IF EXISTS trg_notify_employee_loan_decision ON loans;
CREATE TRIGGER trg_notify_employee_loan_decision
    AFTER UPDATE ON loans
    FOR EACH ROW EXECUTE FUNCTION public.notify_employee_on_loan_decision();


REVOKE EXECUTE ON FUNCTION public.leave_request_days(leave_requests) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.leave_request_days(leave_requests) TO authenticated, service_role;
