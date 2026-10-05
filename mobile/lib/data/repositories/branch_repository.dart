// =========================================================================
// الأفرع (النطاق الجغرافي للبصمة) وأوقات دوامها: القائمة، الإضافة والتعديل والحذف،
// وجداول الدوام على مستوى الفرع (بدون موظف أو قسم).
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';

class BranchRepository {
  BranchRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// كل الأفرع بكل أعمدتها مرتبة بالاسم.
  Future<List<BranchModel>> fetchAll() async {
    return List<Map<String, dynamic>>.from(await _db.from('branches').select().order('name')).map(BranchModel.fromMap).toList();
  }

  Future<void> create(Map<String, dynamic> data) async {
    await _db.from('branches').insert(data);
  }

  Future<void> update(Object id, Map<String, dynamic> data) async {
    await _db.from('branches').update(data).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _db.from('branches').delete().eq('id', id);
  }

  /// [الأفرع (id, name)، جداول الدوام على مستوى الفرع] بالتوازي.
  Future<List<dynamic>> fetchBranchesWithSchedules() {
    return Future.wait([
      _db.from('branches').select('id, name').order('name'),
      _db.from('work_schedules').select().isFilter('employee_id', null).isFilter('department_id', null).not('branch_id', 'is', null),
    ]);
  }

  /// إضافة جدول دوام فرع، أو تعديله إذا [scheduleId] موجود.
  Future<void> saveBranchSchedule(Map<String, dynamic> row, {Object? scheduleId}) async {
    if (scheduleId != null) {
      await _db.from('work_schedules').update(row).eq('id', scheduleId);
    } else {
      await _db.from('work_schedules').insert(row);
    }
  }
}
