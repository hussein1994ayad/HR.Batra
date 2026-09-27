# iOS Setup Guide — HR Pro v6.0

هذا الدليل يشرح خطوات إعداد النسخة iOS عند وصول حساب Apple Developer.

## 📋 قائمة الأشياء الجاهزة الآن (تم بواسطة الكود)

| البند | الحالة |
|---|---|
| `Info.plist` — كل الصلاحيات + Background modes | ✅ جاهز |
| `PrivacyInfo.xcprivacy` — Privacy Manifest (App Store 2024+) | ✅ جاهز |
| `AppDelegate.swift` — APNs registration + notification delegate | ✅ جاهز |
| `special_chime.wav` — ملف الصوت في `ios/Runner/` | ✅ جاهز |
| `notification_service.dart` — يستخدم `special_chime.wav` على iOS | ✅ جاهز |
| Podfile — iOS 14.0 deployment target | ✅ جاهز |
| Bundle ID — `com.batra.hrpro.hrPro` | ✅ محدد |

## 🚧 ما تحتاج تعمله بعد الحصول على حساب Apple Developer

### 1) إنشاء تطبيق iOS في Firebase Console

1. افتح https://console.firebase.google.com/project/hr-pro-batra/settings/general
2. اضغط **Add app** → **iOS**
3. **Bundle ID**: `com.batra.hrpro.hrPro` (بالضبط كما هو في Podfile)
4. **App nickname**: HR Pro iOS
5. حمّل الملف **`GoogleService-Info.plist`**
6. ضعه في: `mobile/ios/Runner/GoogleService-Info.plist`
7. حدّث `mobile/lib/firebase_options.dart` بالقيم الجديدة (أو شغّل `flutterfire configure`)

### 2) إعداد APNs في Firebase

1. افتح https://developer.apple.com/account/resources/authkeys/list
2. اضغط **+** → **Apple Push Notifications service (APNs)**
3. **Key Name**: HR Pro APNs
4. اختر Environment: Both (Development + Production)
5. حمّل ملف `.p8` (يمكن تحميله مرة واحدة فقط!)
6. لاحظ **Key ID** (10 أحرف) و **Team ID** (في أعلى الصفحة)
7. في Firebase Console → Project Settings → Cloud Messaging → APNs Authentication Key → **Upload**
8. ارفع ملف `.p8` + أدخل Key ID + Team ID

### 3) إضافة `special_chime.wav` لـ Xcode target

1. افتح Xcode: `open mobile/ios/Runner.xcworkspace`
2. في **Project Navigator** (اليسار)، اسحب `special_chime.wav` من Finder إلى مجموعة **Runner**
3. عند السؤال، اختر **✓ Copy items if needed** و **✓ Add to targets: Runner**
4. تأكد من ظهوره في **Runner → Build Phases → Copy Bundle Resources**

### 4) توقيع التطبيق (Signing)

1. Xcode → Runner → Signing & Capabilities
2. اختر **Team**: اسم حسابك في Apple Developer
3. تأكد من **Bundle Identifier**: `com.batra.hrpro.hrPro`
4. Xcode ينشئ Provisioning Profile تلقائياً

### 5) تفعيل Capabilities في Xcode

في **Runner → Signing & Capabilities**، اضغط **+ Capability** وأضف:
- **Push Notifications**
- **Background Modes** → فعّل: Location updates, Background fetch, Remote notifications, Background processing
- **Sign in with Apple** (اختياري لتسجيل دخول سريع مستقبلاً)

### 6) البناء والاختبار

```bash
cd mobile
flutter clean
flutter pub get
cd ios && pod install && cd ..

# للاختبار على المحاكي
flutter run

# للاختبار على iPhone حقيقي (يحتاج توقيع)
flutter build ios --release
open ios/Runner.xcworkspace
# ثم Product → Archive في Xcode → Distribute App
```

### 7) TestFlight (توزيع تجريبي)

بعد Archive:
1. Xcode → Organizer → اختر Build → Distribute App → App Store Connect → Upload
2. https://appstoreconnect.apple.com → My Apps → HR Pro → TestFlight
3. أضف Testers بإيميلاتهم (يستلمون دعوة عبر TestFlight app)

## 🐛 مشاكل شائعة

### الإشعارات ما توصل
- تأكد `GoogleService-Info.plist` موجود في `ios/Runner/`
- تأكد APNs Key مرفوع في Firebase
- تأكد الجهاز يستقبل إشعار الاختبار من Firebase Console → Cloud Messaging → Send test message
- في iOS Simulator: Push notifications لا تعمل — استخدم iPhone حقيقي

### الصوت ما يجي
- تأكد `special_chime.wav` موجود في Runner target (Build Phases → Copy Bundle Resources)
- iOS ما يشغل صوت أطول من 30 ثانية للإشعار

### التتبع الجغرافي بالخلفية ينقطع
- iOS يوقف التطبيق بعد ~10 دقائق في الخلفية إذا ما فيه حركة
- Flutter's `flutter_background_service` على iOS محدود لأسباب Apple
- الحل: استخدم Significant Location Changes API (يشتغل حتى لو التطبيق مقفول)

### App Store Rejection على الخصوصية
- تأكد `PrivacyInfo.xcprivacy` موجود في target ✅ (جاهز)
- تأكد كل الصلاحيات معلَّلة بـ NS…UsageDescription ✅ (جاهز)
- iOS 18: قد يطلب Apple شرح إضافي لـ Always Location — اذكر مبرر HR

## 📞 الدعم

كل هذه الإعدادات موجودة في المستودع جاهزة. المطلوب فقط:
1. حساب Apple Developer ($99/سنة)
2. macOS مع Xcode 15+ لبناء iOS
3. اتباع الخطوات أعلاه

مصدر Bundle IDs والـ APNs: راجع Firebase Console + Apple Developer Portal.
