// اختبار على جهاز/محاكي حقيقي (iOS Simulator على GitHub أو أندرويد):
// يشغّل التطبيق الحقيقي (main) ويتأكد إنه يفتح بدون ما يطفي، ويجرّب الكود الأصلي (Swift/Kotlin)
// عبر قنواته: معرّف الجهاز بالـ Keychain، ومراقب الموقع، والموقع الدقيق.
//
// التشغيل:  flutter drive --driver=test_driver/integration_test.dart \
//             --target=integration_test/app_launch_test.dart -d <device>

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hr_pro/core/services/location_service.dart';
import 'package:hr_pro/core/services/precise_location.dart';
import 'package:hr_pro/main.dart' as app;
import 'package:integration_test/integration_test.dart';

/// موقع المحاكي (يضبطه سكربت CI بـ simctl location).
final _simLat = double.parse(const String.fromEnvironment('SIM_LAT', defaultValue: '33.3128'));
final _simLng = double.parse(const String.fromEnvironment('SIM_LNG', defaultValue: '44.3615'));

Future<bool> _pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 40)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real app launches (login, or home if a session exists) without crashing', (tester) async {
    // main يركّب معالج أخطاء خاص؛ نرجّع معالج الاختبار حتى الفشل ينطبع بدل ما يعلّق
    final testOnError = FlutterError.onError;
    app.main();
    // جهاز جديد: شاشة الدخول. جهاز عليه جلسة سابقة: الرئيسية.
    final shown = await _pumpUntil(tester, find.byWidgetPredicate(
        (w) => w is Text && (w.data == 'تسجيل الدخول' || w.data == 'الرئيسية')));
    FlutterError.onError = testOnError;
    if (!shown) {
      // تشخيص: شنو الظاهر على الشاشة
      final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(30).toList();
      debugPrint('LAUNCH_SCREEN_TEXTS: $texts');
      await _shot(binding, '00_launch_timeout');
    }
    expect(shown, isTrue, reason: 'لا شاشة الدخول ولا الرئيسية ظهرت خلال 40 ثانية');
    // ثواني إضافية: أي crash متأخر (تسجيل مهام الخلفية بعد ربط الـ scene) يطلع هنا
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    if (find.text('تسجيل الدخول').evaluate().isNotEmpty) {
      expect(find.text('نسيت كلمة المرور؟'), findsOneWidget);
    }
    await _shot(binding, '00_real_app_launch');
  });

  testWidgets('native device id (Keychain) is stable', (tester) async {
    const channel = MethodChannel('com.batra.hrpro/device');
    if (!Platform.isIOS) return;
    final a = await channel.invokeMethod<String>('getStableDeviceId');
    final b = await channel.invokeMethod<String>('getStableDeviceId');
    expect(a, isNotNull);
    expect(a, startsWith('ios-'));
    expect(b, a);
  });

  testWidgets('native iOS location monitor accepts configure / token / stop', (tester) async {
    if (!Platform.isIOS) return;
    const channel = MethodChannel('com.batra.hrpro/ios_location');
    await channel.invokeMethod<void>('configure', {
      'supabaseUrl': 'https://example.supabase.co',
      'supabaseAnonKey': 'test-anon',
      'employeeId': '00000000-0000-0000-0000-000000000001',
      'accessToken': 'header.payload.sig',
    });
    await channel.invokeMethod<void>('updateAccessToken', {'accessToken': 'header.payload2.sig'});
    await channel.invokeMethod<void>('setCheckedIn', {'value': false});
    await channel.invokeMethod<void>('stopMonitoring');
  });

  testWidgets('precise location is available and matches the simulator', (tester) async {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      // أداة الاختبار تعيد تثبيت التطبيق فتضيع الصلاحية الممنوحة مسبقاً؛ ما نگدر نضغط نافذة النظام من هنا
      debugPrint('LOCATION_TEST_SKIPPED: permission=$permission');
      markTestSkipped('صلاحية الموقع غير ممنوحة في بيئة الاختبار');
      return;
    }
    expect(await PreciseLocation.ensure(), isTrue);
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
    final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, _simLat, _simLng);
    expect(d, lessThan(200), reason: 'الموقع ${pos.latitude},${pos.longitude} بعيد ${d.round()} م');
    expect(pos.accuracy, lessThanOrEqualTo(PreciseLocation.maxPunchAccuracyMeters));
  });

  testWidgets('tracking service starts and stops (location split refactor)', (tester) async {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      debugPrint('LOCATION_TEST_SKIPPED: tracking (permission=$permission)');
      markTestSkipped('صلاحية الموقع غير ممنوحة في بيئة الاختبار');
      return;
    }
    // بدون جلسة: الرفع يُرفض من السيرفر فتبقى النقاط بالطابور المحلي — ما ينكتب شي بالقاعدة الحية
    await LocationService.startTracking(employeeId: '00000000-0000-0000-0000-000000000001');
    expect(LocationService.isTracking, isTrue);
    await Future<void>.delayed(const Duration(seconds: 5));
    await LocationService.stopTracking();
    expect(LocationService.isTracking, isFalse);
  });
}

/// اللقطات للآيفون (محاكي CI). أندرويد يحتاج تحويل سطح الرسم وإطارات إضافية فنتخطاه.
Future<void> _shot(IntegrationTestWidgetsFlutterBinding binding, String name) async {
  if (!Platform.isIOS) return;
  await binding.takeScreenshot(name);
}
