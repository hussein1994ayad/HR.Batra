# قواعد العمل — أين تعيش كل قاعدة

**المصدر الأساسي هو قاعدة البيانات**: السيرفر يحسب ويرفض. **النسخة الحالية** من كل دالة وكل trigger موجودة بملف واحد للقراءة:
`supabase/schema/current_functions.sql` (فيه فهرس: الدالة ← آخر migration عرّفها). لا تعتمد على أول ملف migration تلگاه:
بعض الدوال تعرّفت من جديد 5–7 مرات (مثلاً `sync_payroll_day`). بعد كل `db push` أعد التوليد: `node supabase/schema/generate.mjs`.
الويب والتطبيق ينسخون بعض القواعد فقط لعرض تنبيه أو معاينة قبل الإرسال — إذا غيّرت قاعدة
غيّر المصدر أولاً ثم نسخها بنفس القيمة، وشغّل فحوصات الثلاثة (`supabase/tests`, `web`, `mobile`).

| القاعدة | المصدر (السيرفر) | نسخ للعرض/التنبيه |
|---|---|---|
| **الحضور:** متأخر إذا بعد بداية الدوام + فترة السماح (الافتراضي 08:30 + 15 دقيقة) | `punch_attendance` — آخر نسخة `20261004000000_punch_rejects_low_accuracy.sql` | `web/src/features/tracking/logic.ts` (`manualAttendanceStatus`)، `mobile/lib/core/logic/attendance_rules.dart` |
| **الانصراف المبكر:** قبل نهاية الدوام بأكثر من 15 دقيقة | `punch_attendance` + محرّك الرواتب (`payroll_events`) | `mobile/lib/presentation/employee/attendance/attendance_logic.dart` (`punchNote` — تأكيد قبل الانصراف) |
| **نطاق الفرع:** المسافة ≤ نصف القطر + 10 م تسامح | `punch_attendance` (`c_distance_tolerance_m`) | `mobile/lib/presentation/employee/attendance/attendance_logic.dart` (`localPunchError` — فحص قبل الإرسال) |
| **دقة الـ GPS:** ≤ 100 م (أو نطاق الفرع إذا أوسع) | `punch_attendance` (`c_max_accuracy_m`) | `mobile/lib/core/services/precise_location.dart` (`maxPunchAccuracyMeters`) |
| **البصمة بدون إنترنت:** تُقبل خلال 48 ساعة، وليس بالمستقبل | `punch_attendance` (`c_offline_max_age`) | `mobile/lib/core/services/attendance_sync_service.dart` (يحتفظ ببصمة موظف آخر 48 ساعة) |
| **دورة الراتب:** من يوم (القطع+1) للشهر السابق حتى يوم القطع (الافتراضي 27 ← 26) | إعدادات الشركة `cutoff_day` / `payment_day` + `payroll_schedule()` | `web/src/features/payroll/period.ts` |
| **أجر اليوم = الراتب ÷ 30، وأجر الدقيقة = أجر اليوم ÷ دقائق دوام الموظف** | `payroll_daily_rate` / `sync_payroll_day` (آخر نسخة `20261002000000_full_qa_fixes.sql`) | لا أحد يعيد حسابها: الويب والتطبيق يعرضون أرقام السيرفر (`get_payroll_run`, `get_my_payroll_preview`) |
| **الخصم لا يتجاوز الراتب الشهري، وأي مبلغ ≤ 100,000,000** | `check_bonus_deduction_amount` (`20261002000000_full_qa_fixes.sql`) | — |
| **السلفة:** لا سلفة جديدة مع سلفة جارية، ولا طلبين معلّقين | `_validate_loan_terms` (اعتماد الأدمن، `20261003000000_admin_loans_over_half_salary.sql`) + `one_pending_loan_request` (طلب الموظف، `20261004000100_employee_loan_request_over_half_salary.sql`) | `mobile/lib/presentation/employee/loan/loan_request_logic.dart` (`loanRequestError`) |
| **السلفة:** قسط فوق نص الراتب **مسموح مع تنبيه**؛ طلب الموظف ≤ 100,000,000 | نفس الدالتين (لا تمنع نص الراتب) | النسبة: `LOAN_SALARY_WARNING_RATIO` (`web/src/features/loans/logic.ts`) و`kLoanSalaryWarningRatio` (`mobile/lib/core/logic/loan_rules.dart`)؛ التنبيه: `overHalfSalaryWarning`، `loanSalaryWarning` |
| **العطل الرسمية والأسبوعية:** لا غياب ولا تذكير بصمة | `sync_payroll_day` (`v_workday`) + `official_holidays` | `mobile/lib/core/logic/reminder_plan.dart` |
| **التتبع:** بين بصمة الحضور والانصراف فقط، ومعلن للموظف | — (سياسة) | `mobile/lib/core/services/location_service.dart` + `core/services/location/` (أندرويد)، `mobile/ios/Runner/LocationMonitorIOS.swift` (آيفون) |

