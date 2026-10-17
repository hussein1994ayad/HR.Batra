# قواعد العمل — أين تعيش كل قاعدة

**المصدر الأساسي هو قاعدة البيانات**: السيرفر يحسب ويرفض. **النسخة الحالية** من كل دالة وكل trigger موجودة بملف واحد للقراءة:
`supabase/schema/current_functions.sql` (فيه فهرس: الدالة ← آخر migration عرّفها). لا تعتمد على أول ملف migration تلگاه:
بعض الدوال تعرّفت من جديد لحد 10 مرات (مثلاً `sync_payroll_day`). بعد كل migration جديد أعد التوليد: `node supabase/schema/generate.mjs` (يبني من ملفات migrations بدون اتصال، والفحص التلقائي يفشل إذا نسيته).
الويب والتطبيق ينسخون بعض القواعد فقط لعرض تنبيه أو معاينة قبل الإرسال — إذا غيّرت قاعدة
غيّر المصدر أولاً ثم نسخها بنفس القيمة، وشغّل فحوصات الثلاثة (`supabase/tests`, `web`, `mobile`).

| القاعدة | المصدر (السيرفر) | نسخ للعرض/التنبيه |
|---|---|---|
| **الحضور:** متأخر إذا بعد بداية الدوام + فترة السماح (الافتراضي 08:30 + 15 دقيقة) | `punch_attendance` — آخر نسخة `20261004000000_punch_rejects_low_accuracy.sql` | `web/src/features/tracking/logic.ts` (`manualAttendanceStatus`)، `mobile/lib/core/logic/attendance_rules.dart` |
| **الانصراف المبكر:** قبل نهاية الدوام بأكثر من 15 دقيقة | `punch_attendance` + محرّك الرواتب (`payroll_events`) | `mobile/lib/presentation/employee/attendance/attendance_logic.dart` (`punchNote` — تأكيد قبل الانصراف) |
| **نطاق الفرع:** المسافة ≤ نصف القطر + 10 م تسامح | `punch_attendance` (`c_distance_tolerance_m`) | `mobile/lib/presentation/employee/attendance/attendance_logic.dart` (`localPunchError` — فحص قبل الإرسال) |
| **دقة الـ GPS:** ≤ 100 م (أو نطاق الفرع إذا أوسع) | `punch_attendance` (`c_max_accuracy_m`) | `mobile/lib/core/services/precise_location.dart` (`maxPunchAccuracyMeters`) |
| **البصمة بدون إنترنت:** تُقبل خلال 48 ساعة، وليس بالمستقبل. وقتها **مؤكد** إذا التطبيق حسبه من آخر وقت سيرفر + عدّاد الموبايل منذ التشغيل (ما يتأثر بتغيير الساعة ولا بإطفاء الشاشة)؛ وإلا (الموبايل انطفى وشغل، ماكو وقت سيرفر سابق، تطبيق قديم) = ساعة الموبايل و**«تحتاج مراجعة»**. وقت ساعة الموبايل ينحفظ للمقارنة. الأدمن أو مدير الفرع يعلّم «تمت المراجعة» (ينسجل)، وتعديل الوقت = «يدوي» | `punch_attendance` (`p_trusted_time`، `p_time_check`، `c_offline_max_age`)، `server_now`، `track_attendance_time_source`، `mark_offline_punch_reviewed` (`20261019000000_fix_attendance_offline_punch_time.sql`) | `offline_punch_time.dart` (الحساب)، `trusted_clock.dart` (العدّاد عبر قناة `clockSnapshot` بأندرويد والآيفون)، `attendance_sync_service.dart` (يحتفظ ببصمة موظف آخر 48 ساعة)؛ العرض: `punchTimeInfo` (`web/src/features/tracking/logic.ts`)، `ReportAttendance.needsOfflineReview` |
| **دورة الراتب:** من يوم (القطع+1) للشهر السابق حتى يوم القطع (الافتراضي 27 ← 26) | إعدادات الشركة `cutoff_day` / `payment_day` + `payroll_schedule()` | `web/src/features/payroll/period.ts` |
| **أجر اليوم = الراتب ÷ 30، وأجر الدقيقة = أجر اليوم ÷ دقائق دوام الموظف** | `payroll_daily_rate` / `sync_payroll_day` (آخر نسخة `20261002000000_full_qa_fixes.sql`) | لا أحد يعيد حسابها: الويب والتطبيق يعرضون أرقام السيرفر (`get_payroll_run`, `get_my_payroll_preview`) |
| **الخصم لا يتجاوز الراتب الشهري، وأي مبلغ ≤ 100,000,000** | `check_bonus_deduction_amount` (`20261002000000_full_qa_fixes.sql`) | — |
| **السلفة:** لا سلفة جديدة مع سلفة جارية، ولا طلبين معلّقين | `_validate_loan_terms` (اعتماد الأدمن، `20261003000000_admin_loans_over_half_salary.sql`) + `one_pending_loan_request` (طلب الموظف، `20261004000100_employee_loan_request_over_half_salary.sql`) | `mobile/lib/presentation/employee/loan/loan_request_logic.dart` (`loanRequestError`) |
| **السلفة:** قسط فوق نص الراتب **مسموح مع تنبيه**؛ طلب الموظف ≤ 100,000,000 | نفس الدالتين (لا تمنع نص الراتب) | النسبة: `LOAN_SALARY_WARNING_RATIO` (`web/src/features/loans/logic.ts`) و`kLoanSalaryWarningRatio` (`mobile/lib/core/logic/loan_rules.dart`)؛ التنبيه: `overHalfSalaryWarning`، `loanSalaryWarning` |
| **العطل الرسمية والأسبوعية:** لا غياب ولا تذكير بصمة | `sync_payroll_day` (`v_workday`) + `official_holidays` | `mobile/lib/core/logic/reminder_plan.dart` |
| **التتبع:** بين بصمة الحضور والانصراف فقط، ومعلن للموظف | — (سياسة) | `mobile/lib/core/services/location_service.dart` + `core/services/location/` (أندرويد)، `mobile/ios/Runner/LocationMonitorIOS.swift` (آيفون) |

