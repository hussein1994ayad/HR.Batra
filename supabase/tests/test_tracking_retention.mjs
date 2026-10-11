// عمر بيانات التتبع برقم واحد من الإعدادات (45 يوم)، والتنظيف اليومي هو اللي يحذف.
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const q = async (sql, p = []) => (await db.query(sql, p)).rows;
const one = async (sql, p = []) => (await q(sql, p))[0];
const days = async () => Number((await one(`SELECT value ->> 'tracking_archive_days' d FROM system_settings WHERE key = 'archive_policy'`)).d);
const seed = async () => {
  await q(`DELETE FROM location_tracking WHERE true`);
  await q(`INSERT INTO location_tracking (employee_id, latitude, longitude, "timestamp") VALUES
    ($1, 33.3, 44.4, now() - interval '70 days'), ($1, 33.3, 44.4, now() - interval '50 days'),
    ($1, 33.3, 44.4, now() - interval '40 days'), ($1, 33.3, 44.4, now() - interval '1 day')`, [IDS.emp]);
};
const left = async () => Number((await one(`SELECT count(*)::int c FROM location_tracking`)).c);

check('1) the retention setting is 45 days', (await days()) === 45, String(await days()));

await seed();
await q(`SELECT public.perform_daily_cleanup()`);
check('2) the daily cleanup deletes points older than the setting and keeps the rest (70d and 50d go, 40d and 1d stay)', (await left()) === 2, String(await left()));

await seed();
const purged = Number((await one(`SELECT public.purge_old_location_tracking() n`)).n);
check('   the old monthly function follows the same setting (no fixed 90 days)', purged === 2 && (await left()) === 2, `${purged}/${await left()}`);

await expectOk('3) the admin can set 60 days from the settings page',
  as(db, 'admin', `UPDATE system_settings SET value = '{"tracking_archive_days": 60}' WHERE key = 'archive_policy'`));
await seed();
await q(`SELECT public.perform_daily_cleanup()`);
check('   ...then only the 70-day point goes', (await days()) === 60 && (await left()) === 3, String(await left()));

await expectError('4) less than 35 days is refused (an open payroll period still needs its points)',
  as(db, 'admin', `UPDATE system_settings SET value = '{"tracking_archive_days": 10}' WHERE key = 'archive_policy'`), 'بين 35 و 366');
await expectError('   ...and more than a year too',
  as(db, 'admin', `UPDATE system_settings SET value = '{"tracking_archive_days": 900}' WHERE key = 'archive_policy'`), 'بين 35 و 366');
check('   the setting is unchanged after the refused values', (await days()) === 60);
await expectOk('   other settings are not affected by the check',
  as(db, 'admin', `UPDATE system_settings SET value = value || '{"x": 1}' WHERE key = 'payroll_policy'`));

await done();
