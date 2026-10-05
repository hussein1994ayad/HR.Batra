// رحلات المستخدم: التطبيق الحقيقي (HRProApp + الموجّه الحقيقي + AppChrome) يُستعمل مثل الموظف والمدير —
// ضغط، كتابة، كيبورد يطلع ويتسكّر، نوافذ تأكيد، رجوع بالزر وبالسحب من حافة الشاشة، كاميرا مرفوضة ثم مقبولة.
// نفس الرحلات تشتغل محلياً (test/screens/journeys_test.dart بأسلوب iOS) وعلى محاكيات الآيفون الحقيقية
// (integration_test/user_journeys_test.dart). البيانات وهمية بالكامل (FakeBackend) — ما تلمس القاعدة.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/providers/app_container.dart';
import 'package:hr_pro/core/providers/auth_provider.dart';
import 'package:hr_pro/core/routes/app_router.dart';
import 'package:hr_pro/main.dart' show HRProApp;
import 'package:hr_pro/presentation/shared/ui/ui.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'fake_backend.dart';

typedef Shot = Future<void> Function(String name);

class Journey {
  const Journey(this.name, this.role, this.run);
  final String name;
  final String role;
  final Future<void> Function(JourneyDriver d) run;
}

/// كاميرا/معرض وهمي: يرجع صورة حقيقية، أو يرمي "الصلاحية مرفوضة" مثل الآيفون بعد أول رفض.
class FakeImagePicker extends ImagePickerPlatform {
  String mode = 'image'; // image | denied | cancel
  int calls = 0;
  String? _path;

  /// يجهّز صورة PNG حقيقية بوقت حقيقي (رسمها ما يكمل داخل الوقت الوهمي للاختبار).
  Future<void> prepare() async {
    if (_path != null) return;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = const Color(0xFF3366FF));
    final image = await recorder.endRecording().toImage(64, 64);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('${Directory.systemTemp.path}/journey_pledge.png')..writeAsBytesSync(bytes!.buffer.asUint8List());
    _path = file.path;
  }

  Future<XFile?> _pick(String code) async {
    calls++;
    if (mode == 'denied') throw PlatformException(code: code, message: 'User denied access');
    if (mode == 'cancel') return null;
    return XFile(_path!);
  }

  @override
  Future<XFile?> getImageFromSource({required ImageSource source, ImagePickerOptions options = const ImagePickerOptions()}) =>
      _pick(source == ImageSource.camera ? 'camera_access_denied' : 'photo_access_denied');

  @override
  Future<List<XFile>> getMultiImageWithOptions({MultiImagePickerOptions options = const MultiImagePickerOptions()}) async {
    final f = await _pick('photo_access_denied');
    return f == null ? const [] : [f];
  }
}

class JourneyDriver {
  JourneyDriver(this.t, this.shot, this.picker);
  final WidgetTester t;
  final Shot shot;
  final FakeImagePicker picker;
  int _step = 0;
  String journey = '';

  bool get isIOS => Theme.of(t.element(find.byType(Navigator).first)).platform == TargetPlatform.iOS;
  MediaQueryData get mq => MediaQuery.of(t.element(find.byType(Navigator).first));

  /// يفتح التطبيق الحقيقي على [location] بدور [role].
  Future<void> open(String role, String location, {void Function(Map<String, List<Map<String, dynamic>>> tables)? data}) async {
    FakeBackend.reset(role: role);
    data?.call(FakeBackend.tables);
    appContainer.read(currentUserRoleProvider.notifier).state = role;
    appRouter.go(location);
    await t.pumpWidget(UncontrolledProviderScope(container: appContainer, child: const HRProApp()));
    await settle(8);
  }

