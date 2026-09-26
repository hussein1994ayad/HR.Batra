// جولة الأمان الثانية: أعمدة الموظف، كلمات السر، الإجازات، أوقات البصمة، الحاويات
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();

// ---------------- 1) الموظف لا يعدّل بياناته الحساسة ----------------
const selfUpdate = (col, value) =>
  as(db, 'emp', `UPDATE employees SET ${col} = $1 WHERE id = $2 RETURNING id`, [value, IDS.emp]);

await expectError('employee cannot raise own salary', selfUpdate('monthly_salary_iqd', 99000000), 'غير مصرح');
await expectError('employee cannot set a future salary', selfUpdate('future_salary_iqd', 5000000), 'غير مصرح');
await expectError('employee cannot change own code', selfUpdate('employee_code', 'X9'), 'غير مصرح');
await expectError('employee cannot change own join date', selfUpdate('join_date', '2000-01-01'), 'غير مصرح');
await expectError('employee cannot clear the device lock', selfUpdate('device_id_lock', 'other-phone'), 'غير مصرح');
await expectError('employee cannot rename self', selfUpdate('full_name', 'مدير عام'), 'غير مصرح');
await expectError('manager cannot raise own salary', as(db, 'manager',
  `UPDATE employees SET monthly_salary_iqd = 1 WHERE id = $1 RETURNING id`, [IDS.manager]), 'غير مصرح');
await expectOk('employee can update phone and avatar', selfUpdate('phone', '07700000000'));
await expectOk('employee can clear must_change_password', selfUpdate('must_change_password', false));
await expectOk('admin can change any salary', as(db, 'admin',
  `UPDATE employees SET monthly_salary_iqd = 1200000 WHERE id = $1 RETURNING id`, [IDS.emp]));

// ---------------- 2) لا كلمات سر مقروءة ----------------
await db.exec(`UPDATE employees SET plain_password = 'Secret123' WHERE id = '${IDS.emp}'`);
const pw = (await db.query(`SELECT plain_password FROM employees WHERE id = $1`, [IDS.emp])).rows[0].plain_password;
check('plain passwords are never stored', pw === null, String(pw));

// ---------------- 3) الإجازات ----------------
const leave = (start, end, type = 'annual', extra = '') =>
  as(db, 'emp', `INSERT INTO leave_requests (employee_id, start_date, end_date, leave_type, status${extra ? ', is_hourly, start_hour, end_hour' : ''})
    VALUES ($1, $2, $3, $4, 'pending'${extra}) RETURNING id`, [IDS.emp, start, end, type]);

await expectError('end before start is rejected', leave('2026-12-10T00:00:00+03', '2026-12-08T00:00:00+03'), 'بعد تاريخ بدايتها');
// الخميس 3 → الأحد 6 كانون الأول: الجمعة عطلة = 3 أيام عمل
const l1 = (await expectOk('a Thursday–Sunday leave is accepted', leave('2026-12-03T00:00:00+03', '2026-12-06T00:00:00+03'))).rows[0].id;
const days = (await db.query(`SELECT leave_request_days(lr)::float8 d FROM leave_requests lr WHERE id = $1`, [l1])).rows[0].d;
check('Friday is not counted as a leave day', days === 3, String(days));
await expectError('overlapping leave is rejected', leave('2026-12-05T00:00:00+03', '2026-12-07T00:00:00+03'), 'تتداخل');
await expectError('a Friday-only leave is rejected', leave('2026-12-11T00:00:00+03', '2026-12-11T00:00:00+03'), 'عطلة');
await expectError('more days than the balance is rejected',
  leave('2027-01-03T00:00:00+03', '2027-03-31T00:00:00+03'), 'رصيد الإجازة غير كافٍ');
await expectOk('a non-balance leave type is not limited by the balance',
  leave('2027-01-03T00:00:00+03', '2027-01-20T00:00:00+03', 'other'));

await db.exec(`UPDATE leave_balances SET annual_entitlement = 1 WHERE employee_id = '${IDS.emp}'`);
await expectError('approval re-checks the balance', as(db, 'admin',
  `UPDATE leave_requests SET status = 'approved' WHERE id = $1 RETURNING id`, [l1]), 'رصيد الإجازة غير كافٍ');
