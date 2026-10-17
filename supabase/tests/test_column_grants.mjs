// حماية دائمة (تدقيق 14/10/2026): أعمدة الراتب والمبالغ ما تنقرا مباشرة، وأي عمود جديد لازم ينقرر.
// جدول الموظفين وحركات الرواتب صلاحية قراءتهم عمود عمود. عمود جديد بدون قرار = هذا الفحص يفشل ويقول شنو تسوي.
import fs from 'node:fs';
import { setup, check, done } from './lib.mjs';

const db = await setup();
const repo = new URL('../../', import.meta.url);
const read = (p) => fs.readFileSync(new URL(p, repo), 'utf8');

// الأعمدة المخفية عن القراءة المباشرة (تنقرا من get_employee_pay / get_payroll_event_amounts بس)
const HIDDEN = {
  employees: ['monthly_salary_iqd', 'future_salary_iqd', 'future_salary_month', 'plain_password'],
  payroll_events: ['amount', 'amount_override', 'daily_rate', 'minute_rate'],
};

const granted = {};
for (const table of Object.keys(HIDDEN)) {
  const cols = (await db.query(`SELECT column_name c FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1`, [table])).rows.map((r) => r.c);
  const readable = (await db.query(`SELECT column_name c FROM information_schema.column_privileges
    WHERE table_schema = 'public' AND table_name = $1 AND grantee = 'authenticated' AND privilege_type = 'SELECT'`, [table])).rows.map((r) => r.c);
  granted[table] = readable;
  const leaked = HIDDEN[table].filter((c) => readable.includes(c));
  check(`${table}: the hidden money columns are not readable directly`, leaked.length === 0, `مكشوفة: ${leaked.join(', ')}`);
  const undecided = cols.filter((c) => !readable.includes(c) && !HIDDEN[table].includes(c));
  check(`${table}: every column is either readable or hidden on purpose`, undecided.length === 0,
    `عمود جديد بدون قرار: ${undecided.join(', ')} — إذا ينقرا: GRANT SELECT (عمود) بملف migration جديد` +
    (table === 'employees' ? ' + أضفه لـ EMPLOYEE_COLUMNS (web/src/lib/employeePay.ts) و kEmployeeColumns (mobile/lib/data/repositories/employee_pay.dart)' : '') +
    '؛ وإذا مخفي: أضفه لقائمة HIDDEN بهذا الفحص.');
}

// قائمة الأعمدة بالموقع والتطبيق = نفس المسموح بالقاعدة (وإلا الشاشة تطلب عمود ممنوع أو تنسى عمود).
// LEGACY: مسموح بالقاعدة بس للنسخ القديمة من التطبيق، والكود الحالي ما يطلبه (ينحذف بالمرحلة 10 الجزء الثالث).
const LEGACY = { employees: ['fcm_token'] };
const listOf = (src, re) => (src.match(re)?.[1] ?? '').replace(/['+\s\n]/g, '').split(',').filter(Boolean).sort();
const webCols = listOf(read('web/src/lib/employeePay.ts'), /EMPLOYEE_COLUMNS\s*=\s*([\s\S]*?);/);
const appCols = listOf(read('mobile/lib/data/repositories/employee_pay.dart'), /kEmployeeColumns\s*=\s*([\s\S]*?);/);
const dbCols = granted.employees.filter((c) => !LEGACY.employees.includes(c)).sort();
check('the website employee columns match the database', JSON.stringify(webCols) === JSON.stringify(dbCols), `web=${webCols} db=${dbCols}`);
check('the app employee columns match the database', JSON.stringify(appCols) === JSON.stringify(dbCols), `app=${appCols} db=${dbCols}`);

// ما أحد بالموقع والتطبيق يطلب عمود مخفي مباشرة (غير القراءة الاحتياطية قبل تحديث القاعدة)
const FALLBACK_FILES = ['web/src/lib/employeePay.ts', 'mobile/lib/data/repositories/employee_pay.dart',
  'web/src/features/tracking/api.ts', 'mobile/lib/data/repositories/admin_dashboard_repository.dart'];
const files = [];
const walk = (dir) => {
  for (const e of fs.readdirSync(new URL(dir, repo), { withFileTypes: true })) {
    const p = `${dir}/${e.name}`;
    if (e.isDirectory()) walk(p);
    else if (/\.(ts|tsx|dart)$/.test(e.name) && !/\.test\.|_test\.dart/.test(e.name)) files.push(p);
  }
};
walk('web/src');
walk('mobile/lib');
const offenders = [];
for (const f of files) {
  const src = read(f);
  // أي select (بالموقع أو التطبيق، سطر واحد أو أكثر) فيه عمود راتب
  for (const m of src.matchAll(/select\(\s*(?:'''([\s\S]*?)'''|'([^']*)'|`([^`]*)`|"([^"]*)")/g)) {
    const cols = m[1] ?? m[2] ?? m[3] ?? m[4] ?? '';
    if (HIDDEN.employees.some((c) => cols.includes(c)) && !FALLBACK_FILES.includes(f)) offenders.push(`${f}: ${cols.trim().slice(0, 60)}`);
  }
  // select من حركات الرواتب فيه مبلغ أو أجر
  for (const m of src.matchAll(/from\(\s*'payroll_events'\s*\)\s*\.select\(\s*'([^']*)'/g)) {
    const cols = m[1].split(',').map((c) => c.trim());
    if (cols.some((c) => c === '*' || HIDDEN.payroll_events.includes(c)) && !FALLBACK_FILES.includes(f)) offenders.push(`${f}: payroll_events(${m[1]})`);
  }
}
check('no screen reads a hidden money column directly', offenders.length === 0, offenders.join(' | '));

done();
