# دليل المطوّر — HR Pro

ملف واحد للي يريد يطوّر أو يصلّح المشروع (كان ملفين: هذا و`ARCHITECTURE.md`، ودُمجوا 7/11/2026 وانشالت المعلومات القديمة).
**قواعد العمل** (الحضور، الرواتب، السلف، الإجازات) ومكان كل قاعدة بالكود بـ [`BUSINESS_RULES.md`](./BUSINESS_RULES.md)،
وسجل كل تغيير وسببه بـ [`CHANGES.md`](./CHANGES.md).

---

## 1. نظرة عامة

```
                Supabase (PostgreSQL 17 + Auth + Storage + Edge Functions)
                        │  ← كل الحسابات والصلاحيات هنا
          ┌─────────────┴─────────────┐
   تطبيق Flutter (mobile/)      لوحة Next.js (web/)
   الموظف + المدير + الأدمن     الأدمن والمدير (تصدير ثابت، بدون سيرفر)
```

- **المصدر الأساسي هو قاعدة البيانات:** السيرفر يحسب ويرفض. الويب والتطبيق ينسخون قواعد قليلة بس للعرض قبل الإرسال
  (كل نسخة مكتوب مكانها بـ `BUSINESS_RULES.md`). ماكو سيرفر وسيط.
- **التطبيق:** أندرويد وآيفون، عربي، **داكن فقط**. التوزيع خاص (مو بالمتاجر).

## 2. الأدوار

| الدور | يكدر |
|---|---|
| `employee` | بصمة، إجازة، سلفة، كشوف راتبه، إعداداته |
| `manager` | مثل الموظف + موظفي **فرعه** بس (حضور، قرارات)؛ الرواتب والمبالغ مخفية عنه، وما يقرر على نفسه |
| `admin` | كل شي |

الحماية الحقيقية بالسيرفر (سياسات الصفوف RLS، وفحص الدور داخل الدوال مثل `require_admin`). إخفاء الأزرار بالواجهة للشكل بس.

## 3. هيكل المشروع

```
mobile/lib/
├── main.dart                  نقطة الدخول: Supabase + Firebase + الإشعارات
├── core/
│   ├── constants/             ثوابت وروابط (المفاتيح بـ --dart-define)
│   ├── design/                الألوان والمسافات والخطوط + Fmt (تنسيق التاريخ والمبالغ)
│   ├── theme/app_theme.dart   الثيم (داكن فقط)
│   ├── logic/                 قواعد بدون واجهة وقابلة للفحص (attendance_rules، loan_rules، reminder_plan، push_registration…)
│   ├── models/                نماذج البيانات (models.dart يصدّرها كلها)
│   ├── providers/             Riverpod
│   ├── routes/app_router.dart كل المسارات (go_router)
│   ├── services/              بنية تحتية: auth، البصمة وطابورها بدون إنترنت، التتبع (location/)، الإشعارات، Excel/PDF، التحديثات
│   └── utils/                 السجلات، البحث العربي، تحويل JSON
├── data/repositories/         كل استعلامات Supabase (الشاشات ما تكلم القاعدة مباشرة)
└── presentation/              مجلد لكل شاشة: <screen>_screen.dart + widgets/ + <x>_logic.dart
    ├── auth/  employee/  admin/
    └── shared/ui/ui.dart      مكتبة المكوّنات الموحّدة (التفاصيل بـ mobile/DESIGN.md)

web/src/
├── app/dashboard/<page>/      الصفحات: تركيب فقط
├── features/<x>/              api.ts (Supabase) + logic.ts (منطق نقي) + useX.ts + components/
├── components/ui/             مكوّنات الواجهة المشتركة
└── lib/                       db-types.ts، dates.ts، excel.ts، supabase.ts …

supabase/
├── migrations/                ملف الأساس 20261025000000 + كل ملف جديد بعده (الملف المطبّق ما يتعدّل أبداً)
├── migrations_archive/        الـ 95 ملف القديمة (تاريخ بس، ما تشتغل)
├── schema/current_functions.sql  النسخة الحالية من كل دالة وtrigger (للقراءة؛ تتولد بـ node supabase/schema/generate.mjs)
├── functions/                 push-notification، daily-cleanup، hr-assistant (Deno)
└── tests/                     فحوص قاعدة البيانات على PGlite (npm test)
```

## 4. قاعدة البيانات

- **42 جدول، ~208 دالة، 7 Views**، والسياسات مفعّلة على كل الجداول. أي دالة أو جدول: ابحث بـ `current_functions.sql`
  أو بملف الأساس، مو بالأرشيف.