  /// انتظار البيانات (الخادم الوهمي) والحركات — بوقت حقيقي قصير ثم إطارات.
  Future<void> settle([int rounds = 5]) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  /// لقطة + فحص: ماكو خطأ رسم، وماكو زر/حقل ثابت تحت النوتش أو شريط الهوم.
  Future<void> check(String label) async {
    expect(t.takeException(), isNull, reason: '[$journey] خطأ عند: $label');
    final unsafe = <String>[];
    final m = mq;
    for (final e in find.byWidgetPredicate((w) => w is ButtonStyleButton || w is IconButton || w is EditableText || w is FloatingActionButton || w is CupertinoDialogAction).evaluate()) {
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      if (find.ancestor(of: find.byWidget(e.widget), matching: find.byType(Scrollable)).evaluate().isNotEmpty) continue;
      if (!_onTopRoute(e)) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (r.height == 0 || r.bottom <= 0 || r.top >= m.size.height) continue;
      if (r.top < m.viewPadding.top - 1 || r.bottom > m.size.height - m.viewPadding.bottom + 1) {
        unsafe.add('${e.widget.runtimeType} @ ${r.top.round()}..${r.bottom.round()}');
      }
    }
    expect(unsafe, isEmpty, reason: '[$journey] $label: عناصر بالمنطقة غير الآمنة (insets ${m.viewPadding})');
    _step++;
    await shot('j_${journey}_${_step.toString().padLeft(2, '0')}_$label');
  }

  bool _onTopRoute(Element e) {
    final route = ModalRoute.of(e);
    return route == null || route.isCurrent;
  }

