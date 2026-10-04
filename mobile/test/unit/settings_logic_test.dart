import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/theme/app_theme.dart';
import 'package:hr_pro/presentation/employee/settings/settings_logic.dart';
import 'package:hr_pro/presentation/employee/settings/widgets/settings_widgets.dart';

void main() {
  group('avatarStoragePath', () {
    test('extracts the path after the avatars bucket', () {
      expect(avatarStoragePath('https://x.supabase.co/storage/v1/object/public/avatars/u1/123.jpg'), 'u1/123.jpg');
    });

    test('empty, foreign or bucket-only urls give null', () {
      expect(avatarStoragePath(''), isNull);
      expect(avatarStoragePath('https://example.com/pic.png'), isNull);
      expect(avatarStoragePath('https://x.supabase.co/storage/v1/object/public/avatars'), isNull);
    });
  });

  testWidgets('SettingsNotificationsCard shows the enable button only when off', (tester) async {
    var taps = 0;
    Widget host(bool granted) => MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: SettingsNotificationsCard(granted: granted, onEnable: () => taps++)),
        );
    await tester.pumpWidget(host(false));
    expect(find.text('الإشعارات متوقفة'), findsOneWidget);
    await tester.tap(find.text('تفعيل'));
    expect(taps, 1);

    await tester.pumpWidget(host(true));
    expect(find.text('الإشعارات مفعّلة'), findsOneWidget);
    expect(find.text('تفعيل'), findsNothing);
  });
}
