// السلف المسددة: سجل مالي دائم قبل حذف السلفة، شروط الأرشفة، حماية الكشف، تنظيف السلف، و«تم تسليم الرواتب».
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const E = '00000000-0000-0000-0000-0000000000b7';
const N = (v) => Number(v);

/** موظف عنده سلفة 300,000 على 3 أقساط: الأول انخصم براتب 9 (والمسير مغلق)، والباقي بعدهم. */
async function world() {
  const db = await setup();
  const q = async (sql, p = []) => (await db.query(sql, p)).rows;
  const one = async (sql, p = []) => (await q(sql, p))[0];
  await db.exec(`UPDATE employees SET join_date = '2026-01-01'`);
  await db.exec(`
    INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password)
      VALUES ('${E}', 'SL1', 'موظف السلفة', '${IDS.branch}', 600000, '2026-01-01', false);
    INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
      VALUES ('${E}', 'صباحي', '09:00', '17:00', 15, '{0,1,2,3,4,5,6}');
    UPDATE work_schedule_history SET effective_from = '-infinity';
    UPDATE system_settings SET value = value || '{"no_record_from": "2027-01-01"}' WHERE key = 'payroll_policy';
  `);
  for (const m of ['2026-09', '2026-10', '2026-11']) await q(`SELECT ensure_payroll_period($1)`, [m]);
  const loan = await one(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, status, pledge_url)
                          VALUES ($1, 300000, 100000, 3, 300000, 'pending', 'https://x.supabase.co/storage/v1/object/public/loan-pledges/e/p1.jpg') RETURNING id, loan_no`, [E]);
  await as(db, 'admin', `SELECT approve_loan($1, 300000, 3, '2026-09-10')`, [loan.id]);
  for (const r of await q(`SELECT id FROM employees WHERE is_active`)) await as(db, 'admin', `SELECT approve_payroll_slip($1, '2026-09')`, [r.id]);
  await as(db, 'admin', `SELECT close_payroll_period('2026-09')`);
  const slip = async () => JSON.stringify(await one(`SELECT id, basic_salary::numeric b, deductions::numeric d, loans_deduction::numeric l, net_salary::numeric n FROM salary_slips WHERE employee_id = $1 AND work_month = '2026-09'`, [E]));
  const money = async (m) => { const s = (await one(`SELECT payroll_employee_summary($1, $2) s`, [E, m])).s; return `${N(s.loans)}/${N(s.net)}`; };
  const payRest = () => q(`UPDATE loan_installments SET is_paid = true, paid_at = '2026-10-15 10:00:00+03', payment_type = 'cash', payment_note = 'دفع بالمكتب' WHERE loan_id = $1 AND NOT is_paid`, [loan.id]);
  return { db, q, one, slip, money, payRest, loan: loan.id, loanNo: N(loan.loan_no) };
}

// ---------------- 3) الرقم المرجعي ----------------
{
  const w = await world();
  const next = await w.one(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, status, pledge_url)
                            VALUES ($1, 50000, 50000, 1, 50000, 'pending', 'p') RETURNING loan_no`, [IDS.emp]);
  check('3) every loan gets a reference number, in order', w.loanNo >= 1 && N(next.loan_no) === w.loanNo + 1, `${w.loanNo} → ${next.loan_no}`);
  // الموظف يقدّم طلب سلفة بحسابه: الرقم يجيه من السيرفر، وما يكدر يكتب رقم من عنده ولا يغيّره
  const mine = (await as(w.db, 'emp', `INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, status, pledge_url, loan_no)
    VALUES ($1, 40000, 40000, 1, 40000, 'pending', 'p', 999999) RETURNING loan_no`, [IDS.emp2]).catch((e) => ({ rows: [{ error: e.message }] }))).rows[0];
  const own = await as(w.db, 'emp2', `INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, status, pledge_url, loan_no)
    VALUES ($1, 40000, 40000, 1, 40000, 'pending', 'p', 999999) RETURNING loan_no`, [IDS.emp2]);
  check('   an employee can request a loan and the server assigns the number (a typed number is ignored)', N(own.rows[0].loan_no) > w.loanNo + 1 && N(own.rows[0].loan_no) !== 999999 && !!mine, JSON.stringify(own.rows[0]));
  await w.q(`UPDATE loans SET loan_no = 5555 WHERE loan_no = $1`, [w.loanNo]);
  check('   the reference number never changes', (await w.one(`SELECT loan_no FROM loans WHERE id = $1`, [w.loan])).loan_no == w.loanNo);
}

