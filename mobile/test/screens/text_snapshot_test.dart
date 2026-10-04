// لقطة نصية لكل شاشة: كل النصوص الظاهرة بالترتيب (من بيانات الخادم الوهمي) تُقارن بملف محفوظ
// في test/goldens/text/. أي تغيير بالعرض — حتى حرف — يُفشل الاختبار. يحمي إعادة التنظيم (مثل تحويل
// البيانات الخام لنماذج) من تغيير ما يراه المستخدم.
//
// تحديث اللقطات (فقط عند تغيير مقصود بالواجهة):
//   flutter test test/screens/text_snapshot_test.dart --dart-define=UPDATE_TEXT=true

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hr_pro/presentation/employee/directory/directory_screen.dart';
import 'package:hr_pro/presentation/employee/main_layout.dart';
import 'package:hr_pro/presentation/employee/payslips/payslips_screen.dart';
import 'package:hr_pro/presentation/shared/ui/ui.dart';

import '../support/harness.dart';
import '../support/screens.dart';

const bool _update = bool.fromEnvironment('UPDATE_TEXT');

/// شاشة طويلة حتى تنبني أغلب عناصر القوائم الكسولة.
const _tall = DeviceSize('tall', 430, 5000);

/// الأوقات النسبية والتواريخ تتغير مع الساعة؛ نثبّت الأرقام حتى تبقى اللقطة ثابتة بين يوم ويوم.
/// ومعرّفات الأجهزة العشوائية بالاختبار (device_xxxxxxxx-...) نستبدلها بثابت.
String _normalize(String s) => s
    .replaceAll(RegExp(r'device_[0-9a-fA-F-]+'), 'device_<id>')
    .replaceAll(RegExp(r'[0-9٠-٩]'), '#');

List<String> _visibleTexts(WidgetTester tester) => [
      for (final e in find.byType(RichText).evaluate())
        if ((e.widget as RichText).text.toPlainText().trim().isNotEmpty) _normalize((e.widget as RichText).text.toPlainText()),
    ];

/// حالات فيها تفاعل (تبويب أو نافذة) حتى تنفحص الكروت اللي ما تظهر بأول شاشة.
class _Interaction {
  const _Interaction(this.name, this.build, this.act);
  final String name;
  final Widget Function() build;
  final Finder Function() act;
}

final _interactions = <_Interaction>[
  _Interaction('05b_leave_history', () => const MainLayout(initialTab: 2), () => find.text('طلباتي')),
  _Interaction('06b_loan_history', () => const MainLayout(initialTab: 3), () => find.text('سلفي وأقساطي')),
  _Interaction('10b_payslip_sheet', () => const PayslipsScreen(), () => find.byType(AppListTile).first),
  _Interaction('11c_directory_profile', () => const EmployeeDirectoryScreen(), () => find.byType(AppListTile).first),
];

Future<void> _check(String name, String actual) async {
  final file = File('test/goldens/text/$name.txt');
  if (_update || !file.existsSync()) {
    file.writeAsStringSync(actual);
    return;
  }
  expect(actual, file.readAsStringSync(), reason: 'نصوص الشاشة $name تغيّرت');
}

void main() {
  for (final s in kScreens) {
    testWidgets('text snapshot ${s.name}', (tester) async {
      await pumpScreen(tester, s.build(), role: s.role, device: _tall);
      final actual = '${_visibleTexts(tester).join('\n')}\n';
      await disposeScreen(tester);

      await _check(s.name, actual);
    });
  }

  for (final c in _interactions) {
    testWidgets('text snapshot ${c.name}', (tester) async {
      await pumpScreen(tester, c.build(), role: 'employee', device: _tall);
      await tester.tap(c.act());
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 300));
      }
      final actual = '${_visibleTexts(tester).join('\n')}\n';
      await disposeScreen(tester);
      await _check(c.name, actual);
    });
  }
}
