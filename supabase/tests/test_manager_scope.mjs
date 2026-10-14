// تدقيق 14/10/2026 — المرحلة 1: صلاحيات مدير الفرع وحدود المبالغ
// (BUG-002/003/004/005/012/014/016، PAY-003/004/005). المدير IDS.manager بنفس فرع IDS.emp؛ OTHER بفرع ثاني.
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];
const N = (v) => Number(v);
const noUser = () => db.exec(`SELECT set_config('request.jwt.claim.sub', '', false)`);

const B2 = '00000000-0000-0000-0000-0000000000b2';
const OTHER = '00000000-0000-0000-0000-0000000000d8';
await db.exec(`
  INSERT INTO branches (id, name, latitude, longitude, radius_meters) VALUES ('${B2}', 'فرع ثاني', 33.1, 44.1, 100);
  INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ('${OTHER}', 'O1', 'موظف فرع ثاني', 'employee', '${B2}', 600000, '2026-01-01', false);
  INSERT INTO auth.users (id, email) VALUES ('${OTHER}', 'o@x');
  UPDATE employees SET join_date = '2026-01-01';
  INSERT INTO work_schedules (name, branch_id, check_in_time, check_out_time, grace_period_minutes, work_days)
    VALUES ('B1', '${IDS.branch}', '09:00', '14:00', 15, ARRAY[0,1,2,3,4,6]);
  UPDATE work_schedule_history SET effective_from = '2026-01-01';
  UPDATE system_settings SET value = value || '{"overtime_enabled": true, "overtime_min_minutes": 30}'::jsonb WHERE key = 'payroll_policy';
`);
const today = (await one(`SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date::text d`)).d;
// آخر يوم دوام فات (مو جمعة) بالمسير الحالي
const day = (await one(`SELECT d::date::text d FROM generate_series($1::date - 1, $1::date - 7, interval '-1 day') d
                        WHERE extract(dow FROM d) <> 5 LIMIT 1`, [today])).d;
const month = (await one(`SELECT payroll_natural_month($1::date) m`, [day])).m;
await q(`SELECT ensure_payroll_period($1)`, [month]);

// ---------------- BUG-005: الراتب ما ينقرا مباشرة ----------------
await expectError('BUG-005) an employee cannot read salaries from the table', as(db, 'emp', `SELECT monthly_salary_iqd FROM employees`), 'permission denied');
await expectError('   a manager cannot read salaries from the table', as(db, 'manager', `SELECT monthly_salary_iqd FROM employees WHERE id = $1`, [IDS.emp]), 'permission denied');
await expectError('   select * (all columns) is refused too', as(db, 'manager', `SELECT * FROM employees`), 'permission denied');
const mgrRows = await as(db, 'manager', `SELECT id, full_name, branch_id FROM employees`);
check('   the manager still lists his branch colleagues (without salary)', mgrRows.rows.length === 4 && mgrRows.rows.every((r) => r.branch_id === IDS.branch), JSON.stringify(mgrRows.rows));
const payAdmin = await as(db, 'admin', `SELECT employee_id, monthly_salary_iqd FROM get_employee_pay()`);
check('   the admin reads all salaries through get_employee_pay', payAdmin.rows.length === 5);
const payEmp = await as(db, 'emp', `SELECT employee_id, monthly_salary_iqd FROM get_employee_pay()`);
check('   an employee reads only his own salary', payEmp.rows.length === 1 && payEmp.rows[0].employee_id === IDS.emp && N(payEmp.rows[0].monthly_salary_iqd) === 1000000, JSON.stringify(payEmp.rows));
const payMgr = await as(db, 'manager', `SELECT employee_id FROM get_employee_pay(ARRAY[$1]::uuid[])`, [IDS.emp]);
check('   a manager gets nothing for his staff', payMgr.rows.length === 0);
await expectOk('   the admin still changes a salary', as(db, 'admin', `UPDATE employees SET monthly_salary_iqd = 1100000 WHERE id = $1`, [IDS.emp2]));
await expectOk('   an employee still edits his phone', as(db, 'emp', `UPDATE employees SET phone = '07700000000' WHERE id = $1`, [IDS.emp]));
await expectOk('   a manual deduction still checks the salary (admin)', as(db, 'admin',
  `INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date) VALUES ($1, 'deduction', 5000, 'فحص', $2)`, [IDS.emp, day]));
