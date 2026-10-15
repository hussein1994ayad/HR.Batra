// تدقيق 14/10/2026 — المرحلة 3 (قرارات 15/10/2026): الراتب الجزئي (مباشرة/إنهاء خدمات) بكل أطوال المسيرات،
// آخر يوم بعد يوم القطع، معاينة إنهاء الخدمات، خصومات أكثر من الراتب، فرق التقريب، وإلغاء الاعتماد يرجّع الأقساط.
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];

const today = (await one(`SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date::text d`)).d;
const curMonth = (await one(`SELECT payroll_month_of($1::date) m`, [today])).m;
const prevMonth = (await one(`SELECT payroll_month_add($1, -1) m`, [curMonth])).m;
const prev = await one(`SELECT start_date::text s, cutoff_date::text c FROM ensure_payroll_period($1)`, [prevMonth]);

const newEmp = async (code, salary = 900000, join = '2026-01-01') => {
  const id = (await one('SELECT gen_random_uuid()::text id')).id;
  await q(`INSERT INTO auth.users (id, email) VALUES ($1, $2)`, [id, `${code}@x`]);
  await q(`INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ($1, $2, $2, 'employee', $3, $4, $5, false)`, [id, code, IDS.branch, salary, join]);
  return id;
};
const period = async (m) => one(`SELECT start_date::text s, cutoff_date::text c, (cutoff_date - start_date + 1) n FROM ensure_payroll_period($1)`, [m]);
const summary = async (emp, m) => (await one(`SELECT payroll_employee_summary($1, $2) s`, [emp, m])).s;
const addDays = (d, n) => new Date(Date.parse(d + 'T00:00:00Z') + n * 86400000).toISOString().slice(0, 10);
// أيام الدوام بالجدول الافتراضي (كل الأيام عدا الجمعة) ناقص العطل الرسمية
const workdays = (from, to, holidays = []) => {
  let n = 0;
  for (let d = from; d <= to; d = addDays(d, 1)) if (new Date(d + 'T00:00:00Z').getUTCDay() !== 5 && !holidays.includes(d)) n++;
  return n;
};
const DAILY = 30000; // 900,000 ÷ 30

// ---------------- 1) المباشر بنص المسير: الراتب ناقص أجر الأيام قبل المباشرة، بكل أطوال المسيرات ----------------
// مسيرات 27→26: 2027-03 = 28 يوم، 2028-03 = 29 يوم، 2026-12 = 30 يوم، 2026-11 = 31 يوم
for (const [m, len] of [['2027-03', 28], ['2028-03', 29], ['2026-12', 30], ['2026-11', 31]]) {
  const p = await period(m);
  check(`1) period ${m} is ${len} days`, Number(p.n) === len, JSON.stringify(p));
  const e = await newEmp(`J${m}`, 900000, addDays(p.s, 3));
  const s = await summary(e, m);
  check(`   joined on day 4 of a ${len}-day period: salary minus 3 days (900,000 - 90,000 = 810,000)`,
    Number(s.basic) === 810000 && s.basic_basis === 'joined', JSON.stringify([s.basic, s.basic_basis]));
  check('   the note explains it in plain words', String(s.basic_note).includes('باشر') && String(s.basic_note).includes('3 يوم قبل المباشرة'), s.basic_note);
}
{
  const p = await period('2026-12');
  const full = await newEmp('JF', 900000, p.s);
  const s = await summary(full, '2026-12');
  check('   joined on the first day of the period: full salary', Number(s.basic) === 900000 && s.basic_basis === 'full', JSON.stringify([s.basic, s.basic_basis]));
  check('   ...with a plain note', String(s.basic_note).includes('راتب المسير كامل'), s.basic_note);
  const late = await newEmp('JL', 900000, addDays(p.c, 1));
  const s2 = await summary(late, '2026-12');
  check('   joined after the period: nothing for that period', Number(s2.basic) === 0 && s2.basic_basis === 'none', JSON.stringify([s2.basic, s2.basic_basis]));
}

