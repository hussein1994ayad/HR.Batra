// تنظيف آمن: حذف الحضور القديم ما يغيّر أي راتب، الأيام المنظّفة ما ينعاد حسابها، «تنظيف مسير» بشروطه وسجله،
// السلفة ما تنحذف وعليها باقي، وسجلات النظام تنظف.
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const E = '00000000-0000-0000-0000-0000000000a9';
const N = (v) => Number(v);

/** موظف انخصم منه تأخير (2,500) وغياب (20,000) براتب 9، وعنده سلفة 300,000 انخصم أول قسط منها، والمسير مغلق. */
async function world() {
  const db = await setup();
  const q = async (sql, p = []) => (await db.query(sql, p)).rows;
  const one = async (sql, p = []) => (await q(sql, p))[0];
  await db.exec(`UPDATE employees SET join_date = '2026-01-01'`);
  await db.exec(`
    INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password)
      VALUES ('${E}', 'SC1', 'موظف التنظيف', '${IDS.branch}', 600000, '2026-01-01', false);
    INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
      VALUES ('${E}', 'صباحي', '09:00', '17:00', 15, '{0,1,2,3,4,5,6}');
    UPDATE work_schedule_history SET effective_from = '-infinity';
    UPDATE system_settings SET value = value || '{"no_record_from": "2027-01-01"}' WHERE key = 'payroll_policy';
  `);
  for (const m of ['2026-09', '2026-10', '2026-11']) await q(`SELECT ensure_payroll_period($1)`, [m]);
  await q(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time)
           VALUES ($1, $2, '2026-09-07', 'late', '2026-09-07 10:00:00+03', '2026-09-07 17:00:00+03')`, [E, IDS.branch]);
  const late = await one(`SELECT id FROM payroll_events WHERE employee_id = $1 AND event_type = 'late' AND status <> 'void'`, [E]);
  await as(db, 'admin', `SELECT decide_payroll_event($1, true, 'تأخير')`, [late.id]);
  await as(db, 'admin', `SELECT decide_absence_day($1, '2026-09-08', true, 'غياب')`, [E]);
  await q(`INSERT INTO location_tracking (employee_id, latitude, longitude, "timestamp") VALUES ($1, 33.3, 44.4, '2026-09-07 11:00:00+03'), ($1, 33.3, 44.4, '2026-10-05 11:00:00+03')`, [E]);
  await q(`INSERT INTO notifications (employee_id, title, body, type, created_at) VALUES ($1, 'x', 'قديم', 'system', '2026-09-10 10:00:00+03'), ($1, 'y', 'جديد', 'system', '2026-10-10 10:00:00+03')`, [E]);
  const loan = await one(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, status, pledge_url)
                          VALUES ($1, 300000, 100000, 3, 300000, 'pending', 'pledge.jpg') RETURNING id`, [E]);
  await as(db, 'admin', `SELECT approve_loan($1, 300000, 3, '2026-09-10')`, [loan.id]);
  for (const r of await q(`SELECT id FROM employees WHERE is_active`)) await as(db, 'admin', `SELECT approve_payroll_slip($1, '2026-09')`, [r.id]);
  await as(db, 'admin', `SELECT close_payroll_period('2026-09')`);
  const slip = async () => JSON.stringify(await one(`SELECT basic_salary::numeric b, deductions::numeric d, loans_deduction::numeric l, net_salary::numeric n FROM salary_slips WHERE employee_id = $1 AND work_month = '2026-09'`, [E]));
  const summary = async (m) => (await one(`SELECT payroll_employee_summary($1, $2) s`, [E, m])).s;
  const money = async (m) => { const s = await summary(m); return `${N(s.earnings)}/${N(s.deductions)}/${N(s.loans)}/${N(s.net)}`; };
  const attendance = async () => (await one(`SELECT count(*)::int c FROM attendance WHERE work_date BETWEEN '2026-09-01' AND '2026-09-26'`)).c;
  return { db, q, one, slip, money, attendance, loan: loan.id };
}

