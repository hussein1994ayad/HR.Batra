// ترتيب الشهر في كشوف الرواتب والسلف: "راتب الشهر الخامس 2026".

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/design/design.dart';
import 'package:hr_pro/core/services/pdf_export_service.dart';

void main() {
  test('payslips and installments are labelled by month number', () {
    expect(Fmt.monthNumber(5, 2026), 'الشهر الخامس 2026');
    expect(Fmt.monthNumber(12, 2026), 'الشهر الثاني عشر 2026');
    expect(Fmt.monthOf(DateTime(2026, 11)), 'الشهر الحادي عشر 2026');
    expect(Fmt.monthOf(null), '—');
    expect(PdfExportService.monthLabel('2026-05'), 'الشهر الخامس 2026');
    expect(PdfExportService.monthLabel('bad'), 'bad');
  });
}
