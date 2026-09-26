// يفتح النوافذ المنبثقة المهمة على أصغر هاتف وبخط مكبّر ويتأكد أنها لا تنكسر.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/presentation/employee/admin_dashboard/admin_dashboard_screen.dart';
import 'package:hr_pro/presentation/employee/admin_loans/admin_loans_screen.dart';
import 'package:hr_pro/presentation/employee/admin_loans/widgets/loan_card.dart';
import 'package:hr_pro/presentation/employee/branch_management_screen.dart';
import 'package:hr_pro/presentation/employee/branch_schedule_screen.dart';

import '../support/harness.dart';

const _small = DeviceSize('small', 320, 640);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  for (final scale in const [1.0, 1.3]) {
    for (final tab in const ['الإجازات', 'السلف', 'الأجهزة', 'الأمان']) {
      testWidgets('dashboard tab $tab @${scale}x', (tester) async {
        await pumpScreen(tester, const AdminDashboardScreen(), device: _small, textScale: scale);
        await tester.tap(find.text(tab));
        await _settle(tester);
        await capture(tester, 'dashboard_$tab');
        await disposeScreen(tester);
      });
    }

    testWidgets('loan details sheet @${scale}x', (tester) async {
      await pumpScreen(tester, const AdminLoansManagementScreen(), device: _small, textScale: scale);
      await tester.scrollUntilVisible(find.byType(LoanCard), 250, scrollable: find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable)).first);
      await tester.tap(find.descendant(of: find.byType(LoanCard).first, matching: find.byType(EmployeeAvatar)));
      await _settle(tester);
      expect(find.text('جدول الأقساط (6)'), findsNothing); // أسفل النافذة
      expect(find.text('أصل السلفة'), findsOneWidget);
      await capture(tester, 'sheet_loan_details');
      await disposeScreen(tester);
    });

    testWidgets('create loan sheet @${scale}x', (tester) async {
      await pumpScreen(tester, const AdminLoansManagementScreen(), device: _small, textScale: scale);
      await tester.tap(find.byType(FloatingActionButton));
      await _settle(tester);
      expect(find.text('سلفة مباشرة لموظف'), findsOneWidget);
      await capture(tester, 'sheet_create_loan');
      await disposeScreen(tester);
    });

    testWidgets('schedule editor @${scale}x', (tester) async {
      await pumpScreen(tester, const BranchScheduleScreen(), device: _small, textScale: scale);
      await tester.tap(find.text('فرع المنصور').first);
      await _settle(tester);
      expect(find.text('حفظ الجدول'), findsOneWidget);
      await capture(tester, 'sheet_schedule_editor');
      await disposeScreen(tester);
    });

    testWidgets('branch editor @${scale}x', (tester) async {
      await pumpScreen(tester, const BranchManagementScreen(), device: _small, textScale: scale);
      await tester.tap(find.byType(FloatingActionButton));
      await _settle(tester);
      expect(find.text('إضافة الفرع'), findsOneWidget);
      await capture(tester, 'sheet_branch_editor');
      await disposeScreen(tester);
    });
  }
}
