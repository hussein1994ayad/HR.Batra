// مبلغ الخصم يتعدل عند القرار (ويبقى بعد إعادة الحساب)، قرار غياب اليوم قبل الاحتساب، أجر اليوم، و«الغائبون اليوم» بلوحة التعاميم.
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];
const N = (v) => Number(v);

await db.exec(`UPDATE employees SET join_date = '2026-01-01'`);
const E = '00000000-0000-0000-0000-0000000000e1';
await db.exec(`
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ('${E}', 'DA1', 'موظف المبلغ', '${IDS.branch}', 600000, '2026-01-01', false);
  INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
    VALUES ('${E}', 'صباحي', '09:00', '17:00', 15, '{0,1,2,3,4,5,6}');
  UPDATE work_schedule_history SET effective_from = '-infinity';
  UPDATE system_settings SET value = value || '{"no_record_from": "2026-09-02"}' WHERE key = 'payroll_policy';
`);
await q(`SELECT ensure_payroll_period('2026-09')`);
const at = (d, hm) => `${d} ${hm}:00+03`;
const ev = async (d, type) => one(`SELECT id, amount::numeric a, amount_override::numeric o, status, source FROM payroll_events
  WHERE employee_id = $1 AND event_date = $2 AND event_type = $3 AND status <> 'void' ORDER BY updated_at DESC LIMIT 1`, [E, d, type]);
const deductions = async () => N((await one(`SELECT payroll_employee_summary($1, '2026-09') s`, [E])).s.deductions);

