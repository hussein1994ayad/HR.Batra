# HR Pro — معمارية النظام (Architecture)

هذا الملف يوثّق القرارات المعمارية الرئيسية وسياسة عمل النظام. يهدف لتمكين أي مبرمج جديد من فهم النظام والتعديل عليه خلال يوم عمل واحد.

---

## 1. نظرة عامة

```
                    ┌─────────────────────┐
                    │   Supabase (Cloud)  │
                    │  ─────────────────  │
                    │  PostgreSQL + Auth  │
                    │   + Storage + RLS   │
                    │  + Edge Functions   │
                    └──────────┬──────────┘
                               │ HTTPS + WebSocket (realtime)
              ┌────────────────┼────────────────┐
              │                                 │
        ┌─────▼──────┐                    ┌─────▼──────┐
        │   Mobile   │                    │    Web     │
        │  (Flutter) │                    │  (Next.js) │
        │  Employee  │                    │   Admin    │
        │  + Admin   │                    │            │
        └────────────┘                    └────────────┘
```

- **Mobile** — تطبيق Flutter يعمل على Android (SDK 24+) و iOS (14+). يستخدمه الموظف والأدمن.
- **Web** — لوحة إدارة Next.js 16، static-exported، تُنشر على أي CDN. للأدمن والمدراء فقط.
- **Backend** — Supabase (PostgreSQL 15). كل شي يعبر Supabase — لا خوادم Node/Python وسيطة.

---

## 2. الأدوار (Roles)

| الدور | الصلاحيات |
|---|---|
| `employee` | تسجيل حضور، تقديم إجازة، طلب سلفة، عرض راتبه، تحديث بياناته |
| `manager` | كل صلاحيات الموظف + عرض بيانات موظفي قسمه + اعتماد إجازاتهم |
| `admin` | كل شي: إدارة الموظفين، الفروع، الأقسام، الرواتب، القروض، الأمان |

الصلاحيات تُفرَض على مستويين:
1. **Client-side**: `AuthService.currentUserRole` يُستخدم لإخفاء/إظهار عناصر الواجهة
2. **Server-side (RLS)**: كل جدول عليه سياسات RLS تعتمد على `is_admin(auth.uid())` أو `is_manager(auth.uid())`

**قاعدة ذهبية**: لا تعتمد على client-side فقط. أي endpoint حساس محمي بـ RLS في قاعدة البيانات.

---

## 3. طبقات التطبيق (Mobile)

```
mobile/lib/
├── main.dart                     نقطة الدخول + تهيئة Supabase/Firebase/Location
├── firebase_options.dart         مفاتيح Firebase (Android)
├── core/
│   ├── constants/constants.dart  ثوابت + المفاتيح (مع دعم --dart-define)
│   ├── routes/app_router.dart    go_router — كل المسارات + guards
│   ├── services/                 الخدمات — طبقة Data/Domain
│   │   ├── supabase_service.dart      client + isAuthenticated
│   │   ├── auth_service.dart          signIn + device lock + session
│   │   ├── device_service.dart        UUID + model + OS
│   │   ├── location_service.dart      GPS + geofencing + background
│   │   ├── notification_service.dart  FCM + local notifications
│   │   ├── ota_service.dart           تحديثات هوائية من bucket
│   │   ├── file_upload_service.dart   رفع للـ Storage
│   │   ├── image_compression_service.dart
│   │   ├── pdf_export_service.dart    (Syncfusion)
│   │   ├── excel_export_service.dart  (Syncfusion)
│   │   └── attendance_sync_service.dart offline queue
│   └── theme/app_theme.dart      نظام تصميم موحّد + tokens
└── presentation/
    ├── auth/                     login, change_password
    ├── employee/                 كل الشاشات (15 شاشة)
    └── shared/widgets/           SkeletonLoader, OfflineBanner, BottomNav, GlassBackground
```

**Anti-pattern حالي**: كل شاشة تحوي UI + منطق أعمال + استعلامات Supabase في نفس الملف. هذا يعمل الآن لكنه يعقّد الاختبار والصيانة.

