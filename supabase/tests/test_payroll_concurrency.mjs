// تدقيق 14/10/2026 — المرحلة 5: التزامن والسرعة.
// (PAY-007) ماكو حركة فعالة مكررة (قفل + قيود فريدة)، (BUG-018) «احتساب الرواتب» على دفعات بنفس النتيجة،
// (BUG-013) اعتماد إجازة أطول من 92 يوم يحسب كل أيامها اللي فاتت.
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];
const today = (await one(`SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date::text d`)).d;
const daysAgo = async (n) => (await one(`SELECT ((now() AT TIME ZONE 'Asia/Baghdad')::date - $1::int)::text d`, [n])).d;
const isFriday = (d) => new Date(d + 'T00:00:00Z').getUTCDay() === 5;
const curMonth = (await one(`SELECT payroll_month_of($1::date) m`, [today])).m;
const prevMonth = (await one(`SELECT payroll_month_add($1, -1) m`, [curMonth])).m;
await q(`SELECT ensure_payroll_period($1)`, [curMonth]);

await db.exec(`
  UPDATE employees SET join_date = '2026-01-01';
  UPDATE system_settings SET value = value || '{"no_record_from": "2026-01-01"}' WHERE key = 'payroll_policy';
`);
const s = await one(`INSERT INTO work_schedules (branch_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
  VALUES ($1, 'دوام', '09:00', '14:00', 10, '{0,1,2,3,4,6}') RETURNING id`, [IDS.branch]);
await q(`UPDATE work_schedule_history SET effective_from = '-infinity' WHERE schedule_id = $1`, [s.id]);

const newEmp = async (code) => {
  const id = (await one('SELECT gen_random_uuid()::text id')).id;
  await q(`INSERT INTO auth.users (id, email) VALUES ($1, $2)`, [id, `${code}@x`]);
  await q(`INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ($1, $2, $2, 'employee', $3, 900000, '2026-01-01', false)`, [id, code, IDS.branch]);
  return id;
};
const active = (emp, d, type) => q(`SELECT * FROM payroll_events WHERE employee_id=$1 AND event_date=$2 AND event_type=$3 AND status<>'void'`, [emp, d, type]);

// ---------------- 1) PAY-007: حركة فعالة وحدة ----------------
let past = null;
for (let n = 2; n < 9 && !past; n++) { const d = await daysAgo(n); if (!isFriday(d)) past = d; }
const E = await newEmp('C1');
await q(`SELECT sync_payroll_day($1, $2::date)`, [E, past]);
await q(`SELECT sync_payroll_day($1, $2::date)`, [E, past]);
check('1) a workday without a punch gives one absence waiting for a decision, even if calculated twice', (await active(E, past, 'absence')).length === 1);
const ev = (await active(E, past, 'absence'))[0];
await expectError('   the database itself refuses a second active copy of the same absence',
  db.query(`INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, status, source)
    VALUES ($1, $2, 'absence', $3, -1, $4, 'pending', 'no_record')`, [E, past, ev.amount, ev.payroll_month]), 'duplicate key');
check('   the day calculation waits for any other calculation of the same employee and day (lock)',
  (await one(`SELECT pg_get_functiondef('public.sync_payroll_day(uuid,date)'::regprocedure) ~ 'pg_advisory_xact_lock' a`)).a === true);
const bd = await one(`INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date) VALUES ($1, 'deduction', 25000, 'ضرر', $2) RETURNING id`, [E, past]);
await q(`SELECT sync_payroll_manual($1)`, [bd.id]);
check('   a manual deduction has one active record', (await one(`SELECT count(*)::int c FROM payroll_events WHERE source='manual' AND source_id=$1 AND status<>'void'`, [bd.id])).c === 1);
await expectError('   ...and a second copy is refused', db.query(`INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, status, source, source_id)
  VALUES ($1, $2, 'manual_deduction', 25000, -1, $3, 'approved', 'manual', $4)`, [E, past, ev.payroll_month, bd.id]), 'duplicate key');
// تسوية مفتوحة وحدة لكل حركة داخل كشف
await q(`INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, status, source, adjusts_event_id)
  VALUES ($1, $2, 'adjustment', 1000, 1, $3, 'approved', 'carry_over', $4)`, [E, past, curMonth, ev.id]);
await expectError('   one open settlement per event', db.query(`INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, status, source, adjusts_event_id)
  VALUES ($1, $2, 'adjustment', 1000, 1, $3, 'approved', 'carry_over', $4)`, [E, past, curMonth, ev.id]), 'duplicate key');
await q(`UPDATE payroll_events SET status = 'void' WHERE adjusts_event_id = $1`, [ev.id]);
await expectOk('   voided records do not count (history stays)', db.query(`INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, status, source, adjusts_event_id)
  VALUES ($1, $2, 'adjustment', 1000, 1, $3, 'approved', 'carry_over', $4)`, [E, past, curMonth, ev.id]));