await db.exec(`UPDATE leave_balances SET annual_entitlement = NULL WHERE employee_id = '${IDS.emp}'`);
await expectOk('approval passes with enough balance', as(db, 'admin',
  `UPDATE leave_requests SET status = 'approved' WHERE id = $1 RETURNING id`, [l1]));
const used = Number((await db.query(`SELECT get_leave_balance($1, '2026-12-03') b`, [IDS.emp])).rows[0].b.annual.used);
check('balance deducts work days only', used === 3, String(used));

await expectOk('hourly leave on a free day is accepted',
  leave('2026-12-14T00:00:00+03', '2026-12-14T00:00:00+03', 'annual', `, true, '09:00', '11:00'`));
await expectError('overlapping hours on the same day are rejected',
  leave('2026-12-14T00:00:00+03', '2026-12-14T00:00:00+03', 'annual', `, true, '10:00', '12:00'`), 'تتداخل');
await expectOk('non-overlapping hours on the same day are accepted',
  leave('2026-12-14T00:00:00+03', '2026-12-14T00:00:00+03', 'annual', `, true, '12:00', '13:00'`));

// ---------------- 4) أوقات البصمة للأدمن فقط ----------------
const att = (await db.query(`INSERT INTO attendance (employee_id, branch_id, status, work_date, check_in_time)
  VALUES ($1, $2, 'late', '2026-12-01', '2026-12-01 09:40+03') RETURNING id`, [IDS.emp, IDS.branch])).rows[0].id;
await expectError('manager cannot move a check-in time', as(db, 'manager',
  `UPDATE attendance SET check_in_time = '2026-12-01 08:55+03' WHERE id = $1 RETURNING id`, [att]), 'للأدمن فقط');
await expectOk('manager can still decide the deduction', as(db, 'manager',
  `UPDATE attendance SET deduction_status = 'ignored', deduction_reason = 'زحام' WHERE id = $1 RETURNING id`, [att]));
await expectOk('admin can correct a check-in time', as(db, 'admin',
  `UPDATE attendance SET check_in_time = '2026-12-01 08:55+03' WHERE id = $1 RETURNING id`, [att]));

// ---------------- 6) المستمسكات: الموظف يضيف فقط، الأدمن يعدّل ويحذف ----------------
const docUrl = (emp, f) => `https://x.supabase.co/storage/v1/object/public/employee-documents/${emp}/${f}`;
const setDocs = (who, urls) => as(db, who,
  `UPDATE employees SET document_urls = $1::jsonb WHERE id = $2 RETURNING id`, [JSON.stringify(urls), IDS.emp]);

await expectOk('admin sets the documents', setDocs('admin', [docUrl(IDS.emp, 'passport.jpg')]));
await expectOk('employee can add a document from own folder',
  setDocs('emp', [docUrl(IDS.emp, 'passport.jpg'), docUrl(IDS.emp, 'id.jpg')]));
await expectError('employee cannot delete a document',
  setDocs('emp', [docUrl(IDS.emp, 'id.jpg')]), 'تقدر تضيف مستمسكات فقط');
await expectError('employee cannot replace a document',
  setDocs('emp', [docUrl(IDS.emp, 'passport2.jpg'), docUrl(IDS.emp, 'id.jpg')]), 'تقدر تضيف مستمسكات فقط');
await expectError('employee cannot add someone else\'s file',
  setDocs('emp', [docUrl(IDS.emp, 'passport.jpg'), docUrl(IDS.emp, 'id.jpg'), docUrl(IDS.emp2, 'x.jpg')]), 'تقدر تضيف مستمسكات فقط');
await expectOk('admin can delete a document', setDocs('admin', [docUrl(IDS.emp, 'id.jpg')]));

const upload = (who, path) => as(db, who,
  `INSERT INTO storage.objects (bucket_id, name) VALUES ('employee-documents', $1) RETURNING name`, [path]);
await expectOk('employee can upload a leave attachment', upload('emp', `leaves/${IDS.emp}/a.jpg`));
await expectOk('employee can upload into own documents folder', upload('emp', `${IDS.emp}/new.jpg`));
await expectError('employee cannot upload into another employee folder', upload('emp', `${IDS.emp2}/x.jpg`), 'row-level security');
await expectError('employee cannot upload into another employee leave folder', upload('emp', `leaves/${IDS.emp2}/a.jpg`), 'row-level security');
await expectError('employee cannot delete a stored file', as(db, 'emp',
  `DELETE FROM storage.objects WHERE name = $1 RETURNING name`, [`${IDS.emp}/new.jpg`]).then((r) => {
  if (r.rows.length === 0) throw new Error('row-level security: nothing deleted');
  return r;
}), 'row-level security');

