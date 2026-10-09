// المرحلة 3: البصمة الناقصة بخصم مقترح (قرار الأدمن)، الموظف بدون فرع، العطلة داخل الإجازة، وشرط الأرشفة.
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];
const N = (v) => Number(v);

await db.exec(`UPDATE employees SET join_date = '2026-01-01'`);
const E = '00000000-0000-0000-0000-0000000000d1';
await db.exec(`
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ('${E}', 'Q1', 'موظف البصمة', '${IDS.branch}', 600000, '2026-01-01', false);
  INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
    VALUES ('${E}', 'صباحي', '09:00', '17:00', 15, '{0,1,2,3,4,5,6}');
  UPDATE work_schedule_history SET effective_from = '-infinity';
`);
await q(`SELECT ensure_payroll_period('2026-09')`);
const at = (d, hm) => `${d} ${hm}:00+03`;
const mp = async (d) => one(`SELECT minutes::int m, amount::numeric a, direction::int dir, status, notes FROM payroll_events
  WHERE employee_id = $1 AND event_date = $2 AND event_type = 'missing_punch' AND status <> 'void'`, [E, d]);

// ---------------- 5) بدون بصمة انصراف ----------------
await q(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time) VALUES ($1, $2, '2026-09-07', 'present', $3)`,
  [E, IDS.branch, at('2026-09-07', '09:00')]);
await q(`INSERT INTO location_tracking (employee_id, latitude, longitude, "timestamp") VALUES ($1, 33.3, 44.4, $2), ($1, 33.3, 44.4, $3)`,
  [E, at('2026-09-07', '10:30'), at('2026-09-07', '12:00')]);
await q(`SELECT sync_payroll_day($1, '2026-09-07')`, [E]);
const m1 = await mp('2026-09-07');
check('5) no check-out: suggested deduction from the last tracked presence (12:00 → 17:00 = 300 min = 12,500)',
  m1 && m1.m === 300 && N(m1.a) === 12500 && m1.dir === -1 && m1.status === 'pending' && m1.notes.includes('12:00'), JSON.stringify(m1));
const pending = (await one(`SELECT payroll_employee_summary($1, '2026-09') s`, [E])).s;
check('   it is a pending decision and NOT deducted automatically', N(pending.pending_count) >= 1 && N(pending.deductions) === 0, JSON.stringify(pending));

await q(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time) VALUES ($1, $2, '2026-09-08', 'present', $3)`,
  [E, IDS.branch, at('2026-09-08', '09:10')]);
await q(`SELECT sync_payroll_day($1, '2026-09-08')`, [E]);
const m2 = await mp('2026-09-08');
check('   without tracking: from the check-in time (09:10 → 17:00 = 470 min)', m2 && m2.m === 470 && m2.notes.includes('وقت بصمة الحضور'), JSON.stringify(m2));

const ev1 = (await one(`SELECT id FROM payroll_events WHERE employee_id = $1 AND event_date = '2026-09-07' AND event_type = 'missing_punch' AND status <> 'void'`, [E])).id;
await expectOk('   admin deducts it', as(db, 'admin', `SELECT decide_payroll_event($1, true, 'طلع بدون بصمة')`, [ev1]));
const afterDeduct = (await one(`SELECT payroll_employee_summary($1, '2026-09') s`, [E])).s;
check('   ...then it is deducted', N(afterDeduct.deductions) === 12500, JSON.stringify(afterDeduct.deductions));
check('   ...and the employee is told', (await one(`SELECT count(*)::int c FROM notifications WHERE employee_id = $1 AND body LIKE '%بدون بصمة انصراف%'`, [E])).c === 1);
const ev2 = (await one(`SELECT id FROM payroll_events WHERE employee_id = $1 AND event_date = '2026-09-08' AND event_type = 'missing_punch' AND status <> 'void'`, [E])).id;
await expectOk('   admin excuses the other (forgot to punch)', as(db, 'admin', `SELECT decide_payroll_event($1, false, 'نسي البصمة وهو مداوم')`, [ev2]));
check('   ...nothing deducted for it', N((await one(`SELECT payroll_employee_summary($1, '2026-09') s`, [E])).s.deductions) === 12500);

