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
| **أقساط السلفة: القسط الشهري هو الأساس.** كل قسط ≤ القسط الشهري. الدفع الأقل أو «هالشهر أقل» = الباقي شهر جديد بالأخير «باقي شهر MM/YYYY» (مو زيادة على آخر قسط). التأجيل = قسط الشهر ينتقل لآخر السلفة «مؤجّل من …» والباقي ما يتغير. تعديل السلفة = أقساط بالقسط الشهري بالضبط وآخرها الباقي، من شهر الرواتب المفتوح إذا كشفه ما صادر | `update_loan_and_installments_trigger`، `set_month_installment`، `postpone_loan_installment`، `reschedule_loan` (`20261009000000_smart_loan_installments.sql`) | المعاينات: `previewPayment`، `previewMonthAmount`، `reschedulePlan` (`web/src/features/loans/logic.ts`)؛ الوصف: `installmentOrigin` و`LoanInstallment.originLabel` |
| **«تسجيل دفعة» = فلوس انستلمت فعلاً** (تنحسب مسددة فوراً، فالرواتب ما تخصمها). الشهر اللي يكدر يدفع بيه أقل من راتبه = «هالشهر أقل» (القسط يبقى غير مسدد بالمبلغ الجديد والرواتب تخصمه) | `pay_loan_installment` / `set_month_installment` | — |
| **«استقطاع راتب» اليدوي قبل كشف ذاك الشهر ممنوع** (الكشف هو اللي يخصم القسط؛ اليدوي كان يخليه ما ينخصم أبداً) | `pay_loan_installment` (`20261010000000_payroll_loans_clarity.sql`) | — |
| **القسط يتبع شهر الرواتب مو شهر التقويم:** لحد يوم القطع (26) نفس الشهر، وبعده الشهر الجاي (قسط 28/10 = رواتب 11). اعتماد/إنشاء سلفة يختار «أول شهر يستقطع» والتاريخ = يوم القطع بداخله | `payroll_month_of` | `payrollMonthOfDate`/`cutoffDateOf` (`web/src/features/payroll/period.ts`)، `payrollMonthOf` (`mobile/lib/core/models/loan_model.dart`) |
| **ترك العمل:** الراتب = أجر اليوم × أيام الخدمة لحد «آخر يوم دوام» (يُطلب عند التعطيل). الباقي من السلفة تنبيه، والأدمن يكدر يخصمه (أو جزء) من آخر راتب والباقي يسدد نقداً | `payroll_employee_summary` + `settle_loan_on_exit` | زر «اخصم الباقي من آخر راتب» بتفاصيل الراتب |
| **الراتب حسب سجل الرواتب:** كل تغيير راتب يسري من شهر رواتب (التغيير المباشر من الشهر الحالي، والمجدول من شهر تاريخه)؛ الأشهر الأقدم تبقى براتبها. الزيادة اللي حل شهرها تصير الراتب الحالي | `salary_history`، `payroll_basic_salary`، `apply_due_salary_changes` (`20261011000000_payroll_money_fixes.sql`) | — |
| **الاعتماد بعد نهاية فترة الدوام** (من يوم 27)، إلا آخر راتب لموظف ترك العمل وآخر يوم دوامه فات | `approve_payroll_slip` | `canApproveNow` (`web/src/features/payroll/calc.ts`) |
| **القسط ما يخلي الصافي بالسالب:** وقت الاعتماد ينقص بقد الراتب والباقي شهر جديد «باقي شهر …» (أو يتأجل إذا ما يبقى شي) | `_cap_loans_to_net` | — |
| **القسط المسدد ما ينحذف** (كان يرجع ديناً)، والقسط اللي انخصم من راتب معتمد ما يتراجع إلا بإلغاء اعتماد ذاك الراتب | `guard_paid_installment_delete`، `guard_slip_paid_installment` | — |
| **الخصم/المكافأة اليدوية:** ينسجل منو سجّلها دائماً، ونفس القيد (الموظف/اليوم/المبلغ/السبب) ما يتكرر خلال 10 دقائق | `guard_bonus_deduction_entry` | — |
| **احتساب الرواتب بزر** (مثل أنظمة HR المعروفة): فتح صفحة الرواتب يعرض آخر حساب بدون إعادة؛ «احتساب الرواتب» يحسب المسير كله ويسجّل وقته؛ والتحديث الليلي (00:15) يحسب آخر 3 أيام ويطبّق الزيادات المستحقة. الغياب بدون بصمة يبقى قرار للأدمن (ما ينخصم تلقائياً) | `calculate_payroll`، `get_payroll_run`، `payroll_nightly` (`20261011000100_payroll_calculate.sql`) | خطوة «احسب الرواتب» (`PayrollSteps.tsx`) |
| **المدير يشوف حركات رواتب فرعه بس** | `get_payroll_events` | — |
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
3. **القرار (خصم أو إعفاء):**
   - **إذا لليوم حركة** (الحالة الطبيعية): كل الشاشات تستعمل `decide_payroll_event` — صفحة الرواتب، صفحة التتبع بالويب
     (`web/src/features/tracking/api.ts` تدوّر على الحركة وقت الحفظ)، ولوحة الإدارة بالتطبيق. الدالة تحدّث الحركة **و**
     `attendance.deduction_status`، تمنع المدير من القرار على نفسه أو على فرع ثاني، وتسوّي تسوية إذا الكشف صادر.
   - **الإشعار للموظف بالخصم فقط** (وباعتماد الإضافي). **الإعفاء بدون إشعار**، وملاحظته (مثل «نسي البصمة وهو مداوم») تنحفظ
     بالقرار (`decision_reason`). ملاحظات جاهزة: `web/src/features/payroll/decisionReasons.ts` = `mobile/lib/core/logic/decision_reasons.dart`.
   - **التأخير ما يظهر للموظف قبل الخصم:** إشعار البصمة ما يذكره، ولوحة «المتأخرون اليوم» (`get_late_today`) تعرض بس اللي انخصم.
   - **إذا ماكو حركة بعد** (مثل غياب اليوم قبل ما ينحسب): يُكتب القرار بسجل الحضور مباشرة، والـ trigger `trg_payroll_attendance`
     ينقله لحالة الحركة لما تنحسب (`applied` = `approved`، `ignored` = `ignored`). الحقل `deduction_applied` نسخة قديمة من نفس المعنى.
