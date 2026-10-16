// تدقيق 14/10/2026 — المرحلة 6: ملفات الموظف وعملياته.
// (BUG-009) المستمسك المشال يروح للسلة بس بعد ما ينحفظ التعديل، (BUG-008) الحذف النهائي يحط مستمسكاته وصورته بالسلة،
// (BUG-010) رقم الموظف بالتسلسل، (CODE-005) تعديل/إنهاء/استرجاع/إتلاف بخطوة وحدة، (BUG-019) كود مؤقت لدالة التنظيف.
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];
const BASE = 'https://x.supabase.co/storage/v1/object/public';
const doc = (emp, name) => `${BASE}/employee-documents/${emp}/${name}`;
const putFile = (bucket, path, size = 1000) =>
  q(`INSERT INTO storage.objects (bucket_id, name, metadata) VALUES ($1, $2, jsonb_build_object('size', $3::text))`, [bucket, path, size]);
const trash = (path) => q(`SELECT file_type, related_id, file_size_bytes::int s, (scheduled_deletion_date - now() > interval '29 days') later
  FROM deleted_files WHERE file_path = $1 AND restored_at IS NULL`, [path]);

const newEmp = async (code, extra = {}) => {
  const id = (await one('SELECT gen_random_uuid()::text id')).id;
  await q(`INSERT INTO auth.users (id, email) VALUES ($1, $2)`, [id, `${code}@x`]);
  await q(`INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, join_date, must_change_password, email, document_urls, avatar_url)
    VALUES ($1, $2, $3, 'employee', $4, 600000, '2026-01-01', false, $5, $6::jsonb, $7)`,
    [id, extra.code === undefined ? code : extra.code, code, IDS.branch, `${code}@x`, JSON.stringify(extra.docs ?? []), extra.avatar ?? null]);
  return id;
};

// ---------------- 1) BUG-009: المستمسك المشال يروح للسلة بعد الحفظ بس ----------------
const E = await newEmp('F1');
await putFile('employee-documents', `${E}/a.jpg`, 1111);
await putFile('employee-documents', `${E}/b.jpg`, 2222);
await q(`UPDATE employees SET document_urls = $2::jsonb WHERE id = $1`, [E, JSON.stringify([doc(E, 'a.jpg'), doc(E, 'b.jpg'), doc(E, 'gone.jpg')])]);
await expectOk('1) the admin removes one document and saves', as(db, 'admin', `UPDATE employees SET document_urls = $2::jsonb WHERE id = $1`, [E, JSON.stringify([doc(E, 'a.jpg'), doc(E, 'gone.jpg')])]));
const tb = await trash(`${E}/b.jpg`);
check('   the removed file is in the trash for 30 days (with its size), not deleted', tb.length === 1 && tb[0].file_type === 'document' && tb[0].s === 2222 && tb[0].later && tb[0].related_id === E, JSON.stringify(tb));
check('   the file itself is still in storage (restorable)', (await q(`SELECT 1 FROM storage.objects WHERE name = $1`, [`${E}/b.jpg`])).length === 1);
await expectError('   a save that fails (empty name) ...', as(db, 'admin', `SELECT save_employee($1, 'f1@x', '', '', $2::jsonb)`,
  [E, JSON.stringify({ full_name: '', document_urls: [] })]));
check('   ... puts nothing in the trash and keeps the documents', (await trash(`${E}/a.jpg`)).length === 0
  && (await one(`SELECT jsonb_array_length(document_urls) n FROM employees WHERE id = $1`, [E])).n === 2);
await q(`UPDATE employees SET document_urls = $2::jsonb WHERE id = $1`, [E, JSON.stringify([doc(E, 'a.jpg')])]);
check('   a link to a file that is not in storage adds nothing', (await trash(`${E}/gone.jpg`)).length === 0);
await q(`UPDATE employees SET document_urls = $2::jsonb WHERE id = $1`, [E, JSON.stringify([doc(E, 'a.jpg'), doc(E, 'b.jpg')])]);
await q(`UPDATE employees SET document_urls = $2::jsonb WHERE id = $1`, [E, JSON.stringify([doc(E, 'a.jpg')])]);
check('   removing the same file again does not add a second trash row', (await trash(`${E}/b.jpg`)).length === 1);
// الموظف ما يكدر يشيل مستمسكه بنفسه (قاعدة موجودة: الحذف من الموارد البشرية)
await putFile('employee-documents', `${IDS.emp}/self.jpg`);
await q(`UPDATE employees SET document_urls = $2::jsonb WHERE id = $1`, [IDS.emp, JSON.stringify([doc(IDS.emp, 'self.jpg')])]);
await expectError('   an employee cannot remove his own document (only HR can; existing rule)', as(db, 'emp', `UPDATE employees SET document_urls = '[]'::jsonb WHERE id = $1`, [IDS.emp]), 'الموارد البشرية');
check('   ...so nothing goes to the trash', (await trash(`${IDS.emp}/self.jpg`)).length === 0);
// الصورة الشخصية: التبديل يتكفل بيه التطبيق، الشيل (الحذف النهائي) للسلة
await putFile('avatars', `${E}/p1.jpg`);
await q(`UPDATE employees SET avatar_url = $2 WHERE id = $1`, [E, `${BASE}/avatars/${E}/p1.jpg?t=1`]);
await q(`UPDATE employees SET avatar_url = $2 WHERE id = $1`, [E, `${BASE}/avatars/${E}/p2.jpg`]);
check('   changing the photo does not trash anything (the app handles it)', (await trash(`${E}/p1.jpg`)).length === 0);

