# دليل المطور — HR Pro v6.0
### نظام إدارة الموارد البشرية للشركات متعددة الفروع

---

## 📋 جدول المحتويات

1. [نظرة عامة على المشروع](#نظرة-عامة)
2. [هيكل المشروع](#هيكل-المشروع)
3. [المكتبات والتقنيات](#المكتبات-والتقنيات)
4. [قاعدة البيانات (Supabase)](#قاعدة-البيانات)
5. [الخدمات الأساسية (Services)](#الخدمات-الأساسية)
6. [شاشات التطبيق](#شاشات-التطبيق)
7. [كيفية إضافة ميزة جديدة](#كيفية-إضافة-ميزة-جديدة)
8. [كيفية بناء الـ APK](#كيفية-بناء-الـ-apk)

---

## نظرة عامة

**HR Pro** تطبيق موبايل (Flutter) لإدارة الموارد البشرية في شركة متعددة الفروع.
يعمل على Android وiOS ويتصل بـ Supabase (قاعدة بيانات في السحابة).

### الفروع:
- القناة
- العكد
- كمب سارة
- بغداد الجديدة

### صلاحيات المستخدمين:
| الصلاحية | الوصول |
|-----------|--------|
| `employee` | شاشاته الخاصة فقط (دوام، إجازات، سلف، إشعارات) |
| `admin` | إدارة موظفي فرعه + لوحة الأدمن |
| `superadmin` | صلاحيات كاملة على كل الفروع |

---

## هيكل المشروع

```
HR.Batra/
├── mobile/                          ← تطبيق Flutter (Android + iOS)
│   ├── lib/
│   │   ├── main.dart                ← نقطة دخول التطبيق
│   │   ├── firebase_options.dart    ← إعدادات Firebase (توليد تلقائي)
│   │   │
│   │   ├── core/                    ← المنطق المشترك (لا شاشات هنا)
│   │   │   ├── constants/constants.dart   ← ثوابت وروابط وقيم افتراضية
│   │   │   ├── design/              ← الألوان والمسافات والخطوط + Fmt (تنسيق التاريخ والمبالغ)
│   │   │   ├── theme/app_theme.dart ← ثيم التطبيق (داكن فقط)
│   │   │   ├── logic/               ← قواعد عمل بدون واجهة وقابلة للاختبار
│   │   │   │   ├── attendance_rules.dart, attendance_report.dart, loan_rules.dart
│   │   │   │   └── tracking_rules.dart, reminder_plan.dart
│   │   │   ├── models/              ← نماذج البيانات + models.dart (استيراد مركزي): الإجازة، السلفة، الكشف، الإشعار،
│   │   │   │                          التعميم والمجازون، الدليل، الفرع وجدوله، الموظف، السلة... (fromMap يطابق ما تعرضه الشاشة)
│   │   │   ├── providers/           ← Riverpod: app_container.dart، auth_provider.dart
│   │   │   ├── routes/app_router.dart     ← كل مسارات التنقل (GoRouter)
│   │   │   ├── services/            ← الخدمات (بنية تحتية، مو شاشات)
│   │   │   │   ├── supabase_service.dart, auth_service.dart, device_service.dart
│   │   │   │   ├── attendance_sync_service.dart ← البصمة + طابورها بدون إنترنت
│   │   │   │   ├── location_service.dart        ← تشغيل/إيقاف التتبع والخدمة الخلفية
│   │   │   │   ├── location/                    ← أجزاء التتبع:
│   │   │   │   │   ├── offline_json_queue.dart  ← طابور محلي واحد لكل الأنواع
│   │   │   │   │   ├── geofence_monitor.dart, branch_presence_monitor.dart
│   │   │   │   │   └── tracking_schedule.dart, location_uploader.dart
│   │   │   │   ├── notification_service.dart, schedule_service.dart, ios_region_monitor.dart
│   │   │   │   ├── file_upload_service.dart, image_compression_service.dart, storage_links.dart
│   │   │   │   ├── excel_export_service.dart + excel/ ← كشف السلفة وتقرير الحضور
│   │   │   │   └── pdf_export_service.dart, ota_service.dart, share_helper.dart
│   │   │   └── utils/               ← app_log.dart (السجلات)، arabic_format.dart (البحث العربي)،
│   │   │                              error_text.dart، input_formatters.dart، json_map.dart
│   │   │
│   │   ├── data/
│   │   │   └── repositories/        ← كل استعلامات Supabase للشاشات (الشاشات ما تكلم القاعدة مباشرة)
│   │   │       ├── home_ / attendance_ / leave_ / loan_ / payslips_ / profile_repository.dart
│   │   │       ├── notification_ / directory_ / announcement_repository.dart
│   │   │       ├── admin_dashboard_ / admin_actions_ / employee_admin_ / branch_repository.dart
│   │   │       ├── attendance_report_ / live_tracking_ / storage_repository.dart
│   │   │       └── role_repository.dart ← دور المستخدم (حماية شاشات الإدارة)
│   │   │
│   │   └── presentation/            ← الواجهة: مجلد لكل شاشة = <screen>_screen.dart + widgets/ + <x>_logic.dart
│   │       ├── auth/                ← تسجيل الدخول وتغيير كلمة السر
│   │       ├── employee/            ← شاشات الموظف
│   │       │   ├── main_layout.dart ← الهيكل العام (شريط التبويب السفلي)
│   │       │   ├── home/            ← الرئيسية
│   │       │   ├── attendance/      ← البصمة + سجل الدوام
│   │       │   ├── leave/           ← الإجازات
│   │       │   ├── loan/            ← طلب السلفة
│   │       │   ├── payslips/        ← كشوف الرواتب
│   │       │   ├── notifications/   ← الإشعارات
│   │       │   ├── directory/       ← دليل الموظفين
│   │       │   ├── announcements/   ← لوحة التعاميم
│   │       │   └── settings/        ← الإعدادات والملف الشخصي
│   │       ├── admin/               ← شاشات الإدارة
│   │       │   ├── admin_dashboard/ ← لوحة الإدارة (قرارات، إجازات، سلف، أجهزة، أمان)
│   │       │   ├── admin_loans/     ← سلف الموظفين
│   │       │   ├── employee_management/ ← الموظفون + الوثائق + نموذج الإضافة
│   │       │   ├── branches/        ← الأفرع ومواقعها وأوقات دوامها
│   │       │   ├── attendance_report/ ← تقرير الحضور اليومي
│   │       │   ├── live_tracking/   ← التتبع الحي
│   │       │   ├── announcements/   ← نشر تعميم
│   │       │   └── storage/         ← سلة المحذوفات وإحصائيات التخزين
│   │       └── shared/
│   │           ├── ui/              ← مكتبة المكوّنات الموحّدة (ui.dart) — التفاصيل بـ mobile/DESIGN.md
│   │           └── widgets/         ← bottom_nav_bar، offline_banner، info_row
│   │
│   ├── test/                        ← اختبارات الوحدة والشاشات (flutter test)
│   │   └── goldens/text/            ← لقطات نصية لكل شاشة: أي تغيير بالعرض يُفشل الاختبار
│   ├── integration_test/            ← اختبارات على المحاكي (iOS CI)
│   ├── assets/                      ← google_fonts (Cairo)، fonts، images، sounds
│   └── pubspec.yaml
│
├── web/                             ← لوحة الإدارة (Next.js، تصدير ثابت)
│   └── src/
│       ├── app/dashboard/<page>/page.tsx ← الصفحات: تركيب فقط
│       ├── features/<x>/            ← api.ts (Supabase) + logic.ts (منطق نقي) + types.ts + useX.ts + components/
│       │                              (overview, shell, auth, employees, payroll, loans, leaves, tracking, settings, storage, geofences)
│       ├── components/ui/           ← مكوّنات الواجهة المشتركة
│       └── lib/                     ← db-types.ts، dates.ts، schedules.ts، supabase.ts …
│
├── supabase/
│   ├── migrations/                  ← لا تعدّل ملف مطبّق أبداً؛ أضف ملف جديد
│   ├── schema/current_functions.sql ← النسخة الحالية من كل دالة و trigger (للقراءة؛ أعد توليدها: node supabase/schema/generate.mjs)
│   ├── functions/                   ← Edge Functions: push-notification، daily-cleanup
│   └── tests/                       ← اختبارات قاعدة البيانات (PGlite: npm test)
│
├── BUSINESS_RULES.md                ← قواعد العمل ومصادرها
├── CHANGES.md                       ← سجل خطوات إعادة التنظيم
├── BUILD_APK.bat                    ← بناء الـ APK على Windows
└── DEVELOPER_GUIDE.md               ← هذا الملف 😊
```

---

## المكتبات والتقنيات

| المكتبة | الاستخدام |
|---------|-----------|
| `supabase_flutter` | قاعدة البيانات والمصادقة والـ Realtime |
| `flutter_riverpod` | إدارة الحالة (State Management) |
| `go_router` | التنقل بين الشاشات |
| `flutter_map` + `latlong2` | خرائط OpenStreetMap |
| `geolocator` | GPS وتحديد الموقع |
| `flutter_background_service` | تشغيل التتبع في الخلفية |
| `firebase_messaging` | إشعارات Push عبر Firebase |
| `flutter_local_notifications` | إشعارات محلية |
| `syncfusion_flutter_pdf` | تصدير PDF |
| `syncfusion_flutter_xlsio` | تصدير Excel |
| `image_picker` + `flutter_image_compress` | اختيار وضغط الصور |
| `shared_preferences` | تخزين محلي بسيط |
| `device_info_plus` | معرف الجهاز (لقفل الجهاز الواحد) |
| `dio` | طلبات HTTP متقدمة |
| `permission_handler` | إدارة صلاحيات iOS/Android |

---

## قاعدة البيانات

### جدول الموظفين: `employees`

```sql
id              UUID  PRIMARY KEY  -- معرف فريد، مرتبط بـ auth.users
full_name       TEXT               -- الاسم الكامل
email           TEXT  UNIQUE       -- البريد (لتسجيل الدخول)
phone           TEXT               -- رقم الهاتف
role            TEXT               -- 'employee' | 'admin' | 'superadmin'
department      TEXT               -- القسم (مثال: المحاسبة)
branch_id       UUID  FK(branches) -- الفرع التابع له
avatar_url      TEXT               -- رابط صورة الملف الشخصي
salary          NUMERIC            -- الراتب الشهري (دينار عراقي)
hire_date       DATE               -- تاريخ التعيين
is_active       BOOL  DEFAULT true -- الحساب مفعّل؟
device_id       TEXT               -- معرف جهاز الموظف (قفل الجهاز الواحد)
must_change_password BOOL          -- تغيير كلمة المرور المؤقتة
national_id     TEXT               -- رقم الهوية الوطنية
```

### جدول الدوام: `attendance`

```sql
id              UUID  PRIMARY KEY
employee_id     UUID  FK(employees)
branch_id       UUID  FK(branches)
work_date       DATE               -- تاريخ اليوم (YYYY-MM-DD)
check_in_time   TIMESTAMPTZ        -- وقت الحضور
check_out_time  TIMESTAMPTZ        -- وقت الانصراف (null = لم ينصرف بعد)
check_in_lat    FLOAT8             -- موقع بصمة الحضور
check_in_lng    FLOAT8
check_out_lat   FLOAT8             -- موقع بصمة الانصراف
check_out_lng   FLOAT8
status          TEXT               -- 'present'|'late'|'absent'|'half_day'
is_late         BOOL
late_minutes    INT                -- عدد دقائق التأخير
```

### جدول الفروع: `branches`

```sql
id         UUID  PRIMARY KEY
name       TEXT               -- اسم الفرع
latitude   FLOAT8             -- موقع GPS للفرع
longitude  FLOAT8
radius     FLOAT8             -- نصف قطر السياج الجغرافي (أمتار)
address    TEXT               -- العنوان النصي
is_active  BOOL
```

### جدول طلبات الإجازة: `leave_requests`

```sql
id           UUID  PRIMARY KEY
employee_id  UUID  FK(employees)
leave_type   TEXT  -- 'annual'|'sick'|'emergency'|'unpaid'|'maternity'
start_date   DATE
end_date     DATE
reason       TEXT  -- سبب الإجازة
status       TEXT  -- 'pending'|'approved'|'rejected'
admin_notes  TEXT  -- ملاحظات المدير
approved_by  UUID  FK(employees)
```

### جدول السلف: `loans`

```sql
id             UUID  PRIMARY KEY
employee_id    UUID  FK(employees)
amount         NUMERIC            -- مبلغ السلفة
reason         TEXT
status         TEXT  -- 'pending'|'approved'|'rejected'|'paid'
monthly_deduct NUMERIC            -- الاستقطاع الشهري
months         INT                -- عدد أشهر الاسترداد
paid_months    INT   DEFAULT 0    -- الأشهر المدفوعة
```

### جدول تتبع الموقع: `location_tracking`

```sql
id          UUID  PRIMARY KEY
employee_id UUID  FK(employees)
latitude    FLOAT8
longitude   FLOAT8
accuracy    FLOAT8             -- دقة GPS (أمتار)
timestamp   TIMESTAMPTZ        -- وقت التسجيل
is_online   BOOL               -- كان متصلاً أم رُفع لاحقاً؟
```

### جدول مخالفات السياج الجغرافي: `geofence_violations`

```sql
id             UUID  PRIMARY KEY
employee_id    UUID  FK(employees)
zone_id        UUID  FK(geofence_zones)
violation_type TEXT  -- 'entry'|'exit'
timestamp      TIMESTAMPTZ
```
> **ملاحظة:** هذا الجدول للأدمن فقط — الموظف لا يتلقى إشعاراً عن مخالفات السياج.

---

## الخدمات الأساسية

### 1. `SupabaseService` — الاتصال بقاعدة البيانات
```dart
// الاتصال بقاعدة البيانات
SupabaseService.client.from('جدول').select()...

// المستخدم الحالي
SupabaseService.currentUser

// تسجيل الخروج
await SupabaseService.signOut()
```

### 2. `AuthService` — المصادقة وإدارة الجلسة
**المسؤوليات:**
- تسجيل الدخول مع فحص `is_active` و`must_change_password`
- قفل الجهاز الواحد عبر دالة `register_device_login` في السيرفر. معرّف الجهاز ثابت
  (Android: `ANDROID_ID`، iOS: Keychain) ويبقى بعد حذف التطبيق
- فحص الجلسة عند الفتح (`resolveStartupDestination`): انتهاء 30 يوم، حساب معطّل،
  جهاز أُلغي اعتماده. بدون إنترنت يبقى المستخدم داخل

```dart
// تسجيل الدخول
await AuthService.signIn(email: email, password: password, context: context);

// تسجيل الخروج
await AuthService.signOut(context: context);
```

**الاستثناءات المحتملة:**
- `InactiveAccountException` — الحساب موقوف
- `DeviceLockedException` — الدخول من جهاز آخر غير مسجّل
- `MustChangePasswordException` — كلمة المرور المؤقتة تحتاج تغيير

### 3. `LocationService` — GPS والسياج الجغرافي
**المسؤوليات:**
- تشغيل خدمة الخلفية لتتبع موقع الموظف كل X ثانية
- رفع الموقع لجدول `location_tracking`
- **التتبع أوفلاين:** يحفظ النقاط محلياً ويرفعها لما يعود الاتصال
- السياج الجغرافي: يتحقق إذا الموظف دخل أو خرج من منطقة محددة
- تسجيل المخالفات في `geofence_violations` للأدمن (بدون إشعار للموظف)

```dart
// بدء التتبع
await LocationService.startTracking(employeeId: userId);

// إيقاف التتبع
await LocationService.stopTracking();

// حالة التتبع
bool isActive = LocationService.isTracking;
```

### 4. `NotificationService` — الإشعارات
**المسؤوليات:**
- استقبال إشعارات Firebase Cloud Messaging (FCM) حتى لو التطبيق مغلق
- إشعارات محلية (مثال: تذكير بتسجيل الانصراف)
- Realtime subscription على جدول `notifications` في Supabase

### 5. `AttendanceSyncService` — مزامنة الدوام أوفلاين
**المسؤوليات:**
- كل بصمة تمر عبر دالة `punch_attendance` في السيرفر (الوقت، المسافة، التأخير، الجهاز)
- الطابور المحلي فقط عند انقطاع الشبكة فعلياً؛ البصمة المرفوعة لاحقاً تُقبل إذا كانت
  خلال 48 ساعة وتُعلَّم `check_in_offline` / `check_out_offline` لمراجعة الإدارة
- رفض السيرفر (خارج النطاق، مكررة...) يظهر للموظف ولا يُعاد إرساله

### 6. `OtaService` — تحديثات التطبيق التلقائية
- يتحقق من وجود نسخة جديدة في جدول `app_versions` بـ Supabase
- Android: `apk_url` يجب أن يكون رابط عام من bucket `ota-updates` في نفس مشروع Supabase
  (غير ذلك يُتجاهل). iOS: `ipa_url` رابط App Store أو TestFlight فقط

---

## شاشات التطبيق

### شاشات الموظف العادي:

| الشاشة | الملف | الوظيفة |
|--------|-------|---------|
| الرئيسية | `home_screen.dart` | ملخص يومي: كارد الدوام، الإعلانات، الاشتراكات الفورية |
| الدوام | `attendance_screen.dart` | بصمة الحضور/الانصراف بالـ GPS + خريطة |
| الإجازات | `leave_request_screen.dart` | تقديم وتتبع طلبات الإجازة |
| السلف | `loan_request_screen.dart` | تقديم وتتبع طلبات السلفة |
| الرواتب | `payslips_screen.dart` | عرض كشوف الرواتب وتحميلها PDF |
| الإشعارات | `notifications_screen.dart` | قائمة الإشعارات مع تعليم كمقروءة |
| الإعدادات | `settings_screen.dart` | تعديل الملف الشخصي وتغيير كلمة المرور |
| الدليل | `directory_screen.dart` | بحث في قائمة الموظفين |

### شاشات الأدمن:

| الشاشة | الملف | الوظيفة |
|--------|-------|---------|
| لوحة التحكم | `admin_dashboard_screen.dart` | إحصاءات شاملة + موافقات سريعة |
| التتبع المباشر | `admin_live_tracking_screen.dart` | خريطة فورية لمواقع الموظفين |
| إدارة الموظفين | `employee_management_screen.dart` | إضافة/تعديل/تعطيل الموظفين |
| إدارة الفروع | `branch_management_screen.dart` | إضافة/تعديل الفروع والسياج الجغرافي |
| تقارير الدوام | `attendance_report_screen.dart` | تصدير تقارير الدوام Excel/PDF |
| إدارة السلف | `admin_loans/admin_loans_screen.dart` | قبول/رفض طلبات السلفة وإدارة الأقساط |
| جداول الدوام | `branch_schedule_screen.dart` | ضبط أوقات الدوام لكل فرع |
| الإعلانات | `announcement_screen.dart` | نشر إعلانات للموظفين |

---

## كيفية إضافة ميزة جديدة

### مثال: إضافة شاشة "طلب معدات"

**الخطوة 1:** أنشئ جدول في Supabase
```sql
CREATE TABLE equipment_requests (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  employee_id UUID REFERENCES employees(id),
  item_name   TEXT NOT NULL,
  reason      TEXT,
  status      TEXT DEFAULT 'pending',
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

**الخطوة 2:** أنشئ ملف النموذج
في `lib/core/models/equipment_request_model.dart`:
```dart
class EquipmentRequestModel {
  final String id;
  final String employeeId;
  final String itemName;
  final String? reason;
  final String status;
  // ... الباقي نفس النمط
  factory EquipmentRequestModel.fromMap(Map<String, dynamic> map) { ... }
}
```

**الخطوة 3:** أضف التصدير في `lib/core/models/models.dart`
```dart
export 'equipment_request_model.dart';
```

**الخطوة 4:** أنشئ المستودع والشاشة
- الاستعلامات في `lib/data/repositories/equipment_repository.dart` (نفس نمط `LeaveRepository`).
- الشاشة في `lib/presentation/employee/equipment/equipment_request_screen.dart`، والأجزاء في `widgets/`،
  وأي حساب بدون واجهة في `equipment_logic.dart` مع اختبار بـ `test/unit/`.

**الخطوة 5:** أضف المسار في `lib/core/routes/app_router.dart`
```dart
static const String employeeEquipment = '/employee/equipment';
// وفي قائمة المسارات:
GoRoute(path: AppRoutes.employeeEquipment, builder: (_, __) => const EquipmentRequestScreen()),
```

**الخطوة 6:** أضف زر في `main_layout.dart` أو `home_screen.dart`

---

## كيفية بناء الـ APK

1. افتح مجلد المشروع: `C:\Users\HP\Desktop\HR.Batra\`
2. دبل كليك على **`BUILD_APK.bat`**
3. انتظر 3-6 دقائق
4. الملفات الناتجة:
   - `HR_Batra_arm64.apk` — للهواتف الحديثة (أفضل للتوزيع)
   - `HR_Batra_universal.apk` — يعمل على كل الأجهزة (أكبر حجماً)

### عند الخطأ:
- `Can't find ']' to match '['` → خلل في أقواس Dart، راجع الملف المذكور في الخطأ
- `Gradle build failed` → حاول `flutter clean` ثم أعد البناء
- تحذير `key.properties غير موجود` → النسخة موقّعة بمفتاح debug؛ لا توزعها (انظر قسم النشر)

---

## نشر تحديث التدقيق (سبتمبر 2026)

الترتيب مهم: قاعدة البيانات أولاً، ثم الويب، ثم التطبيق.

### 1) قاعدة البيانات
```bash
supabase migration list          # تأكد أي migrations مطبّقة فعلاً على المشروع
cd supabase/tests && npm ci && npm test   # يجب أن تنجح كلها
cd ../.. && supabase db push
```
- إذا طبّقت migrations سابقاً يدوياً من SQL Editor ولم تُسجَّل، سجّلها أولاً بـ
  `supabase migration repair --status applied <version>` حتى لا يُعاد تشغيلها.
- بعد التطبيق شغّل `supabase/checks/security_audit.sql` من SQL Editor —
  الاستعلامات 1–5 يجب أن ترجع صفر نتائج.
- دالة push-notification: `supabase functions deploy push-notification`، ويُفضَّل ضبط
  `WEBHOOK_SECRET` في أسرار الدالة وإرسال نفس القيمة بترويسة `x-webhook-secret` في الـ Webhook.

### 2) الويب
`cd web && npm ci && npm run build` ثم ارفع `web/out/`.

### 3) التطبيق
- **مفتاح التوقيع (Android):** أنشئه مرة واحدة واحفظه بمكان آمن (ضياعه = لا تحديثات بعد الآن):
  ```bash
  keytool -genkey -v -keystore mobile/android/app/release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias batra
  ```
  وأنشئ `mobile/android/key.properties` (خارج git):
  ```
  storeFile=release.jks
  storePassword=...
  keyAlias=batra
  keyPassword=...
  ```
  للـ CI ضع نفس القيم في Secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- **أول نسخة بالمفتاح الجديد تتطلب حذف التطبيق القديم وتثبيت الجديد** (اختلاف التوقيع)،
  وهذا يغيّر معرّف الجهاز. قبل توزيعها أعد ضبط قفل الأجهزة مرة واحدة:
  ```sql
  UPDATE employees SET device_id_lock = 'force_lock_active'
  WHERE COALESCE(device_id_lock, '') <> '';
  ```
  أول دخول لكل موظف بعدها يعتمد جهازه تلقائياً.
- **iOS:** أضف تطبيق iOS في Firebase (Bundle ID `com.batra.hrpro.hrPro`) وضع في Secrets:
  `IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64`, `FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_API_KEY`،
  ومفاتيح التوقيع `IOS_CERTIFICATE_P12_BASE64`, `IOS_CERTIFICATE_PASSWORD`,
  `IOS_PROVISIONING_PROFILE_BASE64` (مع Push Notifications و Time Sensitive), `IOS_TEAM_ID`.
  وارفع مفتاح APNs (.p8) في Firebase → Cloud Messaging.

### فحوصات قبل أي دمج
```bash
cd mobile && dart analyze && flutter test
cd web && npm run lint && npx tsc --noEmit
cd supabase/tests && npm test
```
نفسها تعمل تلقائياً في `.github/workflows/quality.yml`.

---

## المساعد الذكي (Edge Function `hr-assistant`)
- الملفات: `supabase/functions/hr-assistant/` — `index.ts` (HTTP + التحقق من الأدمن)، `agent.ts` (الحلقة)، `tools.ts` (الأدوات)،
  `excel.ts` (ملفات Excel)، `gemini.ts` (المزوّد)، `prompt.ts` (التعليمات). الشاشات: `mobile/lib/presentation/admin/assistant/`
  و`web/src/features/assistant/`.
- التفعيل (مرة وحدة): مفتاح مجاني من https://aistudio.google.com/apikey ثم
  `npx.cmd supabase secrets set GEMINI_API_KEY=...` و `npx.cmd supabase functions deploy hr-assistant`. موديل ثاني: `GEMINI_MODEL`.
- الفحص: `npx deno test --allow-env --allow-read --allow-net=registry.npmjs.org,jsr.io supabase/functions/hr-assistant/`.

## ملاحظات مهمة للمطور

### التصميم: داكن فقط، ومن نظام التصميم فقط
التطبيق بالوضع الداكن فقط. لا تكتب ألواناً أو أحجاماً مباشرة في الشاشات — استعمل رموز التصميم
ومكوّنات الواجهة (التفاصيل والأمثلة في `mobile/DESIGN.md`):
```dart
import '../shared/ui/ui.dart';
// ثم:
color: AppColors.brand     // لون الهوية
color: AppColors.success   // نجاح / حاضر
color: AppColors.danger    // خطأ / غائب
AppCard(child: ...), AppButton(label: ..., onPressed: ...), AppSnack.success(context, '...')
```
قبل الدمج: `flutter analyze` بدون أي ملاحظة، و `flutter test` (يشمل فحص كل الشاشات على كل
المقاسات: `test/screens/responsive_test.dart`).

### تتبع الموقع: مُعلَن للموظف
التتبع يعمل أثناء ساعات الدوام فقط ولأغراض الحضور، وهو مذكور للموظف في شاشة البصمة وفي سياسة
الخصوصية (`web/src/app/privacy/page.tsx`، ورابطها في إعدادات التطبيق). أنظمة Android و iOS تُظهر
مؤشر استعمال الموقع في الخلفية — لا تحاول إخفاءه، فهذا مخالف لسياسات Apple و Google وقد يمنع
نشر التطبيق. مخالفات السياج الجغرافي تُكتب في `geofence_violations` للإدارة.

### التوزيع
التطبيق للتوزيع الخاص (Ad Hoc) فقط — **ليس في متجر Google Play أو App Store**.

---

*آخر تحديث: أيلول 2026 — HR Pro 2.0.0 (التصميم الجديد)*

---

## حماية العرض عند إعادة التنظيم (لقطات نصية)

`mobile/test/screens/text_snapshot_test.dart` يشغّل كل الشاشات (وبعض التبويبات والنوافذ) على الخادم الوهمي ويقارن **كل نص ظاهر**
بملفات `mobile/test/goldens/text/`. أي تغيير بالعرض — حتى حرف — يُفشل الاختبار. الأرقام تُكتب `#` حتى ما تتأثر بالساعة.

- تغيير غير مقصود؟ صلّح الكود.
- تغيير مقصود بالواجهة؟ حدّث اللقطات:
  `flutter test test/screens/text_snapshot_test.dart --dart-define=UPDATE_TEXT=true`
