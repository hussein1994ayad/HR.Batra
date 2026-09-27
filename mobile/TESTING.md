# HR Pro — Testing Guide

## هيكل الاختبارات

```
mobile/test/
├── unit/
│   ├── constants_test.dart       اختبارات AppConstants (formatMoney, config)
│   ├── auth_provider_test.dart   اختبارات Riverpod (currentUserRole, isAdmin, ...)
│   └── theme_test.dart           اختبارات AppTheme (design tokens, shadows, ...)
├── widget/
│   └── (لاحقاً) skeleton_test.dart, bottom_nav_test.dart, ...
├── integration/
│   └── (لاحقاً) full login → home flow tests
├── unit_test.dart                (legacy — سيُدمج في unit/)
└── widget_test.dart              (legacy — smoke test for GlassContainer)
```

## تشغيل الاختبارات

```bash
# كل الاختبارات
cd mobile
flutter test

# مجلد واحد
flutter test test/unit/

# ملف واحد
flutter test test/unit/auth_provider_test.dart

# مع تغطية (coverage)
flutter test --coverage
# النتيجة في: coverage/lcov.info
# للعرض: genhtml coverage/lcov.info -o coverage/html
```

## كتابة اختبارات جديدة — قواعد

1. **اسم الملف** ينتهي بـ `_test.dart`
2. **مجموعات واضحة**: `group('ما يوصفه', () { ... })`
3. **اختبار واحد = فرضية واحدة**: `test('يفعل كذا في حالة كذا', () { ... })`
4. **AAA pattern**: Arrange → Act → Assert
5. **لا تعتمد على شبكة أو ملفات فعلية** — استخدم mocks
6. **`ProviderContainer` مع `addTearDown`** لتنظيف Riverpod

## Widget Tests

```dart
testWidgets('LoginScreen shows email + password fields', (tester) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: ProviderContainer(),
      child: MaterialApp(home: LoginScreen()),
    ),
  );
  expect(find.byType(TextFormField), findsNWidgets(2));
});
```

## Integration Tests (لاحقاً)

```bash
flutter test integration_test/
```

يتطلب جهاز متصل أو محاكي شغّال. يختبر الـ flow الكامل (login → home → attendance).

## CI

`.github/workflows/build_android.yml` يمكن إضافة خطوة:
```yaml
- name: Run tests
  working-directory: ./mobile
  run: flutter test --reporter compact
```

قبل خطوة `flutter build apk`. أي اختبار يفشل يمنع بناء الـ APK.

## اقتراحات للتوسّع

بالترتيب من الأسهل للأصعب:
- [x] `AppConstants` (تم)
- [x] Riverpod providers (تم)
- [x] `AppTheme` (تم)
- [ ] `AuthService` — يحتاج mock لـ Supabase client
- [ ] `LocationService.checkMockGps()` — منطق بحت
- [ ] Widget tests لـ `SkeletonLoader`, `OfflineBanner`
- [ ] Widget tests لـ `PremiumBottomNavBar` (tap behavior)
- [ ] Integration test: full login flow

## Mocking Supabase

استخدم `mocktail` أو `mockito`:

```yaml
dev_dependencies:
  mocktail: ^1.0.0
```

```dart
class MockSupabaseClient extends Mock implements SupabaseClient {}
```

ثم في الاختبار: `when(() => mock.from('employees')...)`
