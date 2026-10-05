// يقرأ نتائج flutter test (--file-reporter json) ويطبع كل اختبار فاشل كـ GitHub annotation،
// حتى تنقرا أسماء الاختبارات ورسائلها من الـ API بدون تسجيل دخول.
const fs = require('fs');

const file = process.argv[2] || 'test-results.json';
if (!fs.existsSync(file)) process.exit(0);
const events = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
const names = {};
const errors = {};
for (const e of events) {
  if (e.type === 'testStart') names[e.test.id] = e.test.name;
  if (e.type === 'error') (errors[e.testID] = errors[e.testID] || []).push(e.error);
  if (e.type === 'testDone' && e.result !== 'success' && !e.hidden) {
    const msg = (errors[e.testID] || []).join(' | ').replace(/\s+/g, ' ').slice(0, 900);
    console.log(`::error title=FAILED ${names[e.testID]}::${msg}`);
  }
}
