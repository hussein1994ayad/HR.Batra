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
  تدفق الموقع، كشف الموقع الوهمي، البطارية). نفس الدوال العامة ونفس `@pragma(\'vm:entry-point\')`.
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
