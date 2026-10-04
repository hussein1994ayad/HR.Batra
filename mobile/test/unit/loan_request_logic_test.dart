import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/logic/loan_rules.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/presentation/employee/loan/loan_request_logic.dart';
import 'package:hr_pro/presentation/employee/loan/widgets/loan_widgets.dart';

void main() {
  test('installmentPlan rounds down and puts the remainder on the last installment (like the server)', () {
    expect(installmentPlan(1000, 3), (installment: 333.0, last: 334.0));
    expect(installmentPlan(900, 3), (installment: 300.0, last: 300.0));
    expect(installmentPlan(500, 0), (installment: 0.0, last: 0.0));
  });

  group('loan calculator', () {
    test('months round up and the last installment is the remainder', () {
      expect(loanMonths(1000000, 300000), 4);
      expect(loanLastInstallment(1000000, 300000), 100000);
      expect(loanMonths(500000, 250000), 2);
      expect(loanLastInstallment(500000, 250000), 250000);
    });

    test('zero installment means zero months', () {
      expect(loanMonths(500000, 0), 0);
      expect(loanLastInstallment(500000, 0), 0);
    });
  });

  group('loanRequestError', () {
    test('basic checks in order', () {
      expect(loanRequestError(amount: 0, installment: 1, history: const []), 'اكتب مبلغ السلفة');
      expect(loanRequestError(amount: 10, installment: 0, history: const []), 'اكتب القسط الشهري');
      expect(loanRequestError(amount: 10, installment: 20, history: const []), 'القسط أكبر من مبلغ السلفة');
      expect(loanRequestError(amount: 200000000, installment: 1000000, history: const []), contains('كبير جداً'));
      expect(loanRequestError(amount: 500000, installment: 250000, history: const []), isNull);
    });

    test('an approved loan with a remaining balance blocks a new request', () {
      expect(
        loanRequestError(amount: 500000, installment: 250000, history: [
          LoanModel.fromMap(const {'status': 'approved', 'remaining_amount': 100000}),
        ]),
        contains('سلفة جارية'),
      );
      expect(
        loanRequestError(amount: 500000, installment: 250000, history: [
          LoanModel.fromMap(const {'status': 'approved', 'remaining_amount': 0}),
          LoanModel.fromMap(const {'status': 'pending', 'remaining_amount': 500000}),
        ]),
        isNull,
      );
    });
  });

  group('loanSalaryWarning (warning only, never blocks)', () {
    test('no salary or up to half the salary: no warning', () {
      expect(loanSalaryWarning(salary: null, installment: 900000), isNull);
      expect(loanSalaryWarning(salary: 1000000, installment: 500000), isNull);
    });

    test('above half, and above the whole salary', () {
      expect(loanSalaryWarning(salary: 1000000, installment: 600000), contains('نص راتبك'));
      expect(loanSalaryWarning(salary: 1000000, installment: 1200000), contains('بالسالب'));
    });
  });

  testWidgets('MyLoanCard shows cancel only while pending', (tester) async {
    LoanModel? cancelled;
    final loan = <String, dynamic>{'id': 'l1', 'amount': 500000, 'remaining_amount': 500000, 'installment_amount': 250000, 'installment_count': 2, 'status': 'pending'};
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: SingleChildScrollView(child: MyLoanCard(loan: LoanModel.fromMap(loan), onCancel: (l) => cancelled = l))),
    ));
    await tester.tap(find.text('إلغاء الطلب'));
    expect(cancelled?.id, 'l1');
  });
}
