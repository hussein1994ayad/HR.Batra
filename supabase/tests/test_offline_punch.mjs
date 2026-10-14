// تدقيق 14/10/2026 — المرحلة 2: البصمة بدون إنترنت (BUG-001، FEATURE-004).
// وقت البصمة المحفوظة: «مؤكد» إذا التطبيق حسبه من وقت السيرفر وعدّاد الموبايل، وإلا ساعة الموبايل + «يحتاج مراجعة».
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const IN = [33.3, 44.4];
const ago = (mins) => new Date(Date.now() - mins * 60000).toISOString();
const punch = (who, type, args = {}) => as(db, who,
  `SELECT punch_attendance($1, ${IN[0]}, ${IN[1]}, NULL, false, $2::timestamptz, NULL, $3::timestamptz, $4) r`,
  [type, args.client ?? null, args.trusted ?? null, args.check ?? null]).then((r) => r.rows[0].r);
const row = async (emp) => (await db.query(`SELECT check_in_time, check_out_time, check_in_time_source s_in, check_out_time_source s_out,
  check_in_device_time d_in, check_out_device_time d_out, check_in_offline FROM attendance WHERE employee_id = $1 ORDER BY work_date DESC LIMIT 1`, [emp])).rows[0];
const near = (a, b, secs = 2) => Math.abs(new Date(a).getTime() - new Date(b).getTime()) <= secs * 1000;

// 1) بصمة عادية: وقت السيرفر، والمصدر «مباشر»، والرد فيه وقت السيرفر (التطبيق يحفظه)
let r = await punch('emp', 'check_in');
let a = await row(IDS.emp);
check('1) an online punch uses the server time and is marked online', r.ok && a.s_in === 'online' && a.d_in === null, JSON.stringify({ r, a }));
check('   the reply carries the server time for the app clock anchor', !!r.server_time && near(r.server_time, new Date()), r.server_time);
const srv = await as(db, 'emp', `SELECT server_now() t`);
check('   server_now() is available to signed-in users', near(srv.rows[0].t, new Date()));
await expectError('   ...but not to anonymous callers', as(db, 'anon', `SELECT server_now()`), 'permission denied');

// 2) بدون إنترنت + الساعة متغيّرة لكن التطبيق حسب الوقت الحقيقي: الوقت المعتمد = المحسوب، ووقت الموبايل ينحفظ
const real = ago(30); // وصل قبل نص ساعة
const faked = ago(120); // الموظف رجّع ساعة الموبايل ساعتين
r = await punch('emp2', 'check_in', { client: faked, trusted: real, check: 'anchored' });
a = await row(IDS.emp2);
check('2) an anchored offline punch is recorded at the real (computed) time, not the phone clock',
  r.ok && near(a.check_in_time, real) && a.s_in === 'offline_verified' && a.check_in_offline, JSON.stringify(a));
check('   the phone clock is kept for comparison', near(a.d_in, faked), JSON.stringify(a));

// 3) بدون إنترنت وما يكدر يحسب (الموبايل انطفى/ما اكو وقت سيرفر): ساعة الموبايل + «يحتاج مراجعة»
r = await punch('emp2', 'check_out', { client: ago(5), check: 'no_anchor' });
a = await row(IDS.emp2);
check('3) an unanchored offline punch uses the phone clock and needs review', r.ok && near(a.check_out_time, ago(5), 5) && a.s_out === 'offline_review', JSON.stringify(a));

// 4) التطبيق القديم (يرسل وقت الموبايل بس) = يحتاج مراجعة
await db.exec(`DELETE FROM attendance WHERE employee_id = '${IDS.manager}'`);
r = await as(db, 'manager', `SELECT punch_attendance('check_in', ${IN[0]}, ${IN[1]}, NULL, false, $1::timestamptz, NULL) r`, [ago(10)]).then((x) => x.rows[0].r);
a = await row(IDS.manager);
check('4) an old app version (phone clock only) still works but needs review', r.ok && a.s_in === 'offline_review', JSON.stringify(a));

// 5) وقت محسوب غير منطقي (بالمستقبل) = ما ينقبل كمؤكد، يرجع لساعة الموبايل + مراجعة
await db.exec(`DELETE FROM attendance WHERE employee_id = '${IDS.emp}'`);
r = await punch('emp', 'check_in', { client: ago(3), trusted: new Date(Date.now() + 3600000).toISOString(), check: 'anchored' });
a = await row(IDS.emp);
check('5) an impossible computed time (in the future) falls back to the phone clock + review', r.ok && a.s_in === 'offline_review', JSON.stringify(a));
r = await punch('emp', 'check_out', { client: new Date(Date.now() + 3600000).toISOString(), check: 'no_anchor' });
check('   a phone clock in the future is still refused', r.ok === false && r.code === 'clock_in_future', JSON.stringify(r));

// 6) مراجعة: الأدمن أو مدير الفرع؛ الموظف ما يغيّر المصدر ولا وقت الموبايل
const emp2Att = (await db.query(`SELECT id FROM attendance WHERE employee_id = $1`, [IDS.emp2])).rows[0].id;
await expectError('6) an employee cannot mark his own punch as reviewed', as(db, 'emp2', `SELECT mark_offline_punch_reviewed($1)`, [emp2Att]), 'للإدارة');
await expectOk('   the branch manager marks it reviewed', as(db, 'manager', `SELECT mark_offline_punch_reviewed($1)`, [emp2Att]));
a = await row(IDS.emp2);
check('   ...the review flag becomes «reviewed» (the verified check-in stays verified)', a.s_out === 'offline_reviewed' && a.s_in === 'offline_verified', JSON.stringify(a));
check('   ...and it is logged with who did it', (await db.query(`SELECT count(*)::int n FROM audit_log WHERE row_id = $1 AND actor_id = $2`, [emp2Att, IDS.manager])).rows[0].n === 1);
const mgrAtt = (await db.query(`SELECT id FROM attendance WHERE employee_id = $1`, [IDS.manager])).rows[0].id;
await expectError('   a manager cannot review his own punch', as(db, 'manager', `SELECT mark_offline_punch_reviewed($1)`, [mgrAtt]), 'بصمتك');
await expectError('   the phone clock cannot be edited', as(db, 'admin', `UPDATE attendance SET check_in_device_time = now() WHERE id = $1`, [emp2Att]), 'ما يتعدّل');
await expectError('   the source cannot be set by hand', as(db, 'admin', `UPDATE attendance SET check_in_time_source = 'online' WHERE id = $1`, [mgrAtt]), 'ما يتغير يدوياً');

// 7) تعديل الإدارة للوقت = «يدوي»، والحضور اليدوي = «يدوي»
await expectOk('7) the admin corrects a time', as(db, 'admin', `UPDATE attendance SET check_in_time = check_in_time - interval '1 minute' WHERE id = $1`, [mgrAtt]));
check('   ...the time source becomes manual', (await row(IDS.manager)).s_in === 'manual');
await db.exec(`DELETE FROM attendance WHERE employee_id = '${IDS.admin}'`);
await expectOk('   a manual attendance by the admin', as(db, 'admin',
  `INSERT INTO attendance (employee_id, branch_id, work_date, check_in_time, status) VALUES ($1, $2, current_date - 1, now() - interval '1 day', 'present')`, [IDS.admin, IDS.branch]));
check('   ...is marked manual', (await row(IDS.admin)).s_in === 'manual');

done();
