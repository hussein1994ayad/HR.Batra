import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/models/models.dart';
import 'package:hr_pro/presentation/employee/payslips/payslips_logic.dart';

void main() {
  test('one label list covers every payroll event type (same as the web)', () {
    const types = ['absence', 'late', 'early_leave', 'missing_punch', 'unpaid_leave', 'paid_leave', 'overtime',
      'manual_deduction', 'bonus', 'allowance', 'advance', 'adjustment', 'other'];
    for (final t in types) {
      expect(kPayrollEventLabels[t], isNotNull, reason: t);
    }
  });

  test('slip lines use the shared labels and keep the "بند" fallback for unknown types', () {
    final details = slipLinesToDetails([
      {'line_type': 'allowance', 'event_date': '2026-10-01', 'amount': 5000, 'direction': 1},
      {'line_type': 'other', 'event_date': '2026-10-02', 'amount': 1000, 'direction': -1},
      {'line_type': 'something_new', 'event_date': '2026-10-03', 'amount': 1000, 'direction': -1},
    ]);
    expect(details.map((d) => d.reason), ['مخصصات', 'أخرى', 'بند']);
  });
}
