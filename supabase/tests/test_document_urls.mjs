// قائمة المستمسكات دائماً قائمة JSON (التصفير كتبها كائن `{}` فوقفت صفحة الموظفين).
import { setup, as, IDS, expectOk, expectError, check, done } from './lib.mjs';

const db = await setup();
const one = async (sql, p = []) => (await db.query(sql, p)).rows[0];

await expectError('1) an object instead of a list is refused', db.query(`UPDATE employees SET document_urls = '{}'::jsonb WHERE id = $1`, [IDS.emp]),
  'employees_document_urls_is_array');
await expectOk('   an empty list is fine', db.query(`UPDATE employees SET document_urls = '[]'::jsonb WHERE id = $1`, [IDS.emp]));
await expectOk('   no documents at all (NULL) is still allowed', db.query(`UPDATE employees SET document_urls = NULL WHERE id = $1`, [IDS.emp2]));

await db.query(`INSERT INTO employees (id, employee_code, full_name, branch_id, must_change_password) VALUES ('00000000-0000-0000-0000-0000000000d9', 'DU1', 'جديد', $1, false)`, [IDS.branch]);
const fresh = await one(`SELECT jsonb_typeof(document_urls) t FROM employees WHERE id = '00000000-0000-0000-0000-0000000000d9'`);
check('2) a new employee starts with an empty list', fresh.t === 'array', JSON.stringify(fresh));

// الموظف يضيف مستمسك لقائمته الفارغة (فحص «إضافة فقط» يشتغل على قائمة)
await db.query(`UPDATE employees SET document_urls = '[]'::jsonb WHERE id = $1`, [IDS.emp]);
await expectOk('3) the employee can add a document to his empty list', as(db, 'emp',
  `UPDATE employees SET document_urls = '["https://x.supabase.co/storage/v1/object/public/employee-documents/${IDS.emp}/a.jpg"]'::jsonb WHERE id = $1`, [IDS.emp]));
check('   ...and it is saved', (await one(`SELECT jsonb_array_length(document_urls) n FROM employees WHERE id = $1`, [IDS.emp])).n === 1);

done();
