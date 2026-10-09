// «احتساب الرواتب» بزر + التحديث الليلي + صلاحيات المدير على حركات الرواتب.
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];

await db.exec(`UPDATE employees SET join_date = '2026-01-01'`);
const today = (await one(`SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date AS d`)).d;
const month = (await one(`SELECT payroll_month_of((now() AT TIME ZONE 'Asia/Baghdad')::date) m`)).m;
await q(`SELECT ensure_payroll_period(payroll_month_add($1, -1))`, [month]);
await q(`SELECT ensure_payroll_period($1)`, [month]);
// أيام بلا بصمة تُعتبر غياباً من بداية هذا الأسبوع
await db.exec(`UPDATE system_settings SET value = value || jsonb_build_object('no_record_from', ((now() AT TIME ZONE 'Asia/Baghdad')::date - 10)::text) WHERE key = 'payroll_policy'`);
const noRecord = async () => (await one(`SELECT count(*)::int n FROM payroll_events WHERE employee_id = $1 AND source = 'no_record' AND status <> 'void'`, [IDS.emp2])).n;

// ---------------- فتح الصفحة ما يعيد الحساب ----------------
await expectOk('opening the payroll page works for the admin', as(db, 'admin', `SELECT get_payroll_run($1)`, [month]));
check('...and does not recalculate every day for everyone (no absences created by just opening)', (await noRecord()) === 0);

// ---------------- زر «احتساب الرواتب» ----------------
await expectError('employees cannot calculate payroll', as(db, 'emp', `SELECT calculate_payroll($1)`, [month]), 'غير مصرح');
await expectError('managers cannot calculate payroll', as(db, 'manager', `SELECT calculate_payroll($1)`, [month]), 'غير مصرح');
const calc = (await as(db, 'admin', `SELECT calculate_payroll($1) r`, [month])).rows[0].r;
check('calculating returns the payroll with the time and who calculated it',
  !!calc.period.calculated_at && calc.period.calculated_by === IDS.admin && Array.isArray(calc.rows), JSON.stringify(calc.period).slice(0, 200));
const afterCalc = await noRecord();
const workdaysBefore = (await one(`
  SELECT count(*)::int n FROM generate_series(GREATEST((SELECT start_date FROM payroll_periods WHERE period_month = $1), $2::date - 10), $2::date - 1, interval '1 day') g(d)
  WHERE EXTRACT(DOW FROM g.d) <> 5`, [month, today])).n;
check('calculating records the days without a punch (as pending decisions, never deducted automatically)',
  afterCalc === workdaysBefore && (await one(`SELECT count(*)::int n FROM payroll_events WHERE employee_id = $1 AND source = 'no_record' AND status <> 'pending'`, [IDS.emp2])).n === 0,
  `${afterCalc} vs ${workdaysBefore}`);

// ---------------- التحديث الليلي ----------------
await db.query(`UPDATE payroll_events SET status = 'void' WHERE source = 'no_record'`);
await expectError('clients cannot run the nightly job', as(db, 'admin', `SELECT payroll_nightly()`), 'permission denied');
await expectOk('the nightly job runs (as the scheduler)', db.query(`SELECT payroll_nightly()`));
const lastDays = (await one(`
  SELECT count(*)::int n FROM generate_series(GREATEST((SELECT start_date FROM payroll_periods WHERE period_month = $1), $2::date - 3), $2::date - 1, interval '1 day') g(d)
  WHERE EXTRACT(DOW FROM g.d) <> 5 AND g.d::date >= $2::date - 10`, [month, today])).n;
const nightly = (await one(`SELECT count(*)::int n FROM payroll_events WHERE employee_id = $1 AND source = 'no_record' AND status <> 'void'
  AND event_date >= $2::date - 3`, [IDS.emp2, today])).n;
check('the nightly job refreshes the last 3 days for everyone', nightly === lastDays, `${nightly} vs ${lastDays}`);

// ---------------- المدير يشوف فرعه بس ----------------
const otherBranch = (await one(`INSERT INTO branches (name, latitude, longitude, radius_meters) VALUES ('فرع ثاني', 33.1, 44.1, 100) RETURNING id`)).id;
const far = (await one('SELECT gen_random_uuid()::text id')).id;
await q(`INSERT INTO auth.users (id, email) VALUES ($1, 'far@x')`, [far]);
await q(`INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, join_date, must_change_password)
  VALUES ($1, 'FAR1', 'موظف فرع ثاني', 'employee', $2, 500000, '2026-01-01', false)`, [far, otherBranch]);
await q(`INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, status, source, notes)
  VALUES ($1, $2, 'manual_deduction', 10000, -1, $3, 'approved', 'manual', 'خصم')`, [far, today, month]);
const mgrSees = (await as(db, 'manager', `SELECT DISTINCT employee_id FROM get_payroll_events($1)`, [month])).rows.map((r) => r.employee_id);
check('a branch manager no longer sees payroll events of other branches', !mgrSees.includes(far) && mgrSees.length > 0, JSON.stringify(mgrSees));
const adminSees = (await as(db, 'admin', `SELECT DISTINCT employee_id FROM get_payroll_events($1)`, [month])).rows.map((r) => r.employee_id);
check('the admin still sees everyone', adminSees.includes(far));
const empSees = (await as(db, 'emp', `SELECT DISTINCT employee_id FROM get_payroll_events($1)`, [month])).rows.map((r) => r.employee_id);
check('an employee sees only themself', empSees.every((id) => id === IDS.emp));

done();
