-- =========================================================================
-- HR Pro v6.0 - Auto-notify admins/managers on new leave/loan requests
-- Date: 2026-09-20
-- =========================================================================
--
-- Problem being fixed:
--   Admin never gets a phone notification when an employee submits a new
--   leave request or loan request. The push-notification Edge Function
--   only fires when a row is inserted into public.notifications — but
--   nothing was creating those rows for the admin/manager audience.
--
-- Solution:
--   Two AFTER INSERT triggers that fan out one notification row per
--   admin/manager for every new pending leave_request or loan.
--   Once inserted, the existing webhook + FCM function pushes them.
-- =========================================================================


-- =====================================================================
-- Function: notify_admins_of_new_leave_request()
-- =====================================================================
CREATE OR REPLACE FUNCTION public.notify_admins_of_new_leave_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_employee_name  TEXT;
    v_leave_type_ar  TEXT;
    v_days_count     INTEGER;
BEGIN
    -- Only for newly-created PENDING requests
    IF NEW.status != 'pending' THEN
        RETURN NEW;
    END IF;

    -- Employee name for the notification body
    SELECT full_name INTO v_employee_name
    FROM employees
    WHERE id = NEW.employee_id;

    -- Arabic label for leave type
    v_leave_type_ar := CASE NEW.leave_type
        WHEN 'annual'    THEN 'سنوية'
        WHEN 'sick'      THEN 'مرضية'
        WHEN 'emergency' THEN 'طارئة'
        WHEN 'maternity' THEN 'أمومة'
        ELSE                  'أخرى'
    END;

    -- Number of days requested (rounded)
    v_days_count := GREATEST(1, (NEW.end_date::DATE - NEW.start_date::DATE) + 1);

    -- Insert one notification per admin/manager
    INSERT INTO notifications (employee_id, title, body, type)
    SELECT
        e.id,
        '📋 طلب إجازة جديد بانتظار الموافقة',
        format(
            'قدّم %s طلب إجازة %s لمدة %s يوم — يرجى المراجعة والاعتماد.',
            COALESCE(v_employee_name, 'موظف'),
            v_leave_type_ar,
            v_days_count
        ),
        'leave'
    FROM employees e
    WHERE e.role IN ('admin', 'manager')
      AND e.is_active = true
      AND e.id != NEW.employee_id;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_admins_of_new_leave_request() IS
'ينشئ إشعارات للمدراء والأدمنز فور إدراج طلب إجازة جديد. مربوط بـ trigger AFTER INSERT.';

DROP TRIGGER IF EXISTS trg_notify_admins_new_leave_request ON leave_requests;
CREATE TRIGGER trg_notify_admins_new_leave_request
    AFTER INSERT ON leave_requests
    FOR EACH ROW EXECUTE FUNCTION notify_admins_of_new_leave_request();


-- =====================================================================
-- Function: notify_admins_of_new_loan_request()
-- =====================================================================
CREATE OR REPLACE FUNCTION public.notify_admins_of_new_loan_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_employee_name  TEXT;
    v_amount_str     TEXT;
BEGIN
    IF NEW.status != 'pending' THEN
        RETURN NEW;
    END IF;

    SELECT full_name INTO v_employee_name
    FROM employees
    WHERE id = NEW.employee_id;

    -- Format the amount with thousand separators (dots) + د.ع
    v_amount_str := to_char(NEW.amount, 'FM999G999G999') || ' د.ع';

    INSERT INTO notifications (employee_id, title, body, type)
    SELECT
        e.id,
        '💰 طلب سلفة جديد بانتظار الموافقة',
        format(
            'قدّم %s طلب سلفة بمبلغ %s على %s قسط — يرجى المراجعة.',
            COALESCE(v_employee_name, 'موظف'),
            v_amount_str,
            COALESCE(NEW.installments::TEXT, '—')
        ),
        'loan'
    FROM employees e
    WHERE e.role IN ('admin', 'manager')
      AND e.is_active = true
      AND e.id != NEW.employee_id;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.notify_admins_of_new_loan_request() IS
'ينشئ إشعارات للمدراء والأدمنز فور إدراج طلب سلفة جديد. مربوط بـ trigger AFTER INSERT.';

DROP TRIGGER IF EXISTS trg_notify_admins_new_loan_request ON loans;
CREATE TRIGGER trg_notify_admins_new_loan_request
    AFTER INSERT ON loans
    FOR EACH ROW EXECUTE FUNCTION notify_admins_of_new_loan_request();


-- =====================================================================
-- Bonus: notify the requesting employee when their request is decided
-- =====================================================================
CREATE OR REPLACE FUNCTION public.notify_employee_on_leave_decision()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only when status transitions from pending to something decisive
    IF OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected') THEN
        INSERT INTO notifications (employee_id, title, body, type)
        VALUES (
            NEW.employee_id,
            CASE NEW.status
                WHEN 'approved' THEN '✅ تمت الموافقة على طلب الإجازة'
                WHEN 'rejected' THEN '❌ تم رفض طلب الإجازة'
            END,
            CASE NEW.status
                WHEN 'approved' THEN 'طلب الإجازة الذي قدّمته حصل على الموافقة الرسمية. رحلة سعيدة!'
                WHEN 'rejected' THEN COALESCE(
                    'طلب الإجازة الذي قدّمته لم يتم اعتماده. السبب: ' || NULLIF(NEW.reason, ''),
                    'طلب الإجازة الذي قدّمته لم يتم اعتماده. راجع إدارة الموارد البشرية للتفاصيل.'
                )
            END,
            'leave'
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_employee_leave_decision ON leave_requests;
CREATE TRIGGER trg_notify_employee_leave_decision
    AFTER UPDATE ON leave_requests
    FOR EACH ROW EXECUTE FUNCTION notify_employee_on_leave_decision();


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
                WHEN 'rejected' THEN '❌ تم رفض طلب السلفة'
            END,
            CASE NEW.status
                WHEN 'approved' THEN 'طلب السلفة الذي قدّمته حصل على الموافقة. سيتم توفير المبلغ حسب سياسة الشركة.'
                WHEN 'rejected' THEN COALESCE(
                    'طلب السلفة لم يتم اعتماده. السبب: ' || NULLIF(NEW.rejection_reason, ''),
                    'طلب السلفة الذي قدّمته لم يتم اعتماده. راجع إدارة الموارد البشرية.'
                )
            END,
            'loan'
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_employee_loan_decision ON loans;
CREATE TRIGGER trg_notify_employee_loan_decision
    AFTER UPDATE ON loans
    FOR EACH ROW EXECUTE FUNCTION notify_employee_on_loan_decision();
