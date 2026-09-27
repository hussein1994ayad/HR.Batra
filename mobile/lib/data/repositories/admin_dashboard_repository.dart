// =========================================================================
// بيانات لوحة الإدارة: ملخص الحضور، الطلبات المعلقة، سجل الأمان، والقرارات
// =========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logic/attendance_rules.dart';
import '../../core/models/models.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/arabic_format.dart';

class DashboardFilter {
  final String branchId;
  final String employeeId;

  /// null = اليوم بدون عرض القرارات
  final DateTime? date;

  const DashboardFilter({this.branchId = 'all', this.employeeId = 'all', this.date});

  bool get isScoped => branchId != 'all' || employeeId != 'all';
  bool get isActive => isScoped || date != null;
}

class DashboardEmployee {
  final String id;
  final String fullName;
  final String? branchId;
  final String? departmentId;
  final bool isActive;

  const DashboardEmployee({
    required this.id,
    required this.fullName,
    this.branchId,
    this.departmentId,
    this.isActive = true,
  });

  factory DashboardEmployee.fromMap(JsonRow map) => DashboardEmployee(
        id: map.str('id') ?? '',
        fullName: map.str('full_name') ?? 'موظف',
        branchId: map.str('branch_id'),
        departmentId: map.str('department_id'),
        isActive: map.boolean('is_active') ?? true,
      );
}

class DashboardLookups {
  final List<BranchModel> branches;
  final List<DashboardEmployee> employees;
  const DashboardLookups({required this.branches, required this.employees});
}

class DashboardSnapshot {
  final int present;
  final int absent;
  final List<LeaveRequestModel> leaves;
  final List<LoanModel> loans;
  final List<DeviceRequest> devices;
  final List<SecurityLog> securityLogs;
  final List<PendingDecision> decisions;
  final List<WorkScheduleModel> schedules;

  const DashboardSnapshot({
    this.present = 0,
    this.absent = 0,
    this.leaves = const [],
    this.loans = const [],
    this.devices = const [],
    this.securityLogs = const [],
    this.decisions = const [],
    this.schedules = const [],
  });
}

class AdminDashboardRepository {
  AdminDashboardRepository({SupabaseClient? client}) : _db = client ?? SupabaseService.client;
  final SupabaseClient _db;

  Future<DashboardLookups> loadLookups() async {
    final results = await Future.wait<Object?>([
      _db.from('branches').select('id, name').order('name'),
      _db.from('employees').select('id, full_name, branch_id, department_id, is_active').order('full_name'),
    ]);
    return DashboardLookups(
      branches: rowsOf(results[0]).map(BranchModel.fromMap).toList(),
      employees: rowsOf(results[1]).map(DashboardEmployee.fromMap).toList(),
    );
  }

  /// الموظفون النشطون ضمن الفلتر.
  static List<DashboardEmployee> scopedEmployees(List<DashboardEmployee> all, DashboardFilter filter) => all.where((e) {
        if (!e.isActive) return false;
        if (filter.employeeId != 'all') return e.id == filter.employeeId;
        if (filter.branchId != 'all') return e.branchId == filter.branchId;
        return true;
      }).toList();

  Future<DashboardSnapshot> loadSnapshot(DashboardFilter filter, List<DashboardEmployee> allEmployees) async {
    final employees = scopedEmployees(allEmployees, filter);
    // inFilter بقائمة فارغة يرجع كل الصفوف في بعض الإصدارات؛ معرّف وهمي يضمن نتيجة فارغة
    final ids = employees.isEmpty ? ['00000000-0000-0000-0000-000000000000'] : employees.map((e) => e.id).toList();
    final day = filter.date ?? DateTime.now();
    final dayStr = isoDate(day);
    final dayStart = DateTime(day.year, day.month, day.day).toUtc().toIso8601String();
    final dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59).toUtc().toIso8601String();
    final date = filter.date;

