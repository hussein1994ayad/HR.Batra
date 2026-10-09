import fs from 'node:fs';
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();

const request = async (employee, amount = 1000000, months = 4) =>
  (await as(db, employee, `INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
    VALUES ($1, $2, $4, $3, $2, 'pledge.png', 'pending') RETURNING id`, [IDS[employee], amount, months, Math.floor(amount / months)])).rows[0].id;
const approve = (who, id, amount, months, firstDue = '2026-01-31') =>
  as(db, who, `SELECT approve_loan($1, $2, $3, $4::date)`, [id, amount, months, firstDue]);
const installments = async (id) =>
  (await db.query(`SELECT to_char(due_date, 'YYYY-MM-DD') d, amount::int a FROM loan_installments WHERE loan_id=$1 ORDER BY due_date`, [id])).rows;

const loan = await request('emp');
const adminNotif = await db.query(`SELECT body FROM notifications WHERE employee_id=$1 AND type='loan'`, [IDS.admin]);
check('a new loan request inserts and notifies admins with the installment count',
  adminNotif.rows.some((r) => r.body.includes('على 4 قسط')), JSON.stringify(adminNotif.rows));

await expectError('employee cannot approve a loan', approve('emp', loan, 1000000, 3), 'غير مصرح');
await expectError('manager cannot approve a loan', approve('manager', loan, 1000000, 3), 'غير مصرح');
await expectError('zero months is rejected', approve('admin', loan, 1000000, 0), 'أكبر من الصفر');

await expectOk('admin approves with edited months', approve('admin', loan, 1000000, 3));
const row = (await db.query(`SELECT status, installment_count, installment_amount::int ia, remaining_amount::int ra, approved_by FROM loans WHERE id=$1`, [loan])).rows[0];
check('loan row is fully updated',
  row.status === 'approved' && row.installment_count === 3 && row.ia === 333333 && row.ra === 1000000 && row.approved_by === IDS.admin,
  JSON.stringify(row));

const inst = await installments(loan);
check('installments sum to the loan amount exactly', inst.reduce((s, r) => s + r.a, 0) === 1000000, JSON.stringify(inst));
check('last installment absorbs the rounding', inst.map((r) => r.a).join() === '333333,333333,333334');
check('due dates clamp to month end', inst.map((r) => r.d).join() === '2026-01-31,2026-02-28,2026-03-31', JSON.stringify(inst));

await expectError('a processed request cannot be approved twice', approve('admin', loan, 1000000, 3), 'مسبقاً');

// طلب ثاني وعنده سلفة جارية: يُرفض من وقت الطلب (قبل: كان يُقبل ويفشل بس عند الاعتماد)
await expectError('employee with an unpaid loan cannot request another', request('emp', 300000, 3), 'سلفة جارية');

await db.exec(`UPDATE loans SET remaining_amount = 0 WHERE id = '${loan}'`);
const second = await request('emp', 300000, 3);
await expectOk('a fully paid loan no longer blocks a new one', approve('admin', second, 300000, 3, '2026-05-15'));

const notif = await db.query(`SELECT 1 FROM notifications WHERE employee_id=$1 AND type='loan'`, [IDS.emp]);
check('approval still notifies the employee (existing trigger)', notif.rows.length > 0);

// ---------------- create_direct_loan ----------------
const direct = (who, amount = 600000, months = 3, pledge = 'p.png', emp = IDS.emp2) => as(db, who,
  `SELECT create_direct_loan($1, $2, $3, '2026-10-10'::date, $4, 'سلفة زواج') AS id`, [emp, amount, months, pledge]);

await expectError('employee cannot create a direct loan', direct('emp'), 'غير مصرح');
await expectError('direct loan requires a pledge photo', direct('admin', 600000, 3, ''), 'التعهد');
const created = await expectOk('admin creates a direct loan', direct('admin'));
const directId = created?.rows[0].id;
const dl = (await db.query(`SELECT status, notes, installment_amount::int ia, approved_by FROM loans WHERE id=$1`, [directId])).rows[0];
check('direct loan is approved with notes', dl?.status === 'approved' && dl?.notes === 'سلفة زواج' && dl?.ia === 200000 && dl?.approved_by === IDS.admin, JSON.stringify(dl));
check('direct loan has its installments', (await installments(directId)).map((r) => r.d).join() === '2026-10-10,2026-11-10,2026-12-10');
const empNotif = await db.query(`SELECT 1 FROM notifications WHERE employee_id=$1 AND title LIKE 'تم منحك سلفة%'`, [IDS.emp2]);
check('employee is notified of the direct loan', empNotif.rows.length === 1);
const adminNotif2 = await db.query(`SELECT 1 FROM notifications WHERE employee_id=$1 AND body LIKE '%موظف ثاني%'`, [IDS.admin]);
check('no "new request" alert for a direct loan', adminNotif2.rows.length === 0);
await expectError('second direct loan while one is active is rejected', direct('admin'), 'سلفة نشطة');
await expectError('clients cannot call the internal helpers',
  as(db, 'admin', `SELECT _insert_loan_installments($1, 100, 1, current_date)`, [directId]), 'permission denied');

