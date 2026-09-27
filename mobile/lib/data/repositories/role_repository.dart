// =========================================================================
// دور المستخدم الحالي من جدول employees (لحماية شاشات الإدارة)
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';

class RoleRepository {
  RoleRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// 'admin' | 'manager' | 'employee'، أو null بدون جلسة.
  Future<String?> currentRole() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    final row = rowOf(await _db.from('employees').select('role').eq('id', user.id).maybeSingle());
    return row?.str('role');
  }

  Future<bool> isAdminOrManager() async {
    final role = await currentRole();
    return role == 'admin' || role == 'manager';
  }
}
