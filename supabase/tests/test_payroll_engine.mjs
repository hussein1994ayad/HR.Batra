// محرّك الرواتب: المسيرات (1 → 26)، الترحيل، أجر اليوم ÷ 30، أجر الدقيقة حسب الدوام،
// القرارات، الإضافي، الاعتماد، الإغلاق، والتعديل بعد الإغلاق.
import fs from 'node:fs';
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();

// موظفون للاختبار: راتب 600,000 (يومي 20,000) ودوام 8 ساعات؛ وآخر دوام 6 ساعات
const E3 = '00000000-0000-0000-0000-0000000000e3'; // 600,000 — دوام 09:00-17:00
const E4 = '00000000-0000-0000-0000-0000000000e4'; // 600,000 — دوام 08:00-14:00 (6 ساعات)
const J = '00000000-0000-0000-0000-0000000000e5'; // مباشر جديد 2026-09-20
const T = '00000000-0000-0000-0000-0000000000e6'; // انتهت خدمته 2026-09-10
await db.exec(`
  UPDATE employees SET join_date = '2026-01-01';
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password) VALUES
    ('${E3}', 'E3', 'موظف ثمانية ساعات', '${IDS.branch}', 600000, '2026-01-01', false),
    ('${E4}', 'E4', 'موظف ست ساعات', '${IDS.branch}', 600000, '2026-01-01', false),
    ('${J}', 'E5', 'موظف جديد', '${IDS.branch}', 600000, '2026-09-20', false),
    ('${T}', 'E6', 'موظف منتهي', '${IDS.branch}', 600000, '2026-01-01', false);
  INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days) VALUES
    ('${E3}', 'صباحي', '09:00', '17:00', 15, '{0,1,2,3,4,5,6}'),
    ('${E4}', 'قصير', '08:00', '14:00', 15, '{0,1,2,3,4,5,6}');
  -- جداول موجودة من قبل الأيام المختبرة (الجدول المضاف اليوم يسري من اليوم فقط)
  UPDATE work_schedule_history SET effective_from = '-infinity';
  UPDATE employees SET is_active = false, termination_date = '2026-09-10' WHERE id = '${T}';
`);
// أيام بلا بصمة قبل تشغيل المحرّك لا تُعتبر غياباً
await db.exec(`UPDATE system_settings SET value = value || '{"no_record_from": "2026-09-02"}' WHERE key = 'payroll_policy'`);

const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];
const at = (date, hhmm) => `${date} ${hhmm}:00+03`;
const attend = (emp, date, inT, outT, status = 'present', ded = 'pending') => db.query(
  `INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time, deduction_status)
   VALUES ($1, $2, $3, $4, $5, $6, $7)`,
  [emp, IDS.branch, date, status, inT ? at(date, inT) : null, outT ? at(date, outT) : null, ded]);
const absent = (emp, date, ded = 'applied') => db.query(
  `INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status) VALUES ($1, $2, $3, 'absent', $4)`,
  [emp, IDS.branch, date, ded]);
const ev = (emp, date, type) => one(
  `SELECT * FROM payroll_events WHERE employee_id=$1 AND event_date=$2 AND event_type=$3 AND status<>'void'`, [emp, date, type]);
const run = async (month) => (await as(db, 'admin', `SELECT get_payroll_run($1) r`, [month])).rows[0].r;
const row = async (month, emp) => (await run(month)).rows.find((r) => r.employee_id === emp);
const N = (x) => Number(x);
const r2 = (x) => Math.round(x * 100) / 100;

// ---------------- المسيرات ----------------
const sep = await one(`SELECT * FROM payroll_periods WHERE period_month='2026-09'`);
check('September period is 1 → 26, paid on the 30th',
  String(sep.start_date).includes('2026-09-01') || sep.start_date.toISOString().startsWith('2026-09-01'));
const per = async (m) => {
  const p = await one(`SELECT to_char(start_date,'YYYY-MM-DD') s, to_char(cutoff_date,'YYYY-MM-DD') c,
                              to_char(payment_date,'YYYY-MM-DD') pay FROM ensure_payroll_period($1)`, [m]);
  return `${p.s}→${p.c} pay ${p.pay}`;
};
check('1) September period = 2026-09-01 → 26, paid 30', (await per('2026-09')) === '2026-09-01→2026-09-26 pay 2026-09-30', await per('2026-09'));
check('October period starts on 27 September', (await per('2026-10')) === '2026-09-27→2026-10-26 pay 2026-10-30', await per('2026-10'));
check('2) 28-day February 2027: 27 Jan → 26 Feb, payment capped at 28', (await per('2027-02')) === '2027-01-27→2027-02-26 pay 2027-02-28', await per('2027-02'));
check('3) 29-day February 2028: 27 Jan → 26 Feb, payment capped at 29', (await per('2028-02')) === '2028-01-27→2028-02-26 pay 2028-02-29', await per('2028-02'));
check('4) 31-day month (December): 27 Nov → 26 Dec', (await per('2026-12')) === '2026-11-27→2026-12-26 pay 2026-12-30', await per('2026-12'));
const nat = async (d) => (await one(`SELECT payroll_natural_month($1::date) m`, [d])).m;
check('day 26 belongs to its own month, 27..end to the next',
  (await nat('2026-09-26')) === '2026-09' && (await nat('2026-09-27')) === '2026-10' && (await nat('2026-09-30')) === '2026-10'
  && (await nat('2026-10-31')) === '2026-11' && (await nat('2026-12-27')) === '2027-01'
  && (await nat('2028-02-29')) === '2028-03' && (await nat('2027-02-28')) === '2027-03');