// ---------------- 1) «تنظيف بيانات شهر» ما يرجّع الخصومات ----------------
{
  const w = await world();
  await w.q(`UPDATE payroll_periods SET status = 'closed' WHERE period_month = '2026-10'`);
  const slipBefore = await w.slip();
  const novBefore = await w.money('2026-11');
  const r = (await as(w.db, 'admin', `SELECT * FROM manual_purge_month_data(2026, 9, false, false, true)`)).rows[0];
  check('1) purging a closed month deletes its attendance rows', N(r.absences_deleted) === 2 && (await w.attendance()) === 0, JSON.stringify(r));
  check('   the approved slip is untouched', (await w.slip()) === slipBefore, await w.slip());
  check('   NO refund appears in the next open payroll (was +22,500)', (await w.money('2026-11')) === novBefore, `${novBefore} → ${await w.money('2026-11')}`);
  check('   no adjustment events were created', (await w.one(`SELECT count(*)::int c FROM payroll_events WHERE event_type = 'adjustment' AND status <> 'void'`)).c === 0);
  const log = await w.one(`SELECT period_month, attendance_deleted, tracking_deleted, performed_by FROM payroll_cleanups`);
  check('   the purge is logged (who, what, how many)', log && log.period_month === null && log.attendance_deleted === 2 && log.tracking_deleted === null && log.performed_by === IDS.admin, JSON.stringify(log));
  // (2) يوم منظّف ما ينعاد حسابه
  await w.q(`SELECT sync_payroll_day($1, '2026-09-07')`, [E]);
  await w.q(`SELECT sync_payroll_day($1, '2026-09-08')`, [E]);
  await w.q(`INSERT INTO official_holidays (holiday_date, name) VALUES ('2026-09-08', 'عطلة بتاريخ قديم')`).catch(() => {});
  check('2) recalculating a cleaned day changes nothing (was a refund)', (await w.money('2026-11')) === novBefore && (await w.slip()) === slipBefore, await w.money('2026-11'));
}

// ---------------- 1ب) حركات تنتظر قرار تمنع حذف الحضور ----------------
{
  const w = await world();
  await w.q(`UPDATE payroll_periods SET status = 'closed' WHERE period_month = '2026-10'`);
  await w.q(`INSERT INTO payroll_events (employee_id, event_date, event_type, minutes, days, amount, direction, payroll_month, status, source)
             VALUES ($1, '2026-09-20', 'early_leave', 30, 0, 1250, -1, '2026-11', 'pending', 'attendance')`, [E]);
  await expectError('1b) a month with a decision still pending cannot be purged', as(w.db, 'admin', `SELECT * FROM manual_purge_month_data(2026, 9, false, false, true)`), 'تنتظر قرارك');
  check('    ...and nothing was deleted', (await w.attendance()) === 2);
}

// ---------------- 2ب) بعد الأرشفة الرسمية ----------------
{
  const w = await world();
  await w.q(`UPDATE loan_installments SET is_paid = true, paid_at = now(), payment_type = 'cash' WHERE loan_id = $1 AND NOT is_paid AND due_date <= '2026-09-26'`, [w.loan]);
  await w.q(`UPDATE salary_slips SET created_at = now() - interval '70 days' WHERE work_month = '2026-09'`);
  const octBefore = await w.money('2026-10');
  const arch = (await as(w.db, 'admin', `SELECT safe_archive_payroll_month('2026-09') r`)).rows[0].r;
  await w.q(`SELECT sync_payroll_day($1, '2026-09-07')`, [E]);
  await w.q(`SELECT sync_payroll_day($1, '2026-09-08')`, [E]);
  check('2b) after the official archive, recalculating an old day does not refund either', arch.success === true && (await w.money('2026-10')) === octBefore, `${octBefore} → ${await w.money('2026-10')}`);
}

