// =========================================================================
// تقرير الحضور اليومي للإدارة: القوائم (الفروع، الموظفون، الجداول، سياسة الإجازات)،
// سجلات الحضور بصفحات، الإجازات المعتمدة، العطل الرسمية، وتعديل أوقات سجل.
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';

class AttendanceReportRepository {
  AttendanceReportRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// [الفروع، الموظفون، جداول الدوام، صف leave_policy] بالتوازي.
  Future<List<dynamic>> fetchLookups() {
    return Future.wait<dynamic>([
      _db.from('branches').select('id, name').order('name'),
      _db.from('employees').select('id, full_name, employee_code, branch_id, department_id, join_date, is_active').order('full_name'),
      _db.from('work_schedules').select(),
      _db.from('system_settings').select('value').eq('key', 'leave_policy').maybeSingle(),
    ]);
  }

  /// الصفحات تضمن جلب كل السجلات حتى لو تجاوزت حدّ 1000 سطر لكل طلب
  Future<List<Map<String, dynamic>>> fetchAttendance(List<String> employeeIds, {required String from, required String to}) async {
    final attendanceRows = <Map<String, dynamic>>[];
    for (var offset = 0;; offset += 1000) {
      final page = await _db
          .from('attendance')
          .select('id, employee_id, check_in_time, check_out_time, check_in_lat, check_in_lng, check_out_lat, check_out_lng, status, work_date')
          .inFilter('employee_id', employeeIds)
          .gte('work_date', from)
          .lte('work_date', to)
          .order('work_date')
          .range(offset, offset + 999);
      attendanceRows.addAll(rowsOf(page));
      if (page.length < 1000) break;
    }
    return attendanceRows;
  }

  /// الإجازات المعتمدة التي تتقاطع مع الفترة.
  Future<List<Map<String, dynamic>>> fetchApprovedLeaves(List<String> employeeIds, {required DateTime from, required DateTime to}) async {
    return rowsOf(await _db
        .from('leave_requests')
        .select('employee_id, start_date, end_date, leave_type, is_hourly, is_paid, start_hour, end_hour')
        .eq('status', 'approved')
        .inFilter('employee_id', employeeIds)
        .lte('start_date', DateTime(to.year, to.month, to.day, 23, 59, 59).toUtc().toIso8601String())
        .gte('end_date', from.toUtc().toIso8601String()));
  }

  Future<List<Map<String, dynamic>>> fetchHolidays({required String from, required String to}) async {
    return rowsOf(await _db.from('official_holidays').select('holiday_date, name').gte('holiday_date', from).lte('holiday_date', to));
  }

  Future<void> updateAttendanceTimes(String recordId, Map<String, dynamic> updates) async {
    await _db.from('attendance').update(updates).eq('id', recordId);
  }
}