// ---------------- pay_loan_installment (سداد بمبلغ مرن) ----------------
const flex = (await expectOk('admin creates a 500k / 5 month loan', direct('admin', 500000, 5, 'p.png', IDS.manager))).rows[0].id;
const unpaid = async () =>
  (await db.query(`SELECT id, amount::int a FROM loan_installments WHERE loan_id=$1 AND NOT is_paid ORDER BY due_date`, [flex])).rows;
const nextId = async () => (await unpaid())[0].id;
const pay = (who, id, amount, method = 'cash') =>
  as(db, who, `SELECT pay_loan_installment($1, $2, $3, 'وصل 1') AS r`, [id, amount, method]);
const amounts = async () => (await installments(flex)).map((r) => r.a / 1000).join();
const remaining = async () => (await db.query('SELECT remaining_amount::int r FROM loans WHERE id=$1', [flex])).rows[0].r;

await expectError('employee cannot record a payment', pay('manager', await nextId(), 100000), 'غير مصرح');
await expectOk('month 1 pays the planned 100k', pay('admin', await nextId(), 100000, 'salary_deduction'));
await expectOk('month 2 pays 150k instead of 100k', pay('admin', await nextId(), 150000));
check('overpayment shrinks the last installment', (await amounts()) === '100,150,100,100,50', await amounts());
check('remaining is 250k', (await remaining()) === 250000, String(await remaining()));
await expectOk('month 3 pays only 50k', pay('admin', await nextId(), 50000));
check('underpayment refills the next months up to the monthly installment',(await amounts()) === '100,150,50,100,100', await amounts());
await expectError('paying more than the remaining is rejected', pay('admin', await nextId(), 999999), 'أكبر من المتبقي');
await expectError('zero payment is rejected', pay('admin', await nextId(), 0), 'أكبر من الصفر');
await expectOk('month 4 pays 150k', pay('admin', await nextId(), 150000));
check('the last installment shrinks to 50k', (await amounts()) === '100,150,50,150,50', await amounts());
await expectOk('last month pays only 20k', pay('admin', await nextId(), 20000));
const tail = await installments(flex);
check('a new month is added with the 30k difference',
  tail.length === 6 && tail[5].a === 30000 && tail[5].d === '2027-03-10', JSON.stringify(tail));
await expectOk('the extra month is paid in full', pay('admin', await nextId(), 30000));
check('loan is fully repaid', (await remaining()) === 0 && (await unpaid()).length === 0);
const firstPaid = (await db.query(
  `SELECT payment_type, payment_note FROM loan_installments WHERE loan_id=$1 ORDER BY due_date LIMIT 1`, [flex])).rows[0];
check('payment method and note are stored',
  firstPaid.payment_type === 'salary_deduction' && firstPaid.payment_note === 'وصل 1', JSON.stringify(firstPaid));
const payNotifs = await db.query(`SELECT 1 FROM notifications WHERE employee_id=$1 AND title LIKE 'تسجيل دفعة%'`, [IDS.manager]);
check('employee is notified of each payment', payNotifs.rows.length === 6, String(payNotifs.rows.length));
await expectError('anon cannot record a payment', pay('anon', tail[0].id ?? IDS.branch, 1), 'permission denied');

// الأدمن يقدر يعطي قسط أكثر من نص الراتب (الموظف يسدد الباقي نقداً)
await db.query(`UPDATE employees SET monthly_salary_iqd=600000 WHERE id=$1`, [IDS.admin]);
const big = await expectOk("admin may approve an installment above half the salary",
  db.query(`SELECT public._validate_loan_terms($1::uuid, 900000::numeric, 1::int, DATE '2026-10-10', NULL::uuid)::int AS v`, [IDS.admin]));
check("over-half installment is returned, not refused", big?.rows[0].v === 900000, JSON.stringify(big?.rows));

