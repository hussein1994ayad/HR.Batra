import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/presentation/admin/attendance_report/widgets/edit_times_sheet.dart';

void main() {
  testWidgets('shows current times and returns them on save; null when dismissed', (tester) async {
    ({TimeOfDay? checkIn, TimeOfDay? checkOut})? result;
    var done = false;
    final checkIn = DateTime(2026, 10, 4, 8, 5).toUtc().toIso8601String();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showEditTimesSheet(
                context,
                (id: 'a1', employeeName: 'علي', workDate: '2026-10-04', checkIn: checkIn, checkOut: null),
              );
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('تعديل أوقات علي'), findsOneWidget);
    expect(find.text('8:05 ص'), findsOneWidget);
    expect(find.text('لم يُحدد'), findsOneWidget);

    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(result?.checkIn, const TimeOfDay(hour: 8, minute: 5));
    expect(result?.checkOut, isNull);
  });
}