await expectError('   ...and refuses more than the salary', as(db, 'admin',
  `INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date) VALUES ($1, 'deduction', 5000000, 'فحص', $2)`, [IDS.emp, day]), 'أكبر من راتب');

// ---------------- PAY-004: آخر يوم عمل ----------------
await q(`UPDATE employees SET termination_date = '2030-01-01' WHERE id = $1`, [IDS.emp]);
await expectError('PAY-004) an employee cannot clear his last working day', as(db, 'emp', `UPDATE employees SET termination_date = NULL WHERE id = $1`, [IDS.emp]), 'الموارد البشرية');
await q(`UPDATE employees SET termination_date = NULL WHERE id = $1`, [IDS.emp]);

// ---------------- BUG-002: المدير يشوف فرعه بس ----------------
await noUser();
await q(`INSERT INTO attendance (employee_id, branch_id, work_date, check_in_time, check_out_time, status, deduction_status)
  VALUES ($1, $2, $3, ($3::date + time '09:40') - interval '3 hours', ($3::date + time '15:30') - interval '3 hours', 'late', 'pending'),
         ($4, $5, $3, ($3::date + time '09:00') - interval '3 hours', NULL, 'present', 'pending')`, [IDS.emp, IDS.branch, day, OTHER, B2]);
await q(`INSERT INTO location_tracking (employee_id, latitude, longitude, "timestamp") VALUES ($1, 33.3, 44.4, now()), ($2, 33.1, 44.1, now())`, [IDS.emp, OTHER]);
await q(`INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status) VALUES ($1, '2026-12-01T06:00:00Z', '2026-12-01T06:00:00Z', 'annual', 'pending')`, [OTHER]);
const seen = async (who, table) => (await as(db, who, `SELECT DISTINCT employee_id::text e FROM ${table}`)).rows.map((r) => r.e);
for (const t of ['attendance', 'location_tracking', 'leave_requests', 'leave_balances']) {
  const m = await seen('manager', t);
  check(`BUG-002) manager sees only his branch in ${t}`, !m.includes(OTHER) && (t === 'leave_requests' || m.includes(IDS.emp)), JSON.stringify(m));
  check(`   admin sees every branch in ${t}`, (await seen('admin', t)).includes(OTHER));
}
await expectError('   a manager cannot read another branch leave balance', as(db, 'manager', `SELECT get_leave_balance($1)`, [OTHER]), 'غير مصرح');
await expectOk('   ...but reads his own staff balance', as(db, 'manager', `SELECT get_leave_balance($1)`, [IDS.emp]));

// ---------------- BUG-003: الإشعارات ----------------
await expectError('BUG-003) a manager cannot notify another branch', as(db, 'manager',
  `INSERT INTO notifications (employee_id, title, body, type) VALUES ($1, 'x', 'y', 'system')`, [OTHER]), 'row-level security');
await expectOk('   ...but notifies his own staff', as(db, 'manager',
  `INSERT INTO notifications (employee_id, title, body, type) VALUES ($1, 'x', 'y', 'system')`, [IDS.emp]));
await expectError('   send_idempotent_notification follows the same rule', as(db, 'manager',
  `SELECT send_idempotent_notification($1, 'x', 'y', 'system')`, [OTHER]), 'غير مصرح');

// ---------------- PAY-003: حدود مبلغ القرار ----------------
const ev = async (type) => one(`SELECT id::text, amount, minutes, daily_rate FROM payroll_events
  WHERE employee_id = $1 AND event_date = $2 AND event_type = $3 AND status <> 'void'`, [IDS.emp, day, type]);
