// الزر الطايف (سلفة لموظف، موظف جديد، فرع جديد، تعميم جديد) ما لازم يغطي أي زر بالقائمة:
// إذا نزلت لآخر القائمة، كل زر لازم يطلع فوق الزر الطايف حتى ينضغط — على كل مقاسات الموبايل
// (ومنها الآيفونات اللي بيها شريط الهوم بالأسفل).

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/harness.dart';
import '../support/screens.dart';

const _fabScreens = ['12_admin_dashboard', '13_admin_loans', '15_employee_management', '16_branches'];

bool _tappable(Widget w) => w is ButtonStyleButton || w is IconButton || w is InkWell || w is Switch;

Future<List<String>> _coveredByFab(WidgetTester tester) async {
  // كل قائمة عمودية تنزل لآخرها
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) continue;
    s.position.jumpTo(s.position.maxScrollExtent);
  }
  await tester.pump(const Duration(milliseconds: 300));

  final fabFinder = find.byType(FloatingActionButton);
  if (fabFinder.evaluate().isEmpty) return <String>[];
  final fab = tester.getRect(fabFinder.first);
  final covered = <String>[];
  for (final e in find.byWidgetPredicate(_tappable).evaluate()) {
    if (find.ancestor(of: find.byWidget(e.widget), matching: fabFinder).evaluate().isNotEmpty) continue;
    if (find.ancestor(of: find.byWidget(e.widget), matching: find.byType(Scrollable)).evaluate().isEmpty) continue;
    final box = e.renderObject;
    if (box is! RenderBox || !box.hasSize || !box.attached) continue;
    final r = box.localToGlobal(Offset.zero) & box.size;
    if (r.isEmpty || r.bottom <= 0 || r.top >= tester.view.physicalSize.height / tester.view.devicePixelRatio) continue;
    if (r.overlaps(fab)) covered.add('${e.widget.runtimeType} @ ${r.top.round()}..${r.bottom.round()} (الزر الطايف ${fab.top.round()}..)');
  }
  return covered;
}

void main() {
  scrollHidesFabTests();
  for (final s in kScreens.where((s) => _fabScreens.contains(s.name))) {
    for (final device in kPhoneSizes) {
      testWidgets('${s.name} on ${device.name}: floating button covers nothing at the end of the list', (tester) async {
        await pumpScreen(tester, s.build(), role: s.role, device: device);
        final covered = await _coveredByFab(tester);
        // لوحة المدير: كل تبويب (القرارات، الإجازات، السلف...) قائمته مستقلة
        final tabs = find.byType(Tab);
        for (var i = 0; i < tabs.evaluate().length; i++) {
          tester.widget<TabBar>(find.byType(TabBar).first).controller!.animateTo(i, duration: Duration.zero);
          await tester.pump(const Duration(milliseconds: 400));
          covered.addAll((await _coveredByFab(tester)).map((c) => 'تبويب $i: $c'));
        }
        await disposeScreen(tester);
        expect(covered, isEmpty);
      });
    }
  }
}

/// الزر الطايف ظاهر وينضغط؟ (لما يختفي ينزلق لتحت ويتجاهل اللمس)
bool _fabShown(WidgetTester tester) {
  final slide = tester.widget<AnimatedSlide>(find.ancestor(of: find.byType(FloatingActionButton), matching: find.byType(AnimatedSlide)).first);
  return slide.offset == Offset.zero && find.byType(FloatingActionButton).hitTestable().evaluate().isNotEmpty;
}

/// إطار يبدي حركة الزر، وبعدها وقت يكفي حتى تخلص.
Future<void> _settleFab(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void scrollHidesFabTests() {
  for (final name in _fabScreens) {
    testWidgets('$name: floating button hides while scrolling down and comes back when scrolling up', (tester) async {
      final s = kScreens.firstWhere((s) => s.name == name);
      await pumpScreen(tester, s.build(), role: s.role, device: kPhoneSizes.firstWhere((d) => d.name == 'iphone_se'));
      expect(_fabShown(tester), isTrue, reason: 'الزر لازم يبين أول ما تنفتح الصفحة');
      final list = find.byType(Scrollable).first;
      await tester.drag(list, const Offset(0, -150));
      await _settleFab(tester);
      expect(_fabShown(tester), isFalse, reason: 'الزر بقى يغطي القائمة وإنت تنزل');
      await tester.drag(list, const Offset(0, 80));
      await _settleFab(tester);
      expect(_fabShown(tester), isTrue, reason: 'الزر ما رجع لما صعدت');
      await disposeScreen(tester);
    });
  }
}
