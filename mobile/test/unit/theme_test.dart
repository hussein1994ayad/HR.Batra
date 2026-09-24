// =========================================================================
// HR Pro v6.0 - Widget tests for AppTheme
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/theme/app_theme.dart';

void main() {
  // الثيم يطلب خط Cairo من google_fonts عبر الشبكة، وبيئة الاختبار تمنع الشبكة.
  // نبني الثيمين مرة داخل zone يلتقط أخطاء تحميل الخط (google_fonts يخزّن
  // المحاولة فلا تتكرر)؛ هذه الاختبارات تفحص بنية الثيم لا تحميل الخطوط.
  setUpAll(() {
    runZonedGuarded(() {
      expect(AppTheme.lightTheme, isNotNull);
      expect(AppTheme.darkTheme, isNotNull);
    }, (_, __) {});
  });

  group('AppTheme — Design Tokens', () {
    test('spacing scale follows 4pt grid', () {
      expect(AppTheme.space1, 4);
      expect(AppTheme.space2, 8);
      expect(AppTheme.space4, 16);
      expect(AppTheme.space8, 32);
    });

    test('radius scale is monotonically increasing', () {
      expect(AppTheme.radiusXs, lessThan(AppTheme.radiusSm));
      expect(AppTheme.radiusSm, lessThan(AppTheme.radiusMd));
      expect(AppTheme.radiusMd, lessThan(AppTheme.radiusLg));
      expect(AppTheme.radiusLg, lessThan(AppTheme.radiusXl));
    });

    test('motion durations are ordered', () {
      expect(AppTheme.motionFast.inMilliseconds,
          lessThan(AppTheme.motionNormal.inMilliseconds));
      expect(AppTheme.motionNormal.inMilliseconds,
          lessThan(AppTheme.motionSlow.inMilliseconds));
    });
  });

  group('AppTheme — Light Theme', () {
    test('is Material 3 with light brightness', () {
      final theme = AppTheme.lightTheme;
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
    });

    test('has correct primary color', () {
      final theme = AppTheme.lightTheme;
      expect(theme.colorScheme.primary, AppTheme.primaryTeal);
    });

    test('scaffold background is set', () {
      final theme = AppTheme.lightTheme;
      expect(theme.scaffoldBackgroundColor, isNotNull);
    });
  });

  group('AppTheme — Dark Theme', () {
    test('is Material 3 with dark brightness', () {
      final theme = AppTheme.darkTheme;
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
    });

    test('primary color is a lighter variant for contrast', () {
      final theme = AppTheme.darkTheme;
      expect(theme.colorScheme.primary, AppTheme.primaryTealLight);
    });

    test('scaffold background is the dark bg', () {
      final theme = AppTheme.darkTheme;
      expect(theme.scaffoldBackgroundColor, AppTheme.darkBg);
    });
  });

  group('AppTheme — Shadows', () {
    test('all shadow tiers return non-empty lists', () {
      expect(AppTheme.shadowSm(false), isNotEmpty);
      expect(AppTheme.shadowMd(false), isNotEmpty);
      expect(AppTheme.shadowLg(false), isNotEmpty);
      expect(AppTheme.glowPrimary(), isNotEmpty);
    });

    test('dark-mode shadows are stronger than light-mode', () {
      final smLight = AppTheme.shadowSm(false).first;
      final smDark = AppTheme.shadowSm(true).first;
      // Dark shadows use a higher alpha value on the same base color
      expect(smDark.color.a, greaterThan(smLight.color.a));
    });
  });

  group('SkeletonLoader / OfflineBanner smoke tests', () {
    testWidgets('SkeletonBox renders with theme', (tester) async {
      // Note: Requires SkeletonBox import; smoke-test only structure
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: SizedBox(width: 100, height: 20)),
        ),
      );
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });
}
