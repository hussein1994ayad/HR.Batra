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
├── mobile/                        ← مجلد Flutter الرئيسي
│   ├── lib/
│   │   ├── main.dart              ← نقطة دخول التطبيق
│   │   ├── firebase_options.dart  ← إعدادات Firebase (توليد تلقائي)
│   │   │
│   │   ├── core/                  ← المنطق المشترك (لا شاشات هنا)
│   │   │   ├── constants/
│   │   │   │   └── constants.dart         ← ثوابت: URL، مفاتيح API، قيم افتراضية
│   │   │   │
│   │   │   ├── models/            ← نماذج البيانات (Data Models)
│   │   │   │   ├── models.dart            ← استيراد مركزي (استخدم هذا فقط)
│   │   │   │   ├── employee_model.dart    ← بيانات الموظف
│   │   │   │   ├── attendance_model.dart  ← سجلات الدوام
│   │   │   │   ├── branch_model.dart      ← بيانات الفرع
│   │   │   │   ├── leave_request_model.dart ← طلبات الإجازة
│   │   │   │   ├── loan_model.dart        ← طلبات السلفة
│   │   │   │   └── notification_model.dart ← الإشعارات
│   │   │   │
│   │   │   ├── utils/             ← أدوات مساعدة
│   │   │   │   ├── utils.dart             ← استيراد مركزي
│   │   │   │   ├── date_utils.dart        ← تنسيق التواريخ والأوقات
│   │   │   │   └── app_utils.dart         ← SnackBars، dialogs، formatters
│   │   │   │
│   │   │   ├── providers/         ← إدارة الحالة (Riverpod)
│   │   │   │   ├── app_container.dart     ← يربط Riverpod بالخدمات
│   │   │   │   └── auth_provider.dart     ← حالة تسجيل الدخول
│   │   │   │
│   │   │   ├── routes/
│   │   │   │   └── app_router.dart        ← كل مسارات التنقل (GoRouter)
│   │   │   │
│   │   │   ├── services/          ← الخدمات الخلفية
│   │   │   │   ├── supabase_service.dart      ← الاتصال بقاعدة البيانات
│   │   │   │   ├── auth_service.dart          ← تسجيل الدخول والخروج
│   │   │   │   ├── location_service.dart      ← GPS والسياج الجغرافي
│   │   │   │   ├── notification_service.dart  ← الإشعارات (Firebase + Local)
│   │   │   │   ├── attendance_sync_service.dart ← مزامنة الدوام أوفلاين
│   │   │   │   ├── device_service.dart        ← معرف الجهاز (قفل الجهاز الواحد)
│   │   │   │   ├── ota_service.dart           ← تحديثات تلقائية للتطبيق
│   │   │   │   ├── pdf_export_service.dart    ← تصدير تقارير PDF
│   │   │   │   ├── excel_export_service.dart  ← تصدير بيانات Excel
│   │   │   │   ├── file_upload_service.dart   ← رفع الصور والملفات
│   │   │   │   ├── image_compression_service.dart ← ضغط الصور قبل الرفع
│   │   │   │   └── ios_region_monitor.dart    ← السياج الجغرافي لـ iOS
│   │   │   │
│   │   │   └── theme/
│   │   │       └── app_theme.dart             ← الألوان والخطوط والستايل
│   │   │
│   │   └── presentation/          ← الشاشات وعناصر الواجهة
│   │       ├── auth/              ← شاشات المصادقة
│   │       │   ├── login_screen.dart
│   │       │   └── change_password_screen.dart
│   │       │
│   │       ├── employee/          ← شاشات الموظف والأدمن
│   │       │   ├── main_layout.dart           ← الهيكل العام (شريط التبويب السفلي)
│   │       │   ├── home_screen.dart           ← الشاشة الرئيسية
│   │       │   ├── attendance_screen.dart     ← تسجيل الدوام بالـ GPS
│   │       │   ├── leave_request_screen.dart  ← طلبات الإجازة
│   │       │   ├── loan_request_screen.dart   ← طلبات السلفة
│   │       │   ├── payslips_screen.dart       ← كشوف الرواتب
│   │       │   ├── notifications_screen.dart  ← الإشعارات
│   │       │   ├── settings_screen.dart       ← الإعدادات والملف الشخصي
│   │       │   ├── directory_screen.dart      ← دليل الموظفين
│   │       │   ├── admin_dashboard_screen.dart     ← لوحة الأدمن
│   │       │   ├── admin_live_tracking_screen.dart ← التتبع المباشر للموظفين
│   │       │   ├── admin_loans_management_screen.dart ← إدارة السلف
│   │       │   ├── employee_management_screen.dart ← إدارة الموظفين
│   │       │   ├── branch_management_screen.dart   ← إدارة الفروع
│   │       │   ├── branch_schedule_screen.dart     ← جداول الدوام
│   │       │   ├── attendance_report_screen.dart   ← تقارير الدوام
│   │       │   ├── announcement_screen.dart        ← الإعلانات
│   │       │   ├── trash_screen.dart               ← سلة المهملات
│   │       │   └── storage_stats_screen.dart       ← إحصاءات التخزين
│   │       │
│   │       └── shared/            ← عناصر مشتركة بين الشاشات
│   │           └── widgets/
│   │               ├── glass_container.dart   ← حاوية بتأثير الزجاج
│   │               ├── glass_background.dart  ← خلفية بتأثير الزجاج
│   │               ├── bottom_nav_bar.dart    ← شريط التبويب السفلي
│   │               ├── offline_banner.dart    ← شريط "أنت أوفلاين"
│   │               └── skeleton_loader.dart   ← تحميل هيكلي (Shimmer)
│   │
│   ├── assets/
│   │   ├── sounds/    ← أصوات (نغمة البصمة، إلخ)
│   │   └── fonts/     ← خط Cairo
│   │
│   ├── pubspec.yaml   ← المكتبات المستخدمة وإعدادات المشروع
│   └── BUILD_APK.bat  ← سكريبت بناء الـ APK (شغّله على Windows)
│
└── DEVELOPER_GUIDE.md ← هذا الملف 😊
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
- قفل الجهاز الواحد: يمنع الموظف من الدخول على أكثر من جهاز
- انتهاء الجلسة تلقائياً بعد فترة عدم استخدام (SessionTimeout)

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
- حفظ بصمات الحضور/الانصراف محلياً عند انقطاع الإنترنت
- رفعها تلقائياً لما يعود الاتصال

