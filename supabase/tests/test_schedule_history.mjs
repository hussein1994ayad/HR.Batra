// (8) تغيير جدول الدوام يسري من يوم التعديل (الأيام السابقة على الجدول القديم)
// (9) ماكو تأخير ولا خروج مبكر بيوم عطلة لمن يداوم تطوعاً
// (10) يوم غياب كامل: الإذن الزمني بدون راتب ما يُخصم فوقه
// (12) التأخير ما يظهر للموظف إلا إذا انخصم؛ الإعفاء بدون إشعار
import { setup, as, IDS, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];
const at = (date, hhmm) => `${date} ${hhmm}:00+03`;
const ev = (emp, date, type) => one(
  `SELECT * FROM payroll_events WHERE employee_id=$1 AND event_date=$2 AND event_type=$3 AND status<>'void'`, [emp, date, type]);
const today = (await one(`SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date::text d`)).d;
const daysAgo = async (n) => (await one(`SELECT ((now() AT TIME ZONE 'Asia/Baghdad')::date - $1::int)::text d`, [n])).d;

const E = '00000000-0000-0000-0000-0000000000f1';
await db.exec(`
  UPDATE employees SET join_date = '2026-01-01';
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password) VALUES
    ('${E}', 'F1', 'موظف جدول', '${IDS.branch}', 600000, '2026-01-01', false);
  UPDATE system_settings SET value = value || '{"no_record_from": "2026-09-02"}' WHERE key = 'payroll_policy';
`);
// جدول للموظف: الأحد → الخميس + السبت (الجمعة عطلة)
const sched = await one(`INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
  VALUES ($1, 'صباحي', '09:00', '17:00', 10, '{0,1,2,3,4,6}') RETURNING id`, [E]);

// ---------------- (8) ----------------
const hist = await q(`SELECT effective_from::text f FROM work_schedule_history WHERE schedule_id=$1`, [sched.id]);
check('8a) new schedule is recorded in history from today', hist.length === 1 && hist[0].f === today, JSON.stringify(hist));
// نحاكي جدولاً موجوداً من قبل (مثل الجداول الحالية: تسري على كل ما سبق)
await db.query(`UPDATE work_schedule_history SET effective_from='-infinity' WHERE schedule_id=$1`, [sched.id]);

// يوم عمل سابق (ليس جمعة) حضر فيه 09:00 على الدوام القديم
let past = null;
for (let n = 2; n < 9 && !past; n++) {
  const d = await daysAgo(n);
  if ((await one(`SELECT EXTRACT(DOW FROM $1::date)::int w`, [d])).w !== 5) past = d;
}
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time)
  VALUES ($1, $2, $3, 'present', $4, $5)`, [E, IDS.branch, past, at(past, '09:00'), at(past, '17:00')]);
check('8b) on time under the old schedule: no late', !(await ev(E, past, 'late')));

// الإدارة تغيّر بداية الدوام اليوم إلى 08:30
await db.query(`UPDATE work_schedules SET check_in_time='08:30' WHERE id=$1`, [sched.id]);
await db.query(`SELECT sync_payroll_day($1, $2)`, [E, past]);
check('8c) schedule change does NOT make past days late', !(await ev(E, past, 'late')));
const nowSched = await one(`SELECT check_in_time::text t FROM payroll_schedule_at($1, $2)`, [E, today]);
const oldSched = await one(`SELECT check_in_time::text t FROM payroll_schedule_at($1, $2)`, [E, past]);
check('8d) today uses the new schedule, past days the old one', nowSched.t === '08:30:00' && oldSched.t === '09:00:00',
  `${nowSched.t} / ${oldSched.t}`);
// تعديل الاسم فقط ما يضيف سطر بالسجل
const before = (await q(`SELECT 1 FROM work_schedule_history WHERE schedule_id=$1`, [sched.id])).length;
await db.query(`UPDATE work_schedules SET name='اسم جديد' WHERE id=$1`, [sched.id]);
const after = (await q(`SELECT 1 FROM work_schedule_history WHERE schedule_id=$1`, [sched.id])).length;
check('8e) renaming a schedule does not change history', before === after);
// تعديلين بنفس اليوم: الأخير هو الساري
await db.query(`UPDATE work_schedules SET check_in_time='08:45' WHERE id=$1`, [sched.id]);
const t2 = await one(`SELECT check_in_time::text t FROM payroll_schedule_at($1, $2)`, [E, today]);
check('8f) two edits on the same day: the last one applies', t2.t === '08:45:00', t2.t);
await db.query(`UPDATE work_schedules SET check_in_time='09:00' WHERE id=$1`, [sched.id]);

// ---------------- (9) ----------------
let friday = null;
for (let n = 1; n < 9 && !friday; n++) {
  const d = await daysAgo(n);
  if ((await one(`SELECT EXTRACT(DOW FROM $1::date)::int w`, [d])).w === 5) friday = d;
}
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time)
  VALUES ($1, $2, $3, 'late', $4, $5)`, [E, IDS.branch, friday, at(friday, '10:30'), at(friday, '13:00')]);
check('9a) voluntary Friday work: no late', !(await ev(E, friday, 'late')));
check('9b) voluntary Friday work: no early leave', !(await ev(E, friday, 'early_leave')));

