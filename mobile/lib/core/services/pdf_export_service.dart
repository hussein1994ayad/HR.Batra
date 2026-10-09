// =========================================================================
// نظام HR Pro v6.0 - خدمة توليد وتصدير كشف الراتب الشهري PDF للموظف
// =========================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../constants/constants.dart';
import '../design/formatters.dart';
import '../utils/app_log.dart';
import 'share_helper.dart';

class PdfExportService {
  /// توليد كشف راتب شهري PDF وحفظه في مستندات الجهاز (ونسخة في التنزيلات على Android).
  /// يرجع مسار الملف.
  static Future<String> generatePayslipPdf({
    required String employeeName,
    required String branchName,
    required String workMonth,
    required double basicSalary,
    required double allowances,
    required double deductions,
    required double loansDeduction,
    required double netSalary,
    List<Map<String, dynamic>>? bonusesList,
    List<Map<String, dynamic>>? deductionsList,
  }) async {
    final bytes = await buildPayslipPdfBytes(
      employeeName: employeeName,
      branchName: branchName,
      workMonth: workMonth,
      basicSalary: basicSalary,
      allowances: allowances,
      deductions: deductions,
      loansDeduction: loansDeduction,
      netSalary: netSalary,
      bonusesList: bonusesList,
      deductionsList: deductionsList,
    );

    final directory = await getApplicationDocumentsDirectory();
    final cleanName = employeeName.replaceAll(' ', '_').replaceAll('/', '_');
    final String fileName = 'كشف_راتب_${cleanName}_$workMonth.pdf';
    final String path = '${directory.path}/$fileName';
    await File(path).writeAsBytes(bytes, flush: true);

    // نسخة إضافية في مجلد التنزيلات العام على أندرويد لسهولة الوصول المباشر
    try {
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (downloadDir.existsSync()) {
          await File('${downloadDir.path}/$fileName').writeAsBytes(bytes, flush: true);
        }
      }
    } catch (e) {
      appLog('تعذّر حفظ نسخة PDF بالتنزيلات: $e');
    }