4. **الاعتماد** `approve_payroll_slip`: المسير لازم مفتوح ← إعادة مزامنة أيام الموظف ← التعديلات اليدوية وقت الاعتماد تصير حركات
   `bonus`/`manual_deduction` ← `payroll_employee_summary` يحسب ← كشف `salary_slips` + أسطره `salary_slip_lines` ← أقساط السلف
   المستحقة بالفترة (غير النقدية) تتعلّم مدفوعة `paid_by_slip_id`.
5. **التراجع** `revert_payroll_slip` (المسير مفتوح): يحذف الكشف وأسطره وحركات الاعتماد، ويرجع الأقساط غير مدفوعة.
6. **الإغلاق** `close_payroll_period`: يرفض إذا اكو موظف مستحق بدون كشف. الحركات اللي ما انحسمت **تترحّل** للمسير التالي
   (`carried_from`).
7. **بعد الإغلاق:** أي تعديل على يوم بمسير مغلق ما يغيّر الكشف القديم؛ `_payroll_settle` يسوي حركة `adjustment` بأول مسير مفتوح.
8. **إعادة الفتح** `reopen_payroll_period`: للأدمن مع سبب إلزامي يُسجَّل بـ `audit_log`. **الأرشفة** `safe_archive_payroll_month`:
   بعد الإغلاق و60 يوم من آخر اعتماد، وبعدها ما ينفتح.
9. **جدول الدوام له تاريخ** (`work_schedule_history`): أي تعديل على أوقات الدوام أو السماحية أو أيامه يسري **من يوم التعديل**،
   والأيام السابقة تنحسب على الجدول اللي جان سارياً وقتها (`payroll_schedule_at`، `payroll_shift_minutes_at`). جدول جديد يسري من يوم إنشائه.
10. **أيام العطل:** الجمعة/العطلة الرسمية ما بيها تأخير ولا خروج مبكر حتى لو الموظف داوم تطوعاً.
11. **ماكو خصم مزدوج:** يوم غياب كامل **معتمد** أو إجازة يومية: الإذن الزمني بنفس اليوم ما ينخصم فوقه. الغياب المعلّق أو المعفى:
    الإذن يبقى محسوباً.

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
4. التطبيق: `kPayrollEventLabels` في `mobile/lib/core/models/salary_slip_model.dart` (قائمة واحدة لكل التطبيق).
5. اختبار بـ `supabase/tests/test_payroll_engine.mjs`.