| **السلفة النقدية** (`payment_method = 'cash'`): أقساطها ما تنخصم من الراتب | `payroll_employee_summary` + `approve_payroll_slip` | — |
| **راتب جزئي** (مباشرة أو ترك عمل خلال المسير): أجر اليوم × أيام الخدمة (بحد 30) | `payroll_employee_summary` | — |
| **التقريب:** لأقرب دينار على **مجموع** الكشف وليس يوم بيوم | `payroll_employee_summary` (`net`) | — |

## دورة حياة المسير (Payroll) — من البصمة لحد الكشف
كل الخطوات بالسيرفر. الويب (`web/src/features/payroll/`) يعرض ويرسل القرارات فقط، والتطبيق يعرض الكشف.

1. **الحركة:** أي تغيير بالحضور أو الإجازات أو المكافآت يشغّل `sync_payroll_day(موظف، يوم)` عبر triggers
   (`trg_payroll_attendance`, `trg_payroll_leave`, `trg_payroll_manual`). تنكتب حركة بـ `payroll_events` بتاريخها الحقيقي
   (`event_date`) وبالمسير اللي تنحسب بيه (`payroll_month`)، ومعها أجر اليوم والدقيقة وقتها للتدقيق.
2. **حالة الحركة:** `pending` تنتظر قرار الإدارة (الغياب، التأخير، الخروج المبكر، البصمة الناقصة) ← `approved` تنحسب
   أو `ignored` إعفاء. `void` = ألغاها النظام نفسه (مثلاً انحذفت البصمة أو تغيّرت). ليش ما يُخصم تلقائياً؟ لأن الغياب ممكن
   يكون نسيان بصمة أو عذر، فالإدارة هي اللي تقرر.
3. **القرار يدخل من بابين (انتبه):**
   - `decide_payroll_event` (صفحة الرواتب ولوحة الإدارة إذا الحركة موجودة) يحدّث الحركة **و** `attendance.deduction_status`.
   - تحديث مباشر لـ `attendance.deduction_status` (صفحة التتبع بالويب `web/src/features/tracking/api.ts`، ولوحة الإدارة بالتطبيق
     `mobile/lib/data/repositories/admin_actions_repository.dart` للأيام بدون حركة) ← الـ trigger `trg_payroll_attendance` ينقله لحالة الحركة
     (`applied` = `approved`، `ignored` = `ignored`). الحقل `deduction_applied` نسخة قديمة من نفس المعنى.
   أي تغيير بمسار القرار لازم يراعي البابين.
4. **الاعتماد** `approve_payroll_slip`: المسير لازم مفتوح ← إعادة مزامنة أيام الموظف ← التعديلات اليدوية وقت الاعتماد تصير حركات
   `bonus`/`manual_deduction` ← `payroll_employee_summary` يحسب ← كشف `salary_slips` + أسطره `salary_slip_lines` ← أقساط السلف
   المستحقة بالفترة (غير النقدية) تتعلّم مدفوعة `paid_by_slip_id`.
