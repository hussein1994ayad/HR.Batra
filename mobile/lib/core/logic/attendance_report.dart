// =========================================================================
// تقرير الحضور اليومي — دالة نقية بدون Supabase أو Flutter
// =========================================================================
// لكل موظف ولكل يوم في الفترة سطر واحد: حاضر / متأخر / خروج مبكر / غائب /
// مجاز (مع نوع الإجازة) / عطلة. الإجازة الزمنية تظهر ملاحظة على يوم الموظف.
// =========================================================================

import '../models/work_schedule_model.dart';
import 'attendance_rules.dart';

enum ReportStatus { present, late, earlyLeave, absent, leave, dayOff }

extension ReportStatusText on ReportStatus {
  String get arabic => switch (this) {
        ReportStatus.present => 'حاضر',
        ReportStatus.late => 'متأخر',
        ReportStatus.earlyLeave => 'خروج مبكر',
        ReportStatus.absent => 'غائب',
        ReportStatus.leave => 'مجاز',
        ReportStatus.dayOff => 'عطلة',
      };

  /// حضر فعلاً (حاضر أو متأخر أو خرج مبكراً).
  bool get attended => this == ReportStatus.present || this == ReportStatus.late || this == ReportStatus.earlyLeave;
}

class ReportEmployee {
  final String id;
  final String name;
  final String code;
  final String? branchId;
  final String? departmentId;
  final String branchName;

  /// لا تُحسب الأيام قبل المباشرة
  final DateTime? joinDate;

  const ReportEmployee({
    required this.id,
    required this.name,
    this.code = '',
    this.branchId,
    this.departmentId,
    this.branchName = '',
    this.joinDate,
  });
}

class ReportAttendance {
  final String id;
  final String employeeId;
  final DateTime date;

  /// present | late | absent | half_day
  final String status;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final double? checkInLat, checkInLng, checkOutLat, checkOutLng;

  const ReportAttendance({
    required this.id,
    required this.employeeId,
    required this.date,
    required this.status,
    this.checkIn,
    this.checkOut,
    this.checkInLat,
    this.checkInLng,
    this.checkOutLat,
    this.checkOutLng,
  });
}

class ReportLeave {
  final String employeeId;
  final DateTime from;
  final DateTime to;

  /// الاسم العربي لنوع الإجازة
  final String typeName;
  final bool isHourly;
  final bool isPaid;

  /// "HH:MM" للإجازة الزمنية
  final String? startHour;
  final String? endHour;

  const ReportLeave({
    required this.employeeId,
    required this.from,
    required this.to,
    required this.typeName,
    this.isHourly = false,
    this.isPaid = true,
    this.startHour,
    this.endHour,
  });

  bool covers(DateTime day) => !day.isBefore(_d(from)) && !day.isAfter(_d(to));

  /// "إجازة سنوية" / "إجازة مرضية (بدون راتب)" / "إجازة زمنية 10:00 - 12:00"
  String get label {
    final base = isHourly ? 'إجازة زمنية ${startHour ?? ''} - ${endHour ?? ''}'.trim() : typeName;
    return isPaid ? base : '$base (بدون راتب)';
  }
}

class ReportRow {
  final DateTime date;
  final ReportEmployee employee;
  final ReportStatus status;
  final ReportAttendance? attendance;

  /// الإجازة اليومية (الحالة مجاز) أو الزمنية (ملاحظة على يوم دوام)
  final ReportLeave? leave;
  final int lateMinutes;
  final int earlyMinutes;

  /// اسم العطلة الرسمية لهذا اليوم (إن كان عطلة)
  final String? holidayName;

  const ReportRow({
    required this.date,
    required this.employee,
    required this.status,
    this.attendance,
    this.leave,
    this.lateMinutes = 0,
    this.earlyMinutes = 0,
    this.holidayName,
  });

  /// ملاحظة مختصرة للقائمة والإكسل.
  String get note {
    final parts = <String>[
      if (lateMinutes > 0) 'تأخير $lateMinutes دقيقة',
      if (earlyMinutes > 0) 'خروج مبكر $earlyMinutes دقيقة',
      if (attendance != null && attendance!.checkIn != null && attendance!.checkOut == null && status.attended) 'بدون بصمة انصراف',
      if (leave != null) leave!.label,
      if (holidayName != null) 'عطلة رسمية: $holidayName',
    ];
    return parts.join(' · ');
  }
}

