// تدقيق 14/10/2026 — المرحلة 9: التطبيق بساعة بغداد مهما كان توقيت الموبايل، ويوم القطع من إعدادات السيرفر.
// (تشتغل نفس النتائج بأي توقيت: الفحص التلقائي يشغّل الكل بتوقيت بغداد، وجربناها بتوقيت لوس أنجلوس وطوكيو و UTC)

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/design/formatters.dart';
import 'package:hr_pro/core/logic/payroll_settings.dart';
import 'package:hr_pro/core/models/loan_model.dart';
import 'package:hr_pro/core/utils/company_time.dart';

void main() {
  test('company date follows Baghdad (UTC+3), not the device clock', () {
    expect(companyDateStr(DateTime.utc(2026, 10, 4, 20, 59)), '2026-10-04'); // 23:59 بغداد
    expect(companyDateStr(DateTime.utc(2026, 10, 4, 21)), '2026-10-05'); // 00:00 بغداد
    expect(companyDateStr(DateTime.utc(2026, 12, 31, 22)), '2027-01-01');
  });

  test('a local DateTime is converted through UTC first', () {
    final local = DateTime.utc(2026, 10, 5, 6).toLocal();
    expect(companyDateStr(local), '2026-10-05');
  });

  test('a server moment becomes Baghdad time (UTC+3), whatever the phone zone', () {
    final t = toCompanyTime(DateTime.utc(2026, 10, 15, 22, 30));
    expect([t.year, t.month, t.day, t.hour, t.minute], [2026, 10, 16, 1, 30]);
    expect(t.isUtc, isFalse);
  });

  test('Baghdad time back to the server moment', () {
    expect(companyWallToUtc(DateTime(2026, 10, 15, 9)), DateTime.utc(2026, 10, 15, 6));
    expect(companyWallToUtc(toCompanyTime(DateTime.utc(2026, 10, 15, 22, 30))), DateTime.utc(2026, 10, 15, 22, 30));
  });

  test('reading server values: a moment is shown in Baghdad, a plain date stays the same day', () {
    final moment = parseServerTime('2026-10-15T06:05:00+00:00')!;
    expect([moment.hour, moment.minute], [9, 5]);
    final day = parseServerTime('2026-10-15')!;
    expect([day.year, day.month, day.day, day.hour], [2026, 10, 15, 0]);
    expect(parseServerTime(null), isNull);
    expect(parseServerTime('not a date'), isNull);
  });

  test('times on screen are Baghdad times', () {
    expect(Fmt.time(DateTime.utc(2026, 10, 15, 6, 5)), '9:05 ص');
    expect(Fmt.time(DateTime.utc(2026, 10, 15, 11, 30)), '2:30 م');
    expect(Fmt.date(DateTime.utc(2026, 10, 15, 22, 30), withYear: true), '16/10/2026');
  });

  test('the cutoff day comes from the server settings', () {
    expect(PayrollSettings.cutoffDayFrom({'cutoff_day': 25}), 25);
    expect(PayrollSettings.cutoffDayFrom({'cutoff_day': '20'}), 20);
    expect(PayrollSettings.cutoffDayFrom({'cutoff_day': 40}), isNull);
    expect(PayrollSettings.cutoffDayFrom(null), isNull);
    expect(payrollMonthOf(DateTime(2026, 10, 26), cutoffDay: 25), DateTime(2026, 11));
    expect(payrollMonthOf(DateTime(2026, 10, 25), cutoffDay: 25), DateTime(2026, 10));

    final before = PayrollSettings.cutoffDay;
    PayrollSettings.apply({'cutoff_day': 20});
    expect(payrollMonthOf(DateTime(2026, 10, 21)), DateTime(2026, 11));
    PayrollSettings.apply({'something': 'else'});
    expect(PayrollSettings.cutoffDay, 20, reason: 'a bad value keeps the last good one');
    PayrollSettings.cutoffDay = before;
  });
}