// ---------------- 1+2) الأرشفة: الشروط والسجل الدائم ----------------
{
  const w = await world();
  await expectError('1) a loan with a balance cannot be archived', as(w.db, 'admin', `SELECT archive_settled_loan($1)`, [w.loan]), 'عليها باقي 200,000');
  await w.payRest();
  await expectError('   a repaid loan cannot be deleted directly (the record would be lost)', as(w.db, 'admin', `DELETE FROM loans WHERE id = $1`, [w.loan]), 'أرشفة السلفة');
  await expectError('   employees and managers cannot archive', as(w.db, 'manager', `SELECT archive_settled_loan($1)`, [w.loan]), 'غير مصرح');

  // (2) كشف خصم منها ومسيره انفتح من جديد ← تنتظر
  await as(w.db, 'admin', `SELECT reopen_payroll_period('2026-09', 'مراجعة')`);
  await expectError('2) while a payroll that deducted from it is open, it waits', as(w.db, 'admin', `SELECT archive_settled_loan($1)`, [w.loan]), 'بعده مفتوح');
  await as(w.db, 'admin', `SELECT close_payroll_period('2026-09')`);

  const slipBefore = await w.slip();
  const octBefore = await w.money('2026-10');
  const r = (await as(w.db, 'admin', `SELECT archive_settled_loan($1) r`, [w.loan])).rows[0].r;
  check('   archiving succeeds and returns the pledge file to remove', r.success === true && N(r.loan_no) === w.loanNo && String(r.pledge_url).includes('loan-pledges/e/p1.jpg'), JSON.stringify(r));
  check('   the operational loan and its installments are gone',
    (await w.one(`SELECT count(*)::int c FROM loans WHERE id = $1`, [w.loan])).c === 0 && (await w.one(`SELECT count(*)::int c FROM loan_installments WHERE loan_id = $1`, [w.loan])).c === 0);

  const s = await w.one(`SELECT * FROM settled_loans WHERE loan_id = $1`, [w.loan]);
  check('1) the permanent record: reference, employee, original amount, total deducted, zero balance, settlement date, who archived',
    N(s.loan_no) === w.loanNo && s.employee_id === E && s.employee_name === 'موظف السلفة' && s.employee_code === 'SL1'
    && N(s.amount) === 300000 && N(s.total_deducted) === 300000 && N(s.final_balance) === 0 && s.settled_at && s.archived_by === IDS.admin,
    JSON.stringify({ ...s, installments: undefined }));
  const inst = s.installments;
  const slipId = JSON.parse(slipBefore).id;
  check('   every deduction with its date, amount, method and payroll month (salary one points at its slip)',
    inst.length === 3 && inst.map((i) => i.method).join() === 'salary,cash,cash' && inst.map((i) => N(i.amount)).join() === '100000,100000,100000'
    && inst[0].payroll_month === '2026-09' && inst[0].slip_id === slipId && inst[1].slip_id === null && inst[1].note === 'دفع بالمكتب'
    && inst[1].payroll_month === '2026-10' && inst[2].payroll_month === '2026-11', JSON.stringify(inst));

  check('4) the approved slip is identical (its 100,000 deduction and "loan" line stay)',
    (await w.slip()) === slipBefore && (await w.one(`SELECT count(*)::int c FROM salary_slip_lines WHERE line_type = 'loan'`)).c === 1, await w.slip());
  check('   nothing is deducted again and the loan is no longer due', (await w.money('2026-10')) === `0/600000` && octBefore === '0/600000' && (await w.money('2026-11')) === '0/600000',
    `${octBefore} → ${await w.money('2026-10')} / ${await w.money('2026-11')}`);
  await expectError('   archiving twice is refused', as(w.db, 'admin', `SELECT archive_settled_loan($1)`, [w.loan]), 'غير موجودة');

  // الخطأ اللي انلكه بالفحص: إلغاء اعتماد كشف بيه قسط سلفة تأرشفت
  await as(w.db, 'admin', `SELECT reopen_payroll_period('2026-09', 'مراجعة ثانية')`);
  await expectError('2) a slip that carries an installment of an archived loan cannot be un-approved', as(w.db, 'admin', `SELECT revert_payroll_slip($1)`, [slipId]), 'تأرشفت');
  check('   ...the slip is still there, unchanged', (await w.slip()) === slipBefore);
  await as(w.db, 'admin', `SELECT close_payroll_period('2026-09')`);

  // الصلاحيات
  check('   another employee cannot see the record, the admin can', (await as(w.db, 'emp', `SELECT count(*)::int c FROM settled_loans`)).rows[0].c === 0
    && (await as(w.db, 'admin', `SELECT count(*)::int c FROM settled_loans`)).rows[0].c === 1);
  await expectError('   nobody can write the record directly', as(w.db, 'admin', `UPDATE settled_loans SET amount = 1`), 'permission denied');
  // حذف الموظف: السجل يبقى باسمه
  await w.q(`DELETE FROM employees WHERE id = $1`, [E]);
  const kept = await w.one(`SELECT employee_id, employee_name FROM settled_loans WHERE loan_id = $1`, [w.loan]);
  check('   the record survives deleting the employee (name kept as text)', kept && kept.employee_id === null && kept.employee_name === 'موظف السلفة', JSON.stringify(kept));
}

