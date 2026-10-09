// الرواتب والسلف سوا: شهر رواتب القسط، أقساط هالمسير وأسبابها، الراتب الجزئي لمن ترك، تسوية السلفة عند ترك العمل،
// ورفض «استقطاع راتب» اليدوي قبل الكشف + التصليح العام له.
import fs from 'node:fs';
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];

await db.exec(`UPDATE employees SET join_date = '2026-01-01'`);
const p10 = await one(`SELECT start_date::text s, cutoff_date::text c FROM ensure_payroll_period('2026-10')`);
await db.query(`SELECT ensure_payroll_period('2026-11')`);
check('october payroll runs 27/9 → 26/10', p10.s === '2026-09-27' && p10.c === '2026-10-26', JSON.stringify(p10));

// ---------------- شهر الرواتب اللي يتبعه التاريخ ----------------
const pm = async (d) => (await one(`SELECT payroll_month_of($1::date) m`, [d])).m;
check('an installment on 26/10 belongs to October payroll', (await pm('2026-10-26')) === '2026-10');
check('an installment on 28/10 belongs to November payroll', (await pm('2026-10-28')) === '2026-11');
check('a date without a period uses the policy cutoff day', (await pm('2027-05-27')) === '2027-06' && (await pm('2027-05-20')) === '2027-05');

// ---------------- الراتب الجزئي: داوم 3 أيام وترك ----------------
const LEFT = '00000000-0000-0000-0000-0000000000f1';
await db.exec(`
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ('${LEFT}', 'F1', 'داوم ثلاث أيام', '${IDS.branch}', 600000, '2026-01-01', false);
  INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
    VALUES ('${LEFT}', 'صباحي', '09:00', '17:00', 15, '{0,1,2,3,4,5,6}');
  UPDATE work_schedule_history SET effective_from = '-infinity';
`);
for (const d of ['2026-09-27', '2026-09-28', '2026-09-29']) {
  await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time)
    VALUES ($1, $2, $3, 'present', $4, $5)`, [LEFT, IDS.branch, d, `${d} 09:00:00+03`, `${d} 17:00:00+03`]);
}
// الأدمن يعطّله ويكتب آخر يوم دوام (نفس شاشة الموظفين)
await db.query(`UPDATE employees SET is_active = false, termination_date = '2026-09-29' WHERE id = $1`, [LEFT]);
const s3 = await one(`SELECT payroll_employee_summary($1, '2026-10') r`, [LEFT]);
check('worked 3 days then left: paid 3 days only (3 × 600,000 ÷ 30 = 60,000)',
  Number(s3.r.basic) === 60000 && s3.r.employed_days === 3, JSON.stringify({ basic: s3.r.basic, days: s3.r.employed_days }));
check('attended and scheduled days are shown (3 of 3)', s3.r.attended_days === 3 && s3.r.scheduled_days === 3,
  JSON.stringify({ a: s3.r.attended_days, s: s3.r.scheduled_days }));

// ---------------- أقساط هالمسير: عادي، مؤجّل، نقدي مسدد، مبلغ مخفّض، بعد يوم القطع ----------------
const E = IDS.emp;
const loan = (await q(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
  VALUES ($1, 900000, 100000, 9, 900000, 'p.png', 'approved') RETURNING id`, [E]))[0].id;
await db.query(`SELECT set_config('loans.skip_rebalance', 'on', false)`);
const ins = async (due, amount, extra = {}) => (await q(`INSERT INTO loan_installments (loan_id, due_date, amount, is_paid, payment_type, amount_locked, origin_kind, origin_month)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
  [loan, due, amount, extra.paid ?? false, extra.type ?? 'salary_deduction', extra.locked ?? false, extra.kind ?? null, extra.origin ?? null]))[0].id;
await ins('2026-10-01', 40000, { locked: true });               // هالشهر أقل
await ins('2026-10-10', 100000, { paid: true, type: 'cash' });   // انسدد نقداً
await ins('2026-10-26', 100000);                                 // قسط عادي يوم القطع
await ins('2026-10-28', 100000);                                 // بعد القطع ← رواتب شهر 11
await ins('2027-02-26', 60000, { kind: 'shortfall', origin: '2026-10-01' }); // باقي شهر 10
await ins('2027-03-26', 100000, { kind: 'postponed', origin: '2026-10-15' }); // مؤجّل من شهر 10
await db.query(`SELECT set_config('loans.skip_rebalance', 'off', false)`);

const s = (await one(`SELECT payroll_employee_summary($1, '2026-10') r`, [E])).r;
check('october deducts only the reduced amount and the regular installment (not cash-paid, not postponed, not after cutoff)',
  Number(s.loans) === 140000 && s.loan_items.length === 2, JSON.stringify(s.loan_items));
check('loan items explain the reduced month', s.loan_items[0].amount_locked === true && Number(s.loan_items[0].amount) === 40000);
check('net is unchanged by the new info (basic − loans)', Number(s.net) === Number(s.basic) + Number(s.earnings) - Number(s.deductions) - 140000);
const s11 = (await one(`SELECT payroll_employee_summary($1, '2026-11') r`, [E])).r;
check('the installment dated 28/10 is deducted with november', Number(s11.loans) === 100000, String(s11.loans));

// ---------------- رفض «استقطاع راتب» اليدوي قبل الكشف ----------------
const regular = (await one(`SELECT id FROM loan_installments WHERE loan_id = $1 AND due_date = '2026-10-26'`, [loan])).id;
await expectError('manual "salary deduction" before the october slip is refused',
  as(db, 'admin', `SELECT pay_loan_installment($1, 100000, 'salary_deduction', NULL)`, [regular]), 'هالشهر أقل');
await expectOk('cash is always allowed', as(db, 'admin', `SELECT pay_loan_installment($1, 100000, 'cash', 'وصل')`, [regular]));

// ---------------- ترك العمل وعليه سلفة: اخصم الباقي من آخر راتب ----------------
const X = '00000000-0000-0000-0000-0000000000f2';
await db.exec(`
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ('${X}', 'F2', 'ترك وعليه سلفة', '${IDS.branch}', 900000, '2026-01-01', false);
`);
const xl = (await q(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
  VALUES ($1, 500000, 100000, 5, 500000, 'p.png', 'approved') RETURNING id`, [X]))[0].id;