5. **التراجع** `revert_payroll_slip` (المسير مفتوح): يحذف الكشف وأسطره وحركات الاعتماد، ويرجع الأقساط غير مدفوعة.
6. **الإغلاق** `close_payroll_period`: يرفض إذا اكو موظف مستحق بدون كشف. الحركات اللي ما انحسمت **تترحّل** للمسير التالي
   (`carried_from`).
7. **بعد الإغلاق:** أي تعديل على يوم بمسير مغلق ما يغيّر الكشف القديم؛ `_payroll_settle` يسوي حركة `adjustment` بأول مسير مفتوح.
8. **إعادة الفتح** `reopen_payroll_period`: للأدمن مع سبب إلزامي يُسجَّل بـ `audit_log`. **الأرشفة** `safe_archive_payroll_month`:
   بعد الإغلاق و60 يوم من آخر اعتماد، وبعدها ما ينفتح.

## السجل المالي للموظف — وين ينحفظ كل شي
| الشي | الجدول |
|---|---|
| الكشوف المعتمدة (الأساسي، الإضافات، الخصومات، الأقساط، الصافي) | `salary_slips` (+ `computed_by_engine`: كشف المحرّك أو قديم) |
| تفاصيل كل كشف سطراً سطراً | `salary_slip_lines` |
| كل حركة (غياب، تأخير، مكافأة، تسوية...) وحالتها ومسيرها | `payroll_events` |
| المكافآت والخصومات اليدوية (والكشوف القديمة قبل المحرّك) | `bonuses_deductions` |
| السلف وأقساطها ومين سددها | `loans`, `loan_installments` (`paid_by_slip_id` أو دفعة نقدية) |
| فترات المسير وحالتها | `payroll_periods`, `archived_months` |

## إضافة نوع حركة جديد (خصم أو مكافأة) — الأماكن اللي لازم تتعدّل
1. قيد `payroll_events.event_type` (migration جديد) + `sync_payroll_day` أو مصدر الحركة.
2. أسماء الأنواع بالسيرفر: `_payroll_settle` (`v_labels`).
3. الويب: `EVENT_LABELS` (و`DECIDABLE` إذا يحتاج قرار) في `web/src/features/payroll/calc.ts`.
4. التطبيق: `_lineLabels` في `mobile/lib/presentation/employee/payslips/payslips_logic.dart` و`_labels` في `mobile/lib/presentation/employee/payslips/widgets/payslip_widgets.dart`.
5. اختبار بـ `supabase/tests/test_payroll_engine.mjs`.

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
- **أشياء بالقاعدة الحية ما موجودة بأي migration** (انعملت يدوياً من لوحة Supabase؛ إذا انبنت قاعدة جديدة من الـ migrations
  ما راح تكون موجودة):
  - `geofence_zones` ← الـ triggers `trg_sync_geofences_to_branches` و`trg_sync_geofence_coordinates`: **رسم منطقة بالويب ينشئ
    أو يعدّل أو يحذف فرعاً بنفس المعرّف** بجدول `branches` (القيم الافتراضية: بغداد، نطاق 150 م).
  - `notifications` ← `on_notification_insert` → `invoke_push_notification()`: كل إشعار ينكتب يرسل push عبر Edge Function.
  - `rls_auto_enable`: event trigger يفعّل RLS تلقائياً على أي جدول جديد بـ `public`.
  تعريفاتهم الحالية بـ `supabase/schema/current_functions.sql`.
- **تقرير الحضور بالتطبيق للعرض فقط** (`mobile/lib/core/logic/attendance_report.dart`): يصنّف "متأخر/خروج مبكر" بقاعدته
  (ما يطرح وقت الإجازة الزمنية مثل السيرفر)، فممكن يطلع "متأخر" بيوم ما انخصم بيه. مصدر الحقيقة للخصم هو `payroll_events`.
- **مكان المنطق بالتطبيق:** القواعد المشتركة بين شاشات بـ `mobile/lib/core/logic/`؛ منطق شاشة وحدة بملف `<الشاشة>_logic.dart` جنبها.
  الأدوار بـ `mobile/lib/core/models/roles.dart` (`Roles.canManage`, `Roles.isAdmin`)؛ والسيرفر هو اللي يفرض الصلاحيات فعلياً.
