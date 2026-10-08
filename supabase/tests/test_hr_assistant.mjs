// المساعد الذكي (دوال القراءة): أدمن فقط، بحث عربي، سجل يوم بيوم يطابق محرّك الرواتب، وبدون بيانات حساسة.
import { setup, as, IDS, check, expectError, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];
const at = (date, hhmm) => `${date} ${hhmm}:00+03`;
const admin = async (sql, p = []) => (await as(db, 'admin', sql, p)).rows[0];
const daysAgo = async (n) => (await one(`SELECT ((now() AT TIME ZONE 'Asia/Baghdad')::date - $1::int)::text d`, [n])).d;

const E = '00000000-0000-0000-0000-0000000000a7';
await db.exec(`
  UPDATE employees SET join_date = '2026-01-01';
  UPDATE branches SET name = 'فرع كمب سارة' WHERE id = '${IDS.branch}';
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password, phone)
    VALUES ('${E}', 'K7', 'علي محمد سعيد', '${IDS.branch}', 600000, '2026-01-01', false, '07701234567');
  UPDATE system_settings SET value = value || '{"no_record_from": "2026-09-02"}' WHERE key = 'payroll_policy';
`);
await db.query(`INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
  VALUES ($1, 'صباحي', '09:00', '17:00', 10, '{0,1,2,3,4,6}')`, [E]);
await db.query(`UPDATE work_schedule_history SET effective_from = '-infinity' WHERE employee_id = $1`, [E]);

// ---------------- الصلاحيات ----------------
await expectError('employee cannot use the assistant', as(db, 'emp', `SELECT assistant_find_employees('علي')`), 'غير مصرح');
await expectError('manager cannot use the assistant', as(db, 'manager', `SELECT assistant_find_employees('علي')`), 'غير مصرح');
await expectError('anonymous cannot use the assistant', as(db, 'anon', `SELECT assistant_find_employees('علي')`), 'permission denied');

// ---------------- البحث العربي ----------------
const find = async (query, branch = null) => (await admin(`SELECT assistant_find_employees($1, $2) r`, [query, branch])).r;
check('search by full name', (await find('علي محمد سعيد')).some((e) => e.id === E));
check('search with words skipped (علي سعيد)', (await find('علي سعيد')).some((e) => e.id === E));
check('search ignores hamza/taa marbuta differences (فرع كمب ساره)', (await find('علي', 'كمب ساره')).some((e) => e.id === E));
check('search by code', (await find('K7')).some((e) => e.id === E));
check('search result has no phone/email', !JSON.stringify(await find('علي')).match(/0770|phone|email|@/));

// ---------------- سجل الدوام يوم بيوم ----------------
// ثلاث أيام عمل سابقة (مو جمعة): متأخر مخصوم، غياب معفى، حاضر
const workDays = [];
for (let n = 2; workDays.length < 3 && n < 15; n++) {
  const d = await daysAgo(n);
  if ((await one(`SELECT EXTRACT(DOW FROM $1::date)::int w`, [d])).w !== 5) workDays.push(d);
}
const [dLate, dAbs, dOk] = workDays;
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time, deduction_status, deduction_reason)
  VALUES ($1, $2, $3, 'late', $4, $5, 'applied', 'بدون عذر')`, [E, IDS.branch, dLate, at(dLate, '09:30'), at(dLate, '17:00')]);
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status, deduction_reason)
  VALUES ($1, $2, $3, 'absent', 'ignored', 'نسي البصمة وهو مداوم')`, [E, IDS.branch, dAbs]);
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time)
  VALUES ($1, $2, $3, 'present', $4, $5)`, [E, IDS.branch, dOk, at(dOk, '08:58'), at(dOk, '17:05')]);

const from = workDays.slice().sort()[0];
const to = workDays.slice().sort()[2];
const log = (await admin(`SELECT assistant_attendance_log($1, $2::date, $3::date) r`, [E, from, to])).r;
const day = (d) => log.days.find((x) => x.date === d);
check('log header: employee and branch', log.employee.name === 'علي محمد سعيد' && log.employee.branch === 'فرع كمب سارة');
check('late day: status, 30 min, deducted 1,250 (8h shift: 20,000 ÷ 480 × 30)', day(dLate).status === 'متأخر' && Number(day(dLate).late_minutes) === 30
  && day(dLate).decision === 'مخصوم' && Number(day(dLate).deducted) === 1250 && day(dLate).check_in === '09:30', JSON.stringify(day(dLate)));
check('absent day excused with its note', day(dAbs).status === 'غياب' && day(dAbs).decision === 'معفى'
  && day(dAbs).events[0].reason === 'نسي البصمة وهو مداوم', JSON.stringify(day(dAbs)));
check('normal day: present, no decision', day(dOk).status === 'حاضر' && day(dOk).decision === null, JSON.stringify(day(dOk)));
check('summary counts match', log.summary.late === 1 && log.summary.absent >= 1 && log.summary.deducted_days === 1
  && log.summary.excused_days === 1 && Number(log.summary.deducted_total) === 1250, JSON.stringify(log.summary));
await expectError('range longer than 3 months is refused',
  as(db, 'admin', `SELECT assistant_attendance_log($1, '2026-01-01', '2026-06-01')`, [E]), 'أقصاها');

// ---------------- الراتب والوثائق والسلف وملخص اليوم ----------------
const month = (await one(`SELECT payroll_natural_month($1::date) m`, [dLate])).m;
const pay = (await admin(`SELECT assistant_payroll($1, $2) r`, [E, month])).r;
check('payroll: summary and the deducted late event', pay.summary && pay.events.some((e) => e.type === 'late' && e.decision === 'محتسب'),
  JSON.stringify(pay).slice(0, 300));
await db.query(`UPDATE employees SET document_urls = '["https://x/storage/v1/object/public/employee-documents/a.jpg"]'::jsonb WHERE id = $1`, [E]);
const docs = (await admin(`SELECT assistant_documents($1) r`, [E])).r;
check('documents: count and links', docs.count === 1 && docs.urls.length === 1);
const loans = (await admin(`SELECT assistant_loans($1) r`, [E])).r;
check('loans: empty list for an employee without loans', Array.isArray(loans) && loans.length === 0);
const overview = (await admin(`SELECT assistant_day_overview($1::date, NULL) r`, [dLate])).r;
check('day overview lists the late employee by branch', overview.branches.some((b) => (b.late_names || []).includes('علي محمد سعيد')),
  JSON.stringify(overview));
const top = (await admin(`SELECT assistant_top_late($1::date, $2::date, NULL) r`, [from, to])).r;
check('top late ranks him with 30 minutes', top[0] && top[0].employee === 'علي محمد سعيد' && Number(top[0].late_minutes) === 30);
const branches = (await admin(`SELECT assistant_branches() r`)).r;
check('branches list', branches.some((b) => b.name === 'فرع كمب سارة'));

done();