await db.query(`SELECT set_config('loans.skip_rebalance', 'on', false)`);
for (const [i, d] of ['2026-10-20', '2026-11-20', '2026-12-20', '2027-01-20', '2027-02-20'].entries()) {
  await db.query(`INSERT INTO loan_installments (loan_id, due_date, amount) VALUES ($1, $2, 100000)`, [xl, d]);
  void i;
}
await db.query(`SELECT set_config('loans.skip_rebalance', 'off', false)`);
await expectError('only for someone who left during this payroll', as(db, 'admin', `SELECT settle_loan_on_exit($1, '2026-10', 100000)`, [X]), 'ما ترك');
await db.query(`UPDATE employees SET is_active = false, termination_date = '2026-10-15' WHERE id = $1`, [X]);
const before = (await one(`SELECT payroll_employee_summary($1, '2026-10') r`, [X])).r;
check('leaving shows the rest of the loan as a warning (400k after this month)', Number(before.loan_balance_after_exit) === 400000,
  String(before.loan_balance_after_exit));
await expectError('employees cannot settle', as(db, 'emp', `SELECT settle_loan_on_exit($1, '2026-10', 100000)`, [X]), 'غير مصرح');
await expectError('cannot take more than what is left', as(db, 'admin', `SELECT settle_loan_on_exit($1, '2026-10', 500000)`, [X]), 'بين 1');
await expectOk('admin deducts 300k of the rest from the last salary', as(db, 'admin', `SELECT settle_loan_on_exit($1, '2026-10', 300000)`, [X]));
const after = (await one(`SELECT payroll_employee_summary($1, '2026-10') r`, [X])).r;
check('last salary deducts this month + 300k', Number(after.loans) === 400000 && Number(after.loan_balance_after_exit) === 100000,
  JSON.stringify({ loans: after.loans, left: after.loan_balance_after_exit }));
const restRow = await one(`SELECT amount::int a, payment_type t FROM loan_installments WHERE loan_id = $1 AND due_date > '2026-10-26'`, [xl]);
check('the remaining 100k stays as one cash installment', restRow.a === 100000 && restRow.t === 'cash', JSON.stringify(restRow));
check('loan total is unchanged', (await one(`SELECT sum(amount)::int s FROM loan_installments WHERE loan_id = $1`, [xl])).s === 500000);

// ---------------- التصليح العام: «استقطاع راتب» انسجل مسدد يدوياً قبل الكشف ----------------
const M = IDS.emp2;
const ml = (await q(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
  VALUES ($1, 500000, 250000, 2, 400000, 'p.png', 'approved') RETURNING id`, [M]))[0].id;
await db.query(`SELECT set_config('loans.skip_rebalance', 'on', false)`);
await db.query(`INSERT INTO loan_installments (loan_id, due_date, amount, is_paid, paid_at, payment_type) VALUES
  ($1, '2026-10-01', 100000, true, now(), 'salary_deduction'), ($1, '2026-11-01', 400000, false, NULL, 'salary_deduction')`, [ml]);
await db.query(`SELECT set_config('loans.skip_rebalance', 'off', false)`);
const migration = fs.readFileSync(new URL('../migrations/20261010000000_payroll_loans_clarity.sql', import.meta.url), 'utf8');
await expectOk('the repair runs', db.exec(migration));
const fixed = await q(`SELECT to_char(due_date, 'YYYY-MM-DD') d, amount::int a, is_paid p, amount_locked l, origin_kind k, to_char(origin_month, 'YYYY-MM-DD') o
  FROM loan_installments WHERE loan_id = $1 ORDER BY due_date`, [ml]);
check('october 100k is back to unpaid (the october slip deducts it), november 250k, december 150k = rest of october',
  fixed.length === 3 && fixed[0].a === 100000 && !fixed[0].p && fixed[0].l === true
    && fixed[1].a === 250000 && fixed[2].a === 150000 && fixed[2].d === '2026-12-01' && fixed[2].k === 'shortfall' && fixed[2].o === '2026-10-01',
  JSON.stringify(fixed));
check('october payroll now deducts the 100k', Number((await one(`SELECT payroll_employee_summary($1, '2026-10') r`, [M])).r.loans) === 100000);
check('cash payments are not touched by the repair',
  (await one(`SELECT is_paid p FROM loan_installments WHERE loan_id = $1 AND payment_type = 'cash' AND due_date = '2026-10-10'`, [loan])).p === true);
await db.exec(migration);
check('running it again changes nothing', JSON.stringify(await q(`SELECT due_date, amount, is_paid FROM loan_installments WHERE loan_id = $1 ORDER BY due_date`, [ml]))
  === JSON.stringify(await q(`SELECT due_date, amount, is_paid FROM loan_installments WHERE loan_id = $1 ORDER BY due_date`, [ml])));

done();
