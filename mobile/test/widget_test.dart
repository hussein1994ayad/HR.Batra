import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/presentation/shared/ui/ui.dart';

void main() {
  testWidgets('AppCard renders its child and handles taps', (WidgetTester tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: AppCard(onTap: () => taps++, child: const Text('اختبار النظام'))),
      ),
    );

    expect(find.text('اختبار النظام'), findsOneWidget);
    await tester.tap(find.byType(AppCard));
    expect(taps, 1);
  });

  testWidgets('AppButton shows a spinner and ignores taps while loading', (WidgetTester tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: Center(child: AppButton(label: 'حفظ', loading: true, onPressed: () => taps++))),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(AppButton));
    expect(taps, 0);
  });

  testWidgets('StatusBadge.request maps statuses to Arabic labels', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: Column(children: [StatusBadge.request('pending'), StatusBadge.request('approved'), StatusBadge.request('rejected')])),
      ),
    );
    expect(find.text('قيد المراجعة'), findsOneWidget);
    expect(find.text('مقبول'), findsOneWidget);
    expect(find.text('مرفوض'), findsOneWidget);
  });
}
