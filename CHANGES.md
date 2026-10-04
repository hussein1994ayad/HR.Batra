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
