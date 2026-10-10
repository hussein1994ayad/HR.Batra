// قرار الخصم/الإعفاء: ملاحظات جاهزة تنضغط (مثل: نسي البصمة وهو مداوم) وتوصل مع القرار.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/logic/decision_reasons.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/presentation/admin/admin_dashboard/widgets/decision_card.dart';

void main() {
  testWidgets('tapping a ready note fills the reason and the excuse sends it', (tester) async {
    bool? deducted;
    String? sentReason;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: DecisionCard(
            item: const PendingDecision(employeeId: 'e1', employeeName: 'علي', status: 'late', workDate: '2026-10-04', engineMinutes: 25),
            schedule: null,
            onDecide: ({required deduct, required reason, amount}) {
              deducted = deduct;
              sentReason = reason;
            },
          ),
        ),
      ),
    ));

    for (final r in [...kExcuseReasons, ...kDeductReasons]) {
      expect(find.widgetWithText(ActionChip, r), findsOneWidget, reason: r);
    }
    await tester.tap(find.widgetWithText(ActionChip, 'نسي البصمة وهو مداوم'));
    await tester.pump();
    expect(find.widgetWithText(TextFormField, 'نسي البصمة وهو مداوم'), findsOneWidget);

    await tester.ensureVisible(find.text('إعفاء'));
    await tester.tap(find.text('إعفاء'));
    await tester.pump();
    expect(deducted, isFalse);
    expect(sentReason, 'نسي البصمة وهو مداوم');
  });

  testWidgets('the computed amount is shown and can be edited before deducting', (tester) async {
    final sent = <double?>[];
    Widget card(PendingDecision item) => MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DecisionCard(
                key: ValueKey(item.workDate),
                item: item,
                schedule: null,
                onDecide: ({required deduct, required reason, amount}) => sent.add(amount),
              ),
            ),
          ),
        );
    const absence = PendingDecision(employeeId: 'e1', employeeName: 'علي', status: 'absent', workDate: '2026-10-10', engineAmount: 20000);
    await tester.pumpWidget(card(absence));
    final field = find.widgetWithText(TextFormField, '20,000');
    expect(field, findsOneWidget);

    // بدون تعديل: ما ينرسل مبلغ (السيرفر يبقى على المحسوب)
    await tester.ensureVisible(find.text('تطبيق الخصم'));
    await tester.tap(find.text('تطبيق الخصم'));
    await tester.pump();
    expect(sent, [null]);

    // نص يوم
    await tester.enterText(field, '10000');
    await tester.pump();
    await tester.ensureVisible(find.text('تطبيق الخصم'));
    await tester.tap(find.text('تطبيق الخصم'));
    await tester.pump();
    expect(sent.last, 10000);
  });

  test('editedAmount: empty or unchanged means the computed amount', () {
    expect(editedAmount('', 20000), isNull);
    expect(editedAmount('20,000', 20000), isNull);
    expect(editedAmount('20,000', 20000.4), isNull);
    expect(editedAmount('15,000', 20000), 15000);
    expect(editedAmount('0', 20000), 0);
    expect(editedAmount('5000', 0), 5000);
  });

  test('the same ready notes as the website', () {
    expect(kExcuseReasons, ['نسي البصمة وهو مداوم', 'تأخير مبرر', 'عذر مقبول من الإدارة']);
    expect(kDeductReasons, ['بدون عذر', 'تكرر التأخير']);
  });
}
