-- =====================================================================
-- النسخة الحالية من دوال قاعدة البيانات و triggers — مولّدة تلقائياً، للقراءة فقط.
-- لا تعدّل هذا الملف ولا تطبّقه. التعديل = migration جديد، ثم: node supabase/schema/generate.mjs
-- عدد الدوال: 112 — عدد الـ triggers: 33
-- =====================================================================

-- ---------------------------------------------------------------------
-- فهرس: الدالة ← آخر migration عرّفها
-- ---------------------------------------------------------------------
--   _anonymize_employee(p_employee_id uuid)  ←  20260929000400_audit_fixes.sql
--   _ar_time(p_time time without time zone)  ←  20260930000100_arabic_reminder_times.sql
--   _insert_loan_installments(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date)  ←  20260925000000_approve_loan_rpc.sql
--   _payroll_settle(p_event payroll_events, p_desired_signed numeric)  ←  20260929000400_audit_fixes.sql
--   _validate_loan_terms(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_ignore_loan uuid)  ←  20261003000000_admin_loans_over_half_salary.sql
--   announcement_targets(a announcements, p_employee_id uuid)  ←  20260928000400_announcements_period_and_on_leave.sql
--   approve_loan(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date)  ←  20260925000000_approve_loan_rpc.sql
--   approve_payroll_slip(p_employee_id uuid, p_month text, p_adjustments jsonb)  ←  20260929000400_audit_fixes.sql
--   approve_salary_slip(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[], p_adjustments jsonb)  ←  20260929000000_payroll_engine.sql
--   approve_salary_slip_legacy(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[], p_adjustments jsonb)  ←  (خارج migrations)
--   cancel_my_loan_request(p_loan_id uuid)  ←  20260930000400_cancel_loan_request.sql
--   check_and_send_attendance_reminders(p_now timestamp with time zone)  ←  20260930000100_arabic_reminder_times.sql
--   check_bonus_deduction_amount()  ←  20261002000000_full_qa_fixes.sql
--   check_employee_basics()  ←  20261002000000_full_qa_fixes.sql
--   close_payroll_period(p_month text)  ←  20260929000000_payroll_engine.sql
--   company_timezone()  ←  20260924000100_server_side_attendance_and_device_lock.sql
--   create_default_leave_balance()  ←  20260924000200_leave_balances_and_decision_notifications.sql
--   create_direct_loan(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_pledge_url text, p_notes text)  ←  20260925000000_approve_loan_rpc.sql
--   create_employee_secure(p_email text, p_password text, p_full_name text, p_phone text, p_role text, p_branch_id uuid, p_monthly_salary_iqd numeric, p_document_urls text[], p_employee_code text, p_employee_id uuid, p_join_date date, p_department_id uuid)  ←  20260703000000_security_and_rls_hardening.sql
--   decide_payroll_event(p_event_id uuid, p_approve boolean, p_reason text)  ←  20260929000400_audit_fixes.sql
--   distance_meters(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)  ←  20260924000100_server_side_attendance_and_device_lock.sql
--   employee_shift_hours(p_employee_id uuid)  ←  20260928000100_admin_only_documents_hourly_leave_balance.sql
--   employee_work_days(p_employee_id uuid)  ←  20260928000000_security_hardening_round2.sql
--   ensure_payroll_period(p_month text)  ←  20260929000000_payroll_engine.sql
--   fmt_days(v numeric)  ←  20260928000100_admin_only_documents_hourly_leave_balance.sql
--   get_active_announcements(p_limit integer)  ←  20260928000400_announcements_period_and_on_leave.sql
--   get_database_size()  ←  20260924000000_lock_down_rpc_views_and_notifications.sql
--   get_database_table_sizes()  ←  20260924000000_lock_down_rpc_views_and_notifications.sql
--   get_effective_work_schedule(p_employee_id uuid)  ←  20260924000100_server_side_attendance_and_device_lock.sql
--   get_employee_directory()  ←  20260924000000_lock_down_rpc_views_and_notifications.sql
--   get_late_today()  ←  20260929000200_late_today.sql
--   get_leave_balance(p_employee_id uuid, p_on date, p_exclude uuid)  ←  20260928000200_leave_policy.sql
--   get_my_payroll_preview()  ←  20260929000500_user_flow_fixes.sql
--   get_on_leave_now()  ←  20260928000400_announcements_period_and_on_leave.sql
--   get_orphan_storage_candidates()  ←  20260924000000_lock_down_rpc_views_and_notifications.sql
--   get_payroll_events(p_month text, p_employee_id uuid)  ←  20260929000000_payroll_engine.sql
--   get_payroll_run(p_month text)  ←  20260929000500_user_flow_fixes.sql
--   get_pending_payroll_decisions()  ←  20260929000400_audit_fixes.sql
--   get_storage_stats()  ←  20260924000000_lock_down_rpc_views_and_notifications.sql
--   hard_delete_employee(p_employee_id uuid)  ←  20260701000000_fix_rpcs_and_functions.sql
--   invoke_push_notification()  ←  20261005000000_capture_dashboard_objects.sql
--   is_admin()  ←  20260520000001_indexes_rls.sql
--   is_manager()  ←  20260520000001_indexes_rls.sql
--   keep_payroll_policy_keys()  ←  20260929000000_payroll_engine.sql
--   keep_status_on_early_checkout()  ←  20260929000000_payroll_engine.sql
--   leave_policy()  ←  20260928000200_leave_policy.sql
--   leave_request_days(lr leave_requests)  ←  20260928000200_leave_policy.sql
--   leave_request_hours(lr leave_requests)  ←  20260928000200_leave_policy.sql
--   manual_purge_month_data(p_year integer, p_month integer, p_notifications boolean, p_tracking boolean, p_absences boolean)  ←  20261002000000_full_qa_fixes.sql
--   notify_admins_of_new_leave_request()  ←  20260920000300_notify_admins_on_new_requests.sql
--   notify_admins_of_new_loan_request()  ←  20260930000500_loan_requests_notify_admins_only.sql
--   notify_employee_on_leave_decision()  ←  20260924000200_leave_balances_and_decision_notifications.sql
--   notify_employee_on_loan_decision()  ←  20260924000200_leave_balances_and_decision_notifications.sql
--   one_pending_loan_request()  ←  20261004000100_employee_loan_request_over_half_salary.sql
--   pay_loan_installment(p_installment_id uuid, p_amount numeric, p_method text, p_note text)  ←  20260927000000_flexible_installment_payment.sql
--   payroll_basic_salary(p_employee_id uuid, p_month text)  ←  20260929000000_payroll_engine.sql
--   payroll_daily_rate(p_employee_id uuid, p_month text)  ←  20260929000000_payroll_engine.sql
--   payroll_employee_summary(p_employee_id uuid, p_month text)  ←  20260929000400_audit_fixes.sql
--   payroll_hourly_leave_overlap(p_employee_id uuid, p_date date, p_from numeric, p_to numeric)  ←  20260929000400_audit_fixes.sql
--   payroll_legacy_slip(p_employee_id uuid, p_month text)  ←  20260929000400_audit_fixes.sql
--   payroll_legacy_slip(p_employee_id uuid, p_month text, p_date date)  ←  20260929000400_audit_fixes.sql
--   payroll_local_minutes(p_ts timestamp with time zone)  ←  20260929000000_payroll_engine.sql
--   payroll_month_add(p_month text, p_n integer)  ←  20260929000000_payroll_engine.sql
--   payroll_natural_month(p_date date)  ←  20260929000000_payroll_engine.sql
--   payroll_policy()  ←  20260929000000_payroll_engine.sql
--   payroll_same_branch(p_employee_id uuid)  ←  20260929000400_audit_fixes.sql
--   payroll_schedule(p_employee_id uuid)  ←  20260929000000_payroll_engine.sql
--   payroll_shift_minutes(p_employee_id uuid)  ←  20260929000000_payroll_engine.sql
--   payroll_target_month(p_employee_id uuid, p_natural text)  ←  20260929000000_payroll_engine.sql
--   payroll_time_minutes(p_t time without time zone)  ←  20260929000000_payroll_engine.sql
--   perform_daily_cleanup()  ←  20260929000400_audit_fixes.sql
--   protect_attendance_decisions()  ←  20260929000500_user_flow_fixes.sql
--   protect_attendance_times()  ←  20260928000000_security_hardening_round2.sql
--   protect_employee_columns()  ←  20260928000100_admin_only_documents_hourly_leave_balance.sql
--   protect_leave_decisions()  ←  20260929000500_user_flow_fixes.sql
--   publish_announcement(p_title text, p_content text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_target text, p_branch_id uuid, p_employee_ids uuid[], p_pinned boolean)  ←  20260928000400_announcements_period_and_on_leave.sql
--   punch_attendance(p_type text, p_latitude double precision, p_longitude double precision, p_device_id text, p_is_mocked boolean, p_client_time timestamp with time zone, p_accuracy double precision)  ←  20261004000000_punch_rejects_low_accuracy.sql
--   purge_old_location_tracking()  ←  20260920000200_enable_pg_cron_scheduling.sql
--   record_audit_log()  ←  20260920000000_document_rpcs_and_add_audit_log.sql
--   refresh_orphan_candidates_cache()  ←  20260920000200_enable_pg_cron_scheduling.sql
--   register_device_login(p_device_id text, p_model text, p_os_version text, p_legacy_device_id text)  ←  20260924000100_server_side_attendance_and_device_lock.sql
--   reject_future_attendance()  ←  20261002000000_full_qa_fixes.sql
--   reject_negative_salary_slip()  ←  20260928000300_no_negative_salary_slip.sql
--   reopen_payroll_period(p_month text, p_reason text)  ←  20260929000000_payroll_engine.sql
--   request_account_deletion()  ←  20260924000400_account_deletion_request.sql
--   require_admin()  ←  20260924000000_lock_down_rpc_views_and_notifications.sql
--   require_admin_or_manager()  ←  20260924000000_lock_down_rpc_views_and_notifications.sql
--   require_admin_or_system()  ←  20260924000000_lock_down_rpc_views_and_notifications.sql
--   reschedule_loan(p_loan_id uuid, p_amount numeric, p_installment_amount numeric, p_count integer)  ←  20260929000500_user_flow_fixes.sql
--   resync_payroll_on_salary_change()  ←  20261002000000_full_qa_fixes.sql
--   revert_payroll_slip(p_slip_id uuid)  ←  20260929000000_payroll_engine.sql
--   revert_salary_slip(p_slip_id uuid, p_period_start date, p_period_end date)  ←  20260924000300_atomic_payroll_approval.sql
--   rls_auto_enable()  ←  (خارج migrations)
--   safe_archive_payroll_month(target_month text, cycle_start_day integer, cycle_end_day integer)  ←  20260929000000_payroll_engine.sql
--   safe_delete_employee(p_employee_id uuid)  ←  20260929000800_only_admin_deletes_employees.sql
--   send_idempotent_notification(p_employee_id uuid, p_title text, p_body text, p_type text, p_dedup_window_minutes integer)  ←  20260924000000_lock_down_rpc_views_and_notifications.sql
--   set_employee_leave_entitlement(p_employee_id uuid, p_annual numeric, p_sick numeric, p_hourly_monthly_hours numeric)  ←  20260928000200_leave_policy.sql
--   set_payroll_policy(p_cutoff_day integer, p_payment_day integer, p_overtime_enabled boolean, p_overtime_multiplier numeric, p_overtime_min_minutes integer)  ←  20260929000000_payroll_engine.sql
--   set_termination_date()  ←  20260929000000_payroll_engine.sql
--   strip_plain_password()  ←  20260928000000_security_hardening_round2.sql
--   sync_geofence_coordinates()  ←  20261005000000_capture_dashboard_objects.sql
--   sync_geofences_to_branches()  ←  20261005000000_capture_dashboard_objects.sql
--   sync_payroll_day(p_employee_id uuid, p_date date)  ←  20261002000000_full_qa_fixes.sql
--   sync_payroll_manual(p_bd_id uuid)  ←  20260929000000_payroll_engine.sql
--   sync_payroll_period(p_month text, p_employee_id uuid)  ←  20260929000000_payroll_engine.sql
--   trg_payroll_attendance()  ←  20260929000000_payroll_engine.sql
--   trg_payroll_holiday()  ←  20260929000400_audit_fixes.sql
--   trg_payroll_leave()  ←  20260929000000_payroll_engine.sql
--   trg_payroll_manual()  ←  20260929000000_payroll_engine.sql
--   update_employee_credentials(p_employee_id uuid, p_email text, p_password text, p_phone text)  ←  20260924000000_lock_down_rpc_views_and_notifications.sql
--   update_loan_and_installments_trigger()  ←  20260929000500_user_flow_fixes.sql
--   validate_leave_request()  ←  20260928000200_leave_policy.sql

-- ---------------------------------------------------------------------
-- Triggers: الجدول ← الدالة اللي تشتغل تلقائياً
-- ---------------------------------------------------------------------
--   attendance.trg_keep_status_on_early_checkout  →  keep_status_on_early_checkout()
--   attendance.trg_payroll_attendance  →  trg_payroll_attendance()
--   attendance.trg_protect_attendance_decisions  →  protect_attendance_decisions()
--   attendance.trg_protect_attendance_times  →  protect_attendance_times()
--   attendance.trg_reject_future_attendance  →  reject_future_attendance()
--   bonuses_deductions.trg_audit_bonuses  →  record_audit_log()
--   bonuses_deductions.trg_check_bonus_deduction_amount  →  check_bonus_deduction_amount()
--   bonuses_deductions.trg_payroll_manual  →  trg_payroll_manual()
--   employees.trg_audit_employees  →  record_audit_log()
--   employees.trg_check_employee_basics  →  check_employee_basics()
--   employees.trg_create_default_leave_balance  →  create_default_leave_balance()
--   employees.trg_protect_employee_columns  →  protect_employee_columns()
--   employees.trg_resync_payroll_on_salary_change  →  resync_payroll_on_salary_change()
--   employees.trg_set_termination_date  →  set_termination_date()
--   employees.trg_strip_plain_password  →  strip_plain_password()
--   geofence_zones.trg_sync_geofence_coordinates  →  sync_geofence_coordinates()
--   geofence_zones.trg_sync_geofences_to_branches  →  sync_geofences_to_branches()
--   leave_requests.trg_audit_leave_requests  →  record_audit_log()
--   leave_requests.trg_notify_admins_new_leave_request  →  notify_admins_of_new_leave_request()
--   leave_requests.trg_notify_employee_leave_decision  →  notify_employee_on_leave_decision()
--   leave_requests.trg_payroll_leave  →  trg_payroll_leave()
--   leave_requests.trg_protect_leave_decisions  →  protect_leave_decisions()
--   leave_requests.trg_validate_leave_request  →  validate_leave_request()
--   loan_installments.trg_update_loan_and_installments  →  update_loan_and_installments_trigger()
--   loans.trg_audit_loans  →  record_audit_log()
--   loans.trg_notify_admins_new_loan_request  →  notify_admins_of_new_loan_request()
--   loans.trg_notify_employee_loan_decision  →  notify_employee_on_loan_decision()
--   loans.trg_one_pending_loan_request  →  one_pending_loan_request()
--   notifications.on_notification_insert  →  invoke_push_notification()
--   official_holidays.trg_payroll_holiday  →  trg_payroll_holiday()
--   salary_slips.trg_audit_salary_slips  →  record_audit_log()
--   salary_slips.trg_reject_negative_salary_slip  →  reject_negative_salary_slip()
--   system_settings.trg_keep_payroll_policy_keys  →  keep_payroll_policy_keys()

CREATE TRIGGER trg_keep_status_on_early_checkout BEFORE UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION keep_status_on_early_checkout();
CREATE TRIGGER trg_payroll_attendance AFTER INSERT OR DELETE OR UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION trg_payroll_attendance();
CREATE TRIGGER trg_protect_attendance_decisions BEFORE INSERT OR UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION protect_attendance_decisions();
CREATE TRIGGER trg_protect_attendance_times BEFORE UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION protect_attendance_times();
CREATE TRIGGER trg_reject_future_attendance BEFORE INSERT OR UPDATE OF work_date, check_in_time, check_out_time ON public.attendance FOR EACH ROW EXECUTE FUNCTION reject_future_attendance();
CREATE TRIGGER trg_audit_bonuses AFTER INSERT OR DELETE OR UPDATE ON public.bonuses_deductions FOR EACH ROW EXECUTE FUNCTION record_audit_log();
CREATE TRIGGER trg_check_bonus_deduction_amount BEFORE INSERT OR UPDATE OF amount, type, employee_id ON public.bonuses_deductions FOR EACH ROW EXECUTE FUNCTION check_bonus_deduction_amount();
CREATE TRIGGER trg_payroll_manual AFTER INSERT OR DELETE OR UPDATE ON public.bonuses_deductions FOR EACH ROW EXECUTE FUNCTION trg_payroll_manual();
CREATE TRIGGER trg_audit_employees AFTER INSERT OR DELETE OR UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION record_audit_log();
CREATE TRIGGER trg_check_employee_basics BEFORE INSERT OR UPDATE OF full_name, join_date, termination_date ON public.employees FOR EACH ROW EXECUTE FUNCTION check_employee_basics();
CREATE TRIGGER trg_create_default_leave_balance AFTER INSERT ON public.employees FOR EACH ROW EXECUTE FUNCTION create_default_leave_balance();
CREATE TRIGGER trg_protect_employee_columns BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION protect_employee_columns();
CREATE TRIGGER trg_resync_payroll_on_salary_change AFTER UPDATE OF monthly_salary_iqd ON public.employees FOR EACH ROW EXECUTE FUNCTION resync_payroll_on_salary_change();
CREATE TRIGGER trg_set_termination_date BEFORE UPDATE OF is_active ON public.employees FOR EACH ROW EXECUTE FUNCTION set_termination_date();
CREATE TRIGGER trg_strip_plain_password BEFORE INSERT OR UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION strip_plain_password();
CREATE TRIGGER trg_sync_geofence_coordinates BEFORE INSERT OR UPDATE OF polygon_coordinates, coordinates ON public.geofence_zones FOR EACH ROW EXECUTE FUNCTION sync_geofence_coordinates();
CREATE TRIGGER trg_sync_geofences_to_branches AFTER INSERT OR DELETE OR UPDATE ON public.geofence_zones FOR EACH ROW EXECUTE FUNCTION sync_geofences_to_branches();
CREATE TRIGGER trg_audit_leave_requests AFTER DELETE OR UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION record_audit_log();
CREATE TRIGGER trg_notify_admins_new_leave_request AFTER INSERT ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION notify_admins_of_new_leave_request();
CREATE TRIGGER trg_notify_employee_leave_decision AFTER UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION notify_employee_on_leave_decision();
CREATE TRIGGER trg_payroll_leave AFTER INSERT OR DELETE OR UPDATE OF status, start_date, end_date, is_paid, is_hourly, start_hour, end_hour ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION trg_payroll_leave();
CREATE TRIGGER trg_protect_leave_decisions BEFORE INSERT OR UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION protect_leave_decisions();
CREATE TRIGGER trg_validate_leave_request BEFORE INSERT OR UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION validate_leave_request();
CREATE TRIGGER trg_update_loan_and_installments AFTER DELETE OR UPDATE OF is_paid, amount ON public.loan_installments FOR EACH ROW EXECUTE FUNCTION update_loan_and_installments_trigger();
CREATE TRIGGER trg_audit_loans AFTER INSERT OR DELETE OR UPDATE ON public.loans FOR EACH ROW EXECUTE FUNCTION record_audit_log();
CREATE TRIGGER trg_notify_admins_new_loan_request AFTER INSERT ON public.loans FOR EACH ROW EXECUTE FUNCTION notify_admins_of_new_loan_request();
CREATE TRIGGER trg_notify_employee_loan_decision AFTER UPDATE ON public.loans FOR EACH ROW EXECUTE FUNCTION notify_employee_on_loan_decision();
CREATE TRIGGER trg_one_pending_loan_request BEFORE INSERT ON public.loans FOR EACH ROW EXECUTE FUNCTION one_pending_loan_request();
CREATE TRIGGER on_notification_insert AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION invoke_push_notification();
CREATE TRIGGER trg_payroll_holiday AFTER INSERT OR DELETE ON public.official_holidays FOR EACH ROW EXECUTE FUNCTION trg_payroll_holiday();
CREATE TRIGGER trg_audit_salary_slips AFTER INSERT OR DELETE OR UPDATE ON public.salary_slips FOR EACH ROW EXECUTE FUNCTION record_audit_log();
CREATE TRIGGER trg_reject_negative_salary_slip BEFORE INSERT OR UPDATE OF net_salary ON public.salary_slips FOR EACH ROW EXECUTE FUNCTION reject_negative_salary_slip();
CREATE TRIGGER trg_keep_payroll_policy_keys BEFORE INSERT OR UPDATE ON public.system_settings FOR EACH ROW EXECUTE FUNCTION keep_payroll_policy_keys();

