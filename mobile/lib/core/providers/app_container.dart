// =========================================================================
// HR Pro v6.0 - Global Provider Container
// =========================================================================
// حاوية Riverpod الرئيسية تُنشأ في main() وتُشارك بين:
//   • واجهة المستخدم عبر UncontrolledProviderScope(container: appContainer)
//   • الخدمات الثابتة (AuthService, LocationService, ...) لكتابة الحالة
//     من خارج شجرة الويدجت بدون Context
//
// الاستخدام من خدمة (خارج ويدجت):
//   appContainer.read(currentUserRoleProvider.notifier).state = 'admin';
//
// الاستخدام من ويدجت:
//   final role = ref.watch(currentUserRoleProvider);
// =========================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

final ProviderContainer appContainer = ProviderContainer();
