// أداة تشغيل الشاشات في الاختبار: حجم الجهاز، حجم الخط، الخطوط الحقيقية،
// والتقاط لقطة PNG (فقط عند --dart-define=CAPTURE=before|after).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hr_pro/core/providers/app_container.dart';
import 'package:hr_pro/core/providers/auth_provider.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_backend.dart';

/// اسم مجلد اللقطات: before أو after — فارغ = لا حفظ.
const String kCaptureSet = String.fromEnvironment('CAPTURE');

class DeviceSize {
  const DeviceSize(this.name, this.width, this.height, {this.top = 24, this.bottom = 16, this.ios = false});
  final String name;
  final double width;
  final double height;
  /// المساحة الآمنة الحقيقية للجهاز: النوتش/Dynamic Island فوگ، وشريط الهوم/أزرار أندرويد جوه.
  final double top;
  final double bottom;
  /// يرسم بأسلوب iOS (نوافذ Cupertino وغيرها) مثل الآيفون الحقيقي.
  final bool ios;
  Size get size => Size(width, height);
  @override
  String toString() => '$name ${width.toInt()}x${height.toInt()}';
}

const kPhoneSizes = [
  DeviceSize('small', 320, 640),
  DeviceSize('iphone_se', 375, 667, top: 20, bottom: 0, ios: true),
  DeviceSize('iphone_mini_notch', 375, 812, top: 50, bottom: 34, ios: true),
  DeviceSize('iphone_pro_island', 402, 874, top: 62, bottom: 34, ios: true),
  DeviceSize('iphone_pro_max', 440, 956, top: 62, bottom: 34, ios: true),
  DeviceSize('android', 412, 915),
];
const kTabletPortrait = DeviceSize('ipad', 834, 1194, bottom: 20, ios: true);
const kTabletLandscape = DeviceSize('ipad_land', 1194, 834, bottom: 20, ios: true);
const kAllSizes = [...kPhoneSizes, kTabletPortrait, kTabletLandscape];
const kScreenshotSize = DeviceSize('pixel', 393, 852);

bool _fontsLoaded = false;

Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  GoogleFonts.config.allowRuntimeFetching = false;
  final cairo = FontLoader('Cairo');
  for (final w in const ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black', 'Light', 'ExtraLight']) {
    cairo.addFont(rootBundle.load('assets/google_fonts/Cairo-$w.ttf'));
  }
  await cairo.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await loader.load();
    }
  }
  _fontsLoaded = true;
}

final _boundaryKey = GlobalKey();

/// يشغّل [screen] داخل تطبيق كامل (ثيم، RTL، GoRouter، Riverpod) بحجم [device].
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  DeviceSize device = kScreenshotSize,
  double textScale = 1.0,
  String role = 'admin',
  bool offline = false,
  Duration settle = const Duration(seconds: 2),
}) async {
  await tester.runAsync(() async {
    await _loadFonts();
    await FakeBackend.ensureInitialized();
  });
  FakeBackend.reset(role: role, fail: offline);
  appContainer.read(currentUserRoleProvider.notifier).state = role;

  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = device.size * 2.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/__test',
    routes: [GoRoute(path: '/__test', builder: (_, __) => screen)],
    errorBuilder: (_, state) => Scaffold(body: Center(child: Text(state.uri.toString()))),
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: appContainer,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: MediaQuery(
          data: MediaQueryData(
            size: device.size,
            devicePixelRatio: 2.0,
            textScaler: TextScaler.linear(textScale),
            padding: EdgeInsets.only(top: device.top, bottom: device.bottom),
            viewPadding: EdgeInsets.only(top: device.top, bottom: device.bottom),
          ),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ar', 'IQ'),
            supportedLocales: const [Locale('ar', 'IQ'), Locale('ar', '')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: device.ios ? AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS) : AppTheme.darkTheme,
            darkTheme: device.ios ? AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS) : AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            routerConfig: router,
          ),
        ),
      ),
    ),
  );
  // تحميل البيانات من الخادم الوهمي ثم استقرار الحركات
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(settle ~/ 6);
  }
}

/// يحفظ لقطة PNG للشاشة الحالية في mobile/design/screenshots/<set>/<name>.png
Future<void> capture(WidgetTester tester, String name) async {
  if (kCaptureSet.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('design/screenshots/$kCaptureSet/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

/// يزيل الشاشة ليُلغي المؤقتات والاشتراكات قبل نهاية الاختبار.
Future<void> disposeScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final client = Supabase.instance.client;
  // إغلاق القنوات ينتظر رد السوكيت؛ على Linux (CI) فشل الاتصال بالخادم الوهمي يترك هذا
  // الانتظار معلّقاً داخل الوقت الوهمي للاختبار فيتوقف 10 دقائق. يُنفَّذ بوقت حقيقي وبحد أقصى.
  await tester.runAsync(() async {
    await client.removeAllChannels().timeout(const Duration(seconds: 2), onTimeout: () => const []);
    await client.realtime.disconnect().timeout(const Duration(seconds: 2), onTimeout: () {});
  });
  // مؤقتات إعادة المحاولة الداخلية (الريل تايم، طابور البصمات) تنتهي خلال دقائق وهمية
  await tester.pump(const Duration(minutes: 5));
}