## المساعد الذكي للأدمن (HR Assistant)
- **للأدمن فقط. الذكاء ما ينفذ أي تغيير بنفسه.** كل دالة بالقاعدة تبدي بـ `require_admin()`، والـ Edge Function تتأكد من الدور.
  القرارات (خصم/إعفاء) تطلع بطاقات، وتنفذ بس لما الأدمن يضغط «تأكيد» (`decide_payroll_event`، نفس صفحة الرواتب). التعاميم تطلع
  مسودة، والنشر من شاشة التعاميم بيد الأدمن. الشي الوحيد اللي ينكتب تلقائياً: نص المحادثة (للأدمن صاحبها، 90 يوم).
- **الأرقام من القاعدة مو من الذكاء:** الذكاء يطلب "أدوات" (دوال `assistant_*` بـ `20261008000000_hr_assistant.sql`)، وملفات Excel
  تنبني بالسيرفر من نفس نتيجة الدالة (`supabase/functions/hr-assistant/excel.ts`). القرار (مخصوم/معفى/بانتظار) يُقرأ من `payroll_events`.
- **الخصوصية:** للذكاء تروح أسماء وأرقام دوام/خصم/سلف بس لما تنسأل؛ ماكو هواتف/إيميلات/مواقع، وروابط الوثائق تروح للشاشة بس.
  المزوّد Gemini (مجاني؛ Google ممكن تستعمل المحادثات). تبديل المزوّد = ملف واحد `gemini.ts`.
- **السؤال بالصوت:** التسجيل يروح لـ Gemini مرة وحدة للنسخ (عراقي حرفياً، الأسماء بإملاء النظام من `assistant_name_hints`) وما
  ينحفظ بأي مكان. النص اللي انفهم يرجع ويظهر كرسالة الأدمن حتى يشوف شنو انفهم.
- **الملخص الصباحي** 10:00 بغداد: أرقام مباشرة من القاعدة (بدون ذكاء)، إشعار واحد لكل أدمن باليوم، يتطفى من قائمة المساعد.
  "المجدولين" = الموظفين غير الأدمن اللي اليوم يوم دوامهم حسب جدولهم بذاك اليوم (وعطلة رسمية = ماكو أرقام).
- **إضافة قدرة جديدة:** دالة `assistant_*` جديدة بالقاعدة (`require_admin`) ← أداة بـ `tools.ts` ← فحص بـ `test_hr_assistant.mjs`
  و`hr_assistant_test.ts`. التطبيق والموقع ما يحتاجون تغيير (يعرضون النص والملفات والوثائق تلقائياً).

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
- **أشياء انعملت يدوياً من لوحة Supabase** وصارت مسجّلة بـ `supabase/migrations/20261005000000_capture_dashboard_objects.sql`
  (بنفس تعريفها الحي، حتى قاعدة جديدة من الـ migrations تطلع مطابقة):
  - `geofence_zones` ← الـ triggers `trg_sync_geofences_to_branches` و`trg_sync_geofence_coordinates`: **رسم منطقة بالويب ينشئ
    أو يعدّل أو يحذف فرعاً بنفس المعرّف** بجدول `branches` (القيم الافتراضية: بغداد، نطاق 150 م).
  - `notifications` ← `on_notification_insert` → `invoke_push_notification()`: كل إشعار ينكتب يرسل push عبر Edge Function.
  - `rls_auto_enable` (event trigger `ensure_rls`): ميزة من منصة Supabase تفعّل RLS تلقائياً على أي جدول جديد — ما مسجّلة
    بملف لأن إنشاءها يحتاج صلاحيات المنصة.
  تعريفاتهم الحالية بـ `supabase/schema/current_functions.sql`.
- **تقرير الحضور بالتطبيق للعرض فقط** (`mobile/lib/core/logic/attendance_report.dart`): يحسب التأخير والخروج المبكر بنفس قاعدة
  المحرّك (يطرح وقت الإجازة الزمنية، و"متأخر" = فوق السماحية أو بصمة "متأخر" وبقت دقائق). فرق مقصود واحد: موظف بدون جدول يُقاس
  على 09:00–17:00 بالتقرير، والمحرّك ما يحسب له تأخير. مصدر الحقيقة للخصم هو `payroll_events`.
- **مكان المنطق بالتطبيق:** القواعد المشتركة بين شاشات بـ `mobile/lib/core/logic/`؛ منطق شاشة وحدة بملف `<الشاشة>_logic.dart` جنبها.
  الأدوار بـ `mobile/lib/core/models/roles.dart` (`Roles.canManage`, `Roles.isAdmin`)؛ والسيرفر هو اللي يفرض الصلاحيات فعلياً.
