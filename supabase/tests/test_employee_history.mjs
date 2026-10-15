// تدقيق 14/10/2026 — المرحلة 4 (قرارات 15/10/2026): تاريخ الموظف.
// (PAY-002) النقل لفرع/قسم ثاني يسري من يوم التغيير والأيام القديمة تبقى على دوام فرعها،
// (PAY-009) الرجوع بعد الترك: أيام الانقطاع ما تطلع غياب والراتب ناقص أجرها، (FEATURE-001) سجل الموظف.
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];
const at = (date, hhmm) => `${date} ${hhmm}:00+03`;
const evs = (emp, date, type) => q(
  `SELECT * FROM payroll_events WHERE employee_id=$1 AND event_date=$2 AND event_type=$3 AND status<>'void'`, [emp, date, type]);
const today = (await one(`SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date::text d`)).d;
const daysAgo = async (n) => (await one(`SELECT ((now() AT TIME ZONE 'Asia/Baghdad')::date - $1::int)::text d`, [n])).d;
const addDays = (d, n) => new Date(Date.parse(d + 'T00:00:00Z') + n * 86400000).toISOString().slice(0, 10);
const isFriday = (d) => new Date(d + 'T00:00:00Z').getUTCDay() === 5;

const B2 = '00000000-0000-0000-0000-0000000000b2';
const D1 = '00000000-0000-0000-0000-0000000000d1';
await db.exec(`
  UPDATE employees SET join_date = '2026-01-01';
  UPDATE system_settings SET value = value || '{"no_record_from": "2026-01-01"}' WHERE key = 'payroll_policy';
  INSERT INTO branches (id, name, latitude, longitude, radius_meters) VALUES ('${B2}', 'فرع الكرادة', 33.31, 44.41, 100);
  INSERT INTO departments (id, name) VALUES ('${D1}', 'المبيعات');
`);
// دوام الفرع الرئيسي 9 لحد 2، والكرادة 8 لحد 4، وقسم المبيعات 7 لحد 3 (كلها من قبل)
for (const [col, id, inT, outT] of [['branch_id', IDS.branch, '09:00', '14:00'], ['branch_id', B2, '08:00', '16:00'], ['department_id', D1, '07:00', '15:00']]) {
  const s = await one(`INSERT INTO work_schedules (${col}, name, check_in_time, check_out_time, grace_period_minutes, work_days)
    VALUES ($1, 'دوام', $2, $3, 10, '{0,1,2,3,4,6}') RETURNING id`, [id, inT, outT]);
  await q(`UPDATE work_schedule_history SET effective_from = '-infinity' WHERE schedule_id = $1`, [s.id]);
}
const newEmp = async (code, salary = 900000) => {
  const id = (await one('SELECT gen_random_uuid()::text id')).id;
  await q(`INSERT INTO auth.users (id, email) VALUES ($1, $2)`, [id, `${code}@x`]);
  await q(`INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ($1, $2, $2, 'employee', $3, $4, '2026-01-01', false)`, [id, code, IDS.branch, salary]);
  return id;
};
const schedIn = async (emp, d) => (await one(`SELECT check_in_time::text t FROM payroll_schedule_at($1, $2::date)`, [emp, d])).t;