await q(`DELETE FROM payroll_events WHERE adjusts_event_id = $1`, [ev.id]);

// ---------------- 2) BUG-018: الاحتساب على دفعات ----------------
for (let i = 0; i < 22; i++) await newEmp(`B${i}`);
const total = (await one(`SELECT count(*)::int c FROM employees WHERE (join_date IS NULL OR join_date <= (SELECT cutoff_date FROM payroll_periods WHERE period_month=$1))
  AND (termination_date IS NULL OR termination_date >= (SELECT start_date FROM payroll_periods WHERE period_month=$1)) AND (is_active OR termination_date IS NOT NULL)`, [curMonth])).c;
await q(`UPDATE payroll_periods SET calculated_at = NULL WHERE period_month = $1`, [curMonth]);
let after = null; let calls = 0; let last = null; const seen = [];
while (calls < 20) {
  const r = (await as(db, 'admin', `SELECT calculate_payroll_batch($1, $2::uuid, 10) r`, [curMonth, after])).rows[0].r;
  calls++; seen.push(r.done);
  last = r;
  if (calls === 1) check('2) the first batch does 10 employees and the period is not marked calculated yet',
    r.done === 10 && r.total === total && r.finished === false
    && (await one(`SELECT calculated_at FROM payroll_periods WHERE period_month=$1`, [curMonth])).calculated_at === null, JSON.stringify(r));
  if (r.finished) break;
  after = r.last_id;
}
check(`   ${total} employees in ${calls} small requests, progress ${seen.join(' → ')}`, calls === Math.ceil(total / 10) && last.done === total, JSON.stringify(last));
check('   the last batch marks the period as calculated', (await one(`SELECT calculated_at FROM payroll_periods WHERE period_month=$1`, [curMonth])).calculated_at !== null);
const snapshot = async () => (await q(`SELECT employee_id, event_date::text d, event_type, status, amount::numeric a FROM payroll_events WHERE status <> 'void' ORDER BY 1, 2, 3`)).map((r) => JSON.stringify(r)).join('\n');
const batched = await snapshot();
await expectOk('   the old one-shot calculation still works', as(db, 'admin', `SELECT calculate_payroll($1)`, [curMonth]));
check('   ...and gives exactly the same records as the batches', (await snapshot()) === batched);
check('   absences were found for every employee (the batches really calculated)',
  (await one(`SELECT count(DISTINCT employee_id)::int c FROM payroll_events WHERE event_type='absence' AND status<>'void' AND payroll_month=$1`, [curMonth])).c === total);
const big = (await as(db, 'admin', `SELECT calculate_payroll_batch($1, NULL, 500) r`, [curMonth])).rows[0].r;
check('   a too-big batch size falls back to 10', big.done === 10, JSON.stringify(big));
await expectError('   a branch manager cannot run it', as(db, 'manager', `SELECT calculate_payroll_batch($1)`, [curMonth]), 'غير مصرح');
await expectError('   an employee cannot run it', as(db, 'emp', `SELECT calculate_payroll_batch($1)`, [curMonth]), 'غير مصرح');
await q(`UPDATE payroll_periods SET status = 'closed' WHERE period_month = $1`, [prevMonth]);
const closed = (await as(db, 'admin', `SELECT calculate_payroll_batch($1) r`, [prevMonth])).rows[0].r;
check('   a closed period has nothing to calculate', closed.finished === true && closed.total === 0, JSON.stringify(closed));
await q(`UPDATE payroll_periods SET status = 'open' WHERE period_month = $1`, [prevMonth]);

// ---------------- 3) BUG-013: إجازة أطول من 92 يوم ----------------
const L = await newEmp('L1');
const start = await daysAgo(140);
const end = await one(`SELECT ((now() AT TIME ZONE 'Asia/Baghdad')::date + 10)::text d`);
let probe = null;
for (let n = 100; n > 2 && !probe; n--) {
  const d = await daysAgo(n);
  const p = await one(`SELECT payroll_natural_month($1::date) m`, [d]);
  if (p.m && !isFriday(d)) probe = d;
}
await q(`INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status, is_paid)
  VALUES ($1, ($2::date)::timestamp AT TIME ZONE 'Asia/Baghdad', ($3::date)::timestamp AT TIME ZONE 'Asia/Baghdad', 'maternity', 'approved', true)`, [L, start, end.d]);
check(`3) a 150-day leave: day ${probe} (more than 92 days after its start) is counted as paid leave right away`,
  probe !== null && (await active(L, probe, 'paid_leave')).length === 1 && (await active(L, probe, 'absence')).length === 0,
  JSON.stringify([probe, (await active(L, probe, 'paid_leave')).length]));

done();