| **السلفة النقدية** (`payment_method = 'cash'`): أقساطها ما تنخصم من الراتب | `payroll_employee_summary` + `approve_payroll_slip` | — |
| **أقساط السلفة: القسط الشهري هو الأساس.** كل قسط ≤ القسط الشهري. الدفع الأقل أو «هالشهر أقل» = الباقي شهر جديد بالأخير «باقي الشهر العاشر 2026» (مو زيادة على آخر قسط). التأجيل = قسط الشهر ينتقل لآخر السلفة «مؤجّل من …» والباقي ما يتغير. تعديل السلفة = أقساط بالقسط الشهري بالضبط وآخرها الباقي، من شهر الرواتب المفتوح إذا كشفه ما صادر | `update_loan_and_installments_trigger`، `set_month_installment`، `postpone_loan_installment`، `reschedule_loan` (`20261009000000_smart_loan_installments.sql`) | المعاينات: `previewPayment`، `previewMonthAmount`، `reschedulePlan` (`web/src/features/loans/logic.ts`)؛ الوصف: `installmentOrigin` و`LoanInstallment.originLabel` |
| **«تسجيل دفعة» = فلوس انستلمت فعلاً** (تنحسب مسددة فوراً، فالرواتب ما تخصمها). الشهر اللي يكدر يدفع بيه أقل من راتبه = «هالشهر أقل» (القسط يبقى غير مسدد بالمبلغ الجديد والرواتب تخصمه) | `pay_loan_installment` / `set_month_installment` | — |
| **«استقطاع راتب» اليدوي قبل كشف ذاك الشهر ممنوع** (الكشف هو اللي يخصم القسط؛ اليدوي كان يخليه ما ينخصم أبداً) | `pay_loan_installment` (`20261010000000_payroll_loans_clarity.sql`) | — |
| **القسط يتبع شهر الرواتب مو شهر التقويم:** لحد يوم القطع (26) نفس الشهر، وبعده الشهر الجاي (قسط 28/10 = رواتب 11). اعتماد/إنشاء سلفة يختار «أول شهر يستقطع» والتاريخ = يوم القطع بداخله | `payroll_month_of` | `payrollMonthOfDate`/`cutoffDateOf` (`web/src/features/payroll/period.ts`)، `payrollMonthOf` (`mobile/lib/core/models/loan_model.dart`) |
| **ترك العمل (قرار 15/10/2026):** آخر راتب = أجر اليوم × **أيام الدوام** من بداية المسير (أو المباشرة) لحد «آخر يوم عمل»، حتى لو ما بصم. الجمع/العطل الأسبوعية والعطل الرسمية ما تنحسب. ينخصم بس اللي قررته الإدارة (غياب، تأخير، إجازة بدون راتب أو زمنية). آخر يوم = يوم القطع ← راتب كامل. آخر يوم بعد يوم القطع (مثلاً 28 والمسير ينتهي 26) ← المسير المنتهي كامل، وأيام الدوام 27–28 بالمسير اللي بعده، وكشفه ينعتمد أول ما يفوت آخر يوم. الباقي من السلفة تنبيه، والأدمن يكدر يخصمه (أو جزء) من آخر راتب والباقي يسدد نقداً | `payroll_employee_summary` (`basic_basis`/`basic_note`) + `settle_loan_on_exit` (`20261020000000_fix_payroll_partial_exit_and_slip.sql`) | زر «اخصم الباقي من آخر راتب» بتفاصيل الراتب |
| **الراتب حسب سجل الرواتب:** كل تغيير راتب يسري من شهر رواتب يختاره الأدمن («من راتب يا شهر؟»): هذا الشهر = يتغير الراتب هسه، شهر جاي = مجدول ويتطبق وحده؛ الأشهر الأقدم تبقى براتبها. الزيادة اللي حل شهرها تصير الراتب الحالي | `salary_history`، `payroll_basic_salary`، `apply_due_salary_changes` (`20261011000000_payroll_money_fixes.sql`) | `salaryUpdateFields` (`web/src/features/employees/logic.ts`) |
| **الاعتماد بعد نهاية فترة الدوام** (من يوم 27)، إلا آخر راتب لموظف ترك العمل وآخر يوم دوامه فات | `approve_payroll_slip` | `canApproveNow` (`web/src/features/payroll/calc.ts`) |
| **القسط ما يخلي الصافي بالسالب:** وقت الاعتماد ينقص بقد الراتب والباقي شهر جديد «باقي شهر …» (أو يتأجل إذا ما يبقى شي) | `_cap_loans_to_net` | — |
| **القسط المسدد ما ينحذف** (كان يرجع ديناً)، والقسط اللي انخصم من راتب معتمد ما يتراجع إلا بإلغاء اعتماد ذاك الراتب | `guard_paid_installment_delete`، `guard_slip_paid_installment` | — |
| **الخصم/المكافأة اليدوية:** ينسجل منو سجّلها دائماً، ونفس القيد (الموظف/اليوم/المبلغ/السبب) ما يتكرر خلال 10 دقائق | `guard_bonus_deduction_entry` | — |
| **احتساب الرواتب بزر** (مثل أنظمة HR المعروفة): فتح صفحة الرواتب يعرض آخر حساب بدون إعادة؛ «احتساب الرواتب» يحسب المسير كله ويسجّل وقته؛ والتحديث الليلي (00:15) يحسب آخر 3 أيام ويطبّق الزيادات المستحقة. الغياب بدون بصمة يبقى قرار للأدمن (ما ينخصم تلقائياً) | `calculate_payroll`، `get_payroll_run`، `payroll_nightly` (`20261011000100_payroll_calculate.sql`) | خطوة «احسب الرواتب» (`PayrollSteps.tsx`) |
| **«احتساب الرواتب» على دفعات (تدقيق 14/10 BUG-018):** الموقع يحسب 10 موظفين بكل طلب ويبين «جاري الاحتساب: 20 من 120 موظف»، وآخر دفعة تسجّل وقت الاحتساب. السبب: القاعدة توقف طلب المستخدم بعد 8 ثواني، وبالسيرفر الحي كل موظف بمسير كامل ياخذ ~45 ملي ثانية (~150 موظف يوصلون الحد بطلب واحد). نفس النتيجة بالضبط مثل الطلب الواحد (يبقى للنسخ القديمة) | `calculate_payroll_batch` (`20261022000000_payroll_concurrency_and_batches.sql`) | `calculatePayroll` (`web/src/features/payroll/api.ts`)، `PayrollSteps.tsx` |
| **ماكو حركة رواتب مكررة (PAY-007):** حساب نفس الموظف ونفس اليوم (أو نفس القيد اليدوي) من طلبين بنفس اللحظة: الثاني ينتظر الأول. وقيود فريدة بالقاعدة: حركة فعالة وحدة لكل موظف ويوم ونوع ومصدر، ولكل قيد يدوي، وتسوية مفتوحة وحدة لكل حركة. الحلقات تمشي على الموظفين بنفس الترتيب حتى الأقفال ما تتعاكس | `sync_payroll_day`، `sync_payroll_manual` (`pg_advisory_xact_lock`)، `uq_payroll_events_*` | — |
| **إجازة طويلة (BUG-013):** اعتماد الإجازة يحسب كل أيامها اللي فاتت مهما طالت، والقادمة لحد 92 يوم من اليوم (الباقي بالمهمة الليلية والاعتماد) | `trg_payroll_leave` | — |
| **مدير الفرع لفرعه بس:** يشوف حضور وإجازات ورصيد ومواقع GPS ووقفات ومخالفات وحركات رواتب موظفي فرعه (بدون أي مبلغ)، ويكتب إشعار لفرعه. يقرر على طلبات وحركات فرعه المعلّقة (خصم بالمبلغ المحسوب أو إعفاء، بدون ما يشوف أو يكتب مبلغ)، ومو على نفسه. المكافآت والخصومات اليدوية ما يشوفها. بعد قرار الإجازة، تعديلها للأدمن بس. الفروع وأوقات الدوام والأجهزة والمستمسكات والسلف للأدمن بس | `managed_employee_ids()` بسياسات الجداول، `protect_leave_decisions`، `get_payroll_events` (`20261018000000_fix_rls_manager_scope_and_limits.sql`) | `kAdminOnlyRoutes` (`mobile/lib/core/routes/app_router.dart`)، `_adminOnlyTools`، `ensureChanged` (`mobile/lib/data/repositories/write_guard.dart`) |
| **الراتب ما ينقرا من جدول الموظفين مباشرة:** أعمدة الراتب ممنوعة على أي مستخدم؛ الأدمن (والموظف لراتبه) يقراها من `get_employee_pay`، والمدير ما يوصله شي. ونفس الشي مبالغ حركات الرواتب (المبلغ، أجر اليوم والدقيقة): الأدمن يقراها من `get_payroll_event_amounts`، وأجر اليوم (`payroll_day_rates`) للأدمن بس. **أي عمود جديد بالجدولين لازم ينقرر (ينقرا أو مخفي)**: الفحص `test_column_grants.mjs` يفشل لحد ما ينقرر، ويتأكد إن قائمة الموقع والتطبيق مطابقة | `GRANT SELECT (…)` + `get_employee_pay` + `get_payroll_event_amounts` (`20261018000100_hide_pay_amounts_from_managers.sql`، `20261018000000_fix_rls_manager_scope_and_limits.sql`) | `EMPLOYEE_COLUMNS`/`fetchEmployeePay` (`web/src/lib/employeePay.ts`)، `kEmployeeColumns`/`fetchEmployeePay` (`mobile/lib/data/repositories/employee_pay.dart`) |
| **السلفة المعتمدة ما ترجع مرفوضة أو ملغاة** (أقساطها كانت توكف). غلط بيها = تعديل؛ تسددت = أرشفة | `guard_loan_status` (`20261018000000_fix_rls_manager_scope_and_limits.sql`) | — |
| **بدون بصمة انصراف:** خصم مقترح = دقائق الدوام بعد آخر تواجد مسجّل (آخر نقطة تتبع، وإلا بصمة الحضور)، ينتظر قرار الأدمن (خصم أو إعفاء إذا نسي وهو مداوم) — ما ينخصم تلقائياً. القرار القديم يبقى مثل ما تقرر | `sync_payroll_day` (`20261011000200_payroll_data_quality.sql`) | بطاقة القرار (الموقع + `decision_card.dart`) |
| **خصم التأخير ما يتجاوز أجر يوم واحد:** التأخير بالدقيقة من بداية الدوام، وسقفه أجر اليوم (مثل الغياب) — بصمة بعد نهاية الدوام ما تطلع بأجر يومين. الدقائق تبقى للعرض، والمبلغ اللي يكتبه الأدمن يبقى مثل ما كتبه | `sync_payroll_day` (`20261013000000_late_capped_at_daily_rate.sql`) | الرئيسية بالتطبيق تكتب «غائب» بعد نهاية الدوام (`HomeTodayCard`) |
| **مبلغ الخصم يتعدل عند القرار:** الأدمن يشوف المبلغ المحسوب (غياب/تأخير/خروج مبكر/بصمة ناقصة) ويكدر يكتب غيره قبل الخصم (مثل نص يوم). المعدّل ينحفظ ويبقى بعد أي إعادة حساب، ينمسح إذا القرار صار إعفاء، وحده: الغياب/التأخير/الخروج المبكر/البصمة الناقصة ≤ أجر يوم، والإضافي ≤ المحسوب (العقوبة الأكبر = «خصم يدوي»، والزيادة = «مكافأة»). مدير الفرع ما يشوف المبالغ ولا يكتب مبلغ (منها ينعرف الراتب). خصم بدون مبلغ = المحسوب | `decide_payroll_event(…, p_amount)`، `payroll_events.amount_override`، `sync_payroll_day` (`20261012000000_decision_amount_and_absent_board.sql`، الحدود `20261018000000_fix_rls_manager_scope_and_limits.sql`) | حقل «مبلغ الخصم»: `decision_card.dart`، `useConfirmAnswer` (`web/src/components/confirm.tsx`) |
| **غياب اليوم قبل الاحتساب:** القرار يمر بباب واحد بالسيرفر (يسجّل اليوم غياب ثم نفس قواعد القرار)، ومبلغه = أجر اليوم يبين قبل القرار | `decide_absence_day`، `payroll_day_rates` | `applyDecision` (`admin_actions_repository.dart`)، `saveDecision` (`web/src/features/tracking/api.ts`) |
| **«الغائبون اليوم» بلوحة التعاميم:** يطلع بس اللي الإدارة طبّقت خصم غيابه اليوم (نفس قاعدة «المتأخرون اليوم»)، بدون مبالغ | `get_absent_today` | `AbsentTile` (`people_widgets.dart`) |
| **موظف نشط لازم يكون إله فرع**؛ والقديم بدون فرع قراره ما يعلق (فرع احتياطي) | `check_employee_branch`، `decide_payroll_event` | تنبيه «بيانات ناقصة» بالرواتب |
| **العطلة الرسمية داخل الإجازة ما تنحسب من رصيد الإجازة** | `leave_request_days` | — |
| **أرشفة شهر:** تنزّل ملف Excel بالحضور والرواتب قبل الحذف، وتطلب كشوف اللي جانوا بالخدمة بذاك الشهر بس | `safe_archive_payroll_month` | `downloadMonthBeforeArchive` (`web/src/features/payroll/archiveExport.ts`) |
| **تنظيف مسير مغلق:** الحضور ينحذف بس إذا المسير مغلق + المسير اللي بعده مغلق (رواتبه تسلّمت) + ماكو حركة تنتظر قرار لأيامه؛ التتبع والإشعارات يكفيها المسير مغلق. معاينة بالأعداد قبل الحذف، تنفيذ بمعاملة وحدة، ما يتكرر، وينسجل منو ومتى وكم سطر. الكشوف وسطورها وحركات الرواتب ما تنلمس | `payroll_cleanup_preview`، `payroll_cleanup_run`، `payroll_cleanups` (`20261014000000_safe_cleanup.sql`) | `PayrollCleanupSection.tsx` (الإعدادات ← تنظيف البيانات) |
| **يوم انحذف حضوره ما ينعاد حسابه** (أرشفة أو تنظيف): حركاته المعتمدة هي التاريخ. كان حذف الحضور يرجّع خصومات الشهر للموظفين كتسوية بالمسير المفتوح. التصحيح بعد التنظيف (نزاع) يبقى من قرار الحركة نفسها | `payroll_day_frozen`، `sync_payroll_day`، `manual_purge_month_data` | — |
| **السلفة المسددة تتأرشف وما تنحذف مباشرة:** الأرشفة تكتب سجل مالي دائم مختصر (رقم مرجعي `L-0007`، الموظف، المبلغ، كل استقطاع بتاريخه ومبلغه وطريقته ورواتب يا شهر، تاريخ التسوية، الرصيد صفر) ثم تحذف السلفة وأقساطها بخطوة وحدة. شروطها: مسددة بالكامل + كل كشف خصم منها بمسير مغلق. السجل للعرض والإثبات بس، ما يدخل بحساب الرواتب (مبلغ القسط محفوظ بكشفه). الطلبات غير المعتمدة تنحذف عادي | `archive_settled_loan`، `loan_archive_blocker`، `guard_loan_delete`، `settled_loans`، `assign_loan_no` (`20261016000000_settled_loans_archive.sql`) | `archiveSettledLoan` (`web/src/features/loans/api.ts`)، `SettledLoansTable.tsx`، `statementExport.ts` |
| **كشف راتب بيه قسط سلفة تأرشفت ما ينلغي اعتماده** (القسط ما يرجع ينخصم لأن السلفة انحذفت) | `guard_slip_with_archived_loan` | — |
| **«تم تسليم الرواتب»:** الأدمن يأكد تسليم رواتب المسير المغلق؛ إعادة فتح المسير تمسح التأكيد. حضور مسير ينحذف بس بعد ما يتسلّم المسير اللي بعده | `mark_payroll_delivered`، `payroll_periods.delivered_at`، `payroll_cleanup_preview/run` | الخطوة 6 بـ`PayrollSteps.tsx` |
| **تنظيف السلف من شاشة التنظيف:** يأرشف كل المسددة المؤهلة ويحذف الطلبات المرفوضة/الملغاة الأقدم من 30 يوم؛ المعاينة تبين المستثناة وسببها وتقدير المساحة، وينسجل بسجل التنظيف | `loans_cleanup_preview`، `loans_cleanup_run` | `LoansCleanupCard.tsx`، `cleanupReport.ts` (تقرير المعاينة Excel) |
| **سجلات النظام تنظف يومياً:** سجل المهام المجدولة أقدم من 7 أيام، وردود طلبات الإشعارات إذا كبرت (كانت 90% من حجم القاعدة) | `purge_system_logs` (مهمة `system_logs_cleanup` 06:45 بغداد) | — |
| **عمر بيانات التتبع رقم واحد من الإعدادات (45 يوم، بين 35 و 366):** التنظيف اليومي يحذف نقاط GPS والوقفات والمخالفات الأقدم منه. الحد الأدنى 35 حتى يخلص مسير الرواتب اللي يخصها (البصمة الناقصة تعتمد على آخر نقطة) | `check_archive_policy`، `perform_daily_cleanup`، `purge_old_location_tracking` (`20261015000000_single_tracking_retention.sql`) | `GeneralSettings.tsx` |
| **تعديل خانة بجدول الرواتب** = مكافأة/خصم بالفرق ينحفظ فوراً بسبب مكتوب (يطلع بكشف الموظف) | — | `saveOverride` (`usePayroll.ts`) |
| **رجوع الموظف للعمل (قرار 15/10/2026):** «تفعيل الحساب» يطلب تاريخ الرجوع (الافتراضي اليوم، وما يكون بالمستقبل). أيام الانقطاع ما تطلع غياب، والراتب = الراتب ناقص أجر أيام الانقطاع (`basic_basis = returned` ويا سطر شرح). إذا راتب شهر الرجوع معتمد من قبل يطلع تنبيه حتى ينلغي اعتماده ويرجع ينعتمد. التفعيل من نسخة قديمة = رجع اليوم | `reactivate_employee`، `set_termination_date`، `payroll_employee_summary` (`20261021000000_employee_assignment_history.sql`) | استرجاع من الأرشيف (`useEmployees.ts`)، «تفعيل الحساب» `employee_management_screen.dart` |
| **سجل الموظف:** باشر، انتقل من فرع لفرع أو قسم، ترك، رجع — بالتاريخ. للأدمن، ومدير فرعه، والموظف لنفسه (ماكو مبالغ). السجل يكتبه النظام بس | `get_employee_history`، `record_employee_assignment` | `EmployeeHistoryCard.tsx`، `employee_profile_sheet.dart` |
| **إنهاء خدمات موظف:** آخر يوم عمل المقترح = آخر يوم بصم بيه، وقبل التأكيد تطلع **معاينة آخر راتب** لكل مسير مفتوح (شلون انحسب، الخصومات، السلفة، الصافي، ومتى ينعتمد) والمجموع وباقي السلف. المعاينة تحسب على السيرفر وتتراجع (ما يتغير شي) | `end_of_service_preview` (أدمن بس) | «إنهاء خدمات الموظف» `DeleteEmployeeModal.tsx`، «إنهاء الخدمات» `employee_management_screen.dart` |
| **عمليات الموظف بخطوة وحدة (تدقيق 14/10 CODE-005):** تعديل الموظف (الإيميل وكلمة السر والبيانات)، إنهاء الخدمات (أرشفة/حذف مجدول/حذف فوري + سجل الأرشيف)، الاسترجاع، والإتلاف: كل وحدة بالسيرفر بمعاملة وحدة، يا كلشي ينحفظ يا ولا شي. (كان خيار «أرشفة» يعطّل الموظف ويفشل بنص الطريق لأن نوعه انكتب غلط) | `save_employee`، `end_employee_service`، `restore_archived_employee`، `destroy_archived_employee` (`20261023000000_employee_files_and_operations.sql`) | `web/src/features/employees/api.ts` |
| **المستمسكات والصورة للسلة، مو حذف مباشر (BUG-008، BUG-009):** المستمسك اللي ينشال من قائمة الموظف (الموقع أو التطبيق) تحطه القاعدة بالسلة 30 يوم **بعد ما ينحفظ التعديل** (إذا الحفظ فشل ما يصير شي). والحذف النهائي للموظف يحط كل مستمسكاته وصورته بالسلة. بس الملفات الموجودة فعلاً، ومرة وحدة. تبديل الصورة الشخصية يتكفل بيه التطبيق | `trash_removed_employee_files` | `employee_documents.dart`، `updateEmployee` |
| **رقم الموظف تلقائي بالتسلسل (BUG-010):** بدون كود = EMP-003، EMP-004... (يكمل بعد أكبر رقم موجود ويتخطى المحجوز). الكود اللي يكتبه الأدمن يبقى | `assign_employee_code`، `next_employee_code`، `employee_code_seq` | `createEmployee` (الموقع)، `employee_form_sheet.dart` |
| **الأوقات بتوقيت بغداد بالموقع (BUG-007):** البصمة اليدوية وتعديل الأوقات وعرضها، وبداية/نهاية اليوم بالفلاتر والتعاميم، و«اليوم»: كلها بتوقيت بغداد (+3، بدون توقيت صيفي) حتى لو كمبيوتر الأدمن على توقيت ثاني | — | `baghdadIso`، `baghdadHM`، `getLocalDateStr` (`web/src/lib/dates.ts`)، `formatClock` |
| **التطبيق بتوقيت بغداد (تدقيق 14/10، المرحلة 9):** «الوقت المحلي» داخل التطبيق = ساعة بغداد: كل وقت من السيرفر ينقرا بساعة بغداد، «اليوم» وساعة اليوم من ساعة بغداد، والوقت اللي يختاره المستخدم يروح للسيرفر كوقت بغداد. موبايل مضبوط على توقيت ثاني (مسافر أو غلط) يشوف نفس الأوقات والتواريخ. على موبايل بتوقيت العراق النتيجة نفسها بالضبط. المُدد بين لحظتين (مثل تحديث كل 15 دقيقة) تبقى بساعة الموبايل | — | `toCompanyTime`، `companyNow`، `companyWallToUtc`، `parseServerTime` (`mobile/lib/core/utils/company_time.dart`)، `Fmt` |
| **يوم القطع بالتطبيق من إعدادات السيرفر (CODE-004):** أسماء أشهر أقساط السلف تتبع `payroll_policy.cutoff_day` (يتحدث كل ما تنقرا السلف؛ الافتراضي 26) | `system_settings` | `PayrollSettings` (`mobile/lib/core/logic/payroll_settings.dart`)، `payrollMonthOf` |
| **الراتب إجباري (CODE-013):** ماكو راتب افتراضي مخفي (كان 600,000)؛ إضافة موظف بدون راتب = خطأ واضح، والنموذج بالموقع والتطبيق يطلبه | `employees.monthly_salary_iqd` NOT NULL بدون default | `EmployeeFormModal.tsx`، `employee_form_sheet.dart` |
| **رمز الإشعارات بمكان واحد (CODE-007):** `fcm_tokens` بس. `device_tokens` وعمود `employees.fcm_token` انحذفوا (المرحلة 10؛ رموزهم انتقلت قبل الحذف). دالة الإرسال تقرا `fcm_tokens` بس | `fcm_tokens`، `push-notification` | `notification_service.dart` |
| **تعديل ما أثّر = خطأ (CODE-009):** تعديلات وحذف الإدارة (والموظف لملفه) بالموقع والتطبيق تتأكد إن سطر تغيّر فعلاً؛ إذا سياسة منعت بصمت يطلع «ما تغيّر شي» بدل نجاح كاذب | — | `ensureChanged` (`web/src/lib/write-guard.ts`، `mobile/lib/data/repositories/write_guard.dart`) |
| **قائمة أشهر الرواتب تبدي من أول مسير بالقاعدة (BUG-017)** (بعد التصفير: الشهر العاشر 2026)، وكذلك قائمة تنظيف المسيرات | `payroll_periods` | `useFirstPayrollMonth`، `payrollMonthOptions` |
| **دالة تنظيف السلة (daily-cleanup) تشتغل بس من المهمة المجدولة (BUG-019):** المهمة تصدر كود مؤقت لكل تشغيلة بترويسة `x-cleanup-token`، والدالة تقبله مرة وحدة وخلال ساعة. ماكو كلمة سر تنحفظ بمكان | `issue_cleanup_token`، `cleanup_run_tokens`، مهمة `daily_trash_storage_cleanup` | `supabase/functions/daily-cleanup/index.ts` |
| **المباشر بنص المسير (قرار 15/10/2026):** من يوم مباشرته مثل أي موظف: الراتب ناقص أجر الأيام قبل المباشرة (كل يوم = أجر يوم، مهما كان طول المسير 26–31). كان: أجر اليوم × أيام الخدمة بحد 30 (بمسير 28 يوم، يوم واحد متأخر = خصم 3 أيام). كل حساب ويا سطر شرح (`basic_note`) يطلع بتفاصيل الراتب | `payroll_employee_summary` | `AttendanceBreakdownModal.tsx` |
| **راتب كامل بدون بصمات (PAY-008، قرار: بدون تغيير):** الموظف ياخذ راتبه كامل إلا إذا الإدارة قررت غياب (ينسون البصمة أو عندهم شغل برا). الغياب بدون بصمة يبقى «ينتظر قرار» | `sync_payroll_day` | — |
| **خصومات أكثر من الراتب (قرار 15/10/2026):** الكشف ينعتمد عادي حتى ينغلق المسير: قسط السلفة ينقص أول (والباقي بآخر السلفة)، وإذا الخصومات بعدها أكثر = **صافي صفر** وسطر «خصومات ما انخصمت» بالفرق، والشركة تسويه ويا الموظف خارج النظام | `approve_payroll_slip` (سطر `excess_deduction`) | تنبيه الصافي السالب بـ`attentionReasons` |
| **التقريب:** لأقرب دينار على **مجموع** الكشف وليس يوم بيوم. سطور الكشف بالدينار، وإذا جمعها يختلف عن المجموع بسبب التقريب ينضاف سطر «فرق تقريب» | `payroll_employee_summary` (`net`)، `approve_payroll_slip` (سطر `rounding`) | — |
| **إلغاء اعتماد كشف يرجّع جدول السلفة:** الأقساط اللي نقصت أو تأجلت وقت الاعتماد (لأن الراتب ما كفى) ترجع مثل ما جانت. إذا جدول السلفة تغيّر بعدها (قسط انسدد أو إعادة جدولة) يبقى الجدول الحالي (مجموعه صحيح) | `_cap_loans_to_net` + `payroll_loan_caps` + `revert_payroll_slip` | — |

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
   - **التأخير ما يظهر للموظف قبل الخصم:** إشعار البصمة ما يذكره، ولوحة «المتأخرون اليوم» (`get_late_today`) تعرض بس اللي انخصم، والموظف يشوف بحركاته وبمعاينة «راتبي» المعتمد بس (`get_my_payroll_preview`، سياسة `payroll_events`).
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
   **وفرع الموظف وقسمه لهم تاريخ** (`employee_assignment_history`، تدقيق 14/10 PAY-002): نقل الموظف لفرع أو قسم ثاني يسري **من يوم التغيير**
   (قرار 15/10/2026، بدون اختيار تاريخ)، والأيام السابقة تنحسب على دوام الفرع/القسم اللي جان بيه ذاك اليوم (`employee_assignment_at`).
   الموظفين الموجودين قبل التحديث: فرعهم الحالي من البداية.
   **وفترات الانقطاع** (`employee_service_breaks`، PAY-009): الموظف اللي ترك ورجع، الأيام بين آخر يوم عمل ويوم رجوعه «خارج الخدمة»
   (`employee_in_service`): ما بيها غياب ولا حركات، وتنقص من راتب ذاك المسير مثل الأيام قبل المباشرة (قرار 15/10/2026).
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
- **ملف أساس واحد بدل 95 ملف (المرحلة 10، CODE-002):** `supabase/migrations/20261025000000_create_baseline_schema.sql` = القاعدة مثل ما تطلع
  من الملفات القديمة بالضبط (بـ `supabase/migrations_archive` للقراءة بس). مولّد بـ `node supabase/schema/baseline.mjs`، والفحص التلقائي
  (`--check`) يتأكد إنه نفس الأرشيف بكل شي (3469 عنصر + البيانات). يبدي بقفل: على قاعدة موجودة يوكف، فعلى السيرفر الحي ينسجل كمطبّق بـ
  `supabase migration repair` وما يشتغل. الملفات الجديدة تنكتب بعده بـ `supabase/migrations` مثل قبل. **أمر تحديث القاعدة يشتغل بس من
  مجلد المشروع المحدّث** (نسخة قديمة فيها الـ 95 ملف ممكن تحاول تعيدها). المقارنة ويا الحية: `node supabase/schema/baseline.mjs --live`.
