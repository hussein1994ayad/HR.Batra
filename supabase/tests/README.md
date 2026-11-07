# اختبارات قاعدة البيانات

تشغّل ملفات `../migrations` بالترتيب (ملف الأساس وبعده أي ملف جديد) على نسخة Postgres داخل Node
([PGlite](https://pglite.dev)) مع بدائل بسيطة لمخططات Supabase (`auth`, `storage`, `cron`)،
ثم تختبر الصلاحيات والمنطق كمستخدم مجهول، موظف، مدير، وأدمن.

```bash
cd supabase/tests
npm install
npm test
```

| الملف | يغطي |
|---|---|
| `test_security.mjs` | دوال RPC المحمية، الـ Views، الإشعارات، archived_months |
| `test_attendance.mjs` | punch_attendance (المسافة، التأخير، الأوفلاين، الجهاز)، register_device_login |
| `test_leave_payroll.mjs` | خصم رصيد الإجازات، إشعارات القرار، اعتماد الراتب والتراجع عنه |
| `test_deletion.mjs` | request_account_deletion |

أي migration جديد يجب أن يمر من هنا قبل `supabase db push`.

**الساعة ثابتة:** أول سطر بكل ملف فحص `import './clock.mjs';` يخلي «الآن» = 20/10/2026 10:00 بغداد (قاعدة البيانات التجريبية
والفحوص)، حتى التواريخ الثابتة بالفحوص ما تتعارض ويا اليوم الحقيقي. ملف فحص جديد: ضيف هذا السطر أولاً، وضيف الملف لقائمة
`run_all.mjs` (`npm test` يفشل إذا ملف `test_*.mjs` مو بالقائمة). يوم ثاني للتجربة: `TEST_NOW=2026-11-07T10:00:00+03:00 node test_x.mjs`.
