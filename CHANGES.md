# Refactor Changes

إعادة هيكلة بدون تغيير السلوك. كل خطوة commit منفصل على `design-v2` ومفحوصة
(`flutter analyze` + `flutter test`، `tsc` + `lint` + `vitest` + `e2e`، `supabase/tests`).

## Step 1 — التوثيق (النقاط 17، 18، 19، 20)
- أُنشئ `BUSINESS_RULES.md`: كل قاعدة عمل (الحضور، الدقة، البصمة بدون إنترنت، دورة الراتب، أجر اليوم،
  حدود الخصم، السلف، العطل) مع مصدرها بقاعدة البيانات ونسخها بالويب والتطبيق، وقرارات تقنية غير واضحة.
- `README.md`: إزالة "29 ملف SQL" القديم، توضيح أن "v6.0" اسم قديم وليس رقم إصدار، روابط للملفات الجديدة،
  ذكر `supabase/tests` وفحص محاكي الآيفون.
- `DEVELOPER_GUIDE.md`: مسار شاشة السلف `admin_loans/admin_loans_screen.dart` بدل الملف المحذوف.
  (شجرة الملفات الكاملة تُحدَّث بعد خطوات نقل ملفات التطبيق حتى لا تُكتب مرتين. مثال "طلب معدات" مثال افتراضي مقصود.)
- `mobile/lib/core/services/location_service.dart`: تصحيح تعليق مضلل — خدمة الخلفية فعلية لأندرويد فقط؛
  الآيفون يرفض مهمتها والتتبع من `LocationMonitorIOS.swift`.
- `constants.dart` و`web/src/lib/supabase.ts`: تعليق يشرح القيم الاحتياطية المكررة (المفتاح العام) ولماذا تبقى.
- لا تغيير بالسلوك (تعليقات وملفات توثيق فقط).

## Step 2 — الكود الميت (النقطة 16)
- **حُذف** `web/src/components/DashboardErrorBoundary.tsx`: لا يستورده أي ملف؛ `dashboard/layout.tsx` فيه ErrorBoundary خاص به.
- **حُذف** `web/src/lib/compression/image-compression.ts` (والمجلد): لا يستورده أي ملف.
- **توحيد ضغط الصور:** `web/src/features/employees/api.ts` صار يستعمل `imageCompression` من `@/lib/lazy`
  (نفس المكتبة ونفس الخيارات `maxSizeMB: 1, maxWidthOrHeight: 1920, useWebWorker: true`) بدل الاستيراد المباشر —
  المكتبة تُحمَّل عند أول رفع بدل تحميلها مع الصفحة. نفس النتيجة.
- فحص: `tsc` ✓، `lint` ✓، `vitest` 87 ✓، `build` ✓، `e2e` 27 ✓.

## Step 3 — دوال مكررة بالتطبيق (النقطة 6)
- **دالة مشتركة جديدة** `normalizeArabicForSearch` في `mobile/lib/core/utils/arabic_format.dart`
  (نسخة حرفية من `_normalizeArabic` — نفس الاستبدالات ونفس نطاق الحركات `ً-ٟ`).
- **حُذف التكرار** من `directory_screen.dart` و`employee_management_screen.dart`، وصارتا تستدعيان الدالة المشتركة.
- **أُضيف فحص** `mobile/test/unit/arabic_search_test.dart` للدالة المشتركة.
- **لم يُدمج** `_formatBytes` (`storage_stats_screen.dart` و`trash_screen.dart`): النسختان مختلفتان فعلاً
  (التخزين يعرض GB، السلة تعرض MB وتكتب "غير محدد" للقيمة المفقودة) — الدمج يغيّر النص الظاهر.
- فحص: `dart analyze` بدون ملاحظات، `flutter test` 520 ✓ (519 + الجديد).

## Step 4 — ملف أنواع واحد بالويب (النقطة 9)
- **مصدر واحد:** `web/src/lib/db-types.ts` صار المصدر الوحيد لأشكال صفوف قاعدة البيانات.
- **نُقلت حرفياً** إليه الأنواع التي كانت في `lib/types.ts` فقط: `DeductionStatus`, `Attendance`, `RequestStatus`,
  `DeviceRequest`, `MockGpsAttempt`, `GeofenceViolation`, `LeaveTypeOption`, `StorageStat`.
- **الأنواع الـ 15 المكررة بالاسم:** بقيت نسخة `db-types.ts` (يستعملها 29 ملف) — `tsc` أكد أنها تغطي كل استعمالات الملفات السبعة.
- **غُيّر الاستيراد** في: `dashboard/page.tsx`, `layout.tsx`, `geofences`, `leaves`, `loans`, `settings`, `trash`،
  و`lib/attendance.ts`، و`tests/unit/attendance.test.ts`.
- **حُذف** `web/src/lib/types.ts`.
- أنواع فقط (تختفي بعد البناء) — لا تأثير على السلوك.
- متبقٍ: `Attendance` و`AttendanceRecord` نوعان متقاربان لجدول الحضور؛ دمجهما يحتاج تعديل استعمالات صفحة الرئيسية (يُعالج مع تقسيمها).
- فحص: `tsc` ✓، `lint` ✓، `vitest` 87 ✓، `build` ✓، `e2e` 27 ✓.

## Step 5 — تقسيم مكوّنات الواجهة (النقطة 15)
- **حُذف** `web/src/components/ui.tsx` (797 سطر) و**أُنشئ** المجلد `web/src/components/ui/`:
  - `classes.ts` — `cn`, `mergeClasses`, الألوان `Tone`/`TONE_*` (80 سطر)
  - `layout.tsx` — `PageHeader`, `Card`, `CardHeader`
  - `buttons.tsx` — `Button`, `IconButton`
  - `forms.tsx` — `Field`, `Input`, `Select`, `Textarea`, `AmountInput`, `SearchInput`, `FilterSelect`, `Toggle`, `inputCls`
  - `display.tsx` — `Badge`, `Avatar`, `StatTile`, `SegmentedTabs`, `EmptyState`, `InfoNote`
  - `table.tsx` — `DataTable`, `TableEmpty`, `PageSkeleton`
  - `modal.tsx` — `Modal`, `ModalFooter`
  - `index.ts` — يعيد تصدير **نفس الأسماء الـ 33** بالضبط، فكل `import ... from '@/components/ui'` بقي بدون تغيير.
- الكود منقول حرفياً (تحقق آلي: المحتوى مطابق للأصل بعد حذف أسطر الاستيراد). الإضافة الوحيدة: `TONE_DOT` صار `export`
  داخل `classes.ts` لأن `display.tsx` يستعمله (غير مُصدَّر من `index.ts`).
- استُبدلت فواصل الأقسام القديمة بسطر وصف بأعلى كل ملف.
- فحص: `tsc` ✓، `lint` ✓، `vitest` 87 ✓، `build` ✓، `e2e` 27 ✓.

## Step 6 — إطار اللوحة `dashboard/layout.tsx` (النقطة 10)
- `web/src/app/dashboard/layout.tsx`: من 919 إلى 283 سطر — صار تركيب فقط (الشريط، الرأس، منطقة الصفحة، الاختصارات).
- **أُنشئ** المجلد `web/src/features/shell/`:
  - `nav.ts` — `NAV_GROUPS`, `ALL_ITEMS`, و`findActiveItem` (منطق "أطول بادئة" كان داخل useMemo)، و`initialsOf`.
  - `useAdminSession.ts` — التحقق من الجلسة والصلاحية، كاش `batra_cache_admin`، العدّادات، قنوات Realtime الثلاث، النغمة،
    تسجيل الخروج، "تحديد الكل كمقروء" (منقول حرفياً).
  - `components/ErrorBoundary.tsx`, `Sidebar.tsx` (`SidebarNav`, `SidebarBrand`, `SidebarUserCard`), `NotificationsMenu.tsx`,
    `LogoutConfirm.tsx`, `CommandPalette.tsx` — نفس الـ JSX والكلاسات.
- **أُنشئ** `web/src/lib/useClickOutside.ts` (كان دالة داخلية بالإطار).
- **أُضيف فحص** `web/src/features/shell/nav.test.ts` (`findActiveItem`, `initialsOf`).
- ترتيب تسجيل الخروج نفسه: إغلاق النافذة ← مسح الكاش ← signOut ← /login.
- فحص: `tsc` ✓، `lint` ✓، `vitest` 89 ✓، `build` ✓، `e2e` 27 ✓ (تشمل القائمة، الموبايل، صلاحيات مدير الفرع).

## Step 7 — الصفحة الرئيسية `dashboard/page.tsx` (النقطة 11)
- `web/src/app/dashboard/page.tsx`: من 801 إلى 225 سطر (ملخص اليوم، المؤشرات، الإجراءات السريعة — تركيب).
- **أُنشئ** `web/src/features/overview/`:
  - `api.ts` — `fetchDashboard` (نفس الاستعلامات الـ 15 المتوازية والكاش `batra_cache_dashboard`)، `isDashboardData`،
    و`publishAnnouncement` (استدعاء `publish_announcement` كان داخل نافذة التعميم).
  - `logic.ts` — `computeTodayAttendance` (قاعدة الحاضر/الغائب موثقة) و`buildSecurityLogs` و`formatLogTime` — منقولة حرفياً.
  - `components/AnnouncementModal.tsx`, `OverviewWidgets.tsx` (`StatCard`, `AttendanceRing`, `LegendRow`, `DashboardSkeleton`),
    `SecurityCenter.tsx`, `AbsentTodayCard.tsx` (مع بحث الغياب).
- **أُضيف فحص** `web/src/features/overview/logic.test.ts` (الحضور/الغياب، أيام العطل، المجازين، ترتيب الحوادث).
- فحص: `tsc` ✓، `lint` ✓، `vitest` 92 ✓، `build` ✓، `e2e` 27 ✓.

## Step 8 — صفحة الإعدادات `settings/page.tsx` (النقطة 12)
- `web/src/app/dashboard/settings/page.tsx`: من 733 إلى 59 سطر (التبويبات فقط).
- **أُنشئت** في `web/src/features/settings/components/`: `GeneralSettings.tsx`, `SchedulesSection.tsx`, `AnnouncementsSection.tsx`
  (الـ JSX منقول حرفياً بسكربت حسب أرقام الأسطر).
- **الاستعلامات الـ 18 خرجت من الواجهة** إلى `features/settings/api.ts`: `fetchSettings` (نفس القيم الافتراضية)،
  `saveGeneralSettings` (نفس الترتيب: الشركة ← الأرشفة/الإجازات ← `set_payroll_policy`)، `addWorkSchedule`, `deleteWorkSchedule`,
  `deleteAnnouncement`, `deleteAllAnnouncements` (هاتان ترجعان الخطأ بدل رميه حتى يبقى ترتيب إطفاء مؤشر التحميل نفسه).
- `types.ts`: `CompanySettings`, `SettingsData`. `logic.ts`: `DEFAULT_LEAVE_TYPES`, `PROTECTED_LEAVE_TYPES`, `WEEK_ORDER` (مع سبب كل ثابت).
- متبقٍ خارج هذه النقطة: `HolidaysCard.tsx` (كان أصلاً بمجلد الميزة) فيه 5 استعلامات مباشرة.
- فحص: `tsc` ✓، `lint` ✓، `vitest` 92 ✓، `build` ✓، `e2e` 27 ✓ (منها "saves settings").

## Step 9 — صفحة السلف `loans/page.tsx` (النقطة 13)
- `web/src/app/dashboard/loans/page.tsx`: من 698 إلى 80 سطر.
- **أُنشئ** `web/src/features/loans/useLoans.ts`: كل حالة الصفحة وإجراءاتها (منقولة حرفياً) — الاعتماد، الرفض، التعديل،
  الدفعة، التراجع، الحذف، التأجيل.
- **أُنشئت** في `features/loans/components/`: `PendingLoanRequests`, `ApprovedLoansTable`, `ApprovalModal`,
  `InstallmentScheduleModal`, `EditLoanModal`, `PaymentModal` (الـ JSX منقول بسكربت حسب الأسطر).
- **إزالة تكرار:**
  - أنواع `ApprovalDraft`/`EditDraft` المحلية كانت مطابقة لـ `features/loans/types.ts` → تُستعمل الموجودة؛ أُضيف `PayDraft` هناك.
  - `byDueDate` المحلي = `sortInstallments` الموجود؛ وتقسيم الجارية/المكتملة = `splitLoansByCompletion` الموجود.
  - `nextCutoffDay` صار `nextCutoffDate` في `features/loans/logic.ts`.
  - حُذفت تحويلات `as unknown as DbLoan` (بعد الخطوة 4 صار النوعان نفس النوع).
- فحص: `tsc` ✓، `lint` ✓، `vitest` 92 ✓، `build` ✓، `e2e` 27 ✓ (منها اختبارات السلف: الاعتماد، الدفعة، التعديل).

## Step 10 — صفحتا التخزين والفروع (النقطة 14)
**التخزين** — `web/src/app/dashboard/storage/page.tsx`: من 539 إلى 34 سطر.
- **أُنشئ** `web/src/features/storage/`: `api.ts` (`fetchStorageStats`, `emptyTrash`)، `logic.ts` (`TABLE_LABELS`، ألوان الجداول،
  حدود الباقة المجانية `MAX_STORAGE_BYTES`/`MAX_DB_BYTES`، و`formatBytes` الخاص بالصفحة — موثّق اختلافه عن `lib/format`)،
  `useStorageStats.ts` (الحالة والنسب)، و`components/` (`StorageSummary`, `TableSizesCard`, `BucketsCard`, `StorageStatusPanel`).
- **إزالة تكرار:** `getBucketName` المحلي = `bucketFor` في `lib/storage.ts` (نفس الربط ونفس الافتراضي) → تُستعمل الموجودة.
- بقيت نافذة التأكيد الأصلية للمتصفح (`confirm`) لإفراغ السلة كما هي (تغييرها يغيّر ما يراه المستخدم).

**الفروع** — `web/src/app/dashboard/geofences/page.tsx`: من 418 إلى 244 سطر.
- **أُنشئ** `web/src/features/geofences/`: `api.ts` (`fetchGeofences` + الكاش، `deleteBranch`، `saveBranch`)،
  `logic.ts` (`DEFAULT_RADIUS`, `BranchDraft`, `branchCircles`, `attendeesForBranch` — قاعدة "من بصم بالفرع" موثّقة)،
  و`components/BranchFormModal.tsx`.
- **أُضيف فحص** `features/geofences/logic.test.ts`.
- فحص: `tsc` ✓، `lint` ✓، `vitest` 94 ✓، `build` ✓، `e2e` 27 ✓.

## Step 11 — خدمة الموقع `location_service.dart` (النقطتان 1 و 2)
- `mobile/lib/core/services/location_service.dart`: من 1,123 إلى 503 سطر — نقطة الدخول (البدء/الإيقاف، خدمة الخلفية،
  تدفق الموقع، كشف الموقع الوهمي، البطارية). نفس الدوال العامة ونفس `@pragma('vm:entry-point')`.
- **أُنشئ** `mobile/lib/core/services/location/`:
  - `offline_json_queue.dart` — **طابور أوفلاين واحد** بدل 3 نسخ مكررة (النقاط، أحداث الفروع، أحداث السياج) — النقطة 2.
    نفس أسماء الملفات على الجهاز (`offline_locations.json`, `branch_events_offline.json`, `geofence_events_offline.json`)
    فما يضيع شي مخزّن من النسخة السابقة.
  - `geofence_monitor.dart` — السياج الجغرافي + `isPointInPolygon` + طابور أحداثه.
  - `branch_presence_monitor.dart` — دخول/خروج الفروع وإشعاراتها + طابورها.
  - `tracking_schedule.dart` — قرار "نتتبع الآن؟" وحالته المحلية (`tracking_state.json`)، و`isCurrentTimeBetween`
    (أُضيف معامل اختياري `now` للفحص فقط؛ الافتراضي نفس السلوك).
  - `location_uploader.dart` — رفع النقاط والطابور والمزامنة بحزم.
- **ملاحظة سلوك قائم (لم يُغيَّر):** أحداث الفروع/السياج المخزّنة تُرفع فقط إذا كان طابور النقاط غير فارغ؛ صُحّح التعليق المضلل.
- **أُضيف فحص** `mobile/test/unit/location_split_test.dart` (الطابور، المضلع، نافذة الوقت)، واختبار على المحاكي
  يشغّل التتبع ويوقفه (`integration_test/app_launch_test.dart`).
- فحص: `dart analyze` ✓، `flutter test` 523 ✓.

## Step 12 — مجلد شاشات الإدارة (النقطة 7)
- **نُقلت** (بـ `git mv` حتى يبقى تاريخ كل ملف) من `mobile/lib/presentation/employee/` إلى `mobile/lib/presentation/admin/`:
  `admin_dashboard/`, `admin_loans/`, `admin_live_tracking_screen.dart`, `employee_management/`, `employee_management_screen.dart`,
  `branch_management_screen.dart`, `branch_schedule_screen.dart`, `announcement_screen.dart`, `attendance_report_screen.dart`,
  `trash_screen.dart`, `storage_stats_screen.dart` — كلها مسارات `/admin/...` بالراوتر.