// ---------------- 7) تنظيف مسير: الشروط، المعاينة، التنفيذ، السجل ----------------
{
  const w = await world();
  const preview = async (m) => (await as(w.db, 'admin', `SELECT payroll_cleanup_preview($1) r`, [m])).rows[0].r;
  const run = (m, a, t, n) => as(w.db, 'admin', `SELECT payroll_cleanup_run($1, $2, $3, $4) r`, [m, a, t, n]);

  await expectError('7) an open payroll cannot be cleaned', run('2026-10', false, true, false), 'بعده مفتوح');
  await expectError('   employees and managers cannot preview or clean', as(w.db, 'manager', `SELECT payroll_cleanup_preview('2026-09')`), 'غير مصرح');
  await expectError('   ...', as(w.db, 'emp', `SELECT payroll_cleanup_run('2026-09', true, true, true)`), 'غير مصرح');

  const p1 = await preview('2026-09');
  check('   preview counts the candidates before anything is deleted',
    N(p1.counts.attendance) === 2 && N(p1.counts.tracking) === 1 && N(p1.counts.notifications) >= 1 && p1.start_date === '2026-09-01' && p1.end_date === '2026-09-26', JSON.stringify(p1.counts));
  check('   closed but the following payroll is still open: attendance not yet, tracking and notifications yes',
    p1.checks.closed === true && p1.checks.next_closed === false && p1.can.attendance === false && p1.can.tracking === true && p1.can.notifications === true, JSON.stringify(p1.can));
  await expectError('   attendance waits for the next payroll to be closed (delivered)', run('2026-09', true, false, false), 'المسير اللي بعده');
  check('   ...nothing deleted by the refused run', (await w.attendance()) === 2);

  const slipBefore = await w.slip();
  const octBefore = await w.money('2026-10');
  const r1 = (await run('2026-09', false, true, true)).rows[0].r;
  check('   tracking and notifications of the period are deleted, later ones kept',
    N(r1.tracking_deleted) === 1 && N(r1.notifications_deleted) >= 1 && r1.attendance_deleted === null
    && (await w.one(`SELECT count(*)::int c FROM location_tracking`)).c === 1
    && (await w.one(`SELECT count(*)::int c FROM notifications WHERE body = 'جديد'`)).c === 1, JSON.stringify(r1));

  // قرار معلّق لأيام المسير يمنع حذف الحضور حتى بعد إغلاق المسير التالي
  await w.q(`UPDATE payroll_periods SET status = 'closed' WHERE period_month = '2026-10'`);
  await expectError('   ...and for its delivery to be confirmed', run('2026-09', true, false, false), 'تم تسليم الرواتب');
  await expectOk('   the admin confirms the next payroll was delivered', as(w.db, 'admin', `SELECT mark_payroll_delivered('2026-10')`));
  const pend = await w.one(`INSERT INTO payroll_events (employee_id, event_date, event_type, minutes, days, amount, direction, payroll_month, status, source)
             VALUES ($1, '2026-09-20', 'early_leave', 30, 0, 1250, -1, '2026-11', 'pending', 'attendance') RETURNING id`, [E]);
  await expectError('   a pending decision for a day of the period blocks the attendance cleanup', run('2026-09', true, false, false), 'تنتظر قرارك');
  await w.q(`UPDATE payroll_events SET status = 'ignored' WHERE id = $1`, [pend.id]);

  // فشل بالنص: كل شي يتراجع
  await w.db.exec(`CREATE FUNCTION public._boom() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'boom'; END $$;
                   CREATE TRIGGER _boom BEFORE INSERT ON public.payroll_cleanups FOR EACH ROW EXECUTE FUNCTION public._boom();`);
  await expectError('   a failure in the middle...', run('2026-09', true, false, false), 'boom');
  check('   ...rolls everything back (attendance still there, not frozen)', (await w.attendance()) === 2 && (await preview('2026-09')).done.attendance === false);
  await w.db.exec(`DROP TRIGGER _boom ON public.payroll_cleanups; DROP FUNCTION public._boom();`);

  const novBefore = await w.money('2026-11');
  const r2 = (await run('2026-09', true, false, false)).rows[0].r;
  check('   now the attendance of the period is deleted', N(r2.attendance_deleted) === 2 && (await w.attendance()) === 0, JSON.stringify(r2));
  check('   the approved slip and the following payrolls are identical before and after',
    (await w.slip()) === slipBefore && (await w.money('2026-10')) === octBefore && (await w.money('2026-11')) === novBefore,
    `${await w.slip()} | ${await w.money('2026-10')} | ${await w.money('2026-11')}`);
  check('   slip lines and payroll events (the history) are kept',
    (await w.one(`SELECT count(*)::int c FROM salary_slip_lines l JOIN salary_slips s ON s.id = l.salary_slip_id WHERE s.employee_id = $1`, [E])).c === 3
    && (await w.one(`SELECT count(*)::int c FROM payroll_events WHERE employee_id = $1 AND salary_slip_id IS NOT NULL`, [E])).c === 2);
  await expectError('   running it twice is refused', run('2026-09', true, false, false), 'منظّف مسبقاً');
  await w.q(`SELECT sync_payroll_day($1, '2026-09-07')`, [E]);
  check('   a cleaned day is never recalculated', (await w.money('2026-11')) === novBefore);
  const p2 = await preview('2026-09');
  check('   the log says who cleaned what and when',
    p2.done.attendance === true && p2.can.attendance === false && p2.history.length === 2 && p2.history[0].by === 'أدمن' && N(p2.history[0].attendance) === 2, JSON.stringify(p2.history));
  // قرار بعد التنظيف (نزاع): يبقى يشتغل كتسوية
  const lateEv = await w.one(`SELECT id FROM payroll_events WHERE employee_id = $1 AND event_type = 'late' AND salary_slip_id IS NOT NULL`, [E]);
  await expectOk('   a dispute can still be settled after the cleanup (excuse the old late)', as(w.db, 'admin', `SELECT decide_payroll_event($1, false, 'نزاع: طلع عنده عذر')`, [lateEv.id]));
  check('   ...as a 2,500 refund in the open payroll, on purpose this time', (await w.money('2026-11')).startsWith('2500/'), await w.money('2026-11'));
}

