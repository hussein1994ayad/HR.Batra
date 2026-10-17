// تسجيل الموبايل بالإشعارات برقم التنصيب (FID): رمز نفس التنصيب القديم ينحذف حتى الإشعار ما يوصل مرتين.

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
}
