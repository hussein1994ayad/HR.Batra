// رقم الشهر في كشوف الرواتب والسلف: "راتب شهر 5 سنة 2026".

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/design/design.dart';
import 'package:hr_pro/core/services/pdf_export_service.dart';

void main() {
  test('payslips and installments are labelled by month number', () {
    expect(Fmt.monthNumber(5, 2026), 'شهر 5 سنة 2026');
    expect(Fmt.monthOf(DateTime(2026, 11, 1)), 'شهر 11 سنة 2026');
    expect(Fmt.monthOf(null), '—');
    expect(PdfExportService.monthLabel('2026-05'), 'شهر 5 سنة 2026 · أيار');
    expect(PdfExportService.monthLabel('bad'), 'bad');
  });
}
