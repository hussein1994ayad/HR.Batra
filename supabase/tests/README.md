# اختبارات قاعدة البيانات

تشغّل كل ملفات `../migrations` بالترتيب على نسخة Postgres داخل Node
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
