// خصم التأخير ما يتجاوز أجر يوم واحد (بصمة بعد نهاية الدوام كانت تطلع «تأخير 13 ساعة» بأجر أكثر من يومين).
import { setup, as, IDS, expectOk, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];
const N = (v) => Number(v);

await db.exec(`UPDATE employees SET join_date = '2026-01-01'`);
const E = '00000000-0000-0000-0000-0000000000f1';
// دوام 9:00–14:00 (300 دقيقة)، راتب 600,000 ← أجر اليوم 20,000، أجر الدقيقة 66.67
await db.exec(`
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ('${E}', 'LC1', 'موظف التأخير', '${IDS.branch}', 600000, '2026-01-01', false);
  INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
    VALUES ('${E}', 'صباحي', '09:00', '14:00', 10, '{0,1,2,3,4,5,6}');
  UPDATE work_schedule_history SET effective_from = '-infinity';
`);
await q(`SELECT ensure_payroll_period('2026-09')`);
const at = (d, hm) => `${d} ${hm}:00+03`;
const late = async (d) => one(`SELECT id, minutes::int m, amount::numeric a, amount_override::numeric o, status, notes FROM payroll_events
  WHERE employee_id = $1 AND event_date = $2 AND event_type = 'late' AND status <> 'void'`, [E, d]);
const deductions = async () => N((await one(`SELECT payroll_employee_summary($1, '2026-09') s`, [E])).s.deductions);

// تأخير عادي داخل الدوام: ما يتغير
await q(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time) VALUES ($1, $2, '2026-09-07', 'late', $3, $4)`,
  [E, IDS.branch, at('2026-09-07', '10:00'), at('2026-09-07', '14:00')]);
const normal = await late('2026-09-07');
check('1) an ordinary late (60 min) is still charged by the minute (4,000)', normal && normal.m === 60 && N(normal.a) === 4000 && !normal.notes.includes('محدد'), JSON.stringify(normal));

// بصمة بعد نهاية الدوام: 21:58 = 778 دقيقة × 66.67 = 51,867 ← محدد بأجر اليوم 20,000
await q(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time) VALUES ($1, $2, '2026-09-08', 'late', $3)`,
  [E, IDS.branch, at('2026-09-08', '21:58')]);
const huge = await late('2026-09-08');
check('2) a punch after the shift ended: minutes stay (778) but the amount stops at one day (20,000)',
  huge && huge.m === 778 && N(huge.a) === 20000 && huge.notes.includes('محدد بأجر يوم واحد'), JSON.stringify(huge));

// تأخير كل الدوام بالضبط (300 دقيقة) = أجر اليوم بدون ملاحظة التحديد
await q(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time) VALUES ($1, $2, '2026-09-09', 'late', $3, $4)`,
  [E, IDS.branch, at('2026-09-09', '14:00'), at('2026-09-09', '14:00')]);
const full = await late('2026-09-09');
check('   a whole-shift late (300 min) equals the day rate exactly', full && N(full.a) === 20000 && !full.notes.includes('محدد'), JSON.stringify(full));

await expectOk('   the admin deducts the capped late', as(db, 'admin', `SELECT decide_payroll_event($1, true, 'بصم بعد الدوام')`, [huge.id]));
check('   ...one day is deducted, not two and a half', (await deductions()) === 20000, String(await deductions()));
await q(`SELECT sync_payroll_period('2026-09', $1)`, [E]);
check('   ...and it stays capped after a recalculation', N((await late('2026-09-08')).a) === 20000 && (await deductions()) === 20000);

// المبلغ اللي كتبه الأدمن يبقى هو، حتى لو أكبر من أجر اليوم (قراره)
await expectOk('   an amount the admin typed is kept as typed', as(db, 'admin', `SELECT decide_payroll_event($1, true, 'قرار الإدارة', 25000)`, [huge.id]));
await q(`SELECT sync_payroll_day($1, '2026-09-08')`, [E]);
const typed = await late('2026-09-08');
check('   ...25,000 after a recalculation', N(typed.a) === 25000 && N(typed.o) === 25000, JSON.stringify(typed));

await done();
