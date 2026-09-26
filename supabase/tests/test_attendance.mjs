import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const IN = [33.3000, 44.4000];       // branch centre
const FAR = [33.3100, 44.4000];      // ~1.1 km away
const punch = (who, type, [lat, lng], extra = '') =>
  as(db, who, `SELECT punch_attendance('${type}', ${lat}, ${lng}${extra}) AS r`).then((r) => r.rows[0].r);
const offsetTime = (mins) => new Date(Date.now() + mins * 60000).toISOString();

// schedule: employee-specific 00:00–23:59 wins over branch schedule
await db.exec(`
  INSERT INTO work_schedules (branch_id, name, check_in_time, check_out_time, work_days, created_at)
    VALUES ('${IDS.branch}', 'فرع', '08:00', '16:00', '{0,1,2,3,4}', now() - interval '1 day');
  INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
    SELECT '${IDS.emp}', 'خاص', ((now() AT TIME ZONE 'Asia/Baghdad') - interval '5 minutes')::time, '23:59', 30, '{0,1,2,3,4,5,6}';`);

const sched = await as(db, 'emp', `SELECT name FROM get_effective_work_schedule()`);
check('effective schedule prefers employee-specific over branch', sched.rows[0]?.name === 'خاص', JSON.stringify(sched.rows));
await expectError('employee cannot read another employee schedule',
  as(db, 'emp', `SELECT * FROM get_effective_work_schedule($1)`, [IDS.emp2]), 'غير مصرح');

// direct writes are gone
await expectError('employee can no longer insert attendance directly',
  as(db, 'emp', `INSERT INTO attendance (employee_id, branch_id, status, check_in_time) VALUES ($1,$2,'present',now())`,
    [IDS.emp, IDS.branch]), 'row-level security');

let r = await punch('emp', 'check_in', FAR);
check('out-of-range check-in is rejected', r.ok === false && r.code === 'out_of_range', JSON.stringify(r));

r = await punch('emp', 'check_in', IN, `, NULL, true`);
check('mocked location is rejected', r.ok === false && r.code === 'mock_gps', JSON.stringify(r));
const mocks = await db.query(`SELECT count(*)::int n FROM mock_gps_attempts WHERE employee_id = $1`, [IDS.emp]);
check('mock attempt is recorded', mocks.rows[0].n === 1);

r = await punch('emp', 'check_in', IN);
check('check-in succeeds with present status', r.ok === true && r.status === 'present', JSON.stringify(r));
r = await punch('emp', 'check_in', IN);
check('duplicate check-in is rejected', r.ok === false && r.code === 'already_checked_in');

// the bug: check-out used to silently fail for employees
r = await punch('emp', 'check_out', IN);
check('check-out is saved', r.ok === true && r.check_out_time !== null, JSON.stringify(r));
const row = await db.query(`SELECT check_in_time, check_out_time FROM attendance WHERE employee_id = $1`, [IDS.emp]);
check('attendance row has both times', row.rows.length === 1 && row.rows[0].check_out_time !== null);
r = await punch('emp', 'check_out', IN);
check('duplicate check-out is rejected', r.ok === false && r.code === 'already_checked_out');

// branch schedule 08:00-16:00 applies to emp2: check-out only → half day
r = await punch('emp2', 'check_out', IN);
check('check-out without check-in becomes half_day', r.ok && r.status === 'half_day', JSON.stringify(r));

// offline punches (use a fresh employee day by deleting emp2 row)
await db.exec(`DELETE FROM attendance WHERE employee_id = '${IDS.emp2}'`);
r = await punch('emp2', 'check_in', IN, `, NULL, false, '${offsetTime(60)}'`);
check('offline punch in the future is rejected', r.ok === false && r.code === 'clock_in_future', JSON.stringify(r));
r = await punch('emp2', 'check_in', IN, `, NULL, false, '${offsetTime(-60 * 72)}'`);
check('offline punch older than 48h is rejected', r.ok === false && r.code === 'offline_too_old', JSON.stringify(r));
r = await punch('emp2', 'check_in', IN, `, NULL, false, '${offsetTime(-30)}'`);
check('recent offline punch is accepted and flagged', r.ok === true && r.offline === true, JSON.stringify(r));
const off = await db.query(`SELECT check_in_offline FROM attendance WHERE employee_id = $1`, [IDS.emp2]);
check('offline flag stored', off.rows[0]?.check_in_offline === true);