- **قواعد التعديل:**
  1. لا تعدّل ملف migration مطبّق. أضف ملف جديد (`YYYYMMDDHHMMSS_<verb>_<scope>_<subject>.sql`، التفاصيل بـ `supabase/MIGRATION_STYLE.md`).
  2. بعد أي دالة جديدة: `node supabase/schema/generate.mjs` (الفحص التلقائي يفشل إذا الملف مو محدّث).
  3. الملف الجديد لازم ينجح بـ `cd supabase/tests && npm test` قبل `npx.cmd supabase db push`.
- **التخزين:** `avatars` و`company-logos` و`ota-updates` عامة؛ `documents` و`loan-pledges` خاصة (روابط موقّعة).
- **المهام المجدولة (pg_cron):** تذكيرات البصمة كل دقيقة، المسير الليلي، تنظيف يومي (السلة، السجلات، محادثات المساعد)،
  وملخص الصباح للأدمن. القائمة الكاملة بآخر ملف الأساس (`cron.schedule`).
- **الإشعارات:** أي سطر جديد بـ `notifications` يشغّل `invoke_push_notification` ← دالة `push-notification` ← Firebase.
  الموبايل يتسجل برقم التنصيب (FID) ويحتاج إعداد `firebase_messaging_installation_id_enabled` بـ `AndroidManifest.xml`.

## 5. أهم الآليات

- **الدخول:** `AuthService` — حساب معطّل، كلمة سر مؤقتة لازم تتغير، وقفل جهاز واحد لكل موظف (`register_device_login`؛
  معرّف الجهاز ثابت: Android ID / Keychain). الجلسة تنتهي بعد 30 يوم بدون استعمال. بدون إنترنت يبقى المستخدم داخل.
- **البصمة:** كلها تمر بدالة `punch_attendance` بالسيرفر (المسافة، الدقة، الموقع المزيف، التأخير، الجهاز). بدون إنترنت تنحفظ بطابور
  محلي وترتفع بعدين وتتعلّم للمراجعة.
- **التتبع:** أندرويد بخدمة خلفية (`flutter_background_service`): نقطة كل ما تحرك 25 متر، أو كل 2–5 دقايق. الآيفون ما يستعملها:
  التتبع من `ios/Runner/LocationMonitorIOS.swift`. النقاط تبقى 45 يوم. التتبع وقت الدوام بس ومعلَن للموظف (شاشة البصمة وسياسة
  الخصوصية)؛ لا تحاول تخفي مؤشر الموقع بالنظام.
- **الوقت:** كل الحسابات بتوقيت بغداد (وقت الشركة)، والتطبيق يقارن ساعته ويا السيرفر.

## 6. إضافة ميزة جديدة (مثال: طلب معدات)

1. **القاعدة:** ملف migration جديد (الجدول + السياسات + الدوال) ← فحص بـ `supabase/tests` (ملف `test_*.mjs` جديد: أول سطر
   `import './clock.mjs';`، وضيفه لقائمة `run_all.mjs`).
2. **النموذج:** `lib/core/models/equipment_request_model.dart` (`fromMap`) وصدّره بـ `models.dart`.
3. **الاستعلامات:** `lib/data/repositories/equipment_repository.dart` (نفس نمط `LeaveRepository`).
4. **الشاشة:** `lib/presentation/employee/equipment/` — الشاشة، و`widgets/`، وأي حساب بدون واجهة بـ `equipment_logic.dart` ويا فحص بـ `test/unit/`.
5. **المسار:** `lib/core/routes/app_router.dart`، وزر بـ `main_layout.dart` أو `home_screen.dart`.
6. **الويب (إذا لزم):** `web/src/features/equipment/` بنفس التقسيم.
7. **حدّث** `BUSINESS_RULES.md` إذا بيها قاعدة عمل، وسجّل الخطوة بـ `CHANGES.md`.

## 7. التصميم

داكن فقط، ومن نظام التصميم فقط: لا ألوان ولا أحجام مباشرة بالشاشات.
```dart
import '../shared/ui/ui.dart';
AppColors.brand / success / danger
AppCard(child: ...), AppButton(label: ..., onPressed: ...), AppSnack.success(context, '...')
```
الأشهر تنكتب بالرقم («الشهر العاشر 2026») والتواريخ أرقام بكل مكان.

## 8. الفحوص (قبل أي دمج)