// ---------------- (10) ----------------
let d10 = null;
for (let n = 2; n < 12 && !d10; n++) {
  const d = await daysAgo(n);
  if (d !== past && (await one(`SELECT EXTRACT(DOW FROM $1::date)::int w`, [d])).w !== 5) d10 = d;
}
// حضر 10:00 بعد إذن 9→10 (بدون راتب)
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time)
  VALUES ($1, $2, $3, 'late', $4, $5)`, [E, IDS.branch, d10, at(d10, '10:00'), at(d10, '17:00')]);
await db.query(`INSERT INTO leave_requests (employee_id, leave_type, is_hourly, start_date, end_date, start_hour, end_hour, is_paid, status, reason)
  VALUES ($1, 'annual', true, $2, $3, '09:00', '10:00', false, 'approved', 'إذن')`, [E, at(d10, '09:00'), at(d10, '10:00')]);
const hourly = await ev(E, d10, 'unpaid_leave');
check('10a) unpaid hourly permission alone is deducted (60 min), no late', hourly && Number(hourly.minutes) === 60 && !(await ev(E, d10, 'late')),
  JSON.stringify(hourly));
// نفس اليوم صار غياب كامل
await db.query(`UPDATE attendance SET status='absent', check_in_time=NULL, check_out_time=NULL, deduction_status='applied'
  WHERE employee_id=$1 AND work_date=$2`, [E, d10]);
const abs = await ev(E, d10, 'absence');
check('10b) absent the whole day: one full day', abs && Number(abs.amount) === 20000 && abs.status === 'approved');
check('10c) ...and the permission is NOT deducted on top', !(await ev(E, d10, 'unpaid_leave')));
await db.query(`UPDATE attendance SET deduction_status='ignored' WHERE employee_id=$1 AND work_date=$2`, [E, d10]);
check('10d) absence excused → the permission counts again', !!(await ev(E, d10, 'unpaid_leave')));

// ---------------- (12) ----------------
// بصمة حضور متأخرة (أمس 09:40) — الإشعار ما يذكر التأخير
const yest = await daysAgo(1);
await db.query(`UPDATE employees SET device_id_lock = NULL WHERE id = $1`, [IDS.emp]);
await db.query(`INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
  VALUES ($1, 'صباحي', '09:00', '17:00', 10, '{0,1,2,3,4,5,6}')`, [IDS.emp]);
// جدول موجود من قبل (الجدول المضاف اليوم يسري من اليوم فقط)
await db.query(`UPDATE work_schedule_history SET effective_from='-infinity' WHERE employee_id=$1`, [IDS.emp]);
const r = (await as(db, 'emp', `SELECT punch_attendance('check_in', 33.3, 44.4, NULL, false, $1::timestamptz) r`, [at(yest, '09:40')])).rows[0].r;
check('12a) late punch is still recorded as late (for the admin)', r.ok && r.status === 'late', JSON.stringify(r));
const note = await one(`SELECT title, body FROM notifications WHERE employee_id=$1 ORDER BY created_at DESC LIMIT 1`, [IDS.emp]);
check('12b) punch notification does not mention lateness', note && !/متأخر|تأخير/.test(note.title + note.body), JSON.stringify(note));

const lateEv = await ev(IDS.emp, yest, 'late');
check('12c) the late is waiting for the admin', lateEv && lateEv.status === 'pending', JSON.stringify(lateEv));
// الإعفاء (نسي البصمة وهو مداوم): بدون إشعار، والملاحظة محفوظة
const n0 = (await q(`SELECT 1 FROM notifications WHERE employee_id=$1`, [IDS.emp])).length;
await as(db, 'admin', `SELECT decide_payroll_event($1, false, 'نسي البصمة وهو مداوم')`, [lateEv.id]);
const n1 = (await q(`SELECT 1 FROM notifications WHERE employee_id=$1`, [IDS.emp])).length;
const excused = await one(`SELECT status, decision_reason FROM payroll_events WHERE employee_id=$1 AND event_date=$2 AND event_type='late' AND status<>'void'`, [IDS.emp, yest]);
check('12d) excuse sends no notification', n1 === n0, `${n0} → ${n1}`);
check('12e) excuse keeps the note and is not deducted', excused.status === 'ignored' && excused.decision_reason === 'نسي البصمة وهو مداوم',
  JSON.stringify(excused));
// تطبيق الخصم: يوصل إشعار
await as(db, 'admin', `SELECT decide_payroll_event($1, true, 'تأخير')`, [lateEv.id]);
const n2 = (await q(`SELECT 1 FROM notifications WHERE employee_id=$1`, [IDS.emp])).length;
check('12f) applying the deduction notifies the employee', n2 === n1 + 1);

// "المتأخرون اليوم": بصمة اليوم المتأخرة ما تظهر إلا بعد الخصم
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time) VALUES ($1, $2, $3, 'late', $4)`,
  [IDS.emp2, IDS.branch, today, at(today, '00:01')]);
const lateList = async () => (await as(db, 'emp', `SELECT employee_id FROM get_late_today()`)).rows.map((x) => x.employee_id);
check('12g) late today is hidden until deducted', !(await lateList()).includes(IDS.emp2));
await db.query(`UPDATE attendance SET deduction_status='applied' WHERE employee_id=$1 AND work_date=$2`, [IDS.emp2, today]);
check('12h) ...and shown once the deduction is applied', (await lateList()).includes(IDS.emp2));

done();
