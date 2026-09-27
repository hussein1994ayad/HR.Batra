// =========================================================================
// قواعد الحضور المشتركة — دوال نقية بدون Supabase أو Flutter
// =========================================================================
// نفس قواعد لوحة الويب (web/src/lib/schedules.ts و features/*/logic.ts)
// حتى تعطي الشاشتان نفس الأرقام.
// =========================================================================

import '../models/work_schedule_model.dart';

/// الغرامة المقترحة لكل دقيقة تأخير، وليوم الغياب (د.ع).
const double kLatePenaltyPerMinute = 50;
const double kAbsencePenalty = 25000;

/// جدول الدوام الفعلي: جدول الموظف ← جدول قسمه ← جدول فرعه، والأحدث عند التساوي.
WorkScheduleModel? resolveWorkSchedule({
  required String employeeId,
  String? departmentId,
  String? branchId,
  required List<WorkScheduleModel> schedules,
}) {
  final list = [...schedules]
    ..sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
  for (final s in list) {
    if (s.employeeId == employeeId) return s;
  }
  for (final s in list) {
    if (s.employeeId == null && s.departmentId != null && s.departmentId == departmentId) return s;
  }
  for (final s in list) {
    if (s.employeeId == null && s.departmentId == null && s.branchId != null && s.branchId == branchId) return s;
  }
  return null;
}

/// دقائق التأخير عن بداية الدوام (09:00 بدون جدول). لا تُطرح فترة السماح، مثل الويب.
int lateMinutes(DateTime checkIn, WorkScheduleModel? schedule) {
  final start = schedule?.checkInMinutes ?? 9 * 60;
  final actual = checkIn.hour * 60 + checkIn.minute;
  return actual > start ? actual - start : 0;
}

/// دقائق الخروج المبكر قبل نهاية الدوام (17:00 بدون جدول).
int earlyLeaveMinutes(DateTime checkOut, WorkScheduleModel? schedule) {
  final end = schedule?.checkOutMinutes ?? 17 * 60;
  final actual = checkOut.hour * 60 + checkOut.minute;
  return actual < end ? end - actual : 0;
}

/// هل اليوم يوم دوام للموظف حسب جدوله (السبت-الخميس بدون جدول)؟
bool isWorkingDay(DateTime date, WorkScheduleModel? schedule) =>
    (schedule?.workDays ?? kDefaultWorkDays).contains(dbWeekday(date));

class DaySummary {
  final int present;
  final int absent;

  /// موظفون بلا أي سجل ولا إجازة في يوم دوامهم
  final List<String> missingEmployeeIds;

  const DaySummary({required this.present, required this.absent, required this.missingEmployeeIds});
}

/// ملخص حضور يوم: الحاضر (حاضر/متأخر/نصف يوم)، والغائب = سجل غياب في يوم دوام
/// أو موظف بلا سجل وبلا إجازة معتمدة واليوم من أيام دوامه.
DaySummary summarizeDay({
  required DateTime date,
  required List<({String id, String? departmentId, String? branchId})> employees,
  required Map<String, String> statusByEmployee,
  required Set<String> onLeave,
  required List<WorkScheduleModel> schedules,
}) {
  int present = 0;
  int absent = 0;
  final missing = <String>[];
  for (final emp in employees) {
    final schedule = resolveWorkSchedule(
      employeeId: emp.id, departmentId: emp.departmentId, branchId: emp.branchId, schedules: schedules);
    final status = statusByEmployee[emp.id];
    if (status == 'present' || status == 'late' || status == 'half_day') {
      present++;
    } else if (!isWorkingDay(date, schedule)) {
      continue;
    } else if (status == 'absent') {
      absent++;
    } else if (status == null && !onLeave.contains(emp.id)) {
      absent++;
      missing.add(emp.id);
    }
  }
  return DaySummary(present: present, absent: absent, missingEmployeeIds: missing);
}

/// مبلغ الخصم المقترح لقرار (غياب ثابت، تأخير/نصف يوم بالدقيقة).
double suggestedPenalty(String status, int missedMinutes) =>
    status == 'absent' ? kAbsencePenalty : missedMinutes * kLatePenaltyPerMinute;