- **حُدّثت الاستيرادات فقط حيث تغيّر المسار:** `app_router.dart`, `test/support/screens.dart`, `test/screens/sheets_test.dart`,
  `test/unit/payroll_engine_client_test.dart` (+ ترتيب الاستيرادات أبجدياً).
- `presentation/employee/` صار فيه شاشات الموظف فقط. لا تغيير بالكود نفسه.
- فحص: `dart analyze` ✓، `flutter test` 523 ✓.

## Step 13 — الشاشة الرئيسية للموظف (النقاط 3 و 4 و 8)
- **نُقلت** `presentation/employee/home_screen.dart` → `presentation/employee/home/home_screen.dart` (730 → 361 سطر).
- **أُنشئ** `mobile/lib/data/repositories/home_repository.dart`: كل استعلامات الشاشة الـ 16 (الملف الشخصي، دوام اليوم،
  التعاميم، غير المقروء، العطلة، المجازون/المتأخرون) والاشتراكان الفوريان — نفس الاستعلامات ونفس أسماء القنوات.
- **أُنشئ** `presentation/employee/home/widgets/home_widgets.dart`، و**أُعيدت تسمية** الأجزاء الخاصة لتصير عامة:
  `_Header→HomeHeader`, `_TodayCard→HomeTodayCard`, `_DayState→HomeDayState`, `_TimeChip→HomeTimeChip`,
  `_AdminEntry→HomeAdminEntry`, `_QuickAction(s)→HomeQuickAction(s)`, `_Announcements→HomeAnnouncements` (+ `super.key`).
- `main_layout.dart`: مسار الاستيراد فقط.
- فحص: `dart analyze` ✓، `flutter test` 523 ✓.

## Step 14 — شاشة البصمة (النقاط 3 و 4 و 8)
- **نُقلت** `presentation/employee/attendance_screen.dart` → `presentation/employee/attendance/attendance_screen.dart` (773 → 670 سطر)،
  و`attendance_history_card.dart` → `presentation/employee/attendance/widgets/attendance_history_card.dart`.
- **أُنشئ** `mobile/lib/data/repositories/attendance_repository.dart`: فرع الموظف + دوام اليوم + سجل آخر الأيام — نفس الاستعلامات حرفياً.
  البصمة نفسها ما تغيّرت (تبقى عبر `AttendanceSyncService`).
- **أُنشئ** `attendance/widgets/attendance_widgets.dart`: `AttendanceBranchMap` (من `_buildMap`)، `AttendanceLocationCard`
  (من `_buildLocationCard`)، `AttendanceTodayCard` (من `_buildTodayCard`) — نفس العناصر ونفس النصوص. اللوحة ومنطق البصمة بقيت بالشاشة.
- `main_layout.dart`: مسار الاستيراد فقط.
- **أُضيف فحص** `mobile/test/unit/attendance_widgets_test.dart` (حالات كارت الموقع وكارت اليوم).
- فحص: `dart analyze` ✓، `flutter test` 528 ✓.

## Step 15 — شاشة الإجازات (النقاط 3 و 4 و 8)
- **نُقلت** `presentation/employee/leave_request_screen.dart` → `presentation/employee/leave/leave_request_screen.dart` (737 → 547 سطر).
- **أُنشئ** `mobile/lib/data/repositories/leave_repository.dart`: الرصيد (`get_leave_balance`)، سجل طلباتي، سياسة الأنواع،
  رفع المرفق (نفس المسار `leaves/<id>/<uuid>.<ext>` ونفس الـ bucket)، تقديم الطلب، إلغاء طلب قيد المراجعة — نفس الاستعلامات.
- **أُنشئ** `leave/leave_logic.dart` (منطق بدون واجهة): `bareLeaveTypeName`, `formatLeaveMinutes`, `parseActiveLeaveTypes`,
  `leaveTypeLabel`, `leaveHourString`, `validateLeaveDates` — نفس الرسائل ونفس الشروط.
- **أُنشئ** `leave/widgets/leave_widgets.dart`: `LeaveBalanceCard` (من `_buildBalanceCard`) و`LeaveCard` (كان `_LeaveCard`).
- `main_layout.dart`: مسار الاستيراد فقط.
- **أُضيف فحص** `mobile/test/unit/leave_logic_test.dart` (التحقق من التواريخ والتداخل، قراءة السياسة، الأسماء، كارت الرصيد).
- فحص: `dart analyze` ✓، `flutter test` 538 ✓.

## Step 16 — شاشة طلب السلفة (النقاط 3 و 4 و 8)
- **نُقلت** `presentation/employee/loan_request_screen.dart` → `presentation/employee/loan/loan_request_screen.dart` (549 → 369 سطر).
- **وُسّع** `LoanRepository` (بدل ملف جديد): `fetchMyLoans`, `fetchMySalary`, `submitLoanRequest`, `cancelMyLoanRequest` —
  ورفع التعهد يستعمل `uploadPledge` الموجود (نفس الـ bucket `loan-pledges` ونفس المسار `pledges/<id>/<uuid>.<ext>`).
- **أُنشئ** `loan/loan_request_logic.dart`: `loanMonths`, `loanLastInstallment`, `loanRequestError`, `loanSalaryWarning`
  — نفس الشروط ونفس الرسائل (تنبيه نص الراتب/الراتب بالسالب يبقى تنبيه فقط).
- **أُنشئ** `loan/widgets/loan_widgets.dart`: `LoanPledgeCard` (من `_buildPledgeCard`) و`MyLoanCard` (كان `_LoanCard`).
- `main_layout.dart`: مسار الاستيراد فقط.
- **أُضيف فحص** `mobile/test/unit/loan_request_logic_test.dart`.
- فحص: `dart analyze` ✓، `flutter test` 545 ✓.

## Step 17 — شاشة كشوف الرواتب (النقاط 3 و 4 و 8)
- **نُقلت** `presentation/employee/payslips_screen.dart` → `presentation/employee/payslips/payslips_screen.dart` (554 → 314 سطر).
- **أُنشئ** `mobile/lib/data/repositories/payslips_repository.dart`: سياسة الدورة، الكشوف المعتمدة + الملف الشخصي (بالتوازي كما كان)،
  مسير الشهر الحالي (`get_my_payroll_preview`)، أسطر كشف المحرّك، والمكافآت والخصومات للكشوف القديمة — نفس الاستعلامات.
- **أُنشئ** `payslips/payslips_logic.dart`: `payslipCycleDates` (كان `_getCycleDates`)، `payslipMonthOf`، `itemsIncludedInSlip`
  (فلترة البنود التي دخلت بالكشف)، و`slipLinesToDetails` (انتقلت كما هي).
- **أُنشئ** `payslips/widgets/payslip_widgets.dart`: `CurrentPayrollCard` (انتقل كما هو) و`SlipDetailsView` (كان `_SlipDetails`).
- حُدّثت استيرادات: `app_router.dart`, `test/support/screens.dart`, `payroll_engine_client_test.dart`, `user_flow_ui_test.dart`.
- **أُضيف فحص** `mobile/test/unit/payslips_logic_test.dart` (الدورة المالية عبر السنة وفبراير، فلترة البنود).
- فحص: `dart analyze` ✓، `flutter test` 552 ✓.

## Step 18 — شاشة الإعدادات (النقاط 3 و 4 و 8)
- **نُقلت** `presentation/employee/settings_screen.dart` → `presentation/employee/settings/settings_screen.dart` (592 → 441 سطر).
- **أُنشئ** `mobile/lib/data/repositories/profile_repository.dart`: الملف الشخصي (`v_employee_directory`)، رفع/تحديث/حذف الصورة
  الشخصية (نفس الـ bucket ونفس المسار)، رفع المستمسك وتحديث `document_urls`، مجموع السلف المعتمدة المتبقية، و`request_account_deletion`.
  ترتيب الخطوات نفسه (رفع ← تحديث الرابط ← حذف القديمة).
- **أُنشئ** `settings/settings_logic.dart`: `avatarStoragePath` (استخراج مسار الصورة القديمة — كان داخل `_updateAvatar`).
- **أُنشئ** `settings/widgets/settings_widgets.dart`: `SettingsProfileCard`, `SettingsNotificationsCard`, `SettingsDocumentsCard`
  (من `_buildProfileCard` / `_buildNotificationsCard` / `_buildDocuments`). قائمة الخدمات وكارت الجهاز بقيت بالشاشة.
- `main_layout.dart`: مسار الاستيراد فقط.
- **أُضيف فحص** `mobile/test/unit/settings_logic_test.dart`.
- فحص: `dart analyze` ✓، `flutter test` 555 ✓.

## Step 19 — الإشعارات، دليل الموظفين، لوحة التعاميم (النقاط 3 و 4 و 8)
- **نُقلت** `notifications_screen.dart` → `employee/notifications/`، و`directory_screen.dart` → `employee/directory/`
  (+ `app_router.dart` و`test/support/screens.dart` مسارات فقط).
- **أُنشئ** `NotificationRepository` (`fetchMine`, `markRead`) و`DirectoryRepository` (`fetchDirectory` = `get_employee_directory`).
- **أُنشئ** `directory/directory_logic.dart`: `directoryBranchOptions` و`filterDirectory` (نفس البحث العربي وفلتر الفرع حرفياً)؛
  وحُذف تعليق يتيم بقي من الخطوة 3.
- **أُنشئ** `AnnouncementRepository`: `fetchActive`, `fetchOnLeaveAndLateToday`, `fetchBoard` (الثلاثة بالتوازي كما كان).
  `HomeRepository` صار يستدعيه بدل نسخة مكررة من نفس الاستعلامات (نفس الدوال ونفس `catchError` لدالة المتأخرين).
- **أُضيف فحص** `mobile/test/unit/directory_logic_test.dart`.
- فحص: `dart analyze` ✓، `flutter test` 559 ✓.

## Step 20 — تقرير الحضور للإدارة (النقاط 3 و 4 و 8)
- **نُقلت** `presentation/admin/attendance_report_screen.dart` → `presentation/admin/attendance_report/attendance_report_screen.dart` (664 → 516 سطر).
- **أُنشئ** `mobile/lib/data/repositories/attendance_report_repository.dart`: القوائم الأربع بالتوازي، الحضور بصفحات 1000،
  الإجازات المعتمدة المتقاطعة مع الفترة، العطل الرسمية، وتعديل أوقات سجل — نفس الاستعلامات حرفياً.
- فحص صلاحية الشاشة صار عبر `RoleRepository.isAdminOrManager()` الموجود (نفس الاستعلام ونفس الشرط: أدمن أو مدير وإلا ترجع).
- **أُنشئ** `attendance_report/widgets/report_record_card.dart`: `ReportRecordCard` (من `_recordCard`) و`ReportTimeButton` (كان `_TimeButton`).
- فحص: `dart analyze` ✓، `flutter test` 559 ✓ (لقطات الشاشة تغطي التقرير).

## Step 21 — التتبع الحي للإدارة (النقاط 3 و 4 و 8)
- **نُقلت** `presentation/admin/admin_live_tracking_screen.dart` → `presentation/admin/live_tracking/admin_live_tracking_screen.dart` (686 → 417 سطر).
- **أُنشئ** `mobile/lib/data/repositories/live_tracking_repository.dart`: الفروع، الموظفون النشطون، بصمات ونقاط اليوم (صفحات 1000)،
  والاشتراك الفوري (`live-admin-tracking` على `location_tracking` و`attendance`) + `removeChannel` — نفس اسم القناة ونفس الجداول.
- فحص الصلاحية عبر `RoleRepository.isAdminOrManager()` (نفس الشرط، ونفس الرسالة والتحويل للرئيسية).
- **أُنشئ** `live_tracking/widgets/live_tracking_widgets.dart`: `trackStatusStyle` (كان `statusStyle` داخل الـ State)،
  `TrackingStatusCounter`, `LiveTrackingMap`, `TrackingFocusCard`, `TrackingFact` (كانت خاصة بالملف).
- ترتيب الاستيرادات أبجدياً في `app_router.dart` و`test/support/screens.dart` بعد تغيّر المسار.
- فحص: `dart analyze` ✓، `flutter test` 559 ✓.

## Step 22 — إدارة الأفرع وأوقات دوامها (النقاط 3 و 4 و 8)
- **نُقلت** `branch_management_screen.dart` و`branch_schedule_screen.dart` → `presentation/admin/branches/`
  (+ `app_router.dart`، `test/support/screens.dart`، `test/screens/sheets_test.dart` مسارات فقط).
- **أُنشئ** `mobile/lib/data/repositories/branch_repository.dart`: قائمة الأفرع، إضافة/تعديل/حذف فرع، الأفرع مع جداول دوامها
  (بالتوازي)، وحفظ جدول فرع (إضافة أو تعديل) — نفس الاستعلامات. محاولة الحفظ الثانية بدون عمود التذكير (قاعدة قديمة) باقية كما هي.
- فحص صلاحية شاشة أوقات الدوام عبر `RoleRepository.isAdminOrManager()` (نفس الشرط).
- **أُنشئ** `branches/branches_logic.dart`: `mergeBranchSchedules` (دمج الفرع مع جدوله — كان داخل `_loadBranches`).
- **أُضيف فحص** `mobile/test/unit/branches_logic_test.dart`.
- فحص: `dart analyze` ✓، `flutter test` 561 ✓.

## Step 23 — إدارة الموظفين (النقاط 3 و 4 و 8)
- **نُقلت** `presentation/admin/employee_management_screen.dart` → `presentation/admin/employee_management/employee_management_screen.dart`
  (صار بنفس مجلد أجزائه: الوثائق، نموذج الإضافة، ملف الموظف) + مسارات `app_router.dart` والاختبارات.
- **أُنشئ** `mobile/lib/data/repositories/employee_admin_repository.dart`: الموظفون مع الأجهزة والأفرع (بالتوازي)، التفعيل/التعطيل
  مع آخر يوم عمل، فك ربط الجهاز (نفس الخطوتين بنفس الترتيب)، `create_employee_secure`، ورفع/حذف وثائق الموظف وتحديث روابطها.
- `uploadEmployeeDocuments` باقية بنفس الاسم وصارت تستدعي المستودع (نفس الضغط، نفس اسم الملف، نفس تخطي الملف الفاشل).
- صلاحية الشاشة عبر `RoleRepository.currentRole()` (نفس الشرط، و`_isAdmin` من نفس القيمة).
- فحص: `dart analyze` ✓، `flutter test` 561 ✓.

## Step 24 — سلة المحذوفات، إحصائيات التخزين، نشر التعاميم (النقاط 3 و 4 و 8)
- **نُقلت** `trash_screen.dart` و`storage_stats_screen.dart` → `presentation/admin/storage/`، و`announcement_screen.dart` →
  `presentation/admin/announcements/` (+ مسارات `app_router.dart` و`test/support/screens.dart`، مع ترتيب الاستيرادات).
- **أُنشئ** `mobile/lib/data/repositories/storage_repository.dart`: عرض السلة، الاستعادة، الحذف النهائي (التخزين أولاً ثم السجل —
  نفس الترتيب)، أحجام السلة، و`get_storage_stats`.
- **أُنشئ** `storage/storage_logic.dart`: `bucketForFileType` (كان `_getBucketName`)، `sumTrashBytes`، `storageBucketTotals`
  (نفس التوزيع: `documents` القديم يُحسب مع الوثائق).
- **وُسّع** `AnnouncementRepository`: `fetchTargets` (الأفرع + الموظفون النشطون) و`publish` (`publish_announcement`).
- **أُضيف فحص** `mobile/test/unit/storage_logic_test.dart`.
- بهذا **ما بقى أي استدعاء مباشر لـ Supabase داخل `presentation/`** — كلها بالـ repositories (الخدمات بـ `core/services` بقت كما هي).
- فحص: `dart analyze` ✓، `flutter test` 565 ✓.

## Step 25 — سجلات التطبيق الموحّدة (النقطة 21)
- **أُنشئ** `mobile/lib/core/utils/app_log.dart`: `appLog(message)` = `debugPrint(message)` حرفياً (نفس الإخراج ونفس التقطيع).
- **استُبدلت** كل استدعاءات `debugPrint(` بـ `appLog(` (166 استدعاء في 41 ملف) — **نفس نص كل رسالة بدون تغيير**؛
  وحُذف استيراد `flutter/foundation` (أو `material`) من 12 ملف كان يستعمله فقط لـ `debugPrint`.
- الفائدة: مكان واحد لو احتجنا لاحقاً أداة سجلات أو إرسال الأخطاء لخدمة خارجية. السلوك الحالي نفسه بالضبط.
- لم يُوحَّد شكل الرسائل (إيموجي/عربي/إنگليزي) حتى لا يتغير أي إخراج — قرار مقصود.
- فحص: `dart analyze` ✓، `flutter test` 565 ✓.

