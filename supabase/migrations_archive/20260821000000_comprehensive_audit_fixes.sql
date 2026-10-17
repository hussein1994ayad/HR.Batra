-- =========================================================================
-- نظام HR Pro v6.0 - ملف الهجرة الشامل للتدقيق والإصلاح (Comprehensive Audit Fixes)
-- Date: 2026-08-21
-- =========================================================================

-- 1. إضافة قيود التحقق الرياضي على جدول السلف لمنع المبالغ الصفرية أو السالبة
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_loans_positive_amounts'
  ) THEN
    ALTER TABLE public.loans
      ADD CONSTRAINT chk_loans_positive_amounts 
      CHECK (amount > 0 AND installment_count > 0 AND installment_amount > 0 AND remaining_amount >= 0);
  END IF;
END $$;

-- 2. تصحيح تريجر معالجة السلف والأقساط update_loan_and_installments_trigger لمنع تراكم فروقات الكسور
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
    -- الحصول على معرف السلفة
    IF TG_OP = 'DELETE' THEN
        v_loan_id := OLD.loan_id;
    ELSE
        v_loan_id := NEW.loan_id;
    END IF;

    -- منع التكرار اللانهائي للتريجر
    IF pg_trigger_depth() = 1 THEN
        -- 1. جلب تفاصيل السلفة
        SELECT amount, installment_amount INTO v_loan_amount, v_default_installment_amount
        FROM public.loans
        WHERE id = v_loan_id;

        IF FOUND THEN
            -- 2. احتساب إجمالي الأقساط المسددة
            SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
            FROM public.loan_installments
            WHERE loan_id = v_loan_id AND is_paid = true;

            -- 3. تحديث الرصيد المتبقي بدقة
            v_new_remaining := v_loan_amount - v_total_paid;
            IF v_new_remaining < 0 THEN
                v_new_remaining := 0;
            END IF;

            UPDATE public.loans
            SET remaining_amount = v_new_remaining
            WHERE id = v_loan_id;

            -- 4. معالجة الأقساط غير المسددة
            IF v_new_remaining <= 0 THEN
                -- إذا اكتمل السداد، مسح الأقساط الزائدة غير المسددة
                DELETE FROM public.loan_installments
                WHERE loan_id = v_loan_id AND is_paid = false;
            ELSE
                -- إحصاء عدد الأقساط غير المسددة
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
                        -- إذا كان هذا هو القسط الأخير غير المسدد، يأخذ كامل المبلغ المتبقي لاستيعاب أي فرق تقريب
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
                        -- لا يوجد رصيد متبقي، حذف القسط الزائد
                        DELETE FROM public.loan_installments
                        WHERE id = v_unpaid_record.id;
                    END IF;
                END LOOP;

                -- 5. إذا كان الرصيد المتبقي أكبر من الأقساط الحالية، توليد أقساط شهرية إضافية
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

-- 3. دالة فحص واكتشاف الملفات اليتيمة في التخزين (Orphan Files Scanner)
CREATE OR REPLACE FUNCTION public.get_orphan_storage_candidates()
RETURNS TABLE (
  bucket_id TEXT,
  file_path TEXT,
  file_size BIGINT,
  created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- إرجاع الملفات المسجلة في سلة المحذوفات كمرشحات تنظيف
  RETURN QUERY
  SELECT 
    CASE 
      WHEN df.file_type = 'avatar' THEN 'avatars'::TEXT
      WHEN df.file_type = 'document' THEN 'employee-documents'::TEXT
      WHEN df.file_type = 'pledge' THEN 'loan-pledges'::TEXT
      WHEN df.file_type = 'logo' THEN 'company-logos'::TEXT
      ELSE 'employee-documents'::TEXT
    END as bucket_id,
    df.file_path,
    COALESCE(df.file_size_bytes, 0) as file_size,
    df.deleted_at as created_at
  FROM public.deleted_files df
  WHERE df.restored_at IS NULL;
END;
$$;

-- 4. دالة إرسال إشعار آمن مع منع التكرار (Safe Idempotent Notification Sender)
CREATE OR REPLACE FUNCTION public.send_idempotent_notification(
  p_employee_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_type TEXT,
  p_dedup_window_minutes INT DEFAULT 60
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- التحقق من عدم وجود إشعار مطابق تماماً تم إرساله لنفس الموظف خلال نافذة منع التكرار
  IF EXISTS (
    SELECT 1 FROM public.notifications
    WHERE employee_id = p_employee_id
      AND title = p_title
      AND body = p_body
      AND created_at > (NOW() - (p_dedup_window_minutes || ' minutes')::INTERVAL)
  ) THEN
    -- تم تخطي الإرسال لمنع التكرار
    RETURN false;
  END IF;

  INSERT INTO public.notifications (employee_id, title, body, type, is_read, created_at)
  VALUES (p_employee_id, p_title, p_body, p_type, false, NOW());

  RETURN true;
END;
$$;