**اتجاه مستقبلي مقترح**: فصل إلى:
- `data/repositories/` — كل استعلامات Supabase
- `domain/use_cases/` — منطق الأعمال البحت
- `presentation/screens/` — UI فقط + Riverpod providers

---

## 4. قاعدة البيانات — الجداول الأساسية

```
company_settings (1 row)
   ↓
branches ────────┐
   ↓             │
departments      │
   ↓             │
employees ─┬─→ employee_devices
           │
           ├─→ attendance ──── location_tracking
           │                └─ tracked_stops
           ├─→ leave_requests, leave_balances
           ├─→ salary_slips, bonuses_deductions
           ├─→ loans → loan_installments
           ├─→ documents
           ├─→ notifications, device_tokens, fcm_tokens
           └─→ geofence_zones ← employee_geofence_assignments
                                                    └─ geofence_violations
                                                    └─ mock_gps_attempts
```

- **28 جدول** أساسي + `audit_log` للتدقيق + `archived_employees` للأرشفة
- **17 RPC** (دوال) — راجع `supabase/migrations/20260920000000_document_rpcs_and_add_audit_log.sql` لتوثيق كل دالة
- **6 Views** — تجنّب N+1 من العميل (`v_employee_directory`, `v_attendance_with_employee`, ...)
- **RLS مفعّل** على جميع الجداول — سياسات تعتمد على `is_admin()`, `is_manager()`

### قواعد أساسية للتعديل على قاعدة البيانات

1. **لا تعدّل migration سابق** — أنشئ migration جديد
2. **كل migration يجب أن يكون idempotent** (`IF NOT EXISTS`, `DROP … IF EXISTS`)
3. **تسمية**: `YYYYMMDDHHMMSS_<verb>_<scope>_<subject>.sql`
4. **تغييرات schema حساسة** يجب أن تضيف triggers audit في نفس migration

---

## 5. Storage Buckets

| Bucket | Public | حد الحجم | الاستخدام |
|---|---|---|---|
| `avatars` | ✅ | 1 MB | صور الموظفين الشخصية |
| `documents` | ❌ | 10 MB | مستندات (هوية، إقامة، عقود) |
| `employee-documents` | ❌ | 10 MB | مستندات الموظف الرسمية |
| `loan-pledges` | ✅ | 2 MB | تعهدات السلف |
| `company-logos` | ✅ | 2 MB | شعارات الشركة |
| `ota-updates` | ✅ | 100 MB | APK للتحديثات OTA |

كل bucket محمي بـ RLS.

---

## 6. Edge Functions

**`daily-cleanup`** — يُشغَّل يومياً 03:00 UTC عبر pg_cron. يستدعي `perform_daily_cleanup()` ويحذف الملفات المنتهية من Storage.

**`push-notification`** — Webhook على INSERT في `notifications`. يستخدم Firebase HTTP v1 API مع Service Account لإرسال FCM.

---

## 7. المصادقة (Auth Flow)

```
User opens app
    ↓
Splash screen → check Supabase.auth session
    ├─ authenticated + must_change_password → Change Password screen
    ├─ authenticated + valid session         → Home
    └─ not authenticated                     → Login

Login flow:
    Supabase.auth.signInWithPassword(email, password)
        ↓
    fetch employees row (id=auth.uid)
        ↓
    ┌─ is_active? ────────── no → InactiveAccountException
    ├─ device lock check ─── mismatch → DeviceLockedException
    ├─ must_change_password → MustChangePasswordException
    └─ all good → touch activity + navigate to Home
```

**قفل الجهاز**: كل موظف مربوط بجهاز واحد. أي محاولة دخول من جهاز آخر تُسجَّل في `notifications` وترمي `DeviceLockedException`. الأدمن يوافق على الجهاز الجديد من لوحة الويب.

**Session Timeout**: `AuthService.touchActivity()` يُحفَظ في SharedPreferences. `isSessionExpired()` يفحص إذا الفارق > 30 يوم.

