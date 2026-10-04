// ربط التطبيق بمحرّك الرواتب: مبالغ القرارات من السيرفر، وتفاصيل كشف المحرّك.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/data/repositories/admin_dashboard_repository.dart';
import 'package:hr_pro/presentation/admin/admin_dashboard/widgets/decision_card.dart';
import 'package:hr_pro/presentation/employee/payslips_screen.dart';

void main() {
  group('attachEngineEvents', () {
    const day = '2026-09-24';
    final employees = {
      'e1': (name: 'زينب', branchId: 'b1' as String?),
      'e2': (name: 'علي', branchId: 'b1' as String?),
    };

    test('attaches the engine amount and event to late/absence decisions', () {
      final out = attachEngineEvents(
        const [
          PendingDecision(employeeId: 'e1', employeeName: 'زينب', status: 'late', workDate: day, attendanceId: 'a1'),
          PendingDecision(employeeId: 'e2', employeeName: 'علي', status: 'absent', workDate: day),
        ],
        [
          {'id': 'ev1', 'employee_id': 'e1', 'event_type': 'late', 'amount': 1250, 'minutes': 30, 'status': 'pending', 'source_id': 'a1'},
          {'id': 'ev2', 'employee_id': 'e2', 'event_type': 'absence', 'amount': 20000, 'minutes': 0, 'status': 'pending'},
        ],
        employees,
        day,
      );
      expect(out, hasLength(2));
      expect(out[0].eventId, 'ev1');
      expect(out[0].engineAmount, 1250);
      expect(out[0].engineMinutes, 30);
      expect(out[1].eventId, 'ev2');
      expect(out[1].engineAmount, 20000);
    });

    test('adds pending early leave and missing punches as their own decisions', () {
      final out = attachEngineEvents(
        const [],
        [
          {'id': 'ev3', 'employee_id': 'e1', 'event_type': 'early_leave', 'amount': 5000, 'minutes': 120, 'status': 'pending', 'source_id': 'a3'},
          {'id': 'ev4', 'employee_id': 'e2', 'event_type': 'missing_punch', 'amount': 0, 'minutes': 0, 'status': 'pending', 'source_id': 'a4'},
          {'id': 'ev5', 'employee_id': 'e2', 'event_type': 'early_leave', 'amount': 900, 'minutes': 20, 'status': 'ignored', 'source_id': 'a5'},
        ],
        employees,
        day,
      );
      expect(out.map((d) => d.statusArabic), ['خروج مبكر', 'بصمة ناقصة']);
      expect(out.first.isVirtual, isFalse);
      expect(out.first.key, 'ev3');
    });

    test('decisions without an engine event keep the attendance path', () {
      final out = attachEngineEvents(
        const [PendingDecision(employeeId: 'e2', employeeName: 'علي', status: 'absent', workDate: day)],
        const [],
        employees,
        day,
      );
      expect(out.single.eventId, isNull);
      expect(out.single.isVirtual, isTrue);
    });
  });

  test('old half-day records read as early leave or missing punch', () {
    final early = PendingDecision(employeeId: 'e', employeeName: 'x', status: 'half_day', workDate: '2026-09-01', checkInTime: DateTime(2026, 9, 1, 9));
    const missing = PendingDecision(employeeId: 'e', employeeName: 'x', status: 'half_day', workDate: '2026-09-01');
    expect(early.statusArabic, 'خروج مبكر');
    expect(missing.statusArabic, 'بصمة ناقصة');
    expect(early.engineEventTypes, ['early_leave', 'missing_punch']);
  });

  test('engine slip lines become payslip details (loans and zero lines hidden)', () {
    final details = slipLinesToDetails([
      {'line_type': 'absence', 'event_date': '2026-09-10', 'amount': 20000, 'direction': -1, 'minutes': 0},
      {'line_type': 'late', 'event_date': '2026-09-24', 'amount': 1250, 'direction': -1, 'minutes': 30},
      {'line_type': 'absence', 'event_date': '2026-08-28', 'amount': 20000, 'direction': -1, 'minutes': 0, 'carried_from': '2026-08'},
      {'line_type': 'bonus', 'event_date': '2026-09-26', 'amount': 10000, 'direction': 1, 'notes': 'مكافأة أداء'},
      {'line_type': 'paid_leave', 'event_date': '2026-09-15', 'amount': 0, 'direction': 0},
      {'line_type': 'loan', 'event_date': '2026-09-20', 'amount': 100000, 'direction': -1},
    ]);
    expect(details.map((d) => d['reason']), ['غياب', 'تأخير 30 دقيقة', 'غياب (مرحّل من 2026-08)', 'مكافأة أداء']);
    expect(details.map((d) => d['type']), ['deduction', 'deduction', 'deduction', 'bonus']);
  });

  testWidgets('decision card shows the server amount and has no amount field', (tester) async {
    bool? deducted;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: DecisionCard(
              item: const PendingDecision(
                employeeId: 'e1', employeeName: 'زينب', status: 'late', workDate: '2026-09-24',
                attendanceId: 'a1', eventId: 'ev1', engineAmount: 1250, engineMinutes: 30,
              ),
              schedule: null,
              onDecide: ({required deduct, required reason}) => deducted = deduct,
            ),
          ),
        ),
      ),
    ));
    expect(find.text('الخصم المحسوب'), findsOneWidget);
    expect(find.textContaining('1,250'), findsOneWidget);
    expect(find.text('الخصم (د.ع)'), findsNothing);
    await tester.tap(find.text('تطبيق الخصم'));
    expect(deducted, isTrue);
  });
}
