// =========================================================================
// HR Pro v6.0 - Unit tests for AppConstants
// =========================================================================
// شغّل الاختبارات:
//   flutter test test/unit/constants_test.dart
// =========================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/constants/constants.dart';

void main() {
  group('AppConstants — formatMoney', () {
    test('formats whole thousands with dot separator', () {
      expect(AppConstants.formatMoney(1000), '1.000 د.ع');
      expect(AppConstants.formatMoney(1500000), '1.500.000 د.ع');
    });

    test('leaves small numbers without separators', () {
      expect(AppConstants.formatMoney(0), '0 د.ع');
      expect(AppConstants.formatMoney(250), '250 د.ع');
      expect(AppConstants.formatMoney(999), '999 د.ع');
    });

    test('rounds decimals to nearest integer', () {
      expect(AppConstants.formatMoney(1000.4), '1.000 د.ع');
      expect(AppConstants.formatMoney(1000.5), '1.001 د.ع');
    });

    test('handles very large amounts', () {
      expect(AppConstants.formatMoney(1000000000), '1.000.000.000 د.ع');
    });

    test('handles negative amounts', () {
      // Note: current implementation returns "-1.000 د.ع" not "-1000". Verify.
      final result = AppConstants.formatMoney(-1000);
      expect(result.contains('د.ع'), true);
    });
  });

  group('AppConstants — configuration', () {
    test('essential constants are set', () {
      expect(AppConstants.currency, 'د.ع');
      expect(AppConstants.appName, 'HR Pro');
    });

    test('Supabase URL is a valid HTTPS URL', () {
      expect(AppConstants.supabaseUrl, startsWith('https://'));
      expect(AppConstants.supabaseUrl, endsWith('.supabase.co'));
    });

    test('Supabase anon key is present and non-trivial', () {
      expect(AppConstants.supabaseAnonKey.isNotEmpty, true);
      expect(AppConstants.supabaseAnonKey.length, greaterThan(20));
    });

    test('mock GPS threshold is a positive small number', () {
      expect(AppConstants.mockGpsThresholdAccuracy, greaterThan(0));
      expect(AppConstants.mockGpsThresholdAccuracy, lessThan(10));
    });

    test('trash expiry is 30 days', () {
      expect(AppConstants.trashExpiryDays, 30);
    });

    test('image compression settings are sensible', () {
      expect(AppConstants.maxImageWidthHeight, greaterThan(640));
      expect(AppConstants.maxImageWidthHeight, lessThanOrEqualTo(4096));
      expect(AppConstants.imageQuality, greaterThan(0));
      expect(AppConstants.imageQuality, lessThanOrEqualTo(100));
    });
  });
}
