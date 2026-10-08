// المساعد الذكي — الملخص الصباحي (أرقام القاعدة، مرة وحدة باليوم، يتطفى) وحفظ المحادثات (صاحبها فقط، 90 يوم).
import { setup, as, IDS, check, expectError, done } from './lib.mjs';

const db = await setup();
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];
const admin = async (sql, p = []) => (await as(db, 'admin', sql, p)).rows[0].r;
// تشغيل كأنه pg_cron (بدون JWT)
const system = async (sql, p = []) => {
  await db.exec(`RESET ROLE; SELECT set_config('request.jwt.claim.sub', '', false), set_config('request.jwt.claim.role', '', false);`);
  return (await db.query(sql, p)).rows[0];
};
const today = (await one(`SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date::text d`)).d;

IDS.admin2 = '00000000-0000-0000-0000-0000000000a2';
await db.exec(`
  INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, must_change_password)
    VALUES ('${IDS.admin2}', 'A2', 'أدمن ثاني', 'admin', '${IDS.branch}', 2000000, false);
  INSERT INTO auth.users (id, email) VALUES ('${IDS.admin2}', 'a2@x');
  DELETE FROM official_holidays WHERE holiday_date = '${today}';
`);
await db.query(`INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
  SELECT id, 'صباحي', '09:00', '17:00', 10, '{0,1,2,3,4,5,6}' FROM employees WHERE role <> 'admin'`);
await db.query(`UPDATE work_schedule_history SET effective_from = '-infinity'`);
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time) VALUES ($1, $2, $3, 'late', now())`,
  [IDS.emp, IDS.branch, today]);

// ---------------- الملخص الصباحي ----------------
await expectError('summary is admin-only', as(db, 'manager', `SELECT assistant_morning_summary()`), 'غير مصرح');
await expectError('employees cannot send the summary', as(db, 'emp', `SELECT send_assistant_morning_summary()`));
const s = await admin(`SELECT assistant_morning_summary() r`);
check('summary counts: 1 of 3 punched (late), 2 not yet', s.present === 1 && s.scheduled === 3 && s.late === 1 && s.not_punched === 2,
  JSON.stringify(s));
check('summary text names who has not punched', s.body.includes('ما بصموا') && s.body.includes('مدير') && s.body.includes('موظف ثاني'), s.body);

const sent = await system(`SELECT send_assistant_morning_summary() n`);
check('summary sent to each active admin', sent.n === 2, JSON.stringify(sent));
const again = await system(`SELECT send_assistant_morning_summary() n`);
check('not sent twice the same day', again.n === 0);
const notes = await one(`SELECT count(*)::int c, min(type) t FROM notifications WHERE type = 'assistant_summary'`);
check('notification type assistant_summary', notes.c === 2 && notes.t === 'assistant_summary');

check('setting defaults to on', (await admin(`SELECT assistant_settings() r`)).morning_summary === true);
await expectError('only admins change the setting', as(db, 'manager', `SELECT assistant_set_morning_summary(false)`), 'غير مصرح');
await admin(`SELECT assistant_set_morning_summary(false) r`);
await db.query(`DELETE FROM notifications WHERE type = 'assistant_summary'`);
const off = await system(`SELECT send_assistant_morning_summary() n`);
check('turned off: nothing sent', off.n === 0 && (await admin(`SELECT assistant_settings() r`)).morning_summary === false);

// ---------------- حفظ المحادثات ----------------
const conv = await admin(`SELECT assistant_save_messages(NULL, $1::jsonb) r`, [JSON.stringify([
  { role: 'user', text: '  شكد   تأخر علي هالشهر؟ ', voice: true },
  { role: 'assistant', text: 'علي تأخر مرتين.' },
  { role: 'assistant', text: '   ' },
])]);
check('new conversation titled by the first question', (await one(`SELECT title FROM assistant_conversations WHERE id = $1`, [conv])).title === 'شكد تأخر علي هالشهر؟');
await admin(`SELECT assistant_save_messages($1, $2::jsonb) r`, [conv, JSON.stringify([{ role: 'user', text: 'وحسن؟' }, { role: 'assistant', text: 'ما تأخر.' }])]);
const msgs = (await as(db, 'admin', `SELECT role, text, voice FROM assistant_messages WHERE conversation_id = $1 ORDER BY id`, [conv])).rows;
check('messages saved in order, empty ones skipped, voice kept', msgs.length === 4 && msgs[0].voice === true && msgs[3].text === 'ما تأخر.',
  JSON.stringify(msgs));

check('another admin cannot see it', (await as(db, 'admin2', `SELECT count(*)::int c FROM assistant_conversations`)).rows[0].c === 0
  && (await as(db, 'admin2', `SELECT count(*)::int c FROM assistant_messages`)).rows[0].c === 0);
await expectError('another admin cannot append to it', as(db, 'admin2', `SELECT assistant_save_messages($1, '[{"role":"user","text":"x"}]')`, [conv]), 'غير موجودة');
check('managers and employees see nothing', (await as(db, 'manager', `SELECT count(*)::int c FROM assistant_conversations`)).rows[0].c === 0
  && (await as(db, 'emp', `SELECT count(*)::int c FROM assistant_messages`)).rows[0].c === 0);
await expectError('employees cannot save', as(db, 'emp', `SELECT assistant_save_messages(NULL, '[{"role":"user","text":"x"}]')`), 'غير مصرح');
await expectError('messages cannot be inserted directly', as(db, 'admin', `INSERT INTO assistant_messages (conversation_id, role, text) VALUES ($1, 'user', 'x')`, [conv]));

const old = await admin(`SELECT assistant_save_messages(NULL, '[{"role":"user","text":"قديمة"}]') r`);
await db.query(`UPDATE assistant_conversations SET updated_at = now() - interval '91 days' WHERE id = $1`, [old]);
const purged = await system(`SELECT purge_old_assistant_conversations() n`);
check('conversations older than 90 days are deleted with their messages', purged.n === 1
  && (await one(`SELECT count(*)::int c FROM assistant_messages WHERE conversation_id = $1`, [old])).c === 0
  && (await one(`SELECT count(*)::int c FROM assistant_conversations WHERE id = $1`, [conv])).c === 1);

await as(db, 'admin', `DELETE FROM assistant_conversations WHERE id = $1`, [conv]);
check('the owner can delete a conversation', (await one(`SELECT count(*)::int c FROM assistant_conversations`)).c === 0);

done();