  Finder text(String s) => find.text(s);
  Finder field(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(AppTextField)).first,
        matching: find.byType(EditableText),
      );

  Finder pickerField(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(AppPickerField)),
        matching: find.byType(InkWell),
      );

  Future<void> tap(Finder f, {int settleRounds = 4}) async {
    expect(f, findsWidgets, reason: '[$journey] ما لگيت العنصر ${f.toString(describeSelf: true)}. الظاهر: $texts');
    await t.ensureVisible(f.first);
    await settle(1);
    // مثل المستخدم: يضغط بس على شي ظاهر ومو مغطّى (بشريط علوي، رسالة، كيبورد...)
    expect(f.hitTestable(), findsWidgets, reason: '[$journey] ${f.toString(describeSelf: true)} مغطّى بعنصر ثاني. الظاهر: $texts');
    await t.tap(f.hitTestable().first);
    await settle(settleRounds);
  }

  /// يمرر الصفحة لتحت بإصبع (من منتصف الشاشة) لحد ما يطلع [f] — القوائم الطويلة ما تبني العناصر البعيدة.
  Future<void> scrollTo(Finder f) async {
    for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
      await t.dragFrom(Offset(mq.size.width / 2, mq.size.height * 0.6), const Offset(0, -300));
      await settle(1);
    }
    expect(f, findsWidgets, reason: '[$journey] ما وصلت بالتمرير لـ ${f.toString(describeSelf: true)}. الظاهر: $texts');
  }

  /// الرئيسية ظاهرة (بدون زر رجوع، وأزرار الخدمات موجودة).
  void expectHome(String why) {
    expect(find.text('طلب إجازة'), findsOneWidget, reason: '[$journey] $why. الظاهر: $texts');
    expect(find.byType(BackButton), findsNothing, reason: '[$journey] $why');
  }

  // الهاتف: الشريط السفلي؛ الآيباد: الشريط الجانبي
  Future<void> tapNav(String label) =>
      tap(find.descendant(of: find.byWidgetPredicate((w) => w is NavigationBar || w is NavigationRail), matching: find.text(label)));

  /// كيبورد آيفون حقيقي الارتفاع (336 بالأجهزة الحديثة، 260 بالـ SE) — الحقل المكتوب بيه لازم يبقى ظاهر فوگه.
  Future<void> keyboardUp() async {
    final h = mq.viewPadding.bottom > 0 ? 336.0 : 260.0;
    t.view.viewInsets = FakeViewPadding(bottom: h * t.view.devicePixelRatio);
    await settle(3);
  }

  Future<void> keyboardDown() async {
    t.view.resetViewInsets();
    await settle(2);
  }

  /// كل النصوص الظاهرة — للتشخيص.
  String get texts => find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(60).join(' | ');

  /// يكتب بحقل والكيبورد ظاهر، ويتأكد إن الحقل مو مغطّى بالكيبورد.
  Future<void> type(String label, String value) async {
    expect(find.text(label), findsWidgets, reason: '[$journey] الحقل "$label" مو موجود. الظاهر: $texts');
    final f = field(label);
    await t.ensureVisible(f);
    await settle(1);
    expect(f.hitTestable(), findsOneWidget, reason: '[$journey] الحقل "$label" مغطّى');
    await t.tap(f.hitTestable());
    await keyboardUp();
    await t.enterText(f, value);
    await settle(2);
    final r = t.getRect(f);
    final kb = mq.viewInsets.bottom;
    expect(r.bottom, lessThanOrEqualTo(mq.size.height - kb + 4), reason: '[$journey] الحقل "$label" مغطّى بالكيبورد');
    expect(r.top, greaterThanOrEqualTo(0), reason: '[$journey] الحقل "$label" طالع فوگ الشاشة');
  }

  bool get anyFieldFocused {
    final focus = FocusManager.instance.primaryFocus;
    return focus != null && focus.context?.widget is EditableText;
  }

  /// لمس مكان فارغ (نص عادي) — على الآيفون يسكّر الكيبورد.
  Future<void> tapEmpty(Finder plainText) async {
    expect(plainText, findsWidgets, reason: '[$journey] ما لگيت ${plainText.toString(describeSelf: true)}. الظاهر: $texts');
    await t.ensureVisible(plainText.first);
    await settle(1);
    expect(plainText.hitTestable(), findsWidgets, reason: '[$journey] المكان الفارغ مغطّى');
    await t.tap(plainText.hitTestable().first);
    await keyboardDown();
    if (isIOS) expect(anyFieldFocused, isFalse, reason: '[$journey] الكيبورد ما تسكّر باللمس خارج الحقل');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump();
  }

  /// الرسائل الظاهرة (SnackBar) — للتشخيص إذا خطوة ما صارت.
  String get snacks => find
      .descendant(of: find.byType(SnackBar), matching: find.byType(Text))
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .join(' | ');

  /// يسحب الرسالة السفلية لجوّه (مثل المستخدم) حتى ما تغطي الأزرار تحتها.
  Future<void> swipeAwaySnack() async {
    if (find.byType(SnackBar).evaluate().isEmpty) return;
    await t.drag(find.byType(SnackBar).first, const Offset(0, 300));
    await settle(3);
    expect(find.byType(SnackBar), findsNothing, reason: '[$journey] الرسالة ما انسحبت');
  }

  /// زر التأكيد بنافذة التأكيد (Cupertino على الآيفون).
  Future<void> confirm(String label) async {
    expect(find.byType(CupertinoAlertDialog).evaluate().isNotEmpty || find.byType(AlertDialog).evaluate().isNotEmpty, isTrue,
        reason: '[$journey] نافذة التأكيد ما طلعت. الرسائل: $snacks');
    if (isIOS) expect(find.byType(CupertinoAlertDialog), findsOneWidget, reason: '[$journey] نافذة التأكيد مو بأسلوب الآيفون');
    await check('confirm');
    await tap(find.text(label).last, settleRounds: 8);
  }

  /// رجوع: على الآيفون بالسحب من حافة الشاشة (RTL = الحافة اليمنى)، وإلا زر الرجوع.
  Future<void> back({bool swipe = false}) async {
    if (swipe && isIOS) {
      final size = mq.size;
      await t.dragFrom(Offset(size.width - 4, size.height / 2), Offset(-size.width * 0.7, 0));
      await settle(6);
    } else {
      await tap(find.byType(BackButton), settleRounds: 6);
    }
  }

  /// سحب النافذة لجوّه من مقبضها — مثل المستخدم.
  Future<void> closeSheet() async {
    final top = t.getRect(find.byType(BottomSheet).last).topCenter;
    await t.dragFrom(top + const Offset(0, 12), Offset(0, mq.size.height * 0.8));
    await settle(4);
    expect(find.byType(BottomSheet), findsNothing, reason: '[$journey] النافذة السفلية ما تسكّرت');
  }

  bool requested(String method, String pathPart) => FakeBackend.requests.any((r) => r.startsWith('$method ') && r.contains(pathPart));
}