// ---------------- 1) PAY-002: النقل لفرع ثاني ما يغيّر حساب الأيام القديمة ----------------
const E = await newEmp('T1', 600000);
let past = null;
for (let n = 2; n < 9 && !past; n++) { const d = await daysAgo(n); if (!isFriday(d)) past = d; }
await q(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time)
  VALUES ($1, $2, $3, 'present', $4, $5)`, [E, IDS.branch, past, at(past, '09:05'), at(past, '14:00')]);
check('1) on time at the old branch (9 to 2): no late, no early leave',
  (await evs(E, past, 'late')).length === 0 && (await evs(E, past, 'early_leave')).length === 0);
check('   a new employee starts with his branch in the history',
  (await one(`SELECT count(*)::int c FROM employee_assignment_history WHERE employee_id = $1`, [E])).c === 1);

await expectOk('   the admin moves him to the Karrada branch (8 to 4)', as(db, 'admin', `UPDATE employees SET branch_id = $2 WHERE id = $1`, [E, B2]));
const hist = await q(`SELECT branch_id, effective_from::text f FROM employee_assignment_history WHERE employee_id = $1 ORDER BY id`, [E]);
check('   the move is recorded from today (the day of the change)', hist.length === 2 && hist[1].branch_id === B2 && hist[1].f === today, JSON.stringify(hist));
await q(`SELECT sync_payroll_day($1, $2::date)`, [E, past]);
const curMonth = (await one(`SELECT payroll_month_of($1::date) m`, [today])).m;
await q(`SELECT sync_payroll_period($1, $2)`, [curMonth, E]);
check('   recalculating keeps his old day on the old schedule: still no late or early leave',
  (await evs(E, past, 'late')).length === 0 && (await evs(E, past, 'early_leave')).length === 0,
  JSON.stringify([await evs(E, past, 'late'), await evs(E, past, 'early_leave')]));
check('   past days use the old branch schedule, today the new one', (await schedIn(E, past)) === '09:00:00' && (await schedIn(E, today)) === '08:00:00',
  `${await schedIn(E, past)} / ${await schedIn(E, today)}`);

await q(`UPDATE employees SET department_id = $2 WHERE id = $1`, [E, D1]);
check('   a department change also applies from today (department schedule wins)', (await schedIn(E, today)) === '07:00:00' && (await schedIn(E, past)) === '09:00:00');
await q(`UPDATE employees SET branch_id = $2, department_id = NULL WHERE id = $1`, [E, IDS.branch]);
check('   two changes on the same day: the last one applies', (await schedIn(E, today)) === '09:00:00');
await q(`UPDATE employees SET full_name = 'T1 معدل' WHERE id = $1`, [E]);
check('   editing other fields adds nothing to the history',
  (await one(`SELECT count(*)::int c FROM employee_assignment_history WHERE employee_id = $1`, [E])).c === 4);
await expectError('   nobody writes the history by hand (employee)', as(db, 'emp', `INSERT INTO employee_assignment_history (employee_id, effective_from) VALUES ($1, '2026-01-01')`, [IDS.emp]));
await expectError('   ...not even the admin (only the system records it)', as(db, 'admin', `DELETE FROM employee_assignment_history WHERE employee_id = $1`, [E]));
check('   the admin can read it', (await as(db, 'admin', `SELECT count(*)::int c FROM employee_assignment_history WHERE employee_id = $1`, [E])).rows[0].c === 4);
check('   an employee cannot read it', (await as(db, 'emp', `SELECT count(*)::int c FROM employee_assignment_history`)).rows[0].c === 0);

// ---------------- 2) PAY-009: ترك ورجع ----------------
const R = await newEmp('R1', 900000);
const lastDay = await daysAgo(10);
const ret = await daysAgo(3);
await q(`UPDATE employees SET is_active = false, termination_date = $2 WHERE id = $1`, [R, lastDay]);
const r = await expectOk('2) the admin reactivates him with his return date', as(db, 'admin', `SELECT reactivate_employee($1, $2::date) r`, [R, ret]));
const res = r?.rows[0].r;
check('   6 days of break are recorded', res?.gap_days === 6 && res?.warnings.length === 0, JSON.stringify(res));
const emp = await one(`SELECT is_active, termination_date FROM employees WHERE id = $1`, [R]);
check('   active again, no last day', emp.is_active === true && emp.termination_date === null, JSON.stringify(emp));
const gapDays = []; for (let d = addDays(lastDay, 1); d < ret; d = addDays(d, 1)) gapDays.push(d);
let gapAbs = 0;
for (const d of gapDays) gapAbs += (await evs(R, d, 'absence')).length;
check('   no absence appears for the days he was away', gapAbs === 0, String(gapAbs));
let after = 0;
for (let d = ret; d < today; d = addDays(d, 1)) if (!isFriday(d)) after += (await evs(R, d, 'absence')).length;
check('   days after his return are counted normally again (no punch = absence waiting for a decision)', after > 0, String(after));
check('   in service on his return day, not during the break',
  (await one(`SELECT employee_in_service($1, $2::date) a, employee_in_service($1, $3::date) b`, [R, ret, gapDays[2]])).a === true
  && (await one(`SELECT employee_in_service($1, $2::date) b`, [R, gapDays[2]])).b === false);

// الراتب: مثل المباشر — ناقص أجر أيام الانقطاع اللي تقع بكل مسير
for (const m of [...new Set([(await one(`SELECT payroll_month_of($1::date) m`, [lastDay])).m, (await one(`SELECT payroll_month_of($1::date) m`, [ret])).m])]) {
  const p = await one(`SELECT start_date::text s, cutoff_date::text c FROM ensure_payroll_period($1)`, [m]);
  const inP = gapDays.filter((d) => d >= p.s && d <= p.c).length;
  const s = (await one(`SELECT payroll_employee_summary($1, $2) s`, [R, m])).s;
  if (inP > 0) {
    check(`   period ${m}: salary minus ${inP} break day(s) = ${900000 - inP * 30000}`, Number(s.basic) === 900000 - inP * 30000 && s.basic_basis === 'returned'
      && Number(s.gap_days) === inP, JSON.stringify([s.basic, s.basic_basis, s.gap_days]));
    check('   ...with a plain explanation', String(s.basic_note).includes('ترك بعد') && String(s.basic_note).includes('يوم انقطاع'), s.basic_note);
  }
}
const log = (await as(db, 'admin', `SELECT assistant_attendance_log($1, $2::date, $3::date) l`, [R, gapDays[0], gapDays[0]])).rows[0].l;
check('   the attendance log says «outside service» for a break day, not absence', JSON.stringify(log).includes('خارج فترة الخدمة'), JSON.stringify(log).slice(0, 300));

await expectError('   reactivating an active account is refused', as(db, 'admin', `SELECT reactivate_employee($1, $2::date)`, [R, ret]), 'مفعّل أصلاً');
const R2 = await newEmp('R2');
await q(`UPDATE employees SET is_active = false, termination_date = $2 WHERE id = $1`, [R2, await daysAgo(5)]);
await expectError('   a return date in the future is refused', as(db, 'admin', `SELECT reactivate_employee($1, $2::date)`, [R2, addDays(today, 2)]), 'بالمستقبل');
await expectError('   a branch manager cannot reactivate', as(db, 'manager', `SELECT reactivate_employee($1, $2::date)`, [R2, today]));
await expectError('   a return before joining is refused', as(db, 'admin', `SELECT reactivate_employee($1, '2025-06-01'::date)`, [R2]), 'قبل تاريخ المباشرة');
// النسخة القديمة من الموقع/التطبيق: تفعيل عادي = رجع اليوم
await q(`UPDATE employees SET is_active = true WHERE id = $1`, [R2]);
const br2 = await one(`SELECT last_day::text l, return_date::text r FROM employee_service_breaks WHERE employee_id = $1`, [R2]);
check('   a plain reactivation (old app) records the return as today', br2?.r === today && br2?.l === (await daysAgo(5)), JSON.stringify(br2));
const R3 = await newEmp('R3');
await q(`UPDATE employees SET is_active = false, termination_date = $2 WHERE id = $1`, [R3, today]);
await expectOk('   deactivated and reactivated the same day', as(db, 'admin', `SELECT reactivate_employee($1)`, [R3]));
check('   ...is not a break', (await one(`SELECT count(*)::int c FROM employee_service_breaks WHERE employee_id = $1`, [R3])).c === 0);

// كشف شهر الرجوع معتمد (آخر راتب قبل الترك): تنبيه، والكشف ما يتغير
const prevMonth = (await one(`SELECT payroll_month_add($1, -1) m`, [curMonth])).m;
const prev = await one(`SELECT start_date::text s, cutoff_date::text c FROM ensure_payroll_period($1)`, [prevMonth]);
const W = await newEmp('W1');
await q(`UPDATE employees SET is_active = false, termination_date = $2 WHERE id = $1`, [W, addDays(prev.s, 3)]);
await expectOk('   his last salary (before leaving) is approved', as(db, 'admin', `SELECT approve_payroll_slip($1, $2)`, [W, prevMonth]));
const slipBefore = await one(`SELECT basic_salary::int b, net_salary::int n FROM salary_slips WHERE employee_id = $1`, [W]);
const rw = await expectOk('   he comes back in the same month', as(db, 'admin', `SELECT reactivate_employee($1, $2::date) r`, [W, addDays(prev.s, 8)]));
check('   the admin is warned that month is already approved', rw?.rows[0].r.warnings.length === 1 && String(rw?.rows[0].r.warnings[0]).includes('معتمد'),
  JSON.stringify(rw?.rows[0].r));
check('   the approved slip is untouched', JSON.stringify(await one(`SELECT basic_salary::int b, net_salary::int n FROM salary_slips WHERE employee_id = $1`, [W])) === JSON.stringify(slipBefore));

// ---------------- 3) FEATURE-001: سجل الموظف ----------------
const h1 = (await as(db, 'admin', `SELECT get_employee_history($1) h`, [E])).rows[0].h;
const texts = h1.map((x) => x.text);
check('3) history: joined, moved to Karrada, moved to a department, back to the main branch',
  h1[0].kind === 'join' && texts.some((t) => t.includes('انتقل من الفرع الرئيسي إلى فرع الكرادة')) && texts.some((t) => t.includes('صار بقسم المبيعات'))
  && texts.some((t) => t.includes('انتقل من فرع الكرادة إلى الفرع الرئيسي')), JSON.stringify(h1));
const h2 = (await as(db, 'admin', `SELECT get_employee_history($1) h`, [R])).rows[0].h;
check('   leaving and coming back show with their dates', h2.some((x) => x.kind === 'exit' && x.date === lastDay)
  && h2.some((x) => x.kind === 'return' && x.date === ret && x.text.includes('6 يوم')), JSON.stringify(h2));
await expectOk('   the branch manager sees the history of his branch employees', as(db, 'manager', `SELECT get_employee_history($1)`, [R]));
await expectOk('   an employee sees his own', as(db, 'emp', `SELECT get_employee_history($1)`, [IDS.emp]));
await expectError('   ...but not someone else\'s', as(db, 'emp', `SELECT get_employee_history($1)`, [R]), 'غير مصرح');
await q(`UPDATE employees SET branch_id = $2 WHERE id = $1`, [R, B2]);
await expectError('   a manager of another branch cannot see it', as(db, 'manager', `SELECT get_employee_history($1)`, [R]), 'غير مصرح');

done();
