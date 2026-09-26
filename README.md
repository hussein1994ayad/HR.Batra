# HR Pro v6.0 — نظام إدارة الموارد البشرية

نظام إدارة موارد بشرية متكامل لشركة **بترا** ذات الفروع المتعددة (القناة، العكد، كمب سارة، بغداد الجديدة).
واجهة عربية RTL كاملة، دينار عراقي، وتغطي: الحضور بالبصمة الجغرافية، الرواتب، السلف، الإجازات، التتبع الميداني الحي.

## البنية

```
HR.Batra/
├── mobile/          Flutter (Dart) — تطبيق الموظف والأدمن (Android + iOS)
├── web/             Next.js 16 (TypeScript + Tailwind v4) — لوحة الإدارة
├── supabase/        قاعدة بيانات PostgreSQL + Edge Functions
│   ├── migrations/  29 ملف SQL بترتيب زمني
│   ├── functions/   daily-cleanup, push-notification (Deno)
│   └── seed_dev_data.sql
├── .github/workflows/  CI: Android APK + iOS IPA + Web static export
└── .env.example     قالب متغيرات البيئة
```

راجع [`ARCHITECTURE.md`](./ARCHITECTURE.md) لتفاصيل معمارية النظام والقرارات التصميمية.

## متطلبات التطوير

| البند | الإصدار |
|---|---|
| Flutter SDK | 3.41.9+ (Dart 3.11+) |
| Node.js | 20+ |
| Supabase CLI | آخر إصدار |
| Java (للأندرويد) | 17 |
| Xcode (لـ iOS) | 15+ (على macOS) |

## الإعداد الأول

### 1) استنساخ المستودع
```bash
git clone https://github.com/hussein1994ayad/HR.Batra.git
cd HR.Batra
cp .env.example .env.local
# افتح .env.local وضع مفاتيح Supabase الحقيقية
```

### 2) تهيئة قاعدة البيانات
```bash
# تشغيل migrations
supabase db push

# (اختياري) تعبئة بيانات تجريبية للتطوير المحلي
psql "$SUPABASE_DB_URL" -f supabase/seed_dev_data.sql
```

### 3) تشغيل تطبيق الجوال
```bash
cd mobile
flutter pub get

# بدون secrets (للتطوير المحلي، يستخدم القيم الافتراضية في constants.dart)
flutter run

# مع secrets عبر --dart-define
flutter run \
  --dart-define=SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$NEXT_PUBLIC_SUPABASE_ANON_KEY
```

### 4) تشغيل لوحة الويب
```bash
cd web
npm ci
npm run dev
# → http://localhost:3000
```

## البناء للإنتاج

### Android APK
```bash
cd mobile
flutter build apk --release --split-per-abi \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
# النتيجة: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### iOS IPA (macOS فقط)
```bash
cd mobile
flutter build ios --release --no-codesign
# ثم في Xcode: Product → Archive → Distribute App
```

### Web Static Export
```bash
cd web
npm run build
# النتيجة: web/out/ — انسخها لأي static host (Vercel, Netlify, Cloudflare Pages)
```

## CI/CD

كل push على `main` يشغّل تلقائياً:
- `.github/workflows/build_android.yml` — يبني APK بنسختين
- `.github/workflows/build_ios_physical.yml` — يبني IPA لأجهزة حقيقية
- `.github/workflows/build_ios_simulator.yml` — يبني IPA للمحاكي
- `.github/workflows/build_web.yml` — يبني static export من Next.js

الملفات المُنتجة (artifacts) تظهر في تبويب **Actions** لكل run.

## الأمان

- **RLS (Row-Level Security)** مفعّل على كل الجداول
- **قفل الجهاز الواحد** لكل موظف
- **كشف Mock GPS** لمنع تزييف الموقع
- **Session Timeout** بعد 30 يوم عدم استخدام
- **Audit Log** لتغييرات الجداول الحساسة (salary_slips, loans, employees, ...)

## أوامر مفيدة

```bash
# فحص الكود
cd mobile && dart analyze
cd web && npm run lint

# إصلاح تلقائي (unused imports, const, ...)
cd mobile && dart fix --apply

# فحص migrations
supabase db diff

# مسح cache الفلاتر عند مشاكل البناء
cd mobile && flutter clean && flutter pub get
```

## المساهمة

راجع [`ARCHITECTURE.md`](./ARCHITECTURE.md) قبل التعديل. لأي schema change، أضف migration جديد بصيغة `YYYYMMDDHHMMSS_<verb>_<scope>_<subject>.sql` (انظر [`supabase/MIGRATION_STYLE.md`](./supabase/MIGRATION_STYLE.md)).

## الترخيص

مغلق المصدر — للاستخدام الداخلي فقط.
