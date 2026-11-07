// يشغّل كل ملفات الفحص وحدة وحدة، ويكمل حتى لو فشل ملف (قبل كان يوقف عند أول فشل فالباقي ما يشتغل)،
// وبالأخير يطبع ملخص ويطلع بفشل إذا أي ملف فشل.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';

const files = [
  'test_security.mjs', 'test_attendance.mjs', 'test_leave_payroll.mjs', 'test_deletion.mjs', 'test_loans.mjs',
  'test_reminders.mjs', 'test_hardening.mjs', 'test_announcements.mjs', 'test_payroll_engine.mjs', 'test_user_flows.mjs',
  'test_qa_fixes.mjs', 'test_schedule_history.mjs', 'test_hr_assistant.mjs', 'test_hr_assistant_reports.mjs',
  'test_hr_assistant_decisions.mjs', 'test_hr_assistant_history.mjs', 'test_payroll_loans.mjs', 'test_payroll_money.mjs',
  'test_payroll_calculate.mjs', 'test_payroll_quality.mjs', 'test_decision_amount.mjs', 'test_late_cap.mjs',
  'test_safe_cleanup.mjs', 'test_tracking_retention.mjs', 'test_settled_loans.mjs', 'test_document_urls.mjs',
  'test_manager_scope.mjs', 'test_column_grants.mjs', 'test_offline_punch.mjs', 'test_payroll_partial.mjs',
  'test_employee_history.mjs', 'test_payroll_concurrency.mjs', 'test_employee_files.mjs', 'test_stage9_cleanup.mjs',
  'test_stage10_cleanup.mjs',
];

// ملف فحص جديد لازم ينضاف للقائمة، حتى ما يبقى بدون تشغيل
const missing = fs.readdirSync(import.meta.dirname).filter((f) => /^test_.*\.mjs$/.test(f) && !files.includes(f));
const failed = [];
for (const file of files) {
  console.log(`\n===== ${file} =====`);
  const r = spawnSync(process.execPath, [file], { stdio: 'inherit', cwd: import.meta.dirname });
  if (r.status !== 0) failed.push(file);
}

console.log(`\n===== ${files.length - failed.length} of ${files.length} test files passed =====`);
if (failed.length) console.log(`FAILED: ${failed.join(', ')}`);
if (missing.length) console.log(`NOT LISTED in run_all.mjs (never run): ${missing.join(', ')}`);
if (failed.length || missing.length) process.exit(1);
