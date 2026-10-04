import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/presentation/employee/payslips/payslips_logic.dart';

void main() {
  group('payslipCycleDates', () {
    test('default cross-month cycle 25 → 24', () {
      expect(payslipCycleDates('2026-10', startDay: 25, endDay: 24), {'start': '2026-09-25', 'end': '2026-10-24'});
    });

    test('January starts in December of the previous year', () {
      expect(payslipCycleDates('2026-01', startDay: 25, endDay: 24), {'start': '2025-12-25', 'end': '2026-01-24'});
    });

    test('same-month cycle is clipped to the last day of the month', () {
      expect(payslipCycleDates('2026-02', startDay: 1, endDay: 31), {'start': '2026-02-01', 'end': '2026-02-28'});
    });

    test('cross-month start is clipped to the last day of the previous month', () {
      expect(payslipCycleDates('2026-03', startDay: 30, endDay: 29), {'start': '2026-02-28', 'end': '2026-03-29'});
    });

    test('invalid month text gives empty dates', () {
      expect(payslipCycleDates('bad', startDay: 25, endDay: 24), {'start': '', 'end': ''});
    });
  });

  test('payslipMonthOf', () {
    expect(payslipMonthOf('2026-07'), (7, 2026));
    expect(payslipMonthOf('2026'), (1, 2026));
  });

  test('itemsIncludedInSlip keeps linked items and manual items recorded before the slip', () {
    final slipCreated = DateTime.utc(2026, 10, 1, 12);
    final rows = <Map<String, dynamic>>[
      {'id': 'linked', 'salary_slip_id': 's1'},
      {'id': 'other-slip', 'salary_slip_id': 's2'},
      {'id': 'before', 'created_at': '2026-09-30T10:00:00Z'},
      {'id': 'after', 'created_at': '2026-10-02T10:00:00Z'},
      {'id': 'no-date'},
    ];
    final kept = itemsIncludedInSlip(rows, slipId: 's1', slipCreated: slipCreated).map((r) => r['id']).toList();
    expect(kept, ['linked', 'before', 'no-date']);
    expect(itemsIncludedInSlip(rows, slipId: 's1', slipCreated: null).length, 4);
  });
}
