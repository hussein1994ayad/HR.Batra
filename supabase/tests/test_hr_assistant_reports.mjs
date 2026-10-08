// المساعد الذكي — التقارير والتحليلات: فرع/شركة، رواتب الشهر، الجاهزية، التنبيهات، المقارنة، ترتيب الفروع.
import { setup, as, IDS, check, expectError, done } from './lib.mjs';

const db = await setup();
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];
const at = (date, hhmm) => `${date} ${hhmm}:00+03`;
const admin = async (sql, p = []) => (await as(db, 'admin', sql, p)).rows[0].r;
const daysAgo = async (n) => (await one(`SELECT ((now() AT TIME ZONE 'Asia/Baghdad')::date - $1::int)::text d`, [n])).d;
const dow = async (d) => (await one(`SELECT EXTRACT(DOW FROM $1::date)::int w`, [d])).w;

const A = '00000000-0000-0000-0000-0000000000b7';
const B = '00000000-0000-0000-0000-0000000000b8';
const B2 = '00000000-0000-0000-0000-0000000000b2';
await db.exec(`
  UPDATE employees SET join_date = '2026-01-01';
  UPDATE branches SET name = 'فرع كمب سارة' WHERE id = '${IDS.branch}';
  INSERT INTO branches (id, name, latitude, longitude, radius_meters) VALUES ('${B2}', 'فرع المنصور', 33.3, 44.3, 100);
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password) VALUES
    ('${A}', 'R1', 'أحمد المنضبط', '${IDS.branch}', 600000, '2026-01-01', false),
    ('${B}', 'R2', 'باسم المتأخر', '${B2}', 600000, '2026-01-01', false);
  UPDATE system_settings SET value = value || '{"no_record_from": "2026-09-02"}' WHERE key = 'payroll_policy';
`);
for (const e of [A, B]) {
  await db.query(`INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
    VALUES ($1, 'صباحي', '09:00', '17:00', 10, '{0,1,2,3,4,5,6}')`, [e]);
}
await db.query(`UPDATE work_schedule_history SET effective_from = '-infinity'`);

// 6 أيام: أحمد حاضر على الوقت؛ باسم متأخر 40 دقيقة كل يوم
const days = [];
for (let n = 8; n >= 2; n--) days.push(await daysAgo(n));
for (const d of days) {
  await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time) VALUES ($1, $2, $3, 'present', $4, $5)`,
    [A, IDS.branch, d, at(d, '08:55'), at(d, '17:05')]);
  await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time) VALUES ($1, $2, $3, 'late', $4, $5)`,
    [B, B2, d, at(d, '09:40'), at(d, '17:00')]);
}
const from = days[0], to = days.at(-1);

await expectError('reports are admin-only', as(db, 'manager', `SELECT assistant_payroll_readiness('2026-10')`), 'غير مصرح');

// 1) تقرير فرع
const br = await admin(`SELECT assistant_branch_attendance('كمب ساره', $1::date, $2::date) r`, [from, to]);
const names = br.employees.map((x) => x.employee.name);
check('branch report: only that branch, with its employees', names.includes('أحمد المنضبط') && !names.includes('باسم المتأخر'), JSON.stringify(names));
const all = await admin(`SELECT assistant_branch_attendance(NULL, $1::date, $2::date) r`, [from, to]);
check('company report: all branches', all.scope === 'كل الفروع' && all.employees.some((x) => x.employee.name === 'باسم المتأخر'));
await expectError('branch report longer than 31 days is refused',
  as(db, 'admin', `SELECT assistant_branch_attendance(NULL, '2026-01-01', '2026-03-01')`), '31');

// 2) رواتب الشهر
const month = (await one(`SELECT payroll_natural_month($1::date) m`, [to])).m;
const run = await admin(`SELECT assistant_payroll_run($1) r`, [month]);
const rowB = run.rows.find((x) => x.employee === 'باسم المتأخر');
check('payroll run: one row per employee with net and totals', rowB && Number(rowB.basic) === 600000 && run.totals.employees >= 2,
  JSON.stringify(run).slice(0, 300));

// 3) الجاهزية: تأخيرات باسم معلّقة
const ready = await admin(`SELECT assistant_payroll_readiness($1) r`, [month]);
check('readiness: pending lates counted, employees without a slip listed',
  Number(ready.pending_by_type.late) >= days.length && ready.without_slip.includes('باسم المتأخر'), JSON.stringify(ready).slice(0, 400));

// 4) التنبيهات: باسم يتأخر بنفس يوم الأسبوع؟ (6 أيام متتالية = كل يوم مرة) — نضيف 3 أسابيع بنفس اليوم
const w = await dow(to);
const extra = [];
for (let k = 1; k <= 3; k++) extra.push(await daysAgo(2 + 7 * k));
for (const d of extra) {
  await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time) VALUES ($1, $2, $3, 'late', $4, $5)`,
    [B, B2, d, at(d, '09:45'), at(d, '17:00')]);
}
const alerts = await admin(`SELECT assistant_alerts($1::date, $2::date) r`, [extra.at(-1), to]);
check('alerts: recurring late on the same weekday', alerts.recurring_late_weekday.some((x) => x.employee === 'باسم المتأخر' && x.times >= 3),
  JSON.stringify(alerts.recurring_late_weekday) + ' dow=' + w);

// 5) المقارنة
const cmp = await admin(`SELECT assistant_compare($1, NULL, $2, $3) r`, [B, month, month]);
check('compare: same month twice gives identical metrics with lates', JSON.stringify(cmp.a) === JSON.stringify(cmp.b) && cmp.a.late_times >= 1,
  JSON.stringify(cmp));

// 6) ترتيب الفروع والأكثر انضباطاً
const rank = await admin(`SELECT assistant_branch_ranking($1::date, $2::date) r`, [from, to]);
check('ranking: the punctual branch comes first', rank.branches[0].branch === 'فرع كمب سارة', JSON.stringify(rank.branches));
check('most disciplined: the punctual employee, not the late one',
  rank.most_disciplined.some((x) => x.employee === 'أحمد المنضبط') && !rank.most_disciplined.some((x) => x.employee === 'باسم المتأخر'));

done();