final List<Journey> kJourneys = [
  Journey('employee_tabs', 'employee', (d) async {
    await d.open('employee', AppRoutes.employeeHome);
    await d.check('home');
    for (final tab in const ['الدوام', 'الإجازات', 'السلف', 'الإعدادات', 'الرئيسية']) {
      await d.tapNav(tab);
      await d.check('tab_$tab');
    }
  }),

  Journey('leave_request', 'employee', (d) async {
    // بدون إجازات سابقة حتى ما تتعارض التواريخ الافتراضية (التعارض نفسه يمنع الإرسال — صح)
    await d.open('employee', AppRoutes.employeeHome, data: (t) => t['leave_requests'] = []);
    await d.tap(find.text('طلب إجازة'));
    await d.check('form');
    await d.tap(d.pickerField('من'));
    expect(find.byType(DatePickerDialog), findsOneWidget, reason: 'منتقي التاريخ ما انفتح');
    await d.check('date_picker');
    await d.tap(find.text('الإلغاء').last);
    expect(find.byType(DatePickerDialog), findsNothing);
    await d.type('السبب', 'مراجعة طبية');
    await d.check('typing_reason');
    await d.tapEmpty(find.text('المدة'));
    await d.tap(find.text('مراجعة وإرسال'));
    await d.confirm('إرسال');
    expect(find.textContaining('وصل طلبك للإدارة'), findsOneWidget, reason: 'رسالة نجاح الإجازة');
    expect(d.requested('POST', 'leave_requests'), isTrue, reason: 'طلب الإجازة ما انرسل');
    await d.check('sent');
  }),

  Journey('loan_request', 'employee', (d) async {
    // بدون سلفة جارية (السلفة الجارية تمنع طلب جديد — صح)
    await d.open('employee', AppRoutes.employeeHome, data: (t) => t['loans'] = []);
    await d.tap(find.text('طلب سلفة'));
    await d.check('form');
    await d.type('مبلغ السلفة', '600000');
    await d.tapEmpty(find.text('مبلغ السلفة'));
    await d.tap(find.text('مراجعة وإرسال'));
    expect(find.textContaining('صوّر التعهد'), findsOneWidget, reason: 'لازم يطلب صورة التعهد');

    // الكاميرا مرفوضة (الآيفون بعد أول رفض): رسالة واضحة + زر الإعدادات بدل ما يصير ولا شي
    d.picker.mode = 'denied';
    await d.tap(find.text('تصوير التعهد'));
    expect(find.textContaining('صلاحية الكاميرا مرفوضة'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'الإعدادات'), findsOneWidget);
    await d.check('camera_denied');

    d.picker.mode = 'image';
    await d.swipeAwaySnack();
    await d.tap(find.text('تصوير التعهد'));
    expect(d.picker.calls, 2, reason: 'زر التصوير ما انضغط للمرة الثانية');
    expect(find.text('تم إرفاق الصورة'), findsOneWidget, reason: 'الصورة ما انرفقت. الرسائل: ${d.snacks}');
    await d.tap(find.text('مراجعة وإرسال'));
    await d.confirm('إرسال');
    expect(find.textContaining('وصل طلب السلفة'), findsOneWidget, reason: 'رسالة نجاح السلفة. الرسائل: ${d.snacks} الطلبات: ${FakeBackend.requests.where((r) => !r.startsWith('GET')).toList()}');
    expect(d.requested('POST', '/rest/v1/loans'), isTrue, reason: 'طلب السلفة ما انرسل');
    await d.check('sent');
  }),

  Journey('pages_and_back', 'employee', (d) async {
    await d.open('employee', AppRoutes.employeeHome);
    await d.tap(find.text('كشف الراتب'), settleRounds: 6);
    await d.check('payslips');
    await d.back();
    d.expectHome('زر الرجوع ما رجّع للرئيسية');

    await d.tap(find.text('دليل الموظفين'), settleRounds: 6);
    await d.check('directory');
    await d.t.enterText(find.byType(EditableText).first, 'علي');
    await d.settle(3);
    await d.check('directory_search');
    FocusManager.instance.primaryFocus?.unfocus();
    await d.settle(2);
    await d.back(swipe: true); // سحب من حافة الشاشة مثل الآيفون
    d.expectHome('الرجوع بالسحب من حافة الشاشة ما اشتغل');

    await d.tap(find.text('الإشعارات'), settleRounds: 6);
    await d.check('notifications');
    await d.back(swipe: true);
    d.expectHome('الرجوع من الإشعارات');
  }),

  Journey('settings_logout_dialog', 'employee', (d) async {
    await d.open('employee', AppRoutes.employeeHome);
    await d.tapNav('الإعدادات');
    await d.scrollTo(find.text('تسجيل الخروج'));
    await d.check('bottom_of_settings');
    await d.tap(find.text('تسجيل الخروج'));
    expect(find.text('تسجيل الخروج؟'), findsOneWidget);
    if (d.isIOS) expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await d.check('logout_dialog');
    await d.tap(find.text('إلغاء'));
    expect(find.text('تسجيل الخروج؟'), findsNothing, reason: 'نافذة الخروج ما تسكّرت بالإلغاء');
    await d.check('after_cancel');
  }),

  Journey('admin_dashboard', 'admin', (d) async {
    await d.open('admin', AppRoutes.adminDashboard);
    await d.check('dashboard');
    for (final tab in const ['الإجازات', 'السلف', 'الأجهزة', 'الأمان', 'القرارات']) {
      await d.tap(find.text(tab));
      await d.check('tab_$tab');
    }
    await d.tap(find.byTooltip('أدوات الإدارة'));
    await d.check('tools_sheet');
    await d.tap(find.text('الموظفون'), settleRounds: 6);
    await d.check('employees');
    await d.back(swipe: true);
    expect(find.text('لوحة الإدارة'), findsOneWidget, reason: 'الرجوع من الموظفين');
  }),

  Journey('admin_add_employee', 'admin', (d) async {
    await d.open('admin', AppRoutes.adminEmployeeManagement);
    await d.tap(find.byType(FloatingActionButton));
    await d.check('sheet');
    await d.type('الاسم الكامل', 'موظف تجربة');
    await d.type('الراتب الشهري (د.ع)', '750000');
    await d.check('typing_salary');
    // زر الإنشاء يوصل فوق الكيبورد بالتمرير
    await d.t.ensureVisible(find.text('إنشاء الحساب'));
    await d.settle(2);
    expect(d.t.getRect(find.text('إنشاء الحساب')).bottom, lessThanOrEqualTo(d.mq.size.height - d.mq.viewInsets.bottom + 1));
    await d.keyboardDown();
    await d.closeSheet();
    await d.check('closed');
  }),

  Journey('admin_create_loan', 'admin', (d) async {
    await d.open('admin', AppRoutes.adminLoans);
    await d.tap(find.byType(FloatingActionButton));
    await d.type('المبلغ (د.ع)', '1000000');
    await d.type('الأشهر', '5');
    expect(find.text(Fmt.iqd(200000)), findsWidgets, reason: 'القسط الشهري 1.000.000 ÷ 5. الظاهر: ${d.texts}');
    await d.check('typed');
    await d.tapEmpty(find.text('سلفة مباشرة لموظف'));
    await d.check('keyboard_closed');
    await d.closeSheet();
  }),

  Journey('admin_schedule', 'admin', (d) async {
    await d.open('admin', AppRoutes.adminBranchSchedule);
    await d.tap(find.text('فرع المنصور'));
    await d.check('editor');
    await d.tap(d.pickerField('بداية الدوام'));
    await d.check('time_picker');
    await d.tap(find.text('الإلغاء').last);
    expect(find.text('حفظ الجدول'), findsOneWidget, reason: 'إلغاء اختيار الوقت سكّر المحرر');
    await d.closeSheet();
  }),
];

/// يشغّل رحلة كاملة وينظّف بعدها.
Future<void> runJourney(WidgetTester tester, Journey j, Shot shot) async {
  final picker = FakeImagePicker();
  final previous = ImagePickerPlatform.instance;
  ImagePickerPlatform.instance = picker;
  await tester.runAsync(picker.prepare);
  final d = JourneyDriver(tester, shot, picker)..journey = j.name;
  try {
    await j.run(d);
  } finally {
    ImagePickerPlatform.instance = previous;
    tester.view.resetViewInsets();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(const SizedBox.shrink());
    final client = Supabase.instance.client;
    await tester.runAsync(() async {
      await client.removeAllChannels().timeout(const Duration(seconds: 2), onTimeout: () => const []);
      await client.realtime.disconnect().timeout(const Duration(seconds: 2), onTimeout: () {});
    });
    // مؤقتات إعادة المحاولة الداخلية تنتهي خلال دقائق وهمية (بالمحاكي الوقت حقيقي فما نحتاجها)
    if (tester.binding is AutomatedTestWidgetsFlutterBinding) await tester.pump(const Duration(minutes: 5));
  }
}