## Step 26 — التوثيق النهائي
- `DEVELOPER_GUIDE.md`: **أُعيدت كتابة شجرة الملفات** حسب الواقع (core/logic، core/services/location، data/repositories،
  مجلد لكل شاشة تحت presentation/employee و presentation/admin، الويب features/، supabase/) — كانت تذكر ملفات محذوفة من زمان
  (glass_container، date_utils…). وخطوة "إضافة ميزة جديدة" صارت تبدأ بالمستودع ثم الشاشة ثم المنطق مع اختبار.
- `BUSINESS_RULES.md`: قرار أن الشاشات لا تكلّم Supabase مباشرة، وقرار **تأجيل النقطة 5** (تحويل `Map` إلى النماذج) مع السبب:
  القيم الافتراضية بالنماذج تختلف عن المعروض، فالتحويل يغيّر العرض ويخالف قاعدة "نفس السلوك".
- `CHANGES.md`: تصحيح كتابة `@pragma('vm:entry-point')` بالخطوة 11.
- لا تغيير بالكود.

## Step 27 — الويب: آخر الاستدعاءات المباشرة (إكمال النقاط 3 و 4)
- **أُنشئ** `web/src/features/leaves/{api.ts, logic.ts}`: `fetchLeaves`, `fetchLeaveCounts`, `decideLeave` (نفس التحديث ونفس
  شرط الجلسة)، و`LEAVE_TYPES`, `leaveDays`, `filterLeavesByName`. صفحة الإجازات صارت تركيب فقط.
- **وُسّع** `features/storage/api.ts`: `fetchDeletedFiles`, `restoreDeletedFile`, `destroyDeletedFile` (التخزين أولاً ثم السجل) لصفحة السلة.
- **وُسّع** `features/settings/api.ts`: `fetchRecentHolidays`, `addHoliday`, `deleteHoliday` — ترجع الخطأ بدل رميه حتى
  تبقى رسائل `HolidaysCard` نفسها (ومنها رسالة 23505 "مسجّل مسبقاً").
- **أُنشئ** `features/auth/api.ts`: `hasDashboardSession` (فحص الجلسة + الدور) و`signInToDashboard` (نفس الخطوات ونفس الرسائل
  ونفس تسجيل الخروج للحساب غير المخوّل) — تستعملهم صفحة الدخول والصفحة الرئيسية.
- بهذا **ما بقى أي استيراد لـ `@/lib/supabase` داخل `web/src/app` أو `web/src/components`.**
- **أُضيف فحص** `features/leaves/logic.test.ts` و`features/auth/api.test.ts`.
- فحص: `tsc` ✓، `lint` ✓، `vitest` 100 ✓، `build` ✓، Playwright 27 ✓.

## Step 28 — شاشة البصمة: فصل المنطق والعرض (إكمال النقطة 4)
- **أُنشئ** `attendance/attendance_logic.dart` (بدون واجهة): `scheduleMinutesOf`, `punchNote` (التأخير بعد السماحية / الخروج المبكر)،
  `mergeTodayOfflinePunches` (دمج بصمات اليوم المحفوظة بالجهاز فوق سجل السيرفر)، `nextPunchType`، و`localPunchError`
  (دقة GPS ← النطاق ← البصمة المكررة، بنفس الترتيب ونفس الرسائل). نفس ترتيب العمليات (قراءة الطابور قبل قراءة سجل اليوم).
- تكرار تعبئة موقع الفرع (من الكاش ومن السيرفر) صار دالة واحدة `_applyBranch` بنفس ترتيب الحقول.
- **أُضيفت** للـ widgets: `AttendanceErrorCard`, `AttendancePunchControls`, `AttendancePrivacyNote`, `PunchSuccessDialog` — نفس العناصر والنصوص.
- **منطق البصمة نفسه لم يتغير**: الإرسال عبر `AttendanceSyncService.punch`، تشغيل/إيقاف التتبع، ورسائل السيرفر كما هي.
- الشاشة 671 → 538 سطر. **أُضيف فحص** `mobile/test/unit/attendance_logic_test.dart` (13 حالة).
- فحص: `dart analyze` ✓، `flutter test` 578 ✓.

## Step 29 — شبكة أمان للعرض: لقطات نصية لكل الشاشات (تمهيد للنقطة 5)
- **أُضيف** `mobile/test/screens/text_snapshot_test.dart`: يشغّل الـ 22 شاشة على الخادم الوهمي ويحفظ **كل نص ظاهر بالترتيب**
  في `mobile/test/goldens/text/<شاشة>.txt` (835 سطر). أي اختلاف بعدها — حتى حرف — يُفشل الاختبار.
- الأرقام تُستبدل بـ `#` (الأوقات النسبية والتواريخ تتغير مع الساعة) ومعرّف الجهاز العشوائي بـ `device_<id>`؛ ثابت عبر 3 تشغيلات.
- جُرّب: تغيير حرف واحد بملف اللقطة → الاختبار فشل كما يجب.
- اللقطات أُخذت **قبل** أي تحويل للنماذج، فهي المرجع: كل تحويل بالنقطة 5 لازم يمر عليها بدون تحديث.
- لا تغيير بالكود.

## Step 30 — النقطة 5 (1): الإشعارات والإجازات بالنماذج
- **لقطات إضافية بالتفاعل** (سُجّلت من الكود **قبل** التحويل ثم قورنت بعده): تبويب "طلباتي" بالإجازات، "سلفي وأقساطي"،
  نافذة تفاصيل كشف الراتب، وبطاقة موظف بالدليل (`05b/06b/10b/11c` في `test/goldens/text/`).
- **الإشعارات:** `NotificationRepository.fetchMine` ترجع `List<NotificationModel>`؛ الشاشة تستعمل الحقول بدل `n['...']`.
  العنوان الافتراضي بالنموذج صار «تنبيه» (نفس اللي تعرضه الشاشة؛ النموذج ما كان مستعمل بأي مكان ثاني).
- **الإجازات:** `LeaveRepository.fetchMyRequests` ترجع `List<LeaveRequestModel>` (النموذج الموجود والمستعمل بلوحة الإدارة)؛
  `LeaveCard` و`validateLeaveDates` والشاشة تستعمل الحقول. `start_date`/`end_date` إلزاميان بالقاعدة (NOT NULL) فشرط "تخطّي
  الطلب بلا تاريخ" ما يتحقق أبداً؛ و`Fmt.date` يحوّل للتوقيت المحلي بنفسه فالعرض واحد.
- النتيجة: **كل اللقطات النصية (26) مطابقة حرفياً** للكود القديم.
- فحص: `dart analyze` ✓، `flutter test` 604 ✓.

## Step 31 — النقطة 5 (2): سلف الموظف بالنموذج
- **أُضيف أولاً** `mobile/test/unit/my_loan_card_test.dart` + `test/goldens/text/card_my_loan_{approved,pending,rejected}.txt`:
  نصوص كارت السلفة كاملة (مع جدول الأقساط مفتوح) **مسجّلة من الكود القديم**.
- `LoanRepository.fetchMyLoans` ترجع `List<LoanModel>` (النموذج الموجود والمستعمل بالإدارة)؛ `MyLoanCard`، `loanRequestError`
  (`l.isActive` = معتمدة ومتبقي > 0، نفس الشرط) والشاشة تستعمل الحقول. ترتيب الأقساط صار من النموذج (بتاريخ الاستحقاق؛
  نفس نتيجة مقارنة نص "YYYY-MM-DD"). كل الأعمدة المعروضة `NOT NULL` بالقاعدة، والمبالغ تُقرّب بـ `formatThousands`.
- النتيجة: كارت السلفة واللقطات النصية **مطابقة حرفياً**.
- فحص: `dart analyze` ✓، الاختبارات ✓.

## Step 32 — النقطة 5 (3): كشوف الرواتب بالنماذج
- **أُنشئ** `mobile/lib/core/models/salary_slip_model.dart`: `SalarySlipModel` (الكشف)، `PayslipDetail` (بند مكافأة/خصم + `toMap()`
  للـ PDF بنفس المفاتيح)، `PayrollPreview` و`PayrollPreviewEvent` (مسير الشهر الحالي).
- `PayslipsRepository`: `fetchSlipsAndProfile` ترجع `PayslipsData` (الكشوف + `PayslipOwner` لاسم الموظف وفرعه بنفس القاعدة:
  الفرع '' إذا ماكو)، و`fetchPayrollPreview` ترجع `PayrollPreview?` (null إذا الدالة ما رجعت كائن — نفس الشرط).
- `slipLinesToDetails` و`itemsIncludedInSlip` ترجع `PayslipDetail`؛ الشاشة و`CurrentPayrollCard` و`SlipDetailsView` تستعمل الحقول.
  الـ `work_month` الناقص يبقى بنفس البديل لكل مكان ('' بالقائمة، '0000-00' بالتفاصيل والـ PDF).
- النتيجة: لقطات `10_payslips` و`10b_payslip_sheet` **مطابقة حرفياً**، واختبار الـ PDF يمر.
- فحص: `dart analyze` ✓، `flutter test` 607 ✓.

## Step 33 — النقطة 5 (4): التعاميم والمجازون والمتأخرون بالنماذج
- **أُنشئ** `mobile/lib/core/models/announcement_model.dart`: `AnnouncementModel`، `OnLeavePerson`، `LatePerson` (+ `PersonCardData`
  للصورة والاسم والفرع)، و`rowsStrict` — تحويل صارم يرمي مثل `List<Map>.from(x as List)` القديم حتى تبقى حالة الخطأ نفسها.
- القيم الافتراضية نفسها: «إعلان إداري»، «موظف»، «—» للفرع؛ بداية العرض = `starts_at` وإلا `created_at`؛ و`to_date` (عمود DATE)
  يُقرأ بدون تحويل منطقة زمنية كما كان.
- `announcement_widgets.dart` (الكروت والشرائح والأسطر)، لوحة التعاميم، والرئيسية تستعمل الحقول بدل `p['...']`.
- النتيجة: لقطات `03_home` و`11b_announcements_board` **مطابقة حرفياً**.
- **أُضيف فحص** `mobile/test/unit/announcement_models_test.dart` (7 حالات).
- فحص: `dart analyze` ✓، `flutter test` ✓.

## Step 34 — النقطة 5 (5): دليل الموظفين بالنموذج
- **أُنشئ** `mobile/lib/core/models/directory_entry.dart`: `DirectoryEntry` بحقول nullable كما تصل من `get_employee_directory`،
  حتى تبقى بدائل العرض المختلفة بكل مكان كما هي ('—'، 'القسم العام'، 'الفرع العام'، 'غير مسجل'، 'موظف').
- `DirectoryRepository.fetchDirectory`، `filterDirectory`، `directoryBranchOptions`، والشاشة (القائمة وبطاقة الموظف) تستعمل الحقول.
- ترتيب `models.dart` أبجدياً.
- النتيجة: لقطات `11_directory` و`11c_directory_profile` **مطابقة حرفياً**؛ اختبارات البحث العربي تمر.

## Step 35 — النقطة 5 (6): سلة المحذوفات بالنموذج
- **أُنشئ** `mobile/lib/core/models/deleted_file_model.dart`: `DeletedFileModel` (اسم من حذف أو «غير معروف»، موعد الحذف النهائي
  بالتوقيت المحلي، الحجم `num?` حتى يبقى «غير محدد» إذا ماكو حجم) + `fileName`.
- `StorageRepository.fetchTrash` ترجعه، وشاشة السلة (الكارت والاستعادة والحذف النهائي) تستعمل الحقول.
- النتيجة: لقطة `20_trash` **مطابقة حرفياً**.

## Step 36 — النقطة 5 (7): الأفرع وأوقات دوامها بالنماذج + تثبيت اللقطات مع الساعة
- `BranchModel`: الموقع ونصف القطر صاروا nullable (`latitude`/`longitude` فقط إذا رقم — نفس شرط `_pointOf` القديم)، والاسم الخام
  `rawName` مع `name` = «فرع» للقوائم (نفس القيمة اللي تستعملها لوحة الإدارة والسلف). حُذف `toInsert()` (غير مستعمل).
  كل شاشة تعرض بديلها كما كان: «بدون اسم» / «الفرع»، نطاق 50 م بالكارت و100 م بنافذة التعديل.
- **أُنشئ** `branch_schedule_model.dart`: `BranchSchedule` (حقول nullable: الأيام، الأوقات، السماحية، التذكير) و`BranchWithSchedule`؛
  `mergeBranchSchedules` يرجعهم، وشاشة أوقات الدوام ونافذتها تستعمل الحقول بنفس البدائل (15 د، 5 د، 8:00–16:00، كل الأيام عدا الجمعة).
- `BranchRepository.fetchAll` ترجع `List<BranchModel>`.
- **إصلاح باختبار اللقطات:** "مدة العمل حتى الآن" تغيّرت من 9 ساعات لـ 10 (رقم صار رقمين) فاختلفت اللقطة بدون أي تغيير بالكود؛
  صار كل رقم **مهما طال** = `#`، وطُبّق نفس التحويل على ملفات اللقطات (بدون إعادة تسجيل) فبقت مرجعها الكود القديم.
- النتيجة: لقطات `16_branches` و`17_branch_schedule` وكل الباقي **مطابقة**؛ `flutter test` 615 ✓.

## Step 37 — النقطة 5 (8): قوائم الاختيار بنشر التعميم وتقرير الحضور
- **أُنشئ** `mobile/lib/core/models/employee_ref.dart`: `EmployeeRef` (id + الاسم والرقم الوظيفي والفرع والقسم وتاريخ المباشرة
  والحالة — كلها nullable كما تصل).
- `AnnouncementRepository.fetchTargets` ترجع `(branches: List<BranchModel>, employees: List<EmployeeRef>)`؛ شاشة نشر التعميم
  ونافذة اختيار الموظفين تستعمل الحقول (النص `'${...}'` نفس `.toString()` القديم حتى للقيمة الفارغة).
- تقرير الحضور: قوائم الأفرع والموظفين صارت `BranchModel`/`EmployeeRef` (فلتر "نشط" نفسه: `!= false`).
- النتيجة: لقطات `18_announcements` و`19_attendance_report` **مطابقة**؛ `flutter test` 615 ✓.

## Step 38 — النقطة 5 (9): إدارة الموظفين بالنموذج
- **لقطات جديدة سُجّلت من الكود القديم أولاً:** نافذة ملف الموظف (`15b_employee_profile`) ونافذة إضافة موظف (`15c_add_employee`).
- **أُنشئ** `mobile/lib/core/models/managed_employee.dart`: `ManagedEmployee` (الهاتف = phone_number وإلا phone، الفرع والقسم من
  الـ join فقط إذا كائن، "نشط" = كل شي غير false، عدد الأجهزة وطراز أولها، الراتب `num?`).
- `EmployeeAdminRepository.fetchEmployeesAndBranches` ترجع `(employees, branches)` مُنمّطة؛ الشاشة، البحث، نافذة الملف، نافذة
  الوثائق، ونموذج الإضافة (قائمة الأفرع `BranchModel`) تستعمل الحقول بنفس البدائل.
- النتيجة: لقطات `15_employee_management` و`15b` و`15c` **مطابقة حرفياً**؛ `flutter test` 617 ✓.

## Step 39 — النقطة 5 (10): أفرع التتبع الحي بالنموذج
- `LiveTrackingRepository.fetchBranches` ترجع `List<BranchModel>`؛ توسيط الخريطة، دوائر النطاق (نفس شرط "الموقع رقم")،
  ونافذة اختيار الفرع تستعمل الحقول (نطاق 100 م إذا ماكو).
- الموظفون والبصمات والنقاط تبقى صفوفاً تمر لـ `buildTracking` (core/logic) — هي **مُحلّل** يحوّلها لـ `TrackedEmployee`
  وله اختباراته (`tracking_rules_test`)، فهذا هو مكان التحويل الصحيح.
- النتيجة: لقطة `14_admin_tracking` **مطابقة**.

## Step 40 — النقطة 5 (11): رصيد الإجازات وسجل الدوام بالنماذج
- **أُنشئ** `mobile/lib/core/models/leave_balance_model.dart`: `LeaveBalance` (السنوية/المرضية/الزمنيات). التحويل صارم ويصير
  وقت التحميل: إذا رجع رصيد ناقص يُسجَّل الخطأ ويختفي الكارت (كان ممكن يطلع خطأ رسم) — حالة بيانات خربانة فقط.
- `AttendanceModel` (كان غير مستعمل): الحالة صارت nullable حتى يبقى «—» للسجل بلا حالة؛ `AttendanceRepository.fetchRecentHistory`
  ترجعه وكارت "سجل الدوام" يستعمل الحقول.
- **تبقى `Map` عن قصد:** سجل اليوم وجدول الدوام بشاشة البصمة والرئيسية — هم نفس JSON الكاش بالجهاز (`AttendanceSyncService`)
  ودمج البصمات المحفوظة بدون إنترنت؛ تحويلهم يمس مسار البصمة نفسه، والوعد كان ما نغيّر البصمة.
- النتيجة: لقطات `04_attendance` و`05_leave` **مطابقة**؛ `flutter test` 617 ✓.

