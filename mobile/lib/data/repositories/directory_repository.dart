// =========================================================================
// دليل الموظفين: قائمة الزملاء من دالة get_employee_directory (أعمدة غير حساسة فقط).
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';

class DirectoryRepository {
  DirectoryRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  Future<List<DirectoryEntry>> fetchDirectory() async {
    final dynamic data = await _db.rpc<dynamic>('get_employee_directory');
    return (data as List<dynamic>).map((e) => DirectoryEntry.fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }
}
