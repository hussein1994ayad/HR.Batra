// المرحلة 10 الجزء الثاني (تدقيق 14/10): الملفات تطابق السيرفر الحي (6 اختلافات قديمة)، وحذف الجداول اللي ما يستعملها شي.
import fs from 'node:fs';
import { IDS, buildFromFiles, check, done, expectError, setup, sqlFiles } from './lib.mjs';

const db = await setup();
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];

// ---------------- الملفات = السيرفر الحي ----------------
const col = (t, c) => one(`SELECT column_default d, is_nullable n FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2`, [t, c]);
check('1) join date has no hidden default (like live)', (await col('employees', 'join_date')).d === null);
check('   geofence zone "active" may be empty (like live)', (await col('geofence_zones', 'is_active')).n === 'YES');
check('   installments default to salary deduction (like live)', String((await col('loan_installments', 'payment_type')).d).includes('salary_deduction'));
check('   the employee directory keeps its description', !!(await one(`SELECT obj_description('public.v_employee_directory'::regclass) c`)).c);
const pledge = await one(`SELECT with_check w FROM pg_policies WHERE schemaname = 'storage' AND policyname = 'Employees can upload loan pledges'`);
check('   a loan pledge is uploaded into the employee\'s own folder (like live)', /foldername\(name\)\)\[2\]/.test(pledge?.w ?? ''), pledge?.w);
const bucket = await one(`SELECT public, file_size_limit FROM storage.buckets WHERE id = 'employee-documents'`);
check('   the employee documents storage exists and is private', bucket && bucket.public === false && Number(bucket.file_size_limit) === 10485760, JSON.stringify(bucket));

// ---------------- الجداول المحذوفة ----------------
const gone = await one(`SELECT to_regclass('public.tracking_schedules') a, to_regclass('public.employee_geofence_assignments') b,
  to_regclass('public.device_tokens') c`);
check('2) old tracking schedules, geofence assignments and the second token copy are gone', gone.a === null && gone.b === null && gone.c === null, JSON.stringify(gone));

// العمود القديم يبقى للنسخة الحالية من التطبيق، ونقله للمكان الواحد يشتغل
await db.query(`UPDATE employees SET fcm_token = 'tok-current-app' WHERE id = $1`, [IDS.emp]);
check('   the legacy token column still lands in the one place (until part 3)',
  (await db.query(`SELECT 1 FROM fcm_tokens WHERE employee_id = $1 AND token = 'tok-current-app'`, [IDS.emp])).rows.length === 1);

// إخفاء هوية موظف محذوف ما يعتمد على الجدول المحذوف
await db.query(`INSERT INTO fcm_tokens (employee_id, token) VALUES ($1, 'tok-e2')`, [IDS.emp2]);
await db.query(`SELECT _anonymize_employee($1)`, [IDS.emp2]);
const anon = await one(`SELECT full_name, is_active FROM employees WHERE id = $1`, [IDS.emp2]);
const left = await one(`SELECT (SELECT count(*) FROM fcm_tokens WHERE employee_id = $1)::int t, (SELECT count(*) FROM auth.users WHERE id = $1)::int u`, [IDS.emp2]);
check('   deleting an employee\'s identity still works', anon.full_name === 'مستخدم محذوف' && anon.is_active === false && left.t === 0 && left.u === 0, JSON.stringify({ anon, left }));

// ---------------- الحذف محمي، والرموز الباقية تنتقل ----------------
const files = sqlFiles(new URL('../migrations', import.meta.url));
const cleanup = files.find((f) => f.pathname.endsWith('_drop_unused_tracking_and_device_tokens.sql'));
const before = files.filter((f) => f.pathname < cleanup.pathname);

const seed = `
  INSERT INTO branches (id, name, latitude, longitude, radius_meters) VALUES ('${IDS.branch}', 'ف', 33.3, 44.4, 100);
  INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, must_change_password)
    VALUES ('${IDS.emp}', 'E1', 'موظف', 'employee', '${IDS.branch}', 1000000, false);`;
const t1 = await buildFromFiles(before);
await t1.exec(`${seed}
  INSERT INTO tracking_schedules (employee_id, start_time, end_time, tracking_days) VALUES ('${IDS.emp}', '08:00', '16:00', '{0,1,2}');`);
await expectError('3) with data in the old tracking table the cleanup stops and deletes nothing',
  t1.exec(fs.readFileSync(cleanup, 'utf8')), 'tracking_schedules');
check('   ...and the table is still there', (await t1.query(`SELECT to_regclass('public.tracking_schedules') a`)).rows[0].a !== null);

const t2 = await buildFromFiles(before);
await t2.exec(`${seed}
  ALTER TABLE device_tokens DISABLE TRIGGER trg_copy_legacy_push_token;
  INSERT INTO device_tokens (employee_id, token, platform) VALUES ('${IDS.emp}', 'tok-left-behind', 'android');`);
await t2.exec(fs.readFileSync(cleanup, 'utf8'));
const moved = (await t2.query(`SELECT device_platform p FROM fcm_tokens WHERE employee_id = $1 AND token = 'tok-left-behind'`, [IDS.emp])).rows[0];
check('   a token left in the old table moves to the one place before the table is dropped', moved?.p === 'android', JSON.stringify(moved));

done();
