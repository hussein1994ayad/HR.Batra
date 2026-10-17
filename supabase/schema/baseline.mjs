// المرحلة 10 (تدقيق 14/10، CODE-002): ملف أساس واحد بدل 95 ملف migration.
//
// ملف الأساس = القاعدة مثل ما تطلع من كل الملفات القديمة (supabase/migrations_archive) بالترتيب: كل دالة بشكلها
// الأخير مرة وحدة. ينبني بـ PGlite + pg_dump (بدون اتصال ولا تسجيل دخول)، وتنضاف له الأشياء اللي برا الجزء
// الرئيسي: الإضافات (extensions)، تخزين الملفات وصلاحياته، التحديث المباشر، والمهام المجدولة.
// الملف يبدي بقفل: إذا القاعدة موجودة يوكف (على السيرفر الحي ينسجل كمطبّق بـ migration repair، ما يشتغل أبداً).
//
//   node supabase/schema/baseline.mjs           ← يكتب الملف
//   node supabase/schema/baseline.mjs --check   ← (الفحص التلقائي) يفشل إذا الملف مو نفس اللي يطلع من الأرشيف،
//                                                 أو إذا قاعدة مبنية منه تختلف عن الأرشيف بأي شي
//   node supabase/schema/baseline.mjs --live    ← يقارن القاعدة من كل ملفات migrations (الأساس وبعده) ويا القاعدة الحية
//                                                 (قراءة بس، بعد supabase link): الفرق = اللي بعده ما انطبق + أشياء منصة Supabase
// يحتاج: cd supabase/tests && npm ci

