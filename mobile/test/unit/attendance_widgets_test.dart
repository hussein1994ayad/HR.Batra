import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/presentation/employee/attendance/widgets/attendance_widgets.dart';

Widget _host(Widget child) => MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: child));

void main() {
  group('AttendanceLocationCard', () {
    testWidgets('mock location wins over everything', (tester) async {
      await tester.pumpWidget(_host(const AttendanceLocationCard(
        branchName: 'الفرع الرئيسي',
        branchRadius: 100,
        currentPosition: null,
        distanceToBranch: 20,
        inRange: true,
        mockDetected: true,
      )));
      expect(find.text('موقع مزيّف'), findsOneWidget);
      expect(find.text('الفرع الرئيسي'), findsOneWidget);
    });

    testWidgets('no GPS fix yet', (tester) async {
      await tester.pumpWidget(_host(const AttendanceLocationCard(
        branchName: 'الفرع',
        branchRadius: 100,
        currentPosition: null,
        distanceToBranch: null,
        inRange: false,
        mockDetected: false,
      )));
      expect(find.text('بلا موقع'), findsOneWidget);
      expect(find.text('بانتظار إشارة GPS'), findsOneWidget);
    });

    testWidgets('outside range shows remaining metres', (tester) async {
      await tester.pumpWidget(_host(const AttendanceLocationCard(
        branchName: 'الفرع',
        branchRadius: 100,
        currentPosition: null,
        distanceToBranch: 150,
        inRange: false,
        mockDetected: false,
      )));
      expect(find.text('باقي 50 م للدخول بالنطاق'), findsOneWidget);
    });
  });

  group('AttendanceTodayCard', () {
    testWidgets('empty day shows dashes and no schedule row', (tester) async {
      await tester.pumpWidget(_host(const AttendanceTodayCard(todayAttendance: null, workSchedule: null)));
      expect(find.text('--:--'), findsNWidgets(2));
      expect(find.text('الدوام المعتمد'), findsNothing);
    });

    testWidgets('schedule row appears when a schedule exists', (tester) async {
      await tester.pumpWidget(_host(const AttendanceTodayCard(
        todayAttendance: {'check_in_time': '2026-10-04T05:00:00Z'},
        workSchedule: {'check_in_time': '08:00:00', 'check_out_time': '16:00:00'},
      )));
      expect(find.text('--:--'), findsOneWidget);
      expect(find.text('الدوام المعتمد'), findsOneWidget);
    });
  });
}