check('days before the first period are legacy (not in the engine)', (await nat('2026-08-15')) === null);

// ---------------- 5) أجر اليوم = الراتب ÷ 30 ----------------
await absent(E3, '2026-09-10');
let e = await ev(E3, '2026-09-10', 'absence');
check('5) salary 600,000 → one absent day deducts 20,000', e && N(e.amount) === 20000 && N(e.daily_rate) === 20000, JSON.stringify(e));
check('   applied absence is approved and lands in September', e.status === 'approved' && e.payroll_month === '2026-09');

// ---------------- 6/7) غياب يوم 26 ويوم 27 ----------------
await absent(E3, '2026-09-26');
await absent(E3, '2026-09-27');
const a26 = await ev(E3, '2026-09-26', 'absence');
const a27 = await ev(E3, '2026-09-27', 'absence');
check('6) absence on day 26 → September payroll', a26.payroll_month === '2026-09');
check('7) absence on day 27 → October payroll, date unchanged',
  a27.payroll_month === '2026-10' && a27.event_date.toISOString().startsWith('2026-09-27'), JSON.stringify(a27));

// ---------------- 8/9) تأخير يوم 26 ويوم 27 (من بداية الدوام) ----------------
await attend(E3, '2026-09-24', '09:30', '17:00', 'late');
await attend(E3, '2026-09-28', '09:40', '17:00', 'late');
const l26 = await ev(E3, '2026-09-24', 'late');
const l28 = await ev(E3, '2026-09-28', 'late');
// أجر الدقيقة = 20,000 ÷ 480 = 41.667
check('8) late 30 min counted from shift start = 30 × (20,000 ÷ 480) = 1,250 in September',
  l26 && N(l26.minutes) === 30 && N(l26.amount) === 1250 && l26.payroll_month === '2026-09', JSON.stringify(l26));
check('   late is pending until the admin decides (not auto-deducted)', l26.status === 'pending');
check('9) late on day 28 → October', l28 && l28.payroll_month === '2026-10' && N(l28.amount) === r2(40 * 20000 / 480));
await expectOk('admin approves the late deduction', as(db, 'admin', `SELECT decide_payroll_event($1, true, 'تأخير متكرر')`, [l26.id]));
check('   approval updates attendance too (compat with screens)',
  (await one(`SELECT deduction_status FROM attendance WHERE employee_id=$1 AND work_date='2026-09-24'`, [E3])).deduction_status === 'applied');
check('   employee notified with the amount',
  (await q(`SELECT body FROM notifications WHERE employee_id=$1 AND body LIKE '%1,250%'`, [E3])).length === 1);

// ---------------- 10) عدة حركات بعد القطع ----------------
await db.query(`INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, is_paid, status)
  VALUES ($1, '2026-09-28T21:00:00Z', '2026-09-29T21:00:00Z', 'other', false, 'approved')`, [E3]); // 29-30 أيلول بدون راتب
await db.query(`INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date) VALUES ($1, 'deduction', 7000, 'كسر زجاج', '2026-09-30')`, [E3]);
const oct = await q(`SELECT event_type, to_char(event_date,'MM-DD') d, amount, status FROM payroll_events
  WHERE employee_id=$1 AND payroll_month='2026-10' AND status<>'void' ORDER BY event_date, event_type DESC`, [E3]);
check('10) all events on 27–30 Sep go to October with their real dates',
  JSON.stringify(oct.map((r) => `${r.event_type}@${r.d}`)) ===
  JSON.stringify(['absence@09-27', 'late@09-28', 'unpaid_leave@09-29', 'unpaid_leave@09-30', 'manual_deduction@09-30']), JSON.stringify(oct));
check('   unpaid leave day = 20,000', oct.filter((r) => r.event_type === 'unpaid_leave').every((r) => N(r.amount) === 20000));

// ---------------- 11) دوام مختلف (6 ساعات) ----------------
await attend(E4, '2026-09-15', '08:30', '14:00', 'late', 'applied');
const l6 = await ev(E4, '2026-09-15', 'late');
check('11) 6-hour shift: minute = 20,000 ÷ 360 → 30 min late = 1,666.67',
  l6 && N(l6.amount) === r2(30 * 20000 / 360) && Math.abs(N(l6.minute_rate) - 20000 / 360) < 0.001, JSON.stringify(l6));

