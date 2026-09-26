// كل شاشة × كل مقاس (هواتف 320→430، تابلت عمودي/أفقي) × حجم خط 1.0 و 1.3.
// أي overflow أو خطأ رسم يُفشل الاختبار تلقائياً.

import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import '../support/screens.dart';

void main() {
  for (final s in kScreens) {
    group(s.name, () {
      for (final device in kAllSizes) {
        for (final scale in const [1.0, 1.3]) {
          testWidgets('$device @${scale}x', (tester) async {
            await pumpScreen(tester, s.build(), role: s.role, device: device, textScale: scale);
            await disposeScreen(tester);
          });
        }
      }
    });
  }
}