// ---------------- 2) CODE-005: تعديل الموظف بخطوة وحدة ----------------
const B2 = (await one(`INSERT INTO branches (name, latitude, longitude, radius_meters) VALUES ('فرع ثاني', 33.3, 44.4, 100) RETURNING id`)).id;
await expectOk('2) the admin saves email, name, branch, salary and documents in one step', as(db, 'admin',
  `SELECT save_employee($1, 'new-f1@x', '', '0770', $2::jsonb)`,
  [E, JSON.stringify({ full_name: 'فاطمة', branch_id: B2, department_id: null, monthly_salary_iqd: 700000, future_salary_iqd: null, future_salary_month: null, document_urls: [] })]));
const e2 = await one(`SELECT full_name, branch_id, monthly_salary_iqd::int s, email, phone, department_id FROM employees WHERE id = $1`, [E]);
const u2 = await one(`SELECT email FROM auth.users WHERE id = $1`, [E]);
check('   everything is saved', e2.full_name === 'فاطمة' && e2.branch_id === B2 && e2.s === 700000 && e2.email === 'new-f1@x' && u2.email === 'new-f1@x',
  JSON.stringify([e2, u2]));
check('   ...and the removed document went to the trash', (await trash(`${E}/a.jpg`)).length === 1);
await expectError('   if one part fails nothing changes (the login email stays the same)', as(db, 'admin',
  `SELECT save_employee($1, 'other@x', '', '', $2::jsonb)`, [E, JSON.stringify({ role: 'boss' })]));
check('   ...email not changed', (await one(`SELECT email FROM auth.users WHERE id = $1`, [E])).email === 'new-f1@x');
await expectError('   an unknown field is refused', as(db, 'admin', `SELECT save_employee($1, 'new-f1@x', '', '', $2::jsonb)`, [E, '{"is_active": false}']), 'ما ينحفظ');
await expectError('   a branch manager cannot use it', as(db, 'manager', `SELECT save_employee($1, 'x@x', '', '', '{}'::jsonb)`, [E]), 'غير مصرح');

// ---------------- 3) CODE-005 + BUG-008: إنهاء الخدمات، الاسترجاع، الإتلاف ----------------
const A = await newEmp('F2');
await expectOk('3) archive (the default option) works in one step', as(db, 'admin', `SELECT end_employee_service($1, 'archive', NULL, '2026-10-10')`, [A]));
const arch = await one(`SELECT id, archive_type, full_name FROM archived_employees WHERE employee_id = $1`, [A]);
const ea = await one(`SELECT is_active, termination_date::text t FROM employees WHERE id = $1`, [A]);
check('   archived (type «archived»), inactive, last day saved', arch?.archive_type === 'archived' && ea.is_active === false && ea.t === '2026-10-10', JSON.stringify([arch, ea]));
const rr = await expectOk('   restore with a return date', as(db, 'admin', `SELECT restore_archived_employee($1, CURRENT_DATE) r`, [arch.id]));
check('   active again and gone from the archive', (await one(`SELECT is_active FROM employees WHERE id = $1`, [A])).is_active === true
  && (await q(`SELECT 1 FROM archived_employees WHERE id = $1`, [arch.id])).length === 0 && rr?.rows[0].r.gap_days >= 0, JSON.stringify(rr?.rows[0]));
await expectOk('   scheduled deletion', as(db, 'admin', `SELECT end_employee_service($1, 'scheduled', 'استقالة')`, [A]));
const sch = await one(`SELECT id, archive_type, archive_reason, scheduled_deletion_date > now() + interval '29 days' later FROM archived_employees WHERE employee_id = $1`, [A]);
check('   ...is recorded for 30 days with the reason', sch.archive_type === 'scheduled_deletion' && sch.later && sch.archive_reason === 'استقالة', JSON.stringify(sch));
await expectOk('   destroy from the archive', as(db, 'admin', `SELECT destroy_archived_employee($1)`, [sch.id]));
check('   anonymized and marked permanent', (await one(`SELECT full_name FROM employees WHERE id = $1`, [A])).full_name === 'مستخدم محذوف'
  && (await one(`SELECT archive_type FROM archived_employees WHERE id = $1`, [sch.id])).archive_type === 'permanent');