// branch schedule 08:00 + 15 min grace: yesterday 09:00 Baghdad → late
const y9 = (await db.query(`SELECT ((((now() AT TIME ZONE 'Asia/Baghdad')::date - 1) + time '09:00') AT TIME ZONE 'Asia/Baghdad') AS t`)).rows[0].t.toISOString();
r = await punch('emp2', 'check_in', IN, `, NULL, false, '${y9}'`);
check('check-in after grace period is late', r.ok && r.status === 'late', JSON.stringify(r));

// ---------------- device lock ----------------
const reg = (who, dev, legacy = null) =>
  as(db, who, `SELECT register_device_login($1, 'Pixel', 'Android 14', $2) AS r`, [dev, legacy]).then((x) => x.rows[0].r);

await db.exec(`UPDATE employees SET device_id_lock = 'device_legacy_1' WHERE id = '${IDS.emp}';
  INSERT INTO employee_devices (employee_id, device_id, is_approved) VALUES ('${IDS.emp}', 'device_legacy_1', true);`);
r = await reg('emp', 'android-stable-1', 'device_legacy_1');
check('legacy locked device migrates to the new stable id', r.ok === true, JSON.stringify(r));
const lock = await db.query(`SELECT device_id_lock FROM employees WHERE id = $1`, [IDS.emp]);
check('lock now points to new id', lock.rows[0].device_id_lock === 'android-stable-1');

r = await reg('emp', 'other-phone');
check('unapproved device is locked out', r.ok === false && r.code === 'device_locked', JSON.stringify(r));
const req = await db.query(`SELECT is_approved FROM employee_devices WHERE employee_id=$1 AND device_id='other-phone'`, [IDS.emp]);
check('device request recorded as pending', req.rows[0]?.is_approved === false);
const adminNotif = await db.query(`SELECT count(*)::int n FROM notifications WHERE employee_id=$1 AND type='device'`, [IDS.admin]);
check('admin notified about device request', adminNotif.rows[0].n === 1);

await expectError('employee cannot self-approve a device',
  as(db, 'emp', `UPDATE employee_devices SET is_approved = true WHERE device_id = 'other-phone' RETURNING id`)
    .then((x) => { if (x.rows.length === 0) throw new Error('no rows updated (blocked by RLS)'); }),
  'blocked by RLS');

await db.exec(`DELETE FROM attendance WHERE employee_id = '${IDS.emp}'`);
await expectError('punch from non-approved device is refused',
  as(db, 'emp', `SELECT punch_attendance('check_in', ${IN[0]}, ${IN[1]}, 'other-phone')`), 'غير معتمد');
r = await punch('emp', 'check_in', IN, `, 'android-stable-1'`);
check('punch from approved device works', r.ok === true, JSON.stringify(r));

// inactive account
await db.exec(`UPDATE employees SET is_active = false WHERE id = '${IDS.emp2}'`);
await expectError('inactive employee cannot punch',
  as(db, 'emp2', `SELECT punch_attendance('check_out', ${IN[0]}, ${IN[1]})`), 'معطل');


// --- reminder_minutes_after (schedule reminder setting) ---
const rem = await db.query(`SELECT reminder_minutes_after FROM work_schedules LIMIT 1`);
check('work_schedules.reminder_minutes_after defaults to 5', rem.rows[0]?.reminder_minutes_after === 5, JSON.stringify(rem.rows));
await expectError('reminder minutes must be between 0 and 120',
  db.query(`UPDATE work_schedules SET reminder_minutes_after = 500`), 'chk_work_schedules_reminder_minutes');

done();