// ---------------- 2) إنهاء خدمات داخل المسير: أيام الدوام بس (الجمع والعطل الرسمية ما تنحسب) ----------------
{
  const m = '2026-12';
  const p = await period(m);
  const last = addDays(p.s, 13);
  const e = await newEmp('L1');
  await q(`UPDATE employees SET is_active = false, termination_date = $2 WHERE id = $1`, [e, last]);
  let s = await summary(e, m);
  const wd = workdays(p.s, last);
  check(`2) left after 14 calendar days: paid ${wd} workdays × 30,000 = ${(wd * DAILY).toLocaleString('en-US')}`,
    Number(s.basic) === wd * DAILY && s.basic_basis === 'end_of_service' && Number(s.scheduled_days) === wd, JSON.stringify([s.basic, s.scheduled_days, wd]));
  check('   the note says how it was counted', String(s.basic_note).includes(`${wd} يوم دوام`) && String(s.basic_note).includes('الجمع والعطل الرسمية ما تنحسب'), s.basic_note);

  // عطلة رسمية بيوم دوام ضمن خدمته = يوم أقل
  let hol = p.s;
  while (new Date(hol + 'T00:00:00Z').getUTCDay() === 5) hol = addDays(hol, 1);
  await q(`INSERT INTO official_holidays (holiday_date, name) VALUES ($1, 'عطلة') ON CONFLICT DO NOTHING`, [hol]);
  s = await summary(e, m);
  check('   an official holiday inside his service is not paid as a workday', Number(s.basic) === (wd - 1) * DAILY, JSON.stringify([s.basic, wd - 1]));
  await q(`DELETE FROM official_holidays WHERE holiday_date = $1`, [hol]);

  // آخر يوم = يوم القطع: راتب كامل (خدم المسير كله)
  const e2 = await newEmp('L2');
  await q(`UPDATE employees SET is_active = false, termination_date = $2 WHERE id = $1`, [e2, p.c]);
  s = await summary(e2, m);
  check('   last day = the cutoff day: he served the whole period, full salary', Number(s.basic) === 900000 && s.basic_basis === 'full', JSON.stringify([s.basic, s.basic_basis]));

  // باشر وترك بنفس المسير: أيام الدوام من المباشرة لآخر يوم
  const e3 = await newEmp('L3', 900000, addDays(p.s, 5));
  await q(`UPDATE employees SET is_active = false, termination_date = $2 WHERE id = $1`, [e3, addDays(p.s, 15)]);
  s = await summary(e3, m);
  const wd3 = workdays(addDays(p.s, 5), addDays(p.s, 15));
  check('   joined and left inside the same period: workdays between the two', Number(s.basic) === wd3 * DAILY && s.basic_basis === 'end_of_service', JSON.stringify([s.basic, wd3]));
}

// ---------------- 3) آخر يوم بعد يوم القطع (مثلاً 28 والمسير ينتهي 26): ينحسب بالمسير اللي بعده لحد آخر يومه ----------------
{
  const p11 = await period('2026-11');
  const p12 = await period('2026-12');
  const last = addDays(p11.c, 2); // يومين بعد القطع
  const e = await newEmp('L28');
  await q(`UPDATE employees SET is_active = false, termination_date = $2 WHERE id = $1`, [e, last]);
  const s11 = await summary(e, '2026-11');
  const s12 = await summary(e, '2026-12');
  const wd = workdays(p12.s, last);
  check('3) left 2 days after the cutoff: the period he finished is full', Number(s11.basic) === 900000 && s11.basic_basis === 'full', JSON.stringify([s11.basic, s11.basic_basis]));
  check(`   ...and the next period pays the ${wd} workday(s) up to his last day`, Number(s12.basic) === wd * DAILY && s12.basic_basis === 'end_of_service',
    JSON.stringify([s12.basic, s12.basic_basis, wd]));
}

// ---------------- 4) معاينة «إنهاء خدمات»: تحسب كلشي وما تحفظ أي شي ----------------
{
  const e = await newEmp('EOS');
  const last = addDays(prev.s, 9);
  const eventsBefore = (await one(`SELECT count(*)::int c FROM payroll_events WHERE employee_id = $1`, [e])).c;
  const r = await expectOk('4) the admin previews the end of service', as(db, 'admin', `SELECT end_of_service_preview($1, $2::date) p`, [e, last]));
  const pv = r?.rows[0].p;
  const lastP = pv?.periods?.[pv.periods.length - 1];
  const wd = workdays(prev.s, last);
  check('   the last period pays only his workdays, with the explanation', lastP?.month === prevMonth && Number(lastP.summary.basic) === wd * DAILY
    && String(lastP.summary.basic_note).includes('نهاية خدمة'), JSON.stringify(lastP?.summary?.basic_note));
  check('   the total is the sum of what each open period will pay', Number(pv?.total_net) === pv?.periods.reduce((a, x) => a + Number(x.expected_net), 0),
    JSON.stringify(pv?.periods?.map((x) => [x.month, x.expected_net])));
  check('   a past last day can be approved right away', lastP?.can_approve_now === true);
  const after = await one(`SELECT termination_date, is_active FROM employees WHERE id = $1`, [e]);
  check('   nothing is saved: no last day, still active', after.termination_date === null && after.is_active === true, JSON.stringify(after));
  check('   ...and no payroll records were left behind', (await one(`SELECT count(*)::int c FROM payroll_events WHERE employee_id = $1`, [e])).c === eventsBefore);

  const future = addDays(today, 40);
  const periodsBefore = (await one(`SELECT count(*)::int c FROM payroll_periods`)).c;
  const r2 = await expectOk('   a last day in a later month works too', as(db, 'admin', `SELECT end_of_service_preview($1, $2::date) p`, [e, future]));
  check('   ...it is not approvable yet', r2?.rows[0].p.periods.every((x) => x.can_approve_now === false || x.cutoff_date < today));
  check('   ...and it created no payroll periods', (await one(`SELECT count(*)::int c FROM payroll_periods`)).c === periodsBefore);

  await expectError('   an employee cannot run it', as(db, 'emp', `SELECT end_of_service_preview($1, $2::date)`, [e, last]));
  await expectError('   a branch manager cannot run it', as(db, 'manager', `SELECT end_of_service_preview($1, $2::date)`, [e, last]));
  await expectError('   a last day before joining is refused', as(db, 'admin', `SELECT end_of_service_preview($1, '2025-01-01'::date)`, [e]), 'بعد تاريخ المباشرة');
}