// ---------------- 4) تنظيف السلف من شاشة التنظيف ----------------
{
  const w = await world();
  await w.payRest();
  // سلفة ثانية عليها باقي + طلب مرفوض قديم + طلب مرفوض جديد
  const open = await w.one(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, status, pledge_url)
                            VALUES ($1, 200000, 100000, 2, 200000, 'pending', 'https://x/loan-pledges/e/p2.jpg') RETURNING id, loan_no`, [IDS.emp]);
  await as(w.db, 'admin', `SELECT approve_loan($1, 200000, 2, '2026-11-10')`, [open.id]);
  await w.q(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, status, pledge_url, created_at) VALUES
    ($1, 50000, 50000, 1, 50000, 'rejected', 'https://x/loan-pledges/e/old.jpg', now() - interval '60 days'),
    ($1, 60000, 60000, 1, 60000, 'cancelled', 'https://x/loan-pledges/e/new.jpg', now() - interval '2 days')`, [IDS.emp2]);

  const p = (await as(w.db, 'admin', `SELECT loans_cleanup_preview() r`)).rows[0].r;
  check('4) preview: the settled loan is a candidate', p.settled.length === 1 && N(p.settled[0].loan_no) === w.loanNo && p.settled[0].employee === 'موظف السلفة', JSON.stringify(p.settled));
  check('   the loan with a balance is excluded, with the reason', p.excluded.length === 1 && N(p.excluded[0].loan_no) === N(open.loan_no) && String(p.excluded[0].reason).includes('عليها باقي 200,000'), JSON.stringify(p.excluded));
  check('   old rejected requests are candidates, recent ones are kept', p.requests.length === 1 && p.requests[0].status === 'rejected' && N(p.requests_recent) === 1, JSON.stringify(p.requests));
  check('   an estimate of the space is given', N(p.bytes.settled_rows) > 0 && N(p.bytes.requests_rows) > 0 && 'settled_files' in p.bytes, JSON.stringify(p.bytes));
  await expectError('   employees cannot preview or run', as(w.db, 'emp', `SELECT loans_cleanup_preview()`), 'غير مصرح');

  const slipBefore = await w.slip();
  const r = (await as(w.db, 'admin', `SELECT loans_cleanup_run(true, true) r`)).rows[0].r;
  check('   run: 1 loan archived, 1 old request deleted, both pledge files returned for removal',
    N(r.loans_archived) === 1 && N(r.loan_requests_deleted) === 1 && r.pledge_urls.length === 2, JSON.stringify(r));
  check('   the open loan and the recent request are untouched',
    (await w.one(`SELECT count(*)::int c FROM loans`)).c === 2 && (await w.one(`SELECT count(*)::int c FROM loan_installments WHERE loan_id = $1`, [open.id])).c === 2);
  check('   the approved slip did not change', (await w.slip()) === slipBefore);
  const log = await w.one(`SELECT loans_archived, loan_requests_deleted, performed_by, attendance_deleted FROM payroll_cleanups ORDER BY performed_at DESC LIMIT 1`);
  check('   the run is logged', log.loans_archived === 1 && log.loan_requests_deleted === 1 && log.performed_by === IDS.admin && log.attendance_deleted === null, JSON.stringify(log));
  const again = (await as(w.db, 'admin', `SELECT loans_cleanup_run(true, true) r`)).rows[0].r;
  check('   running it again does nothing', N(again.loans_archived) === 0 && N(again.loan_requests_deleted) === 0 && (await w.one(`SELECT count(*)::int c FROM settled_loans`)).c === 1, JSON.stringify(again));
}