// ---------------- 12) غياب جزئي: إجازة زمنية بدون راتب ----------------
await db.query(`INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, is_hourly, start_hour, end_hour, is_paid, status)
  VALUES ($1, '2026-09-16T05:00:00Z', '2026-09-16T07:00:00Z', 'other', true, '08:00', '10:00', false, 'approved')`, [E4]);
const hl = await ev(E4, '2026-09-16', 'unpaid_leave');
check('12) 2-hour unpaid leave = 120 × minute rate, not a full day',
  hl && N(hl.minutes) === 120 && N(hl.amount) === r2(120 * 20000 / 360), JSON.stringify(hl));
await db.query(`INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, is_hourly, start_hour, end_hour, is_paid, status)
  VALUES ($1, '2026-09-17T05:00:00Z', '2026-09-17T07:00:00Z', 'other', true, '08:00', '10:00', true, 'approved')`, [E4]);
check('   paid hourly leave deducts nothing', N((await ev(E4, '2026-09-17', 'paid_leave')).amount) === 0);

// ---------------- لا نصف يوم، والخروج المبكر والبصمة الناقصة بقرار ----------------
await attend(E3, '2026-09-03', '09:00', null, 'present');
await db.query(`UPDATE attendance SET check_out_time=$2, status='half_day' WHERE employee_id=$1 AND work_date='2026-09-03'`,
  [E3, at('2026-09-03', '15:00')]);
check('early checkout no longer turns the day into a half day',
  (await one(`SELECT status FROM attendance WHERE employee_id=$1 AND work_date='2026-09-03'`, [E3])).status === 'present');
const el = await ev(E3, '2026-09-03', 'early_leave');
check('early leave counted in minutes (120) and waits for admin confirmation',
  el && N(el.minutes) === 120 && N(el.amount) === 5000 && el.status === 'pending', JSON.stringify(el));
await attend(E3, '2026-09-04', '09:00', null, 'present');
const mp = await ev(E3, '2026-09-04', 'missing_punch');
check('forgotten check-out = missing punch, amount 0 (no automatic deduction)', mp && N(mp.amount) === 0 && mp.status === 'pending');
check('no half-day deduction anywhere', (await q(`SELECT 1 FROM payroll_events WHERE notes LIKE '%نصف%'`)).length === 0);

// ---------------- 13) الساعات الإضافية ----------------
await attend(E3, '2026-09-05', '09:00', '18:00', 'present');
check('13) overtime is ignored while disabled', !(await ev(E3, '2026-09-05', 'overtime')));
await expectError('employee cannot change payroll policy', as(db, 'emp', `SELECT set_payroll_policy(26, 30, true)`), 'غير مصرح');
await expectOk('admin enables overtime (×1.5, from 30 min)', as(db, 'admin', `SELECT set_payroll_policy(26, 30, true, 1.5, 30)`));
await attend(E3, '2026-09-06', '09:00', '18:00', 'present');
const ot = await ev(E3, '2026-09-06', 'overtime');
check('   enabled: 60 min × minute rate × 1.5 = 3,750, pending approval',
  ot && N(ot.amount) === 3750 && ot.status === 'pending', JSON.stringify(ot));
await as(db, 'admin', `SELECT decide_payroll_event($1, true, NULL)`, [ot.id]);
await expectOk('admin disables overtime again', as(db, 'admin', `SELECT set_payroll_policy(26, 30, false)`));
check('   policy keeps legacy cycle keys for old clients (27 → 26)',
  (await one(`SELECT value FROM system_settings WHERE key='payroll_policy'`)).value.cycle_start_day === 27);

// ---------------- 14) إعادة الحساب ----------------
const before = (await q(`SELECT count(*)::int n FROM payroll_events WHERE status<>'void'`))[0].n;
await as(db, 'admin', `SELECT get_payroll_run('2026-09')`);
await as(db, 'admin', `SELECT get_payroll_run('2026-09')`);
const lateCount = (await q(`SELECT count(*)::int n FROM payroll_events WHERE employee_id=$1 AND event_type='late' AND status<>'void'`, [E3]))[0].n;
check('14) re-running the payroll does not duplicate events', lateCount === 2);
await db.query(`UPDATE attendance SET check_in_time=$2, status='present' WHERE employee_id=$1 AND work_date='2026-09-28'`, [E3, at('2026-09-28', '09:00')]);
check('   correcting a punch removes the late event', !(await ev(E3, '2026-09-28', 'late')));
check('   no-record workdays become pending absences (never auto-deducted)',
  (await q(`SELECT status FROM payroll_events WHERE employee_id=$1 AND source='no_record' AND status<>'void'`, [E3])).every((r) => r.status === 'pending'));

check('   days before "no_record_from" (system start) are not absences',
  !(await ev(E3, '2026-09-01', 'absence')) && (await ev(E3, '2026-09-02', 'absence'))?.status === 'pending');

