// Shared PGlite harness: builds a DB from stubs + all repo migrations,
// seeds a branch and three users, and offers helpers to act as a role.
import { PGlite } from '@electric-sql/pglite';
import { uuid_ossp } from '@electric-sql/pglite/contrib/uuid_ossp';
import fs from 'node:fs';

const repo = new URL('../migrations', import.meta.url);
const stripExt = (sql) =>
  sql.replace(/CREATE EXTENSION[^;]*(pg_cron|pg_net|pgcrypto)[^;]*;/gi, '-- ext skipped;');

export const IDS = {
  admin: '00000000-0000-0000-0000-00000000000a',
  emp: '00000000-0000-0000-0000-00000000000e',
  emp2: '00000000-0000-0000-0000-0000000000e2',
  manager: '00000000-0000-0000-0000-00000000000b',
  branch: '00000000-0000-0000-0000-0000000000b1',
};

/** قاعدة فارغة: الـ stubs + ملفات [files] (URLs) بالترتيب. */
export async function buildFromFiles(files) {
  const db = new PGlite({ extensions: { uuid_ossp } });
  await db.exec(fs.readFileSync(new URL('./stubs.sql', import.meta.url), 'utf8'));
  for (const file of files) {
    try {
      await db.exec(stripExt(fs.readFileSync(file, 'utf8')));
    } catch (e) {
      throw new Error(`${file.pathname.split('/').pop()}: ${e.message}`);
    }
  }
  return db;
}

/** ملفات .sql بمجلد، مرتبة بالاسم (= بالتاريخ). */
export function sqlFiles(dir) {
  return fs.readdirSync(dir).filter((f) => f.endsWith('.sql')).sort().map((f) => new URL(f, dir.href + '/'));
}

/** قاعدة فارغة: الـ stubs + كل ملفات migrations بالترتيب (بدون بيانات). يستعملها أيضاً supabase/schema/generate.mjs. */
export async function buildSchema() {
  return buildFromFiles(sqlFiles(repo));
}

/** الجزء الرئيسي (public) من القاعدة كأوامر SQL (pg_dump: الجداول والدوال والصلاحيات والبيانات). */
export async function dumpPublic(db) {
  const { pgDump } = await import('@electric-sql/pglite-tools/pg_dump');
  const file = await pgDump({ pg: db, args: ['--schema=public', '--no-owner'] });
  // pg_dump يفرّغ search_path على نفس الاتصال: نرجعه مثل Supabase
  await db.exec(`SET search_path TO "$user", public, extensions`);
  return file.text();
}

/** لقطة القاعدة (supabase/schema/snapshot.sql): سطر لكل عنصر، مرتبة. */
export async function snapshot(db) {
  const sql = fs.readFileSync(new URL('../schema/snapshot.sql', import.meta.url), 'utf8');
  await db.exec(`SET search_path = ''`);
  try {
    return (await db.query(sql)).rows.map((r) => `${r.kind}: ${r.item}`).sort();
  } finally {
    await db.exec(`SET search_path TO "$user", public, extensions`);
  }
}

export async function setup() {
  const db = await buildSchema();
  await db.exec(`
    INSERT INTO branches (id, name, latitude, longitude, radius_meters)
      VALUES ('${IDS.branch}', 'الفرع الرئيسي', 33.3000, 44.4000, 100);
    INSERT INTO employees (id, employee_code, full_name, role, branch_id, monthly_salary_iqd, must_change_password) VALUES
      ('${IDS.admin}', 'A1', 'أدمن', 'admin', '${IDS.branch}', 2000000, false),
      ('${IDS.manager}', 'M1', 'مدير', 'manager', '${IDS.branch}', 1500000, false),
      ('${IDS.emp}', 'E1', 'موظف', 'employee', '${IDS.branch}', 1000000, false),
      ('${IDS.emp2}', 'E2', 'موظف ثاني', 'employee', '${IDS.branch}', 900000, false);
    INSERT INTO auth.users (id, email) VALUES
      ('${IDS.admin}', 'a@x'), ('${IDS.manager}', 'm@x'), ('${IDS.emp}', 'e@x'), ('${IDS.emp2}', 'e2@x');
  `);
  return db;
}

/** Runs fn as the given actor ('anon' | 'admin' | 'emp' | ...). */
export async function as(db, who, sql, params = []) {
  const role = who === 'anon' ? 'anon' : 'authenticated';
  const sub = who === 'anon' ? '' : IDS[who];
  await db.exec(`RESET ROLE; SELECT set_config('request.jwt.claim.sub', '${sub}', false),
                 set_config('request.jwt.claim.role', '${role}', false); SET ROLE ${role};`);
  try {
    return await db.query(sql, params);
  } finally {
    await db.exec('RESET ROLE;');
  }
}

let failures = 0;
export async function expectOk(label, p) {
  try {
    const r = await p;
    console.log('PASS', label);
    return r;
  } catch (e) {
    failures++;
    console.log('FAIL', label, '->', e.message);
  }
}
export async function expectError(label, p, match) {
  try {
    await p;
    failures++;
    console.log('FAIL', label, '-> expected error, got success');
  } catch (e) {
    if (match && !String(e.message).includes(match)) {
      failures++;
      console.log('FAIL', label, '-> wrong error:', e.message);
    } else console.log('PASS', label, `(${e.message.slice(0, 70)})`);
  }
}
export function check(label, cond, detail = '') {
  if (cond) console.log('PASS', label);
  else {
    failures++;
    console.log('FAIL', label, detail);
  }
}
export function done() {
  console.log(failures ? `\n${failures} FAILED` : '\nALL PASSED');
  process.exit(failures ? 1 : 0);
}
