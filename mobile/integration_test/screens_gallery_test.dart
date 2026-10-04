// كل شاشات التطبيق على جهاز/محاكي حقيقي ببيانات وهمية (FakeBackend) — بمقاس الجهاز الحقيقي
// ومساحته الآمنة (النوتش، Dynamic Island، شريط الهوم) ورسم iOS الحقيقي. يلتقط صورة لكل شاشة،
// ويفشل إذا صار overflow أو خطأ رسم، أو إذا عنصر قابل للضغط دخل تحت النوتش/شريط الهوم.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hr_pro/core/providers/app_container.dart';
import 'package:hr_pro/core/providers/auth_provider.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../test/support/fake_backend.dart';
import '../test/support/screens.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false; // الخط من داخل التطبيق
    await FakeBackend.ensureInitialized();
  });

  for (final s in kScreens) {
    testWidgets(s.name, (tester) async {
      FakeBackend.reset(role: s.role);
      appContainer.read(currentUserRoleProvider.notifier).state = s.role;
      final router = GoRouter(
        initialLocation: '/__test',
        routes: [GoRoute(path: '/__test', builder: (_, __) => s.build())],
        errorBuilder: (_, state) => Scaffold(body: Center(child: Text(state.uri.toString()))),
      );
      await tester.pumpWidget(UncontrolledProviderScope(
        container: appContainer,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar', 'IQ'),
          supportedLocales: const [Locale('ar', 'IQ'), Locale('ar', '')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.darkTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          routerConfig: router,
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      // أزرار/حقول تحت النوتش أو Dynamic Island أو شريط الهوم = ما ينضغط صح على الآيفون
      final ctx = tester.element(find.byType(Scaffold).first);
      final mq = MediaQuery.of(ctx);
      final unsafe = <String>[];
      for (final e in find.byWidgetPredicate((w) => w is ButtonStyleButton || w is IconButton || w is TextField || w is FloatingActionButton).evaluate()) {
        final box = e.renderObject;
        if (box is! RenderBox || !box.hasSize || !box.attached) continue;
        // محتوى القوائم يتمرر خلف الأشرطة (طبيعي)؛ نفحص العناصر الثابتة فقط (أشرطة، أزرار عائمة)
        if (find.ancestor(of: find.byWidget(e.widget), matching: find.byType(Scrollable)).evaluate().isNotEmpty) continue;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (rect.height == 0 || rect.bottom <= 0 || rect.top >= mq.size.height) continue; // خارج الشاشة
        if (rect.top < mq.viewPadding.top - 1 || rect.bottom > mq.size.height - mq.viewPadding.bottom + 1) {
          unsafe.add('${e.widget.runtimeType} @ ${rect.top.round()}..${rect.bottom.round()}');
        }
      }
      await _shot(binding, s.name);
      expect(unsafe, isEmpty, reason: 'عناصر داخل المنطقة غير الآمنة (insets ${mq.viewPadding})');

      await tester.pumpWidget(const SizedBox.shrink());
      await Supabase.instance.client.removeAllChannels().timeout(const Duration(seconds: 2), onTimeout: () => const []);
    });
  }
}

/// اللقطات للآيفون (محاكي CI). أندرويد يحتاج تحويل سطح الرسم وإطارات إضافية فنتخطاه.
Future<void> _shot(IntegrationTestWidgetsFlutterBinding binding, String name) async {
  if (!Platform.isIOS) return;
  await binding.takeScreenshot(name);
}
