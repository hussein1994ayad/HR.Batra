// يولّد supabase/schema/current_functions.sql: النسخة الحالية (الحية) من كل دالة و trigger بقاعدة البيانات.
//
// ليش؟ الدوال تتعرّف من جديد بـ migrations لاحقة (مثلاً sync_payroll_day بـ 5 ملفات)، فقراءة ملف migration
// قديم تعطي قاعدة ملغية. هذا الملف للقراءة فقط — أي تعديل يصير بـ migration جديد، ثم نعيد التوليد.
//
// التشغيل (بعد `npx supabase link` و `db push`):
//   node supabase/schema/generate.mjs
// يقرأ فقط من القاعدة (SELECT)، وما يغيّر شي.

import { execSync } from 'node:child_process';
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, '..', 'migrations');

function query(file) {
  const out = execSync(`npx supabase db query --linked -f "${join(here, file)}" --output-format json`, {
    cwd: join(here, '..', '..'),
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  return JSON.parse(out.slice(out.indexOf('{'))).rows;
}

// آخر ملف migration يعرّف كل دالة (الملفات مرتبة بالاسم = بالتاريخ)
const migrations = readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
const lastDefinedIn = new Map();
for (const file of migrations) {
  const sql = readFileSync(join(migrationsDir, file), 'utf8');
  for (const m of sql.matchAll(/create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s*\(/gi)) {
    lastDefinedIn.set(m[1].toLowerCase(), file);
  }
}

const functions = query('dump_functions.sql');
const triggers = query('dump_triggers.sql');

const lines = [];
lines.push('-- =====================================================================');
lines.push('-- النسخة الحالية من دوال قاعدة البيانات و triggers — مولّدة تلقائياً، للقراءة فقط.');
lines.push('-- لا تعدّل هذا الملف ولا تطبّقه. التعديل = migration جديد، ثم: node supabase/schema/generate.mjs');
lines.push(`-- عدد الدوال: ${functions.length} — عدد الـ triggers: ${triggers.length}`);
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

writeFileSync(join(here, 'current_functions.sql'), lines.join('\n'));
console.log(`current_functions.sql: ${functions.length} functions, ${triggers.length} triggers`);
