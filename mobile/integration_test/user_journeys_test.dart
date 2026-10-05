// رحلات المستخدم على محاكي آيفون حقيقي: التطبيق الحقيقي (الموجّه، AppChrome، الثيم) يُستعمل مثل الموظف والمدير —
// تنقل، كتابة والكيبورد ظاهر، تأكيد بنوافذ iOS، رجوع بالسحب من حافة الشاشة، كاميرا مرفوضة ثم مقبولة، إرسال طلبات.
// بالمقاس والمساحة الآمنة الحقيقية للجهاز (النوتش، Dynamic Island، شريط الهوم). بيانات وهمية (FakeBackend).
// الرحلات نفسها في test/support/journeys.dart (تنفحص محلياً أيضاً بـ test/screens/journeys_test.dart).

import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fake_backend.dart';
import '../test/support/journeys.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false; // الخط من داخل التطبيق
    await FakeBackend.ensureInitialized();
  });

  for (final j in kJourneys) {
    testWidgets(j.name, (tester) async {
      await runJourney(tester, j, (name) async {
        if (Platform.isIOS) await binding.takeScreenshot(name);
      });
    });
  }
}
