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
    } catch (_) {}

    return path;
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
    // 1. خط Cairo المضمّن (رخصة OFL حرة) يدعم العربية بالكامل
    final fontData = await rootBundle.load('assets/google_fonts/Cairo-Regular.ttf');
    final boldFontData = await rootBundle.load('assets/google_fonts/Cairo-Bold.ttf');
    final fontBytes = fontData.buffer.asUint8List();
    final boldFontBytes = boldFontData.buffer.asUint8List();

    // 2. إنشاء مستند PDF جديد
    final PdfDocument document = PdfDocument();
    document.pageSettings.size = PdfPageSize.a4;
    document.pageSettings.margins.all = 25;

    final PdfPage page = document.pages.add();
    final Size pageSize = page.getClientSize();
    double currentY = 0;

    // 3. خطوط وتنسيقات تدعم اللغة العربية 100%
    final PdfFont titleFont = PdfTrueTypeFont(boldFontBytes, 16);
    final PdfFont subtitleFont = PdfTrueTypeFont(boldFontBytes, 11);
    final PdfFont bodyFont = PdfTrueTypeFont(fontBytes, 9);
    final PdfFont boldBodyFont = PdfTrueTypeFont(boldFontBytes, 9);
    final PdfFont smallFont = PdfTrueTypeFont(fontBytes, 8);

    final PdfStringFormat rtlCenterFormat = PdfStringFormat(
      alignment: PdfTextAlignment.center,
      textDirection: PdfTextDirection.rightToLeft,
    );
    final PdfStringFormat rtlRightFormat = PdfStringFormat(
      alignment: PdfTextAlignment.right,
      textDirection: PdfTextDirection.rightToLeft,
    );

    // ألوان الهوية البصرية
    final PdfColor brandDark = PdfColor(15, 23, 42);       // #0F172A
    final PdfColor brandTeal = PdfColor(13, 148, 136);     // #0D9488
    final PdfColor brandCyan = PdfColor(6, 182, 212);      // #06B6D4
    final PdfColor textSlate = PdfColor(51, 65, 85);       // #334155
    final PdfColor successGreen = PdfColor(16, 185, 129);  // #10B981
    final PdfColor dangerRed = PdfColor(239, 68, 68);      // #EF4444
    final PdfColor lightBg = PdfColor(248, 250, 252);      // #F8FAFC

    // -------------------------------------------------------------
    // الترويسة الرئيسية للشركة
    // -------------------------------------------------------------
    page.graphics.drawRectangle(
      brush: PdfSolidBrush(brandDark),
      bounds: Rect.fromLTWH(0, currentY, pageSize.width, 60),
    );

    page.graphics.drawString(
      'HR PRO BATRA - كشف الراتب الشهري الرسمي',
      titleFont,
      brush: PdfSolidBrush(PdfColor(255, 255, 255)),
      bounds: Rect.fromLTWH(0, currentY + 12, pageSize.width, 24),
      format: rtlCenterFormat,
    );

    final String exportDateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    page.graphics.drawString(
      'تاريخ الاستخراج: $exportDateStr | النظام المالي المعتمد v6.0',
      smallFont,
      brush: PdfSolidBrush(brandCyan),
      bounds: Rect.fromLTWH(0, currentY + 38, pageSize.width, 16),
      format: rtlCenterFormat,
    );

    currentY += 75;

    // -------------------------------------------------------------
    // بطاقة بيانات الموظف والدورة المالية
    // -------------------------------------------------------------
    final PdfGrid infoGrid = PdfGrid();
    infoGrid.columns.add(count: 4);
    infoGrid.columns[0].width = pageSize.width * 0.25;
    infoGrid.columns[1].width = pageSize.width * 0.25;
    infoGrid.columns[2].width = pageSize.width * 0.25;
    infoGrid.columns[3].width = pageSize.width * 0.25;

    infoGrid.style.cellPadding = PdfPaddings(left: 6, top: 6, right: 6, bottom: 6);

    PdfGridRow row1 = infoGrid.rows.add();
    row1.cells[0].value = 'اسم الموظف:';
    row1.cells[1].value = employeeName;
    row1.cells[2].value = 'الشهر المالي:';
    row1.cells[3].value = workMonth;

    PdfGridRow row2 = infoGrid.rows.add();
    row2.cells[0].value = 'الفرع / الموقع:';
    row2.cells[1].value = branchName.isEmpty ? 'المقر الرئيسي' : branchName;
    row2.cells[2].value = 'العملة المعتمدة:';
    row2.cells[3].value = 'دينار عراقي (IQD)';

    for (int i = 0; i < infoGrid.rows.count; i++) {
      final r = infoGrid.rows[i];
      r.cells[0].style.font = boldBodyFont;
      r.cells[0].style.backgroundBrush = PdfSolidBrush(lightBg);
      r.cells[0].style.stringFormat = rtlRightFormat;

      r.cells[1].style.font = boldBodyFont;
      r.cells[1].style.textBrush = PdfSolidBrush(brandTeal);
      r.cells[1].style.stringFormat = rtlRightFormat;

      r.cells[2].style.font = boldBodyFont;
      r.cells[2].style.backgroundBrush = PdfSolidBrush(lightBg);
      r.cells[2].style.stringFormat = rtlRightFormat;

      r.cells[3].style.font = boldBodyFont;
      r.cells[3].style.textBrush = PdfSolidBrush(textSlate);
      r.cells[3].style.stringFormat = rtlRightFormat;
    }

    final PdfLayoutResult infoResult = infoGrid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, currentY, pageSize.width, 0),
    )!;

    currentY = infoResult.bounds.bottom + 18;

    // -------------------------------------------------------------
    // ملخص الموقف المالي وكشف المستحقات والخصومات
    // -------------------------------------------------------------
    page.graphics.drawString(
      '1. تفاصيل وملخص الموقف المالي للشهر:',
      subtitleFont,
      brush: PdfSolidBrush(brandDark),
      bounds: Rect.fromLTWH(0, currentY, pageSize.width, 20),
      format: rtlRightFormat,
    );

    currentY += 24;

    final PdfGrid summaryGrid = PdfGrid();
    summaryGrid.columns.add(count: 3);
    summaryGrid.columns[0].width = pageSize.width * 0.40;
    summaryGrid.columns[1].width = pageSize.width * 0.35;
    summaryGrid.columns[2].width = pageSize.width * 0.25;

    summaryGrid.headers.add(1);
    final PdfGridRow headerRow = summaryGrid.headers[0];
    headerRow.cells[0].value = 'البند المالي';
    headerRow.cells[1].value = 'المبلغ بالدينار العراقي';
    headerRow.cells[2].value = 'النوع / الأثر';

    headerRow.style.backgroundBrush = PdfSolidBrush(brandTeal);
    for (int c = 0; c < 3; c++) {
      headerRow.cells[c].style.font = boldBodyFont;
      headerRow.cells[c].style.textBrush = PdfSolidBrush(PdfColor(255, 255, 255));
      headerRow.cells[c].style.stringFormat = rtlCenterFormat;
    }

    // إضافة صفوف الملخص
    _addSummaryGridRow(summaryGrid, 'الراتب الأساسي الاسمي', AppConstants.formatMoney(basicSalary), 'استحقاق ثابت (+)', boldBodyFont, rtlRightFormat, rtlCenterFormat);
    if (allowances > 0) {
      _addSummaryGridRow(summaryGrid, 'إجمالي المكافآت والبدلات', '+ ${AppConstants.formatMoney(allowances)}', 'إضافة تشجيعية (+)', boldBodyFont, rtlRightFormat, rtlCenterFormat, textColor: successGreen);
    }
    if (deductions > 0) {
      _addSummaryGridRow(summaryGrid, 'إجمالي خصومات الغياب والدوام والجزاءات', '- ${AppConstants.formatMoney(deductions)}', 'استقطاع (-)', boldBodyFont, rtlRightFormat, rtlCenterFormat, textColor: dangerRed);
    }
    if (loansDeduction > 0) {
      _addSummaryGridRow(summaryGrid, 'استقطاع قسط السلفة المالية', '- ${AppConstants.formatMoney(loansDeduction)}', 'سداد سلفة (-)', boldBodyFont, rtlRightFormat, rtlCenterFormat, textColor: dangerRed);
    }

    // صف الصافي الإجمالي
    final PdfGridRow netRow = summaryGrid.rows.add();
    netRow.cells[0].value = 'صافي الراتب المستحق للصرف:';
    netRow.cells[1].value = AppConstants.formatMoney(netSalary);
    netRow.cells[2].value = 'المبلغ النهائي الصافي 💸';

    netRow.style.backgroundBrush = PdfSolidBrush(lightBg);
    netRow.cells[0].style.font = boldBodyFont;
    netRow.cells[0].style.stringFormat = rtlRightFormat;
    netRow.cells[0].style.textBrush = PdfSolidBrush(brandDark);

    netRow.cells[1].style.font = subtitleFont;
    netRow.cells[1].style.stringFormat = rtlCenterFormat;
    netRow.cells[1].style.textBrush = PdfSolidBrush(brandTeal);

    netRow.cells[2].style.font = boldBodyFont;
    netRow.cells[2].style.stringFormat = rtlCenterFormat;
    netRow.cells[2].style.textBrush = PdfSolidBrush(successGreen);

    final PdfLayoutResult summaryResult = summaryGrid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, currentY, pageSize.width, 0),
    )!;

    currentY = summaryResult.bounds.bottom + 18;

    // -------------------------------------------------------------
    // جدول بنود المكافآت والخصومات المسجلة وملاحظاتها
    // -------------------------------------------------------------
    final bool hasBonuses = bonusesList != null && bonusesList.isNotEmpty;
    final bool hasDeductions = deductionsList != null && deductionsList.isNotEmpty;

    if (hasBonuses || hasDeductions) {
      page.graphics.drawString(
        '2. تفاصيل وبنود المكافآت والخصومات الإضافية المسجلة:',
        subtitleFont,
        brush: PdfSolidBrush(brandDark),
        bounds: Rect.fromLTWH(0, currentY, pageSize.width, 20),
        format: rtlRightFormat,
      );

      currentY += 22;

      final PdfGrid detailsGrid = PdfGrid();
      detailsGrid.columns.add(count: 4);
      detailsGrid.columns[0].width = pageSize.width * 0.15;
      detailsGrid.columns[1].width = pageSize.width * 0.20;
      detailsGrid.columns[2].width = pageSize.width * 0.45;
      detailsGrid.columns[3].width = pageSize.width * 0.20;

      detailsGrid.headers.add(1);
      final PdfGridRow dHeader = detailsGrid.headers[0];
      dHeader.cells[0].value = 'النوع';
      dHeader.cells[1].value = 'المبلغ';
      dHeader.cells[2].value = 'السبب / الملاحظات';
      dHeader.cells[3].value = 'تاريخ الإضافة';

      dHeader.style.backgroundBrush = PdfSolidBrush(brandDark);
      for (int c = 0; c < 4; c++) {
        dHeader.cells[c].style.font = boldBodyFont;
        dHeader.cells[c].style.textBrush = PdfSolidBrush(PdfColor(255, 255, 255));
        dHeader.cells[c].style.stringFormat = rtlCenterFormat;
      }

      if (hasBonuses) {
        for (final b in bonusesList) {
          final amt = (b['amount'] as num?)?.toDouble() ?? 0.0;
          final reason = b['reason']?.toString() ?? 'مكافأة تشجيعية';
          final date = b['issue_date']?.toString() ?? '-';
          _addDetailGridRow(detailsGrid, 'مكافأة (+)', '+ ${AppConstants.formatMoney(amt)}', reason, date, bodyFont, rtlCenterFormat, rtlRightFormat, textColor: successGreen);
        }
      }

      if (hasDeductions) {
        for (final d in deductionsList) {
          final amt = (d['amount'] as num?)?.toDouble() ?? 0.0;
          final reason = d['reason']?.toString() ?? 'خصم إداري';
          final date = d['issue_date']?.toString() ?? '-';
          _addDetailGridRow(detailsGrid, 'خصم (-)', '- ${AppConstants.formatMoney(amt)}', reason, date, bodyFont, rtlCenterFormat, rtlRightFormat, textColor: dangerRed);
        }
      }

      final PdfLayoutResult detailsResult = detailsGrid.draw(
        page: page,
        bounds: Rect.fromLTWH(0, currentY, pageSize.width, 0),
      )!;

      currentY = detailsResult.bounds.bottom + 20;
    }

    // -------------------------------------------------------------
    // صندوق التوقيعات الرسمية
    // -------------------------------------------------------------
    if (currentY + 70 > pageSize.height) {
      currentY = pageSize.height - 70;
    }

    final PdfGrid signGrid = PdfGrid();
    signGrid.columns.add(count: 3);
    for (int i = 0; i < 3; i++) {
      signGrid.columns[i].width = pageSize.width / 3;
    }

    final PdfGridRow signRow = signGrid.rows.add();
    signRow.cells[0].value = 'توقيع الموظف المستلم:\n\n___________________';
    signRow.cells[1].value = 'توقيع المحاسب المالي:\n\n___________________';
    signRow.cells[2].value = 'اعتماد الموارد البشرية:\n\n___________________';

    for (int i = 0; i < 3; i++) {
      signRow.cells[i].style.font = boldBodyFont;
      signRow.cells[i].style.stringFormat = rtlCenterFormat;
      signRow.cells[i].style.textBrush = PdfSolidBrush(textSlate);
    }

    signGrid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, currentY, pageSize.width, 0),
    );

    final List<int> bytes = document.saveSync();
    document.dispose();
    return bytes;
  }

  static void _addSummaryGridRow(
    PdfGrid grid,
    String label,
    String amount,
    String type,
    PdfFont font,
    PdfStringFormat rightFmt,
    PdfStringFormat centerFmt, {
    PdfColor? textColor,
  }) {
    final PdfGridRow row = grid.rows.add();
    row.cells[0].value = label;
    row.cells[1].value = amount;
    row.cells[2].value = type;

    row.cells[0].style.font = font;
    row.cells[0].style.stringFormat = rightFmt;

    row.cells[1].style.font = font;
    row.cells[1].style.stringFormat = centerFmt;
    if (textColor != null) {
      row.cells[1].style.textBrush = PdfSolidBrush(textColor);
    }

    row.cells[2].style.font = font;
    row.cells[2].style.stringFormat = centerFmt;
  }

  static void _addDetailGridRow(
    PdfGrid grid,
    String type,
    String amount,
    String reason,
    String date,
    PdfFont font,
    PdfStringFormat centerFmt,
    PdfStringFormat rightFmt, {
    PdfColor? textColor,
  }) {
    final PdfGridRow row = grid.rows.add();
    row.cells[0].value = type;
    row.cells[1].value = amount;
    row.cells[2].value = reason;
    row.cells[3].value = date;

    row.cells[0].style.font = font;
    row.cells[0].style.stringFormat = centerFmt;
    if (textColor != null) {
      row.cells[0].style.textBrush = PdfSolidBrush(textColor);
      row.cells[1].style.textBrush = PdfSolidBrush(textColor);
    }

    row.cells[1].style.font = font;
    row.cells[1].style.stringFormat = centerFmt;

    row.cells[2].style.font = font;
    row.cells[2].style.stringFormat = rightFmt;

    row.cells[3].style.font = font;
    row.cells[3].style.stringFormat = centerFmt;
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
      debugPrint('تعذر فتح ملف PDF عبر OpenFilex: $e');
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
      debugPrint('تعذر مشاركة ملف PDF: $e');
    }
  }
}