// ---------------- الملخص والاعتماد ----------------
let r3 = await row('2026-09', E3);
// أيلول: غياب 10 و26 (40,000) + تأخير 24 (1,250) ؛ إضافي 3,750
check('September summary for E3: 600,000 − 41,250 + 3,750 = 562,500',
  N(r3.basic) === 600000 && N(r3.deductions) === 41250 && N(r3.earnings) === 3750 && N(r3.net) === 562500, JSON.stringify(r3));
check('   pending decisions are counted for the admin', N(r3.pending_count) >= 1);

const rj = await row('2026-09', J);
check('joiner on 20 Sep: 7 days × 20,000 = 140,000 (÷30 rule)', N(rj.basic) === 140000, JSON.stringify(rj));
const rt = await row('2026-09', T);
check('terminated on 10 Sep still in the run: 10 days = 200,000', rt && N(rt.basic) === 200000, JSON.stringify(rt));

await expectError('manager cannot approve slips', as(db, 'manager', `SELECT approve_payroll_slip($1, '2026-09')`, [E3]), 'غير مصرح');
const slip3 = (await as(db, 'admin', `SELECT approve_payroll_slip($1, '2026-09', '[{"type":"bonus","amount":10000,"reason":"مكافأة أداء"}]') id`, [E3])).rows[0].id;
const s3 = await one(`SELECT * FROM salary_slips WHERE id=$1`, [slip3]);
check('server computes the slip: net = 562,500 + 10,000 bonus = 572,500', N(s3.net_salary) === 572500 && s3.computed_by_engine, JSON.stringify(s3));
const lines = await q(`SELECT line_type FROM salary_slip_lines WHERE salary_slip_id=$1 ORDER BY line_type`, [slip3]);
check('slip keeps its detail lines', JSON.stringify(lines.map((l) => l.line_type)) === JSON.stringify(['absence', 'absence', 'bonus', 'late', 'overtime']), JSON.stringify(lines));
await expectError('double approval rejected', as(db, 'admin', `SELECT approve_payroll_slip($1, '2026-09')`, [E3]), 'مسبقاً');

// حركة جديدة لأيلول بعد اعتماد كشف الموظف ← تذهب لأول مسير مفتوح بدون كشف (تشرين الأول)
await absent(E3, '2026-09-12');
check('absence added after the slip → carried to October', (await ev(E3, '2026-09-12', 'absence')).payroll_month === '2026-10');

// ---------------- 15) القفل ----------------
await expectError('cannot close while employees have no slip', as(db, 'admin', `SELECT close_payroll_period('2026-09') r`)
  .then((x) => { if (!x.rows[0].r.success) throw new Error(x.rows[0].r.error); }), 'بدون كشف');
for (const r of (await run('2026-09')).rows) {
  if (!r.slip) await as(db, 'admin', `SELECT approve_payroll_slip($1, '2026-09')`, [r.employee_id]);
}
const closed = (await as(db, 'admin', `SELECT close_payroll_period('2026-09') r`)).rows[0].r;
check('15) period closes once every employee has a slip', closed.success === true, JSON.stringify(closed));
await expectError('closed period: no revert', as(db, 'admin', `SELECT revert_payroll_slip($1)`, [slip3]), 'مغلق');
check('pending September decisions moved to October on close',
  (await q(`SELECT 1 FROM payroll_events WHERE payroll_month='2026-09' AND status='pending' AND salary_slip_id IS NULL`)).length === 0);

// ---------------- 16) تعديل بعد الإغلاق ----------------
const netBefore = N((await one(`SELECT net_salary FROM salary_slips WHERE id=$1`, [slip3])).net_salary);
// الأدمن يعفي غياب 10 أيلول بعد إغلاق المسير
await db.query(`UPDATE attendance SET deduction_status='ignored' WHERE employee_id=$1 AND work_date='2026-09-10'`, [E3]);
const adj = await one(`SELECT * FROM payroll_events WHERE employee_id=$1 AND event_type='adjustment' AND status<>'void'`, [E3]);
check('16) editing a closed day: slip unchanged, +20,000 adjustment in October',
  N((await one(`SELECT net_salary FROM salary_slips WHERE id=$1`, [slip3])).net_salary) === netBefore
  && adj && adj.payroll_month === '2026-10' && N(adj.amount) === 20000 && adj.direction === 1 && adj.carried_from === '2026-09',
  JSON.stringify(adj));
await db.query(`UPDATE attendance SET deduction_status='applied' WHERE employee_id=$1 AND work_date='2026-09-10'`, [E3]);
check('   reverting the edit cancels the adjustment (no double effect)',
  !(await one(`SELECT 1 x FROM payroll_events WHERE employee_id=$1 AND event_type='adjustment' AND status<>'void'`, [E3])));

