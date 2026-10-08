// المساعد الذكي — سياق القرارات المعلّقة والتحقق من الحركات المقترحة (قراءة فقط).
import { setup, as, IDS, check, expectError, done } from './lib.mjs';

const db = await setup();
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];
const at = (date, hhmm) => `${date} ${hhmm}:00+03`;
const admin = async (sql, p = []) => (await as(db, 'admin', sql, p)).rows[0].r;
const daysAgo = async (n) => (await one(`SELECT ((now() AT TIME ZONE 'Asia/Baghdad')::date - $1::int)::text d`, [n])).d;

const E = '00000000-0000-0000-0000-0000000000c7';
await db.exec(`
  UPDATE employees SET join_date = '2026-01-01';
  INSERT INTO employees (id, employee_code, full_name, branch_id, monthly_salary_iqd, join_date, must_change_password)
    VALUES ('${E}', 'D1', 'موظف القرارات', '${IDS.branch}', 600000, '2026-01-01', false);
  UPDATE system_settings SET value = value || '{"no_record_from": "2026-09-02"}' WHERE key = 'payroll_policy';
`);
await db.query(`INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
  VALUES ($1, 'صباحي', '09:00', '17:00', 10, '{0,1,2,3,4,5,6}')`, [E]);
await db.query(`UPDATE work_schedule_history SET effective_from = '-infinity'`);

// تأخيرين: الأول انعفى، الثاني معلّق
const d1 = await daysAgo(4), d2 = await daysAgo(3);
for (const d of [d1, d2]) {
  await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time) VALUES ($1, $2, $3, 'late', $4, $5)`,
    [E, IDS.branch, d, at(d, '09:30'), at(d, '17:00')]);
}
await db.query(`UPDATE attendance SET deduction_status = 'ignored' WHERE employee_id = $1 AND work_date = $2`, [E, d1]);

await expectError('decision context is admin-only', as(db, 'manager', `SELECT assistant_decision_context(NULL)`), 'غير مصرح');
const ctx = await admin(`SELECT assistant_decision_context(NULL) r`);
const item = ctx.find((x) => x.employee === 'موظف القرارات' && x.type === 'late');
check('pending late is listed with its event id and amount', item && item.event_id && Number(item.amount) > 0, JSON.stringify(ctx).slice(0, 300));
check('context: excused once before', item && Number(item.excused_last_90d) === 1, JSON.stringify(item));

const ev = await one(`SELECT id FROM payroll_events WHERE employee_id=$1 AND event_date=$2 AND event_type='late' AND status<>'void'`, [E, d2]);
const excused = await one(`SELECT id FROM payroll_events WHERE employee_id=$1 AND event_date=$2 AND event_type='late' AND status<>'void'`, [E, d1]);
const pending = await admin(`SELECT assistant_pending_events($1::uuid[]) r`, [[ev.id, excused.id, '00000000-0000-0000-0000-000000000000']]);
check('proposal check: only still-pending events come back', pending.length === 1 && pending[0].event_id === ev.id, JSON.stringify(pending));
const before = await one(`SELECT status FROM payroll_events WHERE id=$1`, [ev.id]);
check('reading context changes nothing', before.status === 'pending');

done();
