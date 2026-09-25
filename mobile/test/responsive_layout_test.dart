// Renders the redesigned screens at common phone/tablet sizes and text
// scales. Any RenderFlex overflow or layout exception fails the test.
//
// Set SCREENSHOT_DIR to also write PNG previews, e.g.
//   SCREENSHOT_DIR=/tmp/shots flutter test test/responsive_layout_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/presentation/auth/login_screen.dart';
import 'package:hr_pro/presentation/shared/widgets/app_widgets.dart';
import 'package:hr_pro/presentation/shared/widgets/bottom_nav_bar.dart';
import 'package:hr_pro/presentation/shared/widgets/glass_background.dart';
import 'package:hr_pro/presentation/shared/widgets/glass_container.dart';

const _devices = <String, Size>{
  'small_android': Size(320, 640),
  'iphone_se': Size(375, 667),
  'iphone_16_pro': Size(393, 852),
  'pixel_9_pro_xl': Size(412, 915),
  'ipad_landscape': Size(1194, 834),
};

const _textScales = [1.0, 1.3];

Future<void> _loadFonts() async {
  final loader = FontLoader(AppTheme.fontFamily);
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black']) {
    final bytes = File('assets/fonts/Cairo-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

Widget _app(Widget home, double textScale) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.darkTheme,
    locale: const Locale('ar', 'IQ'),
    supportedLocales: const [Locale('ar', 'IQ')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale).clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.2,
        ),
      ),
      child: child!,
    ),
    home: home,
  );
}

/// A static mock of the home tab built from the shared widgets, so the
/// visual language can be checked without a Supabase backend.
class _ComponentsPreview extends StatelessWidget {
  const _ComponentsPreview();

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      safeBottom: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader(title: 'الخدمات السريعة', icon: Icons.bolt_rounded, actionLabel: 'عرض الكل', onAction: _noop),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(label: 'مقبولة', color: AppTheme.successLight, icon: Icons.check_rounded),
                StatusPill(label: 'قيد المراجعة', color: AppTheme.warningLight),
                StatusPill(label: 'مرفوضة', color: AppTheme.dangerLight),
              ],
            ),
            const SizedBox(height: 16),
            const GlassContainer(
              child: EmptyState(
                icon: Icons.campaign_outlined,
                title: 'لا توجد إعلانات جديدة',
                message: 'ستظهر هنا تعاميم الإدارة فور نشرها.',
              ),
            ),
            const SizedBox(height: 16),
            const SkeletonBox(height: 72, radius: AppTheme.radiusLg),
            const SizedBox(height: 16),
            GradientButton(label: 'تسجيل الحضور', icon: Icons.fingerprint_rounded, onPressed: () {}),
            const SizedBox(height: 16),
            const TextField(decoration: InputDecoration(labelText: 'سبب الإجازة', prefixIcon: Icon(Icons.notes_rounded))),
          ],
        ),
        bottomNavigationBar: PremiumBottomNavBar(currentIndex: 0, onTap: (_) {}),
      ),
    );
  }

  static void _noop() {}
}

Future<void> _screenshot(WidgetTester tester, String name) async {
  final dir = Platform.environment['SCREENSHOT_DIR'];
  if (dir == null || dir.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$dir/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  final screens = <String, Widget Function()>{
    'login': () => const LoginScreen(),
    'components': () => const _ComponentsPreview(),
  };

  for (final screen in screens.entries) {
    for (final device in _devices.entries) {
      for (final scale in _textScales) {
        testWidgets('${screen.key} fits ${device.key} @${scale}x', (tester) async {
          tester.view.physicalSize = device.value * 2;
          tester.view.devicePixelRatio = 2;
          tester.view.padding = const FakeViewPadding(top: 48, bottom: 34);
          addTearDown(tester.view.reset);

          // Tests paint shadows as solid blocks by default; previews use real ones.
          final previews = (Platform.environment['SCREENSHOT_DIR'] ?? '').isNotEmpty;
          if (previews) debugDisableShadows = false;

          await tester.pumpWidget(_app(screen.value(), scale));
          await tester.pump(const Duration(seconds: 1));

          expect(tester.takeException(), isNull);
          await _screenshot(tester, '${screen.key}_${device.key}_$scale');
          debugDisableShadows = true;
        });
      }
    }
  }
}