await expectError('reopen needs a reason', as(db, 'admin', `SELECT reopen_payroll_period('2026-09', ' ')`), 'سبب');
await expectOk('admin reopens with a reason', as(db, 'admin', `SELECT reopen_payroll_period('2026-09', 'تصحيح خطأ')`));
check('reopen is audited', (await q(`SELECT 1 FROM audit_log WHERE table_name='payroll_periods'`)).length === 1);
await expectOk('open period: revert works', as(db, 'admin', `SELECT revert_payroll_slip($1)`, [slip3]));
check('revert removes the approval bonus and unlinks events',
  (await q(`SELECT 1 FROM payroll_events WHERE salary_slip_id=$1`, [slip3])).length === 0
  && (await q(`SELECT 1 FROM payroll_events WHERE source='approval' AND employee_id=$1`, [E3])).length === 0);

// ---------------- أشهر 30 و31 يوماً: القسمة دائماً على 30 ----------------
await absent(E3, '2026-10-31'); // تشرين الأول 31 يوماً → مسير تشرين الثاني
const a31 = await ev(E3, '2026-10-31', 'absence');
check('31st of October → November payroll, still 20,000', a31.payroll_month === '2026-11' && N(a31.amount) === 20000);
await absent(E3, '2027-02-15');
check('February (28 days) absence is still 600,000 ÷ 30', N((await ev(E3, '2027-02-15', 'absence')).amount) === 20000);

// ---------------- الخصم المزدوج القديم ----------------
// نسخة قديمة من الموقع: تضيف قيد خصم ثم تعتمد الحضور بنفس السبب
await db.query(`INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date) VALUES ($1, 'deduction', 25000, 'غياب بدون عذر', '2026-10-05')`, [E4]);
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status, deduction_reason)
  VALUES ($1, $2, '2026-10-05', 'absent', 'applied', 'غياب بدون عذر')`, [E4, IDS.branch]);
const oct5 = await q(`SELECT event_type, amount FROM payroll_events WHERE employee_id=$1 AND event_date='2026-10-05' AND status='approved'`, [E4]);
check('old-client decision is deducted once (attendance), not twice',
  oct5.length === 1 && oct5[0].event_type === 'absence' && N(oct5[0].amount) === 20000, JSON.stringify(oct5));

// ---------------- كشف قديم داخل مسير المحرّك ----------------
// كشف قديم لشهر تشرين الثاني أُنشئ يوم 10 تشرين الثاني
await db.query(`INSERT INTO salary_slips (employee_id, work_month, basic_salary, net_salary, status, created_at)
  VALUES ($1, '2026-11', 900000, 880000, 'published', '2026-11-10 12:00+03')`, [IDS.emp2]);
await absent(IDS.emp2, '2026-11-03');
const legacyEv = await ev(IDS.emp2, '2026-11-03', 'absence');
check('event dated before a legacy (browser) slip was made is treated as already paid',
  legacyEv.payroll_month === '2026-11' && legacyEv.salary_slip_id !== null);
await absent(IDS.emp2, '2026-11-21');
const afterLegacy = await ev(IDS.emp2, '2026-11-21', 'absence');
check('QA#8: event dated after the legacy slip is NOT lost — carried to the next open payroll',
  afterLegacy.salary_slip_id === null && afterLegacy.payroll_month === '2026-12', JSON.stringify(afterLegacy));

// ---------------- تصليحات الفحص الشامل (QA) ----------------
const Q = '00000000-0000-0000-0000-0000000000f7'; // 1,000,000 — دوام E3 نفسه (09:00-17:00)
await db.exec(`
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ('${Q}', 'Q1', 'موظف فحص', '${IDS.branch}', 1000000, '2026-01-01', false);
  INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
    VALUES ('${Q}', 'صباحي', '09:00', '17:00', 15, '{0,1,2,3,4,5,6}');
  UPDATE work_schedule_history SET effective_from = '-infinity' WHERE employee_id = '${Q}';