// ---------------- 1) تأخير: المبلغ المحسوب ثم مبلغ معدّل ----------------
await q(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time) VALUES ($1, $2, '2026-09-07', 'late', $3, $4)`,
  [E, IDS.branch, at('2026-09-07', '10:00'), at('2026-09-07', '17:00')]);
const late = await ev('2026-09-07', 'late');
check('1) late 60 min is computed at 2,500 and waits for a decision', late && N(late.a) === 2500 && late.status === 'pending', JSON.stringify(late));

await expectOk('   the admin deducts a different amount (1,000)', as(db, 'admin', `SELECT decide_payroll_event($1, true, 'أول مرة', 1000)`, [late.id]));
const lateCustom = await ev('2026-09-07', 'late');
check('   ...the event carries the edited amount', N(lateCustom.a) === 1000 && N(lateCustom.o) === 1000 && lateCustom.status === 'approved', JSON.stringify(lateCustom));
check('   ...and only that is deducted', (await deductions()) === 1000);
check('   ...the employee is told the edited amount', (await one(`SELECT count(*)::int c FROM notifications WHERE employee_id = $1 AND body LIKE '%1,000 د.ع%'`, [E])).c === 1);

await q(`SELECT sync_payroll_day($1, '2026-09-07')`, [E]);
await q(`SELECT sync_payroll_period('2026-09', $1)`, [E]);
check('   recalculating keeps the edited amount', N((await ev('2026-09-07', 'late')).a) === 1000 && (await deductions()) === 1000);

await expectOk('   deducting again with no amount returns to the computed one', as(db, 'admin', `SELECT decide_payroll_event($1, true, 'متكرر')`, [late.id]));
const lateBack = await ev('2026-09-07', 'late');
check('   ...2,500 and no override', N(lateBack.a) === 2500 && lateBack.o === null && (await deductions()) === 2500, JSON.stringify(lateBack));

await as(db, 'admin', `SELECT decide_payroll_event($1, true, 'x', 1500)`, [late.id]);
await expectOk('   excusing clears the edited amount', as(db, 'admin', `SELECT decide_payroll_event($1, false, 'عذر مقبول', 1500)`, [late.id]));
const lateExcused = await ev('2026-09-07', 'late');
check('   ...nothing deducted, override gone, amount back to computed', lateExcused.status === 'ignored' && lateExcused.o === null && N(lateExcused.a) === 2500 && (await deductions()) === 0,
  JSON.stringify(lateExcused));

await expectError('   a negative amount is refused', as(db, 'admin', `SELECT decide_payroll_event($1, true, 'x', -5)`, [late.id]), 'صفر أو أكثر');
await expectError('   an amount above the monthly salary is refused (typo guard)', as(db, 'admin', `SELECT decide_payroll_event($1, true, 'x', 6000000)`, [late.id]), 'أكبر من راتب');
await expectOk('   the old 3-argument call still works', as(db, 'admin', `SELECT decide_payroll_event(p_event_id => $1, p_approve => false, p_reason => 'قديم')`, [late.id]));

// ---------------- 2) غياب بدون بصمة (no_record) بمبلغ معدّل ----------------
await q(`SELECT sync_payroll_day($1, '2026-09-08')`, [E]);
const abs = await ev('2026-09-08', 'absence');
check('2) a day with no punch is a pending absence at the daily rate (20,000)', abs && N(abs.a) === 20000 && abs.source === 'no_record', JSON.stringify(abs));
await expectOk('   the admin deducts half a day (10,000)', as(db, 'admin', `SELECT decide_payroll_event($1, true, 'نص يوم', 10000)`, [abs.id]));
const absCustom = await ev('2026-09-08', 'absence');
check('   ...10,000 on the attendance-backed event', N(absCustom.a) === 10000 && N(absCustom.o) === 10000 && absCustom.source === 'attendance' && absCustom.status === 'approved',
  JSON.stringify(absCustom));
check('   ...total deductions = 10,000', (await deductions()) === 10000);
await q(`SELECT sync_payroll_period('2026-09', $1)`, [E]);
check('   ...and it survives a recalculation', (await deductions()) === 10000);

// ---------------- 3) غياب اليوم قبل الاحتساب (ماكو حركة بعد) ----------------
const today = (await one(`SELECT (now() AT TIME ZONE public.company_timezone())::date::text d`)).d;
await q(`SELECT ensure_payroll_period(public.payroll_month_of($1::date))`, [today]);
const rates = await as(db, 'admin', `SELECT * FROM payroll_day_rates($1::date)`, [today]);
const rate = rates.rows.find((r) => r.employee_id === E);
check('3) the day rate is known before any decision (20,000)', rate && N(rate.daily_rate) === 20000, JSON.stringify(rate));
check('   a manager sees rates for his branch only', (await as(db, 'manager', `SELECT * FROM payroll_day_rates($1::date)`, [today])).rows.length >= 1);
await expectError('   an employee cannot read rates', as(db, 'emp', `SELECT * FROM payroll_day_rates($1::date)`, [today]), '');

const isWorkday = (await one(`SELECT NOT EXISTS (SELECT 1 FROM official_holidays WHERE holiday_date = $1::date) ok`, [today])).ok;
if (isWorkday) {
  await expectOk("   the admin deducts today's absence with an edited amount", as(db, 'admin', `SELECT decide_absence_day($1, $2::date, true, 'غايب بدون خبر', 15000)`, [E, today]));
  const todayEv = await ev(today, 'absence');
  check('   ...an attendance row and an approved event at 15,000', todayEv && N(todayEv.a) === 15000 && todayEv.status === 'approved' && todayEv.source === 'attendance',
    JSON.stringify(todayEv));
  const att = await one(`SELECT status, deduction_status FROM attendance WHERE employee_id = $1 AND work_date = $2::date`, [E, today]);
  check('   ...attendance says absent / applied', att.status === 'absent' && att.deduction_status === 'applied', JSON.stringify(att));

  // ---------------- 4) «الغائبون اليوم» بلوحة التعاميم ----------------
  const board = (await as(db, 'emp', `SELECT * FROM get_absent_today()`)).rows;
  check('4) the deducted absence shows on the announcements board for everyone', board.some((r) => r.employee_id === E && r.full_name === 'موظف المبلغ'), JSON.stringify(board));
  await expectOk('   excusing it...', as(db, 'admin', `SELECT decide_absence_day($1, $2::date, false, 'طلع عنده عذر')`, [E, today]));
  check('   ...removes it from the board', !(await as(db, 'emp', `SELECT * FROM get_absent_today()`)).rows.some((r) => r.employee_id === E));
  check('   ...and nothing is deducted for today', N((await ev(today, 'absence')).o ?? 0) === 0 && (await ev(today, 'absence')).status === 'ignored');
} else {
  console.log('   (today is a holiday in the fixtures — absence-day checks skipped)');
}
await expectError('   anonymous users cannot read the board', as(db, 'anon', `SELECT * FROM get_absent_today()`), '');
await expectError('   a future day cannot be decided', as(db, 'admin', `SELECT decide_absence_day($1, ($2::date + 1), true, 'x')`, [E, today]), 'بعده ما اجه');
await expectError('   an employee cannot decide', as(db, 'emp', `SELECT decide_absence_day($1, $2::date, true, 'x')`, [E, today]), '');

// موظف بصم اليوم: ما ينحسب غياب
await q(`DELETE FROM attendance WHERE employee_id = $1 AND work_date = $2::date`, [IDS.emp, today]);
await q(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time) VALUES ($1, $2, $3::date, 'present', now())`, [IDS.emp, IDS.branch, today]);
await expectError('   someone who punched in cannot be marked absent', as(db, 'admin', `SELECT decide_absence_day($1, $2::date, true, 'x')`, [IDS.emp, today]), 'بصم بهذا اليوم');

await done();
