// لقطة نصية لكل شاشة: كل النصوص الظاهرة بالترتيب (من بيانات الخادم الوهمي) تُقارن بملف محفوظ
// في test/goldens/text/. أي تغيير بالعرض — حتى حرف — يُفشل الاختبار. يحمي إعادة التنظيم (مثل تحويل
// البيانات الخام لنماذج) من تغيير ما يراه المستخدم.
//
// تحديث اللقطات (فقط عند تغيير مقصود بالواجهة):
//   flutter test test/screens/text_snapshot_test.dart --dart-define=UPDATE_TEXT=true

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  for (final s in kScreens) {
    testWidgets('text snapshot ${s.name}', (tester) async {
      await pumpScreen(tester, s.build(), role: s.role, device: _tall);
      final actual = '${_visibleTexts(tester).join('\n')}\n';
      await disposeScreen(tester);

      final file = File('test/goldens/text/${s.name}.txt');
      if (_update || !file.existsSync()) {
        file.writeAsStringSync(actual);
        return;
      }
      expect(actual, file.readAsStringSync(), reason: 'نصوص الشاشة ${s.name} تغيّرت');
    });
  }
}
