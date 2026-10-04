// إصلاحات توافق الآيفون: الكيبورد، شريط الهوم بالنوافذ السفلية، صلاحيات الكاميرا والموقع.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/presentation/employee/attendance/widgets/attendance_widgets.dart';
import 'package:hr_pro/presentation/shared/ui/ui.dart';
import 'package:hr_pro/presentation/shared/widgets/offline_banner.dart';

Widget _form(TargetPlatform platform) => MaterialApp(
      theme: AppTheme.darkTheme.copyWith(platform: platform),
      builder: (_, child) => AppChrome(child: child!),
      home: const Scaffold(
        body: Column(
          children: [
            TextField(key: Key('amount'), keyboardType: TextInputType.number),
            SizedBox(height: 300, child: Center(child: Text('مساحة فارغة'))),
          ],
        ),
      ),
    );

bool _hasFocus(WidgetTester tester) => tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

void main() {
  group('keyboard: tap outside closes it on iPhone', () {
    testWidgets('iOS: tapping empty space unfocuses the field', (tester) async {
      await tester.pumpWidget(_form(TargetPlatform.iOS));
      await tester.tap(find.byKey(const Key('amount')));
      await tester.pump();
      expect(_hasFocus(tester), isTrue);

      await tester.tap(find.text('مساحة فارغة'));
      await tester.pump();
      expect(_hasFocus(tester), isFalse);
    });

    testWidgets('iOS: tapping the field itself keeps the keyboard', (tester) async {
      await tester.pumpWidget(_form(TargetPlatform.iOS));
      await tester.tap(find.byKey(const Key('amount')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('amount')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(_hasFocus(tester), isTrue);
    });

    testWidgets('iOS: buttons still receive their taps', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
        builder: (_, child) => AppChrome(child: child!),
        home: Scaffold(body: Center(child: FilledButton(onPressed: () => pressed++, child: const Text('حفظ')))),
      ));
      await tester.tap(find.text('حفظ'));
      await tester.pump();
      expect(pressed, 1);
    });

    testWidgets('Android: unchanged (back button closes the keyboard)', (tester) async {
      await tester.pumpWidget(_form(TargetPlatform.android));
      await tester.tap(find.byKey(const Key('amount')));
      await tester.pump();
      await tester.tap(find.text('مساحة فارغة'));
      await tester.pump();
      expect(_hasFocus(tester), isTrue);
    });
  });

  group('sheetBottomPadding', () {
    Future<double> paddingWith(WidgetTester tester, MediaQueryData data) async {
      late double value;
      await tester.pumpWidget(MediaQuery(
        data: data,
        child: Builder(builder: (context) {
          value = sheetBottomPadding(context);
          return const SizedBox();
        }),
      ));
      return value;
    }

    testWidgets('stays above the home indicator when the keyboard is closed', (tester) async {
      expect(await paddingWith(tester, const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 34))), AppSpace.xl + 34);
    });

    testWidgets('follows the keyboard when it is open', (tester) async {
      expect(
        await paddingWith(tester, const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 34), viewInsets: EdgeInsets.only(bottom: 336))),
        AppSpace.xl + 336,
      );
    });

    testWidgets('no system bar: same as before', (tester) async {
      expect(await paddingWith(tester, const MediaQueryData()), AppSpace.xl);
    });
  });

  group('AppImagePicker messages', () {
    test('denied camera/photos → settings button with a clear message', () {
      expect(AppImagePicker.needsSettings('camera_access_denied'), isTrue);
      expect(AppImagePicker.needsSettings('photo_access_restricted'), isTrue);
      expect(AppImagePicker.errorMessage('camera_access_denied'), contains('الكاميرا'));
      expect(AppImagePicker.errorMessage('photo_access_denied'), contains('الصور'));
    });

    test('other failures → retry message, no settings button', () {
      expect(AppImagePicker.needsSettings('multiple_request'), isFalse);
      expect(AppImagePicker.errorMessage('invalid_image'), contains('حاول مرة ثانية'));
    });
  });

  group('AttendanceErrorCard', () {
    Widget host(bool showSettings) => MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: AttendanceErrorCard(message: 'رسالة', showSettings: showSettings, onRetry: () {})),
        );

    testWidgets('permission needs Settings → "open settings" button', (tester) async {
      await tester.pumpWidget(host(true));
      expect(find.text('فتح الإعدادات'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });

    testWidgets('other errors → retry only', (tester) async {
      await tester.pumpWidget(host(false));
      expect(find.text('فتح الإعدادات'), findsNothing);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });
  });
}