// ---------------- أقساط ذكية: النقص شهر جديد، مبلغ شهر مخفّض، التأجيل، تعديل بالقسط الشهري ----------------
const newEmp = async (code) => {
  const id = (await db.query('SELECT gen_random_uuid()::text id')).rows[0].id;
  await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, $2)`, [id, `${code}@x`]);
  await db.query(`INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, must_change_password)
    VALUES ($1, $2, $2, 'employee', $3, 1000000, false)`, [id, code, IDS.branch]);
  return id;
};
const rows = async (id) => (await db.query(
  `SELECT id, to_char(due_date, 'YYYY-MM-DD') d, amount::int a, is_paid p, amount_locked l, origin_kind k, to_char(origin_month, 'YYYY-MM-DD') o
   FROM loan_installments WHERE loan_id=$1 ORDER BY due_date, id`, [id])).rows;
const amountsOf = async (id) => (await rows(id)).map((r) => r.a / 1000).join();
const loanFor = async (code, amount = 300000, months = 3) =>
  (await direct('admin', amount, months, 'p.png', await newEmp(code))).rows[0].id;

const short = await loanFor('S1');
await expectOk('first month pays only 40k (cash)', pay('admin', (await rows(short))[0].id, 40000));
const sr = await rows(short);
check('the 60k shortfall becomes a new last month, the others stay at the monthly installment',
  (await amountsOf(short)) === '40,100,100,60' && sr[3].d === '2027-01-10' && sr[3].k === 'shortfall' && sr[3].o === '2026-10-10',
  JSON.stringify(sr));

const month = await loanFor('S2');
const m0 = (await rows(month))[0].id;
const setMonth = (who, id, amount, note = 'ما يكدر هالشهر') => as(db, who, 'SELECT set_month_installment($1, $2, $3) r', [id, amount, note]);
await expectError('employees cannot change a month amount', setMonth('emp', m0, 40000), 'غير مصرح');
await expectError('the month amount must be below the installment', setMonth('admin', m0, 100000), 'أقل من قسط الشهر');
await expectError('zero is not a month amount (postpone instead)', setMonth('admin', m0, 0), 'التأجيل');
await expectOk('admin: this month he can only pay 40k', setMonth('admin', m0, 40000));
const mr = await rows(month);
check('the month stays unpaid at 40k (payroll deducts it) and is locked',
  mr[0].a === 40000 && !mr[0].p && mr[0].l === true, JSON.stringify(mr[0]));
check('the 60k goes to a new last month marked as the rest of that month',
  (await amountsOf(month)) === '40,100,100,60' && mr[3].k === 'shortfall' && mr[3].o === mr[0].d, JSON.stringify(mr));
const monthNote = await db.query(`SELECT body FROM notifications WHERE title LIKE 'تعديل قسط السلفة%' ORDER BY created_at DESC LIMIT 1`);
check('employee is told which month changed and where the rest went',
  monthNote.rows[0]?.body.includes('40,000') && monthNote.rows[0]?.body.includes('01/2027'), JSON.stringify(monthNote.rows));
await expectOk('payroll pays the reduced month', db.query(`UPDATE loan_installments SET is_paid = true, paid_at = now() WHERE id = $1`, [m0]));
check('paying the reduced month keeps the plan (no extra month)', (await amountsOf(month)) === '40,100,100,60', await amountsOf(month));

const post = await loanFor('S3');
const [p0, p1] = await rows(post);
const postpone = (who, id, note = 'طلب تأجيل') => as(db, who, 'SELECT postpone_loan_installment($1, $2) r', [id, note]);
await expectError('employees cannot postpone', postpone('emp', p1.id), 'غير مصرح');
await expectOk('admin postpones the 2nd month', postpone('admin', p1.id));
const pr = await rows(post);
check('only that month moves to the end, marked postponed with its original month',
  pr.map((r) => r.d).join() === '2026-10-10,2026-12-10,2027-01-10' && pr[2].id === p1.id && pr[2].k === 'postponed' && pr[2].o === p1.d
    && (await amountsOf(post)) === '100,100,100', JSON.stringify(pr));
await expectOk('first month is paid', pay('admin', p0.id, 100000));
await expectError('a paid month cannot be postponed', postpone('admin', p0.id), 'مسدد');
const postNote = await db.query(`SELECT body FROM notifications WHERE title LIKE 'تأجيل قسط%' ORDER BY created_at DESC LIMIT 1`);
check('employee is told about the postponement',
  postNote.rows[0]?.body.includes('11/2026') && postNote.rows[0]?.body.includes('01/2027'), JSON.stringify(postNote.rows));

// تعديل السلفة: القسط الشهري بالضبط، يبدي من شهر الرواتب المفتوح (إذا كشفه ما صادر)
const today = (await db.query(`SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date::text d`)).rows[0].d;
const thisMonth = today.slice(0, 7);
await db.query(`DELETE FROM payroll_periods WHERE $1::date BETWEEN start_date AND cutoff_date AND period_month <> $2`, [today, thisMonth]);
// مثل الفترات الحقيقية: تبدي قبل أول الشهر بأيام (27 من الشهر السابق)
await db.query(`INSERT INTO payroll_periods (period_month, start_date, cutoff_date, payment_date)
  VALUES ($1, LEAST($2::date, ($1 || '-01')::date) - 4, $2::date + 5, $2::date + 6)
  ON CONFLICT (period_month) DO UPDATE SET start_date = EXCLUDED.start_date, cutoff_date = EXCLUDED.cutoff_date, status = 'open'`, [thisMonth, today]);
const resched = await loanFor('S4', 1000000, 4);
const r0 = (await rows(resched))[0];
await expectOk('first installment paid', pay('admin', r0.id, 250000));
await expectOk('admin edits the monthly installment to 300k', as(db, 'admin', 'SELECT reschedule_loan($1, 1000000, 300000, 99) r', [resched]));
const rr = (await rows(resched)).filter((r) => !r.p);
check('rescheduled at exactly 300k a month, the last takes the rest (no even split)',
  rr.map((r) => r.a / 1000).join() === '300,300,150', JSON.stringify(rr));
check('starts from the open payroll month (no month is skipped)', rr[0].d === thisMonth + '-01', JSON.stringify(rr[0]));
const rl = (await db.query('SELECT installment_count c, installment_amount::int ia FROM loans WHERE id=$1', [resched])).rows[0];
check('installment count is computed', rl.c === 4 && rl.ia === 300000, JSON.stringify(rl));
const owner = (await db.query('SELECT employee_id e FROM loans WHERE id=$1', [resched])).rows[0].e;
await db.query(`INSERT INTO salary_slips (employee_id, work_month, basic_salary, net_salary, status) VALUES ($1, $2, 1000000, 1000000, 'published')`,
  [owner, thisMonth]);
await expectOk('edit again after this month salary was issued', as(db, 'admin', 'SELECT reschedule_loan($1, 1000000, 300000, 99) r', [resched]));
const rr2 = (await rows(resched)).filter((r) => !r.p);
check('then it starts from next month', rr2[0].d > thisMonth + '-31', JSON.stringify(rr2[0]));
const settledRow = (await db.query(`INSERT INTO loan_installments (loan_id, due_date, amount) VALUES ($1, $2::date, 5000) RETURNING id`,
  [resched, today])).rows[0].id;
await expectError('a month whose salary is issued cannot be reduced', setMonth('admin', settledRow, 1000), 'صادر');

// تصليح السلفة الحية 632f0aaf… (نفس شكل جدولها) ثم إعادة تشغيل الـ migration: يتصلح مرة وحدة بس
const BAD = '632f0aaf-fade-45a1-a60f-ad79e3c31df1';
const badEmp = await newEmp('S5');
await db.query(`SELECT set_config('loans.skip_rebalance', 'on', false)`);
await db.query(`INSERT INTO loans (id, employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
  VALUES ($1, $2, 10000000, 700000, 15, 9233333, 'p.png', 'approved')`, [BAD, badEmp]);
await db.query(`INSERT INTO loan_installments (loan_id, due_date, amount, is_paid, paid_at, payment_type) VALUES
  ($1, '2026-09-01', 666667, true, now(), 'salary_deduction'), ($1, '2026-11-01', 100000, true, now(), 'salary_deduction')`, [BAD]);
for (let i = 0; i < 13; i++) {
  await db.query(`INSERT INTO loan_installments (loan_id, due_date, amount) VALUES ($1, ('2026-11-01'::date + make_interval(months => $2::int))::date, $3)`,
    [BAD, i, i === 12 ? 710261 : 710256]);
}
await db.query(`SELECT set_config('loans.skip_rebalance', 'off', false)`);
const migration = fs.readFileSync(new URL('../migrations/20261009000000_smart_loan_installments.sql', import.meta.url), 'utf8');
await expectOk('the repair runs', db.exec(migration));
const fixed = await rows(BAD);
const fixedLoan = (await db.query('SELECT remaining_amount::int r, installment_count c FROM loans WHERE id=$1', [BAD])).rows[0];
check('October is back: 100k unpaid and locked, so the October payroll deducts it',
  fixed[1].d === '2026-10-01' && fixed[1].a === 100000 && !fixed[1].p && fixed[1].l === true, JSON.stringify(fixed[1]));
check('then 700k a month from 11/2026 to 11/2027',
  fixed.slice(2, 15).every((r) => r.a === 700000 && !r.p) && fixed[2].d === '2026-11-01' && fixed[14].d === '2027-11-01',
  JSON.stringify(fixed.slice(2)));
check('last month 12/2027 is the 133,333 rest of October',
  fixed.length === 16 && fixed[15].a === 133333 && fixed[15].d === '2027-12-01' && fixed[15].k === 'shortfall' && fixed[15].o === '2026-10-01',
  JSON.stringify(fixed[15]));
check('remaining 9,333,333 and 16 installments', fixedLoan.r === 9333333 && fixedLoan.c === 16, JSON.stringify(fixedLoan));
await db.exec(migration);
check('running it again changes nothing', JSON.stringify(await rows(BAD)) === JSON.stringify(fixed));

done();