// قرار قديم على بصمة ناقصة (قبل التحديث كانت بدون مبلغ) ما يتغيّر
await q(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time) VALUES ($1, $2, '2026-09-09', 'present', $3)`,
  [E, IDS.branch, at('2026-09-09', '09:00')]);
await q(`SELECT sync_payroll_day($1, '2026-09-09')`, [E]);
await q(`UPDATE payroll_events SET amount = 0, minutes = 0, direction = 0, status = 'approved', decided_at = now()
  WHERE employee_id = $1 AND event_date = '2026-09-09' AND event_type = 'missing_punch'`, [E]);
await q(`SELECT sync_payroll_day($1, '2026-09-09')`, [E]);
const m3 = await mp('2026-09-09');
check('   an earlier decision (confirmed with no amount) stays as decided', m3 && N(m3.a) === 0 && m3.status === 'approved', JSON.stringify(m3));

// ---------------- 11) موظف بدون فرع ----------------
await expectError('11) an active employee without a branch is refused', as(db, 'admin',
  `INSERT INTO employees (id, employee_code, full_name, monthly_salary_iqd) VALUES (gen_random_uuid(), 'Q2', 'بلا فرع', 500000)`), 'لازم يكون إله فرع');
const NB = '00000000-0000-0000-0000-0000000000d2';
await db.exec(`ALTER TABLE employees DISABLE TRIGGER trg_check_employee_branch`);
await q(`INSERT INTO employees (id, employee_code, full_name, monthly_salary_iqd, join_date, must_change_password) VALUES ($1, 'Q3', 'قديم بلا فرع', 500000, '2026-01-01', false)`, [NB]);
await db.exec(`ALTER TABLE employees ENABLE TRIGGER trg_check_employee_branch`);
await q(`INSERT INTO payroll_events (employee_id, event_date, event_type, days, amount, direction, payroll_month, status, source)
  VALUES ($1, '2026-09-10', 'absence', 1, 16667, -1, '2026-09', 'pending', 'no_record')`, [NB]);
const nbEv = (await one(`SELECT id FROM payroll_events WHERE employee_id = $1`, [NB])).id;
await expectOk('   an old employee without a branch: the absence decision no longer gets stuck', as(db, 'admin', `SELECT decide_payroll_event($1, false, 'عذر')`, [nbEv]));
check('   ...the day is recorded under a fallback branch', (await one(`SELECT branch_id FROM attendance WHERE employee_id = $1 AND work_date = '2026-09-10'`, [NB])).branch_id === IDS.branch);
await expectOk('   deactivating a branchless employee still works', db.query(`UPDATE employees SET is_active = false, termination_date = '2026-09-11' WHERE id = $1`, [NB]));

// ---------------- 14) العطلة الرسمية داخل الإجازة ----------------
await q(`INSERT INTO official_holidays (holiday_date, name) VALUES ('2026-11-17', 'عطلة')`);
const lr = (await one(`INSERT INTO leave_requests (employee_id, leave_type, start_date, end_date, status, is_paid)
  VALUES ($1, 'annual', '2026-11-16T09:00:00Z', '2026-11-18T09:00:00Z', 'pending', true) RETURNING id`, [E])).id;
const counted = (await one(`SELECT leave_request_days(l) d FROM leave_requests l WHERE l.id = $1`, [lr])).d;
check('14) an official holiday inside a leave is not taken from the balance (16–18 Nov with a holiday on the 17th = 2 days)', N(counted) === 2, String(counted));

// ---------------- 18) أرشفة: موظف باشر بعد الشهر ما يوقفها ----------------
await db.exec(`UPDATE system_settings SET value = value || '{"no_record_from": "2027-01-01"}' WHERE key = 'payroll_policy'`);
const emps = await q(`SELECT id FROM employees WHERE (is_active OR termination_date IS NOT NULL) AND (join_date IS NULL OR join_date <= '2026-09-26')
  AND (termination_date IS NULL OR termination_date >= '2026-09-01')`);
for (const r of emps) {
  await q(`INSERT INTO salary_slips (employee_id, work_month, basic_salary, net_salary, status, computed_by_engine) VALUES ($1, '2026-09', 1, 1, 'published', true)
    ON CONFLICT DO NOTHING`, [r.id]);
}
await q(`UPDATE payroll_periods SET status = 'closed' WHERE period_month = '2026-09'`);
await q(`INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password)
  VALUES (gen_random_uuid(), 'Q4', 'باشر بعدين', $1, 500000, '2026-10-05', false)`, [IDS.branch]);
const arch = (await as(db, 'admin', `SELECT safe_archive_payroll_month('2026-09') r`)).rows[0].r;
check('18) a new employee who joined after the month does not block archiving it (only the 60-day rule remains)',
  arch.success === false && String(arch.error).includes('60') && !arch.missing_employees, JSON.stringify(arch));

done();