## Step 41 — تصغير آخر الملفات الكبيرة (النقطة 4)
- **Excel:** `core/services/excel_export_service.dart` (581 → 79 سطر) صار واجهة رفيعة بنفس الدوال العامة؛ كشف السلفة انتقل حرفياً إلى
  `core/services/excel/loan_statement_excel.dart`، وتقرير الحضور إلى `core/services/excel/attendance_report_excel.dart`
  (اختبار ملف تقرير الحضور يمر).
- **الإجازات:** تبويب "طلباتي" صار `LeaveHistoryList` ومرفق الطلب `LeaveAttachmentCard` (الشاشة 552 → 488).
- **تقرير الحضور:** تحويل الصفوف (البصمات، الإجازات المعتمدة، العطل، القوائم وأسماء أنواع الإجازات) صار داخل
  `AttendanceReportRepository` ويرجع أنواعاً جاهزة (`ReportAttendance`, `ReportLeave`, `ReportLookups`)؛ ونافذة تعديل الأوقات صارت
  `widgets/edit_times_sheet.dart` تأخذ `ReportTimeEdit` (record مُنمّط بدل Map). الشاشة 517 → 429.
- **أُضيف فحص** `mobile/test/unit/edit_times_sheet_test.dart`.
- النتيجة: كل اللقطات **مطابقة**؛ `flutter test` 618 ✓.

## Step 42 — آخر تصغير: التعاميم وشاشة البصمة
- `announcement_widgets.dart` (470 → 201): المجازون والمتأخرون انتقلوا حرفياً إلى `announcements/people_widgets.dart`
  (يُصدَّر من الملف القديم، فالاستيرادات بقت نفسها).
- شاشة البصمة (538 → 493): حساب المسافة عن الفرع كان مكرر 6 مرات بنفس المعادلة → `_distanceFromBranch(position)`
  (يقرا موقع الفرع وقت الاستدعاء نفسه)؛ و`AttendancePanelSkeleton` و`AttendanceDayCompleteCard` صاروا widgets.
- **ما بقى أي ملف بالتطبيق فوق 503 سطر** (أكبرها `location_service.dart` = نقطة دخول خدمة التتبع الخلفية).
- النتيجة: كل اللقطات **مطابقة**؛ `flutter test` 618 ✓.

## Step 43 — مراجعة جودة الكود (القسم 19): الإصلاحات الآمنة — الكود
- **19.3 حذف كود ميت يحمل قواعد تختلف عن السيرفر (الويب):** `minutesLate`/`minutesEarly` (تأخير بدون سماحية وبداية 09:00)،
  `getCycleDates` (دورة 25←24 قديمة)، `getBaghdadMinutesFromIso`، `parseScheduleMinutes`، `toDateStr`، النسخة المكررة من
  `formatLateDurationArabic` في `lib/attendance.ts`، و`splitAmount`/`buildInstallmentSchedule`/`firstOfNextMonth`/
  `nextUnpaidInstallment`/`loanToEditDraft` + نوع `ScheduledInstallment`. ما حد كان يستدعيها إلا اختباراتها (حُذفت معها:
  `tests/unit/payroll.test.ts` وأجزاء من `attendance.test.ts` و`loans/logic.test.ts`). الويب: 100 → 91 اختبار.
- **19.7 نسبة "نص الراتب" بتنبيه السلفة صارت ثابتاً مسمّى:** `LOAN_SALARY_WARNING_RATIO` (الويب) و`kLoanSalaryWarningRatio`
  (التطبيق، `core/logic/loan_rules.dart`) مع سبب القاعدة؛ بدل 0.5 و`/ 2` المكتوبة 5 مرات. نفس القيم بالضبط.
- **19.12 أخطاء كانت تُبلع بصمت صار لها سجل (15 مكان):** حفظ رمز الإشعارات (FCM)، إيقاف التتبع ومراقبة iOS عند الانصراف
  والخروج، طلب صلاحية الموقع بالخلفية، التحديث الصامت للتتبع الحي، نسخ PDF/Excel للتنزيلات، قراءة حجم الملف. نفس التصرف،
  فقط سطر `appLog`. الأماكن غير المؤثرة (إلغاء اشتراك، تحريك خريطة، رقم النسخة) بقت كما هي.
- **19.13 الأدوار بمكان واحد:** `mobile/lib/core/models/roles.dart` (`Roles.admin/manager/employee`, `isAdmin`, `canManage`)
  بدل 14 مقارنة نصية بالتطبيق؛ وبالويب `isDashboardRole` صارت بـ `lib/role.tsx` وتستعملها صفحة الدخول وجلسة اللوحة.
- **اختبار اللقطات:** الوقت النسبي ("قبل 3 ساعات" ← "قبل 11 ساعة"، "أمس"، "الآن") يتغير مع الساعة فصار علامة ثابتة `‹وقت›`؛
  نفس التحويل طُبّق على ملفات اللقطات (بدون إعادة تسجيل).
- فحص: الويب `tsc` ✓ `lint` ✓ `vitest` 91 ✓؛ التطبيق `dart analyze` ✓ `flutter test` 618 ✓.

## Step 44 — مراجعة جودة الكود (القسم 19): الإصلاحات الآمنة — التوثيق
- **19.1** `supabase/schema/current_functions.sql` (جديد، للقراءة فقط): النسخة **الحية** من الـ 112 دالة والـ 33 trigger، مع فهرس
  "الدالة ← آخر migration عرّفها"، ومولّد `supabase/schema/generate.mjs` (يقرأ من القاعدة فقط، SELECT). فُحص الملف: ماكو أي مفتاح
  أو كلمة سر (كلمة "password" فقط كأسماء أعمدة).
- **اكتشاف أثناء التوليد:** 4 أشياء بالقاعدة الحية **ما موجودة بأي migration** (انعملت يدوياً): مزامنة `geofence_zones` ← `branches`
  (رسم منطقة ينشئ/يعدّل/يحذف فرعاً)، و`invoke_push_notification` على `notifications`، و`rls_auto_enable`. مُوثّقة الآن؛ لم تُغيَّر.
- **19.4** `BUSINESS_RULES.md`: تصحيح كل المسارات القديمة (كلها تُفتح الآن)، وأقسام جديدة: دورة حياة المسير (الحركة ← القرار
  ← الاعتماد ← التراجع ← الإغلاق والترحيل ← التسوية بعد الإغلاق ← إعادة الفتح والأرشفة)، السجل المالي للموظف (أي جدول لأي شي)،
  وقائمة الأماكن عند إضافة نوع خصم/مكافأة جديد. وقواعد ناقصة: السلفة النقدية، الراتب الجزئي، التقريب على المجموع.
- **19.2** بابا قرار الغياب/التأخير موثّقان بـ `BUSINESS_RULES.md` وبتعليق عند الباب بالويب (`features/tracking/api.ts`) والتطبيق.
- **19.9** تعليق على `buildDailyReport`: التقرير للعرض فقط ومصدر الخصم هو `payroll_events`.
- `DEVELOPER_GUIDE.md`: مجلد `supabase/schema/`.
- لا تغيير بالسلوك ولا بالقاعدة.

## Step 45 — 19.15: تسجيل أشياء اللوحة اليدوية بـ migration
- **أُنشئ** `supabase/migrations/20261005000000_capture_dashboard_objects.sql`: أعمدة `geofence_zones` الأربعة (`latitude`,
  `longitude`, `radius_meters`, `polygon_coordinates` — كانت موجودة بالقاعدة الحية بس مو بالملفات)، والدوال
  `sync_geofence_coordinates` و`sync_geofences_to_branches` و`invoke_push_notification` **بنفس تعريفها الحي حرفياً**، والـ triggers
  الثلاثة (تنعمل بس إذا ما موجودة).
- على القاعدة الحية **ما يغيّر شي**: جُرّب داخل `BEGIN … ROLLBACK` على القاعدة الحية ونجح، والـ triggers بقت 3 بدون تكرار.
  اختبارات قاعدة البيانات (PGlite) تمر ويا الملف الجديد.
- `rls_auto_enable` ما انضاف: ميزة من منصة Supabase نفسها.
- ⚠️ **يحتاج من المستخدم:** `npx.cmd supabase db push`.

## Step 46 — 19.5: فترة السماح من جدول الأدمن، والبديل واحد
- فترة السماح **الفعلية دائماً هي اللي يحددها الأدمن** بجدول الدوام (لوحة الإدارة بالتطبيق أو الموقع): العمود إلزامي بالقاعدة
  (`grace_period_minutes NOT NULL DEFAULT 15`)، فكل جدول يحمل قيمته.
- البديل الاحتياطي صار ثابتاً واحداً بنفس رقم السيرفر: `kDefaultGraceMinutes` (`mobile/lib/core/models/work_schedule_model.dart`)
  و`DEFAULT_GRACE_MINUTES` (`web/src/lib/attendance.ts`). كان 0 بثلاث أماكن (تنبيه البصمة، الرئيسية، الحضور اليدوي بالويب)
  و15 بالباقي؛ عملياً ما يتغير شي لأن العمود ما يكون فارغ.
- **اختبار اللقطات صار مستقل عن التاريخ والساعة:** اسم اليوم، اسم الشهر، ومدة العمل "حتى الآن" تتحول لعلامات ثابتة، وتصحيح
  تطابق "قبل يومين". نفس التحويل على ملفات اللقطات (بدون إعادة تسجيل). جُرّب بعد منتصف الليل وبتاريخ جديد.
- فحص: `dart analyze` ✓، `flutter test` 618 ✓؛ الويب `tsc` ✓ `lint` ✓ `vitest` 91 ✓.

## Step 47 — 19.6: الرئيسية بالويب تختار جدول الدوام مثل السيرفر
- `web/src/features/overview/logic.ts` (عدد الغايبين اليوم) صار يستعمل `resolveWorkSchedule` (`lib/schedules.ts`): جدول الموظف ←
  القسم ← الفرع، **والأحدث عند التساوي** — نفس `get_effective_work_schedule` بالسيرفر. حُذفت `findSchedule` (كانت تاخذ أول جدول).
- يفرق بس إذا موظف عنده جدولين بنفس المستوى.
- اختباراتها انتقلت لـ `resolveWorkSchedule` + اختبار جديد لاختيار الأحدث. الويب: 92 ✓.

## Step 48 — 19.8: القسط المعروض عند إنشاء سلفة = اللي ينحفظ
- قاعدة واحدة بنفس قاعدة السيرفر (`_insert_loan_installments`): القسط = floor(المبلغ ÷ الأشهر)، والأخير ياخذ الفرق.
  `installmentPlan` بالويب (`features/loans/logic.ts`) والتطبيق (`core/logic/loan_rules.dart`) + اختبار بكل جهة.
- نافذة إنشاء سلفة بالويب ونافذتها بالتطبيق: كانت تعرض القسط مقرّب للأعلى (ceil)؛ هسه تعرض القسط الحقيقي و"آخر قسط" إذا يختلف.
- **تصحيح رسالة غلط بالتطبيق:** نافذة الأدمن كانت تكول "القسط أكثر من نصف الراتب — النظام سيرفض السلفة"، والسيرفر يقبلها
  من `20261003000000` (تنبيه فقط). صارت: "مسموح، والباقي يتسدد نقداً" مثل الويب.
- فحص: الويب 93 ✓، التطبيق 619 ✓.

## Step 49 — 19.11: "اليوم" بالتطبيق بتوقيت الشركة
- **أُنشئ** `mobile/lib/core/utils/company_time.dart`: `companyDateStr()` = التاريخ بتوقيت بغداد (UTC+3 ثابت، العراق بلا توقيت صيفي) —
  نفس `company_timezone()` بالسيرفر.
- يستعمله: سجل اليوم بالرئيسية (3 أماكن) وشاشة البصمة، ودمج البصمات المحفوظة بدون إنترنت (`mergeTodayOfflinePunches`).
- على موبايل توقيته بغداد **النتيجة نفسها بالضبط**؛ يفرق بس لموبايل توقيته غلط أو مسافر (كان يجيب سجل يوم غلط).
- **أُضيف فحص** `test/unit/company_time_test.dart` (منتصف الليل ورأس السنة)، واختبار الدمج صار يستعمل نفس الدالة (حتى ما يفشل على CI بتوقيت UTC).
- فحص: `dart analyze` ✓، `flutter test` 621 ✓.

## Step 50 — 19.10: قائمة واحدة لأسماء أنواع حركات الرواتب بالتطبيق
- `kPayrollEventLabels` (`mobile/lib/core/models/salary_slip_model.dart`): الـ 13 نوع بنفس أسماء الويب (`EVENT_LABELS`)، بدل قائمتين
  مختلفتين (`_lineLabels` بتفاصيل الكشف و`_labels` بمسير الشهر الحالي). كل مكان بقى ببديله ("بند" أو اسم النوع).
- الفرق الظاهر: أنواع كانت ناقصة صار يطلع اسمها العربي — `allowance`/`advance`/`other` بمسير الشهر الحالي (كانت تطلع بالإنگليزي)،
  و`advance`/`other` بتفاصيل الكشف (كانت "بند").
- `BUSINESS_RULES.md`: قائمة "إضافة نوع حركة جديد" تشير للقائمة الوحدة. **أُضيف فحص** `test/unit/payroll_labels_test.dart`.
- فحص: `dart analyze` ✓، `flutter test` ✓.

## Step 51 — 19.2: باب واحد لقرار الغياب/التأخير إذا لليوم حركة رواتب
- صفحة التتبع بالويب (`saveDecision` في `web/src/features/tracking/api.ts`) صارت تدوّر وقت الحفظ على حركة الرواتب لنفس الموظف
  واليوم والنوع؛ إذا موجودة → `decide_payroll_event` (نفس باب صفحة الرواتب والتطبيق). إذا ما موجودة → نفس المسار القديم بالضبط
  (سجل الحضور + إشعار من المتصفح). إذا قراءة الحركات ما مسموحة أو فشلت → المسار القديم.
- **الفرق الظاهر (موافَق عليه):** بحالة وجود حركة صار إشعار الموظف من السيرفر (نفس نص صفحة الرواتب ويذكر المبلغ — ويوصل إشعار
  حتى عند تطبيق خصم تأخير)، وصارت قيود الصلاحية تنطبق (المدير ما يقرر على نفسه ولا على فرع ثاني)، وإذا الكشف صادر تنعمل تسوية.
- **أُضيف فحص** `web/src/features/tracking/decision.test.ts` (3 حالات: مع حركة بدون أي كتابة ثانية ولا إشعار مكرر، بدونها، ونوع الغياب).
- `BUSINESS_RULES.md` (دورة حياة المسير، البند 3) محدّث.
- فحص: `tsc` ✓ `lint` ✓ `vitest` 96 ✓ `build` ✓ Playwright 27 ✓.

## Step 52 — 19.9: تقرير الحضور بالتطبيق يحسب التأخير مثل محرّك الرواتب
- `hourlyLeaveOverlap` (نفس `payroll_hourly_leave_overlap`): وقت الإجازة الزمنية المعتمدة يُطرح من دقائق التأخير والخروج المبكر.
- "متأخر" = الدقائق بعد الطرح > السماحية، أو بصمة "متأخر" وبقت دقائق > 0 — نفس شرط `sync_payroll_day`. قبل: بصمة "متأخر" = متأخر
  دائماً حتى لو الإجازة غطّت التأخير، فكان التقرير يكول "متأخر" بيوم ما انخصم.
- فرق مقصود يبقى (موثّق بالكود وبـ `BUSINESS_RULES.md`): موظف بدون جدول يُقاس على 09:00–17:00 حتى ما يختفي تأخيره من التقرير.
- **أُضيفت 5 اختبارات** بـ `test/unit/attendance_report_test.dart`. فحص: `dart analyze` ✓، `flutter test` 628 ✓ (لقطة التقرير مطابقة).

## Step 53 — 19.14: تقسيم تهيئة شاشة البصمة لخطوات
- `_initLocationAndBranch` (142 سطر) صارت 30 سطر تنادي 5 خطوات بنفس الترتيب وداخل نفس `try`:
  `_restoreCachedBranch` (الكاش) ← `_ensureLocationAccess` (GPS والصلاحية والموقع الدقيق) ← `_showLastKnownPosition` ←
  `_startPositionStream` ← `_refreshFromServer` (رفع البصمات المحفوظة، الفرع وسجل اليوم، الجدول والكاش — وضع أوفلاين إذا فشل) ←
  `_applyTodayWithOfflinePunches`. **الكود داخل كل خطوة منقول حرفياً**؛ نفس الرسائل ونفس معالجة الأخطاء.
- فحص: `dart analyze` ✓، `flutter test` 628 ✓، `flutter build apk --debug` ✓. ⚠️ يُنصح بتجربة بصمة على جهاز حقيقي.

## Step 54 — توافق الآيفون (مراجعة ثانية شاملة)
المرجع: سلوك أندرويد. كل إصلاح إما خاص بالآيفون، أو خلل حقيقي بالمنصتين (المساحة السفلية).
- **زر الاتصال ما يشتغل بالآيفون:** `canLaunchUrl('tel:')` يرجّع false لأي مخطط مو مذكور بـ `LSApplicationQueriesSchemes`
  (أندرويد عنده `<queries>` لـ tel). أُضيف `tel` بـ `ios/Runner/Info.plist` — الدليل وملف الموظف.