    return path;
  }

  /// مبلغ بفواصل الآلاف + العملة، بدون إشارة (الإشارة في عمود النوع حتى لا
  /// تنقلب مع اتجاه النص العربي).
  @visibleForTesting
  static String money(num amount) => '${NumberFormat('#,##0', 'en').format(amount.abs().round())} ${AppConstants.currency}';

  /// "2026-09" ← "الشهر التاسع 2026" (بدون أقواس: تنعكس في PDF العربي)
  @visibleForTesting
  static String monthLabel(String workMonth) {
    final parts = workMonth.split('-');
    final m = parts.length == 2 ? int.tryParse(parts[1]) : null;
    final y = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    if (m == null || y == null || m < 1 || m > 12) return workMonth;
    return Fmt.monthNumber(m, y);
  }

  /// بناء محتوى كشف الراتب PDF (بدون حفظ) — مفصول لإمكانية اختباره.
  static Future<List<int>> buildPayslipPdfBytes({
    required String employeeName,
    required String branchName,
    required String workMonth,
    required double basicSalary,
    required double allowances,
    required double deductions,
    required double loansDeduction,
    required double netSalary,
    List<Map<String, dynamic>>? bonusesList,
    List<Map<String, dynamic>>? deductionsList,
  }) async {
    // خط IBM Plex Sans Arabic: فيه كل أشكال الحروف العربية التي تحتاجها مكتبة PDF
    // (Cairo ينقصه الألف المنفصل وأشكال أخرى، فكانت الحروف تختفي من الكشف).
    final regular = (await rootBundle.load('assets/fonts/pdf/IBMPlexSansArabic-Regular.ttf')).buffer.asUint8List();
    final bold = (await rootBundle.load('assets/fonts/pdf/IBMPlexSansArabic-Bold.ttf')).buffer.asUint8List();

    final PdfDocument document = PdfDocument();
    document.pageSettings.size = PdfPageSize.a4;
    document.pageSettings.margins.all = 32;
    final PdfPage page = document.pages.add();
    final Size size = page.getClientSize();
    final PdfGraphics g = page.graphics;

    final titleFont = PdfTrueTypeFont(bold, 20);
    final headFont = PdfTrueTypeFont(bold, 12);
    final labelFont = PdfTrueTypeFont(bold, 10);
    final bodyFont = PdfTrueTypeFont(regular, 10);
    final smallFont = PdfTrueTypeFont(regular, 8.5);
    final netFont = PdfTrueTypeFont(bold, 15);

    final right = PdfStringFormat(
      alignment: PdfTextAlignment.right,
      lineAlignment: PdfVerticalAlignment.middle,
      textDirection: PdfTextDirection.rightToLeft,
    );
    final center = PdfStringFormat(
      alignment: PdfTextAlignment.center,
      lineAlignment: PdfVerticalAlignment.middle,
      textDirection: PdfTextDirection.rightToLeft,
    );

    final navy = PdfColor(15, 23, 42);
    final teal = PdfColor(13, 148, 136);
    final tealSoft = PdfColor(204, 251, 241);
    final slate = PdfColor(71, 85, 105);
    final line = PdfColor(226, 232, 240);
    final soft = PdfColor(248, 250, 252);
    final green = PdfColor(5, 150, 105);
    final red = PdfColor(220, 38, 38);
    final white = PdfColor(255, 255, 255);

    // ارتفاع سطر كافٍ للخط (مكتبة PDF تحذف السطر كله إذا كان المستطيل أقصر منه)
    double lineH(PdfFont f) => f.height * 1.35;
    void text(String s, PdfFont f, PdfColor c, double y, {double x = 0, double? w, PdfStringFormat? fmt}) {
      g.drawString(s, f, brush: PdfSolidBrush(c), bounds: Rect.fromLTWH(x, y, w ?? size.width, lineH(f)), format: fmt ?? right);
    }

    double y = 0;

    // ---------------- الترويسة ----------------
    const headerH = 78.0;
    g.drawRectangle(brush: PdfSolidBrush(navy), bounds: Rect.fromLTWH(0, y, size.width, headerH));
    g.drawRectangle(brush: PdfSolidBrush(teal), bounds: Rect.fromLTWH(0, y + headerH - 4, size.width, 4));
    const pad = 18.0;
    text('كشف راتب شهري', titleFont, white, y + 12, x: pad, w: size.width - 2 * pad);
    text('HR Pro · ${monthLabel(workMonth)}', bodyFont, PdfColor(153, 246, 228), y + 12 + lineH(titleFont), x: pad, w: size.width - 2 * pad);
    final ltrLeft = PdfStringFormat(lineAlignment: PdfVerticalAlignment.middle);
    final leftArabic = PdfStringFormat(textDirection: PdfTextDirection.rightToLeft);
    text('تاريخ الإصدار', smallFont, PdfColor(148, 163, 184), y + 14, x: pad, w: size.width / 2, fmt: leftArabic);
    text(DateFormat('yyyy-MM-dd  HH:mm').format(DateTime.now()), smallFont, PdfColor(203, 213, 225), y + 14 + lineH(smallFont),
        x: pad, w: size.width / 2, fmt: ltrLeft);
    y += headerH + 18;

    // ---------------- بيانات الموظف ----------------
    // الجداول تُرسم من اليسار؛ نعكس الأعمدة حتى يكون العمود 0 أقصى اليمين (قراءة عربية)
    PdfGrid grid(List<double> widths) {
      final gr = PdfGrid();
      gr.columns.add(count: widths.length);
      for (var i = 0; i < widths.length; i++) {
        gr.columns[widths.length - 1 - i].width = size.width * widths[i];
      }
      gr.style.cellPadding = PdfPaddings(left: 8, right: 8, top: 7, bottom: 7);
      return gr;
    }

    PdfGridCell rc(PdfGridRow r, int i) => r.cells[r.cells.count - 1 - i];

    PdfGridCellStyle cell(PdfFont f, {PdfColor? color, PdfColor? bg, PdfStringFormat? fmt}) => PdfGridCellStyle(
          font: f,
          textBrush: PdfSolidBrush(color ?? navy),
          backgroundBrush: bg == null ? null : PdfSolidBrush(bg),
          format: fmt ?? right,
          borders: PdfBorders(left: PdfPen(line), right: PdfPen(line), top: PdfPen(line), bottom: PdfPen(line)),
        );

    final info = grid([0.18, 0.32, 0.18, 0.32]);
    void infoRow(String l1, String v1, String l2, String v2) {
      final r = info.rows.add();
      rc(r, 0).value = l1;
      rc(r, 1).value = v1;
      rc(r, 2).value = l2;
      rc(r, 3).value = v2;
      rc(r, 0).style = cell(labelFont, color: slate, bg: soft);
      rc(r, 1).style = cell(bodyFont);
      rc(r, 2).style = cell(labelFont, color: slate, bg: soft);
      rc(r, 3).style = cell(bodyFont);
    }

    infoRow('اسم الموظف', employeeName, 'الشهر', monthLabel(workMonth));
    infoRow('الفرع', branchName.isEmpty ? 'المقر الرئيسي' : branchName, 'العملة', 'دينار عراقي');
    y = info.draw(page: page, bounds: Rect.fromLTWH(0, y, size.width, 0))!.bounds.bottom + 20;

    // ---------------- ملخص الراتب ----------------
    text('ملخص الراتب', headFont, navy, y);
    y += lineH(headFont) + 4;

    final summary = grid([0.50, 0.28, 0.22]);
    summary.headers.add(1);
    final h = summary.headers[0];
    for (final (i, t) in ['البند', 'المبلغ', 'النوع'].indexed) {
      rc(h, i).value = t;
      rc(h, i).style = cell(labelFont, color: white, bg: teal, fmt: i == 0 ? right : center);
    }
    void summaryRow(String label, num amount, String kind, PdfColor color) {
      final r = summary.rows.add();
      rc(r, 0).value = label;
      rc(r, 1).value = money(amount);
      rc(r, 2).value = kind;
      rc(r, 0).style = cell(bodyFont);
      rc(r, 1).style = cell(labelFont, color: color, fmt: center);
      rc(r, 2).style = cell(bodyFont, color: color, fmt: center);
    }

    summaryRow('الراتب الأساسي', basicSalary, 'مستحق +', navy);
    if (allowances > 0) summaryRow('المكافآت والبدلات', allowances, 'إضافة +', green);
    if (deductions > 0) summaryRow('خصومات الغياب والتأخير والجزاءات', deductions, 'خصم −', red);
    if (loansDeduction > 0) summaryRow('قسط السلفة', loansDeduction, 'خصم −', red);
    y = summary.draw(page: page, bounds: Rect.fromLTWH(0, y, size.width, 0))!.bounds.bottom + 12;

    // ---------------- الصافي ----------------
    final netH = lineH(netFont) + 18;
    final negative = netSalary < 0;
    g.drawRectangle(
      brush: PdfSolidBrush(negative ? PdfColor(254, 226, 226) : tealSoft),
      pen: PdfPen(negative ? red : teal),
      bounds: Rect.fromLTWH(0, y, size.width, netH),
    );
    text(negative ? 'الصافي (مبلغ مستحق على الموظف)' : 'صافي الراتب المستحق', headFont, navy, y + (netH - lineH(headFont)) / 2,
        x: size.width * 0.45, w: size.width * 0.55 - 12);
    text(money(netSalary), netFont, negative ? red : teal, y + 9, x: 12, w: size.width * 0.45,
        fmt: PdfStringFormat(textDirection: PdfTextDirection.rightToLeft));
    y += netH + 22;

    // ---------------- تفاصيل المكافآت والخصومات ----------------
    final items = [
      for (final b in bonusesList ?? const <Map<String, dynamic>>[]) (true, b),
      for (final d in deductionsList ?? const <Map<String, dynamic>>[]) (false, d),
    ];
    if (items.isNotEmpty) {
      text('تفاصيل المكافآت والخصومات', headFont, navy, y);
      y += lineH(headFont) + 4;
      final details = grid([0.16, 0.20, 0.46, 0.18]);
      details.headers.add(1);
      for (final (i, t) in ['النوع', 'المبلغ', 'السبب', 'التاريخ'].indexed) {
        rc(details.headers[0], i).value = t;
        rc(details.headers[0], i).style = cell(labelFont, color: white, bg: navy, fmt: i == 2 ? right : center);
      }
      for (final (isBonus, m) in items) {
        final r = details.rows.add();
        final color = isBonus ? green : red;
        rc(r, 0).value = isBonus ? 'مكافأة' : 'خصم';
        rc(r, 1).value = money((m['amount'] as num?) ?? 0);
        rc(r, 2).value = (m['reason']?.toString().trim().isNotEmpty ?? false) ? m['reason'].toString() : (isBonus ? 'مكافأة' : 'خصم إداري');
        rc(r, 3).value = m['issue_date']?.toString() ?? '—';
        rc(r, 0).style = cell(bodyFont, color: color, fmt: center);
        rc(r, 1).style = cell(labelFont, color: color, fmt: center);
        rc(r, 2).style = cell(bodyFont);
        rc(r, 3).style = cell(bodyFont, color: slate, fmt: center);
      }
      y = details.draw(page: page, bounds: Rect.fromLTWH(0, y, size.width, 0))!.bounds.bottom + 26;
    }

    // ---------------- التواقيع ----------------
    const signH = 64.0;
    if (y + signH + 30 > size.height) y = size.height - signH - 30;
    final colW = size.width / 3;
    for (final (i, t) in ['توقيع الموظف', 'المحاسب', 'الموارد البشرية'].indexed) {
      final x = size.width - colW * (i + 1);
      text(t, labelFont, slate, y, x: x, w: colW, fmt: center);
      g.drawLine(PdfPen(PdfColor(148, 163, 184), dashStyle: PdfDashStyle.dash), Offset(x + 20, y + signH - 8), Offset(x + colW - 20, y + signH - 8));
    }
    text('صدر إلكترونياً من نظام HR Pro — لا يحتاج ختماً إلا عند الطلب.', smallFont, PdfColor(148, 163, 184), size.height - lineH(smallFont),
        fmt: center);

    final List<int> bytes = await document.save();
    document.dispose();
    return bytes;
  }

  /// فتح ملف الـ PDF عبر عارض المستندات المفضل في الهاتف
  static Future<void> openPdfFile(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        // إذا تعذر الفتح المباشر، فتح نافذة المشاركة فوراً
        await sharePdfFile(filePath);
      }
    } catch (e) {
      appLog('تعذر فتح ملف PDF عبر OpenFilex: $e');
      await sharePdfFile(filePath);
    }
  }

  /// مشاركة ملف الـ PDF عبر واتساب أو البريد أو التطبيقات
  static Future<void> sharePdfFile(String filePath) async {
    try {
      await ShareHelper.shareParams(ShareParams(
        files: [XFile(filePath)],
        text: 'كشف الراتب الشهري الرسمي - HR Pro Batra',
      ));
    } catch (e) {
      appLog('تعذر مشاركة ملف PDF: $e');
    }
  }
}
