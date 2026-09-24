import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const bal = async (id) => (await db.query(`SELECT annual_used, sick_used FROM leave_balances WHERE employee_id=$1`, [id])).rows[0];

// ---------------- leave balances ----------------
check('every employee has a balance row', (await db.query(`SELECT count(*)::int n FROM leave_balances`)).rows[0].n === 4);
await db.exec(`INSERT INTO employees (id, employee_code, full_name) VALUES ('00000000-0000-0000-0000-0000000000f1','N1','جديد')`);
check('new employee gets a balance row automatically',
  (await db.query(`SELECT 1 FROM leave_balances WHERE employee_id='00000000-0000-0000-0000-0000000000f1'`)).rows.length === 1);

// 3 calendar days in Baghdad time (dates stored as UTC like the app does)
const lr = (await as(db, 'emp', `INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status)
  VALUES ($1, '2026-10-04T21:00:00Z', '2026-10-06T21:00:00Z', 'annual', 'pending') RETURNING id`, [IDS.emp])).rows[0].id;
check('pending leave does not touch balance', (await bal(IDS.emp)).annual_used === 0);

await as(db, 'admin', `UPDATE leave_requests SET status='approved' WHERE id=$1`, [lr]);
check('approved 3-day annual leave deducts 3 days', (await bal(IDS.emp)).annual_used === 3, JSON.stringify(await bal(IDS.emp)));

await as(db, 'admin', `UPDATE leave_requests SET status='rejected' WHERE id=$1`, [lr]);
const lr2 = (await as(db, 'emp', `INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status, reason)
  VALUES ($1, '2026-11-01T21:00:00Z', '2026-11-02T21:00:00Z', 'annual', 'pending', 'سفر عائلي') RETURNING id`, [IDS.emp])).rows[0].id;
await as(db, 'admin', `UPDATE leave_requests SET status='rejected', rejection_reason='ضغط عمل' WHERE id=$1`, [lr2]);
check('un-approving returns the days', (await bal(IDS.emp)).annual_used === 0);
const n = await db.query(`SELECT body FROM notifications WHERE employee_id=$1 AND type='leave' ORDER BY created_at`, [IDS.emp]);
check('decision notification uses admin rejection reason',
  n.rows.some((r) => r.body.includes('ضغط عمل')) && !n.rows.some((r) => r.body.includes('سفر عائلي')), JSON.stringify(n.rows));

const hourly = (await as(db, 'emp', `INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, is_hourly, status)
  VALUES ($1, '2026-10-10T05:00:00Z', '2026-10-10T08:00:00Z', 'sick', true, 'pending') RETURNING id`, [IDS.emp])).rows[0].id;
await as(db, 'admin', `UPDATE leave_requests SET status='approved' WHERE id=$1`, [hourly]);
check('hourly leave is not deducted', (await bal(IDS.emp)).sick_used === 0);

await expectError('employee still cannot edit own balance',
  as(db, 'emp', `UPDATE leave_balances SET annual_used = 0 WHERE employee_id=$1 RETURNING 1`, [IDS.emp])
    .then((x) => { if (!x.rows.length) throw new Error('blocked by RLS'); }), 'blocked by RLS');

// ---------------- payroll ----------------
const loan = (await db.query(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
  VALUES ($1, 300000, 100000, 3, 300000, 'x', 'approved') RETURNING id`, [IDS.emp])).rows[0].id;
await db.exec(`INSERT INTO loan_installments (loan_id, due_date, amount) VALUES
  ('${loan}', '2026-09-20', 100000), ('${loan}', '2026-10-20', 100000), ('${loan}', '2026-11-20', 100000);`);
const inst = (await db.query(`SELECT id FROM loan_installments WHERE loan_id=$1 ORDER BY due_date`, [loan])).rows.map((r) => r.id);

const adjustments = JSON.stringify([
  { type: 'deduction', amount: 25000, reason: 'خصم غياب غير مبرر (1 يوم) للفترة من 2026-08-25 إلى 2026-09-24', issue_date: '2026-09-24', skip_if_exists: true },
  { type: 'bonus', amount: 50000, reason: 'تسوية زيادة مكافآت يدوياً لشهر 2026-09', issue_date: '2026-09-24' },
  { type: 'bonus', amount: 0, reason: 'zero is ignored' },
]);
const approve = (who, instIds, adj = adjustments) => as(db, who,
  `SELECT approve_salary_slip($1, '2026-09', 1000000, 50000, 25000, 100000, 925000, $2::uuid[], $3::jsonb) AS id`,
  [IDS.emp, `{${instIds.join(',')}}`, adj]);

await expectError('employee cannot approve salaries', approve('emp', [inst[0]]), 'غير مصرح');

// atomicity: a bad adjustment makes the whole approval fail with nothing written
await expectError('invalid adjustment rolls back everything',
  approve('admin', [inst[0]], JSON.stringify([{ type: 'gift', amount: 5, reason: 'bad type' }])), 'bonuses_deductions_type_check');
check('no slip left behind after failure', (await db.query(`SELECT count(*)::int n FROM salary_slips`)).rows[0].n === 0);
check('installment not marked paid after failure',
  (await db.query(`SELECT is_paid FROM loan_installments WHERE id=$1`, [inst[0]])).rows[0].is_paid === false);

const slipId = (await approve('admin', [inst[0]])).rows[0].id;
check('approval creates slip', !!slipId);
const i0 = (await db.query(`SELECT is_paid, paid_by_slip_id FROM loan_installments WHERE id=$1`, [inst[0]])).rows[0];
check('installment paid and linked to slip', i0.is_paid === true && i0.paid_by_slip_id === slipId);
const bd = (await db.query(`SELECT count(*)::int n FROM bonuses_deductions WHERE salary_slip_id=$1`, [slipId])).rows[0].n;
check('two adjustments linked (zero ignored)', bd === 2, `got ${bd}`);
check('loan remaining recalculated by trigger',
  Number((await db.query(`SELECT remaining_amount FROM loans WHERE id=$1`, [loan])).rows[0].remaining_amount) === 200000);

await expectError('double approval is rejected', approve('admin', [inst[1]]), 'مسبقاً');

// a manual installment payment in the same period must survive the revert
await db.exec(`UPDATE loan_installments SET is_paid = true, paid_at = now() WHERE id = '${inst[1]}'`);
await expectOk('admin can revert', as(db, 'admin', `SELECT revert_salary_slip($1, '2026-08-25', '2026-10-24')`, [slipId]));
check('slip deleted', (await db.query(`SELECT count(*)::int n FROM salary_slips`)).rows[0].n === 0);
check('linked adjustments deleted', (await db.query(`SELECT count(*)::int n FROM bonuses_deductions`)).rows[0].n === 0);
check('slip installment back to unpaid', (await db.query(`SELECT is_paid FROM loan_installments WHERE id=$1`, [inst[0]])).rows[0].is_paid === false);
check('manually paid installment untouched', (await db.query(`SELECT is_paid FROM loan_installments WHERE id=$1`, [inst[1]])).rows[0].is_paid === true);

// archived month is locked
await db.exec(`INSERT INTO archived_months (work_month) VALUES ('2026-09')`);
await expectError('cannot approve into archived month', approve('admin', [inst[0]]), 'مؤرشف');

done();
