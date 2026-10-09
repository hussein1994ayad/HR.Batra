// تصليحات الفلوس (فحص 2026-10-09): حذف/تراجع الأقساط، تكرار الخصومات اليدوية، سجل الرواتب والزيادة المجدولة،
// الاعتماد بعد نهاية الفترة، وتقليص القسط بدل الصافي السالب.
import fs from 'node:fs';
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];
const migration = fs.readFileSync(new URL('../migrations/20261011000000_payroll_money_fixes.sql', import.meta.url), 'utf8');

await db.exec(`UPDATE employees SET join_date = '2026-01-01'`);
const today = (await one(`SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date::text d`)).d;
const curMonth = (await one(`SELECT payroll_month_of($1::date) m`, [today])).m;
const prevMonth = (await one(`SELECT payroll_month_add($1, -1) m`, [curMonth])).m;
const cur = await one(`SELECT start_date::text s, cutoff_date::text c FROM ensure_payroll_period($1)`, [curMonth]);
const prev = await one(`SELECT start_date::text s, cutoff_date::text c FROM ensure_payroll_period($1)`, [prevMonth]);

const newEmp = async (code, salary = 600000) => {
  const id = (await one('SELECT gen_random_uuid()::text id')).id;
  await q(`INSERT INTO auth.users (id, email) VALUES ($1, $2)`, [id, `${code}@x`]);
  await q(`INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ($1, $2, $2, 'employee', $3, $4, '2026-01-01', false)`, [id, code, IDS.branch, salary]);
  return id;
};
const loanWith = async (emp, rows) => {
  const total = rows.reduce((s, r) => s + r[1], 0);
  const id = (await one(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
    VALUES ($1, $2, $3, $4, $2, 'p.png', 'approved') RETURNING id`, [emp, total, rows[0][1], rows.length])).id;
  await q(`SELECT set_config('loans.skip_rebalance', 'on', false)`);
  for (const [due, amount, paid] of rows) {
    await q(`INSERT INTO loan_installments (loan_id, due_date, amount, is_paid, paid_at, payment_type) VALUES ($1, $2, $3, $4, CASE WHEN $4 THEN now() END, 'cash')`,
      [id, due, amount, !!paid]);
  }
  await q(`SELECT set_config('loans.skip_rebalance', 'off', false)`);
  return id;
};
const inst = async (loan) => q(`SELECT id, to_char(due_date, 'YYYY-MM-DD') d, amount::int a, is_paid p, origin_kind k FROM loan_installments WHERE loan_id = $1 ORDER BY due_date, id`, [loan]);

// ---------------- 1) حذف قسط مسدد ----------------
const e1 = await newEmp('PM1');
const l1 = await loanWith(e1, [['2026-11-26', 100000, true], ['2026-12-26', 100000], ['2027-01-26', 100000]]);
const paid1 = (await inst(l1))[0];
const before1 = JSON.stringify(await inst(l1));
await expectError('1) deleting a paid installment is refused (it would turn into debt again)',
  as(db, 'admin', `DELETE FROM loan_installments WHERE id = $1`, [paid1.id]), 'ما ينحذف');
check('   the schedule is untouched (no new month added)', JSON.stringify(await inst(l1)) === before1);
await expectOk('   deleting the whole loan (with its paid installments) still works', as(db, 'admin', `DELETE FROM loans WHERE id = $1`, [l1]));

// ---------------- 2) التراجع عن قسط انخصم من راتب ----------------
const e2 = await newEmp('PM2');
const l2 = await loanWith(e2, [[prev.c, 100000], ['2027-01-26', 100000]]);
await expectOk('2) previous month salary is approved (deducts the installment)', as(db, 'admin', `SELECT approve_payroll_slip($1, $2) r`, [e2, prevMonth]));
const slipPaid = (await inst(l2))[0];
check('   the installment is paid by the slip', slipPaid.p === true);
await expectError('   undoing it from the loans page is refused', as(db, 'admin',
  `UPDATE loan_installments SET is_paid = false, paid_at = NULL WHERE id = $1`, [slipPaid.id]), 'ألغِ اعتماد');
await expectError('   changing its amount is refused', as(db, 'admin', `UPDATE loan_installments SET amount = 1 WHERE id = $1`, [slipPaid.id]), 'ألغِ اعتماد');
const slip2 = (await one(`SELECT id FROM salary_slips WHERE employee_id = $1 AND work_month = $2`, [e2, prevMonth])).id;
await expectOk('   reverting the salary slip itself still frees it', as(db, 'admin', `SELECT revert_payroll_slip($1)`, [slip2]));
check('   ...and the installment is unpaid again', (await inst(l2))[0].p === false);

// ---------------- 3) الخصومات اليدوية: منو سجّلها + ما تتكرر ----------------
const e3 = await newEmp('PM3');
const bd = (who, amount = 25000, reason = 'سبب') => as(db, who,
  `INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date) VALUES ($1, 'deduction', $2, $3, $4) RETURNING created_by`,
  [e3, amount, reason, cur.s]);
const first = await expectOk('3) a manual deduction is recorded', bd('admin'));
check('   with who recorded it (even if the app did not send it)', first?.rows[0].created_by === IDS.admin, JSON.stringify(first?.rows));
await expectError('   the same deduction again within minutes is refused', bd('admin'), 'قبل دقائق');
await expectOk('   a different amount is fine', bd('admin', 30000));

// التنظيف: نسخ مكررة قديمة بدون منشئ + «تأخير مفقود» لنفس يوم تأخير المحرّك
const e4 = await newEmp('PM4');
await db.exec(`ALTER TABLE bonuses_deductions DISABLE TRIGGER trg_guard_bonus_deduction_entry`);
await q(`INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date, created_at) VALUES
  ($1, 'deduction', 25000, 'تم الخصم بناءً على تعليمات الإدارة', $2, now() - interval '20 seconds'),
  ($1, 'deduction', 25000, 'تم الخصم بناءً على تعليمات الإدارة', $2, now() - interval '14 seconds'),
  ($1, 'deduction', 39450, 'تأخير مفقود: 13 ساعة و 9 دقائق', $2, now()),
  ($1, 'deduction', 39450, 'تأخير مفقود: 13 ساعة و 9 دقائق', $3, now())`, [e4, cur.s, prev.s]);
await db.exec(`ALTER TABLE bonuses_deductions ENABLE TRIGGER trg_guard_bonus_deduction_entry`);
await q(`INSERT INTO payroll_events (employee_id, event_date, event_type, minutes, amount, direction, payroll_month, status, source)
  VALUES ($1, $2, 'late', 353, 23533, -1, $3, 'pending', 'attendance')`, [e4, cur.s, curMonth]);
await expectOk('   the cleanup runs', db.exec(migration));
const left = await q(`SELECT reason, amount::int a, issue_date::text d FROM bonuses_deductions WHERE employee_id = $1 ORDER BY created_at`, [e4]);
check('   one copy of the duplicate is kept, the late duplicate of an engine late day is removed, other days untouched',
  left.length === 2 && left[0].a === 25000 && left.some((r) => r.d === prev.s && r.a === 39450), JSON.stringify(left));
check('   recorded deductions with a creator are never touched by the cleanup',
  (await one(`SELECT count(*)::int c FROM bonuses_deductions WHERE employee_id = $1`, [e3])).c === 2);

// ---------------- 4) سجل الرواتب والزيادة المجدولة ----------------
const e5 = await newEmp('PM5', 600000);
await q(`UPDATE employees SET future_salary_iqd = 800000, future_salary_month = '2026/06/01' WHERE id = $1`, [e5]);
const sal = async (m) => Number((await one(`SELECT payroll_basic_salary($1, $2) s`, [e5, m])).s);
check('4) a scheduled raise written as 2026/06/01 now applies from June', (await sal('2026-05')) === 600000 && (await sal('2026-06')) === 800000
  && (await sal(curMonth)) === 800000, JSON.stringify([await sal('2026-05'), await sal('2026-06'), await sal(curMonth)]));
await q(`SELECT apply_due_salary_changes()`);
const e5row = await one(`SELECT monthly_salary_iqd::int s, future_salary_iqd f FROM employees WHERE id = $1`, [e5]);
check('   a due raise becomes the current salary and keeps its start month in the history',
  e5row.s === 800000 && e5row.f === null && (await sal('2026-06')) === 800000 && (await sal('2026-05')) === 600000, JSON.stringify(e5row));
const future = (await one(`SELECT payroll_month_add($1, 3) m`, [curMonth])).m;
await q(`UPDATE employees SET future_salary_iqd = 1000000, future_salary_month = $2 WHERE id = $1`, [e5, `${future}-01`]);
check('   a future raise applies only from its month', (await sal(curMonth)) === 800000 && (await sal(future)) === 1000000);
await q(`UPDATE employees SET future_salary_iqd = NULL, future_salary_month = NULL WHERE id = $1`, [e5]);
check('   cancelling a future raise removes it', (await sal(future)) === 800000);
await q(`UPDATE employees SET monthly_salary_iqd = 900000 WHERE id = $1`, [e5]);
check('   a direct change applies from the current payroll month, older months keep their salary',
  (await sal(curMonth)) === 900000 && (await sal(prevMonth)) === 800000, JSON.stringify([await sal(prevMonth), await sal(curMonth)]));
check('   employees see their own salary history only',
  (await as(db, 'emp', `SELECT count(*)::int c FROM salary_history WHERE employee_id = $1`, [e5])).rows[0].c === 0);

// ---------------- 6) الاعتماد بعد نهاية فترة الدوام ----------------
const e6 = await newEmp('PM6');
await expectError('6) approving the current month before its cutoff is refused', as(db, 'admin', `SELECT approve_payroll_slip($1, $2)`, [e6, curMonth]),
  'بعد نهاية الدوام');
if (today > cur.s) {
  await q(`UPDATE employees SET is_active = false, termination_date = $2 WHERE id = $1`, [e6, cur.s]);
  await expectOk('   ...except the last salary of someone who left', as(db, 'admin', `SELECT approve_payroll_slip($1, $2)`, [e6, curMonth]));
}
await expectOk('   a finished month is approved normally', as(db, 'admin', `SELECT approve_payroll_slip($1, $2)`, [await newEmp('PM6b'), prevMonth]));

// ---------------- 8) قسط أكبر من الراتب: ينقص بدل ما يوقف الاعتماد ----------------
const e8 = await newEmp('PM8', 300000);
const l8 = await loanWith(e8, [[prev.c, 500000], ['2027-03-26', 500000]]);
await q(`UPDATE loans SET installment_amount = 500000 WHERE id = $1`, [l8]);
await expectOk('8) a 500k installment on a 300k salary no longer blocks the approval', as(db, 'admin', `SELECT approve_payroll_slip($1, $2)`, [e8, prevMonth]));
const s8 = await one(`SELECT net_salary::int n, loans_deduction::int l FROM salary_slips WHERE employee_id = $1 AND work_month = $2`, [e8, prevMonth]);
check('   the salary covers 300k of the installment, net 0', s8.n === 0 && s8.l === 300000, JSON.stringify(s8));
const r8 = await inst(l8);
check('   the missing 200k became a new last month marked as the rest of that month',
  r8.length === 3 && r8[0].a === 300000 && r8[0].p && r8.at(-1).a === 200000 && r8.at(-1).k === 'shortfall', JSON.stringify(r8));
check('   the loan total is unchanged', r8.reduce((s, r) => s + r.a, 0) === 1000000);
check('   the employee is told', (await one(`SELECT count(*)::int c FROM notifications WHERE employee_id = $1 AND body LIKE '%ما يكفي%'`, [e8])).c === 1);

done();