// ---------------- 4) السلفة ما تنحذف وعليها باقي ----------------
{
  const w = await world();
  await expectError('4) a loan with a remaining balance cannot be deleted', as(w.db, 'admin', `DELETE FROM loans WHERE id = $1`, [w.loan]), 'عليها باقي');
  check('   ...the debt is still there', (await w.one(`SELECT count(*)::int c FROM loan_installments WHERE loan_id = $1 AND NOT is_paid`, [w.loan])).c === 2);
  const octBefore = await w.money('2026-10');
  await w.q(`UPDATE loan_installments SET is_paid = true, paid_at = now(), payment_type = 'cash' WHERE loan_id = $1 AND NOT is_paid`, [w.loan]);
  const slipBefore = await w.slip();
  await expectError('   a repaid loan is not deleted directly (its record must be kept)', as(w.db, 'admin', `DELETE FROM loans WHERE id = $1`, [w.loan]), 'أرشفة السلفة');
  await expectOk('   once fully repaid it is archived (summary kept, loan removed)', as(w.db, 'admin', `SELECT archive_settled_loan($1)`, [w.loan]));
  check('   the old slip still carries its 100,000 installment and its "loan" line',
    (await w.slip()) === slipBefore && (await w.one(`SELECT count(*)::int c FROM salary_slip_lines WHERE line_type = 'loan'`)).c === 1, await w.slip());
  check('   pending and rejected requests can still be removed', true);
  const other = await w.one(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, status, pledge_url)
                             VALUES ($1, 50000, 50000, 1, 50000, 'rejected', 'p.jpg') RETURNING id`, [IDS.emp]);
  await expectOk('   (rejected request deleted)', as(w.db, 'admin', `DELETE FROM loans WHERE id = $1`, [other.id]));
  // حذف الموظف نهائياً يمسح سلفه بالتسلسل حتى لو عليها باقي
  const X = '00000000-0000-0000-0000-0000000000c7';
  await w.q(`INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password)
             VALUES ($1, 'SC2', 'ينحذف', $2, 500000, '2026-10-01', false)`, [X, IDS.branch]);
  const xl = await w.one(`INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, status, pledge_url)
                          VALUES ($1, 100000, 50000, 2, 100000, 'pending', 'p.jpg') RETURNING id`, [X]);
  await as(w.db, 'admin', `SELECT approve_loan($1, 100000, 2, '2026-11-10')`, [xl.id]);
  await w.q(`DELETE FROM employees WHERE id = $1`, [X]);
  check('   deleting the employee himself still removes his loans', (await w.one(`SELECT count(*)::int c FROM loans WHERE id = $1`, [xl.id])).c === 0);
  void octBefore;
}

// ---------------- 3) سجلات النظام ----------------
{
  const w = await world();
  await w.db.exec(`
    CREATE TABLE cron.job_run_details (jobid bigint, status text, start_time timestamptz, end_time timestamptz);
    INSERT INTO cron.job_run_details VALUES (1, 'succeeded', now() - interval '30 days', now()), (1, 'succeeded', now() - interval '8 days', now()), (1, 'succeeded', now() - interval '1 hour', now());
  `);
  const r = (await w.q(`SELECT public.purge_system_logs() r`))[0].r;
  check('3) system job logs older than 7 days are purged, recent ones kept',
    N(r.cron_rows_deleted) === 2 && (await w.one(`SELECT count(*)::int c FROM cron.job_run_details`)).c === 1, JSON.stringify(r));
  await expectError('   only the system or an admin can run it', as(w.db, 'emp', `SELECT public.purge_system_logs()`), '');
}

await done();
