// =========================================================================
// HR Pro v6.0 - كشف الراتب PDF بخط Cairo المضمّن
// =========================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/services/pdf_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds an Arabic payslip PDF with the bundled Cairo font', () async {
    final bytes = await PdfExportService.buildPayslipPdfBytes(
      employeeName: 'أحمد علي',
      branchName: 'الفرع الرئيسي',
      workMonth: '2026-09',
      basicSalary: 1000000,
      allowances: 50000,
      deductions: 25000,
      loansDeduction: 100000,
      netSalary: 925000,
      bonusesList: [
        {'reason': 'مكافأة أداء', 'amount': 50000},
      ],
      deductionsList: [
        {'reason': 'خصم تأخير', 'amount': 25000},
      ],
    );

    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
