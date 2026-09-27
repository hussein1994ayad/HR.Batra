import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();

// --- update_employee_credentials (account takeover) ---
await expectError('anon cannot call update_employee_credentials',
  as(db, 'anon', `SELECT update_employee_credentials($1, 'hacker@x', 'pw')`, [IDS.admin]), 'permission denied');
await expectError('employee cannot change admin credentials',
  as(db, 'emp', `SELECT update_employee_credentials($1, 'hacker@x', 'pw')`, [IDS.admin]), 'غير مصرح');
await expectOk('admin can update credentials',
  as(db, 'admin', `SELECT update_employee_credentials($1, 'new@x', NULL)`, [IDS.emp]));

// --- create_employee_secure overloads ---
const ov = await db.query(`SELECT count(*)::int n FROM pg_proc WHERE proname = 'create_employee_secure'`);
check('only the guarded create_employee_secure overload remains', ov.rows[0].n === 1, `found ${ov.rows[0].n}`);
await expectError('employee cannot create employees',
  as(db, 'emp', `SELECT create_employee_secure('x@x','p','n','','admin',NULL,1,ARRAY[]::text[],'X9')`), 'غير مصرح');

// --- destructive RPCs ---
await expectError('employee cannot purge month data',
  as(db, 'emp', `SELECT * FROM manual_purge_month_data(2026, 9, true, true, true)`), 'غير مصرح');
await expectError('employee cannot archive payroll month',
  as(db, 'emp', `SELECT safe_archive_payroll_month('2026-09')`), 'غير مصرح');
await expectError('employee cannot run daily cleanup',
  as(db, 'emp', `SELECT * FROM perform_daily_cleanup()`), 'غير مصرح');
await expectOk('admin can run daily cleanup', as(db, 'admin', `SELECT * FROM perform_daily_cleanup()`));
await expectError('employee cannot read storage stats',
  as(db, 'emp', `SELECT * FROM get_database_table_sizes()`), 'غير مصرح');
await expectOk('manager can read storage stats', as(db, 'manager', `SELECT * FROM get_database_size()`));

// --- views respect RLS ---
await db.exec(`INSERT INTO salary_slips (employee_id, work_month, basic_salary, net_salary, status) VALUES
  ('${IDS.emp}', '2026-08', 1000000, 1000000, 'published'),
  ('${IDS.emp2}', '2026-08', 900000, 900000, 'published');`);
const slips = await as(db, 'emp', `SELECT employee_id FROM v_payroll_with_employee`);
check('employee sees only own payroll through view', slips.rows.length === 1 && slips.rows[0].employee_id === IDS.emp,
  JSON.stringify(slips.rows));
await expectError('anon cannot read employee directory view',
  as(db, 'anon', `SELECT * FROM v_employee_directory`), 'permission denied');
const self = await as(db, 'emp', `SELECT id FROM v_employee_directory`);
check('employee sees own row in directory view', self.rows.length === 1);
const dir = await as(db, 'emp', `SELECT * FROM get_employee_directory()`);
check('get_employee_directory lists all active colleagues', dir.rows.length === 4, `got ${dir.rows.length}`);
check('directory exposes no documents/salary', !('document_urls' in dir.rows[0]) && !('monthly_salary_iqd' in dir.rows[0]));
await expectError('anon cannot call get_employee_directory',
  as(db, 'anon', `SELECT * FROM get_employee_directory()`), 'permission denied');

// --- notifications ---
await expectError('employee cannot notify another employee',
  as(db, 'emp', `INSERT INTO notifications (employee_id, title, body, type) VALUES ($1,'t','b','system')`, [IDS.admin]),
  'row-level security');
await expectOk('employee can notify self',
  as(db, 'emp', `INSERT INTO notifications (employee_id, title, body, type) VALUES ($1,'t','b','system')`, [IDS.emp]));
await expectOk('admin can notify anyone',
  as(db, 'admin', `INSERT INTO notifications (employee_id, title, body, type) VALUES ($1,'t','b','system')`, [IDS.emp]));
await expectError('employee cannot send idempotent notification to others',
  as(db, 'emp', `SELECT send_idempotent_notification($1,'t','b','system')`, [IDS.admin]), 'غير مصرح');

// --- archived_months ---
await expectError('employee cannot lock a payroll month',
  as(db, 'emp', `INSERT INTO archived_months (work_month) VALUES ('2026-01')`), 'row-level security');
await expectOk('employee can read archived months', as(db, 'emp', `SELECT * FROM archived_months`));

// --- schedules readable ---
await db.exec(`INSERT INTO work_schedules (branch_id, name, check_in_time, check_out_time, work_days)
  VALUES ('${IDS.branch}', 'عام', '08:00', '16:00', '{0,1,2,3,4}')`);
const ws = await as(db, 'emp', `SELECT * FROM work_schedules`);
check('employee can read work schedules', ws.rows.length === 1);

done();
