-- =========================================================================
-- Reconcile dashboard-era policies and triggers on the live project.
-- Production carried policy variants (created outside migrations) that let
-- managers write employees, devices, loans, installments and schedules, and
-- let managers insert any notification — bypassing the admin-only rules
-- defined in this repo. Guarded, so a no-op on a repo-built database.
-- =========================================================================

DROP POLICY IF EXISTS "Admins and managers have full access on employees" ON public.employees;
DROP POLICY IF EXISTS "Admins and managers can manage all devices" ON public.employee_devices;
DROP POLICY IF EXISTS "Admins and managers can manage installments" ON public.loan_installments;
DROP POLICY IF EXISTS "Admins and managers can manage loans" ON public.loans;
DROP POLICY IF EXISTS "Admins can insert notifications for anyone" ON public.notifications;
DROP POLICY IF EXISTS "Allow admin and manager manage work_schedules" ON public.work_schedules;
DROP POLICY IF EXISTS "Allow authenticated read work_schedules" ON public.work_schedules;

-- The admin-only policies from 20260520000001 were never applied there.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                 AND tablename = 'employees' AND policyname = 'Admins have full access on employees') THEN
    CREATE POLICY "Admins have full access on employees"
      ON public.employees TO authenticated USING (is_admin()) WITH CHECK (is_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                 AND tablename = 'employee_devices' AND policyname = 'Admins can manage all devices') THEN
    CREATE POLICY "Admins can manage all devices"
      ON public.employee_devices TO authenticated USING (is_admin()) WITH CHECK (is_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
                 AND tablename = 'loan_installments' AND policyname = 'Admins can manage installments') THEN
    CREATE POLICY "Admins can manage installments"
      ON public.loan_installments TO authenticated USING (is_admin()) WITH CHECK (is_admin());
  END IF;
END $$;

-- A second loan trigger recomputed remaining_amount after the repo's
-- trg_update_loan_and_installments and overwrote its result.
DROP TRIGGER IF EXISTS trigger_update_loan_remaining_amount ON public.loan_installments;
DROP FUNCTION IF EXISTS public.update_loan_remaining_amount();

-- A dashboard-era cron job called the old daily-reminder Edge Function
-- every minute; check_and_send_attendance_reminders() (20260922000000)
-- replaces it, and keeping both sends every reminder twice.
DO $$
BEGIN
  PERFORM cron.unschedule('attendance-reminder-check');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
