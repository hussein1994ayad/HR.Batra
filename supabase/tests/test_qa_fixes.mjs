// تصليحات الفحص الشامل (2 تشرين الأول 2026): القفل المالي للتنظيف، العطل، حدود السلف والخصومات،
// الحضور، بيانات الموظف، تغيير الراتب، ومدير الفرع.
import { setup, as as asRaw, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
// بعد كل عملية كمستخدم نرجع لهوية فارغة حتى ما تتسرب لعمليات الإعداد
const as = async (d, who, sql, p = []) => {
  try { return await asRaw(d, who, sql, p); }
  finally { await d.exec("SELECT set_config('request.jwt.claim.sub','',false), set_config('request.jwt.claim.role','',false)"); }
};
const q = async (s, p = []) => (await db.query(s, p)).rows;
const B2 = '00000000-0000-0000-0000-0000000000b2';
await db.exec(`
  UPDATE system_settings SET value = value || '{"no_record_from": "2027-01-01"}' WHERE key = 'payroll_policy';
  UPDATE employees SET join_date = '2026-01-01';
  INSERT INTO work_schedules (employee_id, name, check_in_time, check_out_time, grace_period_minutes, work_days)
    VALUES ('${IDS.emp}', 'ص', '09:00', '17:00', 15, '{0,1,2,3,4,6}'), ('${IDS.emp2}', 'ص', '09:00', '17:00', 15, '{0,1,2,3,4,6}');
  INSERT INTO branches (id, name, latitude, longitude, radius_meters) VALUES ('${B2}', 'فرع ثاني', 30.5, 47.8, 100);
`);
const absEv = async (emp, d) => q(`SELECT amount::int a FROM payroll_events WHERE employee_id=$1 AND event_date=$2 AND event_type='absence' AND status<>'void'`, [emp, d]);

// 1) القفل المالي: حذف حضور شهر مسيره مفتوح مرفوض
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time, deduction_status)
  VALUES ($1, $2, '2026-09-14', 'late', '2026-09-14 10:00+03', '2026-09-14 17:00+03', 'applied')`, [IDS.emp, IDS.branch]);
await expectError('1) purging attendance of a month whose payroll is still open is refused',
  as(db, 'admin', `SELECT * FROM manual_purge_month_data(2026, 9, false, false, true)`), 'مفتوحاً');
check('   the attendance is still there', (await q(`SELECT 1 FROM attendance WHERE employee_id=$1 AND work_date='2026-09-14'`, [IDS.emp])).length === 1);
await expectOk('   notifications/GPS only (no attendance) is still allowed',
  as(db, 'admin', `SELECT * FROM manual_purge_month_data(2026, 9, true, true, false)`));

// 2) غياب مسجّل ثم أُعلنت عطلة رسمية → الخصم يختفي
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status) VALUES ($1, $2, '2026-09-16', 'absent', 'applied')`, [IDS.emp, IDS.branch]);
check('2) absence on a work day is deducted', (await absEv(IDS.emp, '2026-09-16')).length === 1);
await db.exec(`INSERT INTO official_holidays (holiday_date, name) VALUES ('2026-09-16', 'عطلة')`);
check('   declaring that day a holiday removes the deduction', (await absEv(IDS.emp, '2026-09-16')).length === 0);
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status) VALUES ($1, $2, '2026-09-18', 'absent', 'applied')`, [IDS.emp, IDS.branch]);
check('   an absence recorded on a Friday (day off) is not deducted', (await absEv(IDS.emp, '2026-09-18')).length === 0);

// 3) طلب السلفة بنفس شروط الاعتماد
const req = (who, amount, inst, n) => as(db, who, `INSERT INTO loans (employee_id, amount, installment_amount, installment_count, remaining_amount, pledge_url, status)
  VALUES ($1, $2, $3, $4, $2, 'x', 'pending') RETURNING id`, [IDS[who], amount, inst, n]);
await expectError('3) a 900-billion request is refused (installment over 50% of salary)', req('emp', 900000000000, 100000000000, 9), '50%');
await expectOk('   a reasonable request is accepted', req('emp', 1000000, 250000, 4));

// 4) الخصم أكبر من الراتب مرفوض، والمكافأة الضخمة مرفوضة
const bd = (type, amount) => as(db, 'admin', `INSERT INTO bonuses_deductions (employee_id, type, amount, reason, issue_date) VALUES ($1, $2, $3, 'qa', '2026-09-15')`, [IDS.emp, type, amount]);
await expectError('4) a deduction larger than the monthly salary is refused', bd('deduction', 99999999999), 'أكبر من راتب');
await expectError('   a 99-billion bonus is refused', bd('bonus', 99999999999), 'كبير جداً');
await expectOk('   a normal deduction is accepted', bd('deduction', 50000));

// 5) الحضور
await expectError('5) check-out before check-in is refused', as(db, 'admin', `INSERT INTO attendance (employee_id, branch_id, work_date, status, check_in_time, check_out_time)
  VALUES ($1, $2, '2026-09-21', 'present', '2026-09-21 17:00+03', '2026-09-21 09:00+03')`, [IDS.emp2, IDS.branch]), 'بعد وقت الحضور');
await expectError('   recording a future day is refused', as(db, 'admin', `INSERT INTO attendance (employee_id, branch_id, work_date, status)
  VALUES ($1, $2, '2027-05-01', 'absent')`, [IDS.emp2, IDS.branch]), 'لم يأتِ بعد');

// 6) بيانات الموظف
await expectError('6) blank employee name is refused', as(db, 'admin', `UPDATE employees SET full_name='  ' WHERE id=$1`, [IDS.emp2]), 'اسم الموظف مطلوب');
await expectError('   termination before joining is refused', as(db, 'admin', `UPDATE employees SET termination_date='2025-06-01' WHERE id=$1`, [IDS.emp2]), 'قبل تاريخ المباشرة');

// 7) تغيير الراتب يعيد حساب الغياب بالمسير المفتوح
await db.query(`INSERT INTO attendance (employee_id, branch_id, work_date, status, deduction_status) VALUES ($1, $2, '2026-09-22', 'absent', 'applied')`, [IDS.emp2, IDS.branch]);
check('7) absence at the old daily rate (900,000 / 30 = 30,000)', (await absEv(IDS.emp2, '2026-09-22'))[0]?.a === 30000);
await db.exec(`UPDATE employees SET monthly_salary_iqd = 1500000 WHERE id='${IDS.emp2}'`);
check('   after a raise the open payroll uses the new rate (50,000)', (await absEv(IDS.emp2, '2026-09-22'))[0]?.a === 50000, JSON.stringify(await absEv(IDS.emp2, '2026-09-22')));

// 8) مدير الفرع يقرأ موظفين فرعه فقط
await db.exec(`INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, must_change_password)
  VALUES ('00000000-0000-0000-0000-0000000000f9', 'X9', 'موظف فرع ثاني', 'employee', '${B2}', 700000, false)`);
const seen = (await as(db, 'manager', `SELECT count(*)::int c FROM employees WHERE branch_id=$1`, [B2])).rows[0].c;
check('8) branch manager cannot read employees of another branch', seen === 0, `seen=${seen}`);
const own = (await as(db, 'manager', `SELECT count(*)::int c FROM employees WHERE branch_id=$1`, [IDS.branch])).rows[0].c;
check('   but still reads his own branch', own > 1, `own=${own}`);
const dir = (await as(db, 'emp', `SELECT count(*)::int c FROM get_employee_directory()`)).rows[0].c;
check('   the employee directory still lists everyone', dir >= 5, `dir=${dir}`);

done();