- **الكيبورد ما يتسكّر بالآيفون:** كيبورد الأرقام/الهاتف بالآيفون ما بيه زر "تم" وماكو زر رجوع، وFlutter ما يسكّره باللمس خارج
  الحقل على الموبايل. `AppChrome` (`offline_banner.dart`): على iOS فقط، اللمس على مكان فارغ يسكّر الكيبورد؛ الزر أو الحقل يفوز
  باللمسة طبيعي. أندرويد بدون تغيير.
- **أزرار النوافذ السفلية تحت شريط الهوم:** `showModalBottomSheet(useSafeArea: true)` يحمي الأعلى والجوانب فقط. دالة واحدة
  `sheetBottomPadding` (`app_overlays.dart`) = فوق الكيبورد إذا مفتوح وإلا فوق شريط الهوم/شريط التنقل؛ مستعملة بكل النوافذ
  (سلفة مباشرة، موظف جديد، جدول الدوام، الفرع، المستمسكات، `showAppSheet`). نافذتا ملف الموظف وتفاصيل السلفة + `AppPage`
  (الصفحات بدون شريط سفلي): آخر عنصر يوقف فوق الشريط. ينطبق على أندرويد من الحافة للحافة أيضاً (نفس الخلل).
- **الكاميرا المرفوضة = زر ما يسوي شي:** الآيفون ما يعيد طلب الصلاحية بعد أول رفض، و`image_picker` يرمي خطأ بصمت — فتصوير تعهد
  السلفة (إلزامي) كان يتوقف بدون أي رسالة. `AppImagePicker` (`shared/ui/app_image_picker.dart`): رسالة واضحة + زر "الإعدادات".
  كل اختيار صور بالتطبيق يمر منه (7 أماكن).
- **صلاحية الموقع المرفوضة:** بالآيفون أول رفض يصير نهائي (ما تنطلب مرة ثانية)، والشاشة كانت تطلب "فعّلها من الإعدادات" بدون زر.
  صار زر "فتح الإعدادات" يطلع للرفض النهائي (مثل الموقع الدقيق)، وعند الرجوع للتطبيق إذا تفعّلت الصلاحية تعيد الشاشة التهيئة
  تلقائياً (فحص بدون طلب، فما تطلع نوافذ).
- **محرك Flutter ثاني بلا فائدة:** `startTracking` كان يشغّل `flutter_background_service` على الآيفون أيضاً، فيفتح محرك ثاني
  بالذاكرة يشغّل دالة فارغة (التتبع بالآيفون من `LocationMonitorIOS.swift`). صار لأندرويد فقط.
- **إشعار مكرر محتمل:** الآيفون يعرض إشعار FCM والتطبيق مفتوح بنفسه (`AppDelegate willPresent`)؛ مستمع `onMessage` صار
  يعرض الإشعار المحلي لأندرويد فقط.
- `CFBundleLocalizations = ar`: نوافذ النظام داخل التطبيق (الصور، المشاركة، معاينة الملفات) بالعربي على الهواتف العربية.
  `statusBarBrightness` صريح بـ `main.dart` (iOS يتجاهل `statusBarIconBrightness`).
- **فحوص جديدة:** `test/unit/ios_compat_test.dart` (الكيبورد iOS/أندرويد، الأزرار تستلم اللمس، `sheetBottomPadding`، رسائل
  الكاميرا، زر الإعدادات)، و`test/screens/sheets_test.dart` (3 نوافذ على آيفون بشريط هوم — تفشل بدون الإصلاح: الزر كان عند 854 والحد 840).

## Step 55 — رحلات المستخدم على محاكيات الآيفون (فحص "مثل المستخدم")
- `test/support/journeys.dart`: 9 رحلات بالتطبيق الحقيقي (`HRProApp` + الموجّه الحقيقي + `AppChrome`) ببيانات وهمية:
  تبويبات الموظف؛ طلب إجازة كامل (منتقي التاريخ، الكتابة والكيبورد ظاهر، اللمس خارج الحقل يسكّره، نافذة تأكيد iOS، إرسال)؛
  طلب سلفة كامل (بدون تعهد ← رسالة، كاميرا مرفوضة ← رسالة + زر الإعدادات، تصوير، إرسال)؛ كشف الراتب/الدليل/الإشعارات
  والرجوع بالزر وبالسحب من حافة الشاشة؛ نافذة تسجيل الخروج والإلغاء؛ لوحة الإدارة وتبويباتها وأدواتها؛ إضافة موظف (الكيبورد
  مفتوح وزر الإنشاء يوصل فوقه، سحب النافذة لجوّه)؛ منح سلفة (حساب القسط)؛ جدول الدوام (منتقي الوقت والإلغاء).
  بكل خطوة: ماكو خطأ رسم، وماكو زر/حقل ثابت تحت النوتش أو شريط الهوم، والحقل المكتوب بيه مو مغطّى بالكيبورد.
- تنشغل محلياً (`test/screens/journeys_test.dart`: آيفون Dynamic Island، SE، آيباد، أندرويد — 36 فحص) وعلى كل محاكي
  بـ `ios_simulator_tests.yml` (`integration_test/user_journeys_test.dart`) مع لقطة لكل خطوة.
- **خلل لگاه فحص المحاكي:** `stopTracking` كان يرسل "أوقف الخدمة" لمكتبة خدمة الخلفية على الآيفون (الخدمة ما تشتغل هناك) —
  صار لأندرويد فقط مثل التشغيل. الخادم الوهمي: قناة خدمة الخلفية بالآيفون بترميز JSON الصحيح، ورد رفع الملفات بنفس شكل Supabase.
- `image_picker_platform_interface` (dev فقط، نفس النسخة الموجودة) للكاميرا الوهمية.

## Step 56 — تصليحات الرواتب 8 و9 و10 + الإعفاء بملاحظة وإخفاء التأخير (12)
موافَق عليها من المستخدم بعد تدقيق الرواتب. migration جديد `20261006000000_schedule_history_and_late_privacy.sql`.
- **(8) جدول الدوام له تاريخ:** `work_schedule_history` + trigger. تعديل الدوام يسري من يوم التعديل، والأيام السابقة على
  الجدول القديم. الجداول الحالية انسجلت "سارية من البداية" فالحساب الحالي ما يتغير.
- **(9) العطل:** ماكو تأخير ولا خروج مبكر بالجمعة أو العطلة الرسمية. مثال حي: 5 تشرين الأول عطلة رسمية («اجازة زيارة»)
  وموظف داوم: كان يطلع عليه تأخير 2,133 وخروج مبكر 14,600 — ينشالون.
- **(10) خصم مزدوج:** غياب كامل معتمد + إذن زمني بدون راتب بنفس اليوم = يوم واحد بس.
- **(12) الإعفاء بملاحظة:** ملاحظات جاهزة («نسي البصمة وهو مداوم»، «تأخير مبرر»...) بالموقع (صفحة الرواتب وصفحة القرارات)
  وبالتطبيق (لوحة الإدارة). الإعفاء ما يوصل بيه إشعار. إشعار البصمة ما يذكر التأخير، ولوحة «المتأخرون اليوم» تعرض بس اللي انخصم.
- **تجربة على القاعدة الحية داخل معاملة متراجَع عنها:** 78 حركة بدون أي تغيير، وانشالت حركتين (يوم العطلة) فقط.
- **فحوص:** `supabase/tests/test_schedule_history.mjs` (20 فحص) + تحديث فحصين قدام للقاعدة الجديدة؛ كل فحوص القاعدة ✓ (12 ملف).
  الويب: `decision.test.ts` (+2)، `tsc` ✓ `lint` ✓ `vitest` 98 ✓. التطبيق: `decision_card_test.dart`، `flutter test` ✓ `dart analyze` ✓.

## Step 57 — المساعد الذكي للأدمن (التطبيق + الموقع)
- **القاعدة** `20261008000000_hr_assistant.sql`: دوال قراءة فقط للأدمن (`assistant_find_employees` ببحث عربي، `assistant_attendance_log`
  يوم بيوم مع قرار الخصم من `payroll_events`، `assistant_payroll`، `assistant_loans`، `assistant_leaves`، `assistant_documents`،
  `assistant_day_overview`، `assistant_pending_decisions`، `assistant_top_late`، `assistant_branches`). بدون هواتف/إيميلات/مواقع.
- **السيرفر** `supabase/functions/hr-assistant/`: Gemini (مجاني) مع أدوات، حد 6 جولات وآخر 10 رسائل، ملفات Excel بنفس ألوان تقارير النظام
  (سجل الدوام يوم بيوم + ملخص؛ تفاصيل راتب الشهر)، أخطاء عربية (مثل انتهاء الحد المجاني).
- **التطبيق:** شاشة «المساعد الذكي» (لوحة الإدارة + الإعدادات، أدمن فقط)، فتح/مشاركة الإكسل، الوثائق بمعاينة. ماكو مكتبة جديدة.
- **الموقع:** صفحة `/dashboard/assistant` (أدمن فقط) + رابط بالقائمة.
- **فحوص:** القاعدة `test_hr_assistant.mjs` (20)، السيرفر `hr_assistant_test.ts` (9، Deno)، التطبيق `assistant_test.dart` (6)،
  الموقع `assistant.test.ts` (4). تجربة على القاعدة الحية داخل معاملة متراجَع عنها ✓. كل الفحوص الأخرى ✓.

## Step 58 — توسيع المساعد الذكي (المراحل A–D)
- **A تقارير** `20261008000100_hr_assistant_reports.sql`: إكسل فرع/كل الشركة، رواتب كل الموظفين، جاهزية الرواتب، تنبيهات وأنماط،
  مقارنة شهرين، ترتيب الفروع والأكثر انضباطاً، ملف شامل لموظف (`employee_profile_excel`).
- **B قرارات بتأكيد** `20261008000200_hr_assistant_decisions.sql`: `decision_context` ← `propose_decisions` = بطاقات «تأكيد/العكس».
  التنفيذ بس من ضغطة الأدمن عبر `decide_payroll_event` الموجودة (نفس باب صفحة الرواتب). الذكاء ما ينفذ شي.
- **C الصوت** `20261008000300_hr_assistant_voice.sql` (`assistant_name_hints`) + `voice.ts`: التسجيل (WAV أحادي 16kHz، أقصاه دقيقة)
  يتحول لنص بالعراقي حرفياً والأسماء بإملاء النظام، ويرجع النص يظهر كرسالة الأدمن. الصوت ما ينحفظ. التطبيق: مكتبة `record` +
  صلاحية المايك (`NSMicrophoneUsageDescription`، `RECORD_AUDIO`، `PERMISSION_MICROPHONE`). الموقع: MediaRecorder ← WAV.
- **D** `20261008000400_hr_assistant_summary_and_history.sql`:
  - **ملخص صباحي** 10:00 بغداد (pg_cron `assistant_morning_summary`، بدون ذكاء) ← إشعار `assistant_summary` لكل أدمن مرة باليوم؛
    يتطفى من قائمة المساعد (`system_settings.assistant_policy`). الضغط عليه بالإشعارات يفتح المساعد. أداة `morning_summary` بنفس الأرقام.
  - **مسودات تعاميم** `draft_message` ← بطاقة «نسخ» و«فتح كتعميم» (التطبيق: شاشة التعاميم بالنص جاهز؛ الموقع: نافذة «بث تعميم» بالرئيسية).
    النشر بيد الأدمن.
  - **حفظ المحادثات** `assistant_conversations`/`assistant_messages`: نص فقط، الأدمن صاحبها فقط (RLS)، الإضافة عبر
    `assistant_save_messages`، وتنحذف بعد 90 يوم (pg_cron `assistant_conversations_cleanup`). «المحادثات السابقة» بالتطبيق والموقع.
- **فحوص:** القاعدة `test_hr_assistant_reports/decisions/history.mjs`، السيرفر Deno (19)، التطبيق `assistant_test.dart` (16)،
  الموقع `assistant.test.ts` (12). تجربة الأجزاء الجديدة على القاعدة الحية داخل معاملة متراجَع عنها ✓.
- **على المستخدم:** `npx.cmd supabase db push` · `npx.cmd supabase functions deploy hr-assistant` · دمج PR · بناء APK جديد (صلاحية المايك).

## Step 59 — أقساط سلف ذكية: القسط الشهري هو الأساس
- **المشكلة (سلفة 10,000,000):** 100,000 انسجلت «مسددة» على قسط شهر 11 فشهر 10 ضاع والرواتب ما راح تخصمها؛ وتعديل السلفة
  وزّع الباقي بالتساوي (710,256 بدل 700,000) وبدا من الشهر الجاي؛ والدفع الأقل كان يكبّر آخر قسط.
- **القاعدة** `20261009000000_smart_loan_installments.sql`: أعمدة `origin_kind`/`origin_month`/`amount_locked`؛ التريجر يخلي كل قسط
  ≤ القسط الشهري والباقي أشهر جديدة «باقي شهر …»؛ `set_month_installment` (هالشهر أقل، الرواتب تخصم المبلغ الجديد)؛
  `postpone_loan_installment` (ينقل الشهر لآخر السلفة بملاحظة + إشعار)؛ `reschedule_loan` بالقسط الشهري بالضبط ويبدي من شهر
  الرواتب المفتوح؛ تصليح السلفة: شهر 10 = 100,000 غير مسدد، بعدها 700,000 ×13، وآخر شهر 12/2027 = 133,333 «باقي شهر 10/2026».
- **الموقع:** زر «هالشهر أقل» مع معاينة، التأجيل بتأكيد وملاحظة (RPC بدل تحديث التواريخ من المتصفح)، شارات الأقساط،
  تعديل السلفة يحسب عدد الأقساط وحده، وتنبيه إن «تسجيل دفعة» = فلوس انستلمت.
- **التطبيق:** شارات «باقي شهر / مؤجّل من / مبلغ هالشهر مخفّض» بشاشة سلفة الموظف وتفاصيل السلفة للأدمن.
- **فحوص:** `test_loans.mjs` (74)، `logic.test.ts` (18)، `my_loan_card_test.dart`. تجربة التصليح على القاعدة الحية داخل معاملة
  متراجَع عنها ✓ (كشف شهر 10 يخصم 100,000).
- **على المستخدم:** `npx.cmd supabase db push` · دمج PR · APK جديد.

## Step 60 — صفحة الرواتب أوضح + تأكيد حساب السلف والراتب الجزئي
- **فحص (قراءة فقط) لمسير 10/2026:** الراتب يخصم أقساط الفترة غير المسددة بس، ويتجاهل المؤجّل والنقدي، ويحترم «هالشهر أقل»؛
  الاعتماد يعلّم الأقساط مسددة والتراجع يرجعها؛ ترك العمل = راتب جزئي حسب «آخر يوم دوام». المشاكل اللي انلكت وتصلحت تحت.
- **القاعدة** `20261010000000_payroll_loans_clarity.sql`: `payroll_month_of`؛ `payroll_employee_summary` يضيف `loan_items`
  و`attended_days`/`scheduled_days` (الصافي نفسه)؛ `pay_loan_installment` يرفض «استقطاع راتب» قبل كشف الشهر؛ `settle_loan_on_exit`؛
  تصليح عام محمي لأقساط «استقطاع راتب» انسجلت مسددة قبل الكشف (مصطفى: شهر 10 = 100,000 ينخصم، 11 = 250,000، 12 = 150,000).
- **صفحة الرواتب:** «رواتب تشرين الأول 2026» + جملة «يُحسب الدوام من الأحد 27 أيلول إلى الاثنين 26 تشرين الأول · يوم الصرف …»،
  أسهم بين الأشهر، 3 أرقام بس، شريط خطوات (القرارات ← التنبيهات ← الاعتماد ← الإغلاق)، «داوم X من Y يوم»، شارة «يحتاج انتباه»
  بأسباب مفهومة، خانة السلف تبين «قسط شهر …»، وتفاصيل الراتب فيها أقساط هالشهر وزر «اخصم الباقي من آخر راتب».
- **السلف:** «أول شهر يستقطع» بدل تاريخ حر؛ الأقساط تنكتب «رواتب تشرين الأول 2026» بالموقع و«قسط رواتب شهر 10» بالتطبيق.
- **فحوص:** `test_payroll_loans.mjs` (25)، `test_loans.mjs` (75)، الموقع 120، التطبيق 698. تجربة على القاعدة الحية داخل معاملة
  متراجَع عنها ✓: كل الصافيات نفسها إلا مصطفى (ينخصم 100,000 بشهر 10).
- **على المستخدم:** `npx.cmd supabase db push` · دمج PR · APK جديد.