// ---------------- 9) «تم تسليم الرواتب» + 5/6) المستثنى وتقدير المساحة بمعاينة المسير ----------------
{
  const w = await world();
  await w.q(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time)
             VALUES ($1, $2, '2026-09-07', 'present', '2026-09-07 09:00:00+03', '2026-09-07 17:00:00+03')`, [E, IDS.branch]).catch(() => {});
  await expectError('9) an open payroll cannot be marked as delivered', as(w.db, 'admin', `SELECT mark_payroll_delivered('2026-10')`), 'أغلق المسير أولاً');
  await expectError('   only the admin confirms delivery', as(w.db, 'manager', `SELECT mark_payroll_delivered('2026-09')`), 'غير مصرح');
  await expectOk('   a closed payroll is marked delivered', as(w.db, 'admin', `SELECT mark_payroll_delivered('2026-09')`));
  check('   ...with who and when', (await w.one(`SELECT (delivered_at IS NOT NULL AND delivered_by = $1) ok FROM payroll_periods WHERE period_month = '2026-09'`, [IDS.admin])).ok === true);
  await as(w.db, 'admin', `SELECT reopen_payroll_period('2026-09', 'تصحيح')`);
  check('   reopening the payroll clears the delivery mark', (await w.one(`SELECT delivered_at FROM payroll_periods WHERE period_month = '2026-09'`)).delivered_at === null);
  await as(w.db, 'admin', `SELECT close_payroll_period('2026-09')`);

  await w.q(`INSERT INTO payroll_events (employee_id, event_date, event_type, minutes, days, amount, direction, payroll_month, status, source)
             VALUES ($1, '2026-09-20', 'early_leave', 30, 0, 1250, -1, '2026-10', 'pending', 'attendance')`, [E]);
  await w.q(`UPDATE payroll_periods SET status = 'closed' WHERE period_month = '2026-10'`);
  const p = (await as(w.db, 'admin', `SELECT payroll_cleanup_preview('2026-09') r`)).rows[0].r;
  check('   attendance waits for the NEXT payroll to be delivered', p.checks.next_closed === true && p.checks.next_delivered === false && p.can.attendance === false, JSON.stringify(p.checks));
  check('5) the excluded items are listed with who and why', p.pending_list.length === 1 && p.pending_list[0].employee === 'موظف السلفة' && p.pending_list[0].type === 'خروج مبكر' && p.pending_list[0].date === '2026-09-20',
    JSON.stringify(p.pending_list));
  check('6) the preview estimates the space of each category', 'attendance' in p.bytes && 'tracking' in p.bytes && 'notifications' in p.bytes, JSON.stringify(p.bytes));
  await w.q(`UPDATE payroll_events SET status = 'ignored' WHERE status = 'pending'`);
  await expectError('   the run refuses until delivery is confirmed', as(w.db, 'admin', `SELECT payroll_cleanup_run('2026-09', true, false, false)`), 'تم تسليم الرواتب');
  await as(w.db, 'admin', `SELECT mark_payroll_delivered('2026-10')`);
  const ok = (await as(w.db, 'admin', `SELECT payroll_cleanup_preview('2026-09') r`)).rows[0].r;
  check('   once delivered, the attendance of the previous payroll can be cleaned', ok.checks.next_delivered === true && ok.can.attendance === true, JSON.stringify(ok.can));
  await expectOk('   ...and the run goes through', as(w.db, 'admin', `SELECT payroll_cleanup_run('2026-09', true, false, false)`));
}

await done();