    PostgrestFilterBuilder<List<Map<String, dynamic>>> scoped(PostgrestFilterBuilder<List<Map<String, dynamic>>> q) =>
        filter.isScoped ? q.inFilter('employee_id', ids) : q;
    PostgrestFilterBuilder<List<Map<String, dynamic>>> inDay(
            PostgrestFilterBuilder<List<Map<String, dynamic>>> q, String column) =>
        date == null ? q : q.gte(column, dayStart).lte(column, dayEnd);

    var leaves = scoped(_db
        .from('leave_requests')
        .select('*, employees!leave_requests_employee_id_fkey!inner(full_name)')
        .eq('status', 'pending'));
    if (date != null) leaves = leaves.lte('start_date', dayEnd).gte('end_date', dayStart);

    final results = await Future.wait<Object?>([
      scoped(_db.from('attendance').select('status, employee_id').eq('work_date', dayStr)),
      leaves,
      inDay(scoped(_db.from('loans').select('*, employees!loans_employee_id_fkey!inner(full_name, monthly_salary_iqd)')
          .eq('status', 'pending')), 'created_at'),
      inDay(scoped(_db.from('employee_devices').select('*, employees!inner(full_name)').eq('is_approved', false)), 'created_at'),
      inDay(scoped(_db.from('mock_gps_attempts').select('*, employees!inner(full_name)')), 'timestamp')
          .order('timestamp', ascending: false).limit(15),
      inDay(scoped(_db.from('geofence_violations').select('*, employees!inner(full_name)')), 'timestamp')
          .order('timestamp', ascending: false).limit(15),
      _db.from('work_schedules').select(),
      // إجازات معتمدة تغطي اليوم (لا يُحسب صاحبها غائباً)
      scoped(_db.from('leave_requests').select('employee_id').eq('status', 'approved')
          .lte('start_date', dayEnd).gte('end_date', dayStart)),
      if (date != null)
        scoped(_db.from('attendance').select('*, employees!inner(full_name, branch_id)')
            .inFilter('status', ['absent', 'late', 'half_day'])
            .or('deduction_status.is.null,deduction_status.eq.pending')
            .eq('work_date', dayStr)),
    ]);

    final attendance = rowsOf(results[0]);
    final schedules = rowsOf(results[6]).map(WorkScheduleModel.fromMap).toList();
    final onLeave = rowsOf(results[7]).map((r) => r.str('employee_id') ?? '').toSet();

    final summary = summarizeDay(
      date: day,
      employees: [for (final e in employees) (id: e.id, departmentId: e.departmentId, branchId: e.branchId)],
      statusByEmployee: {for (final r in attendance) r.str('employee_id') ?? '': r.str('status') ?? ''},
      onLeave: onLeave,
      schedules: schedules,
    );

    final securityLogs = [
      ...rowsOf(results[4]).map(SecurityLog.fromMockAttempt),
      ...rowsOf(results[5]).map(SecurityLog.fromGeofenceViolation),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final decisions = <PendingDecision>[];
    if (date != null) {
      decisions.addAll(rowsOf(results[8]).map(PendingDecision.fromAttendance));
      final byId = {for (final e in employees) e.id: e};
      for (final id in summary.missingEmployeeIds) {
        final emp = byId[id]!;
        decisions.add(PendingDecision(
          employeeId: emp.id,
          employeeName: emp.fullName,
          branchId: emp.branchId,
          status: 'absent',
          workDate: dayStr,
        ));
      }
    }

    return DashboardSnapshot(
      present: summary.present,
      absent: summary.absent,
      leaves: rowsOf(results[1]).map(LeaveRequestModel.fromMap).toList(),
      loans: rowsOf(results[2]).map(LoanModel.fromMap).toList(),
      devices: rowsOf(results[3]).map(DeviceRequest.fromMap).toList(),
      securityLogs: securityLogs,
      decisions: decisions,
      schedules: schedules,
    );
  }
}
