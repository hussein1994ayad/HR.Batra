// يولّد supabase/schema/current_functions.sql: النسخة الحالية من كل دالة و trigger بقاعدة البيانات.
//
// ليش؟ الدوال تتعرّف من جديد بـ migrations لاحقة (مثلاً sync_payroll_day بـ 10 ملفات)، فقراءة ملف migration
// قديم تعطي قاعدة ملغية. هذا الملف للقراءة فقط — أي تعديل يصير بـ migration جديد، ثم نعيد التوليد.
//
// التشغيل (يبني القاعدة من ملفات migrations بـ PGlite، بدون تسجيل دخول ولا اتصال):
//   node supabase/schema/generate.mjs           ← يكتب الملف
//   node supabase/schema/generate.mjs --check   ← (بالفحص التلقائي) يفشل إذا الملف مو محدّث
//   node supabase/schema/generate.mjs --live    ← من القاعدة الحية (بعد supabase link)، للمقارنة بس
// تدقيق 14/10 CODE-001: كان يتولد من القاعدة الحية بس، فبقى قديم (112 دالة والحية 180).
// يحتاج: cd supabase/tests && npm ci

import { execSync } from 'node:child_process';
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, '..', 'migrations');
const outFile = join(here, 'current_functions.sql');
const live = process.argv.includes('--live');
const checkOnly = process.argv.includes('--check');

async function rows(file) {
  const sql = readFileSync(join(here, file), 'utf8');
  if (live) {
    const out = execSync(`npx supabase db query --linked -f "${join(here, file)}" --output-format json`, {
      cwd: join(here, '..', '..'),
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
    });
    return JSON.parse(out.slice(out.indexOf('{'))).rows;
  }
  db ??= await (await import('../tests/lib.mjs')).buildSchema();
  return (await db.query(sql)).rows;
}
let db = null;

// آخر ملف migration يعرّف كل دالة (الملفات مرتبة بالاسم = بالتاريخ)
const migrations = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
const lastDefinedIn = new Map();
for (const file of migrations) {
  const sql = readFileSync(join(migrationsDir, file), 'utf8');
  for (const m of sql.matchAll(/create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s*\(/gi)) {
    lastDefinedIn.set(m[1].toLowerCase(), file);
  }
}

const functions = await rows('dump_functions.sql');
const triggers = await rows('dump_triggers.sql');

const lines = [];
lines.push('-- =====================================================================');
lines.push('-- النسخة الحالية من دوال قاعدة البيانات و triggers — مولّدة تلقائياً، للقراءة فقط.');
lines.push('-- لا تعدّل هذا الملف ولا تطبّقه. التعديل = migration جديد، ثم: node supabase/schema/generate.mjs');
lines.push(`-- المصدر: ${live ? 'القاعدة الحية' : 'كل ملفات migrations بالترتيب'} — عدد الدوال: ${functions.length} — عدد الـ triggers: ${triggers.length}`);
lines.push('-- =====================================================================');
lines.push('');
lines.push('-- ---------------------------------------------------------------------');
lines.push('-- فهرس: الدالة ← آخر migration عرّفها');
lines.push('-- ---------------------------------------------------------------------');
for (const f of functions) {
  lines.push(`--   ${f.name}(${f.args})  ←  ${lastDefinedIn.get(f.name) ?? '(خارج migrations)'}`);
}
lines.push('');
lines.push('-- ---------------------------------------------------------------------');
lines.push('-- Triggers: الجدول ← الدالة اللي تشتغل تلقائياً');
lines.push('-- ---------------------------------------------------------------------');
for (const t of triggers) lines.push(`--   ${t.table_name}.${t.trigger_name}  →  ${t.function_name}()`);
lines.push('');
for (const t of triggers) lines.push(`${t.def};`);
lines.push('');
for (const f of functions) {
  lines.push('-- ---------------------------------------------------------------------');
  lines.push(`-- ${f.name}(${f.args})  — آخر تعريف: ${lastDefinedIn.get(f.name) ?? '(خارج migrations)'}`);
  lines.push('-- ---------------------------------------------------------------------');
  lines.push(`${f.def.trimEnd()};`);
  lines.push('');
}
const content = lines.join('\n');

if (checkOnly) {
  let current = '';
  try { current = readFileSync(outFile, 'utf8').replace(/\r\n/g, '\n'); } catch { /* ماكو ملف */ }
  if (current !== content) {
    console.error('supabase/schema/current_functions.sql مو محدّث. شغّل: node supabase/schema/generate.mjs وارفع الملف.');
    process.exit(1);
  }
  console.log(`current_functions.sql محدّث (${functions.length} دالة، ${triggers.length} trigger)`);
} else {
  writeFileSync(outFile, content);
  console.log(`current_functions.sql: ${functions.length} functions, ${triggers.length} triggers`);
}
process.exit(0);