## Step 61 — فحص الرواتب: المرحلة 1 (تصليحات الفلوس)
- **القاعدة** `20261011000000_payroll_money_fixes.sql`:
  - منع حذف القسط المسدد (كان يرجّع المبلغ ديناً) ومنع التراجع عن قسط انخصم من راتب معتمد.
  - حماية الخصومات/المكافآت اليدوية من التكرار + تسجيل منو سجّلها، وتنظيف 3 قيود مكررة من نسخة قديمة للتطبيق
    (25,000 الثانية لأحمد علي جاسم وجبار، و«تأخير مفقود» 39,450 للمدير اللي محسوب بالمحرّك).
  - سجل الرواتب `salary_history`: الزيادة المجدولة صارت تنطبق (كانت ما تنطبق بسبب صيغة 2026/06/01)، والتغيير المباشر يسري من
    الشهر الحالي بدون ما يغيّر الأشهر الأقدم.
  - الاعتماد بعد نهاية فترة الدوام إلا آخر راتب لمن ترك، والقسط ينقص تلقائياً بدل الصافي السالب.
- **الموقع:** شلنا «حذف القسط المسدد»، والتراجع بس للدفعات اليدوية؛ زر الاعتماد يتفعّل بعد نهاية الفترة (أو لمن ترك).
- **فحوص:** `test_payroll_money.mjs` (30) + تحديث `test_qa_fixes.mjs`؛ القاعدة 18 مجموعة ✓، الموقع 121 + e2e 28 ✓.
  تجربة على القاعدة الحية داخل معاملة متراجَع عنها ✓: انحذفت 3 قيود مكررة، وراتب أحمد علي جاسم صار 800,000، والباقي نفسه.

## Step 62 — فحص الرواتب: المرحلة 2 (احتساب بزر + سرعة + صلاحيات)
- **القاعدة** `20261011000100_payroll_calculate.sql`: `get_payroll_run` ما يعيد الحساب بكل فتحة (كان يحسب كل يوم لكل موظف)؛
  `calculate_payroll` (زر «احتساب الرواتب») يحسب ويسجّل `calculated_at`؛ `payroll_nightly` (pg_cron 00:15 بغداد) يطبّق الزيادات
  المستحقة ويحسب آخر 3 أيام؛ `get_pending_payroll_decisions` بدون إعادة حساب؛ `get_payroll_events` المدير لفرعه بس.
- **الموقع:** خطوة أولى «احسب الرواتب» بزر وآخر وقت احتساب، والخطوات صارت 5.
- **فحوص:** `test_payroll_calculate.mjs` (12) + تحديث `test_payroll_engine.mjs`؛ القاعدة 19 مجموعة ✓، الموقع e2e 29 ✓.
  تجربة حية متراجَع عنها: فتح الصفحة 0.04 ثانية، الاحتساب 0.12 ثانية.

## Step 63 — فحص الرواتب: المرحلة 3 (البصمة الناقصة، البيانات، الإجازة، الأرشفة)
- **القاعدة** `20261011000200_payroll_data_quality.sql`: البصمة الناقصة بخصم مقترح من آخر تواجد مسجّل (قرار الأدمن، ما ينخصم تلقائياً)
  وتنحسب ضمن القرارات المعلّقة؛ فرع احتياطي لقرارات الموظف بدون فرع + موظف نشط لازم إله فرع؛ العطلة داخل الإجازة ما تنحسب من الرصيد؛
  شرط الأرشفة بس لمن جان بالخدمة؛ `has_schedule` بالملخص.
- **الموقع:** تنبيه «بيانات ناقصة» (راتب صفر/بدون فرع/بدون جدول)، زر «خصم» للبصمة الناقصة بمبلغ، تعديل الخانات ينحفظ فوراً بسبب،
  ملف Excel قبل الأرشفة، و«آخر يوم عمل» المقترح = آخر بصمة.
- **التطبيق:** بطاقة القرار تبين خصم البصمة الناقصة المقترح، وتعطيل الموظف يقترح آخر يوم بصم بيه.
- **فحوص:** `test_payroll_quality.mjs` (15) + تحديث `test_payroll_engine` و`test_leave_payroll`؛ القاعدة 20 مجموعة ✓، الموقع 121 + e2e 29 ✓،
  التطبيق 698 ✓. تجربة حية متراجَع عنها للمراحل الثلاث سوا ✓.

## Step 64 — الأشهر بالترتيب «الشهر العاشر»، تغيير الراتب بشهره، ونتيجة الاحتساب
- **الأشهر:** بالموقع والتطبيق والسلف والإشعارات تنكتب «رواتب الشهر العاشر 2026» بدل «تشرين الأول»، والتواريخ بالأرقام «الأحد 27/9».
  مطابقة إشعارات الراتب القديمة («شهر 10 سنة 2026») باقية.
- **تغيير الراتب (الموقع):** الراتب الحالي مقفول بالتعديل؛ «الراتب الجديد» + «من راتب يا شهر؟» (هذا الشهر لحد 11 شهر قدّام).
  هذا الشهر = يتغير الراتب هسه، شهر جاي = مجدول بشهره. القيم القديمة (2026/06/01) تنقرا كشهر رواتب.
- **احتساب الرواتب:** بعد الزر تطلع «نتيجة الاحتساب»: الأساسي، خصومات الدوام المثبتة، السلف، الصافي، والقرارات اللي تنتظر.
- **فحوص:** الموقع 123 + e2e 29 ✓، التطبيق 698 ✓ (الصور النصية تحدّثت للتاريخ بالأرقام والأشهر بالترتيب).

## Step 65 — المساعد الذكي أسرع
- **القياس:** دوال القاعدة للمساعد كلها أقل من 30ms على القاعدة الحية؛ التأخير من الذكاء (تفكير قبل كل رد + 3 جولات لكل سؤال).
- **`gemini.ts`:** يطلب أقل تفكير (`thinkingLevel: minimal` ثم `thinkingBudget: 0` ثم بدون) ويتذكر الصيغة اللي يقبلها الموديل؛
  إعادة المحاولة عند الضغط 0.7 ثانية بدل 1.5.
- **`tools.ts`:** أدوات الموظف تقبل الاسم مباشرة (`resolveEmployee`) فتروح جولة `find_employees`؛ أكثر من موظف بنفس الاسم يرجع
  للأدمن يختار. مكتبة Excel تتحمل بس لما ينطلب ملف (بداية تشغيل أخف).
- **`index.ts`:** فحص الجلسة والأدمن سوا، وسطر `hr-assistant timing` بالسجل لكل سؤال.
- **`prompt.ts`:** الأدوات سوا بنفس الخطوة، والأشهر بالترتيب «الشهر العاشر» بالأجوبة.
- **فحوص:** Deno 25 ✓ (3 جديدة للسرعة).

## Step 66 — المساعد الذكي: حل جذري للسرعة
- **السبب بالأرقام (سجل الدالة):** الرد الواحد من Gemini 7 ثواني، وسؤال بردّين وصل 68 ثانية؛ القاعدة شبه صفر. الموديل الافتراضي
  (`gemini-flash-latest`) ما يقبل `minimal` فكان يرجع لتفكيره الكامل.
- **`context.ts` (جديد):** بيانات جاهزة قبل السؤال (وضع اليوم + الموظف المذكور بالاسم) ← رد واحد من الذكاء لأغلب الأسئلة.
- **`index.ts`:** الموديل السريع (lite) للأسئلة العادية والأقوى للثقيلة والصوت؛ البيانات تنجاب ويا فحص الجلسة بنفس الوقت؛
  السجل يبين كل محاولة ويا Google.
- **`gemini.ts`:** التفكير حسب الموديل (lite = minimal، غيره = low)، مهلة لكل محاولة ثم الموديل الثاني، و404 يروح للاحتياطي.
- **فحوص:** Deno 29 ✓.

## Step 67 — مبلغ الخصم يبين ويتعدل + «الغائبون اليوم» بالتعاميم
- **القاعدة** `20261012000000_decision_amount_and_absent_board.sql`: `payroll_events.amount_override`؛ `decide_payroll_event` تقبل مبلغ اختياري
  (القديمة بثلاث مدخلات انحذفت والاستدعاء القديم يبقى شغال)؛ `sync_payroll_day` تحافظ على المبلغ المعدّل؛ `decide_absence_day` لغياب اليوم
  قبل الاحتساب؛ `payroll_day_rates` (أجر اليوم)؛ `get_absent_today` للوحة التعاميم.
- **التطبيق:** بطاقة القرار تبين «الخصم المحسوب» وحقل «مبلغ الخصم» قابل للتعديل (غياب اليوم هم يبين مبلغه)؛ قسم «الغائبون اليوم» بالتعاميم.
- **الموقع:** نافذة تأكيد القرار (صفحة الرواتب وصفحة المتابعة) بيها المبلغ المحسوب قابل للتعديل؛ وسم «مبلغ معدّل» بتفاصيل الراتب.
- **فحوص:** `test_decision_amount.mjs` (30)؛ القاعدة 21 مجموعة ✓، الموقع 125 + e2e 29 ✓، التطبيق 700 ✓. تجربة حية متراجَع عنها: الرواتب قبل = بعد،
  اللوحة تطلع الغائبين المخصومين اليوم، والمبلغ المعدّل يبقى بعد إعادة الحساب.

## Step 68 — الرئيسية بالتطبيق: «غائب» بعد نهاية الدوام بدل «متأخر 12 ساعة»
- `HomeTodayCard`: إذا خلص وقت الدوام وما بصم (يوم دوام، مو مجاز) ← شارة «غائب»، «انتهى دوامك» بوقت الانصراف، وزر «عرض سجل الدوام»
  بدل «تسجيل الحضور». الدوام اللي يعبر منتصف الليل يبقى مثل قبل.
- `punchNote`: بصمة حضور بعد نهاية الدوام تنكتب «بعد نهاية الدوام» مو ساعات تأخير.
- **فحوص:** `home_today_card_test.dart` (7)؛ التطبيق 707 ✓.

## Step 69 — خصم التأخير سقفه أجر يوم واحد
- **القاعدة** `20261013000000_late_capped_at_daily_rate.sql`: `sync_payroll_day` تحسب خصم التأخير = الأقل بين (الدقائق × أجر الدقيقة) وأجر اليوم،
  مع ملاحظة «الخصم محدد بأجر يوم واحد»؛ إعادة حساب المسيرات المفتوحة.
- **فحوص:** `test_late_cap.mjs` (8)؛ القاعدة 22 مجموعة ✓. تجربة حية متراجَع عنها: تغيّر تأخيرين معلّقين بس (23,533 و22,000 ← 20,000)، وباقي الرواتب نفسها.

## Step 70 — تنظيف آمن للبيانات القديمة وتخفيف التكلفة (نتيجة فحص التكلفة)
- **الفحص وجد:** القاعدة 179MB منها 161MB سجلات نظام (سجل المهام 62MB + ردود الإشعارات 99MB) وبيانات التطبيق 2.7MB بس؛ «تنظيف بيانات شهر»
  كان يرجّع خصومات الشهر المعتمدة (تجربة: +22,500 بالمسير المفتوح)؛ القاعدة تسمح بحذف سلفة عليها باقي؛ خريطة التتبع بالتطبيق تعيد تحميل كل نقاط اليوم كل 15 ثانية.
- **القاعدة** `20261014000000_safe_cleanup.sql`: `payroll_cleanups` (سجل)، `payroll_day_frozen` + `sync_payroll_day` (اليوم المنظّف ما ينعاد حسابه)،
  `manual_purge_month_data` (بدون إعادة حساب + يرفض إذا اكو قرار معلّق)، `payroll_cleanup_preview/run` (تنظيف مسير)، `guard_loan_delete`،
  `purge_system_logs` + مهمة يومية + تفريغ أول مرة.
- **الموقع:** الإعدادات ← «تنظيف مسير مغلق» (بدل تنظيف شهر ميلادي): شروط، أعداد، تأكيد، سجل. حذف السلفة المسددة ينزّل كشفها Excel أولاً،
  والسطر ينحذف قبل صورة التعهد.
- **التطبيق:** خريطة التتبع الحي تجيب النقاط الجديدة بس (حسب وقت وصولها للسيرفر) وتدمجها، تحديث واحد كل 5 ثواني كحد أقصى من البث المباشر،
  واليوم القديم ما يتحدث.
- **فحوص:** `test_safe_cleanup.mjs` (37)؛ القاعدة 23 مجموعة ✓؛ تجربة حية متراجَع عنها: الرواتب قبل = بعد.

## Step 71 — عمر بيانات التتبع برقم واحد (45 يوم)
- **القاعدة** `20261015000000_single_tracking_retention.sql`: الإعداد `tracking_archive_days` = 45 وهو المصدر الوحيد (كانت مهمة شهرية ثابتة 90 يوم
  تغلب الإعداد 180)؛ المهمة الشهرية انلغت والتنظيف اليومي يكفي؛ الإعداد لازم بين 35 و 366.
- **الموقع:** حقل الاحتفاظ بالإعدادات بحده الأدنى 35 وشرح مبسط.
- **فحوص:** `test_tracking_retention.mjs` (9)؛ القاعدة 24 مجموعة ✓. تجربة حية متراجَع عنها: ما ينحذف شي هسه (أقدم نقطة عمرها 14 يوم).

## Step 72 — سجل دائم للسلف المسددة، تسليم الرواتب، وتنظيف السلف
- **القاعدة** `20261016000000_settled_loans_archive.sql`: `settled_loans` + `archive_settled_loan` (ملخص دائم ثم حذف)، `loans.loan_no` (يعطيه السيرفر)،
  `guard_loan_delete` (المعتمدة تنحذف بس من الأرشفة)، `guard_slip_with_archived_loan` (تصليح: إلغاء اعتماد كشف بعد حذف سلفته كان يضيّع القسط)،
  `mark_payroll_delivered` + `delivered_at`، معاينة المسير بقائمة المستثنى وتقدير المساحة وشرط التسليم، `loans_cleanup_preview/run`.
- **الموقع:** السلف: زر «أرشفة» بدل الحذف، تبويب «المؤرشفة» بتفاصيل كل سلفة وكشفها Excel، والرقم المرجعي بالجدول والكشف.
  الإعدادات: قسم «تنظيف السلف»، قائمة المستثنى، تقدير المساحة، و«تقرير المعاينة Excel». الرواتب: الخطوة 6 «تسليم الرواتب».
- **فحوص:** `test_settled_loans.mjs` (41)؛ القاعدة 25 مجموعة ✓، الموقع 132 + e2e 30 ✓. تجربة حية متراجَع عنها: الرواتب والكشوف قبل = بعد،
  السلف تترقم L-0001…L-0006، وماكو سلفة مسددة هسه (3 مستثناة عليها باقي، وطلب مرفوض قديم واحد مرشح).

## Step 73 — تصليح وكفة صفحة الموظفين بعد التصفير
- **السبب:** تصفير الإطلاق كتب `document_urls` للحسابين `{}` (كائن) بدل `[]`، ففتح ملف الموظف بالموقع وكف («h.map is not a function»)،
  وشاشات التطبيق اللي تقرا المستمسكات كانت راح توكف هم، والموظف ما يكدر يضيف مستمسك.
- **القاعدة** `20261017000000_document_urls_always_array.sql`: تصحيح القيم، القيمة الافتراضية `[]`، وقيد يمنع غير القائمة.
- **الموقع:** `documentList` (`web/src/features/employees/logic.ts`) بكل مكان يقرا المستمسكات. **التطبيق:** `JsonRow.strings` بالنماذج وشاشة الإعدادات.
- **فحوص:** `test_document_urls.mjs` (6)، e2e يفتح ملف موظف مستمسكاته `{}` (يفشل بدون التصليح)؛ القاعدة 26 ✓، الموقع 133 + e2e 31 ✓، التطبيق 712 ✓.

## Step 74 — تدقيق 14/10 المرحلة 1: صلاحيات مدير الفرع وحدود المبالغ
- **القاعدة** `20261018000000_fix_rls_manager_scope_and_limits.sql`:
  - المدير يشوف ويكتب لفرعه بس (BUG-002/003): `managed_employee_ids()` بسياسات الحضور والإجازات والرصيد والتتبع والوقفات والمخالفات
    والإشعارات، و`get_leave_balance`/`get_effective_work_schedule`/`send_idempotent_notification`.
  - حذف المستمسكات للأدمن بس (BUG-004)؛ الصورة الشخصية بمجلد صاحبها، والمستمسكات 10MB صور وPDF (BUG-016).
  - الراتب ما ينقرا مباشرة (BUG-005): `GRANT SELECT` لأعمدة غير الراتب + `get_employee_pay`؛ صلاحية «الموظف يعدّل سطره» صارت بسيطة
    (الحماية بـ `protect_employee_columns`)، و`check_bonus_deduction_amount` بصلاحية المالك.
  - مبلغ القرار (PAY-003): ≤ أجر يوم، الإضافي ≤ المحسوب، والمدير يقلل بس (`_payroll_event_computed_amount`).
  - «آخر يوم عمل» محمي (PAY-004)؛ الإجازة بعد القرار للأدمن بس، وتعديل المعتمدة يفحص الرصيد والتداخل (PAY-005).
  - السلفة المعتمدة ما ترجع مرفوضة (BUG-012)؛ الموظف يشوف حركاته المعتمدة بس، بالقراءة وبمعاينة «راتبي» (BUG-014).