---

## 8. التتبع الجغرافي (Location Service)

`LocationService` يشتغل في Isolate خلفي منفصل (`flutter_background_service`) لسببين:
1. GPS يعمل حتى لو المستخدم أغلق التطبيق
2. Foreground Service على أندرويد يمنع النظام من قتل العملية

**Flow**:
1. الموظف يسجّل حضور → `startTracking(employeeId)`
2. كل 5 دقائق: أخذ Position، فحص السياج الجغرافي، رفع النقطة
3. Mock GPS detected? → INSERT في `mock_gps_attempts`
4. خارج السياج؟ → INSERT في `geofence_violations` (تجنّب التكرار عبر `_lastGeofenceStates`)
5. الموظف يسجّل انصراف → `stopTracking()`

---

## 9. الويب (Next.js)

- **Static Export** (`output: "export"` في `next.config.ts`)
- كل صفحة `'use client'` — لا SSR (متعمّد لتبسيط النشر)
- المصادقة عبر `@supabase/supabase-js` client-side فقط
- لا يوجد middleware: الـ static export لا يشغّل أي كود على السيرفر. `dashboard/layout.tsx`
  يتحقق من الجلسة والدور في المتصفح لأغراض الواجهة فقط — **الحماية الفعلية هي RLS
  وفحوصات الصلاحية داخل دوال قاعدة البيانات** (require_admin وغيرها)
- **ErrorBoundary** في `components/DashboardErrorBoundary.tsx`

**اقتراح مستقبلي**: تفعيل SSR لصفحات القوائم لتحسين وقت التحميل، لكن يتطلب مغادرة `output: "export"` والانتقال لـ Vercel أو Node host.

---

## 10. الأمان — نقاط حرجة

1. **kلمات المرور**: تُخزَّن في `employees.plain_password` (⚠️ يجب تشفيرها لاحقاً) + Supabase Auth
2. **مفاتيح Supabase**: تُمرَّر عبر `--dart-define` في الإنتاج. القيم في `constants.dart` للتطوير فقط
3. **RLS**: كل جدول عليه سياسات، بدون exception
4. **Audit Log**: كل تغيير في salary_slips, loans, employees, bonuses_deductions, leave_requests يُسجَّل تلقائياً
5. **Mock GPS**: يُكشف باستخدام Geolocator's `isMocked` ويُرفَض تسجيل الحضور
6. **Single-Device**: قفل الجهاز الواحد لكل موظف

---

## 11. التغييرات القادمة المقترحة (Roadmap)

- [ ] تشفير `plain_password` باستخدام pgcrypto
- [ ] استخدام Riverpod providers بدلاً من `AuthService.currentUserRole` static
- [ ] تقسيم الشاشات الكبيرة (admin_dashboard 1806 سطر → عدة widgets)
- [ ] إضافة unit tests + widget tests
- [ ] استخراج طبقة Repository لفصل الاستعلامات عن الـ UI
- [ ] Sentry/Crashlytics للـ error tracking
- [ ] Push notification للمدير عند طلب سلفة/إجازة جديدة
- [ ] تمكين 2FA للأدوار الإدارية

---

## 12. جهات الاتصال والحسابات

| الخدمة | Project ID | Dashboard |
|---|---|---|
| Supabase | `jgjlmddphhncatrhqrej` | https://supabase.com/dashboard/project/jgjlmddphhncatrhqrej |
| Firebase | `hr-pro-batra` | https://console.firebase.google.com/project/hr-pro-batra |
| GitHub | `hussein1994ayad/HR.Batra` | https://github.com/hussein1994ayad/HR.Batra |

---

## 13. تنسيقات الملفات

- **Dart**: `dart format` — سطر 80 char، single quotes
- **TypeScript**: `prettier` (default config) + eslint-config-next
- **SQL**: SQL keywords UPPERCASE، أسماء lowercase snake_case
- **Commit messages**: Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`)
