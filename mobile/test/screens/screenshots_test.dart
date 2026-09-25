// يرسم كل شاشة ببيانات وهمية (اختبار دخان). مع --dart-define=CAPTURE=after
// يحفظ اللقطات في design/screenshots/after/.

import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import '../support/screens.dart';

void main() {
  for (final s in kScreens) {
    testWidgets('screen renders: ${s.name}', (tester) async {
      await pumpScreen(tester, s.build(), role: s.role);
      await capture(tester, s.name);
      await disposeScreen(tester);
    });
  }
}