-- ---------------------------------------------------------------------
-- _anonymize_employee(p_employee_id uuid)  — آخر تعريف: 20260929000400_audit_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._anonymize_employee(p_employee_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  -- إخفاء هوية الموظف في جدول الموظفين وتصفير مستنداته بأمان
  UPDATE public.employees
  SET 
    full_name = 'مستخدم محذوف',
    phone = NULL,
    email = 'deleted_' || substring(p_employee_id::text from 1 for 8) || '@deleted.com',
    avatar_url = NULL,
    is_active = false,
    plain_password = NULL,
    document_urls = '[]'::jsonb
  WHERE id = p_employee_id;

  -- إزالة الأجهزة المقترنة والتوكنات
  DELETE FROM public.employee_devices WHERE employee_id = p_employee_id;
  DELETE FROM public.fcm_tokens WHERE employee_id = p_employee_id;
  DELETE FROM public.device_tokens WHERE employee_id = p_employee_id;

  -- حذف الحساب من المصادقة
  DELETE FROM auth.users WHERE id = p_employee_id;
END;
$function$;

-- ---------------------------------------------------------------------
-- _ar_time(p_time time without time zone)  — آخر تعريف: 20260930000100_arabic_reminder_times.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._ar_time(p_time time without time zone)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT to_char(p_time, 'FMHH12:MI') || CASE WHEN extract(hour FROM p_time) < 12 THEN ' ص' ELSE ' م' END;
$function$;

-- ---------------------------------------------------------------------
-- _insert_loan_installments(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date)  — آخر تعريف: 20260925000000_approve_loan_rpc.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._insert_loan_installments(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  INSERT INTO loan_installments (loan_id, due_date, amount, is_paid)
  SELECT p_loan_id,
         (p_first_due + make_interval(months => g))::date,
         CASE WHEN g = p_months - 1
              THEN p_amount - floor(p_amount / p_months) * (p_months - 1)
              ELSE floor(p_amount / p_months) END,
         false
  FROM generate_series(0, p_months - 1) AS g;
$function$;

-- ---------------------------------------------------------------------
-- _payroll_settle(p_event payroll_events, p_desired_signed numeric)  — آخر تعريف: 20260929000400_audit_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._payroll_settle(p_event payroll_events, p_desired_signed numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_posted numeric;
  v_delta numeric;
  v_open payroll_events%ROWTYPE;
  v_target text;
  v_labels jsonb := '{"absence":"غياب","late":"تأخير","early_leave":"خروج مبكر","unpaid_leave":"إجازة بدون راتب","overtime":"ساعات إضافية","manual_deduction":"خصم","bonus":"مكافأة","paid_leave":"إجازة مدفوعة","missing_punch":"بصمة ناقصة"}';
BEGIN
  IF p_event.salary_slip_id IS NULL THEN RETURN; END IF;

  -- الأثر المُحتسب حتى الآن: الحركة الأصلية + تسوياتها المعتمدة داخل كشوف
  SELECT (CASE WHEN p_event.status = 'approved' THEN p_event.direction * p_event.amount ELSE 0 END)
       + COALESCE(sum(a.direction * a.amount) FILTER (WHERE a.salary_slip_id IS NOT NULL AND a.status = 'approved'), 0)
  INTO v_posted
  FROM payroll_events a
  WHERE a.adjusts_event_id = p_event.id;
  v_posted := COALESCE(v_posted, CASE WHEN p_event.status = 'approved' THEN p_event.direction * p_event.amount ELSE 0 END);

  v_delta := round(p_desired_signed - v_posted, 2);

  SELECT * INTO v_open FROM payroll_events
  WHERE adjusts_event_id = p_event.id AND salary_slip_id IS NULL AND status <> 'void'
  LIMIT 1;

  IF v_delta = 0 THEN
    IF v_open.id IS NOT NULL THEN
      UPDATE payroll_events SET status = 'void', updated_at = now() WHERE id = v_open.id;
    END IF;
    RETURN;
  END IF;

  IF v_open.id IS NOT NULL THEN
    UPDATE payroll_events
    SET amount = abs(v_delta), direction = sign(v_delta)::smallint, updated_at = now()
    WHERE id = v_open.id;
  ELSE
    v_target := public.payroll_target_month(p_event.employee_id, p_event.payroll_month);
    INSERT INTO payroll_events (employee_id, event_date, event_type, minutes, days, amount, direction, payroll_month,
                                carried_from, status, source, adjusts_event_id, daily_rate, minute_rate, notes)
    VALUES (p_event.employee_id, p_event.event_date, 'adjustment', p_event.minutes, p_event.days, abs(v_delta),
            sign(v_delta)::smallint, v_target, p_event.payroll_month, 'approved', 'carry_over', p_event.id,
            p_event.daily_rate, p_event.minute_rate,
            format('تسوية %s بتاريخ %s بعد اعتماد مسير %s',
                   COALESCE(v_labels ->> p_event.event_type, p_event.event_type), p_event.event_date, p_event.payroll_month));
  END IF;
END;
$function$;

-- ---------------------------------------------------------------------
-- _validate_loan_terms(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_ignore_loan uuid)  — آخر تعريف: 20261003000000_admin_loans_over_half_salary.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._validate_loan_terms(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_ignore_loan uuid DEFAULT NULL::uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 OR p_months IS NULL OR p_months <= 0 THEN
    RAISE EXCEPTION 'يرجى إدخال مبلغ وعدد أشهر سداد أكبر من الصفر.' USING ERRCODE = '22023';
  END IF;
  IF p_first_due IS NULL THEN
    RAISE EXCEPTION 'يرجى تحديد تاريخ استحقاق أول قسط.' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM loans
    WHERE employee_id = p_employee_id AND status = 'approved' AND remaining_amount > 0
      AND id IS DISTINCT FROM p_ignore_loan
  ) THEN
    RAISE EXCEPTION 'لا يمكن الموافقة: الموظف لديه سلفة نشطة حالياً. يرجى إغلاقها أولاً.' USING ERRCODE = '55000';
  END IF;

  RETURN floor(p_amount / p_months);
END;
$function$;

-- ---------------------------------------------------------------------
-- announcement_targets(a announcements, p_employee_id uuid)  — آخر تعريف: 20260928000400_announcements_period_and_on_leave.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.announcement_targets(a announcements, p_employee_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN a.target_employee_ids IS NOT NULL AND cardinality(a.target_employee_ids) > 0
      THEN p_employee_id = ANY (a.target_employee_ids)
    WHEN a.target_branch_id IS NOT NULL
      THEN EXISTS (SELECT 1 FROM employees e WHERE e.id = p_employee_id AND e.branch_id = a.target_branch_id)
    WHEN a.target_department_id IS NOT NULL
      THEN EXISTS (SELECT 1 FROM employees e WHERE e.id = p_employee_id AND e.department_id = a.target_department_id)
    ELSE true
  END;
$function$;

-- ---------------------------------------------------------------------
-- approve_loan(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date)  — آخر تعريف: 20260925000000_approve_loan_rpc.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_loan(p_loan_id uuid, p_amount numeric, p_months integer, p_first_due date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_loan loans%ROWTYPE;
  v_base numeric;
BEGIN
  PERFORM public.require_admin();

  SELECT * INTO v_loan FROM loans WHERE id = p_loan_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'طلب السلفة غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF v_loan.status <> 'pending' THEN
    RAISE EXCEPTION 'تمت معالجة طلب السلفة هذا مسبقاً.' USING ERRCODE = '55000';
  END IF;

  v_base := public._validate_loan_terms(v_loan.employee_id, p_amount, p_months, p_first_due, p_loan_id);

  UPDATE loans
  SET status = 'approved',
      amount = p_amount,
      installment_count = p_months,
      installment_amount = v_base,
      remaining_amount = p_amount,
      approved_by = auth.uid(),
      approved_at = now()
  WHERE id = p_loan_id;

  PERFORM public._insert_loan_installments(p_loan_id, p_amount, p_months, p_first_due);
END;
$function$;

-- ---------------------------------------------------------------------
-- approve_payroll_slip(p_employee_id uuid, p_month text, p_adjustments jsonb)  — آخر تعريف: 20260929000400_audit_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_payroll_slip(p_employee_id uuid, p_month text, p_adjustments jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_sum jsonb;
  v_slip uuid;
  v_adj jsonb;
BEGIN
  PERFORM public.require_admin();
  v_p := public.ensure_payroll_period(p_month);
  IF v_p.status <> 'open' OR EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month) THEN
    RAISE EXCEPTION 'مسير % مغلق. أعد فتحه أولاً.', p_month USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = p_employee_id AND work_month = p_month) THEN
    RAISE EXCEPTION 'تم صرف الراتب مسبقاً لهذا الموظف في هذا الشهر.' USING ERRCODE = '23505';
  END IF;

  PERFORM public.sync_payroll_period(p_month, p_employee_id);

  -- تعديلات يدوية وقت الاعتماد (مكافأة/خصم إضافي بسبب)
  FOR v_adj IN SELECT * FROM jsonb_array_elements(COALESCE(p_adjustments, '[]'::jsonb)) LOOP
    CONTINUE WHEN COALESCE((v_adj ->> 'amount')::numeric, 0) <= 0;
    INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, status, source, notes, created_by)
    VALUES (p_employee_id, v_p.cutoff_date,
            CASE WHEN v_adj ->> 'type' = 'bonus' THEN 'bonus' ELSE 'manual_deduction' END,
            round((v_adj ->> 'amount')::numeric),
            CASE WHEN v_adj ->> 'type' = 'bonus' THEN 1 ELSE -1 END,
            p_month, 'approved', 'approval', v_adj ->> 'reason', auth.uid());
  END LOOP;

  v_sum := public.payroll_employee_summary(p_employee_id, p_month);

  INSERT INTO salary_slips (employee_id, work_month, basic_salary, allowances, deductions, loans_deduction, net_salary, status, computed_by_engine)
  VALUES (p_employee_id, p_month, (v_sum ->> 'basic')::numeric, (v_sum ->> 'earnings')::numeric,
          (v_sum ->> 'deductions')::numeric, (v_sum ->> 'loans')::numeric, (v_sum ->> 'net')::numeric, 'published', true)
  RETURNING id INTO v_slip;

  INSERT INTO salary_slip_lines (salary_slip_id, event_id, line_type, event_date, minutes, days, amount, direction, notes, carried_from)
  SELECT v_slip, pe.id, pe.event_type, pe.event_date, pe.minutes, pe.days, pe.amount, pe.direction, pe.notes, pe.carried_from
  FROM payroll_events pe
  WHERE pe.employee_id = p_employee_id AND pe.payroll_month = p_month AND pe.status = 'approved'
    AND (pe.amount > 0 OR pe.event_type = 'paid_leave');

  INSERT INTO salary_slip_lines (salary_slip_id, line_type, event_date, amount, direction, notes)
  SELECT v_slip, 'loan', li.due_date, li.amount, -1, 'قسط سلفة'
  FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  UPDATE payroll_events SET salary_slip_id = v_slip, updated_at = now()
  WHERE employee_id = p_employee_id AND payroll_month = p_month AND status = 'approved';

  UPDATE loan_installments li
  SET is_paid = true, paid_at = now(), paid_by_slip_id = v_slip
  FROM loans l
  WHERE li.loan_id = l.id AND l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  RETURN v_slip;
END;
$function$;

-- ---------------------------------------------------------------------
-- approve_salary_slip(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[], p_adjustments jsonb)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_salary_slip(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[] DEFAULT '{}'::uuid[], p_adjustments jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  IF EXISTS (SELECT 1 FROM payroll_periods WHERE period_month = p_work_month) THEN
    RAISE EXCEPTION 'تم تحديث نظام الرواتب. حدّث صفحة الرواتب (Ctrl+Shift+R) ثم أعد الاعتماد.' USING ERRCODE = '42501';
  END IF;
  RETURN public.approve_salary_slip_legacy(p_employee_id, p_work_month, p_basic_salary, p_allowances, p_deductions,
                                           p_loans_deduction, p_net_salary, p_installment_ids, p_adjustments);
END;
$function$;

-- ---------------------------------------------------------------------
-- approve_salary_slip_legacy(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[], p_adjustments jsonb)  — آخر تعريف: (خارج migrations)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_salary_slip_legacy(p_employee_id uuid, p_work_month text, p_basic_salary numeric, p_allowances numeric, p_deductions numeric, p_loans_deduction numeric, p_net_salary numeric, p_installment_ids uuid[] DEFAULT '{}'::uuid[], p_adjustments jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_slip_id uuid;
  v_adj jsonb;
BEGIN
  PERFORM public.require_admin();

  IF EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_work_month) THEN
    RAISE EXCEPTION 'هذا الشهر مؤرشف مالياً ومقفل.' USING ERRCODE = '42501';
  END IF;

  BEGIN
    INSERT INTO salary_slips (employee_id, work_month, basic_salary, allowances,
                              deductions, loans_deduction, net_salary, status)
    VALUES (p_employee_id, p_work_month, p_basic_salary, COALESCE(p_allowances, 0),
            COALESCE(p_deductions, 0), COALESCE(p_loans_deduction, 0), p_net_salary, 'published')
    RETURNING id INTO v_slip_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'تم صرف الراتب مسبقاً لهذا الموظف في هذا الشهر.' USING ERRCODE = '23505';
  END;

  UPDATE loan_installments li
  SET is_paid = true, paid_at = now(), paid_by_slip_id = v_slip_id
  FROM loans l
  WHERE li.id = ANY(COALESCE(p_installment_ids, '{}'))
    AND li.loan_id = l.id
    AND l.employee_id = p_employee_id
    AND li.is_paid = false;

  FOR v_adj IN SELECT * FROM jsonb_array_elements(COALESCE(p_adjustments, '[]'::jsonb))
  LOOP
    CONTINUE WHEN COALESCE((v_adj->>'amount')::numeric, 0) <= 0;
    CONTINUE WHEN COALESCE((v_adj->>'skip_if_exists')::boolean, false) AND EXISTS (
      SELECT 1 FROM bonuses_deductions
      WHERE employee_id = p_employee_id
        AND type = v_adj->>'type'
        AND reason = v_adj->>'reason'
    );

    INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date,
                                    created_by, salary_slip_id)
    VALUES (p_employee_id, v_adj->>'type', (v_adj->>'amount')::numeric, v_adj->>'reason',
            COALESCE((v_adj->>'issue_date')::date, current_date), auth.uid(), v_slip_id);
  END LOOP;

  RETURN v_slip_id;
END;
$function$;

-- ---------------------------------------------------------------------
-- cancel_my_loan_request(p_loan_id uuid)  — آخر تعريف: 20260930000400_cancel_loan_request.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_my_loan_request(p_loan_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  UPDATE loans SET status = 'cancelled'
  WHERE id = p_loan_id AND employee_id = auth.uid() AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يمكن إلغاء هذا الطلب (غير موجود أو تمت معالجته).' USING ERRCODE = '55000';
  END IF;
END;
$function$;

-- ---------------------------------------------------------------------
-- check_and_send_attendance_reminders(p_now timestamp with time zone)  — آخر تعريف: 20260930000100_arabic_reminder_times.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_and_send_attendance_reminders(p_now timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_local    timestamp := p_now AT TIME ZONE public.company_timezone();
  v_today    date := v_local::date;
  v_dow      integer := EXTRACT(DOW FROM v_local)::integer;
  v_emp      record;
  v_sched    work_schedules%ROWTYPE;
  v_att      attendance%ROWTYPE;
  v_has_att  boolean;
  v_start    timestamp;
  v_end      timestamp;
  v_after    interval;
  v_kind     text;
  v_title    text;
  v_body     text;
  v_sent     integer := 0;
BEGIN
  IF EXISTS (SELECT 1 FROM official_holidays WHERE holiday_date = v_today) THEN
    RETURN 0; -- عطلة رسمية
  END IF;

  FOR v_emp IN SELECT id, full_name FROM employees WHERE is_active LOOP
    SELECT * INTO v_sched FROM public.get_effective_work_schedule(v_emp.id) LIMIT 1;
    CONTINUE WHEN NOT FOUND;
    CONTINUE WHEN v_sched.check_in_time IS NULL OR v_sched.check_out_time IS NULL;
    CONTINUE WHEN v_sched.work_days IS NOT NULL AND NOT (v_dow = ANY (v_sched.work_days));

    -- لا تذكير لمن عنده إجازة يومية معتمدة تشمل اليوم
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM leave_requests lr
      WHERE lr.employee_id = v_emp.id AND lr.status = 'approved'
        AND NOT COALESCE(lr.is_hourly, false)
        AND v_today BETWEEN (lr.start_date AT TIME ZONE public.company_timezone())::date
                        AND (lr.end_date AT TIME ZONE public.company_timezone())::date
    );

    SELECT * INTO v_att FROM attendance WHERE employee_id = v_emp.id AND work_date = v_today;
    v_has_att := FOUND;

    v_start := v_today + v_sched.check_in_time;
    v_end   := v_today + v_sched.check_out_time;
    IF v_end <= v_start THEN v_end := v_end + interval '1 day'; END IF;  -- دوام يعبر منتصف الليل
    v_after := make_interval(mins => COALESCE(v_sched.reminder_minutes_after, 5));

    v_kind := NULL;
    IF NOT v_has_att OR v_att.check_in_time IS NULL THEN
      IF v_local >= v_start - interval '15 minutes' AND v_local < v_start - interval '13 minutes' THEN
        v_kind := 'checkin_soon';
        v_title := '⏰ الدوام يبدأ خلال 15 دقيقة';
        v_body := format('مرحباً %s، دوامك يبدأ الساعة %s. لا تنسَ تسجيل الحضور.',
                         v_emp.full_name, public._ar_time(v_sched.check_in_time));
      ELSIF v_local >= v_start + v_after AND v_local < v_start + v_after + interval '2 minutes' THEN
        v_kind := 'checkin_late';
        v_title := '⚠️ لم تسجّل الحضور بعد';
        v_body := format('بدأ الدوام الساعة %s ولم يُسجَّل حضورك. سجّل بصمة الحضور الآن.',
                         public._ar_time(v_sched.check_in_time));
      END IF;
    ELSIF v_att.check_out_time IS NULL THEN
      IF v_local >= v_end - interval '15 minutes' AND v_local < v_end - interval '13 minutes' THEN
        v_kind := 'checkout_soon';
        v_title := '🔔 الدوام ينتهي خلال 15 دقيقة';
        v_body := format('ينتهي دوامك الساعة %s. لا تنسَ تسجيل الانصراف قبل المغادرة.',
                         public._ar_time(v_sched.check_out_time));
      ELSIF v_local >= v_end + v_after AND v_local < v_end + v_after + interval '2 minutes' THEN
        v_kind := 'checkout_late';
        v_title := '⚠️ لم تسجّل الانصراف';
        v_body := format('انتهى دوامك الساعة %s ولم يُسجَّل انصرافك. سجّل بصمة الانصراف الآن.',
                         public._ar_time(v_sched.check_out_time));
      END IF;
    END IF;

    CONTINUE WHEN v_kind IS NULL;

    INSERT INTO attendance_reminder_log (employee_id, work_date, kind)
    VALUES (v_emp.id, v_today, v_kind)
    ON CONFLICT DO NOTHING;
    CONTINUE WHEN NOT FOUND;

    INSERT INTO notifications (employee_id, title, body, type)
    VALUES (v_emp.id, v_title, v_body, 'attendance');
    v_sent := v_sent + 1;
  END LOOP;

  -- تنظيف السجل القديم
  DELETE FROM attendance_reminder_log WHERE work_date < v_today - 7;

  RETURN v_sent;
END;
$function$;

-- ---------------------------------------------------------------------
-- check_bonus_deduction_amount()  — آخر تعريف: 20261002000000_full_qa_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_bonus_deduction_amount()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_salary numeric;
BEGIN
  SELECT monthly_salary_iqd INTO v_salary FROM employees WHERE id = NEW.employee_id;
  IF NEW.type = 'deduction' AND COALESCE(v_salary, 0) > 0 AND NEW.amount > v_salary THEN
    RAISE EXCEPTION 'مبلغ الخصم (% د.ع) أكبر من راتب الموظف الشهري (% د.ع). تأكد من المبلغ.',
      to_char(NEW.amount, 'FM999,999,999,999'), to_char(v_salary, 'FM999,999,999') USING ERRCODE = '22023';
  END IF;
  IF NEW.amount > 100000000 THEN
    RAISE EXCEPTION 'المبلغ كبير جداً (أكثر من 100,000,000 د.ع). تأكد من المبلغ.' USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- check_employee_basics()  — آخر تعريف: 20261002000000_full_qa_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_employee_basics()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF btrim(COALESCE(NEW.full_name, '')) = '' THEN
    RAISE EXCEPTION 'اسم الموظف مطلوب.' USING ERRCODE = '23514';
  END IF;
  IF NEW.termination_date IS NOT NULL AND NEW.join_date IS NOT NULL AND NEW.termination_date < NEW.join_date THEN
    RAISE EXCEPTION 'تاريخ آخر يوم عمل (%) قبل تاريخ المباشرة (%).', NEW.termination_date, NEW.join_date USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- close_payroll_period(p_month text)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.close_payroll_period(p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_missing text[];
BEGIN
  PERFORM public.require_admin();
  v_p := public.ensure_payroll_period(p_month);
  IF v_p.status = 'closed' THEN
    RETURN jsonb_build_object('success', true, 'message', 'المسير مغلق مسبقاً.');
  END IF;

  SELECT array_agg(e.full_name ORDER BY e.full_name) INTO v_missing
  FROM employees e
  WHERE (e.join_date IS NULL OR e.join_date <= v_p.cutoff_date)
    AND (e.termination_date IS NULL OR e.termination_date >= v_p.start_date)
    AND (e.is_active OR e.termination_date IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = e.id AND s.work_month = p_month);
  IF v_missing IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'لا يمكن إغلاق المسير: يوجد موظفون بدون كشف معتمد.',
                              'missing_employees', to_jsonb(v_missing));
  END IF;

  -- قرارات معلّقة لم تُحسم: تُرحَّل للمسير التالي
  UPDATE payroll_events pe
  SET payroll_month = public.payroll_month_add(p_month, 1), carried_from = COALESCE(pe.carried_from, p_month), updated_at = now()
  FROM (SELECT public.ensure_payroll_period(public.payroll_month_add(p_month, 1))) AS ensure_next
  WHERE pe.payroll_month = p_month AND pe.salary_slip_id IS NULL AND pe.status IN ('pending', 'approved');

  UPDATE payroll_periods SET status = 'closed', closed_at = now(), closed_by = auth.uid() WHERE period_month = p_month;
  RETURN jsonb_build_object('success', true, 'message', format('تم إغلاق مسير %s.', p_month));
END;
$function$;

-- ---------------------------------------------------------------------
-- company_timezone()  — آخر تعريف: 20260924000100_server_side_attendance_and_device_lock.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.company_timezone()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT value #>> '{}' FROM system_settings WHERE key = 'timezone'),
    'Asia/Baghdad'
  );
$function$;

-- ---------------------------------------------------------------------
-- create_default_leave_balance()  — آخر تعريف: 20260924000200_leave_balances_and_decision_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_default_leave_balance()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO leave_balances (employee_id) VALUES (NEW.id)
  ON CONFLICT (employee_id) DO NOTHING;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- create_direct_loan(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_pledge_url text, p_notes text)  — آخر تعريف: 20260925000000_approve_loan_rpc.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_direct_loan(p_employee_id uuid, p_amount numeric, p_months integer, p_first_due date, p_pledge_url text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_base numeric;
  v_loan_id uuid;
BEGIN
  PERFORM public.require_admin();

  IF p_pledge_url IS NULL OR btrim(p_pledge_url) = '' THEN
    RAISE EXCEPTION 'صورة التعهد الخطي إلزامية لكل سلفة.' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM employees WHERE id = p_employee_id AND is_active) THEN
    RAISE EXCEPTION 'الموظف غير موجود أو غير نشط.' USING ERRCODE = 'P0002';
  END IF;

  v_base := public._validate_loan_terms(p_employee_id, p_amount, p_months, p_first_due);

  -- تُدرج معتمدة مباشرة، فلا يُرسل تنبيه "طلب جديد" للمدراء (المُطلق يعمل على 'pending' فقط)
  INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount,
                     pledge_url, status, notes, approved_by, approved_at)
  VALUES (p_employee_id, p_amount, v_base, p_months, p_amount,
          p_pledge_url, 'approved', NULLIF(btrim(COALESCE(p_notes, '')), ''), auth.uid(), now())
  RETURNING id INTO v_loan_id;

  PERFORM public._insert_loan_installments(v_loan_id, p_amount, p_months, p_first_due);

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (
    p_employee_id,
    'تم منحك سلفة مالية جديدة 💸',
    format('تم اعتماد سلفة جديدة لك بقيمة %s د.ع مقسمة على %s أقساط شهرية.',
           to_char(p_amount, 'FM999G999G999'), p_months),
    'loan'
  );

  RETURN v_loan_id;
END;
$function$;

-- ---------------------------------------------------------------------
-- create_employee_secure(p_email text, p_password text, p_full_name text, p_phone text, p_role text, p_branch_id uuid, p_monthly_salary_iqd numeric, p_document_urls text[], p_employee_code text, p_employee_id uuid, p_join_date date, p_department_id uuid)  — آخر تعريف: 20260703000000_security_and_rls_hardening.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_employee_secure(p_email text, p_password text, p_full_name text, p_phone text, p_role text, p_branch_id uuid, p_monthly_salary_iqd numeric, p_document_urls text[], p_employee_code text, p_employee_id uuid DEFAULT NULL::uuid, p_join_date date DEFAULT NULL::date, p_department_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  new_user_id uuid;
  new_identity_id uuid;
  hashed_password text;
  v_caller_id uuid;
BEGIN
  -- التحقق من هوية وصلاحية المنفذ
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح: تتطلب هذه العملية صلاحية مسؤول النظام (Admin).';
  END IF;

  -- التحقق من عدم تكرار البريد الإلكتروني
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = p_email) THEN
    RAISE EXCEPTION 'البريد الإلكتروني مسجل بالفعل لموظف آخر';
  END IF;

  new_user_id := COALESCE(p_employee_id, gen_random_uuid());
  new_identity_id := gen_random_uuid();
  hashed_password := extensions.crypt(p_password, extensions.gen_salt('bf'));

  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    is_super_admin,
    is_sso_user,
    is_anonymous,
    phone,
    phone_confirmed_at,
    created_at,
    updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    new_user_id,
    'authenticated',
    'authenticated',
    p_email,
    hashed_password,
    now(),
    '{"provider": "email", "providers": ["email"]}'::jsonb,
    json_build_object('full_name', p_full_name),
    false,
    false,
    false,
    p_phone,
    CASE WHEN p_phone IS NOT NULL AND p_phone != '' THEN now() ELSE NULL END,
    now(),
    now()
  );

  INSERT INTO auth.identities (
    id,
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    new_identity_id,
    new_user_id::text,
    new_user_id,
    json_build_object(
      'sub', new_user_id::text,
      'email', p_email,
      'email_verified', true,
      'phone_verified', false
    ),
    'email',
    NULL,
    now(),
    now()
  );

  INSERT INTO public.employees (
    id,
    employee_code,
    full_name,
    email,
    phone,
    role,
    branch_id,
    department_id,
    monthly_salary_iqd,
    plain_password,
    is_active,
    must_change_password,
    document_urls,
    join_date,
    created_at
  ) VALUES (
    new_user_id,
    p_employee_code,
    p_full_name,
    p_email,
    NULLIF(p_phone, ''),
    p_role,
    p_branch_id,
    p_department_id,
    p_monthly_salary_iqd,
    p_password,
    true,
    true,
    to_jsonb(COALESCE(p_document_urls, ARRAY[]::text[])),
    COALESCE(p_join_date, CURRENT_DATE),
    now()
  );

  RETURN new_user_id;
END;
$function$;

-- ---------------------------------------------------------------------
-- decide_payroll_event(p_event_id uuid, p_approve boolean, p_reason text)  — آخر تعريف: 20260929000400_audit_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.decide_payroll_event(p_event_id uuid, p_approve boolean, p_reason text DEFAULT NULL::text)
 RETURNS payroll_events
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  e payroll_events%ROWTYPE;
  v_att_id uuid;
  v_branch uuid;
  v_status text := CASE WHEN p_approve THEN 'approved' ELSE 'ignored' END;
  v_labels jsonb := '{"absence":"غياب","late":"تأخير","early_leave":"خروج مبكر","missing_punch":"بصمة ناقصة","overtime":"ساعات إضافية"}';
BEGIN
  PERFORM public.require_admin_or_manager();
  SELECT * INTO e FROM payroll_events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND OR e.status = 'void' THEN
    RAISE EXCEPTION 'الحركة غير موجودة.' USING ERRCODE = 'P0002';
  END IF;
  IF NOT public.is_admin() THEN
    IF e.employee_id = auth.uid() THEN
      RAISE EXCEPTION 'لا يمكنك اتخاذ قرار على حركاتك الخاصة.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.payroll_same_branch(e.employee_id) THEN
      RAISE EXCEPTION 'غير مصرح: الموظف من فرع آخر.' USING ERRCODE = '42501';
    END IF;
  END IF;
  IF e.event_type NOT IN ('absence', 'late', 'early_leave', 'missing_punch', 'overtime') THEN
    RAISE EXCEPTION 'هذه الحركة لا تحتاج قراراً.' USING ERRCODE = '22023';
  END IF;

  -- الغياب والتأخير قرارهما محفوظ في سجل الحضور أيضاً (للتوافق مع الشاشات)
  IF e.event_type IN ('absence', 'late') THEN
    IF e.source = 'no_record' THEN
      SELECT branch_id INTO v_branch FROM employees WHERE id = e.employee_id;
      IF v_branch IS NULL THEN
        RAISE EXCEPTION 'الموظف غير مرتبط بفرع، يرجى ربطه بفرع أولاً.' USING ERRCODE = '22023';
      END IF;
      INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status, deduction_reason)
      VALUES (e.employee_id, v_branch, e.event_date, 'absent', CASE WHEN p_approve THEN 'applied' ELSE 'ignored' END, p_reason)
      RETURNING id INTO v_att_id;
    ELSE
      UPDATE attendance
      SET deduction_status = CASE WHEN p_approve THEN 'applied' ELSE 'ignored' END,
          deduction_applied = p_approve,
          deduction_reason = COALESCE(NULLIF(btrim(p_reason), ''), deduction_reason)
      WHERE id = e.source_id;
    END IF;
    SELECT * INTO e FROM payroll_events
    WHERE employee_id = e.employee_id AND event_date = e.event_date AND event_type = e.event_type
      AND status <> 'void' ORDER BY updated_at DESC LIMIT 1;
  END IF;

  IF e.salary_slip_id IS NULL THEN
    UPDATE payroll_events
    SET status = v_status, decision_reason = NULLIF(btrim(p_reason), ''), decided_by = auth.uid(), decided_at = now(),
        payroll_month = CASE
          WHEN EXISTS (SELECT 1 FROM payroll_periods WHERE period_month = e.payroll_month AND status = 'open')
               AND NOT EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = e.employee_id AND work_month = e.payroll_month)
            THEN e.payroll_month
          ELSE public.payroll_target_month(e.employee_id, e.payroll_month) END,
        updated_at = now()
    WHERE id = e.id
    RETURNING * INTO e;
  ELSE
    UPDATE payroll_events SET decision_reason = NULLIF(btrim(p_reason), ''), decided_by = auth.uid(), decided_at = now()
    WHERE id = e.id;
    PERFORM public._payroll_settle(e, CASE WHEN p_approve THEN e.direction * e.amount ELSE 0 END);
  END IF;

  IF e.event_type <> 'missing_punch' THEN
    INSERT INTO notifications (employee_id, title, body, type)
    VALUES (e.employee_id,
            CASE WHEN p_approve AND e.direction < 0 THEN 'إشعار بخصم ⚠️'
                 WHEN p_approve THEN 'اعتماد ساعات إضافية ✅'
                 ELSE 'إعفاء من الخصم 🎉' END,
            format('%s ليوم %s%s%s',
                   CASE WHEN p_approve AND e.direction < 0 THEN 'تم تطبيق خصم ' || COALESCE(v_labels ->> e.event_type, '')
                        WHEN p_approve THEN 'تم اعتماد ساعات إضافية'
                        ELSE 'تم إعفاؤك من خصم ' || COALESCE(v_labels ->> e.event_type, '') END,
                   e.event_date,
                   CASE WHEN p_approve AND e.amount > 0 THEN format(' بمبلغ %s د.ع', to_char(e.amount, 'FM999,999,999')) ELSE '' END,
                   CASE WHEN NULLIF(btrim(p_reason), '') IS NOT NULL THEN '. السبب: ' || btrim(p_reason) ELSE '' END),
            'attendance');
  END IF;
  RETURN e;
