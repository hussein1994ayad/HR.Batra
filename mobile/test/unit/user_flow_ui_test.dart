// واجهة مسارات المستخدم: راتب الشهر الحالي قبل الاعتماد.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/presentation/employee/payslips/widgets/payslip_widgets.dart';
import 'package:hr_pro/presentation/shared/ui/ui.dart';

void main() {
  testWidgets('current payroll card shows expected net and each movement with its status', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: CurrentPayrollCard(preview: PayrollPreview.fromMap(const {
              'period': {'period_month': '2026-10'},
              'summary': {'basic': 900000, 'earnings': 50000, 'deductions': 31250, 'loans': 100000, 'net': 818750},
              'events': [
                {'event_date': '2026-10-05', 'event_type': 'absence', 'minutes': 0, 'amount': 30000, 'direction': -1, 'status': 'approved'},
                {'event_date': '2026-10-06', 'event_type': 'late', 'minutes': 40, 'amount': 1250, 'direction': -1, 'status': 'pending'},
              ],
            })),
          ),
        ),
      ),
    ));
    expect(find.text('راتب الشهر العاشر 2026'), findsOneWidget);
    expect(find.text('الصافي المتوقع'), findsOneWidget);
    expect(find.textContaining('818,750'), findsOneWidget);
    expect(find.textContaining('بانتظار القرار'), findsOneWidget);
    expect(find.text('1 بانتظار قرار'), findsOneWidget);
  });

  test('cancelled requests read as cancelled, not rejected', () {
    final badge = StatusBadge.request('cancelled');
    expect(badge.label, 'ملغى');
  });
}
