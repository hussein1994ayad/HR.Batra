// =========================================================================
// نظام HR Pro v6.0 - اختبار الفحص الدخاني للواجهة (Widget Test)
// =========================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hr_pro/main.dart';

void main() {
  testWidgets('HRProApp smoke test', (WidgetTester tester) async {
    // بناء التطبيق وإطلاق إطار العمل تحت تغليف ProviderScope
    await tester.pumpWidget(
      const ProviderScope(
        child: HRProApp(),
      ),
    );

    // التحقق من بناء عنصر التطبيق الرئيسي بنجاح
    expect(find.byType(HRProApp), findsOneWidget);
  });
}
