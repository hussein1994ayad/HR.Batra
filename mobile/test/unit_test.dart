// =========================================================================
// نظام HR Pro v6.0 - اختبارات الوحدة للحسابات والثوابت (Unit Tests)
// =========================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/constants/constants.dart';

void main() {
  group('AppConstants Tests', () {
    test('formatMoney formats amounts with dot separators correctly', () {
      expect(AppConstants.formatMoney(1000), '1.000 د.ع');
      expect(AppConstants.formatMoney(1500000), '1.500.000 د.ع');
      expect(AppConstants.formatMoney(250), '250 د.ع');
    });

    test('Constants are configured properly', () {
      expect(AppConstants.currency, 'د.ع');
      expect(AppConstants.appName, 'HR Pro');
      expect(AppConstants.supabaseUrl.isNotEmpty, true);
      expect(AppConstants.supabaseAnonKey.isNotEmpty, true);
    });
  });
}