END;
$function$;

-- ---------------------------------------------------------------------
-- distance_meters(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)  — آخر تعريف: 20260924000100_server_side_attendance_and_device_lock.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.distance_meters(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$function$;

-- ---------------------------------------------------------------------
-- employee_shift_hours(p_employee_id uuid)  — آخر تعريف: 20260928000100_admin_only_documents_hourly_leave_balance.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.employee_shift_hours(p_employee_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT NULLIF(
              EXTRACT(EPOCH FROM (
                CASE WHEN ws.check_out_time > ws.check_in_time
                     THEN ws.check_out_time - ws.check_in_time
                     ELSE ws.check_out_time - ws.check_in_time + interval '24 hours' END
              )) / 3600, 0)
     FROM work_schedules ws
     JOIN employees e ON e.id = p_employee_id
     WHERE ws.check_in_time IS NOT NULL AND ws.check_out_time IS NOT NULL
       AND (ws.employee_id = e.id
        OR (ws.employee_id IS NULL AND ws.department_id IS NOT NULL AND ws.department_id = e.department_id)
        OR (ws.employee_id IS NULL AND ws.department_id IS NULL AND ws.branch_id IS NOT NULL AND ws.branch_id = e.branch_id))
     ORDER BY CASE WHEN ws.employee_id IS NOT NULL THEN 0
                   WHEN ws.department_id IS NOT NULL THEN 1 ELSE 2 END,
              ws.created_at DESC
     LIMIT 1),
    8
  )::numeric;
$function$;

-- ---------------------------------------------------------------------
-- employee_work_days(p_employee_id uuid)  — آخر تعريف: 20260928000000_security_hardening_round2.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.employee_work_days(p_employee_id uuid)
 RETURNS integer[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(
    (SELECT ws.work_days
     FROM work_schedules ws
     JOIN employees e ON e.id = p_employee_id
     WHERE ws.employee_id = e.id
        OR (ws.employee_id IS NULL AND ws.department_id IS NOT NULL AND ws.department_id = e.department_id)
        OR (ws.employee_id IS NULL AND ws.department_id IS NULL AND ws.branch_id IS NOT NULL AND ws.branch_id = e.branch_id)
     ORDER BY CASE WHEN ws.employee_id IS NOT NULL THEN 0
                   WHEN ws.department_id IS NOT NULL THEN 1 ELSE 2 END,
              ws.created_at DESC
     LIMIT 1),
    ARRAY[0, 1, 2, 3, 4, 6]
  );
$function$;

-- ---------------------------------------------------------------------
-- ensure_payroll_period(p_month text)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_payroll_period(p_month text)
 RETURNS payroll_periods
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row payroll_periods%ROWTYPE;
  v_prev payroll_periods%ROWTYPE;
  v_first text;
  v_first_day date := (p_month || '-01')::date;
  v_last int := EXTRACT(DAY FROM (v_first_day + interval '1 month - 1 day'))::int;
  v_policy jsonb := public.payroll_policy();
  v_cutoff int := LEAST(COALESCE((v_policy ->> 'cutoff_day')::int, 26), v_last);
  v_pay int := LEAST(COALESCE((v_policy ->> 'payment_day')::int, 30), v_last);
  v_start date;
BEGIN
  SELECT * INTO v_row FROM payroll_periods WHERE period_month = p_month;
  IF FOUND THEN RETURN v_row; END IF;

  SELECT min(period_month) INTO v_first FROM payroll_periods;
  IF v_first IS NULL THEN
    v_start := v_first_day;                       -- أول مسير في النظام يبدأ من أول الشهر
  ELSIF p_month < v_first THEN
    RAISE EXCEPTION 'هذا الشهر قبل بداية نظام المسيرات (%).', v_first USING ERRCODE = '22023';
  ELSE
    v_prev := public.ensure_payroll_period(public.payroll_month_add(p_month, -1));
    v_start := v_prev.cutoff_date + 1;
  END IF;

  INSERT INTO payroll_periods (period_month, start_date, cutoff_date, payment_date)
  VALUES (p_month, v_start, make_date(EXTRACT(YEAR FROM v_first_day)::int, EXTRACT(MONTH FROM v_first_day)::int, v_cutoff),
          make_date(EXTRACT(YEAR FROM v_first_day)::int, EXTRACT(MONTH FROM v_first_day)::int, v_pay))
  ON CONFLICT (period_month) DO NOTHING
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    SELECT * INTO v_row FROM payroll_periods WHERE period_month = p_month;
  END IF;
  RETURN v_row;
END;
$function$;

-- ---------------------------------------------------------------------
-- fmt_days(v numeric)  — آخر تعريف: 20260928000100_admin_only_documents_hourly_leave_balance.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fmt_days(v numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN v = trunc(v) THEN trunc(v)::text ELSE rtrim(rtrim(round(v, 2)::text, '0'), '.') END;
$function$;

-- ---------------------------------------------------------------------
-- get_active_announcements(p_limit integer)  — آخر تعريف: 20260928000400_announcements_period_and_on_leave.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_active_announcements(p_limit integer DEFAULT 20)
 RETURNS SETOF announcements
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT a.*
  FROM announcements a
  WHERE auth.uid() IS NOT NULL
    AND a.starts_at <= now()
    AND (a.ends_at IS NULL OR a.ends_at > now())
    AND public.announcement_targets(a, auth.uid())
  ORDER BY a.is_pinned DESC, a.starts_at DESC
  LIMIT GREATEST(COALESCE(p_limit, 20), 1);
$function$;

-- ---------------------------------------------------------------------
-- get_database_size()  — آخر تعريف: 20260924000000_lock_down_rpc_views_and_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_database_size()
 RETURNS TABLE(db_size bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin_or_manager();
  RETURN QUERY SELECT pg_database_size(current_database())::bigint AS db_size;
END;
$function$;

-- ---------------------------------------------------------------------
-- get_database_table_sizes()  — آخر تعريف: 20260924000000_lock_down_rpc_views_and_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_database_table_sizes()
 RETURNS TABLE(table_name text, row_count bigint, total_bytes bigint, pretty_size text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin_or_manager();

  RETURN QUERY
  SELECT
    c.relname::text AS table_name,
    c.reltuples::bigint AS row_count,
    pg_total_relation_size(c.oid)::bigint AS total_bytes,
    pg_size_pretty(pg_total_relation_size(c.oid))::text AS pretty_size
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
  ORDER BY pg_total_relation_size(c.oid) DESC;
END;
$function$;

-- ---------------------------------------------------------------------
-- get_effective_work_schedule(p_employee_id uuid)  — آخر تعريف: 20260924000100_server_side_attendance_and_device_lock.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_effective_work_schedule(p_employee_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF work_schedules
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp_id uuid := COALESCE(p_employee_id, auth.uid());
BEGIN
  IF auth.uid() IS NOT NULL AND v_emp_id <> auth.uid()
     AND NOT (public.is_admin() OR public.is_manager()) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT ws.*
  FROM work_schedules ws
  JOIN employees e ON e.id = v_emp_id
  WHERE ws.employee_id = e.id
     OR (ws.employee_id IS NULL AND ws.department_id IS NOT NULL
         AND ws.department_id = e.department_id)
     OR (ws.employee_id IS NULL AND ws.department_id IS NULL
         AND ws.branch_id IS NOT NULL AND ws.branch_id = e.branch_id)
  ORDER BY
    CASE
      WHEN ws.employee_id IS NOT NULL THEN 0
      WHEN ws.department_id IS NOT NULL THEN 1
      ELSE 2
    END,
    ws.created_at DESC
  LIMIT 1;
END;
$function$;

-- ---------------------------------------------------------------------
-- get_employee_directory()  — آخر تعريف: 20260924000000_lock_down_rpc_views_and_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_employee_directory()
 RETURNS TABLE(id uuid, employee_code text, full_name text, phone text, email text, avatar_url text, role text, department_id uuid, department_name text, branch_id uuid, branch_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT e.id, e.employee_code, e.full_name, e.phone, e.email, e.avatar_url,
         e.role, e.department_id, d.name, e.branch_id, b.name
  FROM employees e
  LEFT JOIN departments d ON d.id = e.department_id
  LEFT JOIN branches b ON b.id = e.branch_id
  WHERE e.is_active = true
  ORDER BY e.full_name;
END;
$function$;

-- ---------------------------------------------------------------------
-- get_late_today()  — آخر تعريف: 20260929000200_late_today.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_late_today()
 RETURNS TABLE(employee_id uuid, full_name text, avatar_url text, branch_name text, check_in_time timestamp with time zone, late_minutes integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT e.id, e.full_name, e.avatar_url, b.name, a.check_in_time,
         COALESCE(GREATEST(floor(public.payroll_local_minutes(a.check_in_time)
                                 - public.payroll_time_minutes(ws.check_in_time)), 0)::integer, 0)
  FROM attendance a
  JOIN employees e ON e.id = a.employee_id AND e.is_active
  LEFT JOIN branches b ON b.id = e.branch_id
  LEFT JOIN LATERAL public.payroll_schedule(e.id) ws ON true
  WHERE a.work_date = v_today
    AND a.status = 'late'
    AND a.check_in_time IS NOT NULL
  ORDER BY a.check_in_time;
END;
$function$;

-- ---------------------------------------------------------------------
-- get_leave_balance(p_employee_id uuid, p_on date, p_exclude uuid)  — آخر تعريف: 20260928000200_leave_policy.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_leave_balance(p_employee_id uuid DEFAULT NULL::uuid, p_on date DEFAULT NULL::date, p_exclude uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp uuid := COALESCE(p_employee_id, auth.uid());
  v_tz text := public.company_timezone();
  v_on date := COALESCE(p_on, (now() AT TIME ZONE public.company_timezone())::date);
  v_year_start date := date_trunc('year', v_on)::date;
  v_month_start date := date_trunc('month', v_on)::date;
  v_policy jsonb := public.leave_policy();
  v_lb leave_balances%ROWTYPE;
  v_annual numeric; v_sick numeric; v_hours numeric;
  r record;
BEGIN
  IF auth.uid() IS NOT NULL AND v_emp <> auth.uid() AND NOT (public.is_admin() OR public.is_manager()) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_lb FROM leave_balances WHERE employee_id = v_emp;
  v_annual := COALESCE(v_lb.annual_entitlement, (v_policy ->> 'default_annual')::numeric, 21);
  v_sick   := COALESCE(v_lb.sick_entitlement, (v_policy ->> 'default_sick')::numeric, 15);
  v_hours  := COALESCE(v_lb.hourly_monthly_hours, (v_policy ->> 'hourly_monthly_hours')::numeric, 8);

  SELECT
    COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'annual' AND lr.status = 'approved'), 0) AS annual_used,
    COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'annual' AND lr.status = 'pending'), 0) AS annual_pending,
    COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'sick' AND lr.status = 'approved'), 0) AS sick_used,
    COALESCE(SUM(public.leave_request_days(lr)) FILTER (WHERE lr.leave_type = 'sick' AND lr.status = 'pending'), 0) AS sick_pending
  INTO r
  FROM leave_requests lr
  WHERE lr.employee_id = v_emp
    AND lr.id IS DISTINCT FROM p_exclude
    AND NOT COALESCE(lr.is_hourly, false)
    AND (lr.start_date AT TIME ZONE v_tz)::date >= v_year_start
    AND (lr.start_date AT TIME ZONE v_tz)::date < (v_year_start + interval '1 year')::date;

  RETURN jsonb_build_object(
    'year', EXTRACT(YEAR FROM v_on)::int,
    'month', to_char(v_on, 'YYYY-MM'),
    'annual', jsonb_build_object('entitlement', v_annual, 'used', r.annual_used, 'pending', r.annual_pending,
                                 'left', v_annual - r.annual_used - r.annual_pending),
    'sick', jsonb_build_object('entitlement', v_sick, 'used', r.sick_used, 'pending', r.sick_pending,
                               'left', v_sick - r.sick_used - r.sick_pending),
    'hourly', (
      SELECT jsonb_build_object(
        'allowance_hours', v_hours,
        'used_hours', COALESCE(SUM(public.leave_request_hours(lr)) FILTER (WHERE lr.status = 'approved'), 0),
        'pending_hours', COALESCE(SUM(public.leave_request_hours(lr)) FILTER (WHERE lr.status = 'pending'), 0),
        'left_hours', v_hours - COALESCE(SUM(public.leave_request_hours(lr)) FILTER (WHERE lr.status IN ('approved', 'pending')), 0))
      FROM leave_requests lr
      WHERE lr.employee_id = v_emp
        AND lr.id IS DISTINCT FROM p_exclude
        AND lr.is_hourly
        AND (lr.start_date AT TIME ZONE v_tz)::date >= v_month_start
        AND (lr.start_date AT TIME ZONE v_tz)::date < (v_month_start + interval '1 month')::date
    )
  );
END;
$function$;

-- ---------------------------------------------------------------------
-- get_my_payroll_preview()  — آخر تعريف: 20260929000500_user_flow_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_payroll_preview()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_me uuid := auth.uid();
  v_month text;
  v_p payroll_periods%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;
  v_month := public.payroll_natural_month((now() AT TIME ZONE public.company_timezone())::date);
  IF v_month IS NULL THEN
    RETURN NULL;
  END IF;
  v_p := public.ensure_payroll_period(v_month);
  PERFORM public.sync_payroll_period(v_month, v_me);

  RETURN jsonb_build_object(
    'period', to_jsonb(v_p),
    'summary', public.payroll_employee_summary(v_me, v_month),
    'events', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'event_date', pe.event_date, 'event_type', pe.event_type, 'minutes', pe.minutes, 'days', pe.days,
               'amount', pe.amount, 'direction', pe.direction, 'status', pe.status, 'notes', pe.notes,
               'carried_from', pe.carried_from)
             ORDER BY pe.event_date, pe.event_type)
      FROM payroll_events pe
      WHERE pe.employee_id = v_me AND pe.payroll_month = v_month AND pe.status <> 'void'
        AND (pe.amount > 0 OR pe.event_type IN ('missing_punch', 'paid_leave'))), '[]'::jsonb)
  );