- **الشاشات لا تكلّم Supabase مباشرة:** كل الاستعلامات في `mobile/lib/data/repositories/` (الويب: `web/src/features/<x>/api.ts`).
  الخدمات في `core/services` (البصمة، التتبع، الإشعارات، الرفع) بنية تحتية وتبقى تكلّم القاعدة.
- **الشاشات تقرا البيانات من نماذج (تدقيق 14/10، CODE-014):** المستودعات ترجّع نماذج (`AttendanceModel`، `WorkScheduleModel`،
  `BranchModel`، `DirectoryEntry`، `SalarySlipLine`، `PayslipDetail`، `LeaveTypeOption`…) والشاشات ما تقرا `row['...']` بنفسها.
  القيم الافتراضية اللي تعرضها كل شاشة («موظف»، «القسم العام»، `--:--`) تبقى بالشاشة نفسها. المسموح يبقى خريطة:
  البيانات اللي تنرسل للسيرفر (insert/update/rpc)، وصفوف التتبع الحي اللي تروح كما هي لـ `buildTracking` (`core/logic/tracking_rules.dart`).
  كاش البصمة بالجهاز (`attendance_cache.json`) يبقى بنفس أعمدة الجدول، فكاش النسخ القديمة ينقرا عادي.
- **أشياء انعملت يدوياً من لوحة Supabase** وصارت مسجّلة بـ `supabase/migrations_archive/20261005000000_capture_dashboard_objects.sql`
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
