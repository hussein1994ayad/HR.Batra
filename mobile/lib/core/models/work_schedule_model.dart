// =========================================================================
// نموذج جدول الدوام — الجدول: public.work_schedules
// =========================================================================

import '../utils/json_map.dart';

/// أيام الأسبوع بترقيم قاعدة البيانات (0 = الأحد ... 6 = السبت).
const List<String> kArabicWeekdays = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

/// دوام السبت إلى الخميس عند عدم وجود جدول.
const List<int> kDefaultWorkDays = [6, 0, 1, 2, 3, 4];

/// ترقيم قاعدة البيانات من DateTime.weekday في Dart (الاثنين = 1 ... الأحد = 7).
int dbWeekday(DateTime date) => date.weekday % 7;

class WorkScheduleModel {
  final String id;
  final String name;
  final String? employeeId;
  final String? departmentId;
  final String? branchId;

  /// "HH:MM:SS"
  final String checkInTime;
  final String checkOutTime;
  final int gracePeriodMinutes;
  final List<int> workDays;
  final DateTime? createdAt;

  const WorkScheduleModel({
    required this.id,
    required this.name,
    required this.checkInTime,
    required this.checkOutTime,
    this.employeeId,
    this.departmentId,
    this.branchId,
    this.gracePeriodMinutes = 15,
    this.workDays = kDefaultWorkDays,
    this.createdAt,
  });

  factory WorkScheduleModel.fromMap(JsonRow map) => WorkScheduleModel(
        id: map.str('id') ?? '',
        name: map.str('name') ?? '',
        employeeId: map.str('employee_id'),
        departmentId: map.str('department_id'),
        branchId: map.str('branch_id'),
        checkInTime: map.str('check_in_time') ?? '09:00:00',
        checkOutTime: map.str('check_out_time') ?? '17:00:00',
        gracePeriodMinutes: map.integer('grace_period_minutes') ?? 15,
        workDays: map['work_days'] is List ? map.ints('work_days') : kDefaultWorkDays,
        createdAt: map.date('created_at'),
      );

  /// دقائق منذ منتصف الليل لوقت "HH:MM[:SS]".
  static int minutesOf(String time) {
    final parts = time.split(':');
    return (int.tryParse(parts[0]) ?? 0) * 60 + (parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
  }

  int get checkInMinutes => minutesOf(checkInTime);
  int get checkOutMinutes => minutesOf(checkOutTime);
  bool worksOn(DateTime date) => workDays.contains(dbWeekday(date));
}
