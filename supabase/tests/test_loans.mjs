import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();

const request = async (employee, amount = 1000000, months = 4) =>
  (await as(db, employee, `INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
    VALUES ($1, $2, $4, $3, $2, 'pledge.png', 'pending') RETURNING id`, [IDS[employee], amount, months, Math.floor(amount / months)])).rows[0].id;
const approve = (who, id, amount, months, firstDue = '2026-01-31') =>
  as(db, who, `SELECT approve_loan($1, $2, $3, $4::date)`, [id, amount, months, firstDue]);
const installments = async (id) =>
  (await db.query(`SELECT to_char(due_date, 'YYYY-MM-DD') d, amount::int a FROM loan_installments WHERE loan_id=$1 ORDER BY due_date`, [id])).rows;

const loan = await request('emp');
const adminNotif = await db.query(`SELECT body FROM notifications WHERE employee_id=$1 AND type='loan'`, [IDS.admin]);
check('a new loan request inserts and notifies admins with the installment count',
  adminNotif.rows.some((r) => r.body.includes('على 4 قسط')), JSON.stringify(adminNotif.rows));

await expectError('employee cannot approve a loan', approve('emp', loan, 1000000, 3), 'غير مصرح');
await expectError('manager cannot approve a loan', approve('manager', loan, 1000000, 3), 'غير مصرح');
await expectError('zero months is rejected', approve('admin', loan, 1000000, 0), 'أكبر من الصفر');
await expectError('installment above half the salary is rejected', approve('admin', loan, 1000000, 1), '50%');

await expectOk('admin approves with edited months', approve('admin', loan, 1000000, 3));
const row = (await db.query(`SELECT status, installment_count, installment_amount::int ia, remaining_amount::int ra, approved_by FROM loans WHERE id=$1`, [loan])).rows[0];
check('loan row is fully updated',
  row.status === 'approved' && row.installment_count === 3 && row.ia === 333333 && row.ra === 1000000 && row.approved_by === IDS.admin,
  JSON.stringify(row));

const inst = await installments(loan);
check('installments sum to the loan amount exactly', inst.reduce((s, r) => s + r.a, 0) === 1000000, JSON.stringify(inst));
check('last installment absorbs the rounding', inst.map((r) => r.a).join() === '333333,333333,333334');
check('due dates clamp to month end', inst.map((r) => r.d).join() === '2026-01-31,2026-02-28,2026-03-31', JSON.stringify(inst));

await expectError('a processed request cannot be approved twice', approve('admin', loan, 1000000, 3), 'مسبقاً');

const second = await request('emp', 300000, 3);
await expectError('employee with an unpaid loan cannot get another', approve('admin', second, 300000, 3), 'سلفة نشطة');

await db.exec(`UPDATE loans SET remaining_amount = 0 WHERE id = '${loan}'`);
await expectOk('a fully paid loan no longer blocks a new one', approve('admin', second, 300000, 3, '2026-05-15'));

const notif = await db.query(`SELECT 1 FROM notifications WHERE employee_id=$1 AND type='loan'`, [IDS.emp]);
check('approval still notifies the employee (existing trigger)', notif.rows.length > 0);

done();