END;
$function$;

-- ---------------------------------------------------------------------
-- get_on_leave_now()  — آخر تعريف: 20260928000400_announcements_period_and_on_leave.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_on_leave_now()
 RETURNS TABLE(employee_id uuid, full_name text, avatar_url text, branch_name text, is_hourly boolean, from_date date, to_date date, start_hour time without time zone, end_hour time without time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

-- ---------------------------------------------------------------------
-- get_orphan_storage_candidates()  — آخر تعريف: 20260924000000_lock_down_rpc_views_and_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_orphan_storage_candidates()
 RETURNS TABLE(bucket_id text, file_path text, file_size bigint, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();

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
$function$;

-- ---------------------------------------------------------------------
-- get_payroll_events(p_month text, p_employee_id uuid)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_payroll_events(p_month text, p_employee_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF payroll_events
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT pe.* FROM payroll_events pe
  WHERE (public.is_admin() OR public.is_manager() OR pe.employee_id = auth.uid())
    AND pe.payroll_month = p_month
    AND (p_employee_id IS NULL OR pe.employee_id = p_employee_id)
    AND pe.status <> 'void'
  ORDER BY pe.event_date, pe.event_type;
$function$;

-- ---------------------------------------------------------------------
-- get_payroll_run(p_month text)  — آخر تعريف: 20260929000500_user_flow_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_payroll_run(p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_rows jsonb;
BEGIN
  PERFORM public.require_admin();
  IF p_month !~ '^\d{4}-\d{2}$' THEN
    RAISE EXCEPTION 'صيغة الشهر غير صحيحة.' USING ERRCODE = '22023';
  END IF;

  -- أشهر قبل نظام المسيرات: عرض الكشوف القديمة كما حُفظت (بدون حساب)
  IF p_month < (SELECT min(period_month) FROM payroll_periods) THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'employee_id', e.id, 'full_name', e.full_name, 'branch_id', e.branch_id, 'branch_name', b.name,
             'join_date', e.join_date, 'termination_date', e.termination_date, 'is_active', e.is_active,
             'period_days', 0, 'employed_days', 0, 'monthly_salary', COALESCE(e.monthly_salary_iqd, 0),
             'daily_rate', COALESCE(e.monthly_salary_iqd, 0) / 30.0, 'minute_rate', 0, 'shift_minutes', 480,
             'basic', s.basic_salary, 'earnings', s.allowances, 'bonuses', s.allowances, 'overtime', 0,
             'deductions', s.deductions, 'attendance_deductions', 0, 'loans', s.loans_deduction, 'net', s.net_salary,
             'pending_count', 0, 'missing_punches', 0, 'absence_days', 0, 'late_minutes', 0, 'early_minutes', 0,
             'overtime_minutes', 0, 'paid_leave_days', 0, 'unpaid_leave_days', 0,
             'slip', jsonb_build_object('id', s.id, 'basic_salary', s.basic_salary, 'allowances', s.allowances,
                                        'deductions', s.deductions, 'loans_deduction', s.loans_deduction,
                                        'net_salary', s.net_salary, 'created_at', s.created_at, 'legacy', true))
           ORDER BY e.full_name), '[]'::jsonb)
    INTO v_rows
    FROM salary_slips s
    JOIN employees e ON e.id = s.employee_id
    LEFT JOIN branches b ON b.id = e.branch_id
    WHERE s.work_month = p_month;

    RETURN jsonb_build_object(
      'period', jsonb_build_object(
        'period_month', p_month,
        'start_date', to_char((p_month || '-01')::date, 'YYYY-MM-DD'),
        'cutoff_date', to_char((p_month || '-01')::date + interval '1 month - 1 day', 'YYYY-MM-DD'),
        'payment_date', NULL, 'status', 'closed', 'legacy', true,
        'archived', EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month)),
      'rows', v_rows);
  END IF;

  v_p := public.ensure_payroll_period(p_month);
  PERFORM public.sync_payroll_period(p_month);

  SELECT COALESCE(jsonb_agg(
           public.payroll_employee_summary(e.id, p_month)
             || jsonb_build_object('full_name', e.full_name, 'branch_id', e.branch_id, 'branch_name', b.name,
                                   'join_date', e.join_date, 'termination_date', e.termination_date,
                                   'is_active', e.is_active)
           ORDER BY e.full_name), '[]'::jsonb)
  INTO v_rows
  FROM employees e
  LEFT JOIN branches b ON b.id = e.branch_id
  WHERE (
      (e.join_date IS NULL OR e.join_date <= v_p.cutoff_date)
      AND (e.termination_date IS NULL OR e.termination_date >= v_p.start_date)
      AND (e.is_active OR e.termination_date IS NOT NULL)
    )
    -- من له كشف معتمد في هذا الشهر يظهر دائماً (حتى لو عُطّل حسابه لاحقاً)
    OR EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = e.id AND s.work_month = p_month);

  RETURN jsonb_build_object(
    'period', to_jsonb(v_p) || jsonb_build_object('archived', EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month)),
    'rows', v_rows
  );
END;
$function$;

-- ---------------------------------------------------------------------
-- get_pending_payroll_decisions()  — آخر تعريف: 20260929000400_audit_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_pending_payroll_decisions()
 RETURNS TABLE(id uuid, employee_id uuid, full_name text, branch_id uuid, branch_name text, event_date date, event_type text, minutes numeric, days numeric, amount numeric, direction smallint, payroll_month text, carried_from text, status text, source text, source_id uuid, notes text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  v_month text;
BEGIN
  PERFORM public.require_admin_or_manager();
  FOR v_month IN SELECT period_month FROM payroll_periods WHERE status = 'open' LOOP
    PERFORM public.sync_payroll_period(v_month);
  END LOOP;
  PERFORM public.sync_payroll_period(public.payroll_natural_month((now() AT TIME ZONE public.company_timezone())::date));

  RETURN QUERY
  SELECT pe.id, pe.employee_id, e.full_name, e.branch_id, b.name, pe.event_date, pe.event_type, pe.minutes, pe.days,
         pe.amount, pe.direction, pe.payroll_month, pe.carried_from, pe.status, pe.source, pe.source_id, pe.notes
  FROM payroll_events pe
  JOIN employees e ON e.id = pe.employee_id
  LEFT JOIN branches b ON b.id = e.branch_id
  JOIN payroll_periods p ON p.period_month = pe.payroll_month AND p.status = 'open'
  WHERE pe.status = 'pending'
    AND (public.is_admin() OR (pe.employee_id <> auth.uid() AND public.payroll_same_branch(pe.employee_id)))
    AND pe.event_type IN ('absence', 'late', 'early_leave', 'missing_punch', 'overtime')
  ORDER BY pe.event_date DESC, e.full_name;
END;
$function$;

-- ---------------------------------------------------------------------
-- get_storage_stats()  — آخر تعريف: 20260924000000_lock_down_rpc_views_and_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_storage_stats()
 RETURNS TABLE(bucket_name text, total_size bigint, file_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'storage'
AS $function$
BEGIN
    PERFORM public.require_admin_or_manager();

    RETURN QUERY
    SELECT
        b.id::TEXT AS bucket_name,
        COALESCE(SUM(
            COALESCE(
                (o.metadata->>'size')::BIGINT,
                (o.metadata->>'contentLength')::BIGINT,
                (o.user_metadata->>'size')::BIGINT,
                0
            )
        ), 0)::BIGINT AS total_size,
        COUNT(o.id)::BIGINT AS file_count
    FROM storage.buckets b
    LEFT JOIN storage.objects o ON o.bucket_id = b.id
    GROUP BY b.id
    ORDER BY b.id;
END;
$function$;

-- ---------------------------------------------------------------------
-- hard_delete_employee(p_employee_id uuid)  — آخر تعريف: 20260701000000_fix_rpcs_and_functions.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.hard_delete_employee(p_employee_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.safe_delete_employee(p_employee_id);
END;
$function$;

-- ---------------------------------------------------------------------
-- invoke_push_notification()  — آخر تعريف: 20261005000000_capture_dashboard_objects.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.invoke_push_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM net.http_post(
    url := 'https://jgjlmddphhncatrhqrej.supabase.co/functions/v1/push-notification',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := json_build_object('record', row_to_json(NEW))::jsonb
  );
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- is_admin()  — آخر تعريف: 20260520000001_indexes_rls.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM employees 
    WHERE id = auth.uid() AND role = 'admin' AND is_active = true
  );
END;
$function$;

-- ---------------------------------------------------------------------
-- is_manager()  — آخر تعريف: 20260520000001_indexes_rls.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_manager()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM employees 
    WHERE id = auth.uid() AND role = 'manager' AND is_active = true
  );
END;
$function$;

-- ---------------------------------------------------------------------
-- keep_payroll_policy_keys()  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.keep_payroll_policy_keys()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cutoff int;
BEGIN
  IF NEW.key <> 'payroll_policy' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' THEN
    NEW.value := COALESCE(OLD.value, '{}'::jsonb) || COALESCE(NEW.value, '{}'::jsonb);
  END IF;
  v_cutoff := COALESCE((NEW.value ->> 'cutoff_day')::int, 26);
  NEW.value := NEW.value || jsonb_build_object('cycle_start_day', v_cutoff + 1, 'cycle_end_day', v_cutoff);
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- keep_status_on_early_checkout()  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.keep_status_on_early_checkout()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'half_day' AND OLD.status IN ('present', 'late')
     AND OLD.check_out_time IS NULL AND NEW.check_out_time IS NOT NULL THEN
    NEW.status := OLD.status;
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- leave_policy()  — آخر تعريف: 20260928000200_leave_policy.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leave_policy()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT value FROM system_settings WHERE key = 'leave_policy'), '{}'::jsonb);
$function$;

-- ---------------------------------------------------------------------
-- leave_request_days(lr leave_requests)  — آخر تعريف: 20260928000200_leave_policy.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leave_request_days(lr leave_requests)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN lr.is_hourly THEN 0::numeric
    ELSE (
      SELECT count(*)::numeric
      FROM generate_series(
        (lr.start_date AT TIME ZONE public.company_timezone())::date,
        (lr.end_date AT TIME ZONE public.company_timezone())::date,
        interval '1 day') AS d
      WHERE EXTRACT(DOW FROM d)::integer = ANY (public.employee_work_days(lr.employee_id))
    )
  END;
$function$;

-- ---------------------------------------------------------------------
-- leave_request_hours(lr leave_requests)  — آخر تعريف: 20260928000200_leave_policy.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leave_request_hours(lr leave_requests)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN lr.is_hourly
    THEN round(GREATEST(EXTRACT(EPOCH FROM COALESCE(lr.end_hour - lr.start_hour, lr.end_date - lr.start_date)) / 3600, 0)::numeric, 2)
    ELSE 0::numeric END;
$function$;

-- ---------------------------------------------------------------------
-- manual_purge_month_data(p_year integer, p_month integer, p_notifications boolean, p_tracking boolean, p_absences boolean)  — آخر تعريف: 20261002000000_full_qa_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.manual_purge_month_data(p_year integer, p_month integer, p_notifications boolean DEFAULT false, p_tracking boolean DEFAULT false, p_absences boolean DEFAULT false)
 RETURNS TABLE(notifications_deleted integer, tracking_deleted integer, stops_deleted integer, violations_deleted integer, absences_deleted integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_start_date date;
  v_end_date date;
  v_notif_count integer := 0;
  v_track_count integer := 0;
  v_stops_count integer := 0;
  v_viol_count integer := 0;
  v_absent_count integer := 0;
BEGIN
  PERFORM public.require_admin();

  v_start_date := make_date(p_year, p_month, 1);
  v_end_date := (v_start_date + INTERVAL '1 month' - INTERVAL '1 day')::date;

  -- قفل مالي: سجلات الحضور تُحسب منها خصومات الرواتب؛ ما تنحذف إلا إذا كل مسير يغطي
  -- أيام هذا الشهر مغلق (رواتبه معتمدة). قبل: كانت تنحذف فوراً فيصير المتأخر "غائباً" يوماً كاملاً.
  IF p_absences AND EXISTS (
    SELECT 1 FROM payroll_periods pp
    WHERE pp.start_date <= v_end_date AND pp.cutoff_date >= v_start_date AND pp.status <> 'closed'
  ) THEN
    RAISE EXCEPTION 'لا يمكن حذف سجلات الحضور لهذا الشهر: مسير الرواتب الذي يغطيه ما زال مفتوحاً. اعتمد الرواتب وأغلق المسير أولاً.'
      USING ERRCODE = '42501';
  END IF;

  IF p_notifications THEN
    WITH del AS (
      DELETE FROM public.notifications
      WHERE created_at::date >= v_start_date AND created_at::date <= v_end_date
      RETURNING id
    )
    SELECT count(*)::integer INTO v_notif_count FROM del;
  END IF;

  IF p_tracking THEN
    WITH del_stops AS (
      DELETE FROM public.tracked_stops
      WHERE start_time::date >= v_start_date AND start_time::date <= v_end_date
      RETURNING id
    ),
    del_viol AS (
      DELETE FROM public.geofence_violations
      WHERE timestamp::date >= v_start_date AND timestamp::date <= v_end_date
      RETURNING id
    ),
    del_track AS (
      DELETE FROM public.location_tracking
      WHERE timestamp::date >= v_start_date AND timestamp::date <= v_end_date
      RETURNING id
    )
    SELECT
      (SELECT count(*)::integer FROM del_track),
      (SELECT count(*)::integer FROM del_stops),
      (SELECT count(*)::integer FROM del_viol)
    INTO v_track_count, v_stops_count, v_viol_count;
  END IF;

  IF p_absences THEN
    WITH del_att AS (
      DELETE FROM public.attendance
      WHERE work_date >= v_start_date AND work_date <= v_end_date
      RETURNING id
    )
    SELECT count(*)::integer INTO v_absent_count FROM del_att;
  END IF;

  RETURN QUERY SELECT v_notif_count, v_track_count, v_stops_count, v_viol_count, v_absent_count;
END;
$function$;

-- ---------------------------------------------------------------------
-- notify_admins_of_new_leave_request()  — آخر تعريف: 20260920000300_notify_admins_on_new_requests.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_admins_of_new_leave_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

-- ---------------------------------------------------------------------
-- notify_admins_of_new_loan_request()  — آخر تعريف: 20260930000500_loan_requests_notify_admins_only.sql
-- ---------------------------------------------------------------------
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

-- ---------------------------------------------------------------------
-- notify_employee_on_leave_decision()  — آخر تعريف: 20260924000200_leave_balances_and_decision_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_employee_on_leave_decision()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

-- ---------------------------------------------------------------------
-- notify_employee_on_loan_decision()  — آخر تعريف: 20260924000200_leave_balances_and_decision_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_employee_on_loan_decision()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

-- ---------------------------------------------------------------------
-- one_pending_loan_request()  — آخر تعريف: 20261004000100_employee_loan_request_over_half_salary.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.one_pending_loan_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'pending' AND EXISTS (
    SELECT 1 FROM loans WHERE employee_id = NEW.employee_id AND status = 'pending' AND id <> NEW.id
  ) THEN
    RAISE EXCEPTION 'لديك طلب سلفة قيد المراجعة. انتظر قرار الإدارة قبل تقديم طلب جديد.' USING ERRCODE = '23505';
  END IF;

  -- طلبات المستخدمين عبر التطبيق/الموقع فقط (العمليات الداخلية والإعداد تمر)
  IF NEW.status = 'pending' AND current_user IN ('authenticated', 'anon') THEN
    IF EXISTS (SELECT 1 FROM loans WHERE employee_id = NEW.employee_id AND status = 'approved' AND remaining_amount > 0) THEN
      RAISE EXCEPTION 'لديك سلفة جارية لم تُسدَّد بعد. تقدر تطلب سلفة جديدة بعد إكمال سدادها.' USING ERRCODE = '55000';
    END IF;
    IF NEW.amount > 100000000 THEN
      RAISE EXCEPTION 'المبلغ كبير جداً (أكثر من 100,000,000 د.ع). تأكد من المبلغ.' USING ERRCODE = '22023';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- pay_loan_installment(p_installment_id uuid, p_amount numeric, p_method text, p_note text)  — آخر تعريف: 20260927000000_flexible_installment_payment.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pay_loan_installment(p_installment_id uuid, p_amount numeric, p_method text DEFAULT 'cash'::text, p_note text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_inst loan_installments%ROWTYPE;
  v_loan loans%ROWTYPE;
  v_remaining numeric;
BEGIN
  PERFORM public.require_admin();

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'يرجى إدخال مبلغ سداد أكبر من الصفر.' USING ERRCODE = '22023';
  END IF;
  IF p_method NOT IN ('cash', 'salary_deduction') THEN
    RAISE EXCEPTION 'طريقة السداد غير صحيحة.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_inst FROM loan_installments WHERE id = p_installment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'القسط غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF v_inst.is_paid THEN
    RAISE EXCEPTION 'هذا القسط مسدد مسبقاً.' USING ERRCODE = '55000';
  END IF;

  SELECT * INTO v_loan FROM loans WHERE id = v_inst.loan_id FOR UPDATE;
  IF v_loan.status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'السلفة غير معتمدة.' USING ERRCODE = '55000';
  END IF;

  v_remaining := v_loan.amount - COALESCE((
    SELECT SUM(amount) FROM loan_installments WHERE loan_id = v_loan.id AND is_paid
  ), 0);
  IF p_amount > v_remaining THEN
    RAISE EXCEPTION 'المبلغ أكبر من المتبقي على السلفة (%).', to_char(v_remaining, 'FM999,999,999')
      USING ERRCODE = '22023';
  END IF;

  UPDATE loan_installments
  SET amount = round(p_amount),
      is_paid = true,
      paid_at = now(),
      payment_type = p_method,
      payment_note = NULLIF(btrim(COALESCE(p_note, '')), '')
  WHERE id = p_installment_id;

  SELECT remaining_amount INTO v_remaining FROM loans WHERE id = v_loan.id;

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (
    v_loan.employee_id,
    'تسجيل دفعة سلفة 💸',
    format('تم تسجيل دفعة بمبلغ %s د.ع من سلفتك. المتبقي: %s د.ع.',
           to_char(round(p_amount), 'FM999,999,999'), to_char(v_remaining, 'FM999,999,999')),
    'loan'
  );

  RETURN v_remaining;
END;
$function$;

-- ---------------------------------------------------------------------
-- payroll_basic_salary(p_employee_id uuid, p_month text)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_basic_salary(p_employee_id uuid, p_month text)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN e.future_salary_iqd IS NOT NULL AND e.future_salary_month IS NOT NULL
         AND p_month >= substr(e.future_salary_month, 1, 7)
      THEN e.future_salary_iqd
    ELSE COALESCE(e.monthly_salary_iqd, 0)
  END
  FROM employees e WHERE e.id = p_employee_id;
$function$;

-- ---------------------------------------------------------------------
-- payroll_daily_rate(p_employee_id uuid, p_month text)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_daily_rate(p_employee_id uuid, p_month text)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(public.payroll_basic_salary(p_employee_id, p_month), 0) / 30;
$function$;

-- ---------------------------------------------------------------------
-- payroll_employee_summary(p_employee_id uuid, p_month text)  — آخر تعريف: 20260929000400_audit_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_employee_summary(p_employee_id uuid, p_month text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_emp employees%ROWTYPE;
  v_month_basic numeric;
  v_daily numeric;
  v_from date;
  v_to date;
  v_period_days int;
  v_employed_days int;
  v_basic numeric;
  v_ev record;
  v_loans numeric;
  v_slip salary_slips%ROWTYPE;
  v_exit_balance numeric := 0;
BEGIN
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = p_month;
  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  v_month_basic := public.payroll_basic_salary(p_employee_id, p_month);
  v_daily := v_month_basic / 30;

  v_from := GREATEST(v_p.start_date, COALESCE(v_emp.join_date, v_p.start_date));
  v_to := LEAST(v_p.cutoff_date, COALESCE(v_emp.termination_date, v_p.cutoff_date));
  v_period_days := v_p.cutoff_date - v_p.start_date + 1;
  v_employed_days := GREATEST(v_to - v_from + 1, 0);
  -- فترة كاملة = الراتب كاملاً؛ جزئية (مباشرة/انتهاء خدمة) = أجر اليوم × الأيام (بحد 30)
  v_basic := CASE WHEN v_employed_days >= v_period_days THEN v_month_basic
                  ELSE round(v_daily * LEAST(v_employed_days, 30)) END;

  SELECT
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = 1), 0) AS earnings,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = -1), 0) AS deductions,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND direction = -1 AND event_type IN ('absence', 'late', 'early_leave', 'unpaid_leave')), 0) AS attendance_deductions,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND event_type = 'overtime'), 0) AS overtime,
    COALESCE(sum(amount) FILTER (WHERE status = 'approved' AND event_type = 'bonus'), 0) AS bonuses,
    count(*) FILTER (WHERE status = 'pending' AND event_type <> 'missing_punch') AS pending,
    count(*) FILTER (WHERE status = 'pending' AND event_type = 'missing_punch') AS missing_punches,
    COALESCE(sum(days) FILTER (WHERE status = 'approved' AND event_type = 'absence'), 0) AS absence_days,
    COALESCE(sum(minutes) FILTER (WHERE status = 'approved' AND event_type = 'late'), 0) AS late_minutes,
    COALESCE(sum(minutes) FILTER (WHERE status = 'approved' AND event_type = 'early_leave'), 0) AS early_minutes,
    COALESCE(sum(minutes) FILTER (WHERE status = 'approved' AND event_type = 'overtime'), 0) AS overtime_minutes,
    COALESCE(sum(days) FILTER (WHERE event_type = 'paid_leave'), 0) AS paid_leave_days,
    COALESCE(sum(days) FILTER (WHERE status = 'approved' AND event_type = 'unpaid_leave'), 0) AS unpaid_leave_days
  INTO v_ev
  FROM payroll_events
  WHERE employee_id = p_employee_id AND payroll_month = p_month AND status <> 'void';

  SELECT COALESCE(sum(li.amount), 0) INTO v_loans
  FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid
    AND COALESCE(l.payment_method, '') <> 'cash'           -- السلفة النقدية تُسدَّد نقداً لا من الراتب
    AND li.due_date BETWEEN v_p.start_date AND v_p.cutoff_date;

  -- ترك العمل خلال المسير: ما يبقى من السلف بعد أقساط هذا المسير (تنبيه للإدارة)
  IF v_emp.termination_date IS NOT NULL AND v_emp.termination_date <= v_p.cutoff_date THEN
    SELECT COALESCE(sum(li.amount), 0) INTO v_exit_balance
    FROM loan_installments li JOIN loans l ON l.id = li.loan_id
    WHERE l.employee_id = p_employee_id AND l.status = 'approved' AND NOT li.is_paid AND li.due_date > v_p.cutoff_date;
  END IF;

  SELECT * INTO v_slip FROM salary_slips WHERE employee_id = p_employee_id AND work_month = p_month;

  RETURN jsonb_build_object(
    'employee_id', p_employee_id,
    'period_days', v_period_days,
    'employed_days', v_employed_days,
    'monthly_salary', v_month_basic,
    'daily_rate', round(v_daily, 4),
    'minute_rate', round(v_daily / public.payroll_shift_minutes(p_employee_id), 6),
    'shift_minutes', public.payroll_shift_minutes(p_employee_id),
    'basic', v_basic,
    'earnings', round(v_ev.earnings),
    'bonuses', round(v_ev.bonuses),
    'overtime', round(v_ev.overtime),
    'deductions', round(v_ev.deductions),
    'attendance_deductions', round(v_ev.attendance_deductions),
    'loans', v_loans,
    -- التقريب لأقرب دينار على المجموع (لا يوم بيوم)
    'net', v_basic + round(v_ev.earnings) - round(v_ev.deductions) - v_loans,
    'loan_balance_after_exit', v_exit_balance,
    'pending_count', v_ev.pending,
    'missing_punches', v_ev.missing_punches,
    'absence_days', v_ev.absence_days,
    'late_minutes', v_ev.late_minutes,
    'early_minutes', v_ev.early_minutes,
    'overtime_minutes', v_ev.overtime_minutes,
    'paid_leave_days', v_ev.paid_leave_days,
    'unpaid_leave_days', v_ev.unpaid_leave_days,
    'slip', CASE WHEN v_slip.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_slip.id, 'basic_salary', v_slip.basic_salary, 'allowances', v_slip.allowances,
      'deductions', v_slip.deductions, 'loans_deduction', v_slip.loans_deduction,
      'net_salary', v_slip.net_salary, 'created_at', v_slip.created_at,
      'legacy', NOT v_slip.computed_by_engine) END
  );
