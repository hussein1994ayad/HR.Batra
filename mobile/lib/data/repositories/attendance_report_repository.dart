// =========================================================================
// تقرير الحضور اليومي للإدارة: القوائم (الفروع، الموظفون، الجداول، سياسة الإجازات)،
// سجلات الحضور بصفحات، الإجازات المعتمدة، العطل الرسمية، وتعديل أوقات سجل.
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logic/attendance_report.dart';
import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';

/// قوائم التقرير: الأفرع، الموظفون، جداول الدوام، وأسماء أنواع الإجازات من السياسة ("إجازة <الاسم>").
class ReportLookups {
  const ReportLookups({required this.branches, required this.employees, required this.schedules, required this.leaveTypeNames});
  final List<BranchModel> branches;
  final List<EmployeeRef> employees;
  final List<WorkScheduleModel> schedules;
  final Map<String, String> leaveTypeNames;
}

class AttendanceReportRepository {
  AttendanceReportRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  /// الفروع، الموظفون، جداول الدوام، وسياسة الإجازات — بالتوازي.
  Future<ReportLookups> fetchLookups() async {
    final results = await Future.wait<dynamic>([
      _db.from('branches').select('id, name').order('name'),
      _db.from('employees').select('id, full_name, employee_code, branch_id, department_id, join_date, is_active').order('full_name'),
      _db.from('work_schedules').select(),
      _db.from('system_settings').select('value').eq('key', 'leave_policy').maybeSingle(),
    ]);
    final types = rowOf(results[3])?['value'] is Map ? (rowOf(results[3])!['value'] as Map)['active_types'] : null;
    return ReportLookups(
      branches: List<Map<String, dynamic>>.from(results[0] as Iterable<dynamic>).map(BranchModel.fromMap).toList(),
      employees: List<Map<String, dynamic>>.from(results[1] as Iterable<dynamic>).map(EmployeeRef.fromMap).toList(),
      schedules: rowsOf(results[2]).map(WorkScheduleModel.fromMap).toList(),
      leaveTypeNames: {
        if (types is List)
          for (final t in types)
            if (t is Map && t['id'] != null) t['id'].toString(): 'إجازة ${t['name'].toString().replaceFirst(RegExp(r'^إجازة\s*'), '')}',
      },
    );
  }

  /// الصفحات تضمن جلب كل السجلات حتى لو تجاوزت حدّ 1000 سطر لكل طلب
  Future<List<ReportAttendance>> fetchAttendance(List<String> employeeIds, {required String from, required String to}) async {
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
    return [
      for (final a in attendanceRows)
        ReportAttendance(
          id: a.str('id') ?? '',
          employeeId: a.str('employee_id') ?? '',
          date: DateTime.parse(a.str('work_date')!),
          status: a.str('status') ?? 'present',
          checkIn: a.date('check_in_time'),
          checkOut: a.date('check_out_time'),
          checkInLat: a.dbl('check_in_lat'),
          checkInLng: a.dbl('check_in_lng'),
          checkOutLat: a.dbl('check_out_lat'),
          checkOutLng: a.dbl('check_out_lng'),
        ),
    ];
  }

  /// الإجازات المعتمدة التي تتقاطع مع الفترة؛ اسم النوع من [typeNames] (السياسة) وإلا الاسم الثابت.
  Future<List<ReportLeave>> fetchApprovedLeaves(
    List<String> employeeIds, {
    required DateTime from,
    required DateTime to,
    required Map<String, String> typeNames,
  }) async {
    final leaveRows = rowsOf(await _db
        .from('leave_requests')
        .select('employee_id, start_date, end_date, leave_type, is_hourly, is_paid, start_hour, end_hour')
        .eq('status', 'approved')
        .inFilter('employee_id', employeeIds)
        .lte('start_date', DateTime(to.year, to.month, to.day, 23, 59, 59).toUtc().toIso8601String())
        .gte('end_date', from.toUtc().toIso8601String()));

    String hhmm(Object? t) => t == null ? '' : t.toString().substring(0, t.toString().length >= 5 ? 5 : t.toString().length);

    return [
      for (final l in leaveRows)
        if (l.date('start_date') != null && l.date('end_date') != null)
          ReportLeave(
            employeeId: l.str('employee_id') ?? '',
            from: l.date('start_date')!,
            to: l.date('end_date')!,
            typeName: typeNames[l.str('leave_type')] ?? leaveTypeArabic(l.str('leave_type')),
            isHourly: l.boolean('is_hourly') ?? false,
            isPaid: l.boolean('is_paid') ?? true,
            startHour: hhmm(l['start_hour']),
            endHour: hhmm(l['end_hour']),
          ),
    ];
  }

  /// العطل الرسمية بالفترة: التاريخ → الاسم (أو «عطلة»).
  Future<Map<DateTime, String>> fetchHolidays({required String from, required String to}) async {
    final holidayRows = rowsOf(await _db.from('official_holidays').select('holiday_date, name').gte('holiday_date', from).lte('holiday_date', to));
    return {
      for (final h in holidayRows)
        if (DateTime.tryParse(h.str('holiday_date') ?? '') != null) DateTime.parse(h.str('holiday_date')!): h.str('name') ?? 'عطلة',
    };
  }

  Future<void> updateAttendanceTimes(String recordId, Map<String, dynamic> updates) async {
    await _db.from('attendance').update(updates).eq('id', recordId);
  }
}
