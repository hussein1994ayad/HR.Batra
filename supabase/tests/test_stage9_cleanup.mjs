// تدقيق 14/10/2026 — المرحلة 9 (الجزء أ): تنظيف بدون ما يتغير أي حساب.
// (CODE-013) ماكو راتب افتراضي مخفي، (CODE-008) الفهارس، (CODE-006) الأشياء الميتة انشالت،
// (CODE-007) رمز الإشعارات بمكان واحد، (CODE-003) دالة اليوم مقسومة ودوالها الداخلية مقفولة.
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];

// ---------------- CODE-013 ----------------
await q(`INSERT INTO auth.users (id, email) VALUES ('00000000-0000-0000-0000-0000000000a9', 'nosal@x')`);
await expectError('1) adding an employee without a salary is a clear error (no hidden 600,000)',
  db.query(`INSERT INTO employees (id, employee_code, full_name, branch_id) VALUES ('00000000-0000-0000-0000-0000000000a9', 'NS', 'بدون راتب', $1)`, [IDS.branch]),
  'monthly_salary_iqd');
const def = await one(`SELECT column_default d, is_nullable n FROM information_schema.columns WHERE table_name = 'employees' AND column_name = 'monthly_salary_iqd'`);
check('   the salary column has no default and is required', def.d === null && def.n === 'NO', JSON.stringify(def));
const created = await expectOk('   the admin still creates an employee with a salary', as(db, 'admin',
  `SELECT create_employee_secure('new9@x', 'Pass1234', 'موظف جديد', '', 'employee', $1, 700000, ARRAY[]::text[], NULL) id`, [IDS.branch]));
const ne = created ? await one(`SELECT monthly_salary_iqd::int s, employee_code c, join_date::text j FROM employees WHERE id = $1`, [created.rows[0].id]) : null;
check('   ...with his salary, an automatic code and today (Baghdad) as start date', ne?.s === 700000 && /^EMP-\d+$/.test(ne?.c ?? '')
  && ne?.j === (await one(`SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date::text d`)).d, JSON.stringify(ne));

// ---------------- CODE-008 ----------------
const idx = (await q(`SELECT indexname FROM pg_indexes WHERE tablename IN ('attendance', 'salary_slips', 'loan_installments')`)).map((r) => r.indexname);
check('2) duplicate indexes are gone and loan installments have their index',
  !idx.includes('idx_attendance_employee_date') && !idx.includes('idx_salary_slips_employee_month') && idx.includes('idx_loan_installments_loan'), JSON.stringify(idx));

// ---------------- CODE-006 ----------------
const gone = await one(`SELECT to_regclass('public.documents') a, to_regclass('public.branch_schedules') b, to_regclass('public.orphan_storage_candidates_cache') c,
  to_regprocedure('public.refresh_orphan_candidates_cache()') f, to_regprocedure('public.strip_plain_password()') g`);
check('3) unused tables and their empty weekly job are gone', gone.a === null && gone.b === null && gone.c === null && gone.f === null && gone.g === null, JSON.stringify(gone));
const cols = (await q(`SELECT table_name || '.' || column_name c FROM information_schema.columns
  WHERE (table_name = 'employees' AND column_name = 'plain_password') OR (table_name = 'leave_balances' AND column_name IN ('annual_used', 'sick_used'))`)).map((r) => r.c);
check('   the plain-password column and the unused leave columns are gone', cols.length === 0, JSON.stringify(cols));
const bal = (await as(db, 'emp', `SELECT get_leave_balance($1) b`, [IDS.emp])).rows[0].b;
check('   the leave balance still works (it is counted from the requests)', bal?.annual?.entitlement !== undefined, JSON.stringify(bal));
await expectOk('   changing a login password still works', as(db, 'admin', `SELECT update_employee_credentials($1, 'e@x', 'NewPass9', '0770')`, [IDS.emp]));
check('   tracking schedules and geofence assignments stay until every phone has the new app',
  (await one(`SELECT to_regclass('public.tracking_schedules') a, to_regclass('public.employee_geofence_assignments') b`)).a !== null);

// ---------------- CODE-007 ----------------
await q(`UPDATE employees SET fcm_token = 'tok-old-app' WHERE id = $1`, [IDS.emp]);
check('4) an old app saving its code on the employee row also lands in the one place (fcm_tokens)',
  (await q(`SELECT 1 FROM fcm_tokens WHERE employee_id = $1 AND token = 'tok-old-app'`, [IDS.emp])).length === 1);
await q(`INSERT INTO device_tokens (employee_id, token, platform) VALUES ($1, 'tok-device', 'android')`, [IDS.emp2]);
check('   ...and so does the old second copy', (await one(`SELECT device_platform p FROM fcm_tokens WHERE employee_id = $1 AND token = 'tok-device'`, [IDS.emp2]))?.p === 'android');
await q(`UPDATE employees SET fcm_token = 'tok-old-app', full_name = full_name WHERE id = $1`, [IDS.emp]);
await q(`INSERT INTO device_tokens (employee_id, token, platform) VALUES ($1, 'tok-old-app', 'android')`, [IDS.emp]);
check('   no duplicates', (await one(`SELECT count(*)::int c FROM fcm_tokens WHERE employee_id = $1 AND token = 'tok-old-app'`, [IDS.emp])).c === 1);

// ---------------- CODE-003 ----------------
for (const fn of ['_payroll_day_attendance_events', '_payroll_day_leave_events', '_payroll_day_hourly_leaves', '_payroll_day_apply']) {
  const r = await one(`SELECT count(*)::int c FROM pg_proc WHERE proname = $1`, [fn]);
  check(`5) ${fn} exists`, r.c === 1);
}
await expectError('   the inner parts cannot be called by a user (only through the day calculation)',
  as(db, 'admin', `SELECT _payroll_day_hourly_leaves($1, CURRENT_DATE, 1)`, [IDS.emp]), 'permission denied');
const len = (await one(`SELECT length(pg_get_functiondef('public.sync_payroll_day(uuid,date)'::regprocedure)) n`)).n;
check(`   the day calculation itself is now short (${len} characters, was ~15,400)`, len < 6000);

done();
