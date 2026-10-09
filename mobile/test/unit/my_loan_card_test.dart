// كارت السلفة بشاشة الموظف: كل النصوص (مع جدول الأقساط مفتوح) — كُتب قبل تحويل الكارت لـ LoanModel
// حتى يثبت إن العرض بقى نفسه بعد التحويل.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/presentation/employee/loan/widgets/loan_widgets.dart';

final _loan = <String, dynamic>{
  'id': 'l1',
  'amount': 1000000,
  'remaining_amount': 600000,
  'installment_amount': 200000,
  'installment_count': 5,
  'status': 'approved',
  'created_at': DateTime.now().subtract(const Duration(days: 40)).toUtc().toIso8601String(),
  'pledge_url': 'https://x.supabase.co/storage/v1/object/public/loan-pledges/a.jpg',
  'loan_installments': [
    {'id': 'i3', 'due_date': '2026-12-25', 'amount': 200000, 'is_paid': false},
    {'id': 'i1', 'due_date': '2026-10-25', 'amount': 200000, 'is_paid': true},
    {'id': 'i2', 'due_date': '2026-11-25', 'amount': 200000.0, 'is_paid': true},
  ],
};

Widget _card(Map<String, dynamic> loan, void Function(Object) onCancel) =>
    MyLoanCard(loan: LoanModel.fromMap(loan), onCancel: (l) => onCancel(l));

List<String> _texts(WidgetTester tester) => [
      for (final e in find.byType(RichText).evaluate())
        if ((e.widget as RichText).text.toPlainText().trim().isNotEmpty) (e.widget as RichText).text.toPlainText(),
    ];

/// يقارن النصوص بملف محفوظ (يُنشأ بأول تشغيل من الكود الحالي).
void _matchGolden(String name, List<String> texts) {
  final file = File('test/goldens/text/card_$name.txt');
  final actual = '${texts.join('\n')}\n';
  if (!file.existsSync()) {
    file.writeAsStringSync(actual);
    return;
  }
  expect(actual, file.readAsStringSync());
}

void main() {
  testWidgets('approved loan with the installment schedule open', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: SingleChildScrollView(child: _card(_loan, (_) {})))));
    await tester.tap(find.textContaining('جدول الأقساط'));
    await tester.pumpAndSettle();
    // "طُلبت قبل ..." نسبي للوقت الحالي
    _matchGolden('my_loan_approved', _texts(tester).where((t) => !t.startsWith('طُلبت')).toList());
  });

  testWidgets('pending loan shows cancel and passes the loan back', (tester) async {
    Object? cancelled;
    final pending = {..._loan, 'status': 'pending', 'remaining_amount': 1000000, 'loan_installments': <Object>[], 'rejection_reason': null};
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: SingleChildScrollView(child: _card(pending, (l) => cancelled = l)))));
    _matchGolden('my_loan_pending', _texts(tester).where((t) => !t.startsWith('طُلبت')).toList());
    await tester.tap(find.text('إلغاء الطلب'));
    expect(cancelled, isNotNull);
  });

  testWidgets('rejected loan shows the reason', (tester) async {
    final rejected = {..._loan, 'status': 'rejected', 'rejection_reason': 'تجاوز الحد', 'loan_installments': <Object>[]};
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: SingleChildScrollView(child: _card(rejected, (_) {})))));
    _matchGolden('my_loan_rejected', _texts(tester).where((t) => !t.startsWith('طُلبت')).toList());
  });

  testWidgets('installments explain a reduced month, its rest and a postponed month', (tester) async {
    final smart = {
      ..._loan,
      'loan_installments': [
        {'id': 'a', 'due_date': '2026-10-01', 'amount': 100000, 'is_paid': false, 'amount_locked': true},
        {'id': 'b', 'due_date': '2026-11-01', 'amount': 200000, 'is_paid': false},
        {'id': 'c', 'due_date': '2027-01-01', 'amount': 200000, 'is_paid': false, 'origin_kind': 'postponed', 'origin_month': '2026-12-01'},
        {'id': 'd', 'due_date': '2027-02-01', 'amount': 100000, 'is_paid': false, 'origin_kind': 'shortfall', 'origin_month': '2026-10-01'},
      ],
    };
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: Scaffold(body: SingleChildScrollView(child: _card(smart, (_) {})))));
    await tester.tap(find.textContaining('جدول الأقساط'));
    await tester.pumpAndSettle();
    expect(find.text('مبلغ هالشهر مخفّض'), findsOneWidget);
    expect(find.text('مؤجّل من 12/2026'), findsOneWidget);
    expect(find.text('باقي شهر 10/2026'), findsOneWidget);
  });
}
