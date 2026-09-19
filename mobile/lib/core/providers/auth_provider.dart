// =========================================================================
// HR Pro v6.0 - Riverpod providers for authentication state
// =========================================================================
// المزوّدات هذه هي المصدر الوحيد للحقيقة (single source of truth)
// لدور المستخدم الحالي في الطبقة العليا (Presentation).
//
// AuthService لا يزال يحتفظ بحقل static currentUserRole للتوافق مع
// الكود القديم (app_router على وجه الخصوص)، لكن الشاشات الجديدة يجب
// أن تستهلك عبر Riverpod بدلاً من ذلك:
//
//   class SettingsScreen extends ConsumerWidget {
//     Widget build(BuildContext c, WidgetRef ref) {
//       final role = ref.watch(currentUserRoleProvider);
//       final isAdmin = role == 'admin' || role == 'manager';
//       ...
//     }
//   }
//
// الأدوار المعتمدة: 'admin', 'manager', 'employee'.
// =========================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// دور المستخدم الحالي (null إذا غير مسجّل دخول).
final currentUserRoleProvider = StateProvider<String?>((ref) => null);

/// اختصار: هل المستخدم أدمن؟
final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(currentUserRoleProvider) == 'admin';
});

/// اختصار: هل المستخدم مدير أو أدمن؟ (صلاحيات وسيطة)
final isManagerOrAdminProvider = Provider<bool>((ref) {
  final role = ref.watch(currentUserRoleProvider);
  return role == 'admin' || role == 'manager';
});

/// اختصار: هل المستخدم موظف عادي فقط؟
final isEmployeeProvider = Provider<bool>((ref) {
  return ref.watch(currentUserRoleProvider) == 'employee';
});
