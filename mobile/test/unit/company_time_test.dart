import 'package:flutter_test/flutter_test.dart';
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
}