### 6. `OtaService` — تحديثات التطبيق التلقائية
- يتحقق من وجود نسخة جديدة في جدول `app_versions` بـ Supabase
- يُظهر نافذة للمستخدم ويوفر رابط التحميل

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
| إدارة السلف | `admin_loans_management_screen.dart` | قبول/رفض طلبات السلفة وإدارة الأقساط |
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

**الخطوة 4:** أنشئ الشاشة
في `lib/presentation/employee/equipment_request_screen.dart`

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

---

## ملاحظات مهمة للمطور

### نمط Dark Mode فقط
التطبيق مصمم للـ Dark Mode فقط. لا تضف ألواناً ثابتة (مثل `Colors.black`)، استخدم دائماً ألوان من `AppTheme`:
```dart
import '../../core/theme/app_theme.dart';
// ثم:
color: AppTheme.neonCyan   // أزرق فاتح
color: AppTheme.neonPink   // وردي
color: AppTheme.successGreen
color: AppTheme.dangerRed
```

### التتبع مخفي عن الموظفين
يُسمح بتتبع موقع الموظف في الخلفية لأغراض الحضور. **لا تُضف إشعارات تكشف التتبع للموظف.** مخالفات السياج الجغرافي تُكتب في `geofence_violations` للأدمن فقط.

### التوزيع
التطبيق للتوزيع الخاص (Ad Hoc) فقط — **ليس في متجر Google Play أو App Store**.

---

*آخر تحديث: سبتمبر 2026 — HR Pro v6.0*
