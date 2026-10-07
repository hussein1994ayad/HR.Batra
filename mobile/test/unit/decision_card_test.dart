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
            onDecide: ({required deduct, required reason}) {
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

  test('the same ready notes as the website', () {
    expect(kExcuseReasons, ['نسي البصمة وهو مداوم', 'تأخير مبرر', 'عذر مقبول من الإدارة']);
    expect(kDeductReasons, ['بدون عذر', 'تكرر التأخير']);
  });
}