// ---------------- 5) خصومات أكثر من الراتب: الكشف ينعتمد بصافي صفر والزايد سطر «خارج النظام» ----------------
const loanWith = async (emp, rows) => {
  const total = rows.reduce((s, r) => s + r[1], 0);
  const id = (await one(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
    VALUES ($1, $2, $3, $4, $2, 'p.png', 'approved') RETURNING id`, [emp, total, rows[0][1], rows.length])).id;
  await q(`SELECT set_config('loans.skip_rebalance', 'on', false)`);
  for (const [due, amount] of rows) await q(`INSERT INTO loan_installments (loan_id, due_date, amount, is_paid) VALUES ($1, $2, $3, false)`, [id, due, amount]);
  await q(`SELECT set_config('loans.skip_rebalance', 'off', false)`);
  return id;
};
const inst = async (loan) => q(`SELECT id, due_date::text d, amount::int a, is_paid p, amount_locked l, origin_kind k, payment_note n
  FROM loan_installments WHERE loan_id = $1 ORDER BY due_date, id`, [loan]);
const loanRow = async (loan) => one(`SELECT remaining_amount::int r FROM loans WHERE id = $1`, [loan]);
const slipOf = async (emp, m) => one(`SELECT id, basic_salary::int b, allowances::int a, deductions::int d, loans_deduction::int l, net_salary::int n
  FROM salary_slips WHERE employee_id = $1 AND work_month = $2`, [emp, m]);
const linesOf = async (slip) => q(`SELECT line_type t, amount::numeric a, direction::int dir, notes FROM salary_slip_lines WHERE salary_slip_id = $1`, [slip]);
const later = (k) => addDays(prev.c, 31 * k);

{
  const e = await newEmp('X1', 600000);
  const loan = await loanWith(e, [[prev.c, 100000], [later(1), 100000], [later(2), 100000]]);
  const before = JSON.stringify(await inst(loan));
  const r = await expectOk('5) deductions bigger than the salary no longer block the approval', as(db, 'admin',
    `SELECT approve_payroll_slip($1, $2, $3::jsonb) r`, [e, prevMonth, JSON.stringify([{ type: 'deduction', amount: 700000, reason: 'ضرر' }])]));
  const slip = await slipOf(e, prevMonth);
  check('   the slip is approved with net 0 (the month can close)', slip?.n === 0, JSON.stringify(slip));
  check('   only what the salary covers is deducted (600,000), the loan installment is not taken', slip?.d === 600000 && slip?.l === 0, JSON.stringify(slip));
  const lines = await linesOf(slip.id);
  const ex = lines.find((l) => l.t === 'excess_deduction');
  check('   a line says 100,000 of deductions were not taken and are settled outside the system',
    ex && Number(ex.a) === 100000 && ex.dir === 1 && String(ex.notes).includes('خارج النظام'), JSON.stringify(lines));
  const sch = await inst(loan);
  check('   the installment moved to the end of the loan', sch.find((x) => x.d === prev.c) === undefined && sch.some((x) => x.k === 'postponed'), JSON.stringify(sch));

  await expectOk('   reverting the slip', as(db, 'admin', `SELECT revert_payroll_slip($1)`, [slip.id]));
  check('   (PAY-010) the loan schedule is exactly as before the approval', JSON.stringify(await inst(loan)) === before, JSON.stringify(await inst(loan)));
  check('   ...and the loan balance is whole again', (await loanRow(loan)).r === 300000);
  check('   the approval deduction is removed with the slip',
    (await one(`SELECT count(*)::int c FROM payroll_events WHERE employee_id = $1 AND source = 'approval'`, [e])).c === 0);
}

// ---------------- 6) قسط ينقص لأن الراتب ما يكفي، وإلغاء الاعتماد يرجّعه ----------------
{
  const e = await newEmp('X2', 600000);
  const loan = await loanWith(e, [[prev.c, 100000], [later(1), 100000]]);
  const before = JSON.stringify(await inst(loan));
  await expectOk('6) salary covers only half of the installment', as(db, 'admin',
    `SELECT approve_payroll_slip($1, $2, $3::jsonb)`, [e, prevMonth, JSON.stringify([{ type: 'deduction', amount: 550000, reason: 'ضرر' }])]));
  const slip = await slipOf(e, prevMonth);
  check('   50,000 of the installment is deducted, net 0', slip?.l === 50000 && slip?.n === 0, JSON.stringify(slip));
  const sch = await inst(loan);
  check('   the other 50,000 became a new month at the end', sch.length === 3 && sch[2].a === 50000 && sch[2].k === 'shortfall', JSON.stringify(sch));
  await expectOk('   reverting the slip', as(db, 'admin', `SELECT revert_payroll_slip($1)`, [slip.id]));
  check('   (PAY-010) the installment is back to 100,000 and the extra month is gone', JSON.stringify(await inst(loan)) === before, JSON.stringify(await inst(loan)));
  check('   ...balance 200,000', (await loanRow(loan)).r === 200000);

  // الجدول تغيّر بعد الاعتماد (قسط انسدد يدوياً): الإلغاء ما يرجّع النسخة القديمة، والمجموع يبقى صحيح
  await expectOk('   approved again', as(db, 'admin',
    `SELECT approve_payroll_slip($1, $2, $3::jsonb)`, [e, prevMonth, JSON.stringify([{ type: 'deduction', amount: 550000, reason: 'ضرر' }])]));
  const slip2 = await slipOf(e, prevMonth);
  const next = (await inst(loan)).find((x) => !x.p && x.d === later(1));
  await q(`UPDATE loan_installments SET is_paid = true, paid_at = now(), payment_type = 'cash' WHERE id = $1`, [next.id]);
  await expectOk('   an installment is paid by hand, then the slip is reverted', as(db, 'admin', `SELECT revert_payroll_slip($1)`, [slip2.id]));
  const after = await inst(loan);
  const unpaid = after.filter((x) => !x.p).reduce((a, x) => a + x.a, 0);
  check('   the current schedule is kept and still adds up to the balance', unpaid === (await loanRow(loan)).r && (await loanRow(loan)).r === 100000,
    JSON.stringify([after, await loanRow(loan)]));
}

// ---------------- 7) (PAY-011) سطور الكشف بالدينار + فرق التقريب ----------------
{
  const e = await newEmp('R1', 1000000);
  for (let i = 0; i < 3; i++) {
    await q(`INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, status, source, notes)
      VALUES ($1, $2, 'manual_deduction', 1234.4, -1, $3, 'approved', 'manual', 'خصم')`, [e, addDays(prev.s, i), prevMonth]);
  }
  await q(`INSERT INTO payroll_events (employee_id, event_date, event_type, amount, direction, payroll_month, status, source, notes)
    VALUES ($1, $2, 'bonus', 1000.6, 1, $3, 'approved', 'manual', 'مكافأة')`, [e, prev.s, prevMonth]);
  await expectOk('7) approving a slip with fractional amounts', as(db, 'admin', `SELECT approve_payroll_slip($1, $2)`, [e, prevMonth]));
  const slip = await slipOf(e, prevMonth);
  const lines = await linesOf(slip.id);
  check('   every line is in whole dinars', lines.every((l) => Number(l.a) === Math.round(Number(l.a))), JSON.stringify(lines));
  const plus = lines.filter((l) => l.dir === 1).reduce((a, l) => a + Number(l.a), 0);
  const minus = lines.filter((l) => l.dir === -1).reduce((a, l) => a + Number(l.a), 0);
  check('   the lines add up exactly to the slip (3,703 deducted, not 3,702)', slip.d === 3703 && plus - minus === slip.a - slip.d,
    JSON.stringify([slip, plus, minus]));
  check('   with a «فرق تقريب» line', lines.some((l) => l.t === 'rounding' && Number(l.a) === 1), JSON.stringify(lines));
  check('   net = salary + bonus - deductions', slip.n === 1000000 + 1001 - 3703, JSON.stringify(slip));
}

// ---------------- 8) PAY-008 (قرار: بدون تغيير) — راتب كامل بدون بصمات ما دام الأدمن ما غيّبه ----------------
{
  const e = await newEmp('N1');
  const s = await summary(e, prevMonth);
  check('8) no punches and no absence decided by the admin: full salary', Number(s.basic) === 900000 && Number(s.deductions) === 0, JSON.stringify([s.basic, s.deductions]));
}

done();
