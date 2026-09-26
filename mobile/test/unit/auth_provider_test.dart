// =========================================================================
// HR Pro v6.0 - Unit tests for auth providers
// =========================================================================
// شغّل:
//   flutter test test/unit/auth_provider_test.dart
// =========================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/providers/auth_provider.dart';

void main() {
  group('currentUserRoleProvider', () {
    test('defaults to null when unauthenticated', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(currentUserRoleProvider), isNull);
    });

    test('can be set to admin', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(currentUserRoleProvider.notifier).state = 'admin';
      expect(container.read(currentUserRoleProvider), 'admin');
    });

    test('can be cleared to null on signOut', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(currentUserRoleProvider.notifier).state = 'employee';
      container.read(currentUserRoleProvider.notifier).state = null;
      expect(container.read(currentUserRoleProvider), isNull);
    });
  });

  group('isAdminProvider', () {
    test('is false when role is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(isAdminProvider), isFalse);
    });

    test('is true when role is admin', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(currentUserRoleProvider.notifier).state = 'admin';

      expect(container.read(isAdminProvider), isTrue);
    });

    test('is false for manager', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(currentUserRoleProvider.notifier).state = 'manager';

      expect(container.read(isAdminProvider), isFalse);
    });

    test('is false for employee', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(currentUserRoleProvider.notifier).state = 'employee';

      expect(container.read(isAdminProvider), isFalse);
    });
  });

  group('isManagerOrAdminProvider', () {
    test('is true for both admin and manager', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(currentUserRoleProvider.notifier).state = 'admin';
      expect(container.read(isManagerOrAdminProvider), isTrue);

      container.read(currentUserRoleProvider.notifier).state = 'manager';
      expect(container.read(isManagerOrAdminProvider), isTrue);
    });

    test('is false for employee and null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(currentUserRoleProvider.notifier).state = 'employee';
      expect(container.read(isManagerOrAdminProvider), isFalse);

      container.read(currentUserRoleProvider.notifier).state = null;
      expect(container.read(isManagerOrAdminProvider), isFalse);
    });
  });

  group('isEmployeeProvider', () {
    test('is true only for exact employee role', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(currentUserRoleProvider.notifier).state = 'employee';
      expect(container.read(isEmployeeProvider), isTrue);

      container.read(currentUserRoleProvider.notifier).state = 'admin';
      expect(container.read(isEmployeeProvider), isFalse);
    });
  });
}
