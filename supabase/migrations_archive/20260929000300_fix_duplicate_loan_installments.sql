-- =====================================================================
-- إصلاح: أقساط سلفة مكررة بنفس الشهر
--
-- تريجر إعادة توزيع الأقساط (update_loan_and_installments_trigger) إذا اشتغل
-- مرتين بنفس اللحظة (تعديلان متزامنان على أقساط نفس السلفة)، كل نسخة ترى نفس
-- "آخر تاريخ استحقاق" فتولّد نفس الأشهر مرة ثانية: قسطان بكل شهر.
-- (سلفة 10,000,000 على الحي: 12 قسطاً متبقياً كل اثنين بنفس الشهر.)
--
-- 1) التريجر يقفل صف السلفة أولاً (FOR UPDATE) فتتسلسل التعديلات المتزامنة.
-- 2) الأقساط غير المسددة المكررة تُعاد لأشهر متتالية تبدأ من أول قسط متبقٍ،
--    ثم يُعاد توزيع المبالغ (قسط ثابت والأخير يأخذ الباقي). المجموع لا يتغير.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.update_loan_and_installments_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_loan_id UUID;
    v_loan_amount NUMERIC;
    v_default_installment_amount NUMERIC;
    v_total_paid NUMERIC;
    v_new_remaining NUMERIC;
    v_unpaid_count INT;
    v_unpaid_record RECORD;
    v_allocated_so_far NUMERIC;
    v_alloc NUMERIC;
    v_last_due_date DATE;
    v_counter INT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_loan_id := OLD.loan_id;
    ELSE
        v_loan_id := NEW.loan_id;
    END IF;

    IF pg_trigger_depth() = 1 THEN
        -- قفل السلفة: تعديلان متزامنان لا يولّدان نفس الأشهر مرتين
        SELECT amount, installment_amount INTO v_loan_amount, v_default_installment_amount
        FROM public.loans
        WHERE id = v_loan_id
        FOR UPDATE;

        IF FOUND THEN
            SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
            FROM public.loan_installments
            WHERE loan_id = v_loan_id AND is_paid = true;

            v_new_remaining := v_loan_amount - v_total_paid;
            IF v_new_remaining < 0 THEN
                v_new_remaining := 0;
            END IF;

            UPDATE public.loans
            SET remaining_amount = v_new_remaining
            WHERE id = v_loan_id;

            IF v_new_remaining <= 0 THEN
                DELETE FROM public.loan_installments
                WHERE loan_id = v_loan_id AND is_paid = false;
            ELSE
                SELECT COUNT(*) INTO v_unpaid_count
                FROM public.loan_installments
                WHERE loan_id = v_loan_id AND is_paid = false;

                v_allocated_so_far := 0;
                v_counter := 0;

                FOR v_unpaid_record IN
                    SELECT id, amount
                    FROM public.loan_installments
                    WHERE loan_id = v_loan_id AND is_paid = false
                    ORDER BY due_date ASC, id ASC
                LOOP
                    v_counter := v_counter + 1;

                    IF v_allocated_so_far < v_new_remaining THEN
                        IF v_counter = v_unpaid_count THEN
                            v_alloc := v_new_remaining - v_allocated_so_far;
                        ELSE
                            v_alloc := LEAST(v_default_installment_amount, v_new_remaining - v_allocated_so_far);
                        END IF;

                        UPDATE public.loan_installments
                        SET amount = v_alloc
                        WHERE id = v_unpaid_record.id;

                        v_allocated_so_far := v_allocated_so_far + v_alloc;
                    ELSE
                        DELETE FROM public.loan_installments
                        WHERE id = v_unpaid_record.id;
                    END IF;
                END LOOP;

                IF v_allocated_so_far < v_new_remaining THEN
                    SELECT COALESCE(MAX(due_date), CURRENT_DATE) INTO v_last_due_date
                    FROM public.loan_installments
                    WHERE loan_id = v_loan_id;

                    WHILE v_allocated_so_far < v_new_remaining LOOP
                        v_last_due_date := v_last_due_date + INTERVAL '1 month';
                        v_alloc := LEAST(v_default_installment_amount, v_new_remaining - v_allocated_so_far);

                        INSERT INTO public.loan_installments (loan_id, due_date, amount, is_paid)
                        VALUES (v_loan_id, v_last_due_date, v_alloc, false);

                        v_allocated_so_far := v_allocated_so_far + v_alloc;
                    END LOOP;
                END IF;
            END IF;
        END IF;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.update_loan_and_installments_trigger() IS
'Trigger function: يحدّث remaining_amount ويعيد توزيع الأقساط غير المسددة. يقفل صف السلفة لمنع التوليد المكرر.';

-- إصلاح البيانات: أقساط غير مسددة بنفس الشهر ← أشهر متتالية
DO $$
DECLARE
  l record;
  r record;
  i int;
  v_start date;
  v_first uuid;
BEGIN
  FOR l IN
    SELECT loan_id FROM loan_installments
    WHERE NOT is_paid
    GROUP BY loan_id
    HAVING count(*) > count(DISTINCT date_trunc('month', due_date))
  LOOP
    SELECT min(due_date) INTO v_start FROM loan_installments WHERE loan_id = l.loan_id AND NOT is_paid;
    i := 0;
    v_first := NULL;
    FOR r IN
      SELECT id FROM loan_installments
      WHERE loan_id = l.loan_id AND NOT is_paid
      ORDER BY due_date, created_at, id
    LOOP
      UPDATE loan_installments SET due_date = (v_start + make_interval(months => i))::date WHERE id = r.id;
      v_first := COALESCE(v_first, r.id);
      i := i + 1;
    END LOOP;
    -- يُشغّل التريجر مرة واحدة: قسط ثابت لكل شهر والأخير يأخذ الباقي
    UPDATE loan_installments SET amount = amount WHERE id = v_first;
  END LOOP;
END $$;
