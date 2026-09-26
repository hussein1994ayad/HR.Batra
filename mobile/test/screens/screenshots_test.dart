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

  // لقطات تابلت لأهم الشاشات: شريط تنقل جانبي وتخطيط عمودين
  const tabletScreens = {'03_home', '04_attendance', '12_admin_dashboard'};
  for (final s in kScreens.where((s) => tabletScreens.contains(s.name))) {
    testWidgets('tablet landscape: ${s.name}', (tester) async {
      await pumpScreen(tester, s.build(), role: s.role, device: kTabletLandscape);
      await capture(tester, 'tablet_${s.name}');
      await disposeScreen(tester);
    });
  }
}