- **الموقع:** الراتب من `get_employee_pay` (`web/src/lib/employeePay.ts`) بقائمة الموظفين والسلف؛ عدّاد الموظفين بدون `*`.
  سيرفر e2e الوهمي يرفض قراءة الراتب من الجدول مثل الحقيقي.
- **التطبيق:** الراتب من `get_employee_pay` (الموظفين، السلف، لوحة الإدارة، طلب السلفة). المدير ما يشوف الفروع وأوقات الدوام والأجهزة
  والمستمسكات والراتب (حتى برابط مباشر: `kAdminOnlyRoutes`)، وأي حفظ ما أثّر يطلع «ما تغيّر شي» (`ensureChanged`).
- **فحوص:** `test_manager_scope.mjs` جديد؛ تحديث `test_late_cap` (حد أجر اليوم) و`test_user_flows` (الصف ما يوصل المدير)؛
  `manager_scope_test.dart`؛ فحص لوحة المدير بالتطبيق صار يتأكد من غياب الأجهزة والفروع.
- **ترتيب التحديث:** الموقع والتطبيق الجديدين يقرون الراتب من `get_employee_pay`، وإذا الدالة بعدها ما موجودة (قبل `db push`) يقرونه مباشرة مثل قبل،
  فيشتغلون قبل التحديث وبعده. النسخة القديمة من التطبيق تحتاج تتبدل بعد التحديث (كانت تقرا الراتب مباشرة).
- **النتيجة:** القاعدة 27 مجموعة (740 فحص) ✓، الموقع 136 + e2e 31 ✓، التطبيق 717 ✓ والمحلل نظيف. تجربة حية متراجَع عنها: المدير ما يقرا الراتب،
  يشوف موظفين فرعه ويعدّل سطره، الأدمن يقرا الرواتب من الدالة، والصلاحيات القديمة الواسعة انشالت.

## Step 75 — المرحلة 1 (تكملة): سد الخطر المتبقي
- **المدير ما يستنتج الراتب من المبالغ** (`20261018000100_hide_pay_amounts_from_managers.sql`): أعمدة المبلغ وأجر اليوم والدقيقة بحركات الرواتب ما تنقرا مباشرة؛
  الأدمن يقراها من `get_payroll_event_amounts`؛ `payroll_day_rates` للأدمن بس؛ `get_payroll_events` و`get_pending_payroll_decisions` ورد
  `decide_payroll_event` بدون مبالغ لغير الأدمن (والموظف بـ`get_payroll_events` يشوف المقرر بس)؛ المدير ما يكتب مبلغ (يقرر خصم بالمحسوب
  أو إعفاء)؛ المكافآت والخصومات اليدوية ما ينقرن للمدير. الموقع (صفحة التتبع) والتطبيق (بطاقة القرار) يخفون المبلغ عن المدير.
- **عمود جديد بدون قرار ما يمر:** `test_column_grants.mjs` يفشل إذا عمود بجدول الموظفين أو حركات الرواتب ما انقرر (ينقرا لو مخفي)،
  أو إذا قائمة أعمدة الموقع/التطبيق ما تطابق القاعدة، أو إذا شاشة تطلب عمود مخفي مباشرة. انجرب: عمود وهمي جديد يفشّل الفحص برسالة واضحة.
- **فحوص:** `test_manager_scope.mjs` (قسم جديد للمبالغ)، `test_column_grants.mjs`، e2e «المدير يقرر غياب بدون مبلغ»، فحص بطاقة القرار بالتطبيق.

## Step 76 — تدقيق 14/10 المرحلة 2: البصمة بدون إنترنت (BUG-001، FEATURE-004)
- **المشكلة:** وقت البصمة المحفوظة بدون إنترنت = ساعة الموبايل؛ وضع الطيران + تغيير الساعة كان يخفي التأخير والخروج المبكر بلا أي علامة.
- **القاعدة** `20261019000000_fix_attendance_offline_punch_time.sql`: أعمدة مصدر الوقت ووقت ساعة الموبايل بالحضور (البصمات القديمة بدون إنترنت = «تحتاج مراجعة»)؛
  `server_now()`؛ `punch_attendance` يقبل الوقت المحسوب ومصدره ويرجّع وقت السيرفر (التطبيق القديم يكمل يشتغل وبصماته تتعلّم للمراجعة)؛
  `track_attendance_time_source` (تعديل الإدارة = يدوي، وقت الموبايل ما يتعدّل)؛ `mark_offline_punch_reviewed` (أدمن/مدير الفرع، ينسجل بـ audit_log).
- **التطبيق:** قناة `clockSnapshot` بأندرويد (`SystemClock.elapsedRealtime` + `BOOT_COUNT`) والآيفون (`CLOCK_MONOTONIC` + وقت التشغيل)؛
  `TrustedClock` يحفظ وقت السيرفر (شاشة البصمة + رد كل بصمة) ويحسب وقت البصمة المحفوظة؛ تقرير الحضور يبين «بدون إنترنت / تحتاج مراجعة»
  وزر «تمت المراجعة». سيرفر قبل التحديث: البصمة ترجع للطريقة القديمة، والتقرير يقرا بدون الأعمدة الجديدة.
- **الموقع:** سجل الحضور يبين مصدر الوقت وفرق ساعة الموبايل، وزر «N بصمة بدون إنترنت تحتاج مراجعة» (فلتر) و«تمت المراجعة».
- **فحوص:** `test_offline_punch.mjs`، `offline_punch_time_test.dart`، فحوص `punchTimeInfo`، و e2e «بصمة تحتاج مراجعة».

## Step 77 — تدقيق 14/10 المرحلة 3: معادلات الراتب (PAY-001، PAY-006، PAY-010، PAY-011؛ PAY-008 بدون تغيير)
- **قرارات صاحب الشركة 15/10/2026:** المنتهية خدمته ياخذ أيام دوامه بس (حتى بدون بصمة) وينخصم بس اللي قرره الأدمن؛ المباشر مثل أي موظف من يوم مباشرته؛
  الخصومات الأكبر من الراتب ما توقف الاعتماد؛ الراتب كامل بدون بصمات إلا إذا الأدمن غيّبه (بدون تغيير).
- **القاعدة** `20261020000000_fix_payroll_partial_exit_and_slip.sql`:
  - `payroll_employee_summary`: الأساسي حسب الحالة (`basic_basis`: full / joined / end_of_service / none) ويا شرح `basic_note`.
    مثال (راتب 900,000، أجر اليوم 30,000): باشر رابع يوم = 810,000 بأي مسير (كان 28 يوم: 750,000، 31 يوم: 840,000)؛
    ترك بعد 14 يوم (12 يوم دوام) = 360,000 (كان 420,000).
  - `approve_payroll_slip`: صافي ما ينزل تحت الصفر (سطر `excess_deduction`)، سطور بالدينار + سطر `rounding`، وربط سجل الأقساط بالكشف.
  - `payroll_loan_caps` + `_cap_loans_to_net` + `revert_payroll_slip`: إلغاء الاعتماد يرجّع الأقساط اللي نقصت/تأجلت.
  - `end_of_service_preview(employee, last_day)` (أدمن): يحسب آخر راتب لكل مسير مفتوح ويتراجع (ما يحفظ شي).
- **الموقع:** «إنهاء خدمات الموظف» (بدل «حذف أو أرشفة») يبين معاينة آخر راتب قبل التأكيد؛ تفاصيل الراتب تبين سطر الشرح؛
  تنبيه الصافي السالب يشرح شنو يصير وقت الاعتماد؛ مجموع الصافي ما يحسب السالب.
- **التطبيق:** «إنهاء الخدمات» (بدل «تعطيل الحساب»): آخر يوم ← معاينة آخر راتب ← تأكيد؛ أسماء سطور الكشف الجديدة.
  سيرفر قبل التحديث: التعطيل يشتغل بدون معاينة.
- **فحوص:** `test_payroll_partial.mjs` (مسيرات 28/29/30/31 يوم، ترك، عطلة رسمية، آخر يوم بعد القطع، المعاينة ما تحفظ شي، خصومات أكبر من الراتب،
  إلغاء الاعتماد يرجّع الأقساط، فرق التقريب)، `test_payroll_engine.mjs` (القاعدة الجديدة)، `end_of_service_test.dart`، فحوص الموقع، و e2e «إنهاء الخدمات».

## Step 78 — تدقيق 14/10 المرحلة 4: تاريخ الموظف (PAY-002، PAY-009، FEATURE-001)
- **قرارات صاحب الشركة 15/10/2026:** النقل يسري من يوم التغيير دائماً (بدون حقل تاريخ)؛ الراجع للعمل راتبه مثل المباشر (الراتب ناقص أيام الانقطاع).
- **القاعدة** `20261021000000_employee_assignment_history.sql`:
  - `employee_assignment_history` (فرع/قسم بتاريخ، يكتبه trigger `record_employee_assignment`؛ الموجودين = فرعهم الحالي من البداية)،
    `employee_assignment_at`، و`payroll_schedule_at` صار يستعمل فرع وقسم ذاك اليوم.
    مثال التدقيق: نقل من دوام 9–2 لدوام 8–4 كان يطلّع تأخير 65 دقيقة وخروج مبكر 120 دقيقة على كل يوم قديم (77,083 على 10 أيام) — هسه ولا شي.
  - `employee_service_breaks` + `employee_in_service`: `sync_payroll_day` ما يسوي حركات لأيام الانقطاع، و`payroll_employee_summary`
    ينقصها من الراتب (`returned`، `gap_days`). مثال: 900,000، ترك 10/10 ورجع 20/10 = 630,000 (كان: كامل + 9 غيابات تنتظر قرار).
  - `set_termination_date` يحفظ الانقطاع عند التفعيل؛ `reactivate_employee(employee, return_date)` (أدمن) يعيد حساب المسيرات المفتوحة وينبّه إذا كشف شهر الرجوع معتمد.
  - `get_employee_history`؛ تقرير الحضور بالمساعد يكتب «خارج فترة الخدمة» لأيام الانقطاع.
- **الموقع:** الاسترجاع من الأرشيف يطلب «تاريخ الرجوع للعمل» (حقل تاريخ بنافذة التأكيد `useConfirmDate`)؛ «سجل الموظف» بملف الموظف.
- **التطبيق:** «تفعيل الحساب» يطلب تاريخ الرجوع؛ «سجل الموظف» بملف الموظف. سيرفر قبل التحديث: تفعيل عادي وبدون سجل.
- **فحوص:** `test_employee_history.mjs` (النقل وسط المسير وإعادة الاحتساب، القسم، تغييرين بيوم، منو يكتب/يقرا السجل، الرجوع وأيامه وراتبه، التواريخ الممنوعة،
  التفعيل القديم، تنبيه الكشف المعتمد، السجل وصلاحياته)، `employee_history_test.dart`، و e2e «استرجاع موظف بتاريخ رجوع وسجله».
  تجربة على القاعدة الحية (تتراجع): كل حركات وملخصات المسيرات المفتوحة نفسها بالضبط قبل وبعد.

## Step 79 — تدقيق 14/10 المرحلة 5: التزامن والسرعة (PAY-007، BUG-018، BUG-013)
- **القاعدة** `20261022000000_payroll_concurrency_and_batches.sql`:
  - (PAY-007) فحص تكرار قبل التحديث (يوقف بدون حذف إذا اكو)، وثلاث قيود فريدة جزئية على `payroll_events`
    (`uq_payroll_events_engine_day`، `uq_payroll_events_manual`، `uq_payroll_events_open_adjustment`)؛ قفل لكل موظف ويوم بـ`sync_payroll_day`
    ولكل قيد بـ`sync_payroll_manual`؛ `ORDER BY id` بـ`sync_payroll_period` و`payroll_nightly` و`trg_payroll_holiday`.
  - (BUG-018) `calculate_payroll_batch(month, after, limit)`: 10 موظفين بكل طلب بالترتيب، وآخر دفعة تسجّل `calculated_at`.
    قياس بالسيرفر الحي: ~1.5 ملي ثانية لكل موظف بكل يوم. بنسخة الفحص: 204 موظف بطلب واحد 8–26 ثانية، وبالدفعات أبطأ طلب ~1.2 ثانية.
  - (BUG-013) `trg_payroll_leave`: كل الأيام اللي فاتت، والقادمة لحد 92 يوم من اليوم (كان أول 92 يوم من بداية الإجازة بس).
- **الموقع:** زر «احتساب الرواتب» يحسب على دفعات ويبين التقدم؛ سيرفر قبل التحديث = طلب واحد مثل قبل.
- **التطبيق:** بدون تغيير (ما يحتاج APK).
- **فحوص:** `test_payroll_concurrency.mjs` (القيود ترفض النسخة الثانية، الحساب مرتين = حركة وحدة، الدفعات = نفس نتيجة الطلب الواحد، الصلاحيات، إجازة 150 يوم)،
  e2e «الاحتساب على 3 دفعات» و«سيرفر قديم = طلب واحد». تجربة على القاعدة الحية (تتراجع): ماكو تكرار، القيود انخلقت، الدفعات = الطلب الواحد، والنسخة المكررة انرفضت.

## Step 80 — تدقيق 14/10 المرحلة 6: الموقع والملفات (BUG-007، 008، 009، 010، 017، 019، CODE-005)
- **القاعدة** `20261023000000_employee_files_and_operations.sql`:
  - `trash_removed_employee_files` (trigger): المستمسك المشال والصورة المشالة للسلة 30 يوم بعد الحفظ (بالحجم، بس الموجود، مرة وحدة).
  - `employee_code_seq` + `next_employee_code` + `assign_employee_code`: EMP-003، EMP-004... إذا ما انكتب كود.
  - `save_employee`، `end_employee_service`، `restore_archived_employee`، `destroy_archived_employee`: كل عملية بمعاملة وحدة
    (ومعها تصليح خيار «أرشفة»: النوع الصحيح `archived`).
  - `cleanup_run_tokens` + `issue_cleanup_token` وتحديث مهمة `daily_trash_storage_cleanup` حتى ترسل كود مؤقت.
- **دالة السيرفر** `daily-cleanup`: ترفض أي طلب بدون كود مؤقت صالح (تنشر بعد تحديث القاعدة).
- **الموقع:** دوال توقيت بغداد (`baghdadIso`، `baghdadHM`، `baghdadDayStartIso/EndIso`) بالحضور اليدوي والفلاتر والتعاميم والعرض والطباعة؛
  تعديل/إنهاء/استرجاع/إتلاف الموظف بالدوال الجديدة (سيرفر قديم = الخطوات القديمة بترتيب آمن)؛ رقم الموظف من السيرفر؛ أشهر الرواتب من أول مسير.
- **التطبيق:** تعديل المستمسكات ما يحذف ملفات (السلة من القاعدة بعد الحفظ، والملفات اللي انرفعت وما انحفظت تنحذف)؛ رقم الموظف من السيرفر.
- **فحوص:** `test_employee_files.mjs` (السلة بعد الحفظ بس، الحفظ الفاشل ما يغيّر شي حتى الإيميل، الحذف النهائي يحط الملفات بالسلة، الأرشفة/الاسترجاع/الإتلاف،
  الأرقام بالتسلسل، الكود المؤقت)، `baghdad-time.test.ts` (كمبيوتر بتوقيت لوس أنجلوس)، e2e (التعديل بخطوة وحدة بدون حذف ملفات، الأرشفة، أشهر الرواتب)،
  وفحص التطبيق لرقم الموظف. تجربة على القاعدة الحية (تتراجع): الرقم التالي EMP-003، الأرشفة والاسترجاع يشتغلون، والصورة المشالة للسلة.

## Step 81 — تدقيق 14/10 المرحلة 9: تنظيف وترتيب (CODE-001، 003، 004، 006 لحد 011، 013 + التطبيق بتوقيت بغداد)
- **قرار صاحب الشركة 17/10/2026:** المرحلتين 7 (سجل العمليات) و8 (الدوام الليلي) انلغن. بالتاسعة البنود 1–9؛ ترقية المكتبات (CODE-012)
  تنتقل لمرحلة لحالها بعد قرار البند 10 (CODE-014)، وبعدها المرحلة 10 (دمج ملفات القاعدة).
- **القاعدة** `20261024000000_stage9_cleanup.sql` (تجربة على القاعدة الحية: نفس حركات وملخصات الرواتب بالضبط):
  - (CODE-013) الراتب بدون default وNOT NULL. (CODE-008) حذف `idx_attendance_employee_date` و`idx_salary_slips_employee_month` المكررة، وإضافة `idx_loan_installments_loan`.
  - (CODE-006) حذف `documents`، `branch_schedules`، `orphan_storage_candidates_cache` ومهمتها الأسبوعية الفاضية، `employees.plain_password`
    (والـ trigger اللي يمسحه)، `leave_balances.annual_used/sick_used`. الحذف محمي: يوقف إذا اكو بيانات. `tracking_schedules` و`employee_geofence_assignments`
    تبقى لحد ما كل الموبايلات تتحدث (تنحذف بالمرحلة 10).
  - (CODE-007) نقل الرموز الموجودة لـ `fcm_tokens` و`copy_legacy_push_token` للنسخ القديمة.
  - (CODE-003) `sync_payroll_day` صارت ترتّب أربع دوال: `_payroll_day_attendance_events`، `_payroll_day_leave_events`، `_payroll_day_hourly_leaves`، `_payroll_day_apply` (النص نفسه).