const late = await ev('late');
const ot = await ev('overtime');
check('PAY-003) the late (40 min) and overtime (90 min) events exist', late && ot, JSON.stringify({ late, ot }));
const daily = Math.round(N(late.daily_rate) * 100) / 100;
await expectError('   a manager cannot raise a late deduction above the computed amount', as(db, 'manager',
  `SELECT decide_payroll_event($1, true, 'x', $2)`, [late.id, N(late.amount) + 1]), 'يقلل المبلغ بس');
await expectError('   a manager cannot inflate overtime', as(db, 'manager',
  `SELECT decide_payroll_event($1, true, 'x', 1000000)`, [ot.id]), 'يقلل المبلغ بس');
await expectOk('   a manager can lower a late deduction', as(db, 'manager', `SELECT decide_payroll_event($1, true, 'نص', $2)`, [late.id, Math.floor(N(late.amount) / 2)]));
await expectError('   the admin cannot deduct more than one day for a late', as(db, 'admin',
  `SELECT decide_payroll_event($1, true, 'x', $2)`, [late.id, daily + 1]), 'أجر يوم');
await expectOk('   ...one full day is allowed', as(db, 'admin', `SELECT decide_payroll_event($1, true, 'x', $2)`, [late.id, daily]));
await expectError('   the admin cannot raise overtime above the computed amount', as(db, 'admin',
  `SELECT decide_payroll_event($1, true, 'x', $2)`, [ot.id, N(ot.amount) + 1]), 'مكافأة');
await expectOk('   ...the computed overtime is approved', as(db, 'admin', `SELECT decide_payroll_event($1, true, 'x', $2)`, [ot.id, N(ot.amount)]));

// ---------------- BUG-014: الموظف يشوف المقرر بس ----------------
await noUser();
await q(`INSERT INTO attendance (employee_id, branch_id, work_date, check_in_time, check_out_time, status, deduction_status)
  SELECT $1, $2, d::date, (d::date + time '09:50') - interval '3 hours', (d::date + time '14:00') - interval '3 hours', 'late', 'pending'
  FROM generate_series($3::date - 1, $3::date - 7, interval '-1 day') d
  WHERE extract(dow FROM d) <> 5 AND payroll_natural_month(d::date) = $4 LIMIT 1`, [IDS.emp2, IDS.branch, day, month]);
const pend = await one(`SELECT count(*)::int n FROM payroll_events WHERE employee_id = $1 AND status = 'pending'`, [IDS.emp2]);
const sees = await as(db, 'emp2', `SELECT status FROM payroll_events`);
check('BUG-014) an employee does not see his undecided late', pend.n >= 1 && sees.rows.every((r) => r.status === 'approved'), JSON.stringify({ pend, rows: sees.rows }));
const prev = (await as(db, 'emp2', `SELECT get_my_payroll_preview() p`)).rows[0].p;
check('   ...nor in his salary preview', prev && prev.events.every((e) => e.status === 'approved') && prev.summary.pending_count === 0, JSON.stringify(prev?.events));
const empSeesOwnApproved = await as(db, 'emp', `SELECT event_type FROM payroll_events WHERE status = 'approved'`);
check('   a decided deduction is visible to its employee', empSeesOwnApproved.rows.some((r) => r.event_type === 'late'));

// ---------------- PAY-005: الإجازات ----------------
await noUser();
const mk = async (emp, status, date) => (await one(`INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, is_paid, status)
  VALUES ($1, $2::timestamptz, $2::timestamptz, 'annual', true, $3) RETURNING id::text`, [emp, `${date}T06:00:00Z`, status])).id;
const own = await mk(IDS.manager, 'approved', '2026-12-08');
// إجازته ما توصله أصلاً للتعديل (الصلاحية تستثني صاحب الطلب)، فتبقى مثل ما هي
await as(db, 'manager', `UPDATE leave_requests SET is_paid = false WHERE id = $1`, [own]);
check('PAY-005) a manager cannot change his own approved leave', (await one(`SELECT is_paid FROM leave_requests WHERE id = $1`, [own])).is_paid === true);
const decided = await mk(IDS.emp, 'approved', '2026-12-09');
await expectError('   a manager cannot edit a decided leave of his staff', as(db, 'manager',
  `UPDATE leave_requests SET is_paid = false, end_date = '2026-12-20T06:00:00Z' WHERE id = $1`, [decided]), 'الأدمن');
