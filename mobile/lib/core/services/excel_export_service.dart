// =========================================================================
// نظام HR Pro v6.0 - خدمة توليد وتصدير ملفات Excel الاحترافية
// =========================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import '../constants/constants.dart';
import '../logic/attendance_report.dart';
import '../models/loan_model.dart';
import 'share_helper.dart';

class ExcelExportService {
  /// توليد كشف حساب سلفة تفصيلي واحترافي بصيغة Excel (.xlsx)
  static Future<String> generateLoanStatementExcel(LoanRecord record) async {
    final loan = record.loan;
    final installments = loan.installments;
    // 1. إنشاء مصنف عمل جديد
    final xlsio.Workbook workbook = xlsio.Workbook();
    final xlsio.Worksheet sheet = workbook.worksheets[0];
    sheet.name = 'كشف السلفة';
    sheet.isRightToLeft = true; // دعم اللغة العربية واتجاه اليمين إلى اليسار
    sheet.enableSheetCalculations();

    // استخراج بيانات الموظف والسلفة
    final String employeeName = loan.employeeName ?? 'موظف غير معروف';
    final String branchName = record.branchName;
    final String deptName = record.departmentName;
    final double totalAmount = loan.amount;
    final int monthsCount = loan.installmentCount;
    final double monthlyAmt = loan.installmentAmount;
    final double remainingAmt = loan.remainingAmount;
    final double paidAmt = totalAmount - remainingAmt > 0 ? (totalAmount - remainingAmt) : 0.0;
    final String status = loan.status;
    final String loanDate = DateFormat('yyyy-MM-dd').format(loan.createdAt ?? DateTime.now());
    final String notes = record.notes ?? 'لا توجد ملاحظات إضافية';

    // الألوان المستوحاة من هوية HR Pro
    const String headerDarkBg = '#0F172A'; // Slate 900
    const String tealPrimary = '#0D9488'; // Teal 600
    const String lightTealBg = '#F0FDFA'; // Teal 50
    const String softGrayBg = '#F8FAFC'; // Slate 50
    const String borderGray = '#CBD5E1'; // Slate 300
    const String successGreenBg = '#DCFCE7'; // Green 100
    const String successGreenText = '#166534'; // Green 800
    const String pendingYellowBg = '#FEF9C3'; // Yellow 100
    const String pendingYellowText = '#854D0E'; // Yellow 800

    // ضبط عرض الأعمدة
    sheet.setColumnWidthInPixels(1, 45);  // A: التسلسل
    sheet.setColumnWidthInPixels(2, 190); // B: شهر الاستحقاق
    sheet.setColumnWidthInPixels(3, 140); // C: مبلغ القسط
    sheet.setColumnWidthInPixels(4, 130); // D: حالة السداد
    sheet.setColumnWidthInPixels(5, 140); // E: تاريخ التسديد الفعلي
    sheet.setColumnWidthInPixels(6, 220); // F: الملاحظات

    // ----------------------------------------------------
    // 1. الترويسة الرئيسية للتقرير (Title Header)
    // ----------------------------------------------------
    sheet.getRangeByName('A1:F1').merge();
    final xlsio.Range titleRange = sheet.getRangeByName('A1');
    titleRange.setText('نظام HR Pro لإدارة الموارد البشرية - كشف حساب سلفة تفصيلي');
    titleRange.cellStyle.fontSize = 15;
    titleRange.cellStyle.bold = true;
    titleRange.cellStyle.fontColor = '#FFFFFF';
    titleRange.cellStyle.backColor = headerDarkBg;
    titleRange.cellStyle.hAlign = xlsio.HAlignType.center;
    titleRange.cellStyle.vAlign = xlsio.VAlignType.center;
    sheet.setRowHeightInPixels(1, 42);

    sheet.getRangeByName('A2:F2').merge();
    final xlsio.Range subTitleRange = sheet.getRangeByName('A2');
    final String exportDateStr = DateFormat('yyyy/MM/dd - hh:mm a').format(DateTime.now());
    subTitleRange.setText('تاريخ استخراج الكشف: $exportDateStr | حالة السلفة: ${status == "approved" ? "سلفة معتمدة ونشطة ✅" : status == "completed" ? "سلفة مسددة بالكامل 🏁" : status == "rejected" ? "سلفة مرفوضة ❌" : "سلفة معلقة ⏳"}');
    subTitleRange.cellStyle.fontSize = 10;
    subTitleRange.cellStyle.fontColor = '#FFFFFF';
    subTitleRange.cellStyle.backColor = tealPrimary;
    subTitleRange.cellStyle.hAlign = xlsio.HAlignType.center;
    subTitleRange.cellStyle.vAlign = xlsio.VAlignType.center;
    sheet.setRowHeightInPixels(2, 24);

    // ----------------------------------------------------
    // 2. بطاقة معلومات الموظف والسلفة (Employee & Loan Info)
    // ----------------------------------------------------
    sheet.getRangeByName('A4:F4').merge();
    final xlsio.Range infoHeader = sheet.getRangeByName('A4');
    infoHeader.setText('📌 أولاً: بيانات الموظف والسلفة');
    infoHeader.cellStyle.bold = true;
    infoHeader.cellStyle.fontSize = 11;
    infoHeader.cellStyle.fontColor = '#0F172A';
    infoHeader.cellStyle.backColor = lightTealBg;
    infoHeader.cellStyle.vAlign = xlsio.VAlignType.center;

    // الصف الأول من البيانات
    sheet.getRangeByName('A5').setText('اسم الموظف:');
    sheet.getRangeByName('A5').cellStyle.bold = true;
    sheet.getRangeByName('B5').setText(employeeName);
    
    sheet.getRangeByName('C5').setText('الفرع / القسم:');
    sheet.getRangeByName('C5').cellStyle.bold = true;
    sheet.getRangeByName('D5').setText('$branchName / $deptName');

    sheet.getRangeByName('E5').setText('تاريخ تقديم السلفة:');
    sheet.getRangeByName('E5').cellStyle.bold = true;
    sheet.getRangeByName('F5').setText(loanDate);

    // الصف الثاني من البيانات
    sheet.getRangeByName('A6').setText('المبلغ الكلي:');
    sheet.getRangeByName('A6').cellStyle.bold = true;
    sheet.getRangeByName('B6').setText(AppConstants.formatMoney(totalAmount));

    sheet.getRangeByName('C6').setText('مدة السداد:');
    sheet.getRangeByName('C6').cellStyle.bold = true;
    sheet.getRangeByName('D6').setText('$monthsCount أشهر متتالية');

    sheet.getRangeByName('E6').setText('القسط الشهري:');
    sheet.getRangeByName('E6').cellStyle.bold = true;
    sheet.getRangeByName('F6').setText(AppConstants.formatMoney(monthlyAmt));

    // صف الملاحظات
    sheet.getRangeByName('A7').setText('سبب وملاحظات:');
    sheet.getRangeByName('A7').cellStyle.bold = true;
    sheet.getRangeByName('B7:F7').merge();
    sheet.getRangeByName('B7').setText(notes);

    // تلوين وإطار بطاقة البيانات
    final xlsio.Range infoBox = sheet.getRangeByName('A5:F7');
    infoBox.cellStyle.backColor = softGrayBg;
    infoBox.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    infoBox.cellStyle.borders.all.color = borderGray;

    // ----------------------------------------------------
    // 3. ملخص الموقف المالي (Financial Summary KPI Boxes)
    // ----------------------------------------------------
    sheet.getRangeByName('A9:B9').merge();
    final kpi1 = sheet.getRangeByName('A9');
    kpi1.setText('💰 إجمالي السلفة: ${AppConstants.formatMoney(totalAmount)}');
    kpi1.cellStyle.bold = true;
    kpi1.cellStyle.fontSize = 10;
    kpi1.cellStyle.hAlign = xlsio.HAlignType.center;
    kpi1.cellStyle.vAlign = xlsio.VAlignType.center;
    kpi1.cellStyle.backColor = '#E2E8F0';
    kpi1.cellStyle.borders.all.lineStyle = xlsio.LineStyle.medium;
    kpi1.cellStyle.borders.all.color = '#94A3B8';

    sheet.getRangeByName('C9:D9').merge();
    final kpi2 = sheet.getRangeByName('C9');
    kpi2.setText('✅ المسدد حتى الآن: ${AppConstants.formatMoney(paidAmt)}');
    kpi2.cellStyle.bold = true;
    kpi2.cellStyle.fontSize = 10;
    kpi2.cellStyle.fontColor = successGreenText;
    kpi2.cellStyle.hAlign = xlsio.HAlignType.center;
    kpi2.cellStyle.vAlign = xlsio.VAlignType.center;
    kpi2.cellStyle.backColor = successGreenBg;
    kpi2.cellStyle.borders.all.lineStyle = xlsio.LineStyle.medium;
    kpi2.cellStyle.borders.all.color = '#86EFAC';

    sheet.getRangeByName('E9:F9').merge();
    final kpi3 = sheet.getRangeByName('E9');
    kpi3.setText('⏳ المتبقي بذمة الموظف: ${AppConstants.formatMoney(remainingAmt)}');
    kpi3.cellStyle.bold = true;
    kpi3.cellStyle.fontSize = 10;
    kpi3.cellStyle.fontColor = '#991B1B'; // Red 800
    kpi3.cellStyle.hAlign = xlsio.HAlignType.center;
    kpi3.cellStyle.vAlign = xlsio.VAlignType.center;
    kpi3.cellStyle.backColor = '#FEE2E2'; // Red 100
    kpi3.cellStyle.borders.all.lineStyle = xlsio.LineStyle.medium;
    kpi3.cellStyle.borders.all.color = '#FCA5A5';
    sheet.setRowHeightInPixels(9, 32);

    // ----------------------------------------------------
    // 4. جدول الأقساط والتسديدات (Installments Table)
    // ----------------------------------------------------
    sheet.getRangeByName('A11:F11').merge();
    final xlsio.Range tableHeaderTitle = sheet.getRangeByName('A11');
    tableHeaderTitle.setText('📊 ثانياً: جدول الأقساط وحركة التسديدات الشهرية');
    tableHeaderTitle.cellStyle.bold = true;
    tableHeaderTitle.cellStyle.fontSize = 11;
    tableHeaderTitle.cellStyle.fontColor = '#0F172A';
    tableHeaderTitle.cellStyle.backColor = lightTealBg;
    tableHeaderTitle.cellStyle.vAlign = xlsio.VAlignType.center;

    // عناوين أعمدة الجدول
    final List<String> colHeaders = ['ت', 'شهر القسط', 'مبلغ القسط', 'حالة السداد', 'تاريخ التسديد', 'ملاحظات وتفاصيل'];
    for (int c = 0; c < colHeaders.length; c++) {
      final cell = sheet.getRangeByIndex(12, c + 1);
      cell.setText(colHeaders[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.fontSize = 10;
      cell.cellStyle.fontColor = '#FFFFFF';
      cell.cellStyle.backColor = '#334155'; // Slate 700
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#000000';
    }
    sheet.setRowHeightInPixels(12, 28);

    // ملء بيانات الأقساط
    int startRow = 13;
    int seq = 1;

    for (final inst in installments) {
      final double instAmt = inst.amount;
      final bool isPaid = inst.isPaid;
      final String dueDate = DateFormat('yyyy-MM-dd').format(inst.dueDate);
      final String paidDate = inst.paidAt != null
          ? DateFormat('yyyy-MM-dd').format(inst.paidAt!)
          : isPaid ? 'تم الاستقطاع من الراتب' : '-';
      final String instNotes = inst.paymentNote ??
          (isPaid ? (inst.isCash ? 'سداد نقدي' : 'تم السداد بنجاح') : 'قسط مستحق السداد');

      // ت: رقم القسط
      final cellSeq = sheet.getRangeByIndex(startRow, 1);
      cellSeq.setText(seq.toString());
      cellSeq.cellStyle.hAlign = xlsio.HAlignType.center;

      // تاريخ الاستحقاق
      final cellDue = sheet.getRangeByIndex(startRow, 2);
      cellDue.setText('شهر ${inst.dueDate.month} سنة ${inst.dueDate.year} · $dueDate');
      cellDue.cellStyle.hAlign = xlsio.HAlignType.center;

      // مبلغ القسط
      final cellAmt = sheet.getRangeByIndex(startRow, 3);
      cellAmt.setText(AppConstants.formatMoney(instAmt));
      cellAmt.cellStyle.hAlign = xlsio.HAlignType.center;
      cellAmt.cellStyle.bold = true;

      // حالة السداد
      final cellStatus = sheet.getRangeByIndex(startRow, 4);
      cellStatus.setText(isPaid ? 'مسدد ✅' : 'متبقي ⏳');
      cellStatus.cellStyle.bold = true;
      cellStatus.cellStyle.hAlign = xlsio.HAlignType.center;
      cellStatus.cellStyle.backColor = isPaid ? successGreenBg : pendingYellowBg;
      cellStatus.cellStyle.fontColor = isPaid ? successGreenText : pendingYellowText;

      // تاريخ التسديد
      final cellPaidDate = sheet.getRangeByIndex(startRow, 5);
      cellPaidDate.setText(paidDate);
      cellPaidDate.cellStyle.hAlign = xlsio.HAlignType.center;

      // ملاحظات القسط
      final cellNote = sheet.getRangeByIndex(startRow, 6);
      cellNote.setText(instNotes);

      // تنسيق حدود وخلفية الصف
      final xlsio.Range rowRange = sheet.getRangeByName('A$startRow:F$startRow');
      rowRange.cellStyle.vAlign = xlsio.VAlignType.center;
      rowRange.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      rowRange.cellStyle.borders.all.color = borderGray;
      sheet.setRowHeightInPixels(startRow, 24);

      startRow++;
      seq++;
    }

    // صف المجموع الإجمالي أسفل الجدول
    final xlsio.Range totalLabel = sheet.getRangeByName('A$startRow:B$startRow');
    sheet.getRangeByName('A$startRow:B$startRow').merge();
    totalLabel.setText('الإجمالي الكلي:');
    totalLabel.cellStyle.bold = true;
    totalLabel.cellStyle.hAlign = xlsio.HAlignType.center;
    totalLabel.cellStyle.backColor = '#E2E8F0';

    final cellTotalAmt = sheet.getRangeByIndex(startRow, 3);
    cellTotalAmt.setText(AppConstants.formatMoney(totalAmount));
    cellTotalAmt.cellStyle.bold = true;
    cellTotalAmt.cellStyle.hAlign = xlsio.HAlignType.center;
    cellTotalAmt.cellStyle.backColor = '#E2E8F0';

    final xlsio.Range totalRest = sheet.getRangeByName('D$startRow:F$startRow');
    sheet.getRangeByName('D$startRow:F$startRow').merge();
    totalRest.setText('المسدد: ${AppConstants.formatMoney(paidAmt)} | المتبقي: ${AppConstants.formatMoney(remainingAmt)}');
    totalRest.cellStyle.bold = true;
    totalRest.cellStyle.fontSize = 10;
    totalRest.cellStyle.hAlign = xlsio.HAlignType.center;
    totalRest.cellStyle.backColor = '#E2E8F0';

    final xlsio.Range summaryRow = sheet.getRangeByName('A$startRow:F$startRow');
    summaryRow.cellStyle.borders.all.lineStyle = xlsio.LineStyle.medium;
    summaryRow.cellStyle.borders.all.color = '#475569';
    sheet.setRowHeightInPixels(startRow, 28);

    // ----------------------------------------------------
    // 5. التوقيعات والاعتماد الرسمي (Signatures)
    // ----------------------------------------------------
    int sigRow = startRow + 3;
    sheet.getRangeByName('A$sigRow:B$sigRow').merge();
    sheet.getRangeByName('A$sigRow').setText('توقيع مسؤول الموارد البشرية');
    sheet.getRangeByName('A$sigRow').cellStyle.bold = true;
    sheet.getRangeByName('A$sigRow').cellStyle.hAlign = xlsio.HAlignType.center;

    sheet.getRangeByName('C$sigRow:D$sigRow').merge();
    sheet.getRangeByName('C$sigRow').setText('توقيع المحاسب المالي');
    sheet.getRangeByName('C$sigRow').cellStyle.bold = true;
    sheet.getRangeByName('C$sigRow').cellStyle.hAlign = xlsio.HAlignType.center;

    sheet.getRangeByName('E$sigRow:F$sigRow').merge();
    sheet.getRangeByName('E$sigRow').setText('توقيع واعتراف الموظف المستلف');
    sheet.getRangeByName('E$sigRow').cellStyle.bold = true;
    sheet.getRangeByName('E$sigRow').cellStyle.hAlign = xlsio.HAlignType.center;

    int sigLineRow = sigRow + 2;
    sheet.getRangeByName('A$sigLineRow:B$sigLineRow').merge();
    sheet.getRangeByName('A$sigLineRow').setText('....................................');
    sheet.getRangeByName('A$sigLineRow').cellStyle.hAlign = xlsio.HAlignType.center;

    sheet.getRangeByName('C$sigLineRow:D$sigLineRow').merge();
    sheet.getRangeByName('C$sigLineRow').setText('....................................');
    sheet.getRangeByName('C$sigLineRow').cellStyle.hAlign = xlsio.HAlignType.center;

    sheet.getRangeByName('E$sigLineRow:F$sigLineRow').merge();
    sheet.getRangeByName('E$sigLineRow').setText('....................................');
    sheet.getRangeByName('E$sigLineRow').cellStyle.hAlign = xlsio.HAlignType.center;

    // ----------------------------------------------------
    // 6. حفظ الملف في الذاكرة وكتابته إلى مسار التخزين
    // ----------------------------------------------------
    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    // مسار الحفظ في مجلد المستندات / التحميلات
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String cleanEmpName = employeeName.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), '_').trim();
    final String fileName = 'سلفة_${cleanEmpName}_${DateFormat("yyyyMMdd_HHmm").format(DateTime.now())}.xlsx';
    final String filePath = '${appDir.path}/$fileName';

    final File file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    // حفظ نسخة أيضاً في مجلد التنزيلات العام لجهاز الأندرويد (Downloads)
    try {
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (downloadDir.existsSync()) {
          final publicFile = File('${downloadDir.path}/$fileName');
          await publicFile.writeAsBytes(bytes, flush: true);
          debugPrint('✅ تم حفظ نسخة في مجلد التنزيلات: ${publicFile.path}');
        }
      }
    } catch (_) {}