// ---------------- 7) الزمنيات: رصيد ساعات شهري من السياسة ----------------
// السياسة الافتراضية 8 ساعات/شهر. في كانون الأول سبق طلب 09–11 و 12–13 = 3 ساعات.
const hb = async () => (await db.query(`SELECT get_leave_balance($1, '2026-12-01') b`, [IDS.emp])).rows[0].b.hourly;
check('pending hourly leaves reserve the monthly hours', Number((await hb()).left_hours) === 5, JSON.stringify(await hb()));
await expectError('more hours than left this month is rejected',
  leave('2026-12-16T00:00:00+03', '2026-12-16T00:00:00+03', 'sick', `, true, '08:00', '14:00'`), 'المطلوب 6 ساعة والمتبقي 5 ساعة');
const hl = (await expectOk('a 4-hour leave fits',
  leave('2026-12-16T00:00:00+03', '2026-12-16T00:00:00+03', 'sick', `, true, '09:00', '13:00'`))).rows[0].id;
await as(db, 'admin', `UPDATE leave_requests SET status = 'approved' WHERE id = $1`, [hl]);
check('approved hourly leave counts as used hours, not days',
  Number((await hb()).used_hours) === 4 && Number((await db.query(`SELECT get_leave_balance($1, '2026-12-01') b`, [IDS.emp])).rows[0].b.sick.used) === 0,
  JSON.stringify(await hb()));
check('next month starts with a fresh hours balance',
  Number((await db.query(`SELECT get_leave_balance($1, '2027-01-05') b`, [IDS.emp])).rows[0].b.hourly.left_hours) === 8);

// ---------------- 8) السياسة والتخصيص ----------------
await db.exec(`UPDATE system_settings SET value = value || '{"default_annual": 30, "hourly_monthly_hours": 10}' WHERE key = 'leave_policy'`);
const pb = async (who = 'emp') => (await as(db, who, `SELECT get_leave_balance($1, '2027-03-01') b`, [IDS.emp])).rows[0].b;
check('policy change applies to everyone', Number((await pb()).annual.entitlement) === 30 && Number((await pb()).hourly.allowance_hours) === 10);
await expectError('employee cannot set own entitlement',
  as(db, 'emp', `SELECT set_employee_leave_entitlement($1, 99, 99, 99)`, [IDS.emp]), 'غير مصرح');
await expectOk('admin sets a custom entitlement', as(db, 'admin', `SELECT set_employee_leave_entitlement($1, 40, NULL, 12)`, [IDS.emp]));
check('custom entitlement overrides the policy',
  Number((await pb()).annual.entitlement) === 40 && Number((await pb()).sick.entitlement) === 15 && Number((await pb()).hourly.allowance_hours) === 12);
await expectError('employee cannot read a colleague balance',
  as(db, 'emp', `SELECT get_leave_balance($1)`, [IDS.emp2]), 'غير مصرح');
await expectOk('manager can read an employee balance', as(db, 'manager', `SELECT get_leave_balance($1)`, [IDS.emp]));
check('a new year renews the annual balance', Number((await pb()).annual.used) === 0);

await db.exec(`UPDATE system_settings SET value = jsonb_set(value, '{active_types}', value->'active_types' || '[{"id":"marriage","name":"إجازة زواج"}]') WHERE key = 'leave_policy'`);
await expectOk('a leave type added in settings can be requested',
  leave('2027-02-07T00:00:00+03', '2027-02-08T00:00:00+03', 'marriage'));
await expectError('a type not in the policy is rejected',
  leave('2027-02-14T00:00:00+03', '2027-02-15T00:00:00+03', 'vacation'), 'غير متاح');

// ---------------- 5) الحاويات الخاصة ----------------
await db.exec(`INSERT INTO storage.buckets (id, name, public) VALUES ('employee-documents', 'employee-documents', true)
  ON CONFLICT (id) DO UPDATE SET public = true`).catch(() => {});

done();