const pendingLeave = await mk(IDS.emp, 'pending', '2026-12-15');
await expectOk('   a manager approves a pending leave of his staff', as(db, 'manager', `UPDATE leave_requests SET status = 'approved' WHERE id = $1`, [pendingLeave]));
await expectError('   the admin extending an approved leave over another one is refused', as(db, 'admin',
  `UPDATE leave_requests SET end_date = '2026-12-16T06:00:00Z' WHERE id = $1`, [decided]), 'تتداخل');
await expectError('   ...and beyond the balance too', as(db, 'admin',
  `UPDATE leave_requests SET start_date = '2026-01-04T06:00:00Z', end_date = '2026-03-01T06:00:00Z' WHERE id = $1`, [decided]), 'رصيد');
await expectOk('   the admin can still adjust it within the rules', as(db, 'admin',
  `UPDATE leave_requests SET end_date = '2026-12-10T06:00:00Z' WHERE id = $1`, [decided]));

// ---------------- BUG-012: السلفة المعتمدة ----------------
await noUser();
const loan = (await one(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
  VALUES ($1, 300000, 100000, 3, 300000, 'p.png', 'approved') RETURNING id::text`, [IDS.emp2])).id;
await expectError('BUG-012) an approved advance cannot be rejected', as(db, 'admin', `UPDATE loans SET status = 'rejected' WHERE id = $1`, [loan]), 'معتمدة');
await expectError('   ...nor cancelled', as(db, 'admin', `UPDATE loans SET status = 'cancelled' WHERE id = $1`, [loan]), 'معتمدة');
await noUser();
const req = (await one(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
  VALUES ($1, 200000, 100000, 2, 200000, 'p.png', 'pending') RETURNING id::text`, [OTHER])).id;
await expectOk('   a pending request can still be rejected', as(db, 'admin', `UPDATE loans SET status = 'rejected' WHERE id = $1`, [req]));

// ---------------- BUG-004 + BUG-016: التخزين ----------------
await noUser();
await q(`INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('employee-documents', $1, $2), ('employee-documents', $3, $2)`,
  [`${IDS.emp}/id.jpg`, IDS.admin, `${IDS.emp}/passport.jpg`]);
await as(db, 'manager', `DELETE FROM storage.objects WHERE bucket_id = 'employee-documents' AND name = $1`, [`${IDS.emp}/id.jpg`]);
check('BUG-004) a manager cannot delete an employee document', (await one(`SELECT count(*)::int n FROM storage.objects WHERE name = $1`, [`${IDS.emp}/id.jpg`])).n === 1);
await as(db, 'admin', `DELETE FROM storage.objects WHERE bucket_id = 'employee-documents' AND name = $1`, [`${IDS.emp}/passport.jpg`]);
check('   the admin can', (await one(`SELECT count(*)::int n FROM storage.objects WHERE name = $1`, [`${IDS.emp}/passport.jpg`])).n === 0);
await expectError('BUG-016) an employee cannot upload an avatar into another folder', as(db, 'emp',
  `INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('avatars', $1, $2)`, [`${IDS.emp2}/x.jpg`, IDS.emp]), 'row-level security');
await expectOk('   ...his own folder works', as(db, 'emp',
  `INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('avatars', $1, $2)`, [`${IDS.emp}/me.jpg`, IDS.emp]));
const bucket = await one(`SELECT file_size_limit, allowed_mime_types FROM storage.buckets WHERE id = 'employee-documents'`);
check('   documents bucket: 10MB, images and PDF', !bucket || (N(bucket.file_size_limit) === 10485760 && bucket.allowed_mime_types.includes('application/pdf')), JSON.stringify(bucket));

done();
