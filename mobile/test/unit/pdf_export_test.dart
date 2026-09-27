// =========================================================================
// HR Pro - كشف الراتب PDF (خط IBM Plex Sans Arabic المضمّن)
// =========================================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:hr_pro/core/services/pdf_export_service.dart';

// --dart-define=PDF_OUT=path يحفظ الكشف لمعاينته بالعين
const _out = String.fromEnvironment('PDF_OUT');

Future<List<int>> _build({double net = 925000, double loans = 100000}) => PdfExportService.buildPayslipPdfBytes(
      employeeName: 'أحمد علي الساعدي',
      branchName: 'مكتب بغداد الرئيسي',
      workMonth: '2026-09',
      basicSalary: 1000000,
      allowances: 50000,
      deductions: 25000,
      loansDeduction: loans,
      netSalary: net,
      bonusesList: [
        {'reason': 'مكافأة أداء', 'amount': 50000, 'issue_date': '2026-09-10'},
      ],
      deductionsList: [
        {'reason': 'تأخير 3 أيام', 'amount': 25000, 'issue_date': '2026-09-20'},
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds an Arabic payslip PDF', () async {
    final bytes = await _build();
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    if (_out.isNotEmpty) File(_out).writeAsBytesSync(bytes);
  });

  test('a negative net still renders', () async {
    final bytes = await _build(net: -66667, loans: 1141667);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    if (_out.isNotEmpty) File(_out.replaceFirst('.pdf', '-negative.pdf')).writeAsBytesSync(bytes);
  });

  test('amounts use thousands separators and no sign', () {
    expect(PdfExportService.money(666666.6), '666,667 د.ع');
    expect(PdfExportService.money(-66667), '66,667 د.ع');
  });

  test('the PDF font has every Arabic presentation form the PDF library uses', () async {
    // مكتبة PDF تحوّل الحروف العربية إلى أشكال العرض (U+FE70–U+FEFC)؛ أي شكل
    // ناقص في الخط يختفي من الكشف (هذا ما كان يحصل للألف مع خط Cairo).
    for (final f in ['IBMPlexSansArabic-Regular.ttf', 'IBMPlexSansArabic-Bold.ttf']) {
      final data = await rootBundle.load('assets/fonts/pdf/$f');
      expect(_hasPresentationFormsB(data.buffer.asByteData()), isTrue, reason: f);
    }
  });
}

/// يقرأ جدول cmap (الصيغة 4) ويتأكد من وجود الألف المنفصل واللام ألف ونهاية الهاء.
bool _hasPresentationFormsB(ByteData d) {
  final numTables = d.getUint16(4);
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes([for (var k = 0; k < 4; k++) d.getUint8(rec + k)]);
    if (tag != 'cmap') continue;
    final cmap = d.getUint32(rec + 8);
    final n = d.getUint16(cmap + 2);
    for (var t = 0; t < n; t++) {
      final off = cmap + d.getUint32(cmap + 4 + t * 8 + 4);
      if (d.getUint16(off) != 4) continue;
      final segX2 = d.getUint16(off + 6);
      bool has(int cp) {
        for (var s = 0; s < segX2; s += 2) {
          final end = d.getUint16(off + 14 + s);
          final start = d.getUint16(off + 16 + segX2 + s);
          if (cp >= start && cp <= end) return true;
        }
        return false;
      }

      return [0xFE8D, 0xFE8E, 0xFEFB, 0xFEEA, 0xFEDF].every(has);
    }
  }
  return false;
}