    debugPrint('✅ تم إنشاء ملف Excel بنجاح في المسار: $filePath');
    return filePath;
  }

  /// تقرير حضور يومي: ورقة "يوم بيوم" (سطر لكل موظف في كل يوم) وورقة "ملخص الموظفين".
  static Future<String> generateAttendanceReportExcel({
    required List<ReportRow> rows,
    required DateTime from,
    required DateTime to,
    String scopeLabel = 'كل الفروع',
  }) async {
    final bytes = buildAttendanceReportBytes(rows: rows, from: from, to: to, scopeLabel: scopeLabel);
    final fileName = 'تقرير_الحضور_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.xlsx';
    return _saveExcel(bytes, fileName);
  }

  /// محتوى ملف تقرير الحضور (بدون حفظ) — قابل للاختبار.
  static List<int> buildAttendanceReportBytes({
    required List<ReportRow> rows,
    required DateTime from,
    required DateTime to,
    String scopeLabel = 'كل الفروع',
  }) {
    final workbook = xlsio.Workbook(2);
    final daily = workbook.worksheets[0]..name = 'يوم بيوم';
    final summary = workbook.worksheets[1]..name = 'ملخص الموظفين';
    final dayFmt = DateFormat('yyyy-MM-dd');
    final timeFmt = DateFormat('hh:mm a');
    const weekdays = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

    const statusColors = {
      ReportStatus.present: ('#DCFCE7', '#166534'),
      ReportStatus.late: ('#FEF9C3', '#854D0E'),
      ReportStatus.earlyLeave: ('#FFEDD5', '#9A3412'),
      ReportStatus.absent: ('#FEE2E2', '#991B1B'),
      ReportStatus.leave: ('#E0F2FE', '#075985'),
      ReportStatus.dayOff: ('#F1F5F9', '#475569'),
    };

    void title(xlsio.Worksheet sheet, String lastCol, String text, String sub) {
      sheet.isRightToLeft = true;
      sheet.getRangeByName('A1:${lastCol}1').merge();
      final t = sheet.getRangeByName('A1')..setText(text);
      t.cellStyle
        ..fontSize = 14
        ..bold = true
        ..fontColor = '#FFFFFF'
        ..backColor = '#0F172A'
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center;
      sheet.setRowHeightInPixels(1, 38);
      sheet.getRangeByName('A2:${lastCol}2').merge();
      final s = sheet.getRangeByName('A2')..setText(sub);
      s.cellStyle
        ..fontSize = 10
        ..fontColor = '#FFFFFF'
        ..backColor = '#0D9488'
        ..hAlign = xlsio.HAlignType.center;
      sheet.setRowHeightInPixels(2, 22);
    }

    void header(xlsio.Worksheet sheet, int row, List<String> cols) {
      for (var c = 0; c < cols.length; c++) {
        final cell = sheet.getRangeByIndex(row, c + 1)..setText(cols[c]);
        cell.cellStyle
          ..bold = true
          ..fontSize = 10
          ..fontColor = '#FFFFFF'
          ..backColor = '#334155'
          ..hAlign = xlsio.HAlignType.center
          ..vAlign = xlsio.VAlignType.center
          ..wrapText = true;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      }
      sheet.setRowHeightInPixels(row, 30);
    }

    final period = '${dayFmt.format(from)} ← ${dayFmt.format(to)}';
    final sub = 'الفترة: $period | $scopeLabel | استُخرج: ${DateFormat('yyyy/MM/dd hh:mm a').format(DateTime.now())}';

    // ---------------- ورقة يوم بيوم ----------------
    const dailyCols = ['ت', 'التاريخ', 'اليوم', 'الموظف', 'الرمز', 'الفرع', 'الحالة', 'الحضور', 'الانصراف', 'تأخير (دقيقة)', 'خروج مبكر (دقيقة)', 'الإجازة / ملاحظات'];
    const widths = [40, 90, 70, 170, 80, 120, 80, 75, 75, 80, 90, 240];
    for (var i = 0; i < widths.length; i++) {
      daily.setColumnWidthInPixels(i + 1, widths[i]);
    }
    title(daily, 'L', 'تقرير الحضور والغياب اليومي — HR Pro', sub);
    header(daily, 4, dailyCols);

    final sorted = [...rows]..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.employee.name.compareTo(b.employee.name);
      });
    var r = 5;
    DateTime? lastDay;
    for (var i = 0; i < sorted.length; i++) {
      final row = sorted[i];
      final att = row.attendance;
      final values = <Object>[
        i + 1,
        dayFmt.format(row.date),
        weekdays[row.date.weekday - 1],
        row.employee.name,
        row.employee.code,
        row.employee.branchName,
        row.status.arabic,
        att?.checkIn == null ? '-' : timeFmt.format(att!.checkIn!),
        att?.checkOut == null ? '-' : timeFmt.format(att!.checkOut!),
        row.lateMinutes,
        row.earlyMinutes,
        row.note.isEmpty ? '-' : row.note,
      ];
      for (var c = 0; c < values.length; c++) {
        final cell = daily.getRangeByIndex(r, c + 1);
        final v = values[c];
        if (v is int) {
          cell.setNumber(v.toDouble());
        } else {
          cell.setText(v.toString());
        }
        cell.cellStyle
          ..fontSize = 10
          ..vAlign = xlsio.VAlignType.center
          ..hAlign = c == 3 || c == 11 ? xlsio.HAlignType.right : xlsio.HAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
      }
      final (bg, fg) = statusColors[row.status]!;
      daily.getRangeByIndex(r, 7).cellStyle
        ..backColor = bg
        ..fontColor = fg
        ..bold = true;
      // خط فاصل أعرض بين الأيام
      if (lastDay != null && !DateUtils.isSameDay(lastDay, row.date)) {
        daily.getRangeByName('A$r:L$r').cellStyle.borders.top
          ..lineStyle = xlsio.LineStyle.medium
          ..color = '#0D9488';
      }
      lastDay = row.date;
      daily.setRowHeightInPixels(r, 22);
      r++;
    }
    daily.autoFilters.filterRange = daily.getRangeByName('A4:L${r - 1 < 4 ? 4 : r - 1}');
    daily.getRangeByName('A5').freezePanes();

    // ---------------- ورقة الملخص ----------------
    const sumCols = ['ت', 'الموظف', 'الرمز', 'الفرع', 'أيام الحضور', 'منها تأخير', 'منها خروج مبكر', 'غياب', 'إجازات', 'مجموع دقائق التأخير', 'نسبة الحضور'];
    const sumWidths = [40, 170, 80, 120, 80, 75, 90, 60, 60, 110, 80];
    for (var i = 0; i < sumWidths.length; i++) {
      summary.setColumnWidthInPixels(i + 1, sumWidths[i]);
    }
    title(summary, 'K', 'ملخص الحضور لكل موظف — HR Pro', sub);
    header(summary, 4, sumCols);
    final byEmp = <String, List<ReportRow>>{};
    for (final row in rows) {
      byEmp.putIfAbsent(row.employee.id, () => []).add(row);
    }
    final emps = byEmp.values.toList()..sort((a, b) => a.first.employee.name.compareTo(b.first.employee.name));
    var s = 5;
    for (var i = 0; i < emps.length; i++) {
      final list = emps[i];
      final t = reportTotals(list);
      final lateMins = list.fold<int>(0, (acc, x) => acc + x.lateMinutes);
      final values = <Object>[i + 1, list.first.employee.name, list.first.employee.code, list.first.employee.branchName,
        t.attended, t.late, t.earlyLeave, t.absent, t.leave, lateMins, '${t.rate}%'];
      for (var c = 0; c < values.length; c++) {
        final cell = summary.getRangeByIndex(s, c + 1);
        final v = values[c];
        if (v is int) {
          cell.setNumber(v.toDouble());
        } else {
          cell.setText(v.toString());
        }
        cell.cellStyle
          ..fontSize = 10
          ..hAlign = c == 1 ? xlsio.HAlignType.right : xlsio.HAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
      }
      if (t.absent > 0) {
        summary.getRangeByIndex(s, 8).cellStyle
          ..backColor = '#FEE2E2'
          ..fontColor = '#991B1B'
          ..bold = true;
      }
      summary.setRowHeightInPixels(s, 22);
      s++;
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();
    return bytes;
  }

  static Future<String> _saveExcel(List<int> bytes, String fileName) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    try {
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (downloadDir.existsSync()) {
          await File('${downloadDir.path}/$fileName').writeAsBytes(bytes, flush: true);
        }
      }
    } catch (_) {}
    return file.path;
  }

  /// فتح ملف Excel بواسطة تطبيق جداول البيانات المثبت على الجهاز (Excel أو Google Sheets)
  static Future<void> openExcelFile(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        await shareExcelFile(filePath);
      }
    } catch (e) {
      debugPrint('تعذر فتح ملف Excel عبر OpenFilex: $e');
      await shareExcelFile(filePath);
    }
  }

  /// مشاركة ملف Excel عبر واتساب أو تيليغرام أو التطبيقات
  static Future<void> shareExcelFile(String filePath, {String? text}) async {
    try {
      await ShareHelper.shareParams(ShareParams(
        files: [XFile(filePath)],
        text: text ?? 'كشف حساب سلفة الموظف - HR Pro Batra',
      ));
    } catch (e) {
      debugPrint('تعذر مشاركة ملف Excel: $e');
    }
  }
}
