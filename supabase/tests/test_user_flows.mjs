// مسارات المستخدم الحقيقية: تعديل السلفة، قرارات المدير، إلغاء الإجازة، طلب سلفة مكرر،
// "مسير هذا الشهر" للموظف، وظهور الكشف المعتمد لموظف معطّل.
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (s, p = []) => (await db.query(s, p)).rows;
const B2 = '00000000-0000-0000-0000-0000000000b2';
const OTHER = '00000000-0000-0000-0000-0000000000d9';
await db.exec(`
  UPDATE employees SET join_date = '2026-01-01';
  UPDATE employees SET monthly_salary_iqd = 1200000 WHERE id = '${IDS.emp}';
  INSERT INTO branches (id, name, latitude, longitude, radius_meters) VALUES ('${B2}', 'فرع آخر', 33, 44, 100);
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ('${OTHER}', 'X1', 'فرع آخر', '${B2}', 600000, '2026-01-01', false);
  INSERT INTO work_schedules (branch_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
    VALUES ('${IDS.branch}', 'دوام', '08:00', '16:00', 15, '{0,1,2,3,4,6}');
`);
const today = (await q(`SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date::text d`))[0].d;
const dayOffset = (n) => { const d = new Date(`${today}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };

// ---------------- 1) تعديل السلفة ----------------
const loan = (await as(db, 'admin', `SELECT create_direct_loan($1, 900000, 3, '2026-11-15', 'x') id`, [IDS.emp])).rows[0].id
  ?? (await q(`SELECT id FROM loans WHERE employee_id=$1 ORDER BY created_at DESC LIMIT 1`, [IDS.emp]))[0].id;
const inst = await q(`SELECT id FROM loan_installments WHERE loan_id=$1 ORDER BY due_date`, [loan]);
await as(db, 'admin', `SELECT pay_loan_installment($1, 300000, 'cash', NULL)`, [inst[0].id]);
await expectError('employee cannot reschedule a loan', as(db, 'emp', `SELECT reschedule_loan($1, 900000, 200000, 4)`, [loan]), 'غير مصرح');
await expectOk('admin reschedules 900,000 (300,000 paid) into 4 installments', as(db, 'admin', `SELECT reschedule_loan($1, 900000, 200000, 4)`, [loan]));
const sched = await q(`SELECT due_date::text d, amount, is_paid FROM loan_installments WHERE loan_id=$1 ORDER BY due_date`, [loan]);
const unpaid = sched.filter((s) => !s.is_paid);
check('1) no doubled installments: 1 paid + 3 × 200,000 = 900,000',
  sched.length === 4 && unpaid.length === 3 && unpaid.every((s) => Number(s.amount) === 200000)
  && sched.reduce((a, s) => a + Number(s.amount), 0) === 900000, JSON.stringify(sched));
check('   one installment per month, starting next month', new Set(unpaid.map((s) => s.d.slice(0, 7))).size === 3 && unpaid.every((s) => s.d.endsWith('-01')));
check('   remaining balance = 600,000', Number((await q(`SELECT remaining_amount FROM loans WHERE id=$1`, [loan]))[0].remaining_amount) === 600000);
check('   employee notified', (await q(`SELECT 1 FROM notifications WHERE employee_id=$1 AND title LIKE 'تعديل تفاصيل السلفة%'`, [IDS.emp])).length === 1);
await expectError('   new amount below what was paid is rejected', as(db, 'admin', `SELECT reschedule_loan($1, 200000, 100000, 2)`, [loan]), 'أقل من المسدَّد');
await as(db, 'admin', `SELECT reschedule_loan($1, 900000, 150000, 5)`, [loan]);
const sched2 = await q(`SELECT amount FROM loan_installments WHERE loan_id=$1 AND NOT is_paid`, [loan]);
check('   rescheduling twice still reconciles (4 × 150,000)', sched2.length === 4 && sched2.reduce((a, s) => a + Number(s.amount), 0) === 600000, JSON.stringify(sched2));

// ---------------- 2) قرارات الحضور ----------------
await db.exec(`
  INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status) VALUES
    ('${OTHER}', '${B2}', '2026-10-05', 'absent', 'pending'),
    ('${IDS.manager}', '${IDS.branch}', '2026-10-06', 'absent', 'pending'),
    ('${IDS.emp}', '${IDS.branch}', '2026-10-07', 'absent', 'pending');
`);
await expectError('2) manager cannot excuse his own absence', as(db, 'manager', `UPDATE attendance SET deduction_status='ignored' WHERE employee_id=$1`, [IDS.manager]), 'حضورك');
await expectError('   manager cannot apply a deduction in another branch', as(db, 'manager', `UPDATE attendance SET deduction_status='applied' WHERE employee_id=$1`, [OTHER]), 'فرع آخر');
await expectError('   manager cannot record an absence in another branch', as(db, 'manager',
  `INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status) VALUES ($1, $2, '2026-10-08', 'absent', 'applied')`, [OTHER, B2]), 'فرع آخر');
await expectOk('   manager decides for his own branch', as(db, 'manager', `UPDATE attendance SET deduction_status='applied' WHERE employee_id=$1 AND work_date='2026-10-07'`, [IDS.emp]));
await expectOk('   admin (also an employee) can still manage attendance', as(db, 'admin', `UPDATE attendance SET deduction_status='ignored' WHERE employee_id=$1`, [OTHER]));

// ---------------- 3) الإجازات ----------------
const lv = (await as(db, 'emp', `INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status)
  VALUES ($1, '2026-11-03T21:00:00Z', '2026-11-04T21:00:00Z', 'annual', 'pending') RETURNING id`, [IDS.emp])).rows[0].id;
await expectError('3) employee cannot approve his own leave', as(db, 'emp', `UPDATE leave_requests SET status='approved' WHERE id=$1`, [lv]), '');
await expectOk('   employee cancels his pending leave', as(db, 'emp', `UPDATE leave_requests SET status='cancelled' WHERE id=$1`, [lv]));
check('   cancelled', (await q(`SELECT status FROM leave_requests WHERE id=$1`, [lv]))[0].status === 'cancelled');
await expectOk('   and can request the same dates again', as(db, 'emp', `INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status)
  VALUES ($1, '2026-11-03T21:00:00Z', '2026-11-04T21:00:00Z', 'annual', 'pending')`, [IDS.emp]));
const mgrLeave = (await as(db, 'manager', `INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status)
  VALUES ($1, '2026-11-10T21:00:00Z', '2026-11-10T21:00:00Z', 'annual', 'pending') RETURNING id`, [IDS.manager])).rows[0].id;
await expectError('   manager cannot approve his own leave', as(db, 'manager', `UPDATE leave_requests SET status='approved' WHERE id=$1`, [mgrLeave]), 'إجازتك');
await db.query(`INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status) VALUES ($1, '2026-11-14T21:00:00Z', '2026-11-14T21:00:00Z', 'annual', 'pending')`, [OTHER]);
await expectError('   manager cannot approve another branch leave', as(db, 'manager', `UPDATE leave_requests SET status='approved' WHERE employee_id=$1`, [OTHER]), 'فرع آخر');
await expectOk('   admin approves the manager leave', as(db, 'admin', `UPDATE leave_requests SET status='approved' WHERE id=$1`, [mgrLeave]));
await expectError('   leave more than 30 days in the past is refused', as(db, 'emp', `INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status)
  VALUES ($1, $2::date - 40, $2::date - 39, 'sick', 'pending')`, [IDS.emp, today]), '30 يوماً');
await expectOk('   a recent past sick leave (5 days ago) is accepted', as(db, 'emp', `INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status)
  VALUES ($1, ($2::date - 5)::timestamptz, ($2::date - 5)::timestamptz, 'sick', 'pending')`, [IDS.emp, today]));

// ---------------- 4) طلب سلفة مكرر ----------------
await expectOk('4) employee requests an advance', as(db, 'emp2', `INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
  VALUES ($1, 300000, 100000, 3, 300000, 'x', 'pending')`, [IDS.emp2]));
await expectError('   a second pending request is refused', as(db, 'emp2', `INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
  VALUES ($1, 300000, 100000, 3, 300000, 'x', 'pending')`, [IDS.emp2]), 'قيد المراجعة');

// ---------------- 5) مسير هذا الشهر للموظف ----------------
await db.exec(`INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status) VALUES ('${IDS.emp}', '${IDS.branch}', '${dayOffset(-1)}', 'absent', 'applied')
  ON CONFLICT (employee_id, work_date) DO UPDATE SET status='absent', deduction_status='applied'`);
const pv = (await as(db, 'emp', `SELECT get_my_payroll_preview() p`)).rows[0].p;
check('5) employee sees this month preview: own summary + events',
  pv && pv.summary.employee_id === IDS.emp && Number(pv.summary.monthly_salary) === 1200000
  && pv.events.some((e) => e.event_type === 'absence' && e.status === 'approved' && Number(e.amount) === 40000), JSON.stringify(pv?.events));
await expectError('   anonymous cannot call it', as(db, 'anon', `SELECT get_my_payroll_preview()`), 'permission denied');

// ---------------- 6) كشف معتمد لموظف معطّل ----------------
await db.query(`INSERT INTO salary_slips (employee_id, work_month, basic_salary, net_salary, status, computed_by_engine)
  VALUES ($1, '2026-11', 900000, 900000, 'published', true)`, [IDS.emp2]);
await db.exec(`UPDATE employees SET is_active = false, termination_date = '2026-09-29' WHERE id = '${IDS.emp2}'`);
const run = (await as(db, 'admin', `SELECT get_payroll_run('2026-11') r`)).rows[0].r;
check('6) an approved slip stays visible after the employee is disabled', run.rows.some((r) => r.employee_id === IDS.emp2 && r.slip));

done();
