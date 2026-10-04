// تقرير الحضور بصيغة Excel: ورقة "يوم بيوم" وورقة "ملخص الموظفين" (بايتات بدون حفظ — قابل للاختبار).
// الواجهة العامة: ExcelExportService.generateAttendanceReportExcel / buildAttendanceReportBytes.

import 'package:flutter/material.dart' show DateUtils;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../logic/attendance_report.dart';

/// محتوى ملف تقرير الحضور (بدون حفظ) — قابل للاختبار.
List<int> buildAttendanceReportExcelBytes({
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
