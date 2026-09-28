// تقرير الحضور اليومي: سطر لكل موظف في كل يوم، مع الإجازات ونوعها.

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/logic/attendance_report.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/core/services/excel_export_service.dart';

void main() {
  const schedule = WorkScheduleModel(
    id: 's', name: 's', branchId: 'b1', checkInTime: '09:00:00', checkOutTime: '17:00:00',
    workDays: [0, 1, 2, 3, 4, 6], // السبت → الخميس
  );
  const ali = ReportEmployee(id: 'e1', name: 'علي', branchId: 'b1');
  const sara = ReportEmployee(id: 'e2', name: 'سارة', branchId: 'b1');
  // 2026-09-20 الأحد → 2026-09-26 السبت (الجمعة 25 عطلة)
  final from = DateTime(2026, 9, 20);
  final to = DateTime(2026, 9, 26);

  List<ReportRow> build({List<ReportAttendance> att = const [], List<ReportLeave> leaves = const [], DateTime? today}) =>
      buildDailyReport(
        from: from, to: to, today: today ?? DateTime(2026, 9, 30),
        employees: const [ali, sara], attendance: att, leaves: leaves, schedules: const [schedule],
      );

  test('every employee gets one row per day of the range, not one row for the whole range', () {
    final rows = build();
    expect(rows, hasLength(7 * 2));
    expect(rows.where((r) => r.status == ReportStatus.dayOff).map((r) => r.date.day).toSet(), {25});
    expect(rows.where((r) => r.status == ReportStatus.absent), hasLength(6 * 2));
  });

  test('present, late and early leave come from the punches and schedule', () {
    final rows = build(att: [
      ReportAttendance(id: 'a1', employeeId: 'e1', date: DateTime(2026, 9, 20), status: 'present',
          checkIn: DateTime(2026, 9, 20, 8, 55), checkOut: DateTime(2026, 9, 20, 17, 5)),
      ReportAttendance(id: 'a2', employeeId: 'e1', date: DateTime(2026, 9, 21), status: 'late',
          checkIn: DateTime(2026, 9, 21, 9, 40), checkOut: DateTime(2026, 9, 21, 17)),
      ReportAttendance(id: 'a3', employeeId: 'e1', date: DateTime(2026, 9, 22), status: 'present',
          checkIn: DateTime(2026, 9, 22, 9), checkOut: DateTime(2026, 9, 22, 15)),
    ]);
    ReportRow of(int day) => rows.firstWhere((r) => r.employee.id == 'e1' && r.date.day == day);
    expect(of(20).status, ReportStatus.present);
    expect(of(21).status, ReportStatus.late);
    expect(of(21).lateMinutes, 40);
    expect(of(22).status, ReportStatus.earlyLeave);
    expect(of(22).earlyMinutes, 120);
    expect(of(23).status, ReportStatus.absent);
  });

  test('approved leave shows as leave with its type; hourly leave is a note on the day', () {
    final rows = build(
      att: [
        ReportAttendance(id: 'a4', employeeId: 'e2', date: DateTime(2026, 9, 24), status: 'present',
            checkIn: DateTime(2026, 9, 24, 9), checkOut: DateTime(2026, 9, 24, 17)),
      ],
      leaves: [
        ReportLeave(employeeId: 'e2', from: DateTime(2026, 9, 21), to: DateTime(2026, 9, 22, 23, 59), typeName: 'إجازة سنوية'),
        ReportLeave(employeeId: 'e2', from: DateTime(2026, 9, 24, 10), to: DateTime(2026, 9, 24, 12), typeName: 'إجازة أخرى',
            isHourly: true, startHour: '10:00', endHour: '12:00', isPaid: false),
      ],
    );
    ReportRow of(int day) => rows.firstWhere((r) => r.employee.id == 'e2' && r.date.day == day);
    expect(of(21).status, ReportStatus.leave);
    expect(of(22).note, 'إجازة سنوية');
    expect(of(24).status, ReportStatus.present);
    expect(of(24).note, 'إجازة زمنية 10:00 - 12:00 (بدون راتب)');
  });

  test('days after today and before joining are not counted', () {
    final rows = buildDailyReport(
      from: from, to: to, today: DateTime(2026, 9, 22),
      employees: [ReportEmployee(id: 'e3', name: 'جديد', branchId: 'b1', joinDate: DateTime(2026, 9, 21))],
      attendance: const [], leaves: const [], schedules: const [schedule],
    );
    expect(rows.map((r) => r.date.day), [21, 22]);
  });

  test('totals and attendance rate ignore leave and days off', () {
    final rows = build(
      att: [
        ReportAttendance(id: 'a1', employeeId: 'e1', date: DateTime(2026, 9, 20), status: 'present',
            checkIn: DateTime(2026, 9, 20, 9), checkOut: DateTime(2026, 9, 20, 17)),
      ],
      leaves: [ReportLeave(employeeId: 'e2', from: DateTime(2026, 9, 20), to: DateTime(2026, 9, 26), typeName: 'إجازة مرضية')],
    );
    final t = reportTotals(rows.where((r) => r.employee.id == 'e1'));
    expect(t.attended, 1);
    expect(t.absent, 5);
    expect(t.rate, 17);
    expect(reportTotals(rows.where((r) => r.employee.id == 'e2')).leave, 6);
  });

  test('the Excel report builds (day by day + summary sheets)', () {
    final bytes = ExcelExportService.buildAttendanceReportBytes(rows: build(), from: from, to: to);
    expect(bytes.length, greaterThan(1000));
    // ملف xlsx = أرشيف zip
    expect(bytes.take(2), [0x50, 0x4B]);
  });
}
