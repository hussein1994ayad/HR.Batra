// =========================================================================
// HR Pro — اختبارات نظام التصميم (الرموز، الثيم الداكن، التباين)
// =========================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/design/design.dart';
import 'package:hr_pro/core/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('Design tokens', () {
    test('spacing follows the 4pt grid', () {
      for (final v in [AppSpace.xs, AppSpace.sm, AppSpace.md, AppSpace.lg, AppSpace.xl, AppSpace.xxl, AppSpace.x3, AppSpace.x4, AppSpace.x5]) {
        expect(v % 4, 0, reason: '$v is not on the 4pt grid');
      }
      expect(AppSpace.touch, greaterThanOrEqualTo(48));
    });

    test('radius and motion scales are ordered', () {
      expect(AppRadius.xs, lessThan(AppRadius.sm));
      expect(AppRadius.sm, lessThan(AppRadius.md));
      expect(AppRadius.md, lessThan(AppRadius.lg));
      expect(AppRadius.lg, lessThan(AppRadius.xl));
      expect(AppMotion.fast, lessThan(AppMotion.normal));
      expect(AppMotion.normal, lessThan(AppMotion.slow));
      expect(AppMotion.slow.inMilliseconds, lessThanOrEqualTo(300));
    });

    test('breakpoints match Material window size classes', () {
      expect(AppBreakpoints.medium, 600);
      expect(AppBreakpoints.expanded, 840);
    });
  });

  group('Contrast (WCAG AA)', () {
    const surfaces = {'bg': AppColors.bg, 'surface1': AppColors.surface1, 'surface2': AppColors.surface2};
    const texts = {
      'textPrimary': AppColors.textPrimary,
      'textSecondary': AppColors.textSecondary,
      'textMuted': AppColors.textMuted,
      'brand': AppColors.brand,
      'success': AppColors.success,
      'warning': AppColors.warning,
      'danger': AppColors.danger,
      'info': AppColors.info,
      'accent': AppColors.accent,
    };
    surfaces.forEach((sName, s) {
      texts.forEach((tName, t) {
        test('$tName on $sName ≥ 4.5', () => expect(_contrast(t, s), greaterThanOrEqualTo(4.5)));
      });
    });
    for (final tone in AppTone.values) {
      test('${tone.name} text on its container ≥ 4.5', () {
        expect(_contrast(tone.color, tone.container), greaterThanOrEqualTo(4.5));
      });
    }
    test('onBrand on brand ≥ 4.5', () => expect(_contrast(AppColors.onBrand, AppColors.brand), greaterThanOrEqualTo(4.5)));
    test('onStatus on status fills ≥ 4.5', () {
      for (final c in [AppColors.success, AppColors.warning, AppColors.danger, AppColors.info]) {
        expect(_contrast(AppColors.onStatus, c), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('AppTheme (dark only)', () {
    final theme = AppTheme.darkTheme;
    test('is Material 3, dark, built from tokens', () {
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, AppColors.brand);
      expect(theme.scaffoldBackgroundColor, AppColors.bg);
      expect(theme.textTheme.bodyLarge?.fontFamily, AppText.family);
    });

    test('buttons meet the 48dp touch target', () {
      final min = theme.filledButtonTheme.style!.minimumSize!.resolve({})!;
      expect(min.height, greaterThanOrEqualTo(48));
    });
  });

  group('Formatters', () {
    test('IQD uses dot thousands and the dinar unit', () {
      expect(Fmt.iqd(1500000), '1.500.000 د.ع');
      expect(Fmt.iqd(-25000), '-25.000 د.ع');
      expect(Fmt.iqd(null), '0 د.ع');
    });

    test('relative time in Arabic', () {
      final now = DateTime(2026, 9, 26, 12);
      expect(Fmt.relative(now.subtract(const Duration(seconds: 20)), now: now), 'الآن');
      expect(Fmt.relative(now.subtract(const Duration(minutes: 5)), now: now), 'قبل 5 دقائق');
      expect(Fmt.relative(now.subtract(const Duration(hours: 2)), now: now), 'قبل ساعتين');
      expect(Fmt.relative(now.subtract(const Duration(days: 1)), now: now), 'أمس');
      expect(Fmt.relative(now.subtract(const Duration(days: 30)), now: now), startsWith('27 آب'));
    });

    test('time, dates and greeting', () {
      expect(Fmt.timeOfDay('08:05:00'), '8:05 ص');
      expect(Fmt.timeOfDay('16:30:00'), '4:30 م');
      expect(Fmt.date(DateTime(2026, 9, 26)), '26 أيلول');
      expect(Fmt.days(1), 'يوم واحد');
      expect(Fmt.days(2), 'يومين');
      expect(Fmt.days(3), '3 أيام');
      expect(Fmt.greeting(DateTime(2026, 1, 1, 8)), 'صباح الخير');
      expect(Fmt.greeting(DateTime(2026, 1, 1, 20)), 'مساء الخير');
    });
  });
}
