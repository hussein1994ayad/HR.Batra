import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/presentation/employee/leave/leave_logic.dart';
import 'package:hr_pro/presentation/employee/leave/widgets/leave_widgets.dart';

void main() {
  group('leave names and durations', () {
    test('bareLeaveTypeName strips a leading "إجازة"', () {
      expect(bareLeaveTypeName('إجازة سنوية'), 'سنوية');
      expect(bareLeaveTypeName('مرضية'), 'مرضية');
    });

    test('formatLeaveMinutes', () {
      expect(formatLeaveMinutes(45), '45 د');
      expect(formatLeaveMinutes(120), '2 س');
      expect(formatLeaveMinutes(90), '1 س 30 د');
    });

    test('leaveHourString pads to HH:MM:00', () {
      expect(leaveHourString(8, 5), '08:05:00');
      expect(leaveHourString(14, 30), '14:30:00');
    });

    test('leaveTypeLabel prefers the policy name, then the fixed names', () {
      final types = [
        {'id': 'annual', 'name': 'إجازة اعتيادية'},
      ];
      expect(leaveTypeLabel('annual', types), 'اعتيادية');
      expect(leaveTypeLabel('sick', types), 'مرضية');
      expect(leaveTypeLabel(null, types), 'أخرى');
      expect(leaveTypeLabel('custom', types), 'custom');
    });
  });

  group('parseActiveLeaveTypes', () {
    test('null or missing policy keeps the defaults (empty result)', () {
      expect(parseActiveLeaveTypes(null), isEmpty);
      expect(parseActiveLeaveTypes({'value': null}), isEmpty);
      expect(parseActiveLeaveTypes({'value': <String, dynamic>{}}), isEmpty);
    });

    test('maps id and name to strings', () {
      final row = <String, dynamic>{
        'value': <String, dynamic>{
          'active_types': [
            <String, dynamic>{'id': 'annual', 'name': 'سنوية'},
            <String, dynamic>{'id': 7, 'name': null},
          ],
        },
      };
      expect(parseActiveLeaveTypes(row), [
        {'id': 'annual', 'name': 'سنوية'},
        {'id': '7', 'name': ''},
      ]);
    });
  });

  group('validateLeaveDates', () {
    final now = DateTime(2026, 10, 4, 10);
    String? check(DateTime start, DateTime end, {bool hourly = false, int minutes = 60, List<Map<String, dynamic>> history = const []}) =>
        validateLeaveDates(startDay: start, endDay: end, isHourly: hourly, hourlyMinutes: minutes, history: history.map(LeaveRequestModel.fromMap).toList(), now: now);

    test('more than 30 days in the past is refused', () {
      expect(check(DateTime(2026, 9, 3), DateTime(2026, 9, 3)), contains('30'));
      expect(check(DateTime(2026, 9, 4), DateTime(2026, 9, 4)), isNull);
    });

    test('end before start (daily) and non-positive hours (hourly)', () {
      expect(check(DateTime(2026, 10, 6), DateTime(2026, 10, 5)), isNotNull);
      expect(check(DateTime(2026, 10, 6), DateTime(2026, 10, 6), hourly: true, minutes: 0), isNotNull);
    });

    test('overlap with an active request is refused; rejected/cancelled are ignored', () {
      final history = <Map<String, dynamic>>[
        {'status': 'pending', 'start_date': DateTime(2026, 10, 10).toUtc().toIso8601String(), 'end_date': DateTime(2026, 10, 12).toUtc().toIso8601String()},
        {'status': 'rejected', 'start_date': DateTime(2026, 10, 20).toUtc().toIso8601String(), 'end_date': DateTime(2026, 10, 21).toUtc().toIso8601String()},
      ];
      expect(check(DateTime(2026, 10, 12), DateTime(2026, 10, 13), history: history), contains('تتعارض'));
      expect(check(DateTime(2026, 10, 13), DateTime(2026, 10, 14), history: history), isNull);
      expect(check(DateTime(2026, 10, 20), DateTime(2026, 10, 20), history: history), isNull);
    });
  });

  testWidgets('LeaveBalanceCard shows remaining and totals', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: LeaveBalanceCard(
          balance: LeaveBalance.fromMap(const {
            'year': 2026,
            'annual': {'left': 12.5, 'entitlement': 20},
            'sick': {'left': 5, 'entitlement': 5},
            'hourly': {'left_hours': 3, 'allowance_hours': 4},
          }),
          isHourly: false,
          leaveType: 'annual',
        ),
      ),
    ));
    expect(find.text('12.5 يوم'), findsOneWidget);
    expect(find.text('من 20'), findsOneWidget);
    expect(find.text('3 ساعة'), findsOneWidget);
  });
}