```bash
cd mobile && flutter analyze && flutter test        # ~740 فحص، منها كل الشاشات بكل المقاسات
cd web && npm run lint && npx tsc --noEmit && npx vitest run
cd supabase/tests && npm test                       # 35 ملف، الساعة ثابتة على 20/10/2026
```
نفسها تشتغل تلقائياً بـ `.github/workflows/quality.yml`. ودفع `design-v2` يشغّل بناء الآيفون وفحوص محاكي الآيفون
(النتائج بفرع `ios-sim-results`، ملف `RESULTS.md`).

- **لقطات نصية للشاشات:** `mobile/test/screens/text_snapshot_test.dart` يقارن كل نص ظاهر بـ `mobile/test/goldens/text/`.
  تغيير مقصود بالواجهة؟ `flutter test test/screens/text_snapshot_test.dart --dart-define=UPDATE_TEXT=true`.
- **النسخة النهائية (release):** بعد أي تغيير بمكتبات أندرويد أو Flutter، جرّبها على المحاكي وراقب السجل؛ الضغط (R8) خرّب
  الدخول مرة بالنسخة النهائية بس (قواعد الحفظ بـ `android/app/proguard-rules.pro`).

## 9. الإصدار

الترتيب: **قاعدة البيانات ← الدوال ← دمج `main` (ينشر الويب) ← التطبيق.**

```bash
npx.cmd supabase db push
npx.cmd supabase functions deploy push-notification --no-verify-jwt
cd mobile; flutter build apk --release --split-per-abi
```
- **مفتاح التوقيع (أندرويد):** `mobile/android/key.properties` + ملف `.jks` خارج git (`build.gradle.kts` يقراهم). بدونهم تنبني
  نسخة بمفتاح تجريبي: لا توزعها. للـ CI: `ANDROID_KEYSTORE_BASE64` و`ANDROID_KEYSTORE_PASSWORD` و`ANDROID_KEY_ALIAS` و`ANDROID_KEY_PASSWORD`.
- **أول نسخة بمفتاح جديد** تحتاج حذف التطبيق القديم، وهذا يغيّر معرّف الجهاز. قبل توزيعها صفّر قفل الأجهزة مرة وحدة:
  ```sql
  UPDATE employees SET device_id_lock = 'force_lock_active' WHERE COALESCE(device_id_lock, '') <> '';
  ```
- **الآيفون:** الخطوات بـ [`IOS_SETUP.md`](./IOS_SETUP.md).

## 10. المساعد الذكي (Edge Function `hr-assistant`)

- الملفات: `supabase/functions/hr-assistant/` — `index.ts` (HTTP + التحقق من الأدمن)، `agent.ts` (الحلقة)، `tools.ts` (الأدوات)،
  `excel.ts`، `gemini.ts` (المزوّد)، `prompt.ts`، `context.ts`، `voice.ts` (السؤال بالصوت). الشاشات: `mobile/lib/presentation/admin/assistant/` و`web/src/features/assistant/`.
- التفعيل: `npx.cmd supabase secrets set GEMINI_API_KEY=...` ثم `npx.cmd supabase functions deploy hr-assistant`.
- الفحص: `npx deno test --allow-env --allow-read --allow-net=registry.npmjs.org,jsr.io supabase/functions/hr-assistant/`.
- السرعة: الوقت كله بالذكاء مو بالقاعدة. بيانات جاهزة قبل السؤال (`context.ts`)، وموديلين (السريع `GEMINI_FAST_MODEL` للعادي، والأقوى
  `GEMINI_MODEL` للقرارات والصوت، وكل واحد احتياطي للثاني)، وأقل تفكير يقبله الموديل، ومهلة لكل محاولة. كل سؤال يكتب
  `hr-assistant timing` بالسجل.

## 11. الحسابات

| الخدمة | المعرّف | اللوحة |
|---|---|---|
| Supabase | `jgjlmddphhncatrhqrej` | https://supabase.com/dashboard/project/jgjlmddphhncatrhqrej |
| Firebase | `hr-pro-batra` | https://console.firebase.google.com/project/hr-pro-batra |
| GitHub | `hussein1994ayad/HR.Batra` | https://github.com/hussein1994ayad/HR.Batra |

**التنسيق:** Dart بـ `dart format`؛ TypeScript بـ eslint؛ SQL الكلمات المحجوزة كبيرة والأسماء snake_case؛ رسائل الحفظ
بصيغة Conventional Commits (`feat:`، `fix:`، `refactor:`…).
