# قواعد العمل — أين تعيش كل قاعدة

**المصدر الأساسي هو قاعدة البيانات** (`supabase/migrations`): السيرفر يحسب ويرفض.
الويب والتطبيق ينسخون بعض القواعد فقط لعرض تنبيه أو معاينة قبل الإرسال — إذا غيّرت قاعدة
غيّر المصدر أولاً ثم نسخها بنفس القيمة، وشغّل فحوصات الثلاثة (`supabase/tests`, `web`, `mobile`).

| القاعدة | المصدر (السيرفر) | نسخ للعرض/التنبيه |
|---|---|---|
| **الحضور:** متأخر إذا بعد بداية الدوام + فترة السماح (الافتراضي 08:30 + 15 دقيقة) | `punch_attendance` — آخر نسخة `20261004000000_punch_rejects_low_accuracy.sql` | `web/src/features/tracking/logic.ts` (`manualAttendanceStatus`)، `mobile/lib/core/logic/attendance_rules.dart` |
| **الانصراف المبكر:** قبل نهاية الدوام بأكثر من 15 دقيقة | `punch_attendance` + محرّك الرواتب (`payroll_events`) | `attendance_screen.dart` (تأكيد قبل الانصراف) |
| **نطاق الفرع:** المسافة ≤ نصف القطر + 10 م تسامح | `punch_attendance` (`c_distance_tolerance_m`) | `attendance_screen.dart` (فحص قبل الإرسال) |
| **دقة الـ GPS:** ≤ 100 م (أو نطاق الفرع إذا أوسع) | `punch_attendance` (`c_max_accuracy_m`) | `mobile/lib/core/services/precise_location.dart` (`maxPunchAccuracyMeters`) |
| **البصمة بدون إنترنت:** تُقبل خلال 48 ساعة، وليس بالمستقبل | `punch_attendance` (`c_offline_max_age`) | `attendance_sync_service.dart` (يحتفظ ببصمة موظف آخر 48 ساعة) |
| **دورة الراتب:** من يوم (القطع+1) للشهر السابق حتى يوم القطع (الافتراضي 27 ← 26) | إعدادات الشركة `cutoff_day` / `payment_day` + `payroll_schedule()` | `web/src/features/payroll/period.ts` |
| **أجر اليوم = الراتب ÷ 30، وأجر الدقيقة = أجر اليوم ÷ دقائق دوام الموظف** | `payroll_daily_rate` / `sync_payroll_day` (`20260929000000_payroll_engine.sql`) | تعليقات فقط في `admin_models.dart`, `decision_card.dart` (التطبيق لا يحسب المبالغ) |
| **الخصم لا يتجاوز الراتب الشهري، وأي مبلغ ≤ 100,000,000** | `check_bonus_deduction_amount` (`20261002000000_full_qa_fixes.sql`) | — |
| **السلفة:** لا سلفة جديدة مع سلفة جارية، ولا طلبين معلّقين | `_validate_loan_terms` (اعتماد الأدمن) + `one_pending_loan_request` (طلب الموظف) — `20261004000100_...sql` | `loan_request_screen.dart` (`_validationError`) |
| **السلفة:** قسط فوق نص الراتب **مسموح مع تنبيه**؛ طلب الموظف ≤ 100,000,000 | نفس الدالتين (لا تمنع نص الراتب) | `web/src/features/loans/logic.ts` (`overHalfSalaryWarning`)، `loan_request_screen.dart` (`_salaryWarning`) |
| **العطل الرسمية والأسبوعية:** لا غياب ولا تذكير بصمة | `sync_payroll_day` (`v_workday`) + `official_holidays` | `mobile/lib/core/logic/reminder_plan.dart` |
| **التتبع:** بين بصمة الحضور والانصراف فقط، ومعلن للموظف | — (سياسة) | `location_service.dart` (أندرويد)، `ios/Runner/LocationMonitorIOS.swift` (آيفون) |

## قرارات تقنية غير واضحة
- **الآيفون لا يستعمل خدمة الخلفية من `flutter_background_service`:** iOS يرفض تسجيل مهمتها
  ("Registration rejected … not advertised in Info.plist") والتطبيق يكمل عادي. التتبع بالخلفية على الآيفون
  كله في `LocationMonitorIOS.swift` (Region Monitoring + Significant Location Changes) ويرفع مباشرة لـ Supabase.
- **التذكيرات:** أندرويد من السيرفر (cron → FCM)، الآيفون محلية (`flutter_local_notifications`).
- **إذن الإشعارات بالآيفون يُطلب بعد تسجيل الدخول** وليس عند التشغيل (كان يوقف أول شاشة).
- **ملف migration مطبّق لا يُعدَّل أبداً:** `db push` يتخطاه. أي تغيير = ملف جديد.
- **الشاشات لا تكلّم Supabase مباشرة:** كل الاستعلامات في `mobile/lib/data/repositories/` (الويب: `web/src/features/<x>/api.ts`).
  الخدمات في `core/services` (البصمة، التتبع، الإشعارات، الرفع) بنية تحتية وتبقى تكلّم القاعدة.
- **البيانات بالشاشات تبقى `Map<String, dynamic>` حالياً (النقطة 5):** النماذج الموجودة (`NotificationModel`، `LoanModel`…)
  قيمها الافتراضية تختلف عن اللي تعرضه الشاشات (مثلاً عنوان الإشعار الفارغ = «تنبيه» بالشاشة و`''` بالنموذج)، فالتحويل
  مو آلي ويغيّر العرض. يصير لاحقاً شاشة شاشة مع اختبار يثبت نفس العرض قبل/بعد.
