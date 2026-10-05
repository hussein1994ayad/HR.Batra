import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/core/utils/company_time.dart';
import 'package:hr_pro/presentation/employee/attendance/attendance_logic.dart';
import 'package:hr_pro/presentation/employee/attendance/widgets/attendance_widgets.dart';

void main() {
  test('scheduleMinutesOf parses HH:mm and HH:mm:ss', () {
    expect(scheduleMinutesOf('08:30'), 510);
    expect(scheduleMinutesOf('16:00:00'), 960);
    expect(scheduleMinutesOf(null), isNull);
    expect(scheduleMinutesOf('bad'), isNull);
  });

  group('punchNote', () {
    const schedule = {'check_in_time': '08:00:00', 'check_out_time': '16:00:00', 'grace_period_minutes': 15};

    test('late only after the grace period', () {
      expect(punchNote(isCheckIn: true, schedule: schedule, now: DateTime(2026, 10, 4, 8, 15)), isNull);
      expect(punchNote(isCheckIn: true, schedule: schedule, now: DateTime(2026, 10, 4, 8, 40)), 'متأخر 40 د عن بداية الدوام');
    });

    test('early leave before the end of the day', () {
      expect(punchNote(isCheckIn: false, schedule: schedule, now: DateTime(2026, 10, 4, 14, 30)), 'خروج قبل نهاية الدوام بـ 1 س 30 د');
      expect(punchNote(isCheckIn: false, schedule: schedule, now: DateTime(2026, 10, 4, 16, 5)), isNull);
    });

    test('no schedule, no note', () {
      expect(punchNote(isCheckIn: true, schedule: null, now: DateTime(2026, 10, 4, 11)), isNull);
    });
  });

  group('mergeTodayOfflinePunches', () {
    final todayStr = companyDateStr();
    final nowUtc = DateTime.now().toUtc().toIso8601String();

    test('offline punches of this user today override the server row', () {
      final merged = mergeTodayOfflinePunches(
        serverToday: {'id': 'a1', 'check_in_time': '2000-01-01T05:00:00Z'},
        offlineQueue: [
          {'user_id': 'u1', 'type': 'check_out', 'time': nowUtc, 'latitude': 33.3, 'longitude': 44.4},
          {'user_id': 'u2', 'type': 'check_in', 'time': nowUtc, 'latitude': 1, 'longitude': 1},
          {'user_id': 'u1', 'type': 'check_in', 'time': '2000-01-01T05:00:00Z', 'latitude': 1, 'longitude': 1},
        ],
        userId: 'u1',
        todayStr: todayStr,
      );
      expect(merged['id'], 'a1');
      expect(merged['check_in_time'], '2000-01-01T05:00:00Z');
      expect(merged['check_out_time'], nowUtc);
      expect(merged['check_out_lat'], 33.3);
    });

    test('nothing at all gives an empty map', () {
      expect(mergeTodayOfflinePunches(serverToday: null, offlineQueue: const [], userId: 'u1', todayStr: todayStr), isEmpty);
    });
  });

  test('nextPunchType', () {
    expect(nextPunchType({}), 'check_in');
    expect(nextPunchType({'check_in_time': 'x'}), 'check_out');
    expect(nextPunchType({'check_in_time': 'x', 'check_out_time': 'y'}), 'check_in');
  });

  group('localPunchError', () {
    String? check({String type = 'check_in', double accuracy = 10, double distance = 20, Map<String, dynamic>? today}) =>
        localPunchError(punchType: type, accuracy: accuracy, distanceMeters: distance, branchRadius: 100, today: today);

    test('inside range with good accuracy passes', () => expect(check(), isNull));

    test('outside range tells the remaining metres', () {
      expect(check(distance: 150.4), '$attendanceOutOfRangeMessage المتبقي لتصل للفرع: 50.4 متر.');
    });

    test('poor accuracy is refused before the range check', () {
      expect(check(accuracy: 5000, distance: 9999), isNot(contains(attendanceOutOfRangeMessage)));
      expect(check(accuracy: 5000), isNotNull);
    });

    test('duplicate punches are refused', () {
      expect(check(today: {'check_in_time': 'x'}), contains('الحضور مسبقاً'));
      expect(check(type: 'check_out', today: {'check_out_time': 'y'}), contains('الانصراف مسبقاً'));
    });
  });

  testWidgets('AttendancePunchControls: disabled without GPS, submits when ready', (tester) async {
    var submitted = 0;
    String? changed;
    Widget host({required bool hasPosition}) => MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: AttendancePunchControls(
              selectedType: 'check_in',
              onTypeChanged: (t) => changed = t,
              submitting: false,
              mockDetected: false,
              hasPosition: hasPosition,
              inRange: true,
              onSubmit: () => submitted++,
            ),
          ),
        );
    await tester.pumpWidget(host(hasPosition: false));
    expect(find.text('ننتظر تحديد موقعك حتى تقدر تبصم.'), findsOneWidget);
    await tester.tap(find.text('بصمة الحضور'));
    expect(submitted, 0);

    await tester.pumpWidget(host(hasPosition: true));
    expect(find.text('أنت داخل نطاق الفرع، تقدر تبصم الآن.'), findsOneWidget);
    await tester.tap(find.text('بصمة الحضور'));
    expect(submitted, 1);
    await tester.tap(find.text('انصراف'));
    expect(changed, 'check_out');
  });

  testWidgets('PunchSuccessDialog shows the late note, or the offline message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const Scaffold(body: PunchSuccessDialog(isCheckIn: true, isSynced: true, note: 'متأخر 10 د عن بداية الدوام')),
    ));
    expect(find.textContaining('متأخر 10 د'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const Scaffold(body: PunchSuccessDialog(isCheckIn: false, isSynced: false, note: null)),
    ));
    expect(find.textContaining('انقطع الإنترنت'), findsOneWidget);
  });
}
