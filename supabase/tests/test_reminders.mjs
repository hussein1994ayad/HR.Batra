// تذكيرات البصمة: check_and_send_attendance_reminders(p_now)
import { setup, as, IDS, expectError, check, done } from './lib.mjs';

const db = await setup();

// دوام الفرع 09:00–14:00 كل الأيام عدا الجمعة (DOW 5)، تذكير بعد 5 دقائق
await db.exec(`
  DELETE FROM work_schedules;
  INSERT INTO work_schedules (branch_id, name, check_in_time, check_out_time, work_days)
  VALUES ('${IDS.branch}', 'دوام الفرع', '09:00', '14:00', ARRAY[0,1,2,3,4,6]);
  -- emp2 مجاز اليوم (إجازة يومية معتمدة)
  INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status)
  VALUES ('${IDS.emp2}', '2026-09-27 00:00+03', '2026-09-27 23:59+03', 'annual', 'approved');
`);

// الأحد 2026-09-27 بتوقيت بغداد (+03)
const at = (hhmm, date = '2026-09-27') => `${date} ${hhmm}:00+03`;
const run = async (hhmm, date) =>
  (await db.query(`SELECT check_and_send_attendance_reminders($1::timestamptz) AS n`, [at(hhmm, date)])).rows[0].n;
const sent = async (kind) =>
  (await db.query(`SELECT employee_id FROM attendance_reminder_log WHERE kind = $1 ORDER BY employee_id`, [kind])).rows.map((r) => r.employee_id);

check('nothing is sent at 08:00', (await run('08:00')) === 0);
check('08:45 sends "starts in 15 minutes" to the 3 employees not on leave', (await run('08:45')) === 3);
check('the employee on leave gets no reminder', !(await sent('checkin_soon')).includes(IDS.emp2));
check('running again in the same window sends nothing new', (await run('08:46')) === 0);

// emp يسجّل حضور 08:58
await db.exec(`INSERT INTO attendance (employee_id, branch_id, status, work_date, check_in_time)
  VALUES ('${IDS.emp}', '${IDS.branch}', 'present', '2026-09-27', '${at('08:58')}')`);

check('09:05 reminds only those who did not check in', (await run('09:05')) === 2 && !(await sent('checkin_late')).includes(IDS.emp));
check('13:45 reminds the checked-in employee to check out', (await run('13:45')) === 1 && (await sent('checkout_soon')).join() === IDS.emp);
check('14:05 reminds again if still not checked out', (await run('14:05')) === 1 && (await sent('checkout_late')).join() === IDS.emp);

await db.exec(`UPDATE attendance SET check_out_time = '${at('14:10')}' WHERE employee_id = '${IDS.emp}'`);
await db.exec(`DELETE FROM attendance_reminder_log WHERE kind = 'checkout_late'`);
check('no check-out reminder after checking out', (await run('14:05')) === 0);

check('no reminders on Friday (not a work day)', (await run('08:45', '2026-10-02')) === 0);

const bodies = (await db.query(`SELECT title, body FROM notifications WHERE employee_id = $1 AND type = 'attendance' ORDER BY created_at`, [IDS.emp])).rows;
check('the employee got start, check-out-soon and check-out-late reminders', bodies.length === 3, JSON.stringify(bodies));
check('reminder texts are clean (no internal keys)', bodies.every((b) => !b.body.includes('[')), JSON.stringify(bodies));
check('reminder shows the shift time', bodies[0].body.includes('09:00 AM'), bodies[0].body);

await expectError('employees cannot trigger reminders', as(db, 'emp', `SELECT check_and_send_attendance_reminders()`), 'permission denied');
await expectError('admins cannot trigger reminders from the client', as(db, 'admin', `SELECT check_and_send_attendance_reminders()`), 'permission denied');
await expectError('clients cannot read the reminder log', as(db, 'admin', `SELECT * FROM attendance_reminder_log`), 'permission denied');

done();
