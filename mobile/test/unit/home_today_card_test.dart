// بطاقة اليوم بالرئيسية: بعد نهاية الدوام بدون بصمة = «غائب»، مو «متأخر 12 ساعة».

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/presentation/employee/attendance/attendance_logic.dart';
import 'package:hr_pro/presentation/employee/home/widgets/home_widgets.dart';

const _schedule = {
  'check_in_time': '09:00:00',
  'check_out_time': '14:00:00',
  'grace_period_minutes': 10,
  'work_days': [0, 1, 2, 3, 4, 6],
};

Widget _card(DateTime now, {Map<String, dynamic>? attendance, bool onLeave = false, Map<String, dynamic> schedule = _schedule}) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: HomeTodayCard(loading: false, attendance: attendance, schedule: schedule, onLeave: onLeave, onAction: () {}, now: now),
          ),
        ),
      ),
    );

void main() {
  // السبت 10/10/2026 يوم دوام
  testWidgets('during the shift without a punch: late, with the check-in button', (tester) async {
    await tester.pumpWidget(_card(DateTime(2026, 10, 10, 10, 30)));
    expect(find.text('متأخر 1 س 30 د'), findsOneWidget);
    expect(find.text('تسجيل الحضور'), findsOneWidget);
    expect(find.text('غائب'), findsNothing);
  });

  testWidgets('after the shift ended without a punch: absent, not "late 12 hours"', (tester) async {
    await tester.pumpWidget(_card(DateTime(2026, 10, 10, 21, 58)));
    expect(find.text('غائب'), findsOneWidget);
    expect(find.textContaining('متأخر'), findsNothing);
    expect(find.text('انتهى دوامك'), findsOneWidget);
    expect(find.text('2:00 م'), findsOneWidget);
    expect(find.text('تسجيل الحضور'), findsNothing);
    expect(find.text('عرض سجل الدوام'), findsOneWidget);
    expect(find.textContaining('راجع الإدارة'), findsOneWidget);
  });

  testWidgets('right at the end of the shift it is already absent', (tester) async {
    await tester.pumpWidget(_card(DateTime(2026, 10, 10, 14, 0)));
    expect(find.text('غائب'), findsOneWidget);
  });

  testWidgets('someone who punched in is never shown as absent after the shift', (tester) async {
    await tester.pumpWidget(_card(DateTime(2026, 10, 10, 21, 58), attendance: {'check_in_time': DateTime(2026, 10, 10, 9, 5).toIso8601String()}));
    expect(find.text('غائب'), findsNothing);
    expect(find.text('في الدوام'), findsOneWidget);
  });

  testWidgets('on leave or a day off: no absence', (tester) async {
    await tester.pumpWidget(_card(DateTime(2026, 10, 10, 21, 58), onLeave: true));
    expect(find.text('غائب'), findsNothing);
    // الجمعة 9/10 عطلة أسبوعية
    await tester.pumpWidget(_card(DateTime(2026, 10, 9, 21, 58)));
    expect(find.text('غائب'), findsNothing);
    expect(find.text('يوم عطلة'), findsOneWidget);
  });

  testWidgets('a night shift that crosses midnight keeps the old behaviour', (tester) async {
    await tester.pumpWidget(_card(DateTime(2026, 10, 10, 23, 0), schedule: {..._schedule, 'check_in_time': '22:00:00', 'check_out_time': '06:00:00'}));
    expect(find.text('غائب'), findsNothing);
    expect(find.text('متأخر 1 س'), findsOneWidget);
  });

  test('a check-in after the shift ended is noted as such, not as hours of lateness', () {
    expect(punchNote(isCheckIn: true, schedule: _schedule, now: DateTime(2026, 10, 10, 21, 58)), 'بصمة حضور بعد نهاية الدوام (2:00 م)');
    expect(punchNote(isCheckIn: true, schedule: _schedule, now: DateTime(2026, 10, 10, 9, 40)), 'متأخر 40 د عن بداية الدوام');
  });
}
