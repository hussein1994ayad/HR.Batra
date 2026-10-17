-- =========================================================================
-- إشعار "طلب سلفة جديد" للأدمن فقط
-- =========================================================================
-- كان يوصل لمدراء الفروع هم، وهم ما يگدرون يعتمدون السلف (approve_loan للأدمن فقط).
-- الدالة منسوخة من القاعدة الحية؛ التغيير الوحيد شرط الدور.
-- =========================================================================
CREATE OR REPLACE FUNCTION public.notify_admins_of_new_loan_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

    v_amount_str := to_char(NEW.amount, 'FM999G999G999') || ' د.ع';

    INSERT INTO notifications (employee_id, title, body, type)
    SELECT
        e.id,
        '💰 طلب سلفة جديد بانتظار الموافقة',
        format(
            'قدّم %s طلب سلفة بمبلغ %s على %s قسط — يرجى المراجعة.',
            COALESCE(v_employee_name, 'موظف'),
            v_amount_str,
            COALESCE(NEW.installment_count::TEXT, '—')
        ),
        'loan'
    FROM employees e
    -- مدير الفرع ما يعتمد سلف (للأدمن فقط)، فما يستلم إشعار طلبات السلف
    WHERE e.role = 'admin'
      AND e.is_active = true
      AND e.id != NEW.employee_id;

    RETURN NEW;
END;
$function$;