END;
$function$;

-- ---------------------------------------------------------------------
-- payroll_hourly_leave_overlap(p_employee_id uuid, p_date date, p_from numeric, p_to numeric)  — آخر تعريف: 20260929000400_audit_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_hourly_leave_overlap(p_employee_id uuid, p_date date, p_from numeric, p_to numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(sum(GREATEST(LEAST(p_to, l_end) - GREATEST(p_from, l_start), 0)), 0)
  FROM (
    SELECT COALESCE(public.payroll_time_minutes(lr.start_hour), public.payroll_local_minutes(lr.start_date)) AS l_start,
           COALESCE(public.payroll_time_minutes(lr.end_hour), public.payroll_local_minutes(lr.end_date)) AS l_end
    FROM leave_requests lr
    WHERE lr.employee_id = p_employee_id AND lr.status = 'approved' AND COALESCE(lr.is_hourly, false)
      AND (lr.start_date AT TIME ZONE public.company_timezone())::date = p_date
  ) x
  WHERE p_to > p_from;
$function$;

-- ---------------------------------------------------------------------
-- payroll_legacy_slip(p_employee_id uuid, p_month text)  — آخر تعريف: 20260929000400_audit_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_legacy_slip(p_employee_id uuid, p_month text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT id FROM salary_slips
  WHERE employee_id = p_employee_id AND work_month = p_month AND NOT computed_by_engine;
$function$;

-- ---------------------------------------------------------------------
-- payroll_legacy_slip(p_employee_id uuid, p_month text, p_date date)  — آخر تعريف: 20260929000400_audit_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_legacy_slip(p_employee_id uuid, p_month text, p_date date)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT id FROM salary_slips
  WHERE employee_id = p_employee_id AND work_month = p_month AND NOT computed_by_engine
    AND p_date <= (created_at AT TIME ZONE public.company_timezone())::date;
$function$;

-- ---------------------------------------------------------------------
-- payroll_local_minutes(p_ts timestamp with time zone)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_local_minutes(p_ts timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXTRACT(HOUR FROM (p_ts AT TIME ZONE public.company_timezone())) * 60
       + EXTRACT(MINUTE FROM (p_ts AT TIME ZONE public.company_timezone()));
$function$;

-- ---------------------------------------------------------------------
-- payroll_month_add(p_month text, p_n integer)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_month_add(p_month text, p_n integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT to_char((p_month || '-01')::date + make_interval(months => p_n), 'YYYY-MM');
$function$;

-- ---------------------------------------------------------------------
-- payroll_natural_month(p_date date)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_natural_month(p_date date)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_first payroll_periods%ROWTYPE;
  v_month text := to_char(p_date, 'YYYY-MM');
  v_p payroll_periods%ROWTYPE;
BEGIN
  SELECT * INTO v_first FROM payroll_periods ORDER BY period_month LIMIT 1;
  IF NOT FOUND OR p_date < v_first.start_date THEN
    RETURN NULL;
  END IF;
  v_p := public.ensure_payroll_period(v_month);
  IF p_date <= v_p.cutoff_date THEN
    RETURN v_month;                               -- 1 → 26: مسير نفس الشهر
  END IF;
  RETURN public.payroll_month_add(v_month, 1);    -- 27 → نهاية الشهر: مسير الشهر التالي
END;
$function$;

-- ---------------------------------------------------------------------
-- payroll_policy()  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_policy()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT value FROM system_settings WHERE key = 'payroll_policy'), '{}'::jsonb);
$function$;

-- ---------------------------------------------------------------------
-- payroll_same_branch(p_employee_id uuid)  — آخر تعريف: 20260929000400_audit_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_same_branch(p_employee_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM employees me JOIN employees t ON t.id = p_employee_id
    WHERE me.id = auth.uid() AND me.branch_id IS NOT NULL AND t.branch_id = me.branch_id
  );
$function$;

-- ---------------------------------------------------------------------
-- payroll_schedule(p_employee_id uuid)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_schedule(p_employee_id uuid)
 RETURNS work_schedules
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT ws.*
  FROM work_schedules ws
  JOIN employees e ON e.id = p_employee_id
  WHERE ws.employee_id = e.id
     OR (ws.employee_id IS NULL AND ws.department_id IS NOT NULL AND ws.department_id = e.department_id)
     OR (ws.employee_id IS NULL AND ws.department_id IS NULL AND ws.branch_id IS NOT NULL AND ws.branch_id = e.branch_id)
  ORDER BY CASE WHEN ws.employee_id IS NOT NULL THEN 0 WHEN ws.department_id IS NOT NULL THEN 1 ELSE 2 END,
           ws.created_at DESC
  LIMIT 1;
$function$;

-- ---------------------------------------------------------------------
-- payroll_shift_minutes(p_employee_id uuid)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_shift_minutes(p_employee_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(NULLIF(public.employee_shift_hours(p_employee_id), 0), 8) * 60;
$function$;

-- ---------------------------------------------------------------------
-- payroll_target_month(p_employee_id uuid, p_natural text)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_target_month(p_employee_id uuid, p_natural text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_month text := p_natural;
  v_p payroll_periods%ROWTYPE;
BEGIN
  FOR i IN 1..36 LOOP
    v_p := public.ensure_payroll_period(v_month);
    IF v_p.status = 'open'
       AND NOT EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = p_employee_id AND work_month = v_month)
       AND NOT EXISTS (SELECT 1 FROM archived_months WHERE work_month = v_month) THEN
      RETURN v_month;
    END IF;
    v_month := public.payroll_month_add(v_month, 1);
  END LOOP;
  RETURN v_month;
END;
$function$;

-- ---------------------------------------------------------------------
-- payroll_time_minutes(p_t time without time zone)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.payroll_time_minutes(p_t time without time zone)
 RETURNS numeric
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT EXTRACT(HOUR FROM p_t) * 60 + EXTRACT(MINUTE FROM p_t);
$function$;

-- ---------------------------------------------------------------------
-- perform_daily_cleanup()  — آخر تعريف: 20260929000400_audit_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.perform_daily_cleanup()
 RETURNS TABLE(expired_file_path text, expired_bucket_id text, file_record_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  archive_record RECORD;
  tracking_archive_days INT;
BEGIN
  PERFORM public.require_admin_or_system();

  -- 0. ترقية وتفعيل الراتب المستقبلي للموظفين المستحقين
  UPDATE public.employees 
  SET 
    monthly_salary_iqd = future_salary_iqd,
    future_salary_iqd = NULL,
    future_salary_month = NULL
  WHERE future_salary_month IS NOT NULL 
    AND future_salary_iqd IS NOT NULL 
    AND future_salary_month <= TO_CHAR(NOW(), 'YYYY-MM-DD');

  -- 1. الحصول على مدة أرشفة التتبع من إعدادات النظام (الافتراضي 180 يوماً / 6 أشهر)
  SELECT COALESCE((value->>'tracking_archive_days')::INT, 180) INTO tracking_archive_days
  FROM public.system_settings WHERE key = 'archive_policy';

  -- 2. حذف بيانات التتبع والموقع القديمة
  DELETE FROM public.location_tracking WHERE timestamp < (NOW() - (tracking_archive_days || ' days')::INTERVAL);
  DELETE FROM public.tracked_stops WHERE start_time < (NOW() - (tracking_archive_days || ' days')::INTERVAL);
  DELETE FROM public.geofence_violations WHERE timestamp < (NOW() - (tracking_archive_days || ' days')::INTERVAL);

  -- 3. تنظيف الإشعارات القديمة تلقائياً
  DELETE FROM public.notifications WHERE is_read = true AND created_at < (NOW() - INTERVAL '30 days');
  DELETE FROM public.notifications WHERE created_at < (NOW() - INTERVAL '90 days');

  -- 4. إرسال إشعارات التنبيه للأدمن عن موظف مجدول للحذف قبل الحذف بأسبوع
  INSERT INTO public.notifications (employee_id, title, body, type, is_read, created_at)
  SELECT 
    COALESCE(archived_by, (SELECT id FROM public.employees WHERE role = 'admin' LIMIT 1)),
    'تنبيه: حذف مجدول لموظف خلال أسبوع',
    'تنبيه: سيتم حذف حساب الموظف (' || full_name || ') وإخفاء بياناته الشخصية (تبقى سجلاته المالية) في تاريخ ' || TO_CHAR(scheduled_deletion_date, 'YYYY-MM-DD') || '.',
    'system',
    false,
    NOW()
  FROM public.archived_employees
  WHERE archive_type = 'scheduled_deletion' 
    AND scheduled_deletion_date BETWEEN NOW() AND NOW() + INTERVAL '7 days'
    AND NOT EXISTS (
      SELECT 1 FROM public.notifications 
      WHERE notifications.employee_id = COALESCE(archived_employees.archived_by, (SELECT id FROM employees WHERE role = 'admin' LIMIT 1))
        AND notifications.title = 'تنبيه: حذف مجدول لموظف خلال أسبوع'
        AND notifications.created_at > NOW() - INTERVAL '1 day'
    );

  -- 5. معالجة الحذف المجدول للموظفين المؤرشفين
  FOR archive_record IN 
    SELECT employee_id, full_name FROM public.archived_employees 
    WHERE archive_type = 'scheduled_deletion' AND scheduled_deletion_date <= NOW()
  LOOP
    -- لا يُحذف صف الموظف: الحذف كان يمسح كشوف رواتبه وسلفه وحضوره (ON DELETE CASCADE)
    PERFORM public._anonymize_employee(archive_record.employee_id);
    UPDATE public.archived_employees 
    SET 
      archive_type = 'permanent', 
      notes = COALESCE(notes, '') || ' - تم التنفيذ التلقائي للحذف المجدول بتاريخ ' || TO_CHAR(NOW(), 'YYYY-MM-DD') || '.'
    WHERE employee_id = archive_record.employee_id;
  END LOOP;

  -- 6. إرجاع قائمة الملفات المنتهية في سلة المحذوفات بالمجلدات الصحيحة
  RETURN QUERY 
  SELECT 
    df.file_path as expired_file_path, 
    CASE 
      WHEN df.file_type = 'avatar' THEN 'avatars'::TEXT
      WHEN df.file_type = 'document' THEN 'employee-documents'::TEXT
      WHEN df.file_type = 'pledge' THEN 'loan-pledges'::TEXT
      WHEN df.file_type = 'logo' THEN 'company-logos'::TEXT
      ELSE 'employee-documents'::TEXT
    END as expired_bucket_id,
    df.id as file_record_id
  FROM public.deleted_files df
  WHERE df.scheduled_deletion_date <= NOW() AND df.restored_at IS NULL;
END;
$function$;

-- ---------------------------------------------------------------------
-- protect_attendance_decisions()  — آخر تعريف: 20260929000500_user_flow_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_attendance_decisions()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  -- دوال السيرفر (البصمة، decide_payroll_event) تعمل بصلاحية المالك ولها فحوصاتها
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  -- الموظف العادي: صلاحيات الجدول (RLS) تمنعه أصلاً من الكتابة
  IF NOT public.is_manager() THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.deduction_status IS NOT DISTINCT FROM OLD.deduction_status
     AND NEW.deduction_reason IS NOT DISTINCT FROM OLD.deduction_reason
     AND NEW.deduction_applied IS NOT DISTINCT FROM OLD.deduction_applied
     AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;
  IF NEW.employee_id = auth.uid() THEN
    RAISE EXCEPTION 'لا يمكنك اتخاذ قرار على حضورك.' USING ERRCODE = '42501';
  END IF;
  IF NOT public.payroll_same_branch(NEW.employee_id) THEN
    RAISE EXCEPTION 'غير مصرح: الموظف من فرع آخر.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- protect_attendance_times()  — آخر تعريف: 20260928000000_security_hardening_round2.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_attendance_times()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  IF NEW.employee_id IS DISTINCT FROM OLD.employee_id
     OR NEW.work_date IS DISTINCT FROM OLD.work_date
     OR NEW.check_in_time IS DISTINCT FROM OLD.check_in_time
     OR NEW.check_out_time IS DISTINCT FROM OLD.check_out_time
     OR NEW.check_in_lat IS DISTINCT FROM OLD.check_in_lat
     OR NEW.check_in_lng IS DISTINCT FROM OLD.check_in_lng
     OR NEW.check_out_lat IS DISTINCT FROM OLD.check_out_lat
     OR NEW.check_out_lng IS DISTINCT FROM OLD.check_out_lng
     OR NEW.is_mock_detected IS DISTINCT FROM OLD.is_mock_detected
     OR NEW.branch_id IS DISTINCT FROM OLD.branch_id
  THEN
    RAISE EXCEPTION 'غير مصرح: تعديل أوقات البصمة وموقعها للأدمن فقط.' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- protect_employee_columns()  — آخر تعريف: 20260928000100_admin_only_documents_hourly_leave_balance.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_employee_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.role IS DISTINCT FROM OLD.role
     OR NEW.is_active IS DISTINCT FROM OLD.is_active
     OR NEW.branch_id IS DISTINCT FROM OLD.branch_id
     OR NEW.department_id IS DISTINCT FROM OLD.department_id
     OR NEW.employee_code IS DISTINCT FROM OLD.employee_code
     OR NEW.full_name IS DISTINCT FROM OLD.full_name
     OR NEW.email IS DISTINCT FROM OLD.email
     OR NEW.join_date IS DISTINCT FROM OLD.join_date
     OR NEW.monthly_salary_iqd IS DISTINCT FROM OLD.monthly_salary_iqd
     OR NEW.future_salary_iqd IS DISTINCT FROM OLD.future_salary_iqd
     OR NEW.future_salary_month IS DISTINCT FROM OLD.future_salary_month
     OR NEW.device_id_lock IS DISTINCT FROM OLD.device_id_lock
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR (NEW.must_change_password AND NOT COALESCE(OLD.must_change_password, false))
  THEN
    RAISE EXCEPTION 'غير مصرح: هذه البيانات يعدّلها قسم الموارد البشرية فقط.' USING ERRCODE = '42501';
  END IF;

  -- المستمسكات: إضافة فقط. كل القديمة تبقى، والجديدة من مجلد الموظف نفسه.
  IF NEW.document_urls IS DISTINCT FROM OLD.document_urls THEN
    IF NOT (COALESCE(NEW.document_urls, '[]'::jsonb) @> COALESCE(OLD.document_urls, '[]'::jsonb))
       OR EXISTS (
         SELECT 1
         FROM jsonb_array_elements_text(COALESCE(NEW.document_urls, '[]'::jsonb)) AS u(url)
         WHERE NOT (COALESCE(OLD.document_urls, '[]'::jsonb) ? u.url)
           AND position('/employee-documents/' || OLD.id::text || '/' IN u.url) = 0
       )
    THEN
      RAISE EXCEPTION 'غير مصرح: تقدر تضيف مستمسكات فقط، والحذف أو التعديل من قسم الموارد البشرية.' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- protect_leave_decisions()  — آخر تعريف: 20260929000500_user_flow_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_leave_decisions()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.employee_id = auth.uid()
       AND (NEW.start_date AT TIME ZONE public.company_timezone())::date < v_today - 30 THEN
      RAISE EXCEPTION 'لا يمكن طلب إجازة لتاريخ مضى عليه أكثر من 30 يوماً. راجع الإدارة.' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    -- الموظف يلغي طلبه المعلّق فقط
    IF NEW.employee_id = auth.uid() THEN
      IF OLD.status = 'pending' AND NEW.status = 'cancelled' THEN
        RETURN NEW;
      END IF;
      RAISE EXCEPTION 'لا يمكنك اعتماد أو رفض طلب إجازتك.' USING ERRCODE = '42501';
    END IF;
    IF NOT public.payroll_same_branch(NEW.employee_id) THEN
      RAISE EXCEPTION 'غير مصرح: الموظف من فرع آخر.' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- publish_announcement(p_title text, p_content text, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_target text, p_branch_id uuid, p_employee_ids uuid[], p_pinned boolean)  — آخر تعريف: 20260928000400_announcements_period_and_on_leave.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.publish_announcement(p_title text, p_content text, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_ends_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_target text DEFAULT 'all'::text, p_branch_id uuid DEFAULT NULL::uuid, p_employee_ids uuid[] DEFAULT NULL::uuid[], p_pinned boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

-- ---------------------------------------------------------------------
-- punch_attendance(p_type text, p_latitude double precision, p_longitude double precision, p_device_id text, p_is_mocked boolean, p_client_time timestamp with time zone, p_accuracy double precision)  — آخر تعريف: 20261004000000_punch_rejects_low_accuracy.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.punch_attendance(p_type text, p_latitude double precision, p_longitude double precision, p_device_id text DEFAULT NULL::text, p_is_mocked boolean DEFAULT false, p_client_time timestamp with time zone DEFAULT NULL::timestamp with time zone, p_accuracy double precision DEFAULT NULL::double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- هامش تسامح لفرق حساب المسافة بين الجهاز والسيرفر
  c_distance_tolerance_m constant double precision := 10;
  c_offline_max_age constant interval := interval '48 hours';
  -- أسوأ دقة GPS مقبولة (الموقع التقريبي بأندرويد 12+/iOS 14+ يبعد كيلومترات)
  c_max_accuracy_m constant double precision := 100;

  v_uid uuid := auth.uid();
  v_emp employees%ROWTYPE;
  v_branch branches%ROWTYPE;
  v_sched work_schedules%ROWTYPE;
  v_att attendance%ROWTYPE;
  v_tz text := public.company_timezone();
  v_now timestamptz := now();
  v_time timestamptz;
  v_offline boolean := false;
  v_local timestamp;
  v_work_date date;
  v_distance double precision;
  v_deadline timestamp;
  v_early_limit timestamp;
  v_status text;
  v_has_row boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول.' USING ERRCODE = '42501';
  END IF;
  IF p_type NOT IN ('check_in', 'check_out') THEN
    RAISE EXCEPTION 'نوع بصمة غير صالح: %', p_type USING ERRCODE = '22023';
  END IF;
  IF p_latitude IS NULL OR p_longitude IS NULL THEN
    RAISE EXCEPTION 'الموقع الجغرافي مطلوب.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_emp FROM employees WHERE id = v_uid;
  IF NOT FOUND OR NOT v_emp.is_active THEN
    RAISE EXCEPTION 'هذا الحساب معطل حالياً.' USING ERRCODE = '42501';
  END IF;

  -- الجهاز المعتمد (إن كان قفل الجهاز مفعّلاً)
  IF COALESCE(v_emp.device_id_lock, '') NOT IN ('', 'force_lock_active')
     AND p_device_id IS DISTINCT FROM v_emp.device_id_lock THEN
    RAISE EXCEPTION 'هذا الجهاز غير معتمد للبصمة. راجع الإدارة لاعتماد جهازك.'
      USING ERRCODE = '42501';
  END IF;

  IF p_is_mocked THEN
    INSERT INTO mock_gps_attempts (employee_id, latitude, longitude, app_used)
    VALUES (v_uid, p_latitude, p_longitude, 'punch_attendance');
    RETURN jsonb_build_object('ok', false, 'code', 'mock_gps',
      'message', 'تم رصد موقع وهمي. تم تسجيل المحاولة وإبلاغ الإدارة.');
  END IF;

  -- الوقت: وقت السيرفر، أو وقت الجهاز لبصمة أوفلاين ضمن حدود معقولة
  IF p_client_time IS NULL THEN
    v_time := v_now;
  ELSE
    IF p_client_time > v_now + interval '5 minutes' THEN
      RETURN jsonb_build_object('ok', false, 'code', 'clock_in_future',
        'message', 'وقت البصمة المحفوظة في المستقبل — ساعة الجهاز غير مضبوطة.');
    END IF;
    IF p_client_time < v_now - c_offline_max_age THEN
      RETURN jsonb_build_object('ok', false, 'code', 'offline_too_old',
        'message', 'البصمة المحفوظة أقدم من 48 ساعة ولا يمكن قبولها. راجع الإدارة.');
    END IF;
    v_time := p_client_time;
    v_offline := true;
  END IF;

  v_local := v_time AT TIME ZONE v_tz;
  v_work_date := v_local::date;

  -- المسافة من الفرع
  SELECT * INTO v_branch FROM branches WHERE id = v_emp.branch_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'code', 'no_branch',
      'message', 'لم يتم تعيين فرع لحسابك. راجع الإدارة.');
  END IF;

  -- دقة الموقع: فرع نطاقه أوسع من 100 م يتحمّل دقة بقدر نطاقه.
  -- النسخ القديمة من التطبيق ما ترسل الدقة (NULL) فتمر كما كانت.
  IF p_accuracy IS NOT NULL AND p_accuracy > GREATEST(c_max_accuracy_m, v_branch.radius_meters) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'low_accuracy',
      'accuracy_m', round(p_accuracy::numeric),
      'message', format('دقة الموقع ضعيفة (± %s م). فعّل «الموقع الدقيق» وانتظر لحظات بمكان مفتوح ثم حاول مرة ثانية.',
                        round(p_accuracy::numeric)));
  END IF;

  v_distance := public.distance_meters(p_latitude, p_longitude, v_branch.latitude, v_branch.longitude);
  IF v_distance > v_branch.radius_meters + c_distance_tolerance_m THEN
    RETURN jsonb_build_object('ok', false, 'code', 'out_of_range',
      'distance_m', round(v_distance::numeric, 1),
      'message', format('أنت خارج نطاق الفرع الجغرافي. المتبقي لتصل للفرع: %s متر.',
                        round((v_distance - v_branch.radius_meters)::numeric, 1)));
  END IF;

  SELECT * INTO v_sched FROM public.get_effective_work_schedule(v_uid);

  SELECT * INTO v_att FROM attendance
  WHERE employee_id = v_uid AND work_date = v_work_date
  FOR UPDATE;
  v_has_row := FOUND;

  IF p_type = 'check_in' THEN
    IF v_has_row AND v_att.check_in_time IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'code', 'already_checked_in',
        'message', 'لقد قمت بتسجيل بصمة الحضور مسبقاً لهذا اليوم!');
    END IF;

    -- متأخر إذا بعد موعد الحضور + فترة السماح (الافتراضي 08:30 + 15 دقيقة)
    -- (مقارنة timestamp وليس time حتى لا يلف الوقت بعد منتصف الليل)
    v_deadline := v_work_date + COALESCE(v_sched.check_in_time, time '08:30')
                  + make_interval(mins => COALESCE(v_sched.grace_period_minutes, 15));
    v_status := CASE WHEN v_local > v_deadline THEN 'late' ELSE 'present' END;

    IF v_has_row THEN
      -- سطر موجود (انصراف سُجّل قبل الحضور بالخطأ)
      UPDATE attendance
      SET check_in_time = v_time, check_in_lat = p_latitude, check_in_lng = p_longitude,
          check_in_offline = v_offline, status = v_status
      WHERE id = v_att.id
      RETURNING * INTO v_att;
    ELSE
      INSERT INTO attendance (employee_id, branch_id, work_date, status,
                              check_in_time, check_in_lat, check_in_lng, check_in_offline)
      VALUES (v_uid, v_branch.id, v_work_date, v_status,
              v_time, p_latitude, p_longitude, v_offline)
      RETURNING * INTO v_att;
    END IF;
  ELSE
    IF v_has_row AND v_att.check_out_time IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'code', 'already_checked_out',
        'message', 'لقد قمت بتسجيل بصمة الانصراف مسبقاً لهذا اليوم!');
    END IF;

    IF NOT v_has_row THEN
      -- انصراف بدون حضور: يُحتسب نصف يوم
      INSERT INTO attendance (employee_id, branch_id, work_date, status,
                              check_out_time, check_out_lat, check_out_lng, check_out_offline)
      VALUES (v_uid, v_branch.id, v_work_date, 'half_day',
              v_time, p_latitude, p_longitude, v_offline)
      RETURNING * INTO v_att;
    ELSE
      -- خروج مبكر بأكثر من 15 دقيقة يُحتسب نصف يوم (الافتراضي 16:30)
      v_early_limit := v_work_date + COALESCE(v_sched.check_out_time, time '16:30')
                       - interval '15 minutes';
      v_status := CASE
        WHEN v_local < v_early_limit THEN 'half_day'
        ELSE v_att.status
      END;

      UPDATE attendance
      SET check_out_time = v_time, check_out_lat = p_latitude, check_out_lng = p_longitude,
          check_out_offline = v_offline, status = v_status
      WHERE id = v_att.id
      RETURNING * INTO v_att;
    END IF;
  END IF;

  -- نقطة تتبع + إشعار نجاح للموظف
  INSERT INTO location_tracking (employee_id, latitude, longitude, is_moving, timestamp)
  VALUES (v_uid, p_latitude, p_longitude, false, v_time);

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (
    v_uid,
    CASE WHEN p_type = 'check_out' THEN 'بصمة انصراف ناجحة 🔴'
         WHEN v_att.status = 'late' THEN 'بصمة حضور متأخرة 🟠'
         ELSE 'بصمة حضور ناجحة 🟢' END,
    CASE p_type
      WHEN 'check_in' THEN CASE WHEN v_att.status = 'late'
        THEN format('تم تسجيل حضورك في فرع (%s) بعد بداية الدوام، ويُحتسب تأخيراً.', v_branch.name)
        ELSE format('تم تسجيل حضورك اليوم بنجاح في فرع (%s). دواماً موفقاً!', v_branch.name) END
      ELSE format('تم تسجيل انصرافك بنجاح من فرع (%s). يعطيك العافية!', v_branch.name)
    END,
    'attendance'
  );

  RETURN jsonb_build_object(
    'ok', true,
    'status', v_att.status,
    'work_date', v_att.work_date,
    'check_in_time', v_att.check_in_time,
    'check_out_time', v_att.check_out_time,
    'offline', v_offline,
    'distance_m', round(v_distance::numeric, 1)
  );
END;
$function$;

-- ---------------------------------------------------------------------
-- purge_old_location_tracking()  — آخر تعريف: 20260920000200_enable_pg_cron_scheduling.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_old_location_tracking()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_deleted INTEGER;
BEGIN
    DELETE FROM location_tracking
    WHERE timestamp < (now() - INTERVAL '90 days');
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted;
END;
$function$;

-- ---------------------------------------------------------------------
-- record_audit_log()  — آخر تعريف: 20260920000000_document_rpcs_and_add_audit_log.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_audit_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_actor_id     UUID;
    v_actor_email  TEXT;
    v_changed_cols TEXT[];
    v_row_id       UUID;
BEGIN
    -- من هو الفاعل؟
    v_actor_id := auth.uid();
    IF v_actor_id IS NOT NULL THEN
        SELECT email INTO v_actor_email FROM auth.users WHERE id = v_actor_id;
    END IF;

    -- التقاط row_id بحسب نوع الجدول
    IF TG_OP = 'DELETE' THEN
        v_row_id := (OLD.id)::UUID;
    ELSE
        v_row_id := (NEW.id)::UUID;
    END IF;

    -- الأعمدة التي تغيّرت (فقط للـ UPDATE)
    IF TG_OP = 'UPDATE' THEN
        SELECT array_agg(key) INTO v_changed_cols
        FROM jsonb_each(to_jsonb(OLD)) o
        WHERE o.value IS DISTINCT FROM (to_jsonb(NEW) -> o.key);
    END IF;

    -- إدراج السطر في audit_log
    INSERT INTO audit_log (
        table_name, row_id, action, actor_id, actor_email,
        old_data, new_data, changed_columns
    ) VALUES (
        TG_TABLE_NAME,
        v_row_id,
        TG_OP,
        v_actor_id,
        v_actor_email,
        CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) ELSE NULL END,
        v_changed_cols
    );

    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

-- ---------------------------------------------------------------------
-- refresh_orphan_candidates_cache()  — آخر تعريف: 20260920000200_enable_pg_cron_scheduling.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.refresh_orphan_candidates_cache()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_inserted INTEGER := 0;
BEGIN
    -- Placeholder: implementation depends on the exact shape of
    -- get_orphan_storage_candidates(); wire up when that RPC exists.
    -- For now we just clear the stale cache.
    TRUNCATE orphan_storage_candidates_cache;
    RETURN v_inserted;
END;
$function$;

-- ---------------------------------------------------------------------
-- register_device_login(p_device_id text, p_model text, p_os_version text, p_legacy_device_id text)  — آخر تعريف: 20260924000100_server_side_attendance_and_device_lock.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_device_login(p_device_id text, p_model text DEFAULT NULL::text, p_os_version text DEFAULT NULL::text, p_legacy_device_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_emp employees%ROWTYPE;
  v_lock text;
  v_has_devices boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول.' USING ERRCODE = '42501';
  END IF;
  IF COALESCE(p_device_id, '') = '' THEN
    RAISE EXCEPTION 'معرّف الجهاز مطلوب.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_emp FROM employees WHERE id = v_uid FOR UPDATE;
  IF NOT FOUND OR NOT v_emp.is_active THEN
    RAISE EXCEPTION 'هذا الحساب معطل حالياً.' USING ERRCODE = '42501';
  END IF;
  v_lock := COALESCE(v_emp.device_id_lock, '');

  -- ترحيل المعرّف القديم إلى الجديد
  IF COALESCE(p_legacy_device_id, '') <> '' AND p_legacy_device_id <> p_device_id THEN
    IF v_lock = p_legacy_device_id THEN
      UPDATE employees SET device_id_lock = p_device_id WHERE id = v_uid;
      v_lock := p_device_id;
    END IF;
    DELETE FROM employee_devices
    WHERE employee_id = v_uid AND device_id = p_device_id
      AND EXISTS (SELECT 1 FROM employee_devices
                  WHERE employee_id = v_uid AND device_id = p_legacy_device_id);
    UPDATE employee_devices SET device_id = p_device_id
    WHERE employee_id = v_uid AND device_id = p_legacy_device_id;
  END IF;

  -- الحالة 1: القفل غير مفعّل → نسجّل الجهاز الحالي فقط
  IF v_lock = '' THEN
    DELETE FROM employee_devices WHERE employee_id = v_uid AND device_id <> p_device_id;
    INSERT INTO employee_devices (employee_id, device_id, model, os_version, is_approved, approved_at)
    VALUES (v_uid, p_device_id, p_model, p_os_version, true, now())
    ON CONFLICT (employee_id, device_id) DO UPDATE
      SET model = EXCLUDED.model, os_version = EXCLUDED.os_version,
          is_approved = true, approved_at = COALESCE(employee_devices.approved_at, now());
    RETURN jsonb_build_object('ok', true);
  END IF;

  SELECT EXISTS (SELECT 1 FROM employee_devices WHERE employee_id = v_uid) INTO v_has_devices;

  -- الحالة 2: أول دخول، أو 3: الأدمن طلب إعادة الضبط → اعتماد هذا الجهاز
  IF NOT v_has_devices OR v_lock = 'force_lock_active' THEN
    DELETE FROM employee_devices WHERE employee_id = v_uid;
    INSERT INTO employee_devices (employee_id, device_id, model, os_version, is_approved, approved_at)
    VALUES (v_uid, p_device_id, p_model, p_os_version, true, now());
    UPDATE employees SET device_id_lock = p_device_id WHERE id = v_uid;
    RETURN jsonb_build_object('ok', true);
  END IF;

  -- الحالة 4: قفل على جهاز محدد
  IF v_lock = p_device_id AND EXISTS (
    SELECT 1 FROM employee_devices
    WHERE employee_id = v_uid AND device_id = p_device_id AND is_approved
  ) THEN
    RETURN jsonb_build_object('ok', true);
  END IF;

  -- جهاز غير معتمد: طلب ربط جديد + إشعار للموظف والإدارة
  INSERT INTO employee_devices (employee_id, device_id, model, os_version, is_approved)
  VALUES (v_uid, p_device_id, p_model, p_os_version, false)
  ON CONFLICT (employee_id, device_id) DO NOTHING;

  INSERT INTO notifications (employee_id, title, body, type)
  SELECT id, n.title, n.body, 'device'
  FROM (
    SELECT v_uid AS id,
           'محاولة خرق أمني للدخول ⚠️' AS title,
           format('تمت محاولة تسجيل دخول إلى حسابك (%s) من جهاز جديد (%s). تم تقديم طلب ربط جهاز جديد وبانتظار موافقة الإدارة.',
                  v_emp.full_name, COALESCE(p_model, 'غير معروف')) AS body
    UNION ALL
    SELECT e.id,
           'طلب اعتماد جهاز جديد 📱',
           format('الموظف (%s) حاول الدخول من جهاز غير معتمد (%s).',
                  v_emp.full_name, COALESCE(p_model, 'غير معروف'))
    FROM employees e
    WHERE e.role = 'admin' AND e.is_active AND e.id <> v_uid
  ) n
  WHERE NOT EXISTS (
    SELECT 1 FROM notifications x
    WHERE x.employee_id = n.id AND x.title = n.title AND x.body = n.body
      AND x.created_at > now() - interval '1 hour'
  );

  RETURN jsonb_build_object('ok', false, 'code', 'device_locked');
END;
$function$;

-- ---------------------------------------------------------------------
-- reject_future_attendance()  — آخر تعريف: 20261002000000_full_qa_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reject_future_attendance()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  -- إدخالات المستخدمين فقط (البصمة من السيرفر تستعمل وقت السيرفر أصلاً)
  -- رسالة عربية قبل قيد chk_attendance_out_after_in
  IF NEW.check_out_time IS NOT NULL AND NEW.check_in_time IS NOT NULL AND NEW.check_out_time < NEW.check_in_time THEN
    RAISE EXCEPTION 'وقت الانصراف لازم يكون بعد وقت الحضور.' USING ERRCODE = '23514';
  END IF;
  IF current_user IN ('authenticated', 'anon')
     AND (TG_OP = 'INSERT' OR NEW.work_date IS DISTINCT FROM OLD.work_date)
     AND NEW.work_date > (now() AT TIME ZONE public.company_timezone())::date THEN
    RAISE EXCEPTION 'لا يمكن تسجيل حضور أو غياب ليوم لم يأتِ بعد (%).', NEW.work_date USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- reject_negative_salary_slip()  — آخر تعريف: 20260928000300_no_negative_salary_slip.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reject_negative_salary_slip()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.net_salary < 0 THEN
    RAISE EXCEPTION 'صافي الراتب بالسالب (%). الخصومات وأقساط السلف أكبر من الراتب: أجّل القسط أو سجّل دفعة جزئية من صفحة السلف ثم أعد الاعتماد.',
      to_char(NEW.net_salary, 'FM999,999,999')
      USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- reopen_payroll_period(p_month text, p_reason text)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reopen_payroll_period(p_month text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  IF COALESCE(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'اكتب سبب إعادة فتح المسير.' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM archived_months WHERE work_month = p_month) THEN
    RAISE EXCEPTION 'هذا الشهر مؤرشف ولا يمكن فتحه.' USING ERRCODE = '42501';
  END IF;
  UPDATE payroll_periods
  SET status = 'open', reopened_at = now(), reopened_by = auth.uid(), reopen_reason = btrim(p_reason)
  WHERE period_month = p_month AND status = 'closed';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'المسير غير موجود أو مفتوح مسبقاً.' USING ERRCODE = 'P0002';
  END IF;
  INSERT INTO audit_log (table_name, action, actor_id, new_data)
  VALUES ('payroll_periods', 'UPDATE', auth.uid(), jsonb_build_object('period_month', p_month, 'reopened', true, 'reason', btrim(p_reason)));
END;
$function$;

-- ---------------------------------------------------------------------
-- request_account_deletion()  — آخر تعريف: 20260924000400_account_deletion_request.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_account_deletion()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_name text;
  v_sent integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول.' USING ERRCODE = '42501';
  END IF;

  SELECT full_name INTO v_name FROM employees WHERE id = v_uid;

  INSERT INTO notifications (employee_id, title, body, type)
  SELECT e.id,
         'طلب حذف حساب موظف ⚠️',
         format('الموظف (%s) قدم طلباً لحذف حسابه. يرجى مراجعة حسابه المالي وإجراءات الإغلاق من لوحة الإدارة.',
                COALESCE(v_name, 'غير معروف')),
         'system'
  FROM employees e
  WHERE e.role = 'admin' AND e.is_active AND e.id <> v_uid
    -- طلب واحد في اليوم يكفي
    AND NOT EXISTS (
      SELECT 1 FROM notifications n
      WHERE n.employee_id = e.id
        AND n.title = 'طلب حذف حساب موظف ⚠️'
        AND n.body LIKE '%(' || COALESCE(v_name, 'غير معروف') || ')%'
        AND n.created_at > now() - interval '1 day'
    );
  GET DIAGNOSTICS v_sent = ROW_COUNT;

  RETURN v_sent;
END;
$function$;

-- ---------------------------------------------------------------------
-- require_admin()  — آخر تعريف: 20260924000000_lock_down_rpc_views_and_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.require_admin()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح: هذه العملية لمسؤول النظام (Admin) فقط.'
      USING ERRCODE = '42501';
  END IF;
END;
$function$;

-- ---------------------------------------------------------------------
-- require_admin_or_manager()  — آخر تعريف: 20260924000000_lock_down_rpc_views_and_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.require_admin_or_manager()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT (public.is_admin() OR public.is_manager()) THEN
    RAISE EXCEPTION 'غير مصرح: هذه العملية للإدارة فقط.'
      USING ERRCODE = '42501';
  END IF;
END;
$function$;

-- ---------------------------------------------------------------------
-- require_admin_or_system()  — آخر تعريف: 20260924000000_lock_down_rpc_views_and_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.require_admin_or_system()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF COALESCE(auth.role(), '') = 'anon' THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = '42501';
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح: هذه العملية لمسؤول النظام (Admin) فقط.'
      USING ERRCODE = '42501';
  END IF;
END;
$function$;

-- ---------------------------------------------------------------------
-- reschedule_loan(p_loan_id uuid, p_amount numeric, p_installment_amount numeric, p_count integer)  — آخر تعريف: 20260929000500_user_flow_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reschedule_loan(p_loan_id uuid, p_amount numeric, p_installment_amount numeric, p_count integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_loan loans%ROWTYPE;
  v_paid numeric;
  v_paid_count integer;
  v_remaining numeric;
  v_left integer;
  v_base numeric;
  v_first date;
  i integer;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_loan FROM loans WHERE id = p_loan_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'السلفة غير موجودة.' USING ERRCODE = 'P0002';
  END IF;
  IF v_loan.status <> 'approved' THEN
    RAISE EXCEPTION 'يمكن تعديل السلف المعتمدة فقط.' USING ERRCODE = '55000';
  END IF;
  IF COALESCE(p_amount, 0) <= 0 OR COALESCE(p_installment_amount, 0) <= 0 OR COALESCE(p_count, 0) <= 0 THEN
    RAISE EXCEPTION 'اكتب مبلغاً وقسطاً وعدد أقساط أكبر من الصفر.' USING ERRCODE = '22023';
  END IF;
  IF p_installment_amount > p_amount THEN
    RAISE EXCEPTION 'القسط أكبر من مبلغ السلفة.' USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(sum(amount), 0), count(*) INTO v_paid, v_paid_count
  FROM loan_installments WHERE loan_id = p_loan_id AND is_paid;
  v_remaining := round(p_amount - v_paid);
  IF v_remaining < 0 THEN
    RAISE EXCEPTION 'المبلغ الجديد أقل من المسدَّد (%).', to_char(v_paid, 'FM999,999,999') USING ERRCODE = '22023';
  END IF;
  v_left := p_count - v_paid_count;
  IF v_remaining > 0 AND v_left <= 0 THEN
    RAISE EXCEPTION 'عدد الأقساط يجب أن يكون أكبر من الأقساط المسددة (%).', v_paid_count USING ERRCODE = '22023';
  END IF;

  -- الجدول يُكتب هنا كاملاً: التريجر لا يولّد أقساطاً أثناء الحذف والإضافة
  PERFORM set_config('loans.skip_rebalance', 'on', true);

  UPDATE loans
  SET amount = round(p_amount), installment_amount = round(p_installment_amount),
      installment_count = p_count, remaining_amount = v_remaining
  WHERE id = p_loan_id;

  DELETE FROM loan_installments WHERE loan_id = p_loan_id AND NOT is_paid;

  IF v_remaining > 0 THEN
    v_first := (date_trunc('month', (now() AT TIME ZONE public.company_timezone())) + interval '1 month')::date;
    v_base := floor(v_remaining / v_left);
    FOR i IN 0 .. v_left - 1 LOOP
      INSERT INTO loan_installments (loan_id, due_date, amount, is_paid)
      VALUES (p_loan_id, (v_first + make_interval(months => i))::date,
              CASE WHEN i = v_left - 1 THEN v_remaining - v_base * (v_left - 1) ELSE v_base END, false);
    END LOOP;
  END IF;

  PERFORM set_config('loans.skip_rebalance', 'off', true);

  INSERT INTO notifications (employee_id, title, body, type)
  VALUES (v_loan.employee_id, 'تعديل تفاصيل السلفة 💸',
          format('قامت الإدارة بتعديل سلفتك: المبلغ الكلي %s د.ع، القسط الشهري %s د.ع، المتبقي %s د.ع على %s قسط.',
                 to_char(round(p_amount), 'FM999,999,999'), to_char(round(p_installment_amount), 'FM999,999,999'),
                 to_char(v_remaining, 'FM999,999,999'), GREATEST(v_left, 0)),
          'loan');
  RETURN GREATEST(v_left, 0);
END;
$function$;

-- ---------------------------------------------------------------------
-- resync_payroll_on_salary_change()  — آخر تعريف: 20261002000000_full_qa_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resync_payroll_on_salary_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r record;
BEGIN
  IF NEW.monthly_salary_iqd IS NOT DISTINCT FROM OLD.monthly_salary_iqd THEN
    RETURN NEW;
  END IF;
  FOR r IN
    SELECT pp.period_month FROM payroll_periods pp
    WHERE pp.status = 'open'
      AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = NEW.id AND s.work_month = pp.period_month)
  LOOP
    PERFORM public.sync_payroll_period(r.period_month, NEW.id);
  END LOOP;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- revert_payroll_slip(p_slip_id uuid)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.revert_payroll_slip(p_slip_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_slip salary_slips%ROWTYPE;
  v_p payroll_periods%ROWTYPE;
BEGIN
  PERFORM public.require_admin();
  SELECT * INTO v_slip FROM salary_slips WHERE id = p_slip_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'كشف الراتب غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_p FROM payroll_periods WHERE period_month = v_slip.work_month;
  IF (FOUND AND v_p.status <> 'open') OR EXISTS (SELECT 1 FROM archived_months WHERE work_month = v_slip.work_month) THEN
    RAISE EXCEPTION 'مسير % مغلق. أعد فتحه أولاً.', v_slip.work_month USING ERRCODE = '42501';
  END IF;

  IF NOT v_slip.computed_by_engine THEN
    -- كشف قديم (أرقام من المتصفح): نفس التراجع السابق، وحركات أيامه تعود لتُحتسب
    UPDATE payroll_events SET salary_slip_id = NULL, updated_at = now() WHERE salary_slip_id = p_slip_id;
    PERFORM public.revert_salary_slip(
      p_slip_id,
      COALESCE(v_p.start_date, (v_slip.work_month || '-01')::date),
      COALESCE(v_p.cutoff_date, ((v_slip.work_month || '-01')::date + interval '1 month - 1 day')::date));
    RETURN;
  END IF;

  DELETE FROM payroll_events WHERE salary_slip_id = p_slip_id AND source = 'approval';
  UPDATE payroll_events SET salary_slip_id = NULL, updated_at = now() WHERE salary_slip_id = p_slip_id;
  UPDATE loan_installments SET is_paid = false, paid_at = NULL, paid_by_slip_id = NULL WHERE paid_by_slip_id = p_slip_id;
  DELETE FROM bonuses_deductions WHERE salary_slip_id = p_slip_id;
  DELETE FROM salary_slips WHERE id = p_slip_id;
END;
$function$;

-- ---------------------------------------------------------------------
-- revert_salary_slip(p_slip_id uuid, p_period_start date, p_period_end date)  — آخر تعريف: 20260924000300_atomic_payroll_approval.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.revert_salary_slip(p_slip_id uuid, p_period_start date, p_period_end date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_slip salary_slips%ROWTYPE;
  v_linked boolean;
BEGIN
  PERFORM public.require_admin();

  SELECT * INTO v_slip FROM salary_slips WHERE id = p_slip_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'كشف الراتب غير موجود.' USING ERRCODE = 'P0002';
  END IF;
  IF EXISTS (SELECT 1 FROM archived_months WHERE work_month = v_slip.work_month) THEN
    RAISE EXCEPTION 'هذا الشهر مؤرشف مالياً ومقفل.' USING ERRCODE = '42501';
  END IF;

  v_linked := EXISTS (SELECT 1 FROM loan_installments WHERE paid_by_slip_id = p_slip_id)
           OR EXISTS (SELECT 1 FROM bonuses_deductions WHERE salary_slip_id = p_slip_id);

  IF v_linked THEN
    UPDATE loan_installments
    SET is_paid = false, paid_at = NULL, paid_by_slip_id = NULL
    WHERE paid_by_slip_id = p_slip_id;
  ELSE
    DELETE FROM bonuses_deductions
    WHERE employee_id = v_slip.employee_id
      AND salary_slip_id IS NULL
      AND issue_date = p_period_end
      AND (reason LIKE '%للفترة من ' || p_period_start || ' إلى ' || p_period_end || '%'
           OR reason LIKE '%لشهر ' || v_slip.work_month || '%');

    UPDATE loan_installments li
    SET is_paid = false, paid_at = NULL
    FROM loans l
    WHERE li.loan_id = l.id
      AND l.employee_id = v_slip.employee_id
      AND li.is_paid = true
      AND li.due_date BETWEEN p_period_start AND p_period_end;
  END IF;

  DELETE FROM salary_slips WHERE id = p_slip_id;
END;
$function$;

-- ---------------------------------------------------------------------
-- rls_auto_enable()  — آخر تعريف: (خارج migrations)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

-- ---------------------------------------------------------------------
-- safe_archive_payroll_month(target_month text, cycle_start_day integer, cycle_end_day integer)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.safe_archive_payroll_month(target_month text, cycle_start_day integer DEFAULT 25, cycle_end_day integer DEFAULT 24)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE;
  v_start date;
  v_end date;
  v_missing text[];
  v_latest timestamptz;
  v_unpaid int;
  v_att int;
  v_bd int;
  v_notif int;
BEGIN
  PERFORM public.require_admin();
  IF EXISTS (SELECT 1 FROM archived_months WHERE work_month = target_month) THEN
    RETURN json_build_object('success', false, 'error', 'هذا الشهر مؤرشف مسبقاً ولا يمكن أرشفته مرة أخرى.');
  END IF;

  SELECT * INTO v_p FROM payroll_periods WHERE period_month = target_month;
  IF FOUND THEN
    IF v_p.status <> 'closed' THEN
      RETURN json_build_object('success', false, 'error', 'أغلق المسير أولاً قبل الأرشفة.');
    END IF;
    v_start := v_p.start_date;
    v_end := v_p.cutoff_date;
  ELSE
    -- أشهر قبل المحرّك: دورة الإعدادات القديمة (البداية من الشهر السابق إن كانت بعد النهاية)،
    -- مع ضبط الأيام على طول الشهر (كان 1 → 31 يفشل في الأشهر القصيرة).
    v_end := (target_month || '-01')::date
             + (LEAST(cycle_end_day, EXTRACT(DAY FROM (target_month || '-01')::date + interval '1 month - 1 day')::int) - 1);
    IF cycle_start_day > cycle_end_day THEN
      v_start := ((target_month || '-01')::date - interval '1 month')::date
                 + (LEAST(cycle_start_day, EXTRACT(DAY FROM (target_month || '-01')::date - interval '1 day')::int) - 1);
    ELSE
      v_start := (target_month || '-01')::date + (cycle_start_day - 1);
    END IF;
  END IF;

  SELECT array_agg(e.full_name) INTO v_missing
  FROM employees e
  WHERE e.is_active AND NOT EXISTS (SELECT 1 FROM salary_slips s WHERE s.employee_id = e.id AND s.work_month = target_month);
  IF v_missing IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن الأرشفة: يوجد موظفون بدون راتب معتمد لهذا الشهر.',
                             'missing_employees', v_missing);
  END IF;

  SELECT max(created_at) INTO v_latest FROM salary_slips WHERE work_month = target_month;
  IF v_latest IS NOT NULL AND now() - v_latest < interval '60 days' THEN
    RETURN json_build_object('success', false, 'error',
      format('لا يمكن الأرشفة بعد: يجب أن تمر 60 يوماً على آخر اعتماد (مرّ %s يوم).', EXTRACT(DAY FROM now() - v_latest)::int));
  END IF;

  SELECT count(*) INTO v_unpaid FROM loan_installments li JOIN loans l ON l.id = li.loan_id
  WHERE li.due_date BETWEEN v_start AND v_end AND NOT li.is_paid AND l.status = 'approved';
  IF v_unpaid > 0 THEN
    RETURN json_build_object('success', false, 'error', format('لا يمكن الأرشفة: يوجد %s قسط غير مدفوع ضمن الفترة.', v_unpaid));
  END IF;

  PERFORM set_config('payroll.skip_sync', 'on', true);
  DELETE FROM attendance WHERE work_date BETWEEN v_start AND v_end;
  GET DIAGNOSTICS v_att = ROW_COUNT;
  DELETE FROM bonuses_deductions WHERE issue_date BETWEEN v_start AND v_end;
  GET DIAGNOSTICS v_bd = ROW_COUNT;
  DELETE FROM notifications WHERE created_at < now() - interval '90 days';
  GET DIAGNOSTICS v_notif = ROW_COUNT;
  PERFORM set_config('payroll.skip_sync', 'off', true);

  INSERT INTO archived_months (work_month, attendance_deleted, bd_deleted, notifications_deleted)
  VALUES (target_month, v_att, v_bd, v_notif);
  RETURN json_build_object('success', true, 'message', 'تم أرشفة شهر ' || target_month || ' بنجاح! 📦',
                           'attendance_deleted', v_att, 'bd_deleted', v_bd, 'notifications_deleted', v_notif);
END;
$function$;

-- ---------------------------------------------------------------------
-- safe_delete_employee(p_employee_id uuid)  — آخر تعريف: 20260929000800_only_admin_deletes_employees.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.safe_delete_employee(p_employee_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح: يجب تسجيل الدخول لتنفيذ هذا الإجراء.' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح: حذف الموظفين لمسؤول النظام (Admin) فقط.' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.employees WHERE id = p_employee_id) THEN
    RAISE EXCEPTION 'الموظف المطلوب غير موجود في النظام.';
  END IF;

  IF p_employee_id = auth.uid() THEN
    RAISE EXCEPTION 'لا يمكنك حذف حسابك بنفسك.';
  END IF;

  PERFORM public._anonymize_employee(p_employee_id);
END;
$function$;

-- ---------------------------------------------------------------------
-- send_idempotent_notification(p_employee_id uuid, p_title text, p_body text, p_type text, p_dedup_window_minutes integer)  — آخر تعريف: 20260924000000_lock_down_rpc_views_and_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_idempotent_notification(p_employee_id uuid, p_title text, p_body text, p_type text, p_dedup_window_minutes integer DEFAULT 60)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL
     AND p_employee_id IS DISTINCT FROM auth.uid()
     AND NOT (public.is_admin() OR public.is_manager()) THEN
    RAISE EXCEPTION 'غير مصرح بإرسال إشعار لموظف آخر.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.notifications
    WHERE employee_id = p_employee_id
      AND title = p_title
      AND body = p_body
      AND created_at > (NOW() - (p_dedup_window_minutes || ' minutes')::INTERVAL)
  ) THEN
    RETURN false;
  END IF;

  INSERT INTO public.notifications (employee_id, title, body, type, is_read, created_at)
  VALUES (p_employee_id, p_title, p_body, p_type, false, NOW());

  RETURN true;
END;
$function$;

-- ---------------------------------------------------------------------
-- set_employee_leave_entitlement(p_employee_id uuid, p_annual numeric, p_sick numeric, p_hourly_monthly_hours numeric)  — آخر تعريف: 20260928000200_leave_policy.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_employee_leave_entitlement(p_employee_id uuid, p_annual numeric, p_sick numeric, p_hourly_monthly_hours numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  IF COALESCE(p_annual, 0) < 0 OR COALESCE(p_sick, 0) < 0 OR COALESCE(p_hourly_monthly_hours, 0) < 0 THEN
    RAISE EXCEPTION 'الرصيد لا يمكن أن يكون بالسالب.' USING ERRCODE = '22023';
  END IF;
  INSERT INTO leave_balances (employee_id, annual_entitlement, sick_entitlement, hourly_monthly_hours)
  VALUES (p_employee_id, p_annual, p_sick, p_hourly_monthly_hours)
  ON CONFLICT (employee_id) DO UPDATE
  SET annual_entitlement = EXCLUDED.annual_entitlement,
      sick_entitlement = EXCLUDED.sick_entitlement,
      hourly_monthly_hours = EXCLUDED.hourly_monthly_hours,
      updated_at = now();
END;
$function$;

-- ---------------------------------------------------------------------
-- set_payroll_policy(p_cutoff_day integer, p_payment_day integer, p_overtime_enabled boolean, p_overtime_multiplier numeric, p_overtime_min_minutes integer)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_payroll_policy(p_cutoff_day integer, p_payment_day integer, p_overtime_enabled boolean, p_overtime_multiplier numeric DEFAULT 1, p_overtime_min_minutes integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.require_admin();
  IF p_cutoff_day NOT BETWEEN 1 AND 28 THEN
    RAISE EXCEPTION 'يوم القطع يجب أن يكون بين 1 و 28.' USING ERRCODE = '22023';
  END IF;
  IF p_payment_day NOT BETWEEN 1 AND 31 THEN
    RAISE EXCEPTION 'يوم الدفع يجب أن يكون بين 1 و 31.' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_overtime_multiplier, 1) <= 0 OR COALESCE(p_overtime_min_minutes, 0) < 0 THEN
    RAISE EXCEPTION 'قيم الساعات الإضافية غير صحيحة.' USING ERRCODE = '22023';
  END IF;
  UPDATE system_settings
  SET value = value || jsonb_build_object(
    'cutoff_day', p_cutoff_day, 'payment_day', p_payment_day,
    'overtime_enabled', p_overtime_enabled, 'overtime_multiplier', COALESCE(p_overtime_multiplier, 1),
    'overtime_min_minutes', COALESCE(p_overtime_min_minutes, 30),
    'cycle_start_day', p_cutoff_day + 1, 'cycle_end_day', p_cutoff_day)
  WHERE key = 'payroll_policy';
  RETURN public.payroll_policy();
END;
$function$;

-- ---------------------------------------------------------------------
-- set_termination_date()  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_termination_date()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF COALESCE(OLD.is_active, true) AND NOT COALESCE(NEW.is_active, true) AND NEW.termination_date IS NULL THEN
    NEW.termination_date := (now() AT TIME ZONE public.company_timezone())::date;
  ELSIF NOT COALESCE(OLD.is_active, true) AND COALESCE(NEW.is_active, true) THEN
    NEW.termination_date := NULL;
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- strip_plain_password()  — آخر تعريف: 20260928000000_security_hardening_round2.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.strip_plain_password()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.plain_password := NULL;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- sync_geofence_coordinates()  — آخر تعريف: 20261005000000_capture_dashboard_objects.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_geofence_coordinates()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    coord_elem jsonb;
    new_coords jsonb := '[]'::jsonb;
    lat_val double precision;
    lng_val double precision;
BEGIN
    IF NEW.polygon_coordinates IS NOT NULL AND jsonb_array_length(NEW.polygon_coordinates) > 0 THEN
        FOR coord_elem IN SELECT jsonb_array_elements(NEW.polygon_coordinates) LOOP
            IF jsonb_array_length(coord_elem) = 2 THEN
                lat_val := (coord_elem->>0)::double precision;
                lng_val := (coord_elem->>1)::double precision;
                new_coords := new_coords || jsonb_build_object('lat', lat_val, 'lng', lng_val);
            END IF;
        END LOOP;
        NEW.coordinates := new_coords;
    ELSIF NEW.coordinates IS NOT NULL AND jsonb_array_length(NEW.coordinates) > 0 THEN
        FOR coord_elem IN SELECT jsonb_array_elements(NEW.coordinates) LOOP
            IF coord_elem ? 'lat' AND coord_elem ? 'lng' THEN
                lat_val := (coord_elem->>'lat')::double precision;
                lng_val := (coord_elem->>'lng')::double precision;
                new_coords := new_coords || jsonb_build_array(lat_val, lng_val);
            END IF;
        END LOOP;
        NEW.polygon_coordinates := new_coords;
    END IF;
    RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- sync_geofences_to_branches()  — آخر تعريف: 20261005000000_capture_dashboard_objects.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_geofences_to_branches()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
    INSERT INTO branches (id, name, latitude, longitude, radius_meters, address)
    VALUES (new.id, new.name, COALESCE(new.latitude, 33.3152), COALESCE(new.longitude, 44.3661), COALESCE(new.radius_meters, 150.0), 'موقع عمل مرسوم')
    ON CONFLICT (id) DO UPDATE SET
      name = EXCLUDED.name,
      latitude = EXCLUDED.latitude,
      longitude = EXCLUDED.longitude,
      radius_meters = EXCLUDED.radius_meters;
  ELSIF TG_OP = 'DELETE' THEN
    DELETE FROM branches WHERE id = old.id;
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------
-- sync_payroll_day(p_employee_id uuid, p_date date)  — آخر تعريف: 20261002000000_full_qa_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_payroll_day(p_employee_id uuid, p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_natural text;
  v_emp employees%ROWTYPE;
  v_sched work_schedules%ROWTYPE;
  v_has_sched boolean;
  v_att attendance%ROWTYPE;
  v_has_att boolean;
  v_leave leave_requests%ROWTYPE;
  v_policy jsonb := public.payroll_policy();
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_daily numeric;
  v_minute numeric;
  v_workday boolean;
  v_grace int;
  v_mins numeric;
  v_status text;
  d record;
  e payroll_events%ROWTYPE;
  v_target text;
  v_desired_signed numeric;
  v_current_signed numeric;
  v_legacy uuid;
  v_full_leave leave_requests%ROWTYPE;
  v_has_full_leave boolean;
BEGIN
  IF current_setting('payroll.skip_sync', true) = 'on' THEN RETURN; END IF;

  v_natural := public.payroll_natural_month(p_date);
  IF v_natural IS NULL THEN RETURN; END IF;         -- قبل أول مسير: كشوف قديمة

  SELECT * INTO v_emp FROM employees WHERE id = p_employee_id;
  IF NOT FOUND THEN RETURN; END IF;

  v_sched := public.payroll_schedule(p_employee_id);
  v_has_sched := v_sched.id IS NOT NULL;
  v_daily := public.payroll_daily_rate(p_employee_id, v_natural);
  v_minute := v_daily / public.payroll_shift_minutes(p_employee_id);
  v_grace := COALESCE(v_sched.grace_period_minutes, 15);
  v_workday := EXTRACT(DOW FROM p_date)::int = ANY (COALESCE(v_sched.work_days, ARRAY[0, 1, 2, 3, 4, 6]))
               AND NOT EXISTS (SELECT 1 FROM official_holidays WHERE holiday_date = p_date); -- العطلة الرسمية ليست يوم دوام

  -- الحركات المطلوبة لهذا اليوم (جدول مؤقت داخل الاستدعاء)
  CREATE TEMP TABLE IF NOT EXISTS _pd (
    event_type text, source text, source_id uuid, minutes numeric, days numeric,
    amount numeric, direction smallint, status_hint text, notes text
  ) ON COMMIT DROP;
  DELETE FROM _pd WHERE true; -- Supabase (pg_safeupdate) يرفض DELETE بدون WHERE

  -- الموظف لم يباشر بعد أو انتهت خدمته: لا حركات لهذا اليوم
  IF (v_emp.join_date IS NOT NULL AND p_date < v_emp.join_date)
     OR (v_emp.termination_date IS NOT NULL AND p_date > v_emp.termination_date) THEN
    NULL;
  ELSE
    SELECT * INTO v_att FROM attendance WHERE employee_id = p_employee_id AND work_date = p_date LIMIT 1;
    v_has_att := FOUND;

    SELECT * INTO v_full_leave FROM leave_requests
    WHERE employee_id = p_employee_id AND status = 'approved' AND NOT COALESCE(is_hourly, false)
      AND p_date BETWEEN (start_date AT TIME ZONE public.company_timezone())::date
                     AND (end_date AT TIME ZONE public.company_timezone())::date
    LIMIT 1;
    v_has_full_leave := FOUND;

    -- يوم مسجّل غياب ثم اعتُمدت له إجازة يومية: الإجازة هي التي تُحتسب (لا خصم غياب)
    IF v_has_att AND NOT (v_att.status = 'absent' AND v_has_full_leave) THEN
      v_status := CASE v_att.deduction_status WHEN 'applied' THEN 'approved' WHEN 'ignored' THEN 'ignored' ELSE 'pending' END;

      IF v_att.status = 'absent' THEN
        -- يوم عطلة (رسمية أو أسبوعية) ما بيه غياب، حتى لو كان مسجّلاً قبل إعلان العطلة
        IF v_workday THEN
          INSERT INTO _pd VALUES ('absence', 'attendance', v_att.id, 0, 1, round(v_daily, 2), -1, v_status,
                                  COALESCE(v_att.deduction_reason, 'غياب'));
        END IF;
      ELSE
        -- بصمة ناقصة: لا خصم تلقائي، تنتظر قرار الإدارة (قد يكون نسياناً)
        IF v_att.check_in_time IS NULL AND v_att.check_out_time IS NOT NULL THEN
          INSERT INTO _pd VALUES ('missing_punch', 'attendance', v_att.id, 0, 0, 0, 0, NULL, 'انصراف بدون بصمة حضور');
        ELSIF v_att.check_in_time IS NOT NULL AND v_att.check_out_time IS NULL AND p_date < v_today
              -- إجازة زمنية معتمدة تشمل آخر دقيقة من الدوام = ما يحتاج بصمة انصراف
              AND NOT (v_has_sched AND v_sched.check_out_time IS NOT NULL
                       AND public.payroll_hourly_leave_overlap(p_employee_id, p_date,
                             public.payroll_time_minutes(v_sched.check_out_time) - 1,
                             public.payroll_time_minutes(v_sched.check_out_time)) > 0) THEN
          INSERT INTO _pd VALUES ('missing_punch', 'attendance', v_att.id, 0, 0, 0, 0, NULL, 'حضور بدون بصمة انصراف');
        END IF;

        -- التأخير: من بداية الدوام، إذا تجاوز فترة السماح
        IF v_att.check_in_time IS NOT NULL AND v_has_sched AND v_sched.check_in_time IS NOT NULL THEN
          v_mins := floor(public.payroll_local_minutes(v_att.check_in_time) - public.payroll_time_minutes(v_sched.check_in_time))
                    - public.payroll_hourly_leave_overlap(p_employee_id, p_date, public.payroll_time_minutes(v_sched.check_in_time),
                                                         public.payroll_local_minutes(v_att.check_in_time));
          IF v_mins > v_grace OR (v_att.status = 'late' AND v_mins > 0) THEN
            INSERT INTO _pd VALUES ('late', 'attendance', v_att.id, v_mins, 0, round(v_mins * v_minute, 2), -1, v_status,
                                    format('تأخير %s دقيقة', v_mins));
          END IF;
        END IF;

        IF v_att.check_out_time IS NOT NULL AND v_has_sched AND v_sched.check_out_time IS NOT NULL THEN
          -- الخروج المبكر بالدقائق (ينتظر قرار الإدارة)
          v_mins := floor(public.payroll_time_minutes(v_sched.check_out_time) - public.payroll_local_minutes(v_att.check_out_time))
                    - public.payroll_hourly_leave_overlap(p_employee_id, p_date, public.payroll_local_minutes(v_att.check_out_time),
                                                         public.payroll_time_minutes(v_sched.check_out_time));
          IF v_mins > v_grace THEN
            INSERT INTO _pd VALUES ('early_leave', 'attendance', v_att.id, v_mins, 0, round(v_mins * v_minute, 2), -1, NULL,
                                    format('خروج مبكر %s دقيقة', v_mins));
          END IF;

          -- الساعات الإضافية (إن فُعّلت من الإعدادات) وتحتاج موافقة
          IF COALESCE((v_policy ->> 'overtime_enabled')::boolean, false) THEN
            v_mins := floor(public.payroll_local_minutes(v_att.check_out_time) - public.payroll_time_minutes(v_sched.check_out_time));
            IF v_mins >= COALESCE((v_policy ->> 'overtime_min_minutes')::int, 30) THEN
              INSERT INTO _pd VALUES ('overtime', 'attendance', v_att.id, v_mins, 0,
                                      round(v_mins * v_minute * COALESCE((v_policy ->> 'overtime_multiplier')::numeric, 1), 2), 1, NULL,
                                      format('ساعات إضافية %s دقيقة', v_mins));
            END IF;
          END IF;
        END IF;
      END IF;
    ELSE
      -- إجازة يومية معتمدة تغطي اليوم
      SELECT * INTO v_leave FROM leave_requests
      WHERE employee_id = p_employee_id AND status = 'approved' AND NOT COALESCE(is_hourly, false)
        AND p_date BETWEEN (start_date AT TIME ZONE public.company_timezone())::date
                       AND (end_date AT TIME ZONE public.company_timezone())::date
      ORDER BY created_at LIMIT 1;

      IF FOUND AND v_workday THEN
        IF v_leave.is_paid THEN
          INSERT INTO _pd VALUES ('paid_leave', 'leave', v_leave.id, 0, 1, 0, 0, 'approved', 'إجازة مدفوعة');
        ELSE
          INSERT INTO _pd VALUES ('unpaid_leave', 'leave', v_leave.id, 0, 1, round(v_daily, 2), -1, 'approved', 'إجازة بدون راتب');
        END IF;
      ELSIF NOT FOUND AND v_workday AND p_date < v_today
            AND p_date >= COALESCE((v_policy ->> 'no_record_from')::date, '-infinity'::date) THEN
        -- يوم عمل بلا بصمة ولا إجازة: غياب ينتظر قرار الإدارة (لا يُخصم تلقائياً)
        INSERT INTO _pd VALUES ('absence', 'no_record', NULL, 0, 1, round(v_daily, 2), -1, 'pending', 'يوم عمل بدون بصمة ولا إجازة');
      END IF;
    END IF;

    -- الإجازات الزمنية المعتمدة في هذا اليوم
    FOR v_leave IN
      SELECT * FROM leave_requests
      WHERE employee_id = p_employee_id AND status = 'approved' AND COALESCE(is_hourly, false)
        AND (start_date AT TIME ZONE public.company_timezone())::date = p_date
    LOOP
      v_mins := GREATEST(round(EXTRACT(EPOCH FROM COALESCE(v_leave.end_hour - v_leave.start_hour, v_leave.end_date - v_leave.start_date)) / 60), 0);
      IF v_leave.is_paid THEN
        INSERT INTO _pd VALUES ('paid_leave', 'leave', v_leave.id, v_mins, 0, 0, 0, 'approved', 'إجازة زمنية مدفوعة');
      ELSE
        INSERT INTO _pd VALUES ('unpaid_leave', 'leave', v_leave.id, v_mins, 0, round(v_mins * v_minute, 2), -1, 'approved', 'إجازة زمنية بدون راتب');
      END IF;
    END LOOP;
  END IF;

  -- (أ) حركات سابقة لم تعد مطلوبة: تُلغى (أو تُعكس إن كانت داخل كشف معتمد)
  FOR e IN
    SELECT pe.* FROM payroll_events pe
    WHERE pe.employee_id = p_employee_id AND pe.event_date = p_date
      AND pe.source IN ('attendance', 'no_record', 'leave') AND pe.status <> 'void'
      AND NOT EXISTS (SELECT 1 FROM _pd WHERE _pd.event_type = pe.event_type AND _pd.source = pe.source
                        AND _pd.source_id IS NOT DISTINCT FROM pe.source_id)
      -- إيقاف الإضافي من الإعدادات لا يلغي إضافياً اعتمدته الإدارة سابقاً
      AND NOT (pe.event_type = 'overtime' AND pe.decided_at IS NOT NULL
               AND NOT COALESCE((v_policy ->> 'overtime_enabled')::boolean, false))
  LOOP
    PERFORM public._payroll_settle(e, 0);
    UPDATE payroll_events SET status = 'void', updated_at = now() WHERE id = e.id AND salary_slip_id IS NULL;
  END LOOP;

  -- (ب) الحركات المطلوبة: إنشاء أو تحديث
  FOR d IN SELECT * FROM _pd LOOP
    SELECT * INTO e FROM payroll_events pe
    WHERE pe.employee_id = p_employee_id AND pe.event_date = p_date AND pe.event_type = d.event_type
      AND pe.source = d.source AND pe.source_id IS NOT DISTINCT FROM d.source_id AND pe.status <> 'void'
    ORDER BY pe.created_at DESC LIMIT 1;

    IF NOT FOUND THEN
      v_legacy := public.payroll_legacy_slip(p_employee_id, v_natural, p_date);
      v_target := CASE WHEN v_legacy IS NOT NULL THEN v_natural ELSE public.payroll_target_month(p_employee_id, v_natural) END;
      INSERT INTO payroll_events (employee_id, event_date, event_type, minutes, days, amount, direction,
                                  payroll_month, carried_from, status, source, source_id, daily_rate, minute_rate, notes,
                                  salary_slip_id)
      VALUES (p_employee_id, p_date, d.event_type, d.minutes, d.days, d.amount, d.direction,
              v_target, NULLIF(v_natural, v_target), COALESCE(d.status_hint, 'pending'), d.source, d.source_id,
              v_daily, v_minute, d.notes, v_legacy);
    ELSIF e.salary_slip_id IS NOT NULL THEN
      -- داخل كشف معتمد: لا نغيّره، الفرق يصير تسوية في أول مسير مفتوح
      v_status := CASE WHEN d.status_hint IN ('approved', 'ignored') AND d.event_type IN ('absence', 'late')
                       THEN d.status_hint ELSE e.status END;
      v_desired_signed := CASE WHEN v_status = 'approved' THEN d.direction * d.amount ELSE 0 END;
      PERFORM public._payroll_settle(e, v_desired_signed);
    ELSE
      v_status := CASE
        WHEN d.status_hint IN ('approved', 'ignored') AND (d.event_type IN ('absence', 'late') OR d.source = 'leave') THEN d.status_hint
        WHEN d.status_hint = 'pending' AND d.event_type IN ('absence', 'late') AND e.decided_at IS NULL THEN 'pending'
        ELSE e.status
      END;
      v_target := CASE
        WHEN EXISTS (SELECT 1 FROM payroll_periods WHERE period_month = e.payroll_month AND status = 'open')
             AND NOT EXISTS (SELECT 1 FROM salary_slips WHERE employee_id = p_employee_id AND work_month = e.payroll_month)
          THEN e.payroll_month
        ELSE public.payroll_target_month(p_employee_id, v_natural)
      END;
      UPDATE payroll_events
      SET minutes = d.minutes, days = d.days, amount = d.amount, direction = d.direction, notes = d.notes,
          status = v_status, payroll_month = v_target, carried_from = NULLIF(v_natural, v_target),
          daily_rate = v_daily, minute_rate = v_minute, updated_at = now()
      WHERE id = e.id;
    END IF;
  END LOOP;
END;
$function$;

-- ---------------------------------------------------------------------
-- sync_payroll_manual(p_bd_id uuid)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_payroll_manual(p_bd_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  bd bonuses_deductions%ROWTYPE;
  e payroll_events%ROWTYPE;
  v_natural text;
  v_target text;
  v_type text;
  v_dir smallint;
  v_legacy uuid;
BEGIN
  IF current_setting('payroll.skip_sync', true) = 'on' THEN RETURN; END IF;
  SELECT * INTO e FROM payroll_events WHERE source = 'manual' AND source_id = p_bd_id AND status <> 'void' LIMIT 1;
  SELECT * INTO bd FROM bonuses_deductions WHERE id = p_bd_id;

  IF NOT FOUND OR bd.salary_slip_id IS NOT NULL OR bd.superseded_by_attendance THEN
    IF e.id IS NOT NULL THEN
      PERFORM public._payroll_settle(e, 0);
      UPDATE payroll_events SET status = 'void', updated_at = now() WHERE id = e.id AND salary_slip_id IS NULL;
    END IF;
    RETURN;
  END IF;

  v_natural := public.payroll_natural_month(bd.issue_date);
  IF v_natural IS NULL THEN RETURN; END IF;
  v_type := CASE WHEN bd.type = 'bonus' THEN 'bonus' ELSE 'manual_deduction' END;
  v_dir := CASE WHEN bd.type = 'bonus' THEN 1 ELSE -1 END;

  IF e.id IS NULL THEN
    -- قيد أُدخل قبل كشف قديم لنفس المسير = محتسب فيه؛ بعده = يُرحَّل لأول مسير مفتوح
    SELECT s.id INTO v_legacy FROM salary_slips s
    WHERE s.id = public.payroll_legacy_slip(bd.employee_id, v_natural) AND s.created_at >= bd.created_at;
    v_target := CASE WHEN v_legacy IS NOT NULL THEN v_natural ELSE public.payroll_target_month(bd.employee_id, v_natural) END;
    INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, carried_from,
                                status, source, source_id, notes, created_by, salary_slip_id)
    VALUES (bd.employee_id, bd.issue_date, v_type, abs(bd.amount), v_dir, v_target, NULLIF(v_natural, v_target),
            'approved', 'manual', bd.id, bd.reason, bd.created_by, v_legacy);
  ELSIF e.salary_slip_id IS NOT NULL THEN
    PERFORM public._payroll_settle(e, v_dir * abs(bd.amount));
  ELSE
    UPDATE payroll_events SET amount = abs(bd.amount), direction = v_dir, event_type = v_type, event_date = bd.issue_date,
                              notes = bd.reason, updated_at = now()
    WHERE id = e.id;
  END IF;
END;
$function$;

-- ---------------------------------------------------------------------
-- sync_payroll_period(p_month text, p_employee_id uuid)  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_payroll_period(p_month text, p_employee_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_p payroll_periods%ROWTYPE := public.ensure_payroll_period(p_month);
  v_today date := (now() AT TIME ZONE public.company_timezone())::date;
  v_emp record;
  d date;
  bd record;
BEGIN
  IF v_p.status <> 'open' THEN RETURN; END IF;
  FOR v_emp IN
    SELECT id FROM employees
    WHERE (p_employee_id IS NULL OR id = p_employee_id)
      AND (join_date IS NULL OR join_date <= v_p.cutoff_date)
      AND (termination_date IS NULL OR termination_date >= v_p.start_date)
      AND (is_active OR termination_date IS NOT NULL)
  LOOP
    d := v_p.start_date;
    WHILE d <= LEAST(v_p.cutoff_date, v_today) LOOP
      PERFORM public.sync_payroll_day(v_emp.id, d);
      d := d + 1;
    END LOOP;
  END LOOP;

  FOR bd IN
    SELECT b.id FROM bonuses_deductions b
    WHERE b.issue_date BETWEEN v_p.start_date AND v_p.cutoff_date
      AND (p_employee_id IS NULL OR b.employee_id = p_employee_id)
  LOOP
    PERFORM public.sync_payroll_manual(bd.id);
  END LOOP;
END;
$function$;

-- ---------------------------------------------------------------------
-- trg_payroll_attendance()  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_payroll_attendance()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- النسخ القديمة من الموقع/التطبيق تسجّل قرار الخصم كقيد خصم منفصل + تعتمد الحضور = خصم مرتين.
  -- المحرّك يحسب الخصم من الحضور نفسه، فالقيد المكرر (نفس اليوم والسبب، أُضيف للتو) يُعلَّم.
  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.deduction_status = 'applied' AND NEW.status IN ('late', 'absent')
     AND (TG_OP = 'INSERT' OR OLD.deduction_status IS DISTINCT FROM 'applied') THEN
    UPDATE bonuses_deductions
    SET superseded_by_attendance = true
    WHERE employee_id = NEW.employee_id AND issue_date = NEW.work_date AND type = 'deduction'
      AND salary_slip_id IS NULL AND NOT superseded_by_attendance
      AND reason IS NOT DISTINCT FROM NEW.deduction_reason
      AND created_at > now() - interval '10 minutes';
  END IF;

  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    PERFORM public.sync_payroll_day(OLD.employee_id, OLD.work_date);
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE')
     AND (TG_OP = 'INSERT' OR NEW.employee_id IS DISTINCT FROM OLD.employee_id OR NEW.work_date IS DISTINCT FROM OLD.work_date) THEN
    PERFORM public.sync_payroll_day(NEW.employee_id, NEW.work_date);
  END IF;
  RETURN NULL;
END;
$function$;

-- ---------------------------------------------------------------------
-- trg_payroll_holiday()  — آخر تعريف: 20260929000400_audit_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_payroll_holiday()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_emp record;
  v_day date := COALESCE(NEW.holiday_date, OLD.holiday_date);
BEGIN
  FOR v_emp IN SELECT id FROM employees WHERE is_active OR termination_date IS NOT NULL LOOP
    PERFORM public.sync_payroll_day(v_emp.id, v_day);
  END LOOP;
  RETURN NULL;
END;
$function$;

-- ---------------------------------------------------------------------
-- trg_payroll_leave()  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_payroll_leave()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r leave_requests%ROWTYPE;
  d date;
  v_from date;
  v_to date;
BEGIN
  FOREACH r IN ARRAY (CASE TG_OP WHEN 'INSERT' THEN ARRAY[NEW] WHEN 'DELETE' THEN ARRAY[OLD] ELSE ARRAY[OLD, NEW] END) LOOP
    CONTINUE WHEN r.start_date IS NULL OR r.end_date IS NULL;
    v_from := (r.start_date AT TIME ZONE public.company_timezone())::date;
    v_to := LEAST((r.end_date AT TIME ZONE public.company_timezone())::date, v_from + 92);
    d := v_from;
    WHILE d <= v_to LOOP
      PERFORM public.sync_payroll_day(r.employee_id, d);
      d := d + 1;
    END LOOP;
  END LOOP;
  RETURN NULL;
END;
$function$;

-- ---------------------------------------------------------------------
-- trg_payroll_manual()  — آخر تعريف: 20260929000000_payroll_engine.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_payroll_manual()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.sync_payroll_manual(COALESCE(NEW.id, OLD.id));
  RETURN NULL;
END;
$function$;

-- ---------------------------------------------------------------------
-- update_employee_credentials(p_employee_id uuid, p_email text, p_password text, p_phone text)  — آخر تعريف: 20260924000000_lock_down_rpc_views_and_notifications.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_employee_credentials(p_employee_id uuid, p_email text, p_password text DEFAULT NULL::text, p_phone text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_hashed_password text;
BEGIN
  PERFORM public.require_admin();

  IF p_password IS NOT NULL AND p_password != '' THEN
    v_hashed_password := extensions.crypt(p_password, extensions.gen_salt('bf'));
    UPDATE auth.users
    SET email = p_email,
        encrypted_password = v_hashed_password,
        phone = NULLIF(p_phone, ''),
        updated_at = now()
    WHERE id = p_employee_id;
  ELSE
    UPDATE auth.users
    SET email = p_email,
        phone = NULLIF(p_phone, ''),
        updated_at = now()
    WHERE id = p_employee_id;
  END IF;

  UPDATE auth.identities
  SET identity_data = jsonb_set(identity_data, '{email}', to_jsonb(p_email)),
      updated_at = now()
  WHERE user_id = p_employee_id;

  UPDATE public.employees
  SET email = p_email,
      phone = NULLIF(p_phone, ''),
      plain_password = CASE WHEN p_password IS NOT NULL AND p_password != '' THEN p_password ELSE plain_password END
  WHERE id = p_employee_id;
END;
$function$;

-- ---------------------------------------------------------------------
-- update_loan_and_installments_trigger()  — آخر تعريف: 20260929000500_user_flow_fixes.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_loan_and_installments_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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

    -- إعادة الجدولة من reschedule_loan تكتب الجدول كاملاً بنفسها: لا توليد تلقائي أثناءها
    IF current_setting('loans.skip_rebalance', true) = 'on' THEN
        RETURN NULL;
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
$function$;

-- ---------------------------------------------------------------------
-- validate_leave_request()  — آخر تعريف: 20260928000200_leave_policy.sql
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_leave_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tz text := public.company_timezone();
  v_types jsonb := public.leave_policy() -> 'active_types';
  v_days numeric;
  v_hours numeric;
  v_bal jsonb;
  v_left numeric;
BEGIN
  IF TG_OP = 'UPDATE' AND NOT (NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' AND NEW.status NOT IN ('pending', 'approved') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' AND jsonb_typeof(v_types) = 'array' AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_types) t WHERE t ->> 'id' = NEW.leave_type
  ) THEN
    RAISE EXCEPTION 'نوع الإجازة غير متاح حالياً.' USING ERRCODE = '22023';
  END IF;

  IF NEW.start_date IS NULL OR NEW.end_date IS NULL OR NEW.end_date < NEW.start_date THEN
    RAISE EXCEPTION 'تاريخ نهاية الإجازة يجب أن يكون بعد تاريخ بدايتها.' USING ERRCODE = '22023';
  END IF;
  IF NEW.is_hourly AND NEW.start_hour IS NOT NULL AND NEW.end_hour IS NOT NULL
     AND NEW.end_hour <= NEW.start_hour THEN
    RAISE EXCEPTION 'وقت نهاية الإجازة الزمنية يجب أن يكون بعد وقت بدايتها.' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM leave_requests o
    WHERE o.employee_id = NEW.employee_id
      AND o.id IS DISTINCT FROM NEW.id
      AND o.status IN ('pending', 'approved')
      AND (o.start_date AT TIME ZONE v_tz)::date <= (NEW.end_date AT TIME ZONE v_tz)::date
      AND (o.end_date AT TIME ZONE v_tz)::date >= (NEW.start_date AT TIME ZONE v_tz)::date
      AND (
        NOT (COALESCE(o.is_hourly, false) AND COALESCE(NEW.is_hourly, false))
        OR o.start_hour IS NULL OR NEW.start_hour IS NULL
        OR (o.start_hour < NEW.end_hour AND NEW.start_hour < o.end_hour)
      )
  ) THEN
    RAISE EXCEPTION 'توجد إجازة أخرى (قيد الانتظار أو معتمدة) تتداخل مع هذه التواريخ.' USING ERRCODE = '23P01';
  END IF;

  v_bal := public.get_leave_balance(NEW.employee_id, (NEW.start_date AT TIME ZONE v_tz)::date, NEW.id);

  IF COALESCE(NEW.is_hourly, false) THEN
    v_hours := public.leave_request_hours(NEW);
    v_left := (v_bal -> 'hourly' ->> 'left_hours')::numeric;
    IF v_hours > v_left THEN
      RAISE EXCEPTION 'رصيد الإجازات الزمنية لهذا الشهر غير كافٍ: المطلوب % ساعة والمتبقي % ساعة.',
        public.fmt_days(v_hours), public.fmt_days(GREATEST(v_left, 0)) USING ERRCODE = '22023';
    END IF;
  ELSE
    v_days := public.leave_request_days(NEW);
    IF v_days = 0 THEN
      RAISE EXCEPTION 'الأيام المختارة كلها عطلة رسمية، لا حاجة لإجازة.' USING ERRCODE = '22023';
    END IF;
    IF NEW.leave_type IN ('annual', 'sick') THEN
      v_left := (v_bal -> NEW.leave_type ->> 'left')::numeric;
      IF v_days > v_left THEN
        RAISE EXCEPTION 'رصيد الإجازة غير كافٍ: المطلوب % يوم والمتبقي % يوم.',
          public.fmt_days(v_days), public.fmt_days(GREATEST(v_left, 0)) USING ERRCODE = '22023';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;