DateTime _d(DateTime t) => DateTime(t.year, t.month, t.day);

/// سطر لكل موظف ولكل يوم من [from] إلى [to] (لا يتجاوز [today]).
List<ReportRow> buildDailyReport({
  required DateTime from,
  required DateTime to,
  required DateTime today,
  required List<ReportEmployee> employees,
  required List<ReportAttendance> attendance,
  required List<ReportLeave> leaves,
  required List<WorkScheduleModel> schedules,
  /// العطل الرسمية: التاريخ ← الاسم
  Map<DateTime, String> holidays = const {},
}) {
  final holidayByDay = {for (final e in holidays.entries) _d(e.key): e.value};
  final last = _d(to).isAfter(_d(today)) ? _d(today) : _d(to);
  final byKey = {for (final a in attendance) '${a.employeeId}|${_d(a.date).toIso8601String()}': a};
  final rows = <ReportRow>[];

  for (var day = _d(from); !day.isAfter(last); day = DateTime(day.year, day.month, day.day + 1)) {
    for (final emp in employees) {
      if (emp.joinDate != null && day.isBefore(_d(emp.joinDate!))) continue;
      final schedule = resolveWorkSchedule(
        employeeId: emp.id, departmentId: emp.departmentId, branchId: emp.branchId, schedules: schedules);
      final att = byKey['${emp.id}|${day.toIso8601String()}'];
      final dayLeaves = leaves.where((l) => l.employeeId == emp.id && l.covers(day));
      final fullLeave = dayLeaves.where((l) => !l.isHourly).firstOrNull;
      final hourlyLeave = dayLeaves.where((l) => l.isHourly).firstOrNull;

      if (att != null && att.status != 'absent') {
        final late = att.checkIn == null ? 0 : lateMinutes(att.checkIn!, schedule);
        final early = att.checkOut == null ? 0 : earlyLeaveMinutes(att.checkOut!, schedule);
        final grace = schedule?.gracePeriodMinutes ?? 15;
        final status = att.status == 'late' || late > grace
            ? ReportStatus.late
            : early > grace || att.status == 'half_day'
                ? ReportStatus.earlyLeave
                : ReportStatus.present;
        rows.add(ReportRow(
          date: day,
          employee: emp,
          status: status,
          attendance: att,
          leave: hourlyLeave,
          lateMinutes: late > grace || att.status == 'late' ? late : 0,
          earlyMinutes: early > grace ? early : 0,
        ));
      } else if (att == null && (!isWorkingDay(day, schedule) || holidayByDay.containsKey(day))) {
        // العطلة (الأسبوعية أو الرسمية) داخل الإجازة تبقى عطلة (رصيد الإجازة يُحسب بأيام الدوام فقط)
        rows.add(ReportRow(date: day, employee: emp, status: ReportStatus.dayOff, holidayName: holidayByDay[day]));
      } else if (fullLeave != null) {
        rows.add(ReportRow(date: day, employee: emp, status: ReportStatus.leave, attendance: att, leave: fullLeave));
      } else {
        rows.add(ReportRow(date: day, employee: emp, status: ReportStatus.absent, attendance: att, leave: hourlyLeave));
      }
    }
  }
  return rows;
}

class ReportTotals {
  final int present;
  final int late;
  final int earlyLeave;
  final int absent;
  final int leave;

  const ReportTotals({this.present = 0, this.late = 0, this.earlyLeave = 0, this.absent = 0, this.leave = 0});

  int get attended => present + late + earlyLeave;

  /// نسبة الحضور من أيام الدوام المطلوبة (بدون الإجازات والعطل)
  int get rate => attended + absent == 0 ? 0 : (attended / (attended + absent) * 100).round();
}

ReportTotals reportTotals(Iterable<ReportRow> rows) {
  var p = 0, l = 0, e = 0, a = 0, lv = 0;
  for (final r in rows) {
    switch (r.status) {
      case ReportStatus.present:
        p++;
      case ReportStatus.late:
        l++;
      case ReportStatus.earlyLeave:
        e++;
      case ReportStatus.absent:
        a++;
      case ReportStatus.leave:
        lv++;
      case ReportStatus.dayOff:
        break;
    }
  }
  return ReportTotals(present: p, late: l, earlyLeave: e, absent: a, leave: lv);
}
