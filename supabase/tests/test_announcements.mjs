// التعاميم (مدة + جمهور) والمجازون الآن
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();

const publish = (who, args) => as(db, who,
  `SELECT publish_announcement($1, $2, $3::timestamptz, $4::timestamptz, $5, $6::uuid, $7::uuid[]) AS n`,
  [args.title ?? 'اجتماع', args.content ?? 'اجتماع عام الساعة 10', args.starts ?? null, args.ends ?? null,
   args.target ?? 'all', args.branch ?? null, args.employees ?? null]).then((r) => r.rows[0].n);
const visible = async (who) =>
  (await as(db, who, `SELECT title FROM get_active_announcements()`)).rows.map((r) => r.title);
const inHours = (h) => new Date(Date.now() + h * 3600e3).toISOString();

await expectError('an employee cannot publish', publish('emp', {}), 'غير مصرح');
await expectError('end before start is rejected', publish('admin', { starts: inHours(5), ends: inHours(1) }), 'بعد تاريخ بدايته');
await expectError('an already-ended announcement is rejected', publish('admin', { starts: inHours(-48), ends: inHours(-1) }), 'مضى');

const n = await publish('admin', { title: 'للجميع', ends: inHours(24) });
check('publishing to all notifies every active employee', n === 4, String(n));
await publish('manager', { title: 'للفرع', target: 'branch', branch: IDS.branch });
await publish('admin', { title: 'لموظف واحد', target: 'employees', employees: `{${IDS.emp2}}` });
await publish('admin', { title: 'لاحقاً', starts: inHours(3), ends: inHours(30) });

check('an employee sees announcements for everyone and for their branch', (await visible('emp')).sort().join() === ['للجميع', 'للفرع'].sort().join(), JSON.stringify(await visible('emp')));
check('a targeted employee also sees their own', (await visible('emp2')).includes('لموظف واحد'));
check('a scheduled announcement is hidden until it starts', !(await visible('emp2')).includes('لاحقاً'));
const direct = await as(db, 'emp', `SELECT title FROM announcements`);
check('the table no longer leaks other people\'s announcements', !direct.rows.some((r) => r.title === 'لموظف واحد'), JSON.stringify(direct.rows));

await db.exec(`UPDATE announcements SET ends_at = now() - interval '1 minute', starts_at = now() - interval '2 hours' WHERE title = 'للجميع'`);
check('an announcement disappears after its end date', !(await visible('emp')).includes('للجميع'));

const notif = await db.query(`SELECT body FROM notifications WHERE employee_id = $1 AND title = '📢 لموظف واحد'`, [IDS.emp2]);
check('the targeted employee got a push notification', notif.rows.length === 1);

// ---------------- المجازون الآن ----------------
// تواريخ بتوقيت بغداد حول "الآن"
// ساعة بغداد كنص ثم نعاملها كـ UTC حتى لا تتدخل منطقة جهاز الفحص
const baghdad = new Date((await db.query(`SELECT to_char(now() AT TIME ZONE 'Asia/Baghdad', 'YYYY-MM-DD"T"HH24:MI:SS') AS t`)).rows[0].t + 'Z');
const day = (offset) => new Date(baghdad.getTime() + offset * 86400e3).toISOString().slice(0, 10);
const hour = (offsetH) => { const d = new Date(baghdad.getTime() + offsetH * 3600e3); return d.toISOString().slice(11, 16); };
await db.exec(`
  SELECT set_config('request.jwt.claim.sub', '', false);
  INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status) VALUES
    ('${IDS.emp}',  '${day(-1)} 00:00+03', '${day(1)} 00:00+03', 'annual', 'approved'),   -- مجاز الآن
    ('${IDS.manager}', '${day(2)} 00:00+03', '${day(3)} 00:00+03', 'annual', 'approved'), -- إجازة لاحقة
    ('${IDS.admin}', '${day(-5)} 00:00+03', '${day(-3)} 00:00+03', 'annual', 'approved'); -- انتهت
`);
const onLeave = async () => (await as(db, 'emp2', `SELECT full_name, is_hourly FROM get_on_leave_now()`)).rows;
check('only employees on leave right now are listed', (await onLeave()).map((r) => r.full_name).join() === 'موظف', JSON.stringify(await onLeave()));

// زمنية: تظهر حتى تنتهي ساعتها
if (hour(-1) < hour(2) && hour(-2) < hour(-1)) {
  await db.exec(`SELECT set_config('request.jwt.claim.sub', '', false); INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, is_hourly, start_hour, end_hour, status)
    VALUES ('${IDS.emp2}', '${day(0)} 00:00+03', '${day(0)} 00:00+03', 'other', true, '${hour(-1)}', '${hour(2)}', 'approved')`);
  check('an hourly leave in progress is listed', (await onLeave()).some((r) => r.full_name === 'موظف ثاني' && r.is_hourly));
  await db.exec(`UPDATE leave_requests SET start_hour = '${hour(-2)}', end_hour = '${hour(-1)}' WHERE employee_id = '${IDS.emp2}' AND is_hourly`);
  check('an hourly leave that ended is hidden', !(await onLeave()).some((r) => r.full_name === 'موظف ثاني'));
}

const cols = (await as(db, 'emp2', `SELECT * FROM get_on_leave_now() LIMIT 1`)).fields.map((f) => f.name);
check('no leave type or reason is exposed', !cols.includes('leave_type') && !cols.includes('reason'), cols.join());
await expectError('anonymous users cannot list who is on leave', as(db, 'anon', `SELECT * FROM get_on_leave_now()`), 'permission denied');

// ---------------- المتأخرون اليوم ----------------
const today = (await db.query(`SELECT (now() AT TIME ZONE 'Asia/Baghdad')::date::text d`)).rows[0].d;
await db.exec(`
  INSERT INTO work_schedules (branch_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
    VALUES ('${IDS.branch}', 'دوام', '09:00', '17:00', 15, '{0,1,2,3,4,5,6}');
  DELETE FROM attendance WHERE work_date = '${today}';
  INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time) VALUES
    ('${IDS.emp}', '${IDS.branch}', '${today}', 'late', '${today} 09:40:00+03'),
    ('${IDS.manager}', '${IDS.branch}', '${today}', 'present', '${today} 08:55:00+03');
`);
const late = (await as(db, 'emp2', `SELECT full_name, late_minutes, branch_name FROM get_late_today()`)).rows;
check('late today lists only late arrivals with minutes from the shift start',
  late.length === 1 && late[0].full_name === 'موظف' && late[0].late_minutes === 40 && late[0].branch_name === 'الفرع الرئيسي', JSON.stringify(late));
const lateCols = (await as(db, 'emp2', `SELECT * FROM get_late_today() LIMIT 1`)).fields.map((f) => f.name);
check('late list exposes no deduction, reason or location', !lateCols.some((c) => /deduct|reason|_lat$|_lng$|latitude|longitude/.test(c)), lateCols.join());
await expectError('anonymous users cannot list who is late', as(db, 'anon', `SELECT * FROM get_late_today()`), 'permission denied');

done();
