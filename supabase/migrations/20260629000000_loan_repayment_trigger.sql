-- Create or replace the self-healing loan and installments trigger function
CREATE OR REPLACE FUNCTION update_loan_and_installments_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_loan_id UUID;
    v_loan_amount NUMERIC;
    v_default_installment_amount NUMERIC;
    v_total_paid NUMERIC;
    v_new_remaining NUMERIC;
    v_unpaid_record RECORD;
    v_allocated_so_far NUMERIC;
    v_alloc NUMERIC;
    v_last_due_date DATE;
BEGIN
    -- Get the loan_id
    IF TG_OP = 'DELETE' THEN
        v_loan_id := OLD.loan_id;
    ELSE
        v_loan_id := NEW.loan_id;
    END IF;

    -- Only proceed if pg_trigger_depth() = 1 to avoid recursion
    IF pg_trigger_depth() = 1 THEN
        -- 1. Get loan details
        SELECT amount, installment_amount INTO v_loan_amount, v_default_installment_amount
        FROM loans
        WHERE id = v_loan_id;

        IF FOUND THEN
            -- 2. Calculate total paid installments amount
            SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
            FROM loan_installments
            WHERE loan_id = v_loan_id AND is_paid = true;

            -- 3. Update the remaining amount in loans
            v_new_remaining := v_loan_amount - v_total_paid;
            IF v_new_remaining < 0 THEN
                v_new_remaining := 0;
            END IF;

            UPDATE loans
            SET remaining_amount = v_new_remaining
            WHERE id = v_loan_id;

            -- 4. Adjust unpaid installments
            IF v_new_remaining <= 0 THEN
                -- If no remaining amount, delete all unpaid installments
                DELETE FROM loan_installments
                WHERE loan_id = v_loan_id AND is_paid = false;
            ELSE
                -- Re-allocate the remaining amount to unpaid installments
                v_allocated_so_far := 0;
                FOR v_unpaid_record IN 
                    SELECT id, amount 
                    FROM loan_installments 
                    WHERE loan_id = v_loan_id AND is_paid = false 
                    ORDER BY due_date ASC, id ASC
                LOOP
                    IF v_allocated_so_far < v_new_remaining THEN
                        -- Determine how much to assign to this installment
                        v_alloc := LEAST(v_default_installment_amount, v_new_remaining - v_allocated_so_far);
                        
                        -- Update the amount of this installment
                        UPDATE loan_installments
                        SET amount = v_alloc
                        WHERE id = v_unpaid_record.id;
                        
                        v_allocated_so_far := v_allocated_so_far + v_alloc;
                    ELSE
                        -- No more balance remains, delete this extra installment
                        DELETE FROM loan_installments
                        WHERE id = v_unpaid_record.id;
                    END IF;
                END LOOP;

                -- 5. If we still have remaining balance to cover and ran out of unpaid installments,
                -- generate new ones monthly starting from the last due_date
                IF v_allocated_so_far < v_new_remaining THEN
                    -- Get the max due date
                    SELECT COALESCE(MAX(due_date), CURRENT_DATE) INTO v_last_due_date
                    FROM loan_installments
                    WHERE loan_id = v_loan_id;

                    WHILE v_allocated_so_far < v_new_remaining LOOP
                        v_last_due_date := v_last_due_date + INTERVAL '1 month';
                        v_alloc := LEAST(v_default_installment_amount, v_new_remaining - v_allocated_so_far);
                        
                        INSERT INTO loan_installments (loan_id, due_date, amount, is_paid)
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

-- Trigger definition on UPDATE of is_paid or amount, or DELETE
DROP TRIGGER IF EXISTS trg_update_loan_and_installments ON loan_installments;
CREATE TRIGGER trg_update_loan_and_installments
AFTER UPDATE OF is_paid, amount OR DELETE ON loan_installments
FOR EACH ROW
EXECUTE FUNCTION update_loan_and_installments_trigger();