await expectError('   a permanently deleted employee cannot be restored', as(db, 'admin', `SELECT restore_archived_employee($1)`, [sch.id]), 'نهائياً');

const D = await newEmp('F3', { docs: [], avatar: null });
await putFile('employee-documents', `${D}/id.jpg`);
await putFile('avatars', `${D}/me.jpg`);
await q(`UPDATE employees SET document_urls = $2::jsonb, avatar_url = $3 WHERE id = $1`, [D, JSON.stringify([doc(D, 'id.jpg')]), `${BASE}/avatars/${D}/me.jpg`]);
await expectOk('   (BUG-008) immediate deletion', as(db, 'admin', `SELECT end_employee_service($1, 'immediate', NULL, '2026-10-12')`, [D]));
check('   his documents and photo are in the trash (deleted after 30 days)', (await trash(`${D}/id.jpg`)).length === 1 && (await trash(`${D}/me.jpg`))[0]?.file_type === 'avatar');
const ad = await one(`SELECT archive_type, full_name FROM archived_employees WHERE employee_id = $1`, [D]);
check('   the archive keeps his real name, the account is anonymized', ad.archive_type === 'permanent' && ad.full_name === 'F3'
  && (await one(`SELECT full_name FROM employees WHERE id = $1`, [D])).full_name === 'مستخدم محذوف' && (await q(`SELECT 1 FROM auth.users WHERE id = $1`, [D])).length === 0);
await expectError('   the admin cannot end his own service', as(db, 'admin', `SELECT end_employee_service($1, 'archive')`, [IDS.admin]), 'بنفسك');
await expectError('   a branch manager cannot end a service', as(db, 'manager', `SELECT end_employee_service($1, 'archive')`, [IDS.emp2]), 'غير مصرح');
await expectError('   an unknown type is refused', as(db, 'admin', `SELECT end_employee_service($1, 'fire')`, [IDS.emp2]), 'غير معروف');

// ---------------- 4) BUG-010: رقم الموظف بالتسلسل ----------------
await q(`UPDATE employees SET employee_code = 'EMP-007' WHERE id = $1`, [IDS.emp2]);
await q(`SELECT setval('employee_code_seq', 7)`); // مثل الترحيل: يكمل بعد أكبر رقم موجود
const n1 = await newEmp('N1', { code: null });
const n2 = await newEmp('N2', { code: '' });
const codes = (await q(`SELECT employee_code c FROM employees WHERE id IN ($1, $2) ORDER BY employee_code`, [n1, n2])).map((r) => r.c);
check('4) without a code: the next numbers in order', JSON.stringify(codes) === JSON.stringify(['EMP-008', 'EMP-009']), JSON.stringify(codes));
const typed = await newEmp('N3', { code: 'SALES-1' });
check('   a typed code is kept', (await one(`SELECT employee_code c FROM employees WHERE id = $1`, [typed])).c === 'SALES-1');
await q(`INSERT INTO auth.users (id, email) VALUES ('00000000-0000-0000-0000-0000000000d9', 'taken@x')`);
await q(`INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, must_change_password) VALUES ('00000000-0000-0000-0000-0000000000d9', 'EMP-010', 'محجوز', 'employee', $1, 1, false)`, [IDS.branch]);
check('   a number already taken is skipped', (await one(`SELECT employee_code c FROM employees WHERE id = $1`, [await newEmp('N4', { code: null })])).c === 'EMP-011');

// ---------------- 5) BUG-019: كود مؤقت لدالة التنظيف ----------------
const tok = await one(`SELECT issue_cleanup_token()::text t`);
check('5) the scheduled job gets a one-time code', /^[0-9a-f-]{36}$/.test(tok.t) && (await q(`SELECT 1 FROM cleanup_run_tokens WHERE token = $1::uuid`, [tok.t])).length === 1);
await q(`INSERT INTO cleanup_run_tokens (token, created_at) VALUES (gen_random_uuid(), now() - interval '2 days')`);
await q(`SELECT issue_cleanup_token()`);
check('   old codes are cleared', (await one(`SELECT count(*)::int c FROM cleanup_run_tokens WHERE created_at < now() - interval '1 day'`)).c === 0);
await expectError('   nobody can issue a code from outside (admin)', as(db, 'admin', `SELECT issue_cleanup_token()`));
await expectError('   ...or read the codes (anonymous)', as(db, 'anon', `SELECT token FROM cleanup_run_tokens`));

done();