`);
const qEvents = async (d) => q(`SELECT event_type, minutes, amount, status FROM payroll_events WHERE employee_id=$1 AND event_date=$2 AND status<>'void' ORDER BY event_type`, [Q, d]);

// QA#3: إجازة زمنية مدفوعة 09-11 ثم بصمة 11:00 → لا تأخير
await db.query(`INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, is_hourly, start_hour, end_hour, is_paid, status)
  VALUES ($1, '2026-12-07T06:00:00Z', '2026-12-07T08:00:00Z', 'other', true, '09:00', '11:00', true, 'approved')`, [Q]);
await attend(Q, '2026-12-07', '11:00', '17:00', 'late', 'applied');
check('QA#3: paid hourly leave 09-11 + punch 11:00 → no late deduction',
  (await qEvents('2026-12-07')).every((e) => e.event_type !== 'late'), JSON.stringify(await qEvents('2026-12-07')));
// بصمة 11:30 → تأخير 30 دقيقة فقط (بعد نهاية الإجازة)
await attend(Q, '2026-12-08', '11:30', '17:00', 'late', 'applied');
await db.query(`INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, is_hourly, start_hour, end_hour, is_paid, status)
  VALUES ($1, '2026-12-08T06:00:00Z', '2026-12-08T08:00:00Z', 'other', true, '09:00', '11:00', true, 'approved')`, [Q]);
const late8 = (await qEvents('2026-12-08')).find((e) => e.event_type === 'late');
check('   leave 09-11 + punch 11:30 → only 30 minutes late', late8 && N(late8.minutes) === 30, JSON.stringify(await qEvents('2026-12-08')));

// QA#9: إجازة زمنية بدون راتب 15-17 + انصراف 15:00 → خصم الإجازة فقط، لا خروج مبكر
await db.query(`INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, is_hourly, start_hour, end_hour, is_paid, status)
  VALUES ($1, '2026-12-09T12:00:00Z', '2026-12-09T14:00:00Z', 'other', true, '15:00', '17:00', false, 'approved')`, [Q]);
await attend(Q, '2026-12-09', '09:00', '15:00');
const ev9 = await qEvents('2026-12-09');
check('QA#9: unpaid hourly leave 15-17 + leaving at 15:00 → deducted once (the leave), no early-leave',
  ev9.length === 1 && ev9[0].event_type === 'unpaid_leave' && N(ev9[0].amount) === r2(120 * 1000000 / 30 / 480), JSON.stringify(ev9));

// إجازة زمنية معتمدة حتى نهاية الدوام + حضور بلا انصراف → لا "بصمة ناقصة" (ما يحتاج يرجع يبصم)
await db.query(`INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, is_hourly, start_hour, end_hour, is_paid, status)
  VALUES ($1, '2026-09-08T12:00:00Z', '2026-09-08T14:00:00Z', 'other', true, '15:00', '17:00', true, 'approved')`, [Q]);
await attend(Q, '2026-09-08', '09:00', null);
check('hourly leave until the end of the shift → no missing-punch for the absent check-out',
  !(await ev(Q, '2026-09-08', 'missing_punch')), JSON.stringify(await qEvents('2026-09-08')));
await attend(Q, '2026-09-09', '09:00', null);
check('   without such leave the missing punch is still raised', !!(await ev(Q, '2026-09-09', 'missing_punch')));

// QA#4: يوم مسجّل غياب ثم إجازة سنوية مدفوعة معتمدة → الإجازة تُحتسب، لا خصم
await absent(Q, '2026-12-10');
await db.query(`INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, is_paid, status)
  VALUES ($1, '2026-12-09T21:00:00Z', '2026-12-09T21:00:00Z', 'annual', true, 'approved')`, [Q]);
const ev10 = await qEvents('2026-12-10');
check('QA#4: paid leave approved for a day marked absent → no absence deduction',
  ev10.length === 1 && ev10[0].event_type === 'paid_leave' && N(ev10[0].amount) === 0, JSON.stringify(ev10));

// QA#15: راتب 1,000,000، غياب يومين، قسط 100,000 → 833,333 (تقريب على المجموع)
await absent(Q, '2026-12-14');
await absent(Q, '2026-12-15');
const qLoan = (await q(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
  VALUES ($1, 300000, 100000, 3, 300000, 'x', 'approved') RETURNING id`, [Q]))[0].id;
await db.exec(`INSERT INTO loan_installments (loan_id, due_date, amount) VALUES ('${qLoan}', '2026-12-15', 100000), ('${qLoan}', '2027-01-15', 100000), ('${qLoan}', '2027-02-15', 100000)`);
const sQ = (await q(`SELECT payroll_employee_summary($1, '2026-12') s`, [Q]))[0].s;
// غياب 14 و15 (يومان)؛ مدفوعة 7 و10 بلا خصم؛ إجازة زمنية 9 = 4,166.67؛ تأخير 30 د يوم 8 معلّق
// حساب مستقل: غياب يومين + إجازة زمنية بدون راتب 120 د + تأخير 30 د (بعد الإجازة المدفوعة) + قسط 100,000
const dailyQ = 1000000 / 30, minuteQ = dailyQ / 480;
const exactDed = 2 * dailyQ + 120 * minuteQ + 30 * minuteQ; // 77,083.33
check('QA#15: net rounds on the total — 1,000,000 − 77,083.33 − 100,000 = 822,916.67 → 822,917',
  N(sQ.deductions) === Math.round(exactDed) && N(sQ.net) === Math.round(1000000 - exactDed - 100000), JSON.stringify({ d: sQ.deductions, net: sQ.net, exact: 1000000 - exactDed - 100000 }));

