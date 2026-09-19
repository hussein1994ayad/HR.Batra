import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/presentation/shared/widgets/glass_container.dart';

void main() {
  testWidgets('GlassContainer widget renders child correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassContainer(
            child: Text('اختبار النظام'),
          ),
        ),
      ),
    );

    expect(find.text('اختبار النظام'), findsOneWidget);
    expect(find.byType(GlassContainer), findsOneWidget);
  });
}
