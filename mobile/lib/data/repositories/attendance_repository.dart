// =========================================================================
// شاشة البصمة وسجل الدوام: فرع الموظف (موقعه ونطاقه)، سجل اليوم، وآخر الأيام.
// البصمة نفسها تمر بـ AttendanceSyncService (RPC punch_attendance + طابور بدون إنترنت).
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/arabic_format.dart';

class AttendanceRepository {
  AttendanceRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// فرع الموظف وقسمه مع موقع الفرع ونطاقه (لرسم الدائرة وفحص المسافة قبل البصمة).
  /// null = الموظف بدون فرع.
  Future<BranchModel?> fetchEmployeeBranch(String userId) async {
    final row = await _db
        .from('employees')
        .select('branch_id, department_id, branches(id, name, latitude, longitude, radius_meters)')
        .eq('id', userId)
        .maybeSingle();
    final branch = row?.obj('branches');
    return branch == null ? null : BranchModel.fromMap(branch);
  }

  Future<AttendanceModel?> fetchTodayAttendance(String userId, String todayStr) async {
    final row = await _db.from('attendance').select().eq('employee_id', userId).eq('work_date', todayStr).maybeSingle();
    return row == null ? null : AttendanceModel.fromMap(row);
  }

  /// سجل الأيام السابقة (بدون اليوم) من الأحدث للأقدم.
  Future<List<AttendanceModel>> fetchRecentHistory(String userId, {required DateTime today, required int days}) async {
    final data = await _db
        .from('attendance')
        .select('work_date, check_in_time, check_out_time, status')
        .eq('employee_id', userId)
        .gte('work_date', isoDate(today.subtract(Duration(days: days))))
        .lt('work_date', isoDate(today))
        .order('work_date', ascending: false);
    return List<Map<String, dynamic>>.from(data).map(AttendanceModel.fromMap).toList();
  }
}
