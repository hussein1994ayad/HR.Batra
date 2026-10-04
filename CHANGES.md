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
