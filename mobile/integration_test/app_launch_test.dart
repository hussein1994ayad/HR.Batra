// اختبار على جهاز/محاكي حقيقي (iOS Simulator على GitHub أو أندرويد):
// يشغّل التطبيق الحقيقي (main) ويتأكد إنه يفتح بدون ما يطفي، ويجرّب الكود الأصلي (Swift/Kotlin)
// عبر قنواته: معرّف الجهاز بالـ Keychain، ومراقب الموقع، والموقع الدقيق.
//
// التشغيل:  flutter drive --driver=test_driver/integration_test.dart \
//             --target=integration_test/app_launch_test.dart -d <device>

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
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

  testWidgets('real app launches to the login screen without crashing', (tester) async {
    app.main();
    final shown = await _pumpUntil(tester, find.text('تسجيل الدخول'));
    expect(shown, isTrue, reason: 'شاشة الدخول ما ظهرت خلال 40 ثانية');
    // ثواني إضافية: أي crash متأخر (تسجيل مهام الخلفية بعد ربط الـ scene) يطلع هنا
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('نسيت كلمة المرور؟'), findsOneWidget);
    await binding.takeScreenshot('00_real_app_login');
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
    expect(permission, anyOf(LocationPermission.always, LocationPermission.whileInUse),
        reason: 'سكربت CI يمنح صلاحية الموقع مسبقاً');
    expect(await PreciseLocation.ensure(), isTrue);
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
    );
    final d = Geolocator.distanceBetween(pos.latitude, pos.longitude, _simLat, _simLng);
    expect(d, lessThan(200), reason: 'الموقع ${pos.latitude},${pos.longitude} بعيد ${d.round()} م');
    expect(pos.accuracy, lessThanOrEqualTo(PreciseLocation.maxPunchAccuracyMeters));
  });
}