- **دالة الإرسال** `push-notification`: تقرا وتنظف `fcm_tokens` بس.
- **ملف الدوال** (CODE-001): `generate.mjs` يبني من ملفات migrations بـ PGlite (`buildSchema` بـ `supabase/tests/lib.mjs`)، والفحص التلقائي `--check` يفشل إذا الملف قديم.
- **الموقع** (CODE-009): `ensureChanged` بالتعديلات والحذف الإدارية (الأجهزة، الفروع، الإجازات، السلف، الإعدادات، الجداول، التعاميم، العطل، السلة، الحضور).
- **التطبيق:** ساعة بغداد بكل العرض و«اليوم» (`toCompanyTime`، `companyNow`، `companyWallToUtc`، `parseServerTime`)؛ يوم القطع من السيرفر (`PayrollSettings`)؛
  الرمز بـ `fcm_tokens` بس؛ فحص السياج القديم (جدول فارغ) وقراءة `tracking_schedules` انشالوا (نفس السلوك)؛ `ensureChanged` بباقي التعديلات؛ الراتب إجباري بالنموذج.
- **التوثيق** (CODE-010/011): أرقام `ARCHITECTURE.md`؛ `mobile/android/build/` مستبعد من git.
- **فحوص:** `test_stage9_cleanup.mjs`؛ تحديث فحوص كانت تعتمد على الأشياء المحذوفة؛ `write-guard.test.ts`؛ `company_time_test.dart`؛
  كل فحوص التطبيق تنجح بتوقيت بغداد وطوكيو ولوس أنجلوس (قبل: 6 شاشات تختلف).

## Step 82 — تدقيق 14/10 البند 10 (CODE-014): شاشات التطبيق تقرا من نماذج بدل الخرائط الخام
- **قرار صاحب الشركة 17/10/2026:** ينسوى هسه، وبعده مباشرة ترقية المكتبات، وتجربة وحدة على الموبايل للاثنين.
- **نفس العرض بالضبط:** كل لقطات الشاشات النصية (`test/goldens/text`) ما تغيّرت، وكل الفحوص تنجح بتوقيت بغداد وطوكيو ولوس أنجلوس.
- **البصمة والرئيسية:** سجل اليوم `AttendanceModel` (ومعه `withPunch` لدمج بصمات الجهاز بدون إنترنت، و`QueuedPunch` لطابورها)،
  جدول الدوام `WorkScheduleModel` (`ScheduleService` يرجعه)، الفرع `BranchModel`، والملف الشخصي `DirectoryEntry`. كاش البصمة بنفس الأعمدة.
- **الرواتب:** أسطر الكشف `SalarySlipLine`، وبنود الكشوف القديمة `PayslipDetail` (مع الكشف المرتبط ووقت التسجيل)، وأيام الدورة من `PayrollSettings.cycleDaysFrom`.
- **الإجازات:** أنواع الإجازة `LeaveTypeOption`. **الإعدادات:** الملف الشخصي `DirectoryEntry`.
- **الإدارة:** التخزين والأفرع تقرا الصفوف بالقراءة الآمنة (`rowsOf`، `str`، `dbl`)؛ صورة الموظف بالتتبع الحي من `TrackedEmployee.avatarUrl`.
- **فحوص:** نفس الحالات تمر عبر النماذج مثل التطبيق، وحالة جديدة: بصمة بدون إنترنت وبدون سجل من السيرفر تبدي سجل اليوم.
- ما تغيّر شي بقاعدة البيانات ولا بالموقع.

## Step 83 — ترقية المكتبات (CODE-012)، الجزء الأول: الموقع
- **قرار صاحب الشركة 17/10/2026:** ترقية كل المكتبات، الموقع أولاً وبعده التطبيق، وبدل مكتبة Excel القديمة `write-excel-file` (مو exceljs: عليها هي هم تنبيه وحجمها 9 أضعاف).
- **Next** 16.3.7 ← 16.4.2 (يسد 6 تنبيهات أمنية عالية)، React 19.3.1، `@supabase/supabase-js` 2.118، `lucide-react` 1.59.
- **Excel:** `xlsx` (تنبيهين عاليين بدون إصلاح) انشالت؛ الملفات الأربعة (كشف السلفة والمؤرشفة، أرشيف الرواتب، تقرير التنظيف، تقرير التتبع)
  تنبني بـ `src/lib/excel.ts` بنفس الشيتات والأعمدة؛ تقرير التتبع بنفس الاتجاه العربي ودمج سطور العنوان وعرض الأعمدة.
  التنزيل صار ينتظر الملف: كشف السلفة لازم ينزل قبل الأرشفة مثل قبل.
- **أدوات التطوير:** vitest 5، ESLint 10 (Next 16.4 يدعمه)، Playwright 1.64، `@types/node` 24، والفحص التلقائي على Node 24 (نسخة 20 انتهى دعمها).
  TypeScript يبقى 5.9: نسخة 7 ما بيها الواجهة اللي يقراها Next وأداة الفحص.
- **الأمان:** صفر تنبيهات بكود الموقع اللي يوصل للناس (چانت 9). باقي 5 تنبيهات بأداة فحص الكود (ESLint) على حاسبة التطوير بس، ماكو إلها إصلاح لحد الآن.
- **فحوص:** `excel.test.ts` يفتح الملف ويتأكد من الشيتات والاتجاه والدمج والعرض؛ فحص المتصفح ينزّل تقرير التنظيف فعلاً ويفتحه.

## Step 84 — ترقية المكتبات (CODE-012)، الجزء الثاني: التطبيق
- **Flutter** 3.41.9 ← 3.47.7 (Dart 3.13)، بالحاسبة وبالفحص التلقائي (5 ملفات).
- **المكتبات لآخر نسخة:** Firebase (core 5، messaging 17)، الإشعارات المحلية 22، الموقع 14، الصلاحيات 13، الخرائط 8 + latlong2 0.10،
  Syncfusion (PDF و Excel) 35، Riverpod 3، معلومات الجهاز والتطبيق، المشاركة، فتح الملفات، التسجيل الصوتي، الخطوط، التوقيت، Supabase، وغيرها.
- **go_router يبقى 17.5** (من 14.8): نسخة 18 تستعمل حزمة `material_ui` المنفصلة، فما تتعرف على تطبيقنا (مبني على Material المدمجة بـ Flutter)
  وتفتح الصفحات بدون حركة ويوكف الرجوع بالسحب بالآيفون — فحوص الرحلات لكطتها. الانتقال لـ `material_ui` خطوة لحالها بعدين.
- **انشالت مكتبتين ما مستعملة:** `file_picker` و `audioplayers` (صوت الإشعار يشغّله النظام، ملفه باقي).
- **تعديلات الكود:** الإشعارات المحلية بأسماء المعاملات الجديدة (نفس الإشعارات ونفس الأرقام)؛ `StateProvider` من `legacy.dart` (Riverpod 3)؛
  رمز FCM يبقى بـ `getToken` (البديل FID يحتاج تغيير دالة الإرسال بالسيرفر)؛ قواعد الكتابة الجديدة (flutter_lints 6).
- **أندرويد:** compileSdk 37 (يطلبه permission_handler 13)، desugar_jdk_libs 2.1.5 (تطلبه الإشعارات المحلية)؛ targetSdk يبقى 36 والحد الأدنى أندرويد 7 مثل ما هو.
  نسخة الإصدار (release) انبنت بالحاسبة بدون أخطاء.
- **آيفون:** الحد الأدنى iOS 15 بدل 14 (Firebase يطلبه؛ أي آيفون عليه 14 يتحدث لـ 15).
- **فحوص:** مجلد مؤقت لكاش صور الخريطة بالاختبار (الخرائط 8 تخزّن الصور بالموبايل)؛ كل الفحوص (737) تنجح بتوقيت بغداد وطوكيو ولوس أنجلوس
  ولقطات الشاشات ما تغيّرت.

## Step 85 — إصلاح: نسخة الإصدار تطلّع من الحساب كل ما يتسكر التطبيق، والموقع بالخلفية ما يشتغل
- **السبب (لكطناه على محاكي أندرويد):** `shared_preferences_android` 2.5 صارت تشتغل بـ JNI وتدوّر على دوال Kotlin بأسمائها الكاملة؛
  تصغير كود الإصدار (R8) غيّر اسم `kotlin.coroutines.Continuation` فصار `NoSuchMethodError`. Supabase ما يكدر يحفظ الجلسة
  (يطلع من الحساب كل ما يتسكر التطبيق)، وخدمة الموقع بالخلفية تفشل بنفس الخطأ وتوقف تدفق الموقع. نسخة التجربة (debug) ما بيها المشكلة.
- **الإصلاح:** `android/app/proguard-rules.pro` يحافظ على أسماء أنواع Kotlin اللي تنذكر بتواقيع دوال JNI. على المحاكي: صفر أخطاء.
- **حماية:** خطوة بالفحص التلقائي (`build_android.yml`) تفتح نسخة الإصدار المبنية وتتأكد إن الأسماء باقية (جربتها: تفشل على النسخة القديمة وتنجح على الجديدة).

## Step 86 — تدقيق 14/10 المرحلة 10 الجزء الأول (CODE-002): ملف أساس واحد بدل 95 ملف
- **قرار صاحب الشركة 17/10/2026:** موافقة على الخطة (الجزء الأول هسه، الثاني بعد ما الموبايلات تتحدث، الثالث بعدين).
- **ملف الأساس** `supabase/migrations/20261025000000_create_baseline_schema.sql` (14955 سطر بدل 22444): مولّد بـ `supabase/schema/baseline.mjs`
  (PGlite + pg_dump) من الملفات القديمة، ومعه اللي برا الجزء الرئيسي: الإضافات، 5 مخازن ملفات و24 صلاحية تخزين، 5 جداول تحديث مباشر، 7 مهام مجدولة.
  يبدي بقفل (قاعدة موجودة = يوكف؛ جربته على السيرفر الحي بمعاملة تتراجع: وكف). القيم اللي تعتمد على يوم البناء تنحسب وقت التشغيل مثل قبل.
- **الصلاحيات:** pg_dump يضيف صلاحيات بس وما يشيل افتراضي Supabase، فكانت دوال كثيرة راح تطلع مفتوحة لأي أحد بقاعدة جديدة.
  المقارنة لكطتها؛ الملف يوكف الصلاحيات الافتراضية أثناء البناء ويرجع القواعد الأخيرة بالنهاية.
- **المقارنة** (`snapshot.sql`): قاعدة من ملف الأساس = قاعدة من الـ 95 ملف بـ 3469 عنصر (جداول، أعمدة، قيود، فهارس، دوال وصلاحياتها،
  triggers، سياسات، views، تسلسلات، تعليقات، تخزين، تحديث مباشر، مهام) + البيانات. كل فحوص القاعدة (954) تنجح على ملف الأساس لحاله.
  `current_functions.sql` ما تغيّر ولا حرف. فحص تلقائي جديد: `node supabase/schema/baseline.mjs --check`.
- **ضد القاعدة الحية** (`--live`، قراءة بس): غير أشياء منصة Supabase، 6 اختلافات قديمة بين الحية والملفات القديمة نفسها
  (من أيار وحزيران: أشياء انعملت من لوحة Supabase) — ما انلمست هنا.
- **بيئة الفحص** مثل Supabase: `uuid-ossp` بـ extensions وترتيب البحث `"$user", public, extensions`؛ المهام المجدولة تنحفظ حتى تنقارن.
- **الأرشيف** `supabase/migrations_archive` (95 ملف + README + نسخة سجل السيرفر الحي `LIVE_HISTORY_2026-10-17.md`).
- **على السيرفر:** تسجيل بس (`migration repair`)، بدون أي تغيير بالبيانات.

## Step 87 — تدقيق 14/10 المرحلة 10 الجزء الثاني: الملفات = السيرفر الحي، وحذف الجداول الميتة
- **قرار صاحب الشركة 17/10/2026:** «ابدي بالجزء الثاني»، و«إي، ضيفها» للاختلافات الستة.
- `20261026000000_fix_schema_match_live.sql`: 6 اختلافات قديمة بين السيرفر الحي والملفات (من أيار وحزيران، أشياء انعملت من اللوحة)،
  والملفات تمشي على الحية: تاريخ المباشرة بدون قيمة افتراضية، حالة منطقة السياج تقبل الفارغ، القسط افتراضياً خصم من الراتب،
  وصف دليل الموظفين، رفع صورة التعهد لمجلد الموظف، ومخزن `employee-documents`. على الحية ما يتغير شي غير الوصف.
- `20261026000100_drop_unused_tracking_and_device_tokens.sql`: حذف `tracking_schedules` و`employee_geofence_assignments` (فارغة؛ محمي: إذا بيها
  بيانات يوكف) و`device_tokens` (رموزه تنتقل لـ `fcm_tokens` قبل الحذف)، و`_anonymize_employee` بدون الجدول المحذوف.
- **الموقع والتطبيق ما يقرون `employees.fcm_token`** (العمود يبقى مسموح للنسخة الحالية من التطبيق لحد الجزء الثالث؛ فحص الأعمدة يعرف هذا).
  صفحة التخزين بالموقع ما تعرض الجداول المحذوفة.
- **فحوص:** `test_stage10_cleanup.mjs` (12 فحص)؛ كل فحوص القاعدة تنجح؛ الموقع (155 + 39 بالمتصفح)؛ التطبيق (737).
- **على السيرفر الحي (تجربة تتراجع):** الجداول تنحذف، الرمز القديم ينتقل (1 ← 2 رمز)، الموظفين نفسهم؛ وبعد التراجع ما تغير شي.
  المقارنة (`baseline.mjs --live`) تبين بالضبط هالتغييرات + أشياء منصة Supabase بس.
- **الشرط:** كل الموبايلات على نسخة المرحلة 9 أو أحدث قبل تحديث القاعدة (النسخ الأقدم تقرا الجداول المحذوفة).

## Step 88 — تدقيق 14/10 المرحلة 10 الجزء الثالث: حذف عمود رمز الإشعارات القديم
- **قرار صاحب الشركة 17/10/2026:** كل الموبايلات على النسخة الأخيرة (المشروع بعده بمرحلة البناء، والمستخدم الوحيد حساب أحمد).
- **قبلها (تحقق على السيرفر الحي بعد تحديث الجزء الثاني):** سجل التحديثات 3 ملفات، 42 جدول، الرمز انتقل، والمقارنة الكاملة صفر اختلاف
  غير أشياء منصة Supabase. النسخة الجديدة من التطبيق بصمت وبعثت نقاط موقع، ورمز الإشعارات تجدد.
- `20261027000000_drop_employees_legacy_fcm_token.sql`: أي رمز باقي بـ `employees.fcm_token` ينتقل لـ `fcm_tokens`، وبعدها ينحذف العمود
  والـ trigger ودالة `copy_legacy_push_token`. ينعاد بأمان.
- **فحوص:** `test_stage10_cleanup.mjs` (14)، فحص الأعمدة بدون استثناء، كل فحوص القاعدة؛ تجربة على الحية تتراجع: العمود والـ trigger والدالة
  انحذفوا، الرموز نفسها (2)، دليل الموظفين يشتغل؛ والمقارنة تبين هالأربعة بس.
- **صغيرة:** اسم خطوة Node بالفحص التلقائي (`build_web.yml`) صار 24؛ تعليق `push-notification` (بدون حاجة لنشرها من جديد).

## Step 89 — أدوات بناء الأندرويد الجديدة (من البواقي بعد المرحلة 10)
- **قرار صاحب الشركة 18/10/2026:** البواقي وحدة وحدة، والأولى أدوات بناء الأندرويد.
- **النسخ (نفس قالب Flutter 3.47):** AGP 8.11.1 ← 9.1.0، Gradle 8.14 ← 9.3.1، Kotlin 2.2.20 ← 2.4.0.
- **إعدادات Kotlin بالطريقة الجديدة** (`kotlin { compilerOptions }` بدل `kotlinOptions`)؛ `compileSdk` بالطريقة الجديدة لأن منصة
  أندرويد 37 مسجّلة بالرقم الجديد (37.0). إعدادا التوافق (`android.builtInKotlin=false`، `android.newDsl=false`) يبقون: مكتبتين
  (firebase_core و flutter_image_compress_common) بعدهن يستعملن الطريقة القديمة، وهذا اللي ينصح بيه Flutter لحد ما يتحدثن.
- **فحوص:** نسخة التجربة والنسخة النهائية انبنن؛ فحص أسماء JNI بالنسخة النهائية نجح؛ النسخة النهائية على المحاكي: صفر أخطاء وشاشة الدخول سليمة.
  ما تغير شي بكود التطبيق ولا بالآيفون ولا بالموقع.
