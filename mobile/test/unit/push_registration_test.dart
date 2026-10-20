// تسجيل الموبايل بالإشعارات برقم التنصيب (FID): رمز نفس التنصيب القديم ينحذف حتى الإشعار ما يوصل مرتين.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/logic/push_registration.dart';

void main() {
  const fid = 'cX1a_b-2Zz9QwErTyUiOpA';

  test('the old token of the same install is found by its prefix', () {
    expect(oldTokensOfInstall(fid, ['$fid:APA91bHk_old', 'other:APA91bxyz', fid]), ['$fid:APA91bHk_old']);
  });

  test('the new number itself and other phones are never removed', () {
    expect(oldTokensOfInstall(fid, [fid, 'dOther_fid_22chars_xx', 'dOther_fid_22chars_xx:APA91b']), isEmpty);
  });

  test('a token that only starts with the same letters but is another install stays', () {
    expect(oldTokensOfInstall(fid, ['${fid}Z:APA91b']), isEmpty);
  });

  // بدون هذا الإعداد Firebase يرفض register() ("API disabled") وما يوصل أي رقم للسيرفر (20/10/2026)
  test('Android manifest turns on registration by installation id', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      RegExp(r'android:name="firebase_messaging_installation_id_enabled"\s+android:value="true"').hasMatch(manifest),
      isTrue,
    );
  });

  test('iOS Info.plist turns on registration by installation id', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(RegExp(r'<key>FirebaseMessagingInstallationIdEnabled</key>\s*<true/>').hasMatch(plist), isTrue);
  });
}