import { execSync } from 'node:child_process';
import { existsSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const archiveDir = pathToFileURL(join(root, 'migrations_archive') + '/');
export const BASELINE_VERSION = '20261025000000';
const baselineFile = join(root, 'migrations', `${BASELINE_VERSION}_create_baseline_schema.sql`);
const lib = await import('../tests/lib.mjs');

// ---------------------------------------------------------------------------
// قيم SQL
// ---------------------------------------------------------------------------
const lit = (v) => {
  if (v === null || v === undefined) return 'NULL';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number' || typeof v === 'bigint') return String(v);
  if (Array.isArray(v)) return `ARRAY[${v.map(lit).join(', ')}]::text[]`;
  return `'${String(v).replace(/'/g, "''")}'`;
};
const ident = (s) => (/^[a-z_][a-z0-9_]*$/.test(s) ? s : `"${s.replace(/"/g, '""')}"`);
const dollar = (body, tag = 'body') => {
  let t = tag;
  for (let i = 0; body.includes(`$${t}$`); i++) t = `${tag}${i}`;
  return `$${t}$${body}$${t}$`;
};
const roleList = (roles) => {
  const list = Array.isArray(roles) ? roles : String(roles).replace(/^\{|\}$/g, '').split(',');
  return list.map((r) => (r === 'public' ? 'public' : ident(r))).join(', ');
};

// ---------------------------------------------------------------------------
// بناء ملف الأساس من الأرشيف
// ---------------------------------------------------------------------------
async function generate() {
  const files = lib.sqlFiles(archiveDir);
  const db = await lib.buildFromFiles(files);
  let dump = await lib.dumpPublic(db);

  await db.exec(`SET search_path = ''`);
  const q = async (s) => (await db.query(s)).rows;
  const buckets = await q(`SELECT id, name, public, file_size_limit, allowed_mime_types FROM storage.buckets ORDER BY id`);
  const policies = await q(`SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
                            FROM pg_catalog.pg_policies WHERE schemaname = 'storage' ORDER BY tablename, policyname`);
  const realtime = await q(`SELECT tablename FROM pg_catalog.pg_publication_tables
                            WHERE pubname = 'supabase_realtime' AND schemaname = 'public' ORDER BY tablename`);
  const jobs = await q(`SELECT jobname, schedule, command FROM cron.job ORDER BY jobname`);
  await db.exec(`SET search_path TO "$user", public, extensions`);
  await db.close();

  // الجزء الرئيسي موجود بكل قاعدة Supabase
  dump = dump.replace(/--\n-- Name: public; Type: SCHEMA;[^\n]*\n--\n\nCREATE SCHEMA public;\n\n\n/, '');
  dump = dump.replace(/--\n-- Name: SCHEMA public; Type: COMMENT;[^\n]*\n--\n\nCOMMENT ON SCHEMA public IS [^\n]*\n\n\n/, '');
  if (/CREATE SCHEMA public;|COMMENT ON SCHEMA public/.test(dump)) throw new Error('baseline: public schema block not removed');

  // البيانات اللي تعتمد على يوم البناء تنحسب وقت التشغيل (مثل الملفات القديمة) حتى الملف يبقى ثابت:
  //  • payroll_policy.no_record_from = يوم بناء القاعدة (20260929000000_payroll_engine.sql)
  //  • payroll_periods.created_at = now() (القيمة الافتراضية)
  const before = dump;
  dump = dump
    .replace(/"no_record_from": "\d{4}-\d{2}-\d{2}", /g, '')
    .replace(/, "no_record_from": "\d{4}-\d{2}-\d{2}"/g, '');
  if (dump === before) throw new Error('baseline: no_record_from not found in system_settings data');
  dump = dump.replace(/^(INSERT INTO public\.payroll_periods VALUES .*)$/gm, (line) =>
    line.replace(/'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d+)?\+00'/g, 'now()'),
  );
  if (/\d{2}:\d{2}:\d{2}(\.\d+)?\+00'/.test(dump.split('\n').filter((l) => l.startsWith('INSERT INTO')).join('\n'))) {
    throw new Error('baseline: a build-time timestamp is still in the data');
  }

  const out = [];
  out.push(
    '-- =========================================================================',
    '-- HR Pro — ملف الأساس (المرحلة 10، تدقيق 14/10 CODE-002)',
    '-- =========================================================================',
    `-- القاعدة كاملة مثل ما تطلع من ${files.length} ملف قديم (supabase/migrations_archive) — كل دالة بشكلها الأخير مرة وحدة.`,
    '-- مولّد تلقائياً: لا تعدّله. التوليد: node supabase/schema/baseline.mjs (والفحص: --check).',
    '--',
    '-- • للقواعد الجديدة الفارغة بس (فحوص، نسخة تجربة، نسخة احتياطية جديدة).',
    `-- • السيرفر الحي: ينسجل كمطبّق بدون تشغيل (supabase migration repair --status applied ${BASELINE_VERSION}).`,
    '-- • التعديلات الجاية = ملف migration جديد بعد هذا الملف، مثل قبل.',
    '-- =========================================================================',
    '',
    '-- القفل: إذا القاعدة موجودة يوكف وما يغير شي',
    'DO $guard$',
    'BEGIN',
    "  IF to_regclass('public.employees') IS NOT NULL THEN",
    "    RAISE EXCEPTION 'ملف الأساس للقواعد الجديدة الفارغة بس: القاعدة موجودة. سجّله كمطبّق بدل تشغيله: supabase migration repair --status applied " +
      BASELINE_VERSION +
      "';",
    '  END IF;',
    'END',
    '$guard$;',
    '',
    '-- الصلاحيات: Supabase يعطي كل جدول ودالة جديدة صلاحيات افتراضية لـ anon و authenticated و service_role،',
    '-- و pg_dump يكتب الصلاحيات نسبةً لافتراضي Postgres الأصلي (يضيف بس، ما يشيل). فنوقف الافتراضي أثناء البناء',
    '-- حتى كل عنصر يطلع بصلاحياته بالضبط؛ القواعد الافتراضية الأخيرة ترجع بنهاية الجزء الرئيسي (DEFAULT ACL).',
    'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated, service_role;',
    'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON FUNCTIONS FROM anon, authenticated, service_role;',
    '',
    '-- الإضافات (نفس الملفات القديمة؛ بـ Supabase موجودة أصلاً)',
    'CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;',
    'CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;',
    '',
  );
  out.push(dump.trimEnd(), '');

  out.push(
    '',
    '-- =========================================================================',
    '-- برا الجزء الرئيسي: نفس اللي سوته الملفات القديمة',
    '-- =========================================================================',
    '',
    '-- يوم بداية الحساب = يوم بناء القاعدة (مثل 20260929000000_payroll_engine.sql)',
    "UPDATE public.system_settings SET value = value || jsonb_build_object('no_record_from', to_char((now() AT TIME ZONE 'Asia/Baghdad')::date, 'YYYY-MM-DD'))",
    "WHERE key = 'payroll_policy' AND NOT (value ? 'no_record_from');",
    '',
    '-- تخزين الملفات',
  );
  for (const b of buckets) {
    out.push(
      `INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES (${[b.id, b.name, b.public, b.file_size_limit, b.allowed_mime_types].map(lit).join(', ')})`,
      '  ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, public = EXCLUDED.public, file_size_limit = EXCLUDED.file_size_limit, allowed_mime_types = EXCLUDED.allowed_mime_types;',
    );
  }
  out.push('', '-- صلاحيات تخزين الملفات');
  for (const p of policies) {
    const on = `storage.${ident(p.tablename)}`;
    out.push(`DROP POLICY IF EXISTS ${ident(p.policyname)} ON ${on};`);
    out.push(
      `CREATE POLICY ${ident(p.policyname)} ON ${on} AS ${p.permissive} FOR ${p.cmd} TO ${roleList(p.roles)}` +
        (p.qual ? `\n  USING (${p.qual})` : '') +
        (p.with_check ? `\n  WITH CHECK (${p.with_check})` : '') +
        ';',
    );
  }
  out.push(
    '',
    '-- التحديث المباشر (Realtime)',
    'DO $realtime$',
    'DECLARE t text;',
    'BEGIN',
    `  FOREACH t IN ARRAY ARRAY[${realtime.map((r) => lit(r.tablename)).join(', ')}] LOOP`,
    '    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication_tables',
    "                   WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t) THEN",
    "      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);",
    '    END IF;',
    '  END LOOP;',
    'END',
    '$realtime$;',
    '',
    '-- المهام المجدولة',
  );
  for (const j of jobs) out.push(`SELECT cron.schedule(${lit(j.jobname)}, ${lit(j.schedule)}, ${dollar(j.command, 'cron')});`);
  out.push(
    '',
    '-- إعدادات الجلسة ترجع مثل Supabase (pg_dump غيّرها فوق) حتى الملفات اللي بعده تشتغل عادي',
    `SELECT pg_catalog.set_config('search_path', '"$user", public, extensions', false);`,
    'RESET check_function_bodies;',
    'RESET client_min_messages;',
    'RESET row_security;',
    'RESET xmloption;',
    'RESET statement_timeout;',
    'RESET lock_timeout;',
    'RESET idle_in_transaction_session_timeout;',
    'RESET transaction_timeout;',
    '',
  );
  return {
    text: out.join('\n'),
    counts: { files: files.length, buckets: buckets.length, policies: policies.length, realtime: realtime.length, jobs: jobs.length },
  };
}

// ---------------------------------------------------------------------------
// المقارنة
// ---------------------------------------------------------------------------
function diff(label, a, b) {
  const sa = new Set(a), sb = new Set(b);
  const onlyA = a.filter((x) => !sb.has(x));
  const onlyB = b.filter((x) => !sa.has(x));
  if (!onlyA.length && !onlyB.length) {
    console.log(`PASS ${label}: ${a.length} items identical`);
    return true;
  }
  console.log(`FAIL ${label}: ${onlyA.length} only in first, ${onlyB.length} only in second`);
  for (const x of onlyA.slice(0, Number(process.env.DIFF_MAX ?? 40))) console.log('  - ' + x);
  for (const x of onlyB.slice(0, Number(process.env.DIFF_MAX ?? 40))) console.log('  + ' + x);
  return false;
}

/** صفوف كل الجداول اللي بيها بيانات (بدون الأعمدة اللي تتغير بوقت البناء). */
async function dataRows(db) {
  const tables = (await db.query(`SELECT c.oid::regclass::text AS t FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                                  WHERE n.nspname = 'public' AND c.relkind = 'r' ORDER BY 1`)).rows.map((r) => r.t);
  const rows = [];
  for (const t of tables) {
    const r = await db.query(`SELECT (to_jsonb(x) - 'created_at' - 'updated_at')::text AS j FROM ${t} x`);
    for (const { j } of r.rows) rows.push(`${t}: ${j}`);
  }
  return rows.sort();
}

async function baselineDb() {
  return lib.buildFromFiles([pathToFileURL(baselineFile)]);
}

function liveSnapshot() {
  const tmp = join(here, '.snapshot_live.sql');
  writeFileSync(tmp, `SET search_path = '';\n${readFileSync(join(here, 'snapshot.sql'), 'utf8')}`);
  try {
    const out = execSync(`npx supabase db query --linked -f "${tmp}" --output-format json`, {
      cwd: join(root, '..'),
      encoding: 'utf8',
      maxBuffer: 256 * 1024 * 1024,
    });
    return JSON.parse(out.slice(out.indexOf('{'))).rows.map((r) => `${r.kind}: ${r.item}`).sort();
  } finally {
    unlinkSync(tmp);
  }
}

// ---------------------------------------------------------------------------
process.on('unhandledRejection', (e) => { console.error('ERROR', e?.message ?? e); process.exit(1); });
const mode = process.argv.includes('--check') ? 'check' : process.argv.includes('--live') ? 'live' : 'write';

if (mode === 'write') {
  const { text, counts } = await generate();
  writeFileSync(baselineFile, text);
  console.log(`written ${baselineFile}`, counts, `${text.split('\n').length} lines`);
} else if (mode === 'check') {
  let ok = true;
  const { text } = await generate();
  if (!existsSync(baselineFile) || readFileSync(baselineFile, 'utf8') !== text) {
    console.log('FAIL baseline file is not what the archive produces: run node supabase/schema/baseline.mjs');
    ok = false;
  } else console.log('PASS baseline file matches the archive output');

  const a = await lib.buildFromFiles(lib.sqlFiles(archiveDir));
  const b = await baselineDb();
  ok = diff('schema: archive vs baseline', await lib.snapshot(a), await lib.snapshot(b)) && ok;
  ok = diff('data: archive vs baseline', await dataRows(a), await dataRows(b)) && ok;
  process.exit(ok ? 0 : 1);
} else {
  const b = await lib.buildSchema();
  const ok = diff('schema: migrations vs LIVE', await lib.snapshot(b), liveSnapshot());
  process.exit(ok ? 0 : 1);
}
