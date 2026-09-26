import { setup, as, IDS, check, done } from './lib.mjs';
const db = await setup();
const r = await as(db, 'emp', `SELECT request_account_deletion() AS n`);
check('deletion request reaches the admin', r.rows[0].n === 1);
const again = await as(db, 'emp', `SELECT request_account_deletion() AS n`);
check('repeat request same day is not duplicated', again.rows[0].n === 0);
const own = await db.query(`SELECT count(*)::int n FROM notifications WHERE employee_id=$1`, [IDS.emp]);
check('employee does not notify themselves', own.rows[0].n === 0);
done();