// QA#10: سلفة نقدية لا تُخصم من الراتب
const cashLoan = (await q(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status, payment_method)
  VALUES ($1, 50000, 50000, 1, 50000, 'x', 'approved', 'cash') RETURNING id`, [Q]))[0].id;
await db.exec(`INSERT INTO loan_installments (loan_id, due_date, amount) VALUES ('${cashLoan}', '2026-12-20', 50000)`);
check('QA#10: a cash loan is not deducted from the salary',
  N((await q(`SELECT payroll_employee_summary($1, '2026-12') s`, [Q]))[0].s.loans) === 100000);

// QA#11: ترك العمل وعليه سلفة → تنبيه بالرصيد الباقي
await db.exec(`UPDATE employees SET is_active = false, termination_date = '2026-12-20' WHERE id = '${Q}'`);
check('QA#11: leaving with a loan shows the balance still owed after the final slip',
  N((await q(`SELECT payroll_employee_summary($1, '2026-12') s`, [Q]))[0].s.loan_balance_after_exit) === 200000);
await db.exec(`UPDATE employees SET is_active = true, termination_date = NULL WHERE id = '${Q}'`);

// QA#13: العطلة الرسمية — لا غياب "بدون بصمة" ولا تذكير
const pastDay = (await q(`SELECT ((now() AT TIME ZONE 'Asia/Baghdad')::date - 2)::text d`))[0].d;
const pastMonth = (await q(`SELECT payroll_natural_month($1::date) m`, [pastDay]))[0].m;
await as(db, 'admin', `SELECT get_payroll_run($1)`, [pastMonth]);
const beforeHoliday = (await q(`SELECT count(*)::int n FROM payroll_events WHERE event_date=$1 AND source='no_record' AND status<>'void'`, [pastDay]))[0].n;
await expectError('employee cannot add official holidays', as(db, 'emp', `INSERT INTO official_holidays (holiday_date, name) VALUES ($1, 'x')`, [pastDay]), 'row-level security');
await expectOk('admin adds an official holiday', as(db, 'admin', `INSERT INTO official_holidays (holiday_date, name) VALUES ($1, 'عطلة رسمية')`, [pastDay]));
const afterHoliday = (await q(`SELECT count(*)::int n FROM payroll_events WHERE event_date=$1 AND source='no_record' AND status<>'void'`, [pastDay]))[0].n;
check('QA#13: an official holiday removes the pending "no punch" absences of that day', beforeHoliday > 0 && afterHoliday === 0, `${beforeHoliday} → ${afterHoliday}`);
await db.exec(`INSERT INTO official_holidays (holiday_date, name) VALUES ((now() AT TIME ZONE 'Asia/Baghdad')::date, 'اليوم عطلة') ON CONFLICT DO NOTHING`);
check('   no punch reminders on an official holiday', (await q(`SELECT check_and_send_attendance_reminders() n`))[0].n === 0);

// QA#2 و#6: المدير لا يضيف مكافآت، ولا يقرّر على نفسه أو على فرع آخر، ويرى حركات فرعه فقط
await expectError('QA#2: manager cannot add a bonus (even for himself)',
  as(db, 'manager', `INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date) VALUES ($1, 'bonus', 99999, 'x', '2026-12-01')`, [IDS.manager]), 'row-level security');
await expectOk('   admin (also an employee) can still add bonuses/deductions',
  as(db, 'admin', `INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date) VALUES ($1, 'bonus', 1000, 'أدمن', '2026-12-01')`, [IDS.admin]));
const B2 = '00000000-0000-0000-0000-0000000000b2';
const OT = '00000000-0000-0000-0000-0000000000f8';
await db.exec(`INSERT INTO branches (id, name, latitude, longitude, radius_meters) VALUES ('${B2}', 'فرع آخر', 33, 44, 100);
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password) VALUES ('${OT}', 'Q2', 'فرع آخر', '${B2}', 600000, '2026-01-01', false);
  INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status) VALUES ('${OT}', '${B2}', '2026-12-02', 'absent', 'pending'), ('${IDS.manager}', '${IDS.branch}', '2026-12-02', 'absent', 'pending');`);
const otherEv = (await q(`SELECT id FROM payroll_events WHERE employee_id=$1 AND event_type='absence'`, [OT]))[0].id;
const selfEv = (await q(`SELECT id FROM payroll_events WHERE employee_id=$1 AND event_date='2026-12-02'`, [IDS.manager]))[0].id;
await expectError('QA#6: manager cannot decide for another branch', as(db, 'manager', `SELECT decide_payroll_event($1, true, NULL)`, [otherEv]), 'فرع آخر');
await expectError('   manager cannot decide his own deductions', as(db, 'manager', `SELECT decide_payroll_event($1, false, NULL)`, [selfEv]), 'حركاتك');
const mgrSees = (await as(db, 'manager', `SELECT DISTINCT employee_id FROM payroll_events`)).rows.map((r) => r.employee_id);
check('   manager reads payroll events of his branch only', !mgrSees.includes(OT) && mgrSees.includes(IDS.emp), JSON.stringify(mgrSees));
const mgrPending = (await as(db, 'manager', `SELECT DISTINCT employee_id FROM get_pending_payroll_decisions()`)).rows.map((r) => r.employee_id);
check('   manager pending list excludes other branches and himself', !mgrPending.includes(OT) && !mgrPending.includes(IDS.manager), JSON.stringify(mgrPending));

// QA#7 و#16: قيم غير صحيحة
await expectError('QA#7: negative bonus is rejected', as(db, 'admin', `INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date) VALUES ($1, 'bonus', -50000, 'x', '2026-12-01')`, [Q]), 'chk_bd_amount_positive');
await expectError('   zero deduction is rejected', as(db, 'admin', `INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date) VALUES ($1, 'deduction', 0, 'x', '2026-12-01')`, [Q]), 'chk_bd_amount_positive');
await expectError('QA#16: negative salary is rejected', db.query(`UPDATE employees SET monthly_salary_iqd = -5 WHERE id=$1`, [Q]), 'chk_employees_salary_non_negative');
await expectError('   installment larger than the loan is rejected', as(db, 'emp', `INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
  VALUES ($1, 100000, 500000, 1, 100000, 'x', 'pending')`, [IDS.emp]), 'chk_loans_installment_le_amount');

// QA#1: الحذف المجدول لا يمسح التاريخ المالي
const slipsBefore = (await q(`SELECT count(*)::int n FROM salary_slips WHERE employee_id=$1`, [E4]))[0].n;
await db.exec(`INSERT INTO archived_employees (employee_id, full_name, archive_type, scheduled_deletion_date) VALUES ('${E4}', 'موظف ست ساعات', 'scheduled_deletion', now() - interval '1 day')`);
await db.exec(`SELECT set_config('request.jwt.claim.sub', '', false), set_config('request.jwt.claim.role', '', false)`); // مهمة النظام الليلية
await db.query(`SELECT * FROM perform_daily_cleanup()`);
const emp3 = (await q(`SELECT full_name, is_active FROM employees WHERE id=$1`, [E4]))[0];
check('QA#1: scheduled deletion anonymises the employee but keeps salary slips, loans and attendance',
  emp3 && emp3.full_name === 'مستخدم محذوف' && !emp3.is_active
  && (await q(`SELECT count(*)::int n FROM salary_slips WHERE employee_id=$1`, [E4]))[0].n === slipsBefore && slipsBefore > 0
  && (await q(`SELECT count(*)::int n FROM attendance WHERE employee_id=$1`, [E4]))[0].n > 0,
  JSON.stringify({ emp3, slipsBefore }));

// ---------------- التوافق مع النسخ القديمة ----------------
await db.query(`INSERT INTO system_settings (key, value) VALUES ('payroll_policy', '{"cycle_start_day": 1, "cycle_end_day": 31}')
  ON CONFLICT (key) DO UPDATE SET value = excluded.value`);
const pol = (await one(`SELECT value FROM system_settings WHERE key='payroll_policy'`)).value;
check('old settings page overwrite keeps the engine keys (cutoff 26, cycle 27→26)',
  pol.cutoff_day === 26 && pol.cycle_start_day === 27 && pol.cycle_end_day === 26 && pol.no_record_from === '2026-09-02', JSON.stringify(pol));
await db.query(`INSERT INTO salary_slips (employee_id, work_month, basic_salary, net_salary, status) VALUES ($1, '2026-08', 1000000, 990000, 'published')`, [IDS.emp]);
const legacyRun = await run('2026-08');
check('months before the engine show their stored slips (read-only)',
  legacyRun.period.legacy === true && legacyRun.rows.length === 1 && N(legacyRun.rows[0].net) === 990000 && legacyRun.rows[0].slip.legacy === true,
  JSON.stringify(legacyRun));

// ---------------- الصلاحيات ----------------
await expectError('employee cannot run payroll', as(db, 'emp', `SELECT get_payroll_run('2026-09')`), 'غير مصرح');
await expectError('employee cannot decide events', as(db, 'emp', `SELECT decide_payroll_event($1, false, NULL)`, [el.id]), 'غير مصرح');
await expectOk('manager can list and decide pending events', as(db, 'manager', `SELECT * FROM get_pending_payroll_decisions()`));
const own = await as(db, 'emp', `SELECT count(*)::int n FROM payroll_events WHERE employee_id <> $1`, [IDS.emp]);
check('employee sees only own payroll events', own.rows[0].n === 0);
await expectError('employee cannot write payroll events',
  as(db, 'emp', `INSERT INTO payroll_events (employee_id, event_date, event_type, direction, payroll_month, source) VALUES ($1, '2026-10-01', 'bonus', 1, '2026-10', 'manual')`, [IDS.emp]),
  'row-level security');

// Supabase يفعّل pg_safeupdate لطلبات الـ API (PGlite لا يفعّله): DELETE/UPDATE بدون WHERE يفشل هناك
const migDir = new URL('../migrations/', import.meta.url);
const unsafe = fs.readdirSync(migDir).filter((f) => f.endsWith('.sql')).flatMap((f) =>
  fs.readFileSync(new URL(f, migDir), 'utf8').split('\n').map((l, i) => [f, i + 1, l])
    .filter(([, , l]) => /^\s*DELETE\s+FROM\s+[\w.]+\s*;/i.test(l)).map(([file, n]) => `${file}:${n}`));
check('no DELETE without WHERE in migrations (rejected by pg_safeupdate on Supabase)', unsafe.length === 0, unsafe.join(', '));

done();
